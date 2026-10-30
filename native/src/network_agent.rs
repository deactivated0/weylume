//! A user-scoped secrets agent lives only for an explicit saved-profile activation.
use crate::{
    bus::{string, Bus},
    dbus::{self, variant},
    util::*,
};
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_int, c_void},
    ptr,
    time::{Duration, Instant},
};
const NM: &str = "org.freedesktop.NetworkManager";
const ROOT: &str = "/org/freedesktop/NetworkManager";
#[link(name = "libsystemd.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn sd_bus_add_object(
        b: *mut c_void,
        s: *mut *mut c_void,
        p: *const c_char,
        cb: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void) -> c_int,
        u: *mut c_void,
    ) -> c_int;
    fn sd_bus_message_get_interface(m: *mut c_void) -> *const c_char;
    fn sd_bus_message_get_member(m: *mut c_void) -> *const c_char;
    fn sd_bus_message_get_sender(m: *mut c_void) -> *const c_char;
    fn sd_bus_message_ref(m: *mut c_void) -> *mut c_void;
    fn sd_bus_message_unref(m: *mut c_void) -> *mut c_void;
    fn sd_bus_message_new_method_return(m: *mut c_void, r: *mut *mut c_void) -> c_int;
    fn sd_bus_reply_method_errorf(m: *mut c_void, n: *const c_char, f: *const c_char, ...)
        -> c_int;
    fn sd_bus_send(b: *mut c_void, m: *mut c_void, c: *mut u64) -> c_int;
    fn sd_bus_flush(b: *mut c_void) -> c_int;
    fn sd_bus_process(b: *mut c_void, m: *mut *mut c_void) -> c_int;
    fn sd_bus_get_fd(b: *mut c_void) -> c_int;
    fn sd_bus_slot_unref(s: *mut c_void) -> *mut c_void;
}
struct Pending {
    message: *mut c_void,
    id: u64,
    setting: String,
    fields: Vec<String>,
}
impl Drop for Pending {
    fn drop(&mut self) {
        unsafe {
            sd_bus_message_unref(self.message);
        }
    }
}
struct Agent {
    bus: *mut c_void,
    owner: String,
    profile: String,
    pending: Option<Pending>,
    serial: u64,
    cancelled: bool,
}
struct Slot(*mut c_void);
impl Drop for Slot {
    fn drop(&mut self) {
        unsafe {
            sd_bus_slot_unref(self.0);
        }
    }
}
fn check(n: c_int) -> Result<()> {
    if n < 0 {
        Err(std::io::Error::from_raw_os_error(-n).into())
    } else {
        Ok(())
    }
}
unsafe fn reject(m: *mut c_void) {
    sd_bus_reply_method_errorf(
        m,
        c"org.freedesktop.NetworkManager.SecretAgent.UserCanceled".as_ptr(),
        c"Secrets request cancelled".as_ptr(),
    );
}
unsafe fn reply(bus: *mut c_void, m: *mut c_void, sig: &str, values: &[Value]) -> Result<()> {
    let mut r = ptr::null_mut();
    check(sd_bus_message_new_method_return(m, &mut r))?;
    let result = dbus::append_sequence(r, sig, values)
        .and_then(|_| check(sd_bus_send(bus, r, ptr::null_mut())));
    sd_bus_message_unref(r);
    result
}
unsafe extern "C" fn request(m: *mut c_void, data: *mut c_void, _: *mut c_void) -> c_int {
    let a = &mut *(data as *mut Agent);
    if string(sd_bus_message_get_interface(m)) != "org.freedesktop.NetworkManager.SecretAgent" {
        return 0;
    }
    if string(sd_bus_message_get_sender(m)) != a.owner {
        reject(m);
        return 1;
    }
    let method = string(sd_bus_message_get_member(m));
    let mut args = Vec::new();
    while let Ok(Some(v)) = dbus::read_value(m, 0) {
        args.push(v);
    }
    if method == "CancelGetSecrets" {
        if args.first().and_then(Value::as_str) == Some(a.profile.as_str()) {
            if let Some(p) = a.pending.take() {
                reject(p.message);
            }
            let _ = emit(&json!({"type":"cancel"}));
        }
        let _ = reply(a.bus, m, "", &[]);
        return 1;
    }
    if ["SaveSecrets", "DeleteSecrets"].contains(&method.as_str()) {
        // This ephemeral agent does not claim persistent secret storage.
        sd_bus_reply_method_errorf(
            m,
            c"org.freedesktop.NetworkManager.SecretAgent.NoSecrets".as_ptr(),
            c"Weylume does not store agent-owned secrets".as_ptr(),
        );
        return 1;
    }
    if method != "GetSecrets" {
        return 0;
    }
    if args.get(1).and_then(Value::as_str) != Some(a.profile.as_str()) || a.pending.is_some() {
        reject(m);
        return 1;
    }
    let setting = args.get(2).and_then(Value::as_str).unwrap_or("");
    let hints = args.get(3).and_then(Value::as_array);
    let mut fields: Vec<String> = hints
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter(|s| !s.starts_with("x-vpn-") && !s.is_empty() && s.len() <= 128)
        .take(16)
        .map(str::to_string)
        .collect();
    if fields.is_empty() {
        fields = match setting {
            "802-11-wireless-security" => vec![if args[0][setting]["key-mgmt"] == "none" {
                "wep-key0"
            } else {
                "psk"
            }
            .into()],
            "802-1x" => vec![if args[0][setting]["eap"][0] == "tls" {
                "private-key-password"
            } else {
                "password"
            }
            .into()],
            "wireguard" => vec!["private-key".into()],
            "vpn" | "pppoe" | "gsm" | "cdma" => vec!["password".into()],
            _ => {
                reject(m);
                return 1;
            }
        };
    }
    a.serial += 1;
    let _ = emit(
        &json!({"type":"prompt","id":a.serial,"name":args[0]["connection"]["id"],"setting":setting,"fields":fields,"retry":args.get(4).and_then(Value::as_u64).unwrap_or(0)&2!=0}),
    );
    a.pending = Some(Pending {
        message: sd_bus_message_ref(m),
        id: a.serial,
        setting: setting.into(),
        fields,
    });
    1
}
pub fn activate(id: &str, kind: &str) -> Result<()> {
    let bus = Bus::system()?;
    let state = crate::network::snapshot()?;
    let profile = if kind == "vpn" {
        state["vpns"]
            .as_array()
            .and_then(|v| v.iter().find(|v| v["uuid"] == id))
            .and_then(|v| v["path"].as_str())
    } else {
        state["wifiNetworks"]
            .as_array()
            .and_then(|v| v.iter().find(|v| v["ssid"] == id))
            .and_then(|v| v["profile"]["path"].as_str())
    }
    .ok_or("Saved connection no longer exists")?
    .to_string();
    let owner = bus.call(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "GetNameOwner",
        "s",
        &[json!(NM)],
    )?[0]
        .as_str()
        .ok_or("NetworkManager unavailable")?
        .to_string();
    let mut agent = Box::new(Agent {
        bus: bus.0,
        owner,
        profile: profile.clone(),
        pending: None,
        serial: 0,
        cancelled: false,
    });
    let mut slot = Slot(ptr::null_mut());
    unsafe {
        check(sd_bus_add_object(
            bus.0,
            &mut slot.0,
            c"/org/freedesktop/NetworkManager/SecretAgent".as_ptr(),
            request,
            (&mut *agent as *mut Agent).cast(),
        ))?;
    }
    bus.call_interactive(
        NM,
        "/org/freedesktop/NetworkManager/AgentManager",
        "org.freedesktop.NetworkManager.AgentManager",
        "RegisterWithCapabilities",
        "su",
        &[json!("org.weylume.Secrets"), json!(1)],
    )?;
    let result = (|| -> Result<()> {
        let active = bus.call_interactive(
            NM,
            ROOT,
            NM,
            "ActivateConnection",
            "ooo",
            &[json!(profile), json!("/"), json!("/")],
        )?[0]
            .as_str()
            .ok_or("Activation failed")?
            .to_string();
        bus.watch(&format!("type='signal',sender='{NM}',path='{active}'"))?;
        let deadline = Instant::now() + Duration::from_secs(120);
        let mut input = Vec::new();
        let mut buf = [0u8; 4096];
        let outcome = (|| -> Result<()> {
            loop {
                unsafe {
                    loop {
                        let n = sd_bus_process(bus.0, ptr::null_mut());
                        check(n)?;
                        if n == 0 {
                            break;
                        }
                    }
                    sd_bus_flush(bus.0);
                }
                if agent.cancelled {
                    return Err("Connection cancelled".into());
                }
                let status = bus.get(
                    NM,
                    &active,
                    "org.freedesktop.NetworkManager.Connection.Active",
                    "State",
                )?;
                if status == 2 {
                    return Ok(());
                }
                if status == 4 {
                    return Err("Connection activation failed; check credentials, certificates and VPN service settings".into());
                }
                if unsafe { sd_bus_process(bus.0, ptr::null_mut()) } > 0 {
                    continue;
                }
                let timeout = deadline
                    .saturating_duration_since(Instant::now())
                    .as_millis()
                    .min(i32::MAX as u128) as i32;
                if timeout == 0 {
                    return Err("Connection authentication timed out".into());
                }
                let mut fds = [
                    libc::pollfd {
                        fd: 0,
                        events: libc::POLLIN,
                        revents: 0,
                    },
                    libc::pollfd {
                        fd: unsafe { sd_bus_get_fd(bus.0) },
                        events: libc::POLLIN,
                        revents: 0,
                    },
                ];
                let n = unsafe { libc::poll(fds.as_mut_ptr(), 2, timeout) };
                if n < 0 {
                    if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                        continue;
                    }
                    return Err(std::io::Error::last_os_error().into());
                }
                if fds[0].revents & (libc::POLLHUP | libc::POLLERR) != 0
                    || fds[1].revents & (libc::POLLHUP | libc::POLLERR) != 0
                {
                    return Err("Connection request closed".into());
                }
                if fds[0].revents & libc::POLLIN != 0 {
                    let n = unsafe { libc::read(0, buf.as_mut_ptr().cast(), buf.len()) };
                    if n <= 0 {
                        return Err("Connection request closed".into());
                    }
                    input.extend_from_slice(&buf[..n as usize]);
                    if input.len() > 32768 {
                        return Err("Secrets reply too large".into());
                    }
                    while let Some(end) = input.iter().position(|b| *b == b'\n') {
                        let value = serde_json::from_slice::<Value>(&input[..end]);
                        input.drain(..=end);
                        let Ok(value) = value else {
                            continue;
                        };
                        if value["cancel"] == true {
                            agent.cancelled = true;
                            break;
                        }
                        if agent
                            .pending
                            .as_ref()
                            .is_none_or(|p| value["id"].as_u64() != Some(p.id))
                        {
                            continue;
                        }
                        let p = agent.pending.take().unwrap();
                        if value["accept"] != true {
                            unsafe {
                                reject(p.message);
                            }
                            agent.cancelled = true;
                            break;
                        }
                        let mut secrets = serde_json::Map::new();
                        for key in &p.fields {
                            let value = value["values"][key]
                                .as_str()
                                .filter(|v| v.len() <= 8192)
                                .ok_or("Missing secret field")?;
                            secrets.insert(
                                key.clone(),
                                if p.setting == "vpn" {
                                    json!(value)
                                } else {
                                    variant("s", json!(value))
                                },
                            );
                        }
                        let settings = if p.setting == "vpn" {
                            json!({"vpn":{"secrets":variant("a{ss}",json!(secrets))}})
                        } else {
                            json!({p.setting.clone():secrets})
                        };
                        unsafe {
                            reply(bus.0, p.message, "a{sa{sv}}", &[settings])?;
                        }
                    }
                }
            }
        })();
        if outcome.is_err() {
            let _ = bus.call(NM, ROOT, NM, "DeactivateConnection", "o", &[json!(active)]);
        }
        outcome
    })();
    if let Some(p) = agent.pending.take() {
        unsafe {
            reject(p.message);
        }
    }
    let _ = bus.call(
        NM,
        "/org/freedesktop/NetworkManager/AgentManager",
        "org.freedesktop.NetworkManager.AgentManager",
        "Unregister",
        "",
        &[],
    );
    let _ = emit(
        &json!({"type":"finished","ok":result.is_ok(),"message":result.as_ref().err().map_or("Connected".into(),|e|e.to_string())}),
    );
    drop(slot);
    result
}
