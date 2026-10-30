//! A pairing agent exists only during an explicit pairing transaction.
use crate::{
    bus::{string, Bus},
    dbus,
    util::*,
};
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_int, c_void, CString},
    ptr,
    time::{Duration, Instant},
};
const BLUEZ: &str = "org.bluez";
const AGENT: &str = "/org/weylume/PairingAgent";
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
    fn sd_bus_message_new_method_call(
        b: *mut c_void,
        m: *mut *mut c_void,
        d: *const c_char,
        p: *const c_char,
        i: *const c_char,
        n: *const c_char,
    ) -> c_int;
    fn sd_bus_reply_method_errorf(
        m: *mut c_void,
        name: *const c_char,
        fmt: *const c_char,
        ...
    ) -> c_int;
    fn sd_bus_send(b: *mut c_void, m: *mut c_void, c: *mut u64) -> c_int;
    fn sd_bus_flush(b: *mut c_void) -> c_int;
    fn sd_bus_call_async(
        b: *mut c_void,
        s: *mut *mut c_void,
        m: *mut c_void,
        cb: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void) -> c_int,
        u: *mut c_void,
        t: u64,
    ) -> c_int;
    fn sd_bus_message_is_method_error(m: *mut c_void, n: *const c_char) -> c_int;
    fn sd_bus_process(b: *mut c_void, m: *mut *mut c_void) -> c_int;
    fn sd_bus_get_fd(b: *mut c_void) -> c_int;
}
fn check(n: c_int) -> Result<()> {
    if n < 0 {
        Err(std::io::Error::from_raw_os_error(-n).into())
    } else {
        Ok(())
    }
}
struct Pending {
    message: *mut c_void,
    id: u64,
    kind: String,
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
    device: String,
    pending: Option<Pending>,
    serial: u64,
    done: Option<bool>,
}
unsafe fn reject(m: *mut c_void) {
    sd_bus_reply_method_errorf(
        m,
        c"org.bluez.Error.Rejected".as_ptr(),
        c"Pairing request rejected".as_ptr(),
    );
}
unsafe fn reply(b: *mut c_void, m: *mut c_void, sig: &str, value: &[Value]) -> Result<()> {
    let mut r = ptr::null_mut();
    check(sd_bus_message_new_method_return(m, &mut r))?;
    let result = dbus::append_sequence(r, sig, value)
        .and_then(|_| check(sd_bus_send(b, r, ptr::null_mut())));
    sd_bus_message_unref(r);
    result
}
unsafe extern "C" fn request(m: *mut c_void, data: *mut c_void, _: *mut c_void) -> c_int {
    let agent = &mut *(data as *mut Agent);
    if string(sd_bus_message_get_interface(m)) != "org.bluez.Agent1" {
        return 0;
    }
    if string(sd_bus_message_get_sender(m)) != agent.owner {
        reject(m);
        return 1;
    }
    let method = string(sd_bus_message_get_member(m));
    let mut args = Vec::new();
    while let Ok(Some(v)) = dbus::read_value(m, 0) {
        args.push(v);
    }
    if method == "Cancel" || method == "Release" {
        if let Some(p) = agent.pending.take() {
            reject(p.message);
        }
        let _ = reply(agent.bus, m, "", &[]);
        let _ = emit(&json!({"type":"cancel"}));
        if method == "Release" {
            agent.done = Some(false);
        }
        return 1;
    }
    if args.first().and_then(Value::as_str) != Some(&agent.device) {
        reject(m);
        return 1;
    }
    let display = method == "DisplayPasskey" || method == "DisplayPinCode";
    if !display
        && ![
            "RequestPinCode",
            "RequestPasskey",
            "RequestConfirmation",
            "RequestAuthorization",
            "AuthorizeService",
        ]
        .contains(&method.as_str())
    {
        return 0;
    }
    if !display && agent.pending.is_some() {
        reject(m);
        return 1;
    }
    agent.serial += 1;
    let _ = emit(
        &json!({"type":"prompt","id":agent.serial,"kind":method,"device":agent.device,"value":args.get(1),"entered":args.get(2),"displayOnly":display}),
    );
    if display {
        let _ = reply(agent.bus, m, "", &[]);
    } else {
        agent.pending = Some(Pending {
            message: sd_bus_message_ref(m),
            id: agent.serial,
            kind: method,
        });
    }
    1
}
unsafe extern "C" fn finished(m: *mut c_void, data: *mut c_void, _: *mut c_void) -> c_int {
    let agent = &mut *(data as *mut Agent);
    let ok = sd_bus_message_is_method_error(m, ptr::null()) == 0;
    agent.done = Some(ok);
    let error = if ok {
        Value::Null
    } else {
        dbus::read_value(m, 0)
            .ok()
            .flatten()
            .unwrap_or(json!("Bluetooth pairing failed"))
    };
    let _ = emit(&json!({"type":"finished","ok":ok,"message":error}));
    1
}
pub fn device_path(b: &Bus, address: &str, adapter: &str) -> Result<String> {
    let objects = b.call(
        BLUEZ,
        "/",
        "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects",
        "",
        &[],
    )?;
    for (path, interfaces) in objects[0].as_object().ok_or("Invalid BlueZ object list")? {
        let d = &interfaces["org.bluez.Device1"];
        if d["Address"]
            .as_str()
            .is_some_and(|a| a.eq_ignore_ascii_case(address))
        {
            let ap = d["Adapter"].as_str().unwrap_or("");
            if adapter.is_empty()
                || adapter == ap
                || objects[0][ap]["org.bluez.Adapter1"]["Address"]
                    .as_str()
                    .is_some_and(|a| a.eq_ignore_ascii_case(adapter))
            {
                return Ok(path.clone());
            }
        }
    }
    Err("Bluetooth device is no longer available on this adapter".into())
}
pub fn pair(address: &str, adapter: &str) -> Result<()> {
    let bus = Bus::system()?;
    let device = device_path(&bus, address, adapter)?;
    let owner = bus.call(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "GetNameOwner",
        "s",
        &[json!(BLUEZ)],
    )?[0]
        .as_str()
        .ok_or("BlueZ unavailable")?
        .to_string();
    let mut agent = Box::new(Agent {
        bus: bus.0,
        owner,
        device: device.clone(),
        pending: None,
        serial: 0,
        done: None,
    });
    let data = (&mut *agent as *mut Agent).cast();
    unsafe {
        check(sd_bus_add_object(
            bus.0,
            ptr::null_mut(),
            c"/org/weylume/PairingAgent".as_ptr(),
            request,
            data,
        ))?;
    }
    bus.call(
        BLUEZ,
        "/org/bluez",
        "org.bluez.AgentManager1",
        "RegisterAgent",
        "os",
        &[json!(AGENT), json!("KeyboardDisplay")],
    )?;
    unsafe {
        let mut m = ptr::null_mut();
        let path = CString::new(device.as_str())?;
        check(sd_bus_message_new_method_call(
            bus.0,
            &mut m,
            c"org.bluez".as_ptr(),
            path.as_ptr(),
            c"org.bluez.Device1".as_ptr(),
            c"Pair".as_ptr(),
        ))?;
        let rc = sd_bus_call_async(bus.0, ptr::null_mut(), m, finished, data, 120_000_000);
        sd_bus_message_unref(m);
        check(rc)?;
        sd_bus_flush(bus.0);
    }
    let deadline = Instant::now() + Duration::from_secs(120);
    let mut input = Vec::new();
    let mut buffer = [0u8; 4096];
    while agent.done.is_none() && Instant::now() < deadline {
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
        if agent.done.is_some() {
            break;
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
        let timeout = deadline
            .saturating_duration_since(Instant::now())
            .as_millis()
            .min(i32::MAX as u128) as i32;
        let rc = unsafe { libc::poll(fds.as_mut_ptr(), 2, timeout) };
        if rc < 0 {
            if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            break;
        }
        if fds[0].revents & (libc::POLLHUP | libc::POLLERR) != 0 {
            break;
        }
        if fds[0].revents & libc::POLLIN != 0 {
            let n = unsafe { libc::read(0, buffer.as_mut_ptr().cast(), buffer.len()) };
            if n <= 0 {
                break;
            }
            input.extend_from_slice(&buffer[..n as usize]);
            if input.len() > 8192 {
                break;
            }
            while let Some(end) = input.iter().position(|b| *b == b'\n') {
                let result = serde_json::from_slice::<Value>(&input[..end]);
                input.drain(..=end);
                let Ok(value) = result else {
                    continue;
                };
                if value["cancel"] == true {
                    agent.done = Some(false);
                    break;
                }
                if agent
                    .pending
                    .as_ref()
                    .is_none_or(|p| value["id"].as_u64() != Some(p.id))
                {
                    continue;
                }
                let pending = agent.pending.take().unwrap();
                let accepted = value["accept"] == true;
                unsafe {
                    if !accepted {
                        reject(pending.message);
                    } else {
                        let answer = value["value"].as_str().unwrap_or("");
                        let result = match pending.kind.as_str() {
                            "RequestPinCode" if (1..=16).contains(&answer.chars().count()) => {
                                reply(bus.0, pending.message, "s", &[json!(answer)])
                            }
                            "RequestPasskey"
                                if answer.len() <= 6
                                    && !answer.is_empty()
                                    && answer.bytes().all(|c| c.is_ascii_digit()) =>
                            {
                                reply(
                                    bus.0,
                                    pending.message,
                                    "u",
                                    &[json!(answer.parse::<u32>()?)],
                                )
                            }
                            "RequestPinCode" | "RequestPasskey" => {
                                Err("Invalid PIN or passkey".into())
                            }
                            _ => reply(bus.0, pending.message, "", &[]),
                        };
                        if result.is_err() {
                            reject(pending.message);
                        }
                    }
                }
            }
        }
    }
    let succeeded = agent.done == Some(true);
    if let Some(p) = agent.pending.take() {
        unsafe {
            reject(p.message);
        }
    }
    if agent.done != Some(true) {
        let _ = bus.call(
            BLUEZ,
            &device,
            "org.bluez.Device1",
            "CancelPairing",
            "",
            &[],
        );
    }
    let _ = bus.call(
        BLUEZ,
        "/org/bluez",
        "org.bluez.AgentManager1",
        "UnregisterAgent",
        "o",
        &[json!(AGENT)],
    );
    if succeeded {
        Ok(())
    } else {
        Err("Bluetooth pairing cancelled or failed".into())
    }
}
