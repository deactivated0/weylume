use crate::{bus, clipboard, labwc, network, session, util::*};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use std::fs;
const COMMANDS:&str="nmcli bluetoothctl wpctl pactl playerctl powerprofilesctl busctl wl-gammarelay-rs brightnessctl grim slurp swappy wl-copy wl-paste gpu-screen-recorder gpu-screen-recorder-gtk kitty pcmanfm-qt featherpad pavucontrol easyeffects missioncenter btop qdirstat btrfs-assistant cachyos-kernel-manager cachyos-packageinstaller cachyos-pi cachy-update lact goverlay piper scx-manager amdgpu_top fwupdmgr ufw waydroid-helper wlr-randr labwc systemctl systemd-inhibit loginctl checkupdates wtype xdg-open riseup-vpn waydroid haruna spotify-launcher discord-development discord-canary discord-ptb nmtui heroic bitwarden bitwarden-desktop steam canberra-gtk-play";
fn available_commands() -> serde_json::Map<String, Value> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    use std::sync::OnceLock;

    static CMDS: OnceLock<serde_json::Map<String, Value>> = OnceLock::new();
    if let Some(cached) = CMDS.get() {
        return cached.clone();
    }

    let mut remaining: Vec<(&'static str, CString)> = COMMANDS
        .split_whitespace()
        .map(|cmd| (cmd, CString::new(cmd).unwrap()))
        .collect();
    let mut map = serde_json::Map::with_capacity(remaining.len());
    for &(cmd, _) in &remaining {
        map.insert(cmd.into(), json!(false));
    }

    let paths = std::env::var_os("PATH").unwrap_or_default();
    let split_paths: Vec<_> = std::env::split_paths(&paths).filter(|d| d.is_dir()).collect();
    for dir in &split_paths {
        if remaining.is_empty() {
            break;
        }
        let Ok(c_dir) = CString::new(dir.as_os_str().as_bytes()) else { continue };
        let dir_fd = unsafe { libc::open(c_dir.as_ptr(), libc::O_DIRECTORY | libc::O_PATH | libc::O_CLOEXEC) };
        if dir_fd < 0 { continue };
        remaining.retain(|&(cmd, ref c_cmd)| {
            let res = unsafe { libc::faccessat(dir_fd, c_cmd.as_ptr(), libc::X_OK, 0) };
            if res == 0 {
                map.insert(cmd.to_string(), json!(true));
                false
            } else {
                true
            }
        });
        unsafe { libc::close(dir_fd) };
    }

    let _ = CMDS.set(map.clone());
    map
}
fn capabilities() -> Value {
    let commands = available_commands();
    let has_labwc = !std::env::var("LABWC_PID").unwrap_or_default().is_empty()
        || commands.get("labwc").and_then(Value::as_bool).unwrap_or(false);
    json!({"commands":commands,"wayland":!std::env::var("WAYLAND_DISPLAY").unwrap_or_default().is_empty(),"labwc":has_labwc,"labwcConfig":config().join("labwc/rc.xml"),"previewHelper":shell().join("weylume-native"),"previewSource":shell().join("native/src/preview.rs"),"screenshots":home().join("Pictures/Screenshots"),"recordings":home().join("Videos")})
}
fn state() -> Result<Value> {
    let _lock = Lock::new(&shell().join(".state.lock"))?;
    let (mut valid, mut repaired) = (Vec::new(), Vec::new());
    for name in [
        "pinned.json",
        "start_favorites.json",
        "tray_config.json",
        "calendar.json",
        "desktop_positions.json",
        "wallpaper.json",
        "nightlight.json",
        "settings.json",
        "clipboard_history.json",
        "notification_history.json",
        "game_profiles.json",
        "output_profiles.json",
    ] {
        let path = shell().join(name);
        let v = json_file(&path);
        let list = name == "pinned.json" || name == "start_favorites.json";
        if (list && v.is_array()) || (!list && v.is_object()) {
            valid.push(name)
        } else {
            if path.exists() {
                let _ = fs::copy(&path, shell().join(format!("{name}.corrupt-{}", now())));
            }
            save_json(&path, &if list { json!([]) } else { json!({}) })?;
            repaired.push(name);
        }
    }
    let marker = shell().join(".state-version.json");
    let v = json!({"version":3});
    if json_file(&marker) != v {
        save_json(&marker, &v)?;
    }
    Ok(json!({"valid":valid,"repaired":repaired,"version":3}))
}
fn clean(limit: usize, age: u64) -> Result<Value> {
    let dir = cache().join("weylume/previews");
    fs::create_dir_all(&dir)?;
    let mut files = Vec::new();
    let mut removed = 0;
    for e in fs::read_dir(&dir)?.flatten() {
        let name = e.file_name();
        if !name.as_encoded_bytes().ends_with(b".jpg") {
            continue;
        }
        let Ok(m) = e.metadata() else { continue };
        let p = e.path();
        let t = m
            .modified()?
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs();
        if now().saturating_sub(t) > age * 3600 {
            if fs::remove_file(&p).is_ok() {
                removed += 1
            }
        } else {
            files.push((t, p))
        }
    }
    files.sort_by(|a, b| b.cmp(a));
    for (_, p) in files.into_iter().skip(limit.max(1)) {
        if fs::remove_file(p).is_ok() {
            removed += 1
        }
    }
    Ok(json!({"directory":dir,"removed":removed}))
}
fn session_status() -> Value {
    session::status()
}
fn status() -> Value {
    if let Ok(b) = bus::Bus::system() {
        let mut state = session::status_with_bus(&b);
        state["powerProfile"] = json!(session::profile_with_bus(&b).unwrap_or("unavailable".into()));
        state
    } else {
        let mut state = session_status();
        state["powerProfile"] = json!("unavailable");
        state
    }
}
fn audio_default(id: &str, name: &str, source: bool) -> (bool, String) {
    // Quickshell sets the preferred default natively. Only migrate existing
    // streams here; duplicate wpctl/pactl default writes are unnecessary.
    let pulse = crate::audio::migrate(name, source);
    let success = pulse.is_ok();
    let messages = pulse
        .err()
        .map(|e| e.to_string())
        .into_iter()
        .collect::<Vec<_>>();
    let class = if source {
        "Stream/Input/Audio"
    } else {
        "Stream/Output/Audio"
    };
    if !id.is_empty() && has("pw-cli") && has("pw-metadata") {
        let dump = output(&["pw-cli", "list-objects", "Node"]);
        let mut current = String::new();
        let mut cls = String::new();
        let route = |current: &str, cls: &str| {
            if !current.is_empty() && cls.contains(class) {
                for key in ["target.node", "target.object"] {
                    run(&["pw-metadata", "-n", "default", current, key, id]);
                }
            }
        };
        for l in dump.lines() {
            let l = l.trim();
            if let Some(s) = l.strip_prefix("id ") {
                route(&current, &cls);
                current = s.split(',').next().unwrap_or("").trim().into();
                cls.clear()
            } else if l.contains("media.class = ") {
                cls = l
                    .split_once('=')
                    .map_or("", |(_, s)| s)
                    .replace('"', "")
                    .trim()
                    .into()
            }
        }
        route(&current, &cls);
    }
    (success, messages.join("\n"))
}
fn media(action: &str) -> (bool, String) {
    let (method, key) = match action {
        "play-pause" => ("PlayPause", "XF86AudioPlay"),
        "previous" => ("Previous", "XF86AudioPrev"),
        "next" => ("Next", "XF86AudioNext"),
        _ => return (false, "Unknown media action".into()),
    };
    let result = run(&["playerctl", action]);
    if result.0 {
        return result;
    }
    let list = output(&["busctl", "--user", "list"]);
    let players: Vec<_> = list
        .lines()
        .filter(|l| l.contains("org.mpris.MediaPlayer2"))
        .filter_map(|l| l.split_whitespace().next())
        .collect();
    if !players.is_empty() {
        let mut ok = false;
        for p in players {
            ok |= run(&[
                "busctl",
                "--user",
                "call",
                p,
                "/org/mpris/MediaPlayer2",
                "org.mpris.MediaPlayer2.Player",
                method,
            ])
            .0;
        }
        return (ok, String::new());
    }
    if has("wtype") {
        run(&["wtype", "-k", key])
    } else {
        (false, "No active media player".into())
    }
}
fn screenshot(mode: &str, copy: bool, annotate: bool) -> Result<(bool, String, Value)> {
    if !has("grim") {
        return Err("grim is not installed".into());
    }
    let dir = home().join("Pictures/Screenshots");
    fs::create_dir_all(&dir)?;
    let path = dir.join(format!(
        "{}-{}.png",
        stamp("Weylume_%Y-%m-%d_%H-%M-%S"),
        std::process::id()
    ));
    if mode == "window" {
        return Err("Select a window before capturing".into());
    }
    let window_id = mode.strip_prefix("window:");
    if mode != "screen" && mode != "region" && window_id.is_none() {
        return Err("Invalid screenshot mode".into());
    }
    if let Some(id) = window_id {
        if id.is_empty() || id.len() > 512 || id.contains(['\n', '\0']) {
            return Err("Invalid window identity".into());
        }
    }
    let geometry = if mode == "region" {
        if !has("slurp") {
            return Err("slurp is required for region capture".into());
        }
        let (c, g, e) = execute(&["slurp"], 120, None);
        if c != 0 || g.trim().is_empty() {
            return Err(if e.trim().is_empty() {
                "Screenshot cancelled".to_string()
            } else {
                e.trim().into()
            }
            .into());
        }
        g.trim().to_string()
    } else {
        String::new()
    };
    let p = path.to_string_lossy();
    let mut args = vec!["grim"];
    if !geometry.is_empty() {
        args.extend(["-g", &geometry]);
    }
    if let Some(id) = window_id {
        args.extend(["-T", id]);
    }
    args.push(&p);
    let (c, o, e) = execute(&args, 45, None);
    if c != 0 {
        return Ok((false, if e.is_empty() { o } else { e }, Value::Null));
    }
    if copy && has("wl-copy") {
        if let Ok(b) = fs::read(&path) {
            execute(&["wl-copy", "--type", "image/png"], 15, Some(&b));
        }
    }
    if annotate && has("swappy") {
        spawn(&["swappy", "-f", &p]);
    }
    Ok((
        true,
        format!("Saved {}", path.file_name().unwrap().to_string_lossy()),
        json!({"path":path}),
    ))
}
pub fn action(args: &[String]) -> Result<(bool, String, Value)> {
    let v: Vec<&str> = args.iter().map(String::as_str).collect();
    let Some((command, a)) = v.split_first() else {
        return Err("No command supplied".into());
    };
    let c = *command;
    let answer = |msg: &str, v: Value| Ok((true, msg.into(), v));
    let pair = |(ok, msg): (bool, String)| Ok((ok, msg, Value::Null));
    match (c, a) {
        ("capabilities", _) => answer("Capabilities detected", capabilities()),
        ("startup-data", _) => {
            let limit = a.first().unwrap_or(&"96").parse::<usize>()?.clamp(8, 512);
            let age = a.get(1).unwrap_or(&"6").parse::<u64>()?.clamp(1, 168);
            let sys_bus = bus::Bus::system().ok();
            let sys_val = if let Some(ref b) = sys_bus {
                let mut s = session::status_with_bus(b);
                s["powerProfile"] = json!(session::profile_with_bus(b).unwrap_or("unavailable".into()));
                s
            } else {
                status()
            };
            let net_val = if let Some(ref b) = sys_bus {
                network::data_with_bus(b)
            } else {
                network::data()
            };
            answer(
                "Startup state loaded",
                json!({"recovery":session::recover(),"outputRecovery":match crate::outputs::restore(){Ok(v)=>json!({"restored":v}),Err(e)=>json!({"error":e.to_string()})},"capabilities":capabilities(),"preview":clean(limit,age)?,"labwc":labwc::data(),"system":sys_val,"network":net_val}),
            )
        }
        ("diagnostics", []) => answer("Diagnostics complete", crate::diagnostics::data()),
        ("profile", [pid, seconds]) => answer(
            "Measurement complete",
            crate::diagnostics::profile(pid.parse()?, seconds.parse()?)?,
        ),
        ("network-data", _) => answer("Network state refreshed", network::data()),
        ("labwc-data", _) => answer("Labwc state refreshed", labwc::data()),
        ("system-status", _) => answer("System state refreshed", status()),
        ("session-status", _) => answer("Session state refreshed", session_status()),
        ("outputs", []) => answer(
            "Displays refreshed",
            json!({"outputs":crate::outputs::data()?,"profiles":json_file(shell().join("output_profiles.json"))}),
        ),
        ("output-save", [name]) => {
            answer("Output profile saved", crate::outputs::save_profile(name)?)
        }
        ("output-recover", []) => answer(
            "Display recovery checked",
            json!({"restored":crate::outputs::restore()?}),
        ),
        ("calendar-import", [path]) => answer("Calendar imported", crate::calendar::import(path)?),
        ("calendar-notify", [title, body]) => {
            bus::Bus::user()?.call(
                "org.freedesktop.Notifications",
                "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications",
                "Notify",
                "susssasa{sv}i",
                &[
                    json!("Weylume Calendar"),
                    json!(0),
                    json!("x-office-calendar"),
                    json!(title),
                    json!(body),
                    json!([]),
                    json!({}),
                    json!(-1),
                ],
            )?;
            answer("Reminder delivered", Value::Null)
        }
        ("state-validate", _) => answer("State files validated", state()?),
        ("preview-clean", _) => answer(
            "Preview cache cleaned",
            clean(
                a.first().unwrap_or(&"96").parse::<usize>()?.clamp(8, 512),
                a.get(1).unwrap_or(&"6").parse::<u64>()?.clamp(1, 168),
            )?,
        ),
        ("prepare-recording", [container]) => {
            answer("Recording prepared", crate::recording::prepare(container)?)
        }
        ("recording-control", [path, action]) => answer(
            "Recorder acknowledged request",
            crate::recording::control(path, action)?,
        ),
        ("recording-check", [path]) => {
            answer("Recording file checked", crate::recording::check(path)?)
        }
        ("media", [action]) => pair(media(action)),
        ("brightness", [raw]) => {
            let n = raw.parse::<f64>()?;
            if !n.is_finite() {
                return Err("Invalid brightness".into());
            }
            let value = ((n * 100.).round_ties_even() / 100.).clamp(0.05, 1.);
            let (ok, msg) = bus::gamma("Brightness", value);
            let backlight = has("brightnessctl")
                && run(&[
                    "brightnessctl",
                    "-q",
                    "-c",
                    "backlight",
                    "set",
                    &format!("{:.0}%", value * 100.),
                ])
                .0;
            Ok((ok || backlight, msg, json!({"value":value})))
        }
        ("temperature", [raw]) => {
            let value = raw.parse::<i32>()?.clamp(2500, 6500);
            let (ok, msg) = bus::gamma("Temperature", value as f64);
            Ok((ok, msg, json!({"value":value})))
        }
        ("lock", []) => {
            session::lock()?;
            answer("Locker acknowledged session lock", Value::Null)
        }
        ("gaming-mode", [enabled, performance, tearing]) => answer(
            "Gaming mode updated",
            session::gaming(*enabled == "1", *performance == "1", *tearing == "1", "")?,
        ),
        ("gaming-mode", [enabled, performance, tearing, output]) => answer(
            "Gaming profile updated",
            session::gaming(
                *enabled == "1",
                *performance == "1",
                *tearing == "1",
                output,
            )?,
        ),
        ("audio-details", []) => answer("Audio profiles refreshed", crate::audio::details()?),
        ("audio-profile", [name, profile]) => {
            crate::audio::set("profile", name, profile)?;
            answer("Audio profile applied", Value::Null)
        }
        ("audio-port", [kind, name, port]) => {
            crate::audio::set(kind, name, port)?;
            answer("Audio port applied", Value::Null)
        }
        ("audio-settings", []) => {
            for p in ["pavucontrol", "easyeffects"] {
                if has(p) && spawn(&[p]) {
                    return answer(&format!("Opened {p}"), Value::Null);
                }
            }
            Err("No audio settings application was found".into())
        }
        ("bt-connect" | "bt-disconnect" | "bt-remove", [addr]) => {
            pair(run(&["bluetoothctl", &c[3..], addr]))
        }
        ("bt-power", [value]) if ["on", "off"].contains(value) => {
            pair(run(&["bluetoothctl", "power", value]))
        }
        ("bt-scan-start" | "bt-scan-stop", []) => pair(run(&[
            "bluetoothctl",
            "scan",
            if c.ends_with("start") { "on" } else { "off" },
        ])),
        (
            "wifi-connect" | "wifi-enterprise" | "wifi-disconnect" | "wifi-forget" | "wifi-power"
            | "wifi-rescan" | "vpn-up" | "vpn-down" | "network-check",
            args,
        ) => {
            let secret = if ["wifi-connect", "wifi-enterprise"].contains(&c) {
                read_input()?
            } else {
                Value::Null
            };
            answer(
                "Network request accepted",
                network::action(c, args, &secret)?,
            )
        }
        ("audio-default" | "audio-source-default", [id, name]) => {
            pair(audio_default(id, name, c == "audio-source-default"))
        }
        ("audio-move-stream", [id, target]) => {
            let r = run(&["wpctl", "move", id, target]);
            pair(if !r.0 && has("pactl") {
                run(&["pactl", "move-sink-input", id, target])
            } else {
                r
            })
        }
        ("power-profile", [profile]) => {
            session::set_profile(profile)?;
            answer("Power profile applied", json!({"profile":profile}))
        }

        ("screenshot", [mode, copy, annotate]) => screenshot(mode, *copy == "1", *annotate == "1"),
        ("notification-sound", []) => {
            if !has("canberra-gtk-play") {
                return Err("Notification sounds are unavailable".into());
            }
            Ok((
                spawn(&["canberra-gtk-play", "-i", "message-new-instant"]),
                "Notification sound played".into(),
                Value::Null,
            ))
        }
        ("clipboard-copy", [raw]) => {
            let data = STANDARD.decode(raw).map_err(|_| "Invalid clipboard data")?;
            let (code, _, e) = execute(&["wl-copy"], 15, Some(&data));
            pair((code == 0, e.trim().into()))
        }
        ("clipboard-copy-image", [raw, mime]) => {
            let path = clipboard::checked(raw, true)?;
            let data = fs::read(path)?;
            let (code, _, e) = execute(&["wl-copy", "--type", mime], 15, Some(&data));
            pair((code == 0, e.trim().into()))
        }
        ("clipboard-store", []) => answer("Clipboard history saved", clipboard::store()?),
        ("clipboard-image-delete", [raw]) => {
            clipboard::remove_unreferenced(raw)?;
            answer("Clipboard cache reconciled", Value::Null)
        }
        ("system-theme", [mode]) => {
            let is_dark = *mode != "light" && *mode != "false";
            apply_system_theme(is_dark)
        }
        ("labwc-set", [k, v]) => labwc::set(k, v),
        ("workspace-switch" | "workspace-send", [raw])
            if !raw.is_empty() && raw.bytes().all(|b| b.is_ascii_digit()) =>
        {
            let number = raw.parse::<usize>()?;
            let index = labwc::workspace_key(number, c == "workspace-send")?;
            let mut cmd = vec!["wtype", "-M", "logo"];
            if c == "workspace-send" {
                cmd.extend(["-M", "shift"])
            }
            cmd.extend(["-k", &index]);
            if c == "workspace-send" {
                cmd.extend(["-m", "shift"])
            }
            cmd.extend(["-m", "logo"]);
            let (ok, msg) = run(&cmd);
            Ok((ok, msg, json!({"index":number})))
        }
        ("launch", [exe, rest @ ..])
            if COMMANDS
                .split_whitespace()
                .chain(["cachyos-hello", "mission-center"])
                .any(|s| s == *exe) =>
        {
            let p = which(exe).ok_or_else(|| format!("{exe} is not installed"))?;
            let p = p.to_string_lossy();
            let mut cmd = vec![p.as_ref()];
            cmd.extend(rest);
            Ok((spawn(&cmd), format!("Opened {exe}"), Value::Null))
        }
        ("open-path", [raw]) => {
            let p = expand(raw);
            let p = p.to_string_lossy();
            Ok((spawn(&["xdg-open", &p]), format!("Opened {p}"), Value::Null))
        }
        ("service", [scope, op, name])
            if ["user", "system"].contains(scope)
                && ["start", "stop", "restart"].contains(op)
                && [
                    "NetworkManager",
                    "bluetooth",
                    "ufw",
                    "power-profiles-daemon",
                    "upower",
                    "pipewire",
                    "pipewire-pulse",
                    "wireplumber",
                    "ananicy-cpp",
                    "ollama",
                ]
                .contains(name) =>
        {
            let mut cmd = vec!["systemctl"];
            if *scope == "user" {
                cmd.push("--user")
            }
            cmd.extend([op, name]);
            let (code, o, e) = execute(&cmd, 30, None);
            pair((code == 0, if e.is_empty() { o } else { e }.trim().into()))
        }
        ("session", [a]) => {
            session::action(a)?;
            answer("Session request accepted", Value::Null)
        }
        ("update-check", []) => {
            let exe = which("checkupdates").ok_or("checkupdates is not installed")?;
            let (code, o, _) = execute(&[&exe.to_string_lossy()], 120, None);
            let updates: Vec<_> = o.lines().filter(|l| !l.trim().is_empty()).collect();
            Ok((
                [0, 2].contains(&code),
                if updates.is_empty() {
                    "System is up to date".into()
                } else {
                    format!("{} updates available", updates.len())
                },
                json!({"updates":updates.iter().take(500).collect::<Vec<_>>(),"count":updates.len()}),
            ))
        }
        _ => Err(format!("Unsupported action: {c}").into()),
    }
}

