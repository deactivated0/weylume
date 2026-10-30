use crate::bus::{string, Bus};
use std::{
    collections::HashMap,
    ffi::{c_char, c_int, c_void},
    ptr,
    time::{Duration, Instant},
};
#[link(name = "libudev.so.1", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn udev_new() -> *mut c_void;
    fn udev_unref(p: *mut c_void) -> *mut c_void;
    fn udev_monitor_new_from_netlink(u: *mut c_void, n: *const c_char) -> *mut c_void;
    fn udev_monitor_enable_receiving(m: *mut c_void) -> c_int;
    fn udev_monitor_get_fd(m: *mut c_void) -> c_int;
    fn udev_monitor_receive_device(m: *mut c_void) -> *mut c_void;
    fn udev_monitor_unref(m: *mut c_void) -> *mut c_void;
    fn udev_device_get_property_value(d: *mut c_void, k: *const c_char) -> *const c_char;
    fn udev_device_unref(d: *mut c_void) -> *mut c_void;
}
pub struct Devices {
    udev: *mut c_void,
    monitor: *mut c_void,
    start: Instant,
    recent: HashMap<String, Instant>,
    bus: Option<Bus>,
}
impl Drop for Devices {
    fn drop(&mut self) {
        unsafe {
            if !self.monitor.is_null() {
                udev_monitor_unref(self.monitor);
            }
            if !self.udev.is_null() {
                udev_unref(self.udev);
            }
        }
    }
}
impl Devices {
    pub fn new() -> Self {
        unsafe {
            let u = udev_new();
            let m = if u.is_null() {
                ptr::null_mut()
            } else {
                udev_monitor_new_from_netlink(u, c"udev".as_ptr())
            };
            let mut s = Self {
                udev: u,
                monitor: m,
                start: Instant::now(),
                recent: HashMap::new(),
                bus: None,
            };
            if !m.is_null() && udev_monitor_enable_receiving(m) < 0 {
                udev_monitor_unref(m);
                s.monitor = ptr::null_mut();
            }
            s
        }
    }
    pub fn disconnect(&mut self) {
        if !self.monitor.is_null() {
            unsafe {
                udev_monitor_unref(self.monitor);
            }
            self.monitor = ptr::null_mut();
        }
    }
    pub fn fd(&self) -> i32 {
        if self.monitor.is_null() {
            -1
        } else {
            unsafe { udev_monitor_get_fd(self.monitor) }
        }
    }
    pub fn drain(&mut self) -> bool {
        let mut hardware = false;
        if self.monitor.is_null() {
            return false;
        }
        loop {
            let d = unsafe { udev_monitor_receive_device(self.monitor) };
            if d.is_null() {
                break;
            }
            let keys = [
                c"ACTION",
                c"SUBSYSTEM",
                c"DEVTYPE",
                c"ID_BUS",
                c"NAME",
                c"ID_MODEL_FROM_DATABASE",
                c"ID_FS_LABEL",
                c"ID_MODEL",
                c"ID_VENDOR",
                c"ID_VENDOR_FROM_DATABASE",
                c"ID_DRIVE_FLASH",
                c"ID_USB_INTERFACE_NUM",
                c"ID_INPUT_JOYSTICK",
                c"ID_INPUT",
                c"ID_INPUT_MOUSE",
                c"ID_INPUT_KEYBOARD",
            ];
            let vals: Vec<String> = keys
                .iter()
                .map(|k| unsafe { string(udev_device_get_property_value(d, k.as_ptr())) })
                .collect();
            unsafe {
                udev_device_unref(d);
            }
            let v: Vec<&str> = vals.iter().map(String::as_str).collect();
            let (a, s, t) = (v[0], v[1], v[2]);
            if ["drm", "hwmon", "cpu"].contains(&s) {
                hardware = true
            }
            if self.start.elapsed() < Duration::from_millis(3500) || !["add", "remove"].contains(&a)
            {
                continue;
            }
            if !((s == "usb" && t == "usb_device")
                || (s == "block" && ["disk", "partition"].contains(&t) && v[3] == "usb")
                || (s == "sound" && t == "card")
                || s == "bluetooth"
                || (s == "input" && !v[4].is_empty() && t.is_empty()))
            {
                continue;
            }
            let raw = if !v[5].is_empty() {
                v[5].to_string()
            } else if !v[6].is_empty() {
                v[6].to_string()
            } else if !v[7].is_empty() {
                if !v[8].is_empty() && !v[7].contains(v[8]) {
                    format!("{} {}", v[8], v[7])
                } else {
                    v[7].to_string()
                }
            } else if !v[4].is_empty() {
                v[4].to_string()
            } else {
                v[9].to_string()
            };
            let name = raw
                .trim_matches(['\'', '"'])
                .replace('_', " ")
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" ");
            let lower = name.to_lowercase();
            if name.chars().count() < 2
                || [
                    "root hub",
                    "host controller",
                    "linux foundation",
                    "virtual",
                    "loop",
                    "zram",
                    "null",
                    "dummy",
                    "pipewire",
                ]
                .iter()
                .any(|s| lower.contains(s))
            {
                continue;
            }
            let now = Instant::now();
            let key = format!("{a}:{s}:{name}");
            if self
                .recent
                .get(&key)
                .is_some_and(|t| now.duration_since(*t) < Duration::from_secs(2))
            {
                continue;
            }
            self.recent.insert(key, now);
            if self.recent.len() > 50 {
                self.recent
                    .retain(|_, t| now.duration_since(*t) < Duration::from_secs(10));
            }
            let icon = if s == "block" || !v[10].is_empty() || v[3] == "usb" {
                "drive-removable-media"
            } else if s == "sound" || v[11].to_lowercase().contains("audio") {
                "audio-card"
            } else if s == "bluetooth" {
                "bluetooth"
            } else if s == "input" {
                if v[12].contains("joystick") || v[13].contains("gamepad") {
                    "input-gaming"
                } else if v[14] == "1" {
                    "input-mouse"
                } else if v[15] == "1" {
                    "input-keyboard"
                } else {
                    "preferences-desktop-peripherals"
                }
            } else {
                "preferences-desktop-peripherals"
            };
            if self.bus.is_none() {
                self.bus = Bus::user().ok()
            }
            if self.bus.as_ref().is_some_and(|b| {
                b.notify(
                    "Device Manager",
                    if a == "add" {
                        "Device Connected"
                    } else {
                        "Device Disconnected"
                    },
                    &name,
                    icon,
                )
                .is_err()
            }) {
                self.bus = None;
            }
        }
        hardware
    }
}
