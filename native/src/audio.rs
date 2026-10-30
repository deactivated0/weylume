//! On-demand libpulse client (also supported by pipewire-pulse). No daemon/runtime.
use crate::{bus::string, util::*};
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_int, c_void, CString},
    ptr,
    time::{Duration, Instant},
};
#[repr(C)]
struct Profile {
    name: *const c_char,
    description: *const c_char,
    sinks: u32,
    sources: u32,
    priority: u32,
    available: c_int,
}
#[repr(C)]
struct Card {
    index: u32,
    name: *const c_char,
    owner: u32,
    driver: *const c_char,
    count: u32,
    old_profiles: *mut c_void,
    old_active: *mut c_void,
    props: *mut c_void,
    port_count: u32,
    ports: *mut c_void,
    profiles: *const *const Profile,
    active: *const Profile,
}
#[repr(C)]
struct Port {
    name: *const c_char,
    description: *const c_char,
    priority: u32,
    available: c_int,
}
#[repr(C)]
struct Sample {
    format: c_int,
    rate: u32,
    channels: u8,
}
#[repr(C)]
struct Channels {
    count: u8,
    values: [c_int; 32],
}
#[repr(C)]
struct Volume {
    count: u8,
    values: [u32; 32],
}
#[repr(C)]
struct Device {
    name: *const c_char,
    index: u32,
    description: *const c_char,
    sample: Sample,
    channels: Channels,
    owner: u32,
    volume: Volume,
    mute: c_int,
    monitor: u32,
    monitor_name: *const c_char,
    latency: u64,
    driver: *const c_char,
    flags: c_int,
    props: *mut c_void,
    configured_latency: u64,
    base: u32,
    state: c_int,
    steps: u32,
    card: u32,
    count: u32,
    ports: *const *const Port,
    active: *const Port,
}
#[repr(C)]
struct Stream {
    index: u32,
    name: *const c_char,
    owner: u32,
    client: u32,
    device: u32,
}
type CardCb = unsafe extern "C" fn(*mut c_void, *const Card, c_int, *mut c_void);
type DeviceCb = unsafe extern "C" fn(*mut c_void, *const Device, c_int, *mut c_void);
type StreamCb = unsafe extern "C" fn(*mut c_void, *const Stream, c_int, *mut c_void);
type Success = unsafe extern "C" fn(*mut c_void, c_int, *mut c_void);
struct Library(*mut c_void);
impl Drop for Library {
    fn drop(&mut self) {
        unsafe {
            libc::dlclose(self.0);
        }
    }
}
macro_rules! api{($( $name:ident ( $($arg:ty),* ) -> $ret:ty; )*)=>{
 struct Api{_library:Library,$($name:unsafe extern "C" fn($($arg),*)->$ret,)*}
 impl Api{fn new()->Result<Self>{unsafe{
 let library=Library(libc::dlopen(c"libpulse.so.0".as_ptr(),libc::RTLD_NOW|libc::RTLD_LOCAL));if library.0.is_null(){return Err("libpulse.so.0 is unavailable".into());}
 $(let symbol=CString::new(stringify!($name))?;let address=libc::dlsym(library.0,symbol.as_ptr());if address.is_null(){return Err(concat!("Missing libpulse symbol: ",stringify!($name)).into());}let $name=std::mem::transmute::<*mut c_void,unsafe extern "C" fn($($arg),*)->$ret>(address);)*
 Ok(Self{_library:library,$($name,)*})}}}}}