fn read_input() -> Result<Value> {
    use std::io::Read;
    let mut input = String::new();
    std::io::stdin().take(65537).read_to_string(&mut input)?;
    if input.len() > 65536 {
        return Err("Input exceeds 64 KiB".into());
    }
    if input.trim().is_empty() {
        Ok(json!({}))
    } else {
        Ok(serde_json::from_str(&input)?)
    }
}

pub fn apply_system_theme(is_dark: bool) -> Result<(bool, String, Value)> {
    let color_scheme = if is_dark { "prefer-dark" } else { "prefer-light" };
    let _ = std::process::Command::new("gsettings")
        .args(["set", "org.gnome.desktop.interface", "color-scheme", color_scheme])
        .status();

    let h = home();
    for rel in [".config/gtk-3.0/settings.ini", ".config/gtk-4.0/settings.ini"] {
        let p = h.join(rel);
        if p.exists() {
            if let Ok(content) = fs::read_to_string(&p) {
                let mut lines = Vec::new();
                let mut replaced = false;
                let target = format!("gtk-application-prefer-dark-theme={}", if is_dark { "true" } else { "false" });
                for line in content.lines() {
                    if line.trim_start().starts_with("gtk-application-prefer-dark-theme") {
                        lines.push(target.clone());
                        replaced = true;
                    } else {
                        lines.push(line.to_string());
                    }
                }
                if !replaced {
                    lines.push(target);
                }
                lines.push(String::new());
                let _ = atomic(&p, lines.join("\n").as_bytes());
            }
        }
    }

    let theme_name = if is_dark { "Weylume" } else { "Weylume-Light" };
    let (lab_ok, _, lab_data) = labwc::set("theme", theme_name)?;

    Ok((lab_ok, format!("System theme applied: {}", if is_dark { "dark" } else { "light" }), json!({"darkMode": is_dark, "labwc": lab_data})))
}
