//! Bounded synchronous system operations; resident monitoring remains event driven.
use crate::{
    bus::{string, Bus},
    util::Result,
};
use serde_json::{json, Map, Value};
use std::{
    ffi::{c_char, c_int, c_void, CStr, CString},
    ptr,
};
#[repr(C)]
#[derive(Default)]
struct Error {
    name: *const c_char,
    message: *const c_char,
    free: c_int,
}
#[link(name = "libsystemd.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn sd_bus_open_system(bus: *mut *mut c_void) -> c_int;
    fn sd_bus_set_method_call_timeout(bus: *mut c_void, usec: u64) -> c_int;
    fn sd_bus_message_new_method_call(
        b: *mut c_void,
        m: *mut *mut c_void,
        d: *const c_char,
        p: *const c_char,
        i: *const c_char,
        n: *const c_char,
    ) -> c_int;
    fn sd_bus_message_set_allow_interactive_authorization(m: *mut c_void, allow: c_int) -> c_int;
    fn sd_bus_message_append_basic(m: *mut c_void, t: c_char, v: *const c_void) -> c_int;
    fn sd_bus_message_open_container(m: *mut c_void, t: c_char, c: *const c_char) -> c_int;
    fn sd_bus_message_close_container(m: *mut c_void) -> c_int;
    fn sd_bus_call(
        b: *mut c_void,
        m: *mut c_void,
        timeout: u64,
        error: *mut Error,
        reply: *mut *mut c_void,
    ) -> c_int;
    fn sd_bus_error_free(e: *mut Error);
    fn sd_bus_message_unref(m: *mut c_void) -> *mut c_void;
    fn sd_bus_message_peek_type(
        m: *mut c_void,
        t: *mut c_char,
        contents: *mut *const c_char,
    ) -> c_int;
    fn sd_bus_message_read_basic(m: *mut c_void, t: c_char, v: *mut c_void) -> c_int;
    fn sd_bus_message_enter_container(m: *mut c_void, t: c_char, c: *const c_char) -> c_int;
    fn sd_bus_message_exit_container(m: *mut c_void) -> c_int;
}
fn check(n: c_int) -> Result<()> {
    if n < 0 {
        Err(std::io::Error::from_raw_os_error(-n).into())
    } else {
        Ok(())
    }
}
struct Message(*mut c_void);
impl Drop for Message {
    fn drop(&mut self) {
        unsafe {
            sd_bus_message_unref(self.0);
        }
    }
}
impl Drop for Error {
    fn drop(&mut self) {
        unsafe {
            sd_bus_error_free(self);
        }
    }
}

