use crate::util::{config, Result};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs,
    path::Path,
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Clone)]
pub struct AutostartEntry {
    pub id: String,
    pub name: String,
    pub exec: String,
    pub icon: String,
    pub comment: String,
    pub enabled: bool,
    pub delay: u32,
    pub terminal: bool,
    pub source: String, // "user", "system", "labwc"
    pub path: String,
    pub running: bool,
    pub pid: Option<u32>,
}

impl AutostartEntry {
    pub fn to_json(&self) -> Value {
        json!({
            "id": self.id,
            "name": self.name,
            "exec": self.exec,
            "icon": self.icon,
            "comment": self.comment,
            "enabled": self.enabled,
            "delay": self.delay,
            "terminal": self.terminal,
            "source": self.source,
            "path": self.path,
            "running": self.running,
            "pid": self.pid,
        })
    }
}

fn get_running_processes() -> HashMap<String, u32> {
    let mut map = HashMap::with_capacity(256);
    let Ok(entries) = fs::read_dir("/proc") else { return map };
    let mut path_buf = Vec::with_capacity(32);
    let mut comm_buf = [0u8; 32];
    for entry in entries.flatten() {
        let name_bytes = entry.file_name().into_encoded_bytes();
        if name_bytes.is_empty() || !name_bytes.iter().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let pid = crate::util::parse_ascii_u64(&name_bytes) as u32;
        if pid == 0 {
            continue;
        }
        path_buf.clear();
        path_buf.extend_from_slice(b"/proc/");
        path_buf.extend_from_slice(&name_bytes);
        path_buf.extend_from_slice(b"/comm\0");
        let fd = unsafe {
            libc::open(
                path_buf.as_ptr().cast(),
                libc::O_RDONLY | libc::O_CLOEXEC,
            )
        };
        if fd >= 0 {
            let n = unsafe { libc::read(fd, comm_buf.as_mut_ptr().cast(), comm_buf.len()) };
            unsafe { libc::close(fd); }
            if n > 0 {
                let mut slice = &comm_buf[..n as usize];
                while let Some((&first, rest)) = slice.split_first() {
                    if first.is_ascii_whitespace() { slice = rest; } else { break; }
                }
                while let Some((&last, rest)) = slice.split_last() {
                    if last.is_ascii_whitespace() { slice = rest; } else { break; }
                }
                if !slice.is_empty() {
                    let mut s = String::with_capacity(slice.len());
                    for &b in slice {
                        s.push((b as char).to_ascii_lowercase());
                    }
                    map.entry(s).or_insert(pid);
                }
            }
        }
    }
    map
}

pub fn extract_bin_name(exec: &str) -> String {
    let mut s = exec.trim();
    if let Some(pos) = s.rfind("&&") {
        s = s[pos + 2..].trim();
    }
    if s.starts_with('(') {
        s = s.trim_start_matches('(').trim();
    }
    if s.starts_with("env ") {
        let parts: Vec<&str> = s.split_whitespace().collect();
        let mut idx = 1;
        while idx < parts.len() {
            if parts[idx] == "-u" || parts[idx] == "-i" {
                idx += 2;
            } else if parts[idx].contains('=') {
                idx += 1;
            } else {
                break;
            }
        }
        if idx < parts.len() {
            s = parts[idx];
        }
    }
    let first_token = s.split_whitespace().next().unwrap_or("");
    let unquoted = first_token.trim_matches('"').trim_matches('\'');
    Path::new(unquoted)
        .file_name()
        .map(|n| n.to_string_lossy().to_lowercase())
        .unwrap_or_default()
}

