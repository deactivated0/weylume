use crate::util::*;
use serde_json::{json, Value};
use std::{fs, path::PathBuf};
use xmltree::{Element, EmitterConfig, XMLNode};
fn dir() -> PathBuf {
    config().join("labwc")
}
fn environment_layout() -> String {
    for l in read(dir().join("environment")).lines() {
        let l = l.trim();
        if l.starts_with('#') || l.is_empty() {
            continue;
        }
        if let Some((k, v)) = l.split_once('=') {
            if k.trim() == "XKB_DEFAULT_LAYOUT" {
                return v.trim().to_string();
            }
        }
    }
    "us".into()
}
fn set_env(key: &str, value: &str) -> Result<()> {
    let p = dir().join("environment");
    let old = read(&p);
    let mut seen = false;
    let mut lines = Vec::new();
    let prefix = format!("{key}=");
    let replacement = format!("{key}={value}");
    for l in old.lines() {
        if l.trim_start().starts_with(&prefix) {
            if !seen {
                lines.push(replacement.as_str());
                seen = true
            }
        } else {
            lines.push(l)
        }
    }
    if !seen {
        lines.push(&replacement)
    }
    atomic(&p, format!("{}\n", lines.join("\n").trim_end()).as_bytes())
}
fn child<'a>(e: &'a Element, path: &[&str]) -> Option<&'a Element> {
    let Some((head, tail)) = path.split_first() else {
        return Some(e);
    };
    child(e.get_child(*head)?, tail)
}
fn make(parent: &Element, name: &str) -> Element {
    let mut e = Element::new(name);
    e.namespace = parent.namespace.clone();
    e.prefix = parent.prefix.clone();
    e
}
fn ensure<'a>(e: &'a mut Element, path: &[&str]) -> &'a mut Element {
    let Some((head, tail)) = path.split_first() else {
        return e;
    };
    let i = if let Some(i) = e
        .children
        .iter()
        .position(|n| n.as_element().is_some_and(|c| c.name == *head))
    {
        i
    } else {
        let c = make(e, head);
        e.children.push(XMLNode::Element(c));
        e.children.len() - 1
    };
    ensure(e.children[i].as_mut_element().unwrap(), tail)
}
fn text(e: &Element, path: &[&str], fallback: &str) -> String {
    child(e, path)
        .and_then(Element::get_text)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| fallback.into())
}
fn set_text(e: &mut Element, t: String) {
    e.children
        .retain(|c| !matches!(c, XMLNode::Text(_) | XMLNode::CData(_)));
    e.children.insert(0, XMLNode::Text(t));
}
fn device<'a>(e: &'a Element, cat: &str) -> Option<&'a Element> {
    child(e, &["libinput"])?
        .children
        .iter()
        .filter_map(XMLNode::as_element)
        .find(|c| {
            c.name == "device"
                && c.attributes
                    .get("category")
                    .map_or("default", String::as_str)
                    == cat
        })
}
fn ensure_device<'a>(e: &'a mut Element, cat: &str) -> &'a mut Element {
    let p = ensure(e, &["libinput"]);
    let i = if let Some(i) = p.children.iter().position(|n| {
        n.as_element().is_some_and(|c| {
            c.name == "device"
                && c.attributes
                    .get("category")
                    .map_or("default", String::as_str)
                    == cat
        })
    }) {
        i
    } else {
        let mut c = make(p, "device");
        c.attributes.insert("category".into(), cat.into());
        p.children.push(XMLNode::Element(c));
        p.children.len() - 1
    };
    p.children[i].as_mut_element().unwrap()
}
fn bool_value(s: &str) -> bool {
    ["yes", "true", "on", "1"].contains(&s.to_lowercase().as_str())
}
const BOOLS: &[(&str, &[&str], bool)] = &[
    ("adaptiveSync", &["core", "adaptiveSync"], false),
    ("allowTearing", &["core", "allowTearing"], false),
    ("hdr", &["core", "hdr"], false),
    (
        "xwaylandPersistence",
        &["core", "xwaylandPersistence"],
        false,
    ),
    ("followMouse", &["focus", "followMouse"], false),
    ("raiseOnFocus", &["focus", "raiseOnFocus"], false),
    ("reuseOutputMode", &["core", "reuseOutputMode"], false),
    ("snappingOverlay", &["snapping", "overlay", "enabled"], true),
    ("topMaximize", &["snapping", "topMaximize"], true),
];
pub fn data() -> Value {
    let mut d = json!({"configPath":dir().join("rc.xml"),"environmentPath":dir().join("environment"),"decoration":"server","gap":0,"adaptiveSync":false,"allowTearing":false,"hdr":false,"xwaylandPersistence":false,"placementPolicy":"cascade","followMouse":false,"raiseOnFocus":false,"repeatRate":25,"repeatDelay":600,"workspaceCount":1,"workspaceNames":["Default"],"keyboardLayout":"us","pointerSpeed":0.0,"accelProfile":"adaptive","naturalScroll":false,"tapToClick":true,"scrollFactor":1.0,"snappingEnabled":true,"snappingOverlay":true,"topMaximize":true,"reuseOutputMode":false});
    let layout_val = environment_layout();
    let layout = layout_val
        .split(',')
        .next()
        .unwrap_or("us");
    d["keyboardLayout"] = json!(layout);
    let Ok(root) = Element::parse(read(dir().join("rc.xml")).as_bytes()) else {
        return d;
    };
    d["keyboardLayout"] = json!(layout.to_lowercase());
    for &(key, path, fallback) in BOOLS {
        let raw = text(&root, path, if fallback { "yes" } else { "no" }).to_lowercase();
        d[key] = json!(
            bool_value(&raw)
                || (key == "adaptiveSync" && raw == "fullscreen")
                || (key == "allowTearing"
                    && ["fullscreen", "fullscreenforced"].contains(&raw.as_str()))
        );
    }
    for (key, path, fallback) in [
        ("decoration", ["core", "decoration"], "server"),
        ("placementPolicy", ["placement", "policy"], "cascade"),
        ("theme", ["theme", "name"], "Weylume"),
    ] {
        d[key] = json!(text(&root, &path, fallback));
    }
    for (key, path, fallback) in [
        ("gap", ["core", "gap"], 0),
        ("repeatRate", ["keyboard", "repeatRate"], 25),
        ("repeatDelay", ["keyboard", "repeatDelay"], 600),
    ] {
        d[key] = json!(text(&root, &path, &fallback.to_string())
            .parse::<i64>()
            .unwrap_or(fallback));
    }
    let default = Element::new("device");
    let pointer = device(&root, "non-touch").unwrap_or(&default);
    let touch = device(&root, "touchpad").unwrap_or(&default);
    for (key, fallback) in [("pointerSpeed", 0.), ("scrollFactor", 1.)] {
        d[key] = json!(text(pointer, &[key], &fallback.to_string())
            .parse::<f64>()
            .unwrap_or(fallback));
    }
    d["accelProfile"] = json!(text(pointer, &["accelProfile"], "adaptive"));
    d["naturalScroll"] = json!(bool_value(&text(pointer, &["naturalScroll"], "no")));
    d["tapToClick"] = json!(bool_value(&text(touch, &["tap"], "yes")));
    d["snappingEnabled"] = json!(
        text(&root, &["snapping", "range", "outer"], "10")
            .parse::<i64>()
            .unwrap_or(0)
            > 0
    );
    let count = child(&root, &["desktops"])
        .and_then(|e| e.attributes.get("number"))
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1)
        .clamp(1, 4096);
    let names: Vec<String> = child(&root, &["desktops", "names"])
        .map(|e| {
            e.children
                .iter()
                .filter_map(XMLNode::as_element)
                .filter(|e| e.name == "name")
                .map(|e| text(e, &[], ""))
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default();
    d["workspaceCount"] = json!(count.max(names.len()));
    d["workspaceNames"] = json!(if names.is_empty() {
        (1..=count).map(|i| format!("Workspace {i}")).collect()
    } else {
        names
    });
    d
}
fn keybinds(root: &mut Element, count: usize) {
    let keyboard = ensure(root, &["keyboard"]);
    for i in 1..=count.min(16) {
        let suffix = workspace_suffix(i);
        for (key, name) in [
            (format!("W-{suffix}"), "GoToDesktop"),
            (format!("W-S-{suffix}"), "SendToDesktop"),
        ] {
            if keyboard
                .children
                .iter()
                .filter_map(XMLNode::as_element)
                .any(|e| e.name == "keybind" && e.attributes.get("key") == Some(&key))
            {
                continue;
            }
            let mut bind = make(keyboard, "keybind");
            bind.attributes.insert("key".into(), key);
            let mut a = make(keyboard, "action");
            a.attributes.insert("name".into(), name.into());
            a.attributes.insert("to".into(), i.to_string());
            if name == "SendToDesktop" {
                a.attributes.insert("follow".into(), "no".into());
            }
            bind.children.push(XMLNode::Element(a));
            keyboard.children.push(XMLNode::Element(bind));
        }
    }
}
pub fn set(key: &str, raw: &str) -> Result<(bool, String, Value)> {
    let _lock = Lock::new(&dir().join(".weylume.lock"))?;
    struct Transaction {
        old: Vec<(PathBuf, Option<Vec<u8>>)>,
        committed: bool,
    }
    impl Drop for Transaction {
        fn drop(&mut self) {
            if !self.committed {
                for (p, old) in &self.old {
                    if let Some(bytes) = old {
                        let _ = atomic(p, bytes);
                    } else {
                        let _ = fs::remove_file(p);
                    }
                }
            }
        }
    }
    let mut transaction = Transaction {
        old: ["rc.xml", "environment"]
            .iter()
            .map(|name| {
                let p = dir().join(name);
                let b = fs::read(&p);
                match b {
                    Ok(v) => Ok((p, Some(v))),
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok((p, None)),
                    Err(e) => Err(e),
                }
            })
            .collect::<std::io::Result<_>>()?,
        committed: false,
    };
    let rc = dir().join("rc.xml");
    let raw_lower = raw.to_lowercase();
    let yes = if bool_value(raw) { "yes" } else { "no" };
    if key == "keyboardLayout" {
        if !(2..=16).contains(&raw.len())
            || !raw
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"_-".contains(&c))
        {
            return Err("Invalid keyboard layout".into());
        }
        set_env("XKB_DEFAULT_LAYOUT", &raw_lower)?;
    } else {
        let mut root = match fs::read(&rc) {
            Ok(b) => Element::parse(b.as_slice())
                .map_err(|e| format!("Labwc configuration is not valid XML: {e}"))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Element::new("labwc_config"),
            Err(e) => return Err(e.into()),
        };
        if root.name != "labwc_config" {
            return Err("Expected a labwc_config XML root; no configuration was changed".into());
        }
        if let Some((_, path, _)) = BOOLS.iter().find(|(k, _, _)| *k == key) {
            set_text(ensure(&mut root, path), yes.into());
            if key == "hdr" && yes == "yes" {
                set_env("WLR_RENDERER", "vulkan")?;
            }
        } else {
            match key {
                "naturalScroll" | "tapToClick" => {
                    let cat = if key == "tapToClick" {
                        "touchpad"
                    } else {
                        "non-touch"
                    };
                    let name = if key == "tapToClick" { "tap" } else { key };
                    set_text(ensure(ensure_device(&mut root, cat), &[name]), yes.into());
                }
                "accelProfile" => {
                    if !["flat", "adaptive"].contains(&raw_lower.as_str()) {
                        return Err("Acceleration profile must be flat or adaptive".into());
                    }
                    set_text(
                        ensure(ensure_device(&mut root, "non-touch"), &[key]),
                        raw_lower,
                    );
                }
                "pointerSpeed" | "scrollFactor" => {
                    let v = raw.parse::<f64>()?;
                    if !v.is_finite() {
                        return Err("Invalid number".into());
                    }
                    let (min, max) = if key == "pointerSpeed" {
                        (-1., 1.)
                    } else {
                        (0.1, 10.)
                    };
                    set_text(
                        ensure(ensure_device(&mut root, "non-touch"), &[key]),
                        v.clamp(min, max).to_string(),
                    );
                }
                "snappingEnabled" => {
                    for edge in ["inner", "outer"] {
                        set_text(
                            ensure(&mut root, &["snapping", "range", edge]),
                            if yes == "yes" { "10" } else { "0" }.into(),
                        );
                    }
                }
                "theme" => {
                    let name = if raw_lower.contains("light") || raw_lower == "false" {
                        "Weylume-Light"
                    } else {
                        "Weylume"
                    };
                    set_text(ensure(&mut root, &["theme", "name"]), name.into());
                }
                "decoration" | "placementPolicy" => {
                    let (outer, inner, choices) = if key == "decoration" {
                        ("core", "decoration", &["server", "client"][..])
                    } else {
                        (
                            "placement",
                            "policy",
                            &["cascade", "center", "automatic"][..],
                        )
                    };
                    if !choices.contains(&raw_lower.as_str()) {
                        return Err(format!("Invalid value for {key}").into());
                    }
                    set_text(ensure(&mut root, &[outer, inner]), raw_lower);
                }
                "gap" | "repeatRate" | "repeatDelay" => {
                    let (outer, min, max) = match key {
                        "gap" => ("core", 0, 200),
                        "repeatRate" => ("keyboard", 1, 100),
                        _ => ("keyboard", 100, 2000),
                    };
                    let v = raw.parse::<i64>()?.clamp(min, max);
                    set_text(ensure(&mut root, &[outer, key]), v.to_string());
                }
                "workspaceCount" => {
                    let v = raw.parse::<i64>()?.clamp(1, 16) as usize;
                    ensure(&mut root, &["desktops"])
                        .attributes
                        .insert("number".into(), v.to_string());
                    keybinds(&mut root, v);
                }
                "workspaceNames" => {
                    let names: Vec<_> = raw
                        .split(',')
                        .map(str::trim)
                        .filter(|s| !s.is_empty())
                        .take(16)
                        .collect();
                    if names.is_empty() {
                        return Err("At least one workspace name is required".into());
                    }
                    let p = ensure(&mut root, &["desktops", "names"]);
                    p.children.clear();
                    for name in &names {
                        let mut e = make(p, "name");
                        set_text(&mut e, (*name).into());
                        p.children.push(XMLNode::Element(e));
                    }
                    ensure(&mut root, &["desktops"])
                        .attributes
                        .insert("number".into(), names.len().to_string());
                    keybinds(&mut root, names.len());
                }
                _ => return Err(format!("Unsupported Labwc setting: {key}").into()),
            }
        }
        if rc.exists() {
            let _ = fs::copy(&rc, dir().join("rc.xml.weylume.bak"));
        }
        let mut bytes = Vec::new();
        root.write_with_config(
            &mut bytes,
            EmitterConfig::new()
                .perform_indent(true)
                .write_document_declaration(false),
        )?;
        bytes.push(b'\n');
        atomic(&rc, &bytes)?;
    }
    let (mut ok, mut msg) = run(&["labwc", "--reconfigure"]);
    if !ok && std::env::var("LABWC_PID").unwrap_or_default().is_empty() {
        ok = true;
        msg = "Saved; Labwc is not running in this session".into()
    }
    if msg.is_empty() {
        msg = "Configuration saved; Labwc reload requested".into()
    }
    if !ok {
        drop(transaction);
        let _ = run(&["labwc", "--reconfigure"]);
        return Ok((
            false,
            format!("Reload failed; previous configuration restored: {msg}"),
            data(),
        ));
    }
    transaction.committed = true;
    if key == "keyboardLayout" || key == "xwaylandPersistence" || key == "hdr" {
        msg.push_str("; environment-dependent changes require a new compositor session");
    }
    Ok((ok, msg, data()))
}