api! {
 pa_mainloop_new()->*mut c_void;pa_mainloop_free(*mut c_void)->();pa_mainloop_get_api(*mut c_void)->*mut c_void;
 pa_mainloop_prepare(*mut c_void,c_int)->c_int;pa_mainloop_poll(*mut c_void)->c_int;pa_mainloop_dispatch(*mut c_void)->c_int;
 pa_context_new(*mut c_void,*const c_char)->*mut c_void;pa_context_connect(*mut c_void,*const c_char,c_int,*const c_void)->c_int;pa_context_get_state(*mut c_void)->c_int;pa_context_disconnect(*mut c_void)->();pa_context_unref(*mut c_void)->();
 pa_operation_get_state(*mut c_void)->c_int;pa_operation_cancel(*mut c_void)->();pa_operation_unref(*mut c_void)->();
 pa_context_get_card_info_list(*mut c_void,CardCb,*mut c_void)->*mut c_void;
 pa_context_get_sink_info_list(*mut c_void,DeviceCb,*mut c_void)->*mut c_void;pa_context_get_source_info_list(*mut c_void,DeviceCb,*mut c_void)->*mut c_void;
 pa_context_set_card_profile_by_name(*mut c_void,*const c_char,*const c_char,Success,*mut c_void)->*mut c_void;
 pa_context_set_sink_port_by_name(*mut c_void,*const c_char,*const c_char,Success,*mut c_void)->*mut c_void;pa_context_set_source_port_by_name(*mut c_void,*const c_char,*const c_char,Success,*mut c_void)->*mut c_void;
 pa_context_get_sink_input_info_list(*mut c_void,StreamCb,*mut c_void)->*mut c_void;pa_context_get_source_output_info_list(*mut c_void,StreamCb,*mut c_void)->*mut c_void;
 pa_context_move_sink_input_by_name(*mut c_void,u32,*const c_char,Success,*mut c_void)->*mut c_void;pa_context_move_source_output_by_name(*mut c_void,u32,*const c_char,Success,*mut c_void)->*mut c_void;
}
struct Client {
    api: Api,
    main: *mut c_void,
    context: *mut c_void,
}
impl Drop for Client {
    fn drop(&mut self) {
        unsafe {
            if !self.context.is_null() {
                (self.api.pa_context_disconnect)(self.context);
                (self.api.pa_context_unref)(self.context);
            }
            if !self.main.is_null() {
                (self.api.pa_mainloop_free)(self.main);
            }
        }
    }
}
impl Client {
    fn new() -> Result<Self> {
        unsafe {
            let api = Api::new()?;
            let main = (api.pa_mainloop_new)();
            if main.is_null() {
                return Err("Cannot allocate audio connection".into());
            }
            let mut c = Self {
                api,
                main,
                context: ptr::null_mut(),
            };
            c.context =
                (c.api.pa_context_new)((c.api.pa_mainloop_get_api)(main), c"Weylume".as_ptr());
            if c.context.is_null()
                || (c.api.pa_context_connect)(c.context, ptr::null(), 1, ptr::null()) < 0
            {
                return Err("Audio server unavailable".into());
            }
            c.wait(|| (c.api.pa_context_get_state)(c.context) == 4)?;
            Ok(c)
        }
    }
    fn wait(&self, ready: impl Fn() -> bool) -> Result<()> {
        let end = Instant::now() + Duration::from_secs(4);
        unsafe {
            while !ready() {
                let state = (self.api.pa_context_get_state)(self.context);
                if state >= 5 {
                    return Err("Audio connection closed".into());
                }
                let timeout = end
                    .saturating_duration_since(Instant::now())
                    .as_millis()
                    .min(i32::MAX as u128) as i32;
                if timeout == 0 {
                    return Err("Audio operation timed out".into());
                }
                if (self.api.pa_mainloop_prepare)(self.main, timeout) < 0
                    || (self.api.pa_mainloop_poll)(self.main) < 0
                    || (self.api.pa_mainloop_dispatch)(self.main) < 0
                {
                    return Err("Audio operation failed".into());
                }
            }
        }
        Ok(())
    }
    fn operation(&self, op: *mut c_void) -> Result<()> {
        if op.is_null() {
            return Err("Audio operation unavailable".into());
        }
        let result = self.wait(|| unsafe { (self.api.pa_operation_get_state)(op) != 0 });
        unsafe {
            if result.is_err() {
                (self.api.pa_operation_cancel)(op);
            }
            (self.api.pa_operation_unref)(op);
        }
        result
    }
}
struct Collected<T> {
    items: Vec<T>,
    failed: bool,
}
impl<T> Default for Collected<T> {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            failed: false,
        }
    }
}
impl<T> Collected<T> {
    fn finish(self) -> Result<Vec<T>> {
        if self.failed {
            Err("Audio server could not enumerate devices or streams".into())
        } else {
            Ok(self.items)
        }
    }
}
unsafe extern "C" fn cards(_: *mut c_void, p: *const Card, eol: c_int, data: *mut c_void) {
    if eol != 0 || p.is_null() {
        if eol < 0 {
            (*(data as *mut Collected<Value>)).failed = true;
        }
        return;
    }
    let c = &*p;
    let out = &mut *(data as *mut Collected<Value>);
    if out.items.len() >= 128 {
        return;
    }
    let mut profiles = Vec::new();
    if !c.profiles.is_null() {
        for i in 0..c.count.min(256) {
            let p = *c.profiles.add(i as usize);
            if p.is_null() {
                break;
            }
            let p = &*p;
            profiles.push(json!({"name":string(p.name),"description":string(p.description),"available":p.available!=0}));
        }
    }
    out.items.push(json!({"name":string(c.name),"index":c.index,"profiles":profiles,"active":if c.active.is_null(){String::new()}else{string((*c.active).name)}}));
}
unsafe extern "C" fn devices(_: *mut c_void, p: *const Device, eol: c_int, data: *mut c_void) {
    if eol != 0 || p.is_null() {
        if eol < 0 {
            (*(data as *mut Collected<Value>)).failed = true;
        }
        return;
    }
    let d = &*p;
    let out = &mut *(data as *mut Collected<Value>);
    if out.items.len() >= 256 {
        return;
    }
    let mut ports = Vec::new();
    if !d.ports.is_null() {
        for i in 0..d.count.min(256) {
            let p = *d.ports.add(i as usize);
            if p.is_null() {
                break;
            }
            let p = &*p;
            ports.push(json!({"name":string(p.name),"description":string(p.description),"available":p.available!=1}));
        }
    }
    out.items.push(json!({"name":string(d.name),"description":string(d.description),"card":d.card,"ports":ports,"active":if d.active.is_null(){String::new()}else{string((*d.active).name)}}));
}
unsafe extern "C" fn stream(_: *mut c_void, p: *const Stream, eol: c_int, data: *mut c_void) {
    if eol < 0 {
        (*(data as *mut Collected<u32>)).failed = true;
    }
    if eol == 0 && !p.is_null() {
        let out = &mut *(data as *mut Collected<u32>);
        if out.items.len() < 512 {
            out.items.push((*p).index);
        }
    }
}
unsafe extern "C" fn success(_: *mut c_void, ok: c_int, data: *mut c_void) {
    *(data as *mut bool) = ok != 0;
}
pub fn details() -> Result<Value> {
    let c = Client::new()?;
    let (mut cards_out, mut sinks, mut sources) = (
        Collected::<Value>::default(),
        Collected::<Value>::default(),
        Collected::<Value>::default(),
    );
    unsafe {
        c.operation((c.api.pa_context_get_card_info_list)(
            c.context,
            cards,
            (&mut cards_out as *mut Collected<Value>).cast(),
        ))?;
        c.operation((c.api.pa_context_get_sink_info_list)(
            c.context,
            devices,
            (&mut sinks as *mut Collected<Value>).cast(),
        ))?;
        c.operation((c.api.pa_context_get_source_info_list)(
            c.context,
            devices,
            (&mut sources as *mut Collected<Value>).cast(),
        ))?;
    }
    Ok(json!({"cards":cards_out.finish()?,"sinks":sinks.finish()?,"sources":sources.finish()?}))
}
pub fn set(kind: &str, name: &str, value: &str) -> Result<()> {
    let c = Client::new()?;
    let name = CString::new(name)?;
    let value = CString::new(value)?;
    let mut ok = false;
    unsafe {
        let method = match kind {
            "profile" => c.api.pa_context_set_card_profile_by_name,
            "sink" => c.api.pa_context_set_sink_port_by_name,
            "source" => c.api.pa_context_set_source_port_by_name,
            _ => return Err("Invalid audio setting".into()),
        };
        c.operation(method(
            c.context,
            name.as_ptr(),
            value.as_ptr(),
            success,
            (&mut ok as *mut bool).cast(),
        ))?;
    }
    if ok {
        Ok(())
    } else {
        Err("Audio server rejected the profile or port".into())
    }
}
pub fn migrate(name: &str, source: bool) -> Result<()> {
    let c = Client::new()?;
    let target = CString::new(name)?;
    let mut streams = Collected::<u32>::default();
    unsafe {
        let get = if source {
            c.api.pa_context_get_source_output_info_list
        } else {
            c.api.pa_context_get_sink_input_info_list
        };
        c.operation(get(
            c.context,
            stream,
            (&mut streams as *mut Collected<u32>).cast(),
        ))?;
        let move_stream = if source {
            c.api.pa_context_move_source_output_by_name
        } else {
            c.api.pa_context_move_sink_input_by_name
        };
        for id in streams.finish()? {
            let mut ok = false;
            c.operation(move_stream(
                c.context,
                id,
                target.as_ptr(),
                success,
                (&mut ok as *mut bool).cast(),
            ))?;
            if !ok {
                return Err("An audio stream could not be moved".into());
            }
        }
    }
    Ok(())
}

#[cfg(all(test, target_pointer_width = "64"))]
mod tests {
    use super::*;
    use std::mem::offset_of;
    #[test]
    fn system_pulse_abi() {
        // Verified against PulseAudio 17 public C headers on x86-64.
        assert_eq!(offset_of!(Card, profiles), 80);
        assert_eq!(offset_of!(Card, active), 88);
        assert_eq!(offset_of!(Device, ports), 384);
        assert_eq!(offset_of!(Device, active), 392);
        assert_eq!(offset_of!(Device, card), 372);
        assert_eq!(offset_of!(Device, count), 376);
    }
}