// A signature parser for the small native API surface, not a second D-Bus stack.
fn signature_end(s: &[u8], start: usize) -> Result<usize> {
    let c = *s.get(start).ok_or("Incomplete D-Bus signature")?;
    if c == b'a' {
        return signature_end(s, start + 1);
    }
    if c == b'{' || c == b'(' {
        let closing = if c == b'{' { b'}' } else { b')' };
        let mut end = start + 1;
        while s.get(end) != Some(&closing) {
            end = signature_end(s, end)?;
        }
        return Ok(end + 1);
    }
    Ok(start + 1)
}
unsafe fn append(m: *mut c_void, sig: &str, value: &Value) -> Result<()> {
    let kind = *sig.as_bytes().first().ok_or("Empty D-Bus signature")?;
    match kind {
        b's' | b'o' | b'g' => {
            let v = CString::new(value.as_str().ok_or("Expected string")?)?;
            check(sd_bus_message_append_basic(
                m,
                kind as c_char,
                v.as_ptr().cast(),
            ))
        }
        b'b' => {
            let v: c_int = value.as_bool().ok_or("Expected boolean")?.into();
            check(sd_bus_message_append_basic(
                m,
                kind as c_char,
                (&v as *const c_int).cast(),
            ))
        }
        b'u' => {
            let v = u32::try_from(value.as_u64().ok_or("Expected uint32")?)?;
            check(sd_bus_message_append_basic(
                m,
                kind as c_char,
                (&v as *const u32).cast(),
            ))
        }
        b'i' => {
            let v = i32::try_from(value.as_i64().ok_or("Expected int32")?)?;
            check(sd_bus_message_append_basic(
                m,
                kind as c_char,
                (&v as *const i32).cast(),
            ))
        }
        b'y' => {
            let v = u8::try_from(value.as_u64().ok_or("Expected byte")?)?;
            check(sd_bus_message_append_basic(
                m,
                kind as c_char,
                (&v as *const u8).cast(),
            ))
        }
        b't' => {
            let v = value.as_u64().ok_or("Expected uint64")?;
            check(sd_bus_message_append_basic(
                m,
                kind as c_char,
                (&v as *const u64).cast(),
            ))
        }
        b'v' => {
            let sig = value["sig"].as_str().ok_or("Missing variant signature")?;
            let c = CString::new(sig)?;
            check(sd_bus_message_open_container(m, b'v' as c_char, c.as_ptr()))?;
            append(m, sig, &value["value"])?;
            check(sd_bus_message_close_container(m))
        }
        b'a' => {
            let contents = CString::new(&sig[1..])?;
            check(sd_bus_message_open_container(
                m,
                b'a' as c_char,
                contents.as_ptr(),
            ))?;
            if sig.as_bytes().get(1) == Some(&b'{') {
                for (k, v) in value.as_object().ok_or("Expected dictionary")? {
                    append(m, &sig[1..], &json!([k, v]))?;
                }
            } else {
                for v in value.as_array().ok_or("Expected array")? {
                    append(m, &sig[1..], v)?;
                }
            }
            check(sd_bus_message_close_container(m))
        }
        b'{' | b'(' => {
            let contents = &sig[1..sig.len() - 1];
            let c = CString::new(contents)?;
            check(sd_bus_message_open_container(
                m,
                if kind == b'{' { b'e' } else { b'r' } as c_char,
                c.as_ptr(),
            ))?;
            append_sequence(m, contents, value.as_array().ok_or("Expected tuple")?)?;
            check(sd_bus_message_close_container(m))
        }
        _ => Err(format!("Unsupported argument type {sig}").into()),
    }
}
pub(crate) unsafe fn append_sequence(m: *mut c_void, sig: &str, values: &[Value]) -> Result<()> {
    let mut offset = 0;
    for v in values {
        let end = signature_end(sig.as_bytes(), offset)?;
        append(m, &sig[offset..end], v)?;
        offset = end;
    }
    if offset != sig.len() {
        return Err("D-Bus argument count mismatch".into());
    }
    Ok(())
}
pub(crate) unsafe fn read_value(m: *mut c_void, depth: usize) -> Result<Option<Value>> {
    if depth > 32 {
        return Err("D-Bus nesting limit exceeded".into());
    }
    let mut kind = 0;
    let mut contents = ptr::null();
    let n = sd_bus_message_peek_type(m, &mut kind, &mut contents);
    check(n)?;
    if n == 0 {
        return Ok(None);
    }
    macro_rules! scalar {
        ($t:ty) => {{
            let mut v: $t = 0 as $t;
            check(sd_bus_message_read_basic(
                m,
                kind,
                (&mut v as *mut $t).cast(),
            ))?;
            json!(v)
        }};
    }
    let value = match kind as u8 {
        b's' | b'o' | b'g' => {
            let mut v: *const c_char = ptr::null();
            check(sd_bus_message_read_basic(
                m,
                kind,
                (&mut v as *mut *const c_char).cast(),
            ))?;
            json!(string(v))
        }
        b'b' => scalar!(c_int).as_i64().map(|n| json!(n != 0)).unwrap(),
        b'y' => scalar!(u8),
        b'n' => scalar!(i16),
        b'q' => scalar!(u16),
        b'i' | b'h' => scalar!(i32),
        b'u' => scalar!(u32),
        b'x' => scalar!(i64),
        b't' => scalar!(u64),
        b'd' => scalar!(f64),
        b'a' | b'r' | b'e' | b'v' => {
            let dict = kind as u8 == b'a'
                && !contents.is_null()
                && CStr::from_ptr(contents).to_bytes().first() == Some(&b'{');
            check(sd_bus_message_enter_container(m, kind, contents))?;
            let mut values = Vec::new();
            while let Some(v) = read_value(m, depth + 1)? {
                if values.len() >= 65536 {
                    return Err("D-Bus collection too large".into());
                }
                values.push(v);
            }
            check(sd_bus_message_exit_container(m))?;
            if kind as u8 == b'v' {
                values.into_iter().next().unwrap_or(Value::Null)
            } else if dict {
                let mut map = Map::with_capacity(values.len());
                for pair in values {
                    if let Value::Array(mut arr) = pair {
                        if arr.len() == 2 {
                            let val = arr.pop().unwrap();
                            if let Value::String(k) = arr.pop().unwrap() {
                                map.insert(k, val);
                            }
                        }
                    }
                }
                Value::Object(map)
            } else {
                Value::Array(values)
            }
        }
        _ => return Err("Unsupported D-Bus reply type".into()),
    };
    Ok(Some(value))
}
impl Bus {
    pub fn system() -> Result<Self> {
        let mut b = ptr::null_mut();
        check(unsafe { sd_bus_open_system(&mut b) })?;
        let bus = Self(b);
        check(unsafe { sd_bus_set_method_call_timeout(b, 3_000_000) })?;
        Ok(bus)
    }
    pub fn call(
        &self,
        dest: &str,
        path: &str,
        interface: &str,
        method: &str,
        sig: &str,
        values: &[Value],
    ) -> Result<Value> {
        self.call_mode(dest, path, interface, method, sig, values, false)
    }
    pub fn call_interactive(
        &self,
        dest: &str,
        path: &str,
        interface: &str,
        method: &str,
        sig: &str,
        values: &[Value],
    ) -> Result<Value> {
        self.call_mode(dest, path, interface, method, sig, values, true)
    }
    #[allow(clippy::too_many_arguments)]
    fn call_mode(
        &self,
        dest: &str,
        path: &str,
        interface: &str,
        method: &str,
        sig: &str,
        values: &[Value],
        interactive: bool,
    ) -> Result<Value> {
        let [dest, path, interface, method] = [dest, path, interface, method].map(CString::new);
        let mut m = ptr::null_mut();
        unsafe {
            check(sd_bus_message_new_method_call(
                self.0,
                &mut m,
                dest?.as_ptr(),
                path?.as_ptr(),
                interface?.as_ptr(),
                method?.as_ptr(),
            ))?;
            let m = Message(m);
            if interactive {
                check(sd_bus_message_set_allow_interactive_authorization(m.0, 1))?;
            }
            append_sequence(m.0, sig, values)?;
            let mut error = Error::default();
            let mut reply = ptr::null_mut();
            let rc = sd_bus_call(
                self.0,
                m.0,
                if interactive { 120_000_000 } else { 3_000_000 },
                &mut error,
                &mut reply,
            );
            let reply = Message(reply);
            if rc < 0 {
                let description = string(error.message);
                return Err(if description.is_empty() {
                    std::io::Error::from_raw_os_error(-rc).to_string()
                } else {
                    description
                }
                .into());
            }
            let mut values = Vec::new();
            while let Some(value) = read_value(reply.0, 0)? {
                values.push(value);
            }
            Ok(Value::Array(values))
        }
    }
    pub fn get(&self, dest: &str, path: &str, interface: &str, name: &str) -> Result<Value> {
        Ok(self.call(
            dest,
            path,
            "org.freedesktop.DBus.Properties",
            "Get",
            "ss",
            &[json!(interface), json!(name)],
        )?[0]
            .take())
    }
    pub fn properties(&self, dest: &str, path: &str, interface: &str) -> Result<Value> {
        Ok(self.call(
            dest,
            path,
            "org.freedesktop.DBus.Properties",
            "GetAll",
            "s",
            &[json!(interface)],
        )?[0]
            .take())
    }
    pub fn set(
        &self,
        dest: &str,
        path: &str,
        interface: &str,
        name: &str,
        sig: &str,
        value: Value,
    ) -> Result<()> {
        self.call_interactive(
            dest,
            path,
            "org.freedesktop.DBus.Properties",
            "Set",
            "ssv",
            &[json!(interface), json!(name), variant(sig, value)],
        )?;
        Ok(())
    }
}
pub fn variant(sig: &str, value: Value) -> Value {
    json!({"sig":sig,"value":value})
}

