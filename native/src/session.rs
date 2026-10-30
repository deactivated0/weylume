use crate::{bus::Bus, labwc, util::*};
use serde_json::{json, Value};
const LOGIN: &str = "org.freedesktop.login1";
const PATH: &str = "/org/freedesktop/login1";
const MANAGER: &str = "org.freedesktop.login1.Manager";
const SESSION: &str = "org.freedesktop.login1.Session";
fn permission(b: &Bus, method: &str) -> String {
    b.call(LOGIN, PATH, MANAGER, method, "", &[])
        .ok()
        .and_then(|v| v[0].as_str().map(str::to_string))
        .unwrap_or("unavailable".into())
}
pub fn status() -> Value {
    let Ok(b) = Bus::system() else {
        return json!({"canSuspend":false,"canHibernate":false,"inhibitors":[],"powerAvailable":false,"error":"System bus unavailable"});
    };
    let mut value = json!({"inhibitors":[],"powerAvailable":true});
    for (key, method) in [
        ("Suspend", "CanSuspend"),
        ("Hibernate", "CanHibernate"),
        ("PowerOff", "CanPowerOff"),
        ("Reboot", "CanReboot"),
    ] {
        let p = permission(&b, method);
        value[format!("can{key}")] = json!(["yes", "challenge"].contains(&p.as_str()));
        value[format!("permission{key}")] = json!(p);
    }
    if let Ok(v) = b.call(LOGIN, PATH, MANAGER, "ListInhibitors", "", &[]) {
        value["inhibitors"] = json!(v[0]
            .as_array()
            .into_iter()
            .flatten()
            .take(32)
            .map(|i| format!(
                "{}: {} ({}, {})",
                i[1].as_str().unwrap_or("Application"),
                i[2].as_str().unwrap_or(""),
                i[0].as_str().unwrap_or(""),
                i[3].as_str().unwrap_or("")
            ))
            .collect::<Vec<_>>());
    } else {
        value["inhibitorsUnknown"] = json!(true);
    }
    value
}
pub fn lock() -> Result<()> {
    let b = Bus::system()?;
    let path = b
        .call(
            LOGIN,
            PATH,
            MANAGER,
            "GetSessionByPID",
            "u",
            &[json!(std::process::id())],
        )
        .or_else(|error| {
            let session = std::env::var("XDG_SESSION_ID").unwrap_or_default();
            if session.is_empty() {
                return Err(error);
            }
            b.call(LOGIN, PATH, MANAGER, "GetSession", "s", &[json!(session)])
        })?[0]
        .as_str()
        .ok_or("Session not found")?
        .to_string();
    b.watch(&format!("type='signal',sender='{LOGIN}',path='{path}',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"))?;
    b.call(LOGIN, &path, SESSION, "Lock", "", &[])?;
    b.wait_until(8,||Ok(b.get(LOGIN,&path,SESSION,"LockedHint")?==true))
        .map_err(|_|"Locker did not acknowledge a secure session lock. Suspend was cancelled; configure a locker that updates logind LockedHint after acquiring the Wayland lock.".into())
}
pub fn action(action: &str) -> Result<()> {
    if action == "logout" {
        let (ok, msg) = run(&["labwc", "--exit"]);
        return if ok { Ok(()) } else { Err(msg.into()) };
    }
    let method = match action {
        "suspend" => "Suspend",
        "hibernate" => "Hibernate",
        "shutdown" => "PowerOff",
        "reboot" => "Reboot",
        _ => return Err("Unsupported session action".into()),
    };
    let b = Bus::system()?;
    let p = permission(&b, &format!("Can{method}"));
    if !["yes", "challenge"].contains(&p.as_str()) {
        return Err(format!("{method} is unavailable ({p})").into());
    }
    b.call_interactive(LOGIN, PATH, MANAGER, method, "b", &[json!(true)])?;
    Ok(())
}
fn power_bus() -> Result<(Bus, &'static str, &'static str)> {
    let b = Bus::system()?;
    for (name, path) in [
        (
            "org.freedesktop.UPower.PowerProfiles",
            "/org/freedesktop/UPower/PowerProfiles",
        ),
        ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles"),
    ] {
        if b.get(name, path, name, "ActiveProfile").is_ok() {
            return Ok((b, name, path));
        }
    }
    Err("Power profiles service is unavailable".into())
}
pub fn profile() -> Result<String> {
    let (b, n, p) = power_bus()?;
    Ok(b.get(n, p, n, "ActiveProfile")?
        .as_str()
        .ok_or("Invalid power profile")?
        .into())
}
pub fn set_profile(profile: &str) -> Result<()> {
    let (b, n, p) = power_bus()?;
    let profiles = b.get(n, p, n, "Profiles")?;
    if !profiles
        .as_array()
        .into_iter()
        .flatten()
        .any(|v| v["Profile"] == profile)
    {
        return Err(format!("Power profile {profile} is unsupported").into());
    }
    b.set(n, p, n, "ActiveProfile", "s", json!(profile))?;
    if b.get(n, p, n, "ActiveProfile")? != profile {
        return Err("Power profile was not applied".into());
    }
    Ok(())
}
pub fn gaming(
    enable: bool,
    performance: bool,
    tearing: bool,
    output_profile: &str,
) -> Result<Value> {
    let dir = cache().join("weylume");
    std::fs::create_dir_all(&dir)?;
    let _lock = Lock::new(&dir.join(".gaming.lock"))?;
    let path = dir.join("gaming-state.json");
    let saved = json_file(&path);
    if enable {
        if saved.is_object() {
            return Err("A gaming transaction already exists; disable gaming mode to restore it before applying another profile".into());
        }
        let prior = if performance { Some(profile()?) } else { None };
        let old_tearing = labwc::data()["allowTearing"].as_bool().unwrap_or(false);
        let output = if output_profile.is_empty() {
            Value::Null
        } else {
            crate::outputs::game_profile(output_profile)?
        };
        let journal = json!({"profile":prior,"tearing":old_tearing,"changedPower":performance,"changedTearing":tearing&&!old_tearing,"output":output});
        save_json(&path, &journal)?;
        let apply = || -> Result<()> {
            if output.is_object() {
                crate::outputs::set_layout(&output["desired"])?;
            }
            if performance {
                set_profile("performance")?;
            }
            if tearing && !old_tearing {
                let (ok, msg, _) = labwc::set("allowTearing", "true")?;
                if !ok {
                    return Err(msg.into());
                }
            }
            Ok(())
        };
        if let Err(error) = apply() {
            let restore = restore(&journal, true);
            if restore.is_ok() {
                std::fs::remove_file(path)?;
            }
            return Err(format!(
                "Gaming mode failed: {error}; restoration: {}",
                restore.err().map_or("complete".into(), |e| e.to_string())
            )
            .into());
        }
    } else if saved.is_object() {
        restore(&saved, false)?;
        std::fs::remove_file(path)?;
    }
    Ok(json!({"gaming":enable,"profile":profile().ok(),"labwc":labwc::data()}))
}
fn restore(saved: &Value, force_outputs: bool) -> Result<()> {
    let mut errors = Vec::new();
    if saved["output"].is_object() {
        match crate::outputs::data() {
            Ok(current)
                if force_outputs
                    || crate::outputs::same_layout(&current, &saved["output"]["desired"]) =>
            {
                if let Err(e) = crate::outputs::set_layout(&saved["output"]["previous"]) {
                    errors.push(e.to_string());
                }
            }
            Err(e) => errors.push(e.to_string()),
            _ => (),
        }
    }
    if saved["changedPower"] == true {
        match profile() {
            Ok(current) if current == "performance" => {
                if let Some(previous) = saved["profile"].as_str() {
                    if let Err(e) = set_profile(previous) {
                        errors.push(e.to_string());
                    }
                }
            }
            Err(e) => errors.push(e.to_string()),
            _ => (),
        }
    }
    if saved["changedTearing"] == true && labwc::data()["allowTearing"] == true {
        if let Err(e) = labwc::set(
            "allowTearing",
            if saved["tearing"] == true {
                "true"
            } else {
                "false"
            },
        )
        .and_then(|(ok, msg, _)| if ok { Ok(()) } else { Err(msg.into()) })
        {
            errors.push(e.to_string());
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("; ").into())
    }
}
pub fn recover() -> Value {
    if !cache().join("weylume/gaming-state.json").exists() {
        return json!({"recovered":false});
    }
    match gaming(false, false, false, "") {
        Ok(_) => json!({"recovered":true}),
        Err(e) => json!({"recovered":false,"error":e.to_string()}),
    }
}
