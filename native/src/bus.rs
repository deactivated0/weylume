//! Small sd-bus wrapper; uses the system library already shipped with systemd.
use crate::util::Result;
use std::{
    ffi::{c_char, c_int, c_void, CStr, CString},
    ptr,
};
#[link(name = "libsystemd.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn sd_bus_open_user(p: *mut *mut c_void) -> c_int;
    fn sd_bus_unref(p: *mut c_void) -> *mut c_void;
    fn sd_bus_get_property_trivial(
        b: *mut c_void,
        d: *const c_char,
        p: *const c_char,
        i: *const c_char,
        n: *const c_char,
        e: *mut c_void,
        t: c_char,
        v: *mut c_void,
    ) -> c_int;
    fn sd_bus_set_property(
        b: *mut c_void,
        d: *const c_char,
        p: *const c_char,
        i: *const c_char,
        n: *const c_char,
        e: *mut c_void,
        s: *const c_char,
        ...
    ) -> c_int;
    fn sd_bus_message_new_method_call(
        b: *mut c_void,
        m: *mut *mut c_void,
        d: *const c_char,
        p: *const c_char,
        i: *const c_char,
        n: *const c_char,
    ) -> c_int;
    fn sd_bus_message_append(m: *mut c_void, t: *const c_char, ...) -> c_int;
    fn sd_bus_message_open_container(m: *mut c_void, t: c_char, c: *const c_char) -> c_int;
    fn sd_bus_message_close_container(m: *mut c_void) -> c_int;
    fn sd_bus_message_set_expect_reply(m: *mut c_void, b: c_int) -> c_int;
    fn sd_bus_send(b: *mut c_void, m: *mut c_void, c: *mut u64) -> c_int;
    fn sd_bus_flush(b: *mut c_void) -> c_int;
    fn sd_bus_message_unref(m: *mut c_void) -> *mut c_void;
}
pub struct Bus(pub(crate) *mut c_void);
impl Drop for Bus {
    fn drop(&mut self) {
        unsafe {
            sd_bus_unref(self.0);
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
impl Bus {
    pub fn user() -> Result<Self> {
        let mut p = ptr::null_mut();
        check(unsafe { sd_bus_open_user(&mut p) })?;
        Ok(Self(p))
    }
    pub fn brightness(&self) -> Result<f64> {
        let mut v = 0f64;
        check(unsafe {
            sd_bus_get_property_trivial(
                self.0,
                c"rs.wl-gammarelay".as_ptr(),
                c"/".as_ptr(),
                c"rs.wl.gammarelay".as_ptr(),
                c"Brightness".as_ptr(),
                ptr::null_mut(),
                b'd' as c_char,
                (&mut v as *mut f64).cast(),
            )
        })?;
        Ok(v)
    }
    pub fn gamma(&self, name: &str, value: f64) -> Result<()> {
        let name = CString::new(name)?;
        let signature = if name.as_c_str() == c"Brightness" {
            c"d"
        } else {
            c"q"
        };
        check(unsafe {
            if signature == c"d" {
                sd_bus_set_property(
                    self.0,
                    c"rs.wl-gammarelay".as_ptr(),
                    c"/".as_ptr(),
                    c"rs.wl.gammarelay".as_ptr(),
                    name.as_ptr(),
                    ptr::null_mut(),
                    signature.as_ptr(),
                    value,
                )
            } else {
                sd_bus_set_property(
                    self.0,
                    c"rs.wl-gammarelay".as_ptr(),
                    c"/".as_ptr(),
                    c"rs.wl.gammarelay".as_ptr(),
                    name.as_ptr(),
                    ptr::null_mut(),
                    signature.as_ptr(),
                    value as c_int,
                )
            }
        })
    }
    pub fn notify(&self, app: &str, title: &str, body: &str, icon: &str) -> Result<()> {
        let vals = [app, icon, title, body].map(CString::new);
        let [app, icon, title, body] = vals;
        let (app, icon, title, body) = (app?, icon?, title?, body?);
        let mut m = ptr::null_mut();
        check(unsafe {
            sd_bus_message_new_method_call(
                self.0,
                &mut m,
                c"org.freedesktop.Notifications".as_ptr(),
                c"/org/freedesktop/Notifications".as_ptr(),
                c"org.freedesktop.Notifications".as_ptr(),
                c"Notify".as_ptr(),
            )
        })?;
        struct Msg(*mut c_void);
        impl Drop for Msg {
            fn drop(&mut self) {
                unsafe {
                    sd_bus_message_unref(self.0);
                }
            }
        }
        let _msg = Msg(m);
        unsafe {
            check(sd_bus_message_append(
                m,
                c"susss".as_ptr(),
                app.as_ptr(),
                0u32,
                icon.as_ptr(),
                title.as_ptr(),
                body.as_ptr(),
            ))?;
            check(sd_bus_message_open_container(
                m,
                b'a' as c_char,
                c"s".as_ptr(),
            ))?;
            check(sd_bus_message_close_container(m))?;
            check(sd_bus_message_open_container(
                m,
                b'a' as c_char,
                c"{sv}".as_ptr(),
            ))?;
            check(sd_bus_message_open_container(
                m,
                b'e' as c_char,
                c"sv".as_ptr(),
            ))?;
            check(sd_bus_message_append(m, c"s".as_ptr(), c"urgency".as_ptr()))?;
            check(sd_bus_message_open_container(
                m,
                b'v' as c_char,
                c"y".as_ptr(),
            ))?;
            check(sd_bus_message_append(m, c"y".as_ptr(), 1 as c_int))?;
            check(sd_bus_message_close_container(m))?;
            check(sd_bus_message_close_container(m))?;
            check(sd_bus_message_close_container(m))?;
            check(sd_bus_message_append(m, c"i".as_ptr(), -1 as c_int))?;
            check(sd_bus_message_set_expect_reply(m, 0))?;
            check(sd_bus_send(self.0, m, ptr::null_mut()))?;
            check(sd_bus_flush(self.0))
        }
    }
}
pub fn gamma(name: &str, v: f64) -> (bool, String) {
    let set = || Bus::user()?.gamma(name, v);
    match set() {
        Ok(()) => (true, String::new()),
        Err(e) => {
            if crate::util::has("wl-gammarelay-rs") {
                crate::util::spawn(&["wl-gammarelay-rs", "run"]);
                std::thread::sleep(std::time::Duration::from_millis(150));
                match set() {
                    Ok(()) => (true, String::new()),
                    Err(e) => (false, e.to_string()),
                }
            } else {
                (false, e.to_string())
            }
        }
    }
}
pub unsafe fn string(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

#[link(name = "libsystemd.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn sd_bus_message_get_path(m: *mut c_void) -> *const c_char;
    fn sd_bus_message_get_member(m: *mut c_void) -> *const c_char;
    fn sd_bus_open_system(p: *mut *mut c_void) -> c_int;
    fn sd_bus_get_fd(b: *mut c_void) -> c_int;
    fn sd_bus_process(b: *mut c_void, m: *mut *mut c_void) -> c_int;
    fn sd_bus_add_match(
        b: *mut c_void,
        s: *mut *mut c_void,
        pattern: *const c_char,
        callback: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void) -> c_int,
        data: *mut c_void,
    ) -> c_int;
}
unsafe extern "C" fn network_changed(m: *mut c_void, data: *mut c_void, _: *mut c_void) -> c_int {
    let path = string(sd_bus_message_get_path(m));
    let member = string(sd_bus_message_get_member(m));
    if member == "PrepareForSleep" || member == "PrepareForShutdown" {
        if let Ok(Some(sleeping)) = crate::dbus::read_value(m, 0) {
            let _ =
                crate::util::emit(&serde_json::json!({"type":"prepare-sleep","sleeping":sleeping}));
        }
        return 0;
    }
    // AP strength/LastSeen telemetry does not justify a full network snapshot.
    // Refresh connection, address and device state from events.
    if member == "NameOwnerChanged"
        || member == "StateChanged"
        || member == "VpnStateChanged"
        || path == "/org/freedesktop/NetworkManager"
        || path.starts_with("/org/freedesktop/NetworkManager/Settings")
        || path.starts_with("/org/freedesktop/NetworkManager/Devices/")
        || path.starts_with("/org/freedesktop/NetworkManager/IP")
        || path.starts_with("/org/freedesktop/NetworkManager/ActiveConnection/")
    {
        *(data as *mut bool) = true;
    }
    0
}
pub struct NetworkBus {
    bus: Bus,
    changed: Box<bool>,
}
impl NetworkBus {
    pub fn new() -> Result<Self> {
        let mut ptr = ptr::null_mut();
        check(unsafe { sd_bus_open_system(&mut ptr) })?;
        let mut s = Self {
            bus: Bus(ptr),
            changed: Box::new(false),
        };
        for rule in [c"type='signal',sender='org.freedesktop.NetworkManager'",c"type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.freedesktop.NetworkManager'"]{check(unsafe{sd_bus_add_match(s.bus.0,ptr::null_mut(),rule.as_ptr(),network_changed,(&mut *s.changed as *mut bool).cast())})?;}
        check(unsafe {
            sd_bus_add_match(s.bus.0,ptr::null_mut(),c"type='signal',sender='org.freedesktop.login1',path='/org/freedesktop/login1',interface='org.freedesktop.login1.Manager'".as_ptr(),network_changed,(&mut *s.changed as *mut bool).cast())
        })?;
        Ok(s)
    }
    pub fn inhibit(&self) -> Result<std::os::fd::OwnedFd> {
        self.bus.sleep_inhibitor()
    }
    pub fn fd(&self) -> i32 {
        unsafe { sd_bus_get_fd(self.bus.0) }
    }
    pub fn process(&mut self) -> Result<bool> {
        loop {
            let n = unsafe { sd_bus_process(self.bus.0, ptr::null_mut()) };
            check(n)?;
            if n == 0 {
                break;
            }
        }
        let changed = *self.changed;
        *self.changed = false;
        Ok(changed)
    }
}

// Asynchronous gamma calls share the resident backend. Keep callback userdata
// stable until its slot is removed, and include D-Bus deadlines in poll().
#[link(name = "libsystemd.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn sd_bus_get_events(b: *mut c_void) -> c_int;
    fn sd_bus_get_timeout(b: *mut c_void, usec: *mut u64) -> c_int;
    fn sd_bus_call_async(
        b: *mut c_void,
        slot: *mut *mut c_void,
        m: *mut c_void,
        callback: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void) -> c_int,
        data: *mut c_void,
        usec: u64,
    ) -> c_int;
    fn sd_bus_slot_unref(slot: *mut c_void) -> *mut c_void;
    fn sd_bus_message_is_method_error(m: *mut c_void, name: *const c_char) -> c_int;
}
struct GammaRequest {
    id: u64,
    slot: *mut c_void,
    done: bool,
}
impl Drop for GammaRequest {
    fn drop(&mut self) {
        unsafe {
            sd_bus_slot_unref(self.slot);
        }
    }
}
pub fn gamma_reply(id: u64, ok: bool) {
    let _ = crate::util::emit(&serde_json::json!({"type":"gamma", "id":id, "ok":ok}));
}
unsafe extern "C" fn gamma_finished(m: *mut c_void, data: *mut c_void, _: *mut c_void) -> c_int {
    let request = &mut *(data as *mut GammaRequest);
    request.done = true;
    gamma_reply(
        request.id,
        sd_bus_message_is_method_error(m, ptr::null()) == 0,
    );
    1
}
pub struct GammaBus {
    // Requests/slots must be dropped before the connection and cannot move while
    // libsystemd holds their userdata addresses.
    #[allow(clippy::vec_box)]
    pending: Vec<Box<GammaRequest>>,
    bus: Bus,
}
impl Drop for GammaBus {
    fn drop(&mut self) {
        for request in &self.pending {
            if !request.done {
                gamma_reply(request.id, false);
            }
        }
    }
}
impl GammaBus {
    pub fn new() -> Result<Self> {
        Ok(Self {
            pending: Vec::with_capacity(2),
            bus: Bus::user()?,
        })
    }
    pub fn set(&mut self, id: u64, name: &str, value: f64) -> Result<()> {
        self.pending.retain(|r| !r.done);
        if self.pending.len() >= 2
            || !value.is_finite()
            || !(name == "Brightness" || name == "Temperature")
        {
            return Err("Invalid or busy gamma request".into());
        }
        let name = CString::new(name)?;
        let signature = if name.as_c_str() == c"Brightness" {
            c"d"
        } else {
            c"q"
        };
        let mut m = ptr::null_mut();
        unsafe {
            check(sd_bus_message_new_method_call(
                self.bus.0,
                &mut m,
                c"rs.wl-gammarelay".as_ptr(),
                c"/".as_ptr(),
                c"org.freedesktop.DBus.Properties".as_ptr(),
                c"Set".as_ptr(),
            ))?;
        }
        struct Message(*mut c_void);
        impl Drop for Message {
            fn drop(&mut self) {
                unsafe {
                    sd_bus_message_unref(self.0);
                }
            }
        }
        let _message = Message(m);
        let mut request = Box::new(GammaRequest {
            id,
            slot: ptr::null_mut(),
            done: false,
        });
        unsafe {
            check(sd_bus_message_append(
                m,
                c"ss".as_ptr(),
                c"rs.wl.gammarelay".as_ptr(),
                name.as_ptr(),
            ))?;
            check(sd_bus_message_open_container(
                m,
                b'v' as c_char,
                signature.as_ptr(),
            ))?;
            if signature == c"d" {
                check(sd_bus_message_append(m, signature.as_ptr(), value))?;
            } else {
                check(sd_bus_message_append(m, signature.as_ptr(), value as c_int))?;
            }
            check(sd_bus_message_close_container(m))?;
            check(sd_bus_call_async(
                self.bus.0,
                &mut request.slot,
                m,
                gamma_finished,
                (&mut *request as *mut GammaRequest).cast(),
                0,
            ))?;
        }
        self.pending.push(request);
        Ok(())
    }
    pub fn poll_state(&self) -> Result<(libc::pollfd, i32)> {
        let fd = unsafe { sd_bus_get_fd(self.bus.0) };
        check(fd)?;
        let events = unsafe { sd_bus_get_events(self.bus.0) };
        check(events)?;
        let mut deadline = u64::MAX;
        check(unsafe { sd_bus_get_timeout(self.bus.0, &mut deadline) })?;
        let mut now: libc::timespec = unsafe { std::mem::zeroed() };
        if unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut now) } < 0 {
            return Err(std::io::Error::last_os_error().into());
        }
        let now = (now.tv_sec as u64).saturating_mul(1_000_000) + now.tv_nsec as u64 / 1000;
        let wait = deadline
            .saturating_sub(now)
            .div_ceil(1000)
            .min(i32::MAX as u64) as i32;
        Ok((
            libc::pollfd {
                fd,
                events: events as i16,
                revents: 0,
            },
            wait,
        ))
    }
    pub fn process(&mut self) -> Result<()> {
        loop {
            let n = unsafe { sd_bus_process(self.bus.0, ptr::null_mut()) };
            check(n)?;
            if n == 0 {
                break;
            }
        }
        self.pending.retain(|r| !r.done);
        Ok(())
    }
}