pub fn workspace_suffix(index: usize) -> String {
    match index {
        1..=9 => index.to_string(),
        10 => "0".into(),
        11..=16 => format!("F{}", index - 10),
        _ => String::new(),
    }
}
pub fn workspace_key(index: usize, send: bool) -> Result<String> {
    if !(1..=16).contains(&index) {
        return Err("Workspace must be between 1 and 16".into());
    }
    let state = data();
    if index > state["workspaceCount"].as_u64().unwrap_or(1) as usize {
        return Err("Workspace is not configured".into());
    }
    let suffix = workspace_suffix(index);
    let key = format!("W-{}{suffix}", if send { "S-" } else { "" });
    let expected = if send { "SendToDesktop" } else { "GoToDesktop" };
    let root = Element::parse(fs::File::open(dir().join("rc.xml"))?)?;
    let bind = child(&root, &["keyboard"])
        .and_then(|k| {
            k.children
                .iter()
                .filter_map(XMLNode::as_element)
                .find(|e| e.name == "keybind" && e.attributes.get("key") == Some(&key))
        })
        .ok_or("Set the workspace count in Labwc settings to install workspace bindings")?;
    if !bind
        .children
        .iter()
        .filter_map(XMLNode::as_element)
        .any(|a| {
            a.name == "action"
                && a.attributes.get("name").is_some_and(|n| n == expected)
                && (a
                    .attributes
                    .get("to")
                    .is_some_and(|t| t == &index.to_string())
                    || text(a, &["to"], "") == index.to_string())
        })
    {
        return Err(
            format!("Shortcut {key} belongs to a custom action; it was not overwritten").into(),
        );
    }
    Ok(suffix)
}
