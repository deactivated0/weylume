mod audio;
mod autostart;
mod backend;
mod bluetooth;
mod bus;
mod calendar;
mod clipboard;
mod dbus;
mod desktop;
mod devices;
mod diagnostics;
mod disk_worker;
mod hardware;
mod labwc;
mod network;
mod network_agent;
mod output_protocol;
mod outputs;
mod preview;
mod recording;
mod session;
mod system;
mod util;
mod wayland;
use serde_json::json;
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let first = args.first().map_or("", String::as_str);
    let result = match first {
        "network-activate" if args.len() == 3 => network_agent::activate(&args[1], &args[2]),
        "backend" => backend::main(),
        "bluetooth-pair" if args.len() >= 2 => {
            bluetooth::pair(&args[1], args.get(2).map_or("", String::as_str))
        }
        "disk-metrics" => hardware::drives().and_then(|v| Ok(util::emit(&v)?)),
        "output-apply-json" => outputs::apply_stdin(),
        "output-apply" if args.len() == 2 => outputs::profile(&args[1]).and_then(outputs::apply),
        "previews" => preview::main(&args[1..]),
        "windows" => preview::windows().and_then(|v| Ok(util::emit(&v)?)),
        "desktop" => desktop::action(&args[1..]),
        "clipboard-capture" => clipboard::capture(),
        "autostart-list" => autostart::list().and_then(|v| Ok(util::emit(&v)?)),
        "autostart-toggle" if args.len() >= 3 => autostart::toggle(&args[1], args[2] == "true")
            .and_then(|_| Ok(util::emit(&json!({"ok":true}))?)),
        "autostart-save" if args.len() >= 2 => {
            autostart::save(&args[1]).and_then(|_| Ok(util::emit(&json!({"ok":true}))?))
        }
        "autostart-delete" if args.len() >= 2 => {
            autostart::delete(&args[1]).and_then(|_| Ok(util::emit(&json!({"ok":true}))?))
        }
        "autostart-launch" if args.len() >= 2 => {
            autostart::launch(&args[1]).and_then(|_| Ok(util::emit(&json!({"ok":true}))?))
        }
        "autostart-labwc-read" => {
            autostart::read_labwc().and_then(|v| Ok(util::emit(&json!({"ok":true,"content":v}))?))
        }
        "autostart-labwc-write" if args.len() >= 2 => {
            autostart::write_labwc(&args[1]).and_then(|_| Ok(util::emit(&json!({"ok":true}))?))
        }
        "gamma-get" => bus::Bus::user()
            .and_then(|b| b.brightness())
            .map(|v| println!("d {v}")),
        "gamma-set" if args.len() == 3 => args[2]
            .parse::<f64>()
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error>)
            .and_then(|v| bus::Bus::user()?.gamma(&args[1], v)),
        _ => {
            let (ok, mut message, data) = system::action(&args)
                .unwrap_or_else(|e| (false, e.to_string(), serde_json::Value::Null));
            if message.is_empty() {
                message = if ok { "Done" } else { "Action failed" }.into()
            }
            let mut v = json!({"ok":ok,"message":message});
            if !data.is_null() {
                v["data"] = data;
            }
            let _ = util::emit(&v);
            std::process::exit(if ok { 0 } else { 1 });
        }
    };
    if let Err(e) = result {
        eprintln!("weylume-native: {e}");
        std::process::exit(1)
    }
}
