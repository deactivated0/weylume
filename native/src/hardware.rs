use crate::{backend::human, util::*};
use serde_json::{json, Value};
use std::{
    ffi::CString,
    fs,
    path::{Path, PathBuf},
};
fn config_data() -> &'static Value {
    static CONFIG: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    CONFIG.get_or_init(|| json_file(shell().join("hardware.json")))
}
pub fn gpu_label(device: Option<&Path>) -> String {
    let Some(device) = device else {
        return "GPU unavailable".into();
    };
    let config = config_data();
    let vendor = read(device.join("vendor"));
    let id = read(device.join("device"));
    let key = format!(
        "{}:{}",
        vendor.trim().trim_start_matches("0x"),
        id.trim().trim_start_matches("0x")
    );
    if let Some(label) = config["gpuLabels"][&key].as_str() {
        return label.to_string();
    }
    let product = read(device.join("product_name"));
    if !product.trim().is_empty() {
        return product.trim().into();
    }
    let driver = fs::read_link(device.join("driver"))
        .ok()
        .and_then(|p| p.file_name().map(|s| s.to_string_lossy().into_owned()))
        .unwrap_or("GPU".into());
    format!("{driver} ({key})")
}
fn unescape_mount(value: &str) -> String {
    if !value.contains('\\') {
        return value.to_string();
    }
    let mut res = String::with_capacity(value.len());
    let bytes = value.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && i + 3 < bytes.len() {
            match &bytes[i..i + 4] {
                b"\\040" => {
                    res.push(' ');
                    i += 4;
                    continue;
                }
                b"\\011" => {
                    res.push('\t');
                    i += 4;
                    continue;
                }
                b"\\012" => {
                    res.push('\n');
                    i += 4;
                    continue;
                }
                b"\\134" => {
                    res.push('\\');
                    i += 4;
                    continue;
                }
                _ => {}
            }
        }
        res.push(bytes[i] as char);
        i += 1;
    }
    res
}
pub fn mounts() -> Vec<(PathBuf, String)> {
    let config = config_data();
    if let Some(paths) = config["mounts"].as_array() {
        return paths
            .iter()
            .take(32)
            .filter_map(|v| {
                Some((
                    PathBuf::from(v["path"].as_str()?),
                    v["label"].as_str().unwrap_or("Disk").into(),
                ))
            })
            .collect();
    }
    let mut seen = std::collections::HashSet::new();
    read("/proc/self/mountinfo")
        .lines()
        .filter_map(|line| {
            let path_field = line.split_whitespace().nth(4)?;
            let path = unescape_mount(path_field);
            if path != "/"
                && !path.starts_with("/mnt/")
                && !path.starts_with("/media/")
                && !path.starts_with("/run/media/")
            {
                return None;
            }
            if !seen.insert(path.clone()) {
                return None;
            }
            let label = if path == "/" {
                "SSD".into()
            } else {
                Path::new(&path)
                    .file_name()
                    .map_or("Disk".into(), |s| s.to_string_lossy().into_owned())
            };
            Some((path.into(), label))
        })
        .take(32)
        .collect()
}
pub fn drives() -> Result<Value> {
    let mut values = Vec::new();
    for (path, name) in mounts() {
        use std::os::unix::ffi::OsStrExt;
        let c = CString::new(path.as_os_str().as_bytes())?;
        let mut s: libc::statvfs = unsafe { std::mem::zeroed() };
        if unsafe { libc::statvfs(c.as_ptr(), &mut s) } < 0 {
            values.push(
                json!({"name":name,"mount":path,"used":"Unavailable","usage":0,"available":false}),
            );
            continue;
        }
        let total = s.f_blocks.saturating_mul(s.f_frsize);
        let used = s
            .f_blocks
            .saturating_sub(s.f_bfree)
            .saturating_mul(s.f_frsize);
        let avail = s.f_bavail.saturating_mul(s.f_frsize);
        let usage = if used + avail == 0 {
            0
        } else {
            (used as u128 * 100).div_ceil((used + avail) as u128) as u64
        };
        values.push(json!({"name":name,"mount":path,"used":format!("{} / {}",human(used),human(total)),"usage":usage,"available":true}));
    }
    Ok(json!(values))
}
