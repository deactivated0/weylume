//! Native output snapshots and test/apply transactions, without wlr-randr.
use crate::{bus::string, output_protocol::*, util::*, wayland::*};
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_void, CStr},
    fs, ptr,
    sync::atomic::{AtomicI32, Ordering},
    time::Duration,
};
#[derive(Default)]
struct Mode {
    proxy: *mut c_void,
    width: i32,
    height: i32,
    refresh: i32,
    preferred: bool,
    gone: bool,
}
#[derive(Default)]
struct Head {
    proxy: *mut c_void,
    name: String,
    description: String,
    make: String,
    model: String,
    serial: String,
    enabled: bool,
    current: *mut c_void,
    x: i32,
    y: i32,
    transform: i32,
    scale: i32,
    adaptive_sync: u32,
    gone: bool,
    #[allow(clippy::vec_box)]
    modes: Vec<Box<Mode>>,
}
struct State {
    display: *mut c_void,
    registry: *mut c_void,
    manager: *mut c_void,
    serial: u32,
    version: u32,
    #[allow(clippy::vec_box)]
    heads: Vec<Box<Head>>,
}
impl Drop for State {
    fn drop(&mut self) {
        unsafe {
            for h in &self.heads {
                for m in &h.modes {
                    wl_proxy_destroy(m.proxy);
                }
                wl_proxy_destroy(h.proxy);
            }
            if !self.manager.is_null() {
                wl_proxy_destroy(self.manager);
            }
            if !self.registry.is_null() {
                wl_proxy_destroy(self.registry);
            }
            wl_display_disconnect(self.display);
        }
    }
}
unsafe extern "C" fn size(d: *mut c_void, _: *mut c_void, w: i32, h: i32) {
    let m = &mut *(d as *mut Mode);
    m.width = w;
    m.height = h;
}
unsafe extern "C" fn refresh(d: *mut c_void, _: *mut c_void, v: i32) {
    (*(d as *mut Mode)).refresh = v;
}
unsafe extern "C" fn preferred(d: *mut c_void, _: *mut c_void) {
    (*(d as *mut Mode)).preferred = true;
}
unsafe extern "C" fn mode_finished(d: *mut c_void, _: *mut c_void) {
    (*(d as *mut Mode)).gone = true;
}
#[repr(C)]
struct ModeListener {
    size: unsafe extern "C" fn(*mut c_void, *mut c_void, i32, i32),
    refresh: unsafe extern "C" fn(*mut c_void, *mut c_void, i32),
    preferred: unsafe extern "C" fn(*mut c_void, *mut c_void),
    finished: unsafe extern "C" fn(*mut c_void, *mut c_void),
}
static MODE_LISTENER: ModeListener = ModeListener {
    size,
    refresh,
    preferred,
    finished: mode_finished,
};
macro_rules! string_event {
    ($func:ident,$field:ident) => {
        unsafe extern "C" fn $func(d: *mut c_void, _: *mut c_void, v: *const c_char) {
            (*(d as *mut Head)).$field = string(v);
        }
    };
}
string_event!(name, name);
string_event!(description, description);
string_event!(make, make);
string_event!(model, model);
string_event!(serial_number, serial);
unsafe extern "C" fn physical(_: *mut c_void, _: *mut c_void, _: i32, _: i32) {}
unsafe extern "C" fn mode(d: *mut c_void, _: *mut c_void, p: *mut c_void) {
    let head = &mut *(d as *mut Head);
    let mut m = Box::new(Mode {
        proxy: p,
        ..Default::default()
    });
    wl_proxy_add_listener(
        p,
        (&MODE_LISTENER as *const ModeListener).cast(),
        (&mut *m as *mut Mode).cast(),
    );
    head.modes.push(m);
}
unsafe extern "C" fn enabled(d: *mut c_void, _: *mut c_void, v: i32) {
    (*(d as *mut Head)).enabled = v != 0;
}
unsafe extern "C" fn current(d: *mut c_void, _: *mut c_void, p: *mut c_void) {
    (*(d as *mut Head)).current = p;
}
unsafe extern "C" fn position(d: *mut c_void, _: *mut c_void, x: i32, y: i32) {
    let h = &mut *(d as *mut Head);
    h.x = x;
    h.y = y;
}
unsafe extern "C" fn transform(d: *mut c_void, _: *mut c_void, v: i32) {
    (*(d as *mut Head)).transform = v;
}
unsafe extern "C" fn scale(d: *mut c_void, _: *mut c_void, v: i32) {
    (*(d as *mut Head)).scale = v;
}
unsafe extern "C" fn head_finished(d: *mut c_void, _: *mut c_void) {
    (*(d as *mut Head)).gone = true;
}
unsafe extern "C" fn adaptive_sync(d: *mut c_void, _: *mut c_void, v: u32) {
    (*(d as *mut Head)).adaptive_sync = v;
}
#[repr(C)]
struct HeadListener {
    name: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
    description: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
    physical: unsafe extern "C" fn(*mut c_void, *mut c_void, i32, i32),
    mode: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void),
    enabled: unsafe extern "C" fn(*mut c_void, *mut c_void, i32),
    current: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void),
    position: unsafe extern "C" fn(*mut c_void, *mut c_void, i32, i32),
    transform: unsafe extern "C" fn(*mut c_void, *mut c_void, i32),
    scale: unsafe extern "C" fn(*mut c_void, *mut c_void, i32),
    finished: unsafe extern "C" fn(*mut c_void, *mut c_void),
    make: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
    model: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
    serial: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
    adaptive_sync: unsafe extern "C" fn(*mut c_void, *mut c_void, u32),
}
static HEAD_LISTENER: HeadListener = HeadListener {
    name,
    description,
    physical,
    mode,
    enabled,
    current,
    position,
    transform,
    scale,
    finished: head_finished,
    make,
    model,
    serial: serial_number,
    adaptive_sync,
};
unsafe extern "C" fn head(d: *mut c_void, _: *mut c_void, p: *mut c_void) {
    let state = &mut *(d as *mut State);
    let mut h = Box::new(Head {
        proxy: p,
        scale: 256,
        ..Default::default()
    });
    wl_proxy_add_listener(
        p,
        (&HEAD_LISTENER as *const HeadListener).cast(),
        (&mut *h as *mut Head).cast(),
    );
    state.heads.push(h);
}
unsafe extern "C" fn done(d: *mut c_void, _: *mut c_void, s: u32) {
    (*(d as *mut State)).serial = s;
}
unsafe extern "C" fn finished(_: *mut c_void, _: *mut c_void) {}
#[repr(C)]
struct ManagerListener {
    head: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void),
    done: unsafe extern "C" fn(*mut c_void, *mut c_void, u32),
    finished: unsafe extern "C" fn(*mut c_void, *mut c_void),
}
static MANAGER_LISTENER: ManagerListener = ManagerListener {
    head,
    done,
    finished,
};
unsafe extern "C" fn global(d: *mut c_void, r: *mut c_void, n: u32, i: *const c_char, v: u32) {
    if CStr::from_ptr(i) != c"zwlr_output_manager_v1" {
        return;
    }
    let s = &mut *(d as *mut State);
    s.version = v.min(4);
    s.manager = wl_proxy_marshal_flags(
        r,
        0,
        &ZWLR_OUTPUT_MANAGER_V1,
        s.version,
        0,
        n,
        ZWLR_OUTPUT_MANAGER_V1.name,
        s.version,
        ptr::null::<c_void>(),
    );
    wl_proxy_add_listener(
        s.manager,
        (&MANAGER_LISTENER as *const ManagerListener).cast(),
        d,
    );
}
unsafe extern "C" fn removed(_: *mut c_void, _: *mut c_void, _: u32) {}
#[repr(C)]
struct RegistryListener {
    global: unsafe extern "C" fn(*mut c_void, *mut c_void, u32, *const c_char, u32),
    removed: unsafe extern "C" fn(*mut c_void, *mut c_void, u32),
}
static REGISTRY_LISTENER: RegistryListener = RegistryListener { global, removed };
fn connect() -> Result<Box<State>> {
    unsafe {
        let display = wl_display_connect(ptr::null());
        if display.is_null() {
            return Err("Cannot connect to Wayland".into());
        }
        let mut s = Box::new(State {
            display,
            registry: ptr::null_mut(),
            manager: ptr::null_mut(),
            serial: 0,
            version: 0,
            heads: Vec::new(),
        });
        s.registry = wl_proxy_marshal_flags(
            display,
            1,
            &wl_registry_interface,
            1,
            0,
            ptr::null::<c_void>(),
        );
        wl_proxy_add_listener(
            s.registry,
            (&REGISTRY_LISTENER as *const RegistryListener).cast(),
            (&mut *s as *mut State).cast(),
        );
        roundtrip(display)?;
        if s.manager.is_null() {
            return Err("Compositor does not support wlr-output-management".into());
        }
        roundtrip(display)?;
        Ok(s)
    }
}
fn snapshot(s: &State) -> Value {
    json!(s.heads.iter().filter(|h|!h.gone).map(|h|{
 let current=h.modes.iter().find(|m|m.proxy==h.current&&!m.gone);
 json!({"name":h.name,"description":h.description,"make":h.make,"model":h.model,"serial":h.serial,"enabled":h.enabled,"x":h.x,"y":h.y,"scale":h.scale as f64/256.,"transform":h.transform,"adaptiveSync":if s.version>=4{Some(h.adaptive_sync!=0)}else{None},"width":current.map_or(0,|m|m.width),"height":current.map_or(0,|m|m.height),"refresh":current.map_or(0,|m|m.refresh),"modes":h.modes.iter().filter(|m|!m.gone).map(|m|json!({"width":m.width,"height":m.height,"refresh":m.refresh,"preferred":m.preferred})).collect::<Vec<_>>()})
}).collect::<Vec<_>>())
}
pub fn data() -> Result<Value> {
    Ok(snapshot(&*connect()?))
}
unsafe extern "C" fn succeeded(d: *mut c_void, _: *mut c_void) {
    if !d.is_null() {
        (&*(d as *const AtomicI32)).store(1, Ordering::SeqCst);
    }
}
unsafe extern "C" fn failed(d: *mut c_void, _: *mut c_void) {
    if !d.is_null() {
        (&*(d as *const AtomicI32)).store(-1, Ordering::SeqCst);
    }
}
unsafe extern "C" fn cancelled(d: *mut c_void, _: *mut c_void) {
    if !d.is_null() {
        (&*(d as *const AtomicI32)).store(-2, Ordering::SeqCst);
    }
}
#[repr(C)]
struct ConfigListener {
    ok: unsafe extern "C" fn(*mut c_void, *mut c_void),
    failed: unsafe extern "C" fn(*mut c_void, *mut c_void),
    cancelled: unsafe extern "C" fn(*mut c_void, *mut c_void),
}
static CONFIG_LISTENER: ConfigListener = ConfigListener {
    ok: succeeded,
    failed,
    cancelled,
};
struct Configuration {
    proxy: *mut c_void,
    heads: Vec<*mut c_void>,
}
impl Drop for Configuration {
    fn drop(&mut self) {
        unsafe {
            for h in &self.heads {
                wl_proxy_destroy(*h);
            }
            wl_proxy_marshal_flags(
                self.proxy,
                4,
                ptr::null(),
                wl_proxy_get_version(self.proxy),
                1,
            );
        }
    }
}
fn validate(request: &Value) -> Result<&Vec<Value>> {
    let items = request
        .as_array()
        .filter(|v| !v.is_empty() && v.len() <= 32)
        .ok_or("Expected 1–32 output entries")?;
    if !items.iter().any(|v| v["enabled"] == true) {
        return Err("At least one display must stay enabled".into());
    }
    let mut names = std::collections::HashSet::new();
    for item in items {
        let name = item["name"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or("Missing output name")?;
        if !names.insert(name) {
            return Err("Duplicate output name".into());
        }
        if !item["enabled"].is_boolean() {
            return Err("Missing or invalid output enabled state".into());
        }
        if item["enabled"] != true {
            continue;
        }
        for key in ["x", "y", "transform"] {
            if item.get(key).is_some() && item[key].as_i64().is_none() {
                return Err(format!("Invalid integer for {key}").into());
            }
        }
        if item.get("scale").is_some() && !item["scale"].is_number() {
            return Err("Invalid display scale".into());
        }
        let scale = item["scale"].as_f64().unwrap_or(1.);
        if !scale.is_finite() || !(0.25..=8.).contains(&scale) {
            return Err("Invalid display scale".into());
        }
        for key in ["x", "y"] {
            if !(-32768..=32767).contains(&item[key].as_i64().unwrap_or(0)) {
                return Err("Invalid output position".into());
            }
        }
        if !(0..=7).contains(&item["transform"].as_i64().unwrap_or(0)) {
            return Err("Invalid output transform".into());
        }
    }
    Ok(items)
}
fn configure(s: &mut State, request: &Value, test: bool) -> Result<()> {
    let items = validate(request)?;
    for item in items {
        if !s.heads.iter().any(|h| !h.gone && item["name"] == h.name) {
            return Err("Display set changed; refresh before applying".into());
        }
    }
    unsafe {
        let proxy = wl_proxy_marshal_flags(
            s.manager,
            0,
            &ZWLR_OUTPUT_CONFIGURATION_V1,
            s.version,
            0,
            ptr::null::<c_void>(),
            s.serial,
        );
        let mut config = Configuration {
            proxy,
            heads: Vec::new(),
        };
        let result = AtomicI32::new(0);
        wl_proxy_add_listener(
            proxy,
            (&CONFIG_LISTENER as *const ConfigListener).cast(),
            &result as *const AtomicI32 as *mut c_void,
        );
        for h in s.heads.iter().filter(|h| !h.gone) {
            let item = items
                .iter()
                .find(|i| i["name"] == h.name)
                .ok_or("Profile does not cover all connected displays")?;
            if item["enabled"] != true {
                wl_proxy_marshal_flags(proxy, 1, ptr::null(), s.version, 0, h.proxy);
                continue;
            }
            let mode = h
                .modes
                .iter()
                .find(|m| {
                    !m.gone
                        && item["width"] == m.width
                        && item["height"] == m.height
                        && item["refresh"] == m.refresh
                })
                .ok_or("Requested display mode is not advertised")?;
            let c = wl_proxy_marshal_flags(
                proxy,
                0,
                &ZWLR_OUTPUT_CONFIGURATION_HEAD_V1,
                s.version,
                0,
                ptr::null::<c_void>(),
                h.proxy,
            );
            config.heads.push(c);
            wl_proxy_marshal_flags(c, 0, ptr::null(), s.version, 0, mode.proxy);
            wl_proxy_marshal_flags(
                c,
                2,
                ptr::null(),
                s.version,
                0,
                item["x"].as_i64().unwrap_or(0) as i32,
                item["y"].as_i64().unwrap_or(0) as i32,
            );
            wl_proxy_marshal_flags(
                c,
                3,
                ptr::null(),
                s.version,
                0,
                item["transform"].as_i64().unwrap_or(0) as i32,
            );
            wl_proxy_marshal_flags(
                c,
                4,
                ptr::null(),
                s.version,
                0,
                (item["scale"].as_f64().unwrap_or(1.) * 256.).round() as i32,
            );
            if let Some(vrr) = item["adaptiveSync"].as_bool() {
                if s.version < 4 {
                    return Err("Compositor does not expose per-output VRR".into());
                }
                wl_proxy_marshal_flags(c, 5, ptr::null(), s.version, 0, u32::from(vrr));
            }
        }
        wl_proxy_marshal_flags(proxy, if test { 3 } else { 2 }, ptr::null(), s.version, 0);
        wait_for(s.display, Duration::from_secs(5), || result.load(Ordering::SeqCst) != 0)?;
        let res = result.load(Ordering::SeqCst);
        if res != 1 {
            return Err(match res {
                -2 => "Display configuration cancelled by hotplug",
                -1 => "Display configuration rejected",
                _ => "Display configuration acknowledgement timed out",
            }
            .into());
        }
    }
    Ok(())
}
fn journal() -> std::path::PathBuf {
    cache().join("weylume/output-rollback.json")
}
fn restore_unlocked() -> Result<bool> {
    let previous = json_file(journal());
    if !previous.is_array() {
        return Ok(false);
    }
    let mut s = connect()?;
    configure(&mut s, &previous, true)?;
    configure(&mut s, &previous, false)?;
    fs::remove_file(journal())?;
    Ok(true)
}
pub fn apply(request: Value) -> Result<()> {
    let _lock = Lock::try_new(&cache().join("weylume/.outputs.lock"))?;
    let mut s = connect()?;
    let previous = snapshot(&s);
    configure(&mut s, &request, true)?;
    save_json(&journal(), &previous)?;
    if let Err(e) = configure(&mut s, &request, false) {
        if configure(&mut s, &previous, false).is_ok() {
            let _ = fs::remove_file(journal());
        }
        return Err(e);
    }
    emit(&json!({"type":"applied","data":snapshot(&s),"confirmationSeconds":15}))?;
    let mut fd = libc::pollfd {
        fd: 0,
        events: libc::POLLIN,
        revents: 0,
    };
    let mut accepted = false;
    if unsafe { libc::poll(&mut fd, 1, 15000) } > 0 && fd.revents & libc::POLLIN != 0 {
        let mut bytes = [0u8; 32];
        let n = unsafe { libc::read(0, bytes.as_mut_ptr().cast(), bytes.len()) };
        accepted =
            n > 0 && std::str::from_utf8(&bytes[..n as usize]).is_ok_and(|s| s.trim() == "keep");
    }
    if accepted {
        fs::remove_file(journal())?;
        emit(&json!({"type":"finished","ok":true,"message":"Display configuration kept"}))?;
    } else {
        unsafe {
            roundtrip(s.display)?;
        }
        configure(&mut s, &previous, true)?;
        configure(&mut s, &previous, false)?;
        fs::remove_file(journal())?;
        emit(&json!({"type":"finished","ok":false,"message":"Display configuration reverted"}))?;
    }
    Ok(())
}
pub fn save_profile(name: &str) -> Result<Value> {
    if name.trim().is_empty() || name.len() > 80 {
        return Err("Use a profile name of 1–80 characters".into());
    }
    let path = shell().join("output_profiles.json");
    let _lock = Lock::new(&shell().join(".outputs-store.lock"))?;
    let mut profiles = json_file(&path);
    if !profiles.is_object() {
        profiles = json!({});
    }
    profiles[name] = data()?;
    save_json(&path, &profiles)?;
    Ok(profiles)
}
pub fn profile(name: &str) -> Result<Value> {
    let profiles = json_file(shell().join("output_profiles.json"));
    profiles
        .get(name)
        .cloned()
        .ok_or("Output profile not found".into())
}

pub fn restore() -> Result<bool> {
    let _lock = Lock::try_new(&cache().join("weylume/.outputs.lock"))?;
    restore_unlocked()
}
pub fn apply_stdin() -> Result<()> {
    use std::io::{BufRead, Read};
    let mut input = String::new();
    std::io::stdin()
        .lock()
        .take(128 * 1024 + 1)
        .read_line(&mut input)?;
    if input.len() > 128 * 1024 {
        return Err("Display request too large".into());
    }
    apply(serde_json::from_str(&input)?)
}

pub fn same_layout(a: &Value, b: &Value) -> bool {
    let (Some(a), Some(b)) = (a.as_array(), b.as_array()) else {
        return false;
    };
    a.len() == b.len()
        && a.iter().all(|a| {
            b.iter().any(|b| {
                a["name"] == b["name"]
                    && [
                        "enabled",
                        "width",
                        "height",
                        "refresh",
                        "x",
                        "y",
                        "scale",
                        "transform",
                        "adaptiveSync",
                    ]
                    .iter()
                    .all(|key| a[*key] == b[*key])
            })
        })
}
pub fn set_layout(request: &Value) -> Result<()> {
    let _lock = Lock::try_new(&cache().join("weylume/.outputs.lock"))?;
    let mut s = connect()?;
    configure(&mut s, request, true)?;
    configure(&mut s, request, false)
}
pub fn game_profile(name: &str) -> Result<Value> {
    let desired = profile(name)?;
    let current = data()?;
    let items = validate(&desired)?;
    if items.len() != current.as_array().map_or(0, Vec::len)
        || !items.iter().all(|p| {
            current.as_array().unwrap().iter().any(|c| {
                ["name", "make", "model", "serial"]
                    .iter()
                    .all(|key| p[*key] == c[*key])
            })
        })
    {
        return Err("Gaming output profile does not match the connected displays".into());
    }
    Ok(json!({"previous":current,"desired":desired}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reject_black_screen_and_invalid_profiles() {
        assert!(validate(&json!([{ "name":"DP-1","enabled":false}])).is_err());
        assert!(validate(&json!([{ "name":"DP-1","enabled":true,"scale":0}])).is_err());
        assert!(validate(&json!([{ "name":"DP-1","enabled":true,"scale":1,"x":-1920}])).is_ok());
    }
}
