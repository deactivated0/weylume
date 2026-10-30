//! Explicit preflight and /proc measurements. No background sampling service.
use crate::{bus::Bus, util::*};
use serde_json::{json, Value};
use std::{
    fs,
    time::{Duration, Instant},
};
pub fn data() -> Value {
    let mut summary = vec![
        format!(
            "Native binary: {} / {}",
            std::env::consts::ARCH,
            std::env::consts::OS
        ),
        format!("Configuration: {}", shell().display()),
    ];
    for command in [
        "quickshell",
        "labwc",
        "wl-paste",
        "wl-copy",
        "grim",
        "slurp",
        "gpu-screen-recorder",
        "wtype",
    ] {
        summary.push(format!(
            "{command}: {}",
            which(command).map_or("missing (dependent feature unavailable)".into(), |p| p
                .display()
                .to_string())
        ));
    }
    for (system, names) in [
        (
            true,
            vec![
                "org.freedesktop.NetworkManager",
                "org.bluez",
                "org.freedesktop.UPower",
                "org.freedesktop.login1",
            ],
        ),
        (
            false,
            vec!["org.freedesktop.portal.Desktop", "rs.wl-gammarelay"],
        ),
    ] {
        let bus = if system { Bus::system() } else { Bus::user() };
        let owned = bus.and_then(|b| {
            b.call(
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "ListNames",
                "",
                &[],
            )
        });
        for name in names {
            summary.push(format!(
                "{name}: {}",
                match &owned {
                    Ok(v) if v[0].as_array().is_some_and(|v| v.iter().any(|n| n == name)) =>
                        "running",
                    Ok(_) => "not running (may be activated on demand)",
                    Err(_) => "bus unavailable",
                }
            ));
        }
    }
    if std::env::var_os("WAYLAND_DISPLAY").is_none() {
        summary.push("WAYLAND_DISPLAY is unset; run acceptance inside Labwc".into());
    }
    if !shell().join("native/Cargo.toml").exists() {
        summary.push("Native source missing; keep native/ with the configuration".into());
    }
    summary.push("Lock contract: configure a locker that reports logind LockedHint only after acquiring the session lock".into());
    summary.push("Labwc reload is a request, not a compositor acknowledgement; validate live behavior on target".into());
    summary.push("Cross-application portal sharing enumeration/revocation is unavailable in the portable API".into());
    json!({"architecture":std::env::consts::ARCH,"binaryBytes":std::env::current_exe().ok().and_then(|p|fs::metadata(p).ok()).map(|m|m.len()),"summary":summary})
}
fn counters(pid: u32) -> Result<(u64, u64, u64, u64)> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let fields: Vec<_> = stat
        .rsplit_once(')')
        .ok_or("Invalid process stat")?
        .1
        .split_whitespace()
        .collect();
    let number = |i: usize| {
        fields
            .get(i)
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0)
    };
    let status = fs::read_to_string(format!("/proc/{pid}/status"))?;
    let find = |key: &str| {
        status
            .lines()
            .find_map(|l| l.strip_prefix(key))
            .and_then(|v| v.split_whitespace().next()?.parse::<u64>().ok())
            .unwrap_or(0)
    };
    Ok((
        number(11) + number(12),
        find("VmRSS:"),
        find("voluntary_ctxt_switches:") + find("nonvoluntary_ctxt_switches:"),
        number(19),
    ))
}
pub fn profile(pid: u32, seconds: u64) -> Result<Value> {
    if !(1..=60).contains(&seconds) {
        return Err("Choose a measurement duration from 1 to 60 seconds".into());
    }
    let before = counters(pid)?;
    let start = Instant::now();
    std::thread::sleep(Duration::from_secs(seconds));
    let after = counters(pid)?;
    if before.3 != after.3 {
        return Err("Process changed during measurement".into());
    }
    let elapsed = start.elapsed().as_secs_f64();
    let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
    Ok(
        json!({"pid":pid,"seconds":elapsed,"rssKiB":after.1,"cpuPercentOneCore":(after.0.saturating_sub(before.0))as f64/hz/elapsed*100.,"mainThreadContextSwitches":after.2.saturating_sub(before.2),"note":"One PID only. Context switches are not CPU wakeups; measure scheduler wakeups separately on the target."}),
    )
}