fn parse_desktop_file(
    path: &Path,
    source: &str,
    running: &HashMap<String, u32>,
) -> Option<AutostartEntry> {
    let content = fs::read_to_string(path).ok()?;
    let mut name = String::new();
    let mut exec = String::new();
    let mut icon = String::new();
    let mut comment = String::new();
    let mut hidden = false;
    let mut gnome_enabled = true;
    let mut delay: u32 = 0;
    let mut terminal = false;

    let mut in_desktop_entry = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == "[Desktop Entry]" {
            in_desktop_entry = true;
            continue;
        } else if trimmed.starts_with('[') && trimmed.ends_with(']') {
            in_desktop_entry = false;
            continue;
        }
        if !in_desktop_entry || trimmed.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = trimmed.split_once('=') {
            let key = k.trim();
            let val = v.trim();
            match key {
                "Name" if name.is_empty() => name = val.to_string(),
                "Exec" if exec.is_empty() => exec = val.to_string(),
                "Icon" if icon.is_empty() => icon = val.to_string(),
                "Comment" if comment.is_empty() => comment = val.to_string(),
                "Hidden" => hidden = val.eq_ignore_ascii_case("true"),
                "X-GNOME-Autostart-enabled" => gnome_enabled = !val.eq_ignore_ascii_case("false"),
                "X-GNOME-Autostart-Delay" | "X-KDE-autostart-after" => {
                    if let Ok(d) = val.parse::<u32>() {
                        delay = d;
                    }
                }
                "Terminal" => terminal = val.eq_ignore_ascii_case("true"),
                _ => {}
            }
        }
    }

    if exec.is_empty() && name.is_empty() {
        return None;
    }
    let file_id = path.file_name()?.to_string_lossy().to_string();
    if name.is_empty() {
        name = file_id
            .strip_suffix(".desktop")
            .unwrap_or(&file_id)
            .to_string();
    }
    if icon.is_empty() {
        icon = "application-x-executable".to_string();
    }

    let bin = extract_bin_name(&exec);
    let (is_running, pid) = if let Some(&p) = running.get(&bin) {
        (true, Some(p))
    } else {
        (false, None)
    };

    let enabled = !hidden && gnome_enabled;

    Some(AutostartEntry {
        id: file_id,
        name,
        exec,
        icon,
        comment,
        enabled,
        delay,
        terminal,
        source: source.to_string(),
        path: path.to_string_lossy().to_string(),
        running: is_running,
        pid,
    })
}

fn parse_labwc_autostart(
    path: &Path,
    running: &HashMap<String, u32>,
) -> Vec<AutostartEntry> {
    let mut items = Vec::new();
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return items,
    };

    for (idx, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let (enabled, raw_code) = if trimmed.starts_with('#') {
            (false, trimmed.trim_start_matches('#').trim())
        } else {
            (true, trimmed)
        };

        if raw_code.starts_with("systemctl --user import-environment")
            || raw_code.starts_with("dbus-update-activation-environment")
            || raw_code.starts_with("command -v")
            || raw_code.starts_with("mkdir -p")
            || raw_code.starts_with("systemctl --user restart")
            || raw_code.starts_with("state_dir=")
            || raw_code.starts_with("marker=")
            || raw_code.starts_with("success=")
            || raw_code.starts_with("for i in")
            || raw_code.starts_with("if ")
            || raw_code.ends_with("then")
            || raw_code.contains("qs ipc")
            || raw_code.contains("weylume-postboot-cleanup")
            || raw_code.starts_with("pkill -x")
            || raw_code.starts_with("fi")
            || raw_code.starts_with("done")
            || raw_code.starts_with("echo ")
            || raw_code.starts_with("rm -f")
            || raw_code.starts_with("#!/bin")
            || raw_code == ")"
            || raw_code == ") &"
            || raw_code == "("
        {
            continue;
        }

        if !raw_code.contains('&')
            && !raw_code.contains("waydroid")
            && !raw_code.contains("easyeffects")
            && !raw_code.contains("kanshi")
            && !raw_code.contains("ABDownloadManager")
        {
            continue;
        }

        let mut delay = 0u32;
        if let Some(pos) = raw_code.find("sleep ") {
            let after = &raw_code[pos + 6..];
            let num: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(d) = num.parse::<u32>() {
                delay = d;
            }
        }

        let bin = extract_bin_name(raw_code);
        if bin.is_empty() || bin == "sleep" || bin == "sh" {
            continue;
        }

        let (is_running, pid) = if let Some(&p) = running.get(&bin) {
            (true, Some(p))
        } else {
            (false, None)
        };

        let name = match bin.as_str() {
            "kanshi" => "Kanshi Display Profile Manager".into(),
            "easyeffects" => "EasyEffects Audio Service".into(),
            "abdownloadmanager" => "AB Download Manager (Background)".into(),
            "waydroid" => "Waydroid Walkie Talkie".into(),
            _ => format!("{} (Labwc session)", bin),
        };

        let icon = match bin.as_str() {
            "easyeffects" => "com.github.wwmm.easyeffects",
            "kanshi" => "video-display",
            "abdownloadmanager" => "abdownloadmanager",
            "waydroid" => "waydroid",
            _ => "application-x-executable",
        };

        items.push(AutostartEntry {
            id: format!("labwc:line_{}", idx),
            name,
            exec: raw_code.to_string(),
            icon: icon.to_string(),
            comment: format!("Launched via ~/.config/labwc/autostart:{}", idx + 1),
            enabled,
            delay,
            terminal: false,
            source: "labwc".to_string(),
            path: path.to_string_lossy().to_string(),
            running: is_running,
            pid,
        });
    }

    items
}