#[link(name = "libsystemd.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn sd_bus_add_match(
        b: *mut c_void,
        slot: *mut *mut c_void,
        rule: *const c_char,
        callback: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void) -> c_int,
        data: *mut c_void,
    ) -> c_int;
    fn sd_bus_process(b: *mut c_void, m: *mut *mut c_void) -> c_int;
    fn sd_bus_wait(b: *mut c_void, timeout: u64) -> c_int;
}
unsafe extern "C" fn changed(_: *mut c_void, _: *mut c_void, _: *mut c_void) -> c_int {
    0
}
impl Bus {
    pub fn watch(&self, rule: &str) -> Result<()> {
        let rule = CString::new(rule)?;
        check(unsafe {
            sd_bus_add_match(
                self.0,
                ptr::null_mut(),
                rule.as_ptr(),
                changed,
                ptr::null_mut(),
            )
        })
    }
    pub fn wait_until(&self, seconds: u64, ready: impl Fn() -> Result<bool>) -> Result<()> {
        let end = std::time::Instant::now() + std::time::Duration::from_secs(seconds);
        loop {
            loop {
                let n = unsafe { sd_bus_process(self.0, ptr::null_mut()) };
                check(n)?;
                if n == 0 {
                    break;
                }
            }
            if ready()? {
                return Ok(());
            }
            let remaining = end.saturating_duration_since(std::time::Instant::now());
            if remaining.is_zero() {
                return Err("Timed out waiting for service acknowledgement".into());
            }
            check(unsafe {
                sd_bus_wait(self.0, remaining.as_micros().min(u64::MAX as u128) as u64)
            })?;
        }
    }
}
impl Bus {
    pub fn sleep_inhibitor(&self) -> Result<std::os::fd::OwnedFd> {
        use std::os::fd::FromRawFd;
        unsafe {
            let mut m = ptr::null_mut();
            check(sd_bus_message_new_method_call(
                self.0,
                &mut m,
                c"org.freedesktop.login1".as_ptr(),
                c"/org/freedesktop/login1".as_ptr(),
                c"org.freedesktop.login1.Manager".as_ptr(),
                c"Inhibit".as_ptr(),
            ))?;
            let m = Message(m);
            append_sequence(
                m.0,
                "ssss",
                &[
                    json!("sleep:shutdown"),
                    json!("Weylume Recorder"),
                    json!("Finalize active recording"),
                    json!("delay"),
                ],
            )?;
            let mut error = Error::default();
            let mut r = ptr::null_mut();
            let result = sd_bus_call(self.0, m.0, 3_000_000, &mut error, &mut r);
            let r = Message(r);
            check(result)?;
            let mut fd = -1;
            check(sd_bus_message_read_basic(
                r.0,
                b'h' as c_char,
                (&mut fd as *mut c_int).cast(),
            ))?;
            let owned = libc::fcntl(fd, libc::F_DUPFD_CLOEXEC, 3);
            if owned < 0 {
                return Err(std::io::Error::last_os_error().into());
            }
            Ok(std::os::fd::OwnedFd::from_raw_fd(owned))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn signatures() {
        for s in ["s", "a{sa{sv}}", "(susa{sv})", "aa{sv}"] {
            assert_eq!(signature_end(s.as_bytes(), 0).unwrap(), s.len());
        }
        for s in ["", "a", "a{sv", "(s"] {
            assert!(signature_end(s.as_bytes(), 0).is_err());
        }
    }
}
