//! ext-foreign-toplevel-list-v1 wire definitions, expressed in Rust.
//! Protocol copyright Ilia Bozhinov, Isaac Freund, wb9688 and i509VCB;
//! see PROTOCOL_LICENSE.md.
use crate::{bus::string, util::*, wayland::*};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    ffi::{c_char, c_void, CStr},
    fs,
    io::Read,
    ptr,
    time::{Duration, Instant},
};
static TYPES: Types<2> = Types([ptr::null(), &HANDLE]);
const fn message(name: &'static CStr, sig: &'static CStr, offset: usize) -> Message {
    Message {
        name: name.as_ptr(),
        signature: sig.as_ptr(),
        types: unsafe { TYPES.0.as_ptr().add(offset) },
    }
}
static LIST_METHODS: [Message; 2] = [message(c"stop", c"", 0), message(c"destroy", c"", 0)];
static LIST_EVENTS: [Message; 2] = [message(c"toplevel", c"n", 1), message(c"finished", c"", 0)];
static HANDLE_METHODS: [Message; 1] = [message(c"destroy", c"", 0)];
static HANDLE_EVENTS: [Message; 5] = [
    message(c"closed", c"", 0),
    message(c"done", c"", 0),
    message(c"title", c"s", 0),
    message(c"app_id", c"s", 0),
    message(c"identifier", c"s", 0),
];
static LIST: Interface = Interface {
    name: c"ext_foreign_toplevel_list_v1".as_ptr(),
    version: 1,
    method_count: 2,
    methods: LIST_METHODS.as_ptr(),
    event_count: 2,
    events: LIST_EVENTS.as_ptr(),
};
static HANDLE: Interface = Interface {
    name: c"ext_foreign_toplevel_handle_v1".as_ptr(),
    version: 1,
    method_count: 1,
    methods: HANDLE_METHODS.as_ptr(),
    event_count: 5,
    events: HANDLE_EVENTS.as_ptr(),
};
#[derive(Default)]
struct Window {
    handle: *mut c_void,
    title: String,
    app: String,
    id: String,
    closed: bool,
}
struct State {
    display: *mut c_void,
    registry: *mut c_void,
    list: *mut c_void,
    // Listener userdata must remain stable when the vector grows.
    #[allow(clippy::vec_box)]
    windows: Vec<Box<Window>>,
}
impl Drop for State {
    fn drop(&mut self) {
        unsafe {
            for w in &self.windows {
                wl_proxy_marshal_flags(w.handle, 0, ptr::null(), 1, 1);
            }
            if !self.list.is_null() {
                wl_proxy_marshal_flags(self.list, 1, ptr::null(), 1, 1);
            }
            if !self.registry.is_null() {
                wl_proxy_destroy(self.registry);
            }
            wl_display_disconnect(self.display);
        }
    }
}
unsafe extern "C" fn closed(data: *mut c_void, _: *mut c_void) {
    (*(data as *mut Window)).closed = true;
}
unsafe extern "C" fn noop(_: *mut c_void, _: *mut c_void) {}
unsafe extern "C" fn title(data: *mut c_void, _: *mut c_void, v: *const c_char) {
    (*(data as *mut Window)).title = string(v);
}
unsafe extern "C" fn app(data: *mut c_void, _: *mut c_void, v: *const c_char) {
    (*(data as *mut Window)).app = string(v);
}
unsafe extern "C" fn identifier(data: *mut c_void, _: *mut c_void, v: *const c_char) {
    (*(data as *mut Window)).id = string(v);
}
#[repr(C)]
struct HandleListener {
    closed: unsafe extern "C" fn(*mut c_void, *mut c_void),
    done: unsafe extern "C" fn(*mut c_void, *mut c_void),
    title: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
    app: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
    id: unsafe extern "C" fn(*mut c_void, *mut c_void, *const c_char),
}
static HANDLE_LISTENER: HandleListener = HandleListener {
    closed,
    done: noop,
    title,
    app,
    id: identifier,
};
unsafe extern "C" fn toplevel(data: *mut c_void, _: *mut c_void, handle: *mut c_void) {
    let state = &mut *(data as *mut State);
    let mut w = Box::new(Window {
        handle,
        ..Default::default()
    });
    wl_proxy_add_listener(
        handle,
        (&HANDLE_LISTENER as *const HandleListener).cast(),
        (&mut *w as *mut Window).cast(),
    );
    state.windows.push(w);
}
#[repr(C)]
struct ListListener {
    toplevel: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void),
    finished: unsafe extern "C" fn(*mut c_void, *mut c_void),
}
static LIST_LISTENER: ListListener = ListListener {
    toplevel,
    finished: noop,
};
unsafe extern "C" fn global(
    data: *mut c_void,
    registry: *mut c_void,
    name: u32,
    interface: *const c_char,
    version: u32,
) {
    if CStr::from_ptr(interface) != c"ext_foreign_toplevel_list_v1" {
        return;
    }
    let state = &mut *(data as *mut State);
    let version = version.min(1);
    state.list = wl_proxy_marshal_flags(
        registry,
        0,
        &LIST,
        version,
        0,
        name,
        LIST.name,
        version,
        ptr::null::<c_void>(),
    );
    wl_proxy_add_listener(
        state.list,
        (&LIST_LISTENER as *const ListListener).cast(),
        data,
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
    // Applies only to this short-lived helper; compositor stalls cannot leave
    // a preview request alive indefinitely. execute() kills capture children
    // when this parent exits.
    unsafe {
        libc::alarm(15);
    }
    let display = unsafe { wl_display_connect(ptr::null()) };
    if display.is_null() {
        return Err("Cannot connect to Wayland display".into());
    }
    let mut state = Box::new(State {
        display,
        registry: ptr::null_mut(),
        list: ptr::null_mut(),
        windows: Vec::new(),
    });
    unsafe {
        state.registry = wl_proxy_marshal_flags(
            display,
            1,
            &wl_registry_interface,
            wl_proxy_get_version(display),
            0,
            ptr::null::<c_void>(),
        );
        wl_proxy_add_listener(
            state.registry,
            (&REGISTRY_LISTENER as *const RegistryListener).cast(),
            (&mut *state as *mut State).cast(),
        );
        roundtrip(display)?;
        if state.list.is_null() {
            return Err("Compositor does not provide ext-foreign-toplevel-list-v1".into());
        }
        roundtrip(display)?;
    }
    Ok(state)
}
fn id_filename(id: &str) -> String {
    format!("{:x}.jpg", Sha256::digest(id.as_bytes()))
}
pub fn windows() -> Result<Value> {
    let state = connect()?;
    Ok(json!(state
        .windows
        .iter()
        .rev()
        .filter(|w| !w.closed && !w.id.is_empty())
        .take(256)
        .map(|w| json!({"id":w.id,"app":w.app,"title":w.title}))
        .collect::<Vec<_>>()))
}
pub fn main(args: &[String]) -> Result<()> {
    let mut raw = String::new();
    std::io::stdin().take(65537).read_to_string(&mut raw)?;
    if raw.len() > 65536 {
        return Err("Preview request too large".into());
    }
    let request: Vec<Value> = if raw.trim().is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&raw)?
    };
    if request.len() > 128 {
        return Err("Too many preview windows".into());
    }
    // Empty requests do not capture the entire desktop by accident.
    if request.is_empty() && !args.iter().any(|s| s == "--all") {
        return Ok(());
    }
    let dir = cache().join("weylume/previews");
    unsafe {
        libc::umask(0o077);
    }
    fs::create_dir_all(&dir)?;
    let _lock = Lock::new(&dir.join(".capture.lock"))?;
    let state = connect()?;
    let deadline = Instant::now() + Duration::from_secs(10);
    for (index, w) in state.windows.iter().rev().enumerate() {
        if w.closed
            || w.id.is_empty()
            || (!request.is_empty()
                && !request
                    .iter()
                    .any(|r| r["app"] == w.app && r["title"] == w.title))
        {
            continue;
        }
        let dest = dir.join(id_filename(&w.id));
        if Instant::now() < deadline {
            let temp = dir.join(format!(".capture-{}-{index}.jpg", std::process::id()));
            let seconds = deadline
                .saturating_duration_since(Instant::now())
                .as_secs()
                .clamp(1, 3);
            let (code, _, _) = execute(
                &[
                    "grim",
                    "-t",
                    "jpeg",
                    "-q",
                    "75",
                    "-T",
                    &w.id,
                    &temp.to_string_lossy(),
                ],
                seconds,
                None,
            );
            if code == 0 {
                fs::rename(&temp, &dest)?;
            } else {
                let _ = fs::remove_file(&temp);
            }
        }
        emit(
            &json!({"id":w.id,"app":w.app,"title":w.title,"path":if dest.exists(){dest.to_string_lossy().into_owned()}else{String::new()}}),
        )?;
    }
    unsafe {
        wl_proxy_marshal_flags(state.list, 0, ptr::null(), 1, 0);
        wl_display_flush(state.display);
        libc::alarm(0);
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stable_identity() {
        assert_ne!(id_filename("one"), id_filename("two"));
        assert_eq!(id_filename("one").len(), 68);
        assert_eq!(id_filename("one"), id_filename("one"));
    }
}