pub fn list() -> Result<Value> {
    let running = get_running_processes();
    let mut entries_map: HashMap<String, AutostartEntry> = HashMap::new();

    // 1. Scan System autostart: /etc/xdg/autostart
    let sys_dir = Path::new("/etc/xdg/autostart");
    if sys_dir.exists() {
        if let Ok(rd) = fs::read_dir(sys_dir) {
            for entry in rd.flatten() {
                let p = entry.path();
                if p.extension().map_or(false, |ext| ext == "desktop") {
                    if let Some(item) = parse_desktop_file(&p, "system", &running) {
                        entries_map.insert(item.id.clone(), item);
                    }
                }
            }
        }
    }

    // 2. Scan User autostart: ~/.config/autostart (overrides system)
    let user_dir = config().join("autostart");
    if user_dir.exists() {
        if let Ok(rd) = fs::read_dir(&user_dir) {
            for entry in rd.flatten() {
                let p = entry.path();
                if p.extension().map_or(false, |ext| ext == "desktop") {
                    if let Some(item) = parse_desktop_file(&p, "user", &running) {
                        entries_map.insert(item.id.clone(), item);
                    }
                }
            }
        }
    }

    let mut list: Vec<AutostartEntry> = entries_map.into_values().collect();

    // 3. Scan Labwc session autostart: ~/.config/labwc/autostart
    let labwc_path = config().join("labwc/autostart");
    let mut labwc_entries = parse_labwc_autostart(&labwc_path, &running);
    list.append(&mut labwc_entries);

    // Sort: user items first, then enabled items, then alphabetical by name
    list.sort_by(|a, b| {
        b.enabled
            .cmp(&a.enabled)
            .then_with(|| a.source.cmp(&b.source))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });

    let json_items: Vec<Value> = list.into_iter().map(|item| item.to_json()).collect();
    Ok(json!(json_items))
}

pub fn toggle(id: &str, enable: bool) -> Result<()> {
    if id.starts_with("labwc:line_") {
        let line_num: usize = id.strip_prefix("labwc:line_").unwrap_or("0").parse()?;
        let labwc_path = config().join("labwc/autostart");
        let content = fs::read_to_string(&labwc_path)?;
        let mut lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
        if line_num < lines.len() {
            let cur = lines[line_num].trim();
            if enable {
                lines[line_num] = cur.trim_start_matches('#').trim().to_string();
            } else if !cur.starts_with('#') {
                lines[line_num] = format!("# {}", cur);
            }
            fs::write(&labwc_path, lines.join("\n") + "\n")?;
        }
        return Ok(());
    }

    let user_dir = config().join("autostart");
    fs::create_dir_all(&user_dir)?;
    let user_file = user_dir.join(id);

    let content = if user_file.exists() {
        fs::read_to_string(&user_file)?
    } else {
        let sys_file = Path::new("/etc/xdg/autostart").join(id);
        if sys_file.exists() {
            fs::read_to_string(&sys_file)?
        } else {
            return Err(format!("Autostart file {} not found", id).into());
        }
    };

    let mut new_lines = Vec::new();
    let mut has_hidden = false;
    let mut has_gnome = false;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("Hidden=") {
            new_lines.push(format!("Hidden={}", !enable));
            has_hidden = true;
        } else if trimmed.starts_with("X-GNOME-Autostart-enabled=") {
            new_lines.push(format!("X-GNOME-Autostart-enabled={}", enable));
            has_gnome = true;
        } else {
            new_lines.push(line.to_string());
        }
    }

    if !has_hidden {
        new_lines.push(format!("Hidden={}", !enable));
    }
    if !has_gnome {
        new_lines.push(format!("X-GNOME-Autostart-enabled={}", enable));
    }

    fs::write(&user_file, new_lines.join("\n") + "\n")?;
    Ok(())
}

