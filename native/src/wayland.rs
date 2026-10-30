//! Minimal libwayland-client ABI shared by on-demand protocol helpers.
use crate::util::Result;
use std::{
    ffi::{c_char, c_int, c_void},
    ptr,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};
#[repr(C)]
pub struct Message {
    pub name: *const c_char,
    pub signature: *const c_char,
    pub types: *const *const Interface,
}
#[repr(C)]
pub struct Interface {
    pub name: *const c_char,
    pub version: c_int,
    pub method_count: c_int,
    pub methods: *const Message,
    pub event_count: c_int,
    pub events: *const Message,
}
unsafe impl Sync for Message {}
unsafe impl Sync for Interface {}
pub struct Types<const N: usize>(pub [*const Interface; N]);
unsafe impl<const N: usize> Sync for Types<N> {}
#[link(
    name = "libwayland-client.so.0",
    kind = "dylib",
    modifiers = "+verbatim"
)]
extern "C" {
    pub static wl_registry_interface: Interface;
    static wl_callback_interface: Interface;
    pub fn wl_display_connect(n: *const c_char) -> *mut c_void;
    pub fn wl_display_disconnect(d: *mut c_void);
    pub fn wl_display_flush(d: *mut c_void) -> c_int;
    pub fn wl_proxy_add_listener(p: *mut c_void, l: *const c_void, data: *mut c_void) -> c_int;
    pub fn wl_proxy_marshal_flags(
        p: *mut c_void,
        op: u32,
        i: *const Interface,
        v: u32,
        flags: u32,
        ...
    ) -> *mut c_void;
    pub fn wl_proxy_get_version(p: *mut c_void) -> u32;
    pub fn wl_proxy_destroy(p: *mut c_void);
    fn wl_display_get_fd(d: *mut c_void) -> c_int;
    fn wl_display_prepare_read(d: *mut c_void) -> c_int;
    fn wl_display_read_events(d: *mut c_void) -> c_int;
    fn wl_display_cancel_read(d: *mut c_void);
    fn wl_display_dispatch_pending(d: *mut c_void) -> c_int;
}
unsafe extern "C" fn done(data: *mut c_void, _: *mut c_void, _: u32) {
    if !data.is_null() {
        (&*(data as *const AtomicBool)).store(true, Ordering::SeqCst);
    }
}
#[repr(C)]
struct Callback {
    done: unsafe extern "C" fn(*mut c_void, *mut c_void, u32),
}
static CALLBACK: Callback = Callback { done };
pub unsafe fn wait_for(
    display: *mut c_void,
    timeout: Duration,
    ready: impl Fn() -> bool,
) -> Result<()> {
    let end = Instant::now() + timeout;
    while !ready() {
        if wl_display_dispatch_pending(display) < 0 {
            return Err("Wayland connection closed".into());
        }
        if ready() {
            break;
        }
        if Instant::now() >= end {
            return Err("Wayland acknowledgement timed out".into());
        }
        if wl_display_prepare_read(display) != 0 {
            continue;
        }
        let flush = wl_display_flush(display);
        if flush < 0 && std::io::Error::last_os_error().raw_os_error() != Some(libc::EAGAIN) {
            wl_display_cancel_read(display);
            return Err("Wayland flush failed".into());
        }
        let mut fd = libc::pollfd {
            fd: wl_display_get_fd(display),
            events: libc::POLLIN | if flush < 0 { libc::POLLOUT } else { 0 },
            revents: 0,
        };
        let timeout = end
            .saturating_duration_since(Instant::now())
            .as_millis()
            .min(i32::MAX as u128) as i32;
        let n = libc::poll(&mut fd, 1, timeout);
        if n <= 0 {
            wl_display_cancel_read(display);
            if n < 0 && std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err("Wayland synchronization timed out".into());
        }
        if fd.revents & libc::POLLIN != 0 {
            if wl_display_read_events(display) < 0 {
                return Err("Wayland read failed".into());
            }
        } else {
            wl_display_cancel_read(display);
            if fd.revents & (libc::POLLERR | libc::POLLHUP) != 0 {
                return Err("Wayland disconnected".into());
            }
        }
    }
    Ok(())
}
pub unsafe fn roundtrip(display: *mut c_void) -> Result<()> {
    let complete = AtomicBool::new(false);
    let callback = wl_proxy_marshal_flags(
        display,
        0,
        &wl_callback_interface,
        1,
        0,
        ptr::null::<c_void>(),
    );
    if callback.is_null() {
        return Err("Cannot create Wayland synchronization callback".into());
    }
    wl_proxy_add_listener(
        callback,
        (&CALLBACK as *const Callback).cast(),
        &complete as *const AtomicBool as *mut c_void,
    );
    let result = wait_for(display, Duration::from_secs(3), || complete.load(Ordering::SeqCst));
    wl_proxy_destroy(callback);
    result
}
