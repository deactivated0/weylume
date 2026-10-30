//! Native NetworkManager snapshots and on-demand actions. No CLI or secret argv.
use crate::{bus::Bus, dbus::variant as v, util::*};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
const NM: &str = "org.freedesktop.NetworkManager";
const ROOT: &str = "/org/freedesktop/NetworkManager";
const SETTINGS: &str = "/org/freedesktop/NetworkManager/Settings";
const CONNECTION: &str = "org.freedesktop.NetworkManager.Settings.Connection";
const ACTIVE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const DEVICE: &str = "org.freedesktop.NetworkManager.Device";
const WIFI: &str = "org.freedesktop.NetworkManager.Device.Wireless";
fn items(v: &Value) -> impl Iterator<Item = &Value> {
    v.as_array().into_iter().flatten()
}
fn text<'a>(v: &'a Value, key: &str) -> &'a str {
    v[key].as_str().unwrap_or("")
}
fn ssid(v: &Value) -> String {
    let Some(arr) = v.as_array() else { return String::new() };
    let mut bytes = Vec::with_capacity(arr.len());
    for n in arr {
        if let Some(byte) = n.as_u64().and_then(|n| u8::try_from(n).ok()) {
            bytes.push(byte);
        }
    }
    String::from_utf8_lossy(&bytes).into_owned()
}
fn profiles(b: &Bus) -> Result<Vec<(String, Value)>> {
    let paths = b.call(
        NM,
        SETTINGS,
        "org.freedesktop.NetworkManager.Settings",
        "ListConnections",
        "",
        &[],
    )?;
    let mut profiles = Vec::new();
    for p in items(&paths[0]).filter_map(Value::as_str) {
        // A profile can be removed while the snapshot is in progress.
        if let Ok(mut reply) = b.call(NM, p, CONNECTION, "GetSettings", "", &[]) {
            profiles.push((p.into(), reply[0].take()));
        }
    }
    profiles.sort_by(|a, b| {
        text(&a.1["connection"], "id")
            .to_lowercase()
            .cmp(&text(&b.1["connection"], "id").to_lowercase())
    });
    Ok(profiles)
}
fn channel(freq: u64) -> u64 {
    match freq {
        2484 => 14,
        2412..=2472 => (freq - 2407) / 5,
        4910..=4980 => (freq - 4000) / 5,
        5000..=5895 => (freq - 5000) / 5,
        5935 => 2,
        5955..=7115 => (freq - 5950) / 5,
        _ => 0,
    }
}
fn security(ap: &Value) -> String {
    let wpa = ap["WpaFlags"].as_u64().unwrap_or(0);
    let rsn = ap["RsnFlags"].as_u64().unwrap_or(0);
    let mut names = String::with_capacity(16);
    if wpa != 0 {
        names.push_str("WPA1");
    }
    if rsn & 0x300 != 0 {
        if !names.is_empty() {
            names.push(' ');
        }
        names.push_str("WPA2");
    }
    if rsn & 0x400 != 0 {
        if !names.is_empty() {
            names.push(' ');
        }
        names.push_str("WPA3");
    }
    if rsn & 0x1800 != 0 {
        if !names.is_empty() {
            names.push(' ');
        }
        names.push_str("OWE");
    }
    if (wpa | rsn) & 0x200 != 0 {
        if !names.is_empty() {
            names.push(' ');
        }
        names.push_str("802.1X");
    }
    if names.is_empty() && ap["Flags"].as_u64().unwrap_or(0) & 1 != 0 {
        names.push_str("WEP");
    }
    names
}
pub fn data_with_bus(b: &Bus) -> Value {
    snapshot_with_bus(b).unwrap_or_else(|e| json!({"available":false,"error":e.to_string()}))
}
pub fn snapshot() -> Result<Value> {
    let b = Bus::system()?;
    snapshot_with_bus(&b)
}
pub fn snapshot_with_bus(b: &Bus) -> Result<Value> {
    let manager = b.properties(NM, ROOT, NM)?;
    let profiles = profiles(b)?;
    let mut saved = BTreeMap::new();
    let mut vpns = Vec::new();
    let mut active = Vec::new();
    for p in items(&manager["ActiveConnections"]).filter_map(Value::as_str) {
        if let Ok(a) = b.properties(NM, p, ACTIVE) {
            active.push(json!({"name":a["Id"],"uuid":a["Uuid"],"type":a["Type"],"state":match a["State"].as_u64(){Some(2)=>"activated",Some(1)=>"activating",Some(3)=>"deactivating",_=>"deactivated"},"path":p,"devices":a["Devices"],"ip4":a["Ip4Config"],"ip6":a["Ip6Config"]}));
        }
    }
    for (path, profile) in profiles {
        let c = &profile["connection"];
        let kind = text(c, "type");
        if kind == "802-11-wireless" {
            saved.insert(
                ssid(&profile["802-11-wireless"]["ssid"]),
                json!({"uuid":c["uuid"],"path":path}),
            );
        }
        if ["vpn", "wireguard", "tun"].contains(&kind) {
            let a = active.iter().find(|a| a["uuid"] == c["uuid"]);
            vpns.push(json!({"name":c["id"],"uuid":c["uuid"],"type":kind,"autoconnect":c["autoconnect"].as_bool().unwrap_or(true),"active":a.is_some_and(|v| v["state"] == "activated"),"state":a.map(|v| &v["state"]),"path":path}));
        }
    }
    let mut ethernet = json!({"connected":false,"name":"Wired Connection","device":""});
    let mut networks = Vec::new();
    let mut device_name = String::new();
    let mut ip4 = String::new();
    let mut ip6 = String::new();
    for path in items(&manager["Devices"]).filter_map(Value::as_str) {
        let Ok(d) = b.properties(NM, path, DEVICE) else {
            continue;
        };
        let name = text(&d, "Interface");
        let connected = d["State"] == 100;
        for a in &mut active {
            if items(&a["devices"]).any(|v| v == path) {
                a["device"] = json!(name);
            }
        }
        if connected && (device_name.is_empty() || d["DeviceType"] == 1) {
            device_name = name.into();
            ip4 = text(&d, "Ip4Config").into();
            ip6 = text(&d, "Ip6Config").into();
        }
        if d["DeviceType"] == 1 && connected {
            let a = active
                .iter()
                .find(|a| text(a, "path") == text(&d, "ActiveConnection"));
            ethernet = json!({"connected":true,"name":a.map_or("Wired Connection", |a| text(a,"name")),"device":name});
        }
        if d["DeviceType"] != 2 {
            continue;
        }
        let Ok(w) = b.properties(NM, path, WIFI) else {
            continue;
        };
        for ap_path in items(&w["AccessPoints"]).filter_map(Value::as_str) {
            let Ok(ap) = b.properties(NM, ap_path, "org.freedesktop.NetworkManager.AccessPoint")
            else {
                continue;
            };
            let name = ssid(&ap["Ssid"]);
            if name.is_empty() {
                continue;
            }
            let sec = security(&ap);
            let in_use = w["ActiveAccessPoint"] == ap_path;
            let freq = ap["Frequency"].as_u64().unwrap_or(0);
            networks.push(json!({"inUse":in_use,"ssid":name,"signal":ap["Strength"],"security":sec,"locked":!sec.is_empty()&&!sec.contains("OWE"),"enterprise":sec.contains("802.1X"),"saved":saved.contains_key(&name)||in_use,"channel":channel(freq).to_string(),"frequency":format!("{freq} MHz"),"rate":format!("{} Mbit/s",ap["MaxBitrate"].as_u64().unwrap_or(0)/1000),"bssid":ap["HwAddress"],"path":ap_path,"devicePath":path,"profile":saved.get(&name)}));
        }
    }
    networks.sort_by(|a, b| {
        b["inUse"]
            .as_bool()
            .cmp(&a["inUse"].as_bool())
            .then(b["signal"].as_u64().cmp(&a["signal"].as_u64()))
    });
    let mut seen = HashSet::new();
    networks.retain(|n| seen.insert(text(n, "ssid").to_string()));
    for (name, profile) in saved {
        if !seen.contains(&name) {
            networks.push(json!({"inUse":false,"ssid":name,"signal":0,"security":"Saved Profile","locked":true,"saved":true,"channel":"","frequency":"","rate":"","bssid":"","profile":profile}));
        }
    }
    let (mut addresses, mut dns) = (Vec::new(), Vec::new());
    let mut gateway = String::new();
    for (path, interface) in [
        (&ip4, "org.freedesktop.NetworkManager.IP4Config"),
        (&ip6, "org.freedesktop.NetworkManager.IP6Config"),
    ] {
        if path.is_empty() || path == "/" {
            continue;
        }
        if let Ok(ip) = b.properties(NM, path, interface) {
            for a in items(&ip["AddressData"]) {
                addresses.push(format!("{}/{}", text(a, "address"), a["prefix"]));
            }
            for a in items(&ip["NameserverData"]) {
                if let Some(s) = a["address"].as_str() {
                    dns.push(s.to_string());
                }
            }
            if gateway.is_empty() {
                gateway = text(&ip, "Gateway").into();
            }
        }
    }
    let active_vpn = active
        .iter()
        .find(|a| vpns.iter().any(|v| v["uuid"] == a["uuid"]) && a["state"] == "activated");
    Ok(
        json!({"available":true,"ethernet":ethernet,"wifiEnabled":manager["WirelessEnabled"],"wifiHardwareEnabled":manager["WirelessHardwareEnabled"],"wifiNetworks":networks,"vpns":vpns,"activeVpn":active_vpn,"activeConnections":active,"device":device_name,"addresses":addresses,"gateway":gateway,"dns":dns,"connectivity":match manager["Connectivity"].as_u64(){Some(1)=>"none",Some(2)=>"portal",Some(3)=>"limited",Some(4)=>"full",_=>"unknown"}}),
    )
}
pub fn data() -> Value {
    snapshot().unwrap_or_else(|e| json!({"available":false,"error":e.to_string(),"connectivity":"unknown","wifiNetworks":[],"vpns":[]}))
}
pub fn action(command: &str, args: &[&str], secret: &Value) -> Result<Value> {
    let b = Bus::system()?;
    let arg = args.first().copied().unwrap_or("");
    match command {
        "wifi-power" => {
            if !["on", "off"].contains(&arg) {
                return Err("Invalid radio state".into());
            }
            b.set(NM, ROOT, NM, "WirelessEnabled", "b", json!(arg == "on"))?;
        }
        "network-check" => {
            b.call(NM, ROOT, NM, "CheckConnectivity", "", &[])?;
        }
        "wifi-rescan" => {
            let manager = b.properties(NM, ROOT, NM)?;
            let mut found = false;
            for path in items(&manager["Devices"]).filter_map(Value::as_str) {
                if b.get(NM, path, DEVICE, "DeviceType")? == 2 {
                    b.call(NM, path, WIFI, "RequestScan", "a{sv}", &[json!({})])?;
                    found = true;
                }
            }
            if !found {
                return Err("No Wi-Fi adapter is available".into());
            }
        }
        "vpn-up" | "wifi-forget" => {
            let profile = profiles(&b)?
                .into_iter()
                .find(|(_, s)| {
                    if command == "vpn-up" {
                        text(&s["connection"], "uuid") == arg
                    } else {
                        ssid(&s["802-11-wireless"]["ssid"]) == arg
                            || text(&s["connection"], "id") == arg
                    }
                })
                .ok_or("Saved profile not found")?;
            if command == "vpn-up" {
                b.call(
                    NM,
                    ROOT,
                    NM,
                    "ActivateConnection",
                    "ooo",
                    &[json!(profile.0), json!("/"), json!("/")],
                )?;
            } else {
                b.call(NM, &profile.0, CONNECTION, "Delete", "", &[])?;
            }
        }
        "vpn-down" | "wifi-disconnect" => {
            let state = snapshot()?;
            let a = items(&state["activeConnections"])
                .find(|v| {
                    if command == "vpn-down" {
                        text(v, "uuid") == arg
                    } else {
                        text(v, "name") == arg || text(v, "type") == "802-11-wireless"
                    }
                })
                .ok_or("Connection is not active")?;
            b.call(
                NM,
                ROOT,
                NM,
                "DeactivateConnection",
                "o",
                &[a["path"].clone()],
            )?;
        }
        "wifi-connect" | "wifi-enterprise" => {
            let state = snapshot()?;
            let n = items(&state["wifiNetworks"])
                .find(|n| text(n, "ssid") == arg)
                .ok_or("Network is not in range; rescan first")?;
            if let Some(profile) = n["profile"]["path"].as_str().filter(|_| {
                command == "wifi-connect" && secret["password"].as_str().unwrap_or("").is_empty()
            }) {
                b.call(
                    NM,
                    ROOT,
                    NM,
                    "ActivateConnection",
                    "ooo",
                    &[
                        json!(profile),
                        json!(text(n, "devicePath")),
                        json!(text(n, "path")),
                    ],
                )?;
            } else {
                let mut settings = json!({"connection":{"id":v("s",json!(arg)),"type":v("s",json!("802-11-wireless"))},"802-11-wireless":{"ssid":v("ay",json!(arg.as_bytes())),"mode":v("s",json!("infrastructure"))}});
                if command == "wifi-enterprise" {
                    let identity = text(secret, "identity");
                    let domain = text(secret, "domain");
                    let ca = expand(text(secret, "ca"));
                    if identity.is_empty() || domain.is_empty() || !ca.is_file() {
                        return Err("Enterprise Wi-Fi requires identity, server domain and a readable CA certificate".into());
                    }
                    let method = text(secret, "method");
                    if !["peap", "ttls", "tls"].contains(&method) {
                        return Err("Choose PEAP, TTLS or TLS".into());
                    }
                    let mut ca_bytes = format!("file://{}", ca.display()).into_bytes();
                    ca_bytes.push(0);
                    settings["802-11-wireless-security"] =
                        json!({"key-mgmt":v("s",json!("wpa-eap"))});
                    let mut eap = json!({"eap":v("as",json!([method])),"identity":v("s",json!(identity)),"domain-suffix-match":v("s",json!(domain)),"ca-cert":v("ay",json!(ca_bytes))});
                    if method == "tls" {
                        for (field, input) in [
                            ("client-cert", "certificate"),
                            ("private-key", "privateKey"),
                        ] {
                            let path = expand(text(secret, input));
                            if !path.is_file() {
                                return Err(format!("Missing {field}").into());
                            }
                            let mut bytes = format!("file://{}", path.display()).into_bytes();
                            bytes.push(0);
                            eap[field] = v("ay", json!(bytes));
                        }
                        eap["private-key-password"] = v("s", secret["password"].clone());
                    } else {
                        eap["phase2-auth"] = v(
                            "s",
                            json!(if method == "peap" { "mschapv2" } else { "pap" }),
                        );
                        eap["password"] = v("s", secret["password"].clone());
                    }
                    settings["802-1x"] = eap;
                } else if text(n, "security").contains("OWE") {
                    settings["802-11-wireless-security"] = json!({"key-mgmt":v("s",json!("owe"))});
                } else if n["locked"] == true {
                    if n["enterprise"] == true {
                        return Err("This network requires enterprise authentication".into());
                    }
                    let password = text(secret, "password");
                    if password.is_empty() {
                        return Err("A network password is required".into());
                    }
                    let sec = text(n, "security");
                    settings["802-11-wireless-security"] = if sec == "WEP" {
                        let key_type = if [5, 13].contains(&password.len())
                            || ([10, 26].contains(&password.len())
                                && password.bytes().all(|b| b.is_ascii_hexdigit()))
                        {
                            1
                        } else {
                            2
                        };
                        json!({"key-mgmt":v("s",json!("none")),"wep-key0":v("s",json!(password)),"wep-key-type":v("u",json!(key_type))})
                    } else {
                        json!({"key-mgmt":v("s",json!(if sec.contains("WPA3") && !sec.contains("WPA2") {"sae"} else {"wpa-psk"})),"psk":v("s",json!(password))})
                    };
                }
                if n["profile"]["path"].is_string() {
                    return Err("Use saved-profile authentication to replace credentials without duplicating the profile".into());
                }
                b.call_interactive(
                    NM,
                    ROOT,
                    NM,
                    "AddAndActivateConnection",
                    "a{sa{sv}}oo",
                    &[settings, n["devicePath"].clone(), n["path"].clone()],
                )?;
            }
        }
        _ => return Err("Unsupported network action".into()),
    }
    Ok(json!({"requested":true}))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn channels_and_security() {
        assert_eq!(channel(2412), 1);
        assert_eq!(channel(2484), 14);
        assert_eq!(channel(5180), 36);
        assert_eq!(channel(5955), 1);
        assert_eq!(security(&json!({"RsnFlags":0x300})), "WPA2 802.1X");
        assert_eq!(ssid(&json!([32, 65, 58, 66, 32])), " A:B ");
    }
}