pub fn save(data_str: &str) -> Result<()> {
    let v: Value = serde_json::from_str(data_str)?;
    let mut id = v.get("id").and_then(|s| s.as_str()).unwrap_or("").trim().to_string();
    let name = v.get("name").and_then(|s| s.as_str()).unwrap_or("Application").trim();
    let exec = v.get("exec").and_then(|s| s.as_str()).unwrap_or("").trim();
    let icon = v.get("icon").and_then(|s| s.as_str()).unwrap_or("application-x-executable").trim();
    let comment = v.get("comment").and_then(|s| s.as_str()).unwrap_or("").trim();
    let delay = v.get("delay").and_then(|n| n.as_u64()).unwrap_or(0);
    let terminal = v.get("terminal").and_then(|b| b.as_bool()).unwrap_or(false);
    let enabled = v.get("enabled").and_then(|b| b.as_bool()).unwrap_or(true);

    if exec.is_empty() {
        return Err("Command / Exec cannot be empty".into());
    }

    if id.is_empty() || id.starts_with("new") {
        let slug: String = name
            .to_lowercase()
            .chars()
            .map(|c| if c.is_alphanumeric() { c } else { '-' })
            .collect();
        id = format!("{}.desktop", slug.trim_matches('-'));
    }
    if !id.ends_with(".desktop") {
        id = format!("{}.desktop", id);
    }

    let user_dir = config().join("autostart");
    fs::create_dir_all(&user_dir)?;
    let user_file = user_dir.join(&id);

    let content = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name={name}\n\
         Exec={exec}\n\
         Icon={icon}\n\
         Comment={comment}\n\
         Terminal={terminal}\n\
         Hidden={hidden}\n\
         X-GNOME-Autostart-enabled={enabled}\n\
         X-GNOME-Autostart-Delay={delay}\n",
        name = name,
        exec = exec,
        icon = icon,
        comment = comment,
        terminal = terminal,
        hidden = !enabled,
        enabled = enabled,
        delay = delay
    );

    fs::write(&user_file, content)?;
    Ok(())
}

pub fn delete(id: &str) -> Result<()> {
    if id.starts_with("labwc:line_") {
        let line_num: usize = id.strip_prefix("labwc:line_").unwrap_or("0").parse()?;
        let labwc_path = config().join("labwc/autostart");
        let content = fs::read_to_string(&labwc_path)?;
        let mut lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
        if line_num < lines.len() {
            lines.remove(line_num);
            fs::write(&labwc_path, lines.join("\n") + "\n")?;
        }
        return Ok(());
    }

    let user_file = config().join("autostart").join(id);
    let sys_file = Path::new("/etc/xdg/autostart").join(id);

    if sys_file.exists() {
        // Mask the system entry by setting Hidden=true in user directory
        let content = format!(
            "[Desktop Entry]\n\
             Type=Application\n\
             Hidden=true\n\
             X-GNOME-Autostart-enabled=false\n"
        );
        fs::write(&user_file, content)?;
    } else if user_file.exists() {
        fs::remove_file(&user_file)?;
    }
    Ok(())
}

pub fn launch(exec: &str) -> Result<()> {
    let clean = exec.trim();
    if clean.is_empty() {
        return Err("No command provided".into());
    }
    Command::new("sh")
        .arg("-c")
        .arg(format!("{} &", clean))
        .spawn()?;
    Ok(())
}

pub fn read_labwc() -> Result<String> {
    let p = config().join("labwc/autostart");
    Ok(fs::read_to_string(p).unwrap_or_default())
}

pub fn write_labwc(content: &str) -> Result<()> {
    let p = config().join("labwc/autostart");
    if p.exists() {
        let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
        let bak = p.with_extension(format!("bak.{}", now));
        let _ = fs::copy(&p, bak);
    }
    fs::write(p, content)?;
    Ok(())
}
