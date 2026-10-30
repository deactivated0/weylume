use crate::{devices::Devices, util::*};
use serde_json::{json, Value};
use std::{
    ffi::CString,
    fs,
    io,
    os::{
        fd::{AsRawFd, FromRawFd, OwnedFd},
        unix::ffi::OsStrExt,
    },
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
fn paths(path: impl AsRef<Path>) -> Vec<PathBuf> {
    let mut v: Vec<_> = fs::read_dir(path)
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok().map(|e| e.path()))
        .collect();
    v.sort();
    v
}
pub fn human(n: u64) -> String {
    let mut v = n as f64;
    let mut u = 0;
    while v >= 1024. && u < 4 {
        v /= 1024.;
        u += 1
    }
    let s = ["B", "KiB", "MiB", "GiB", "TiB"][u];
    if u == 0 {
        format!("{v:.0} {s}")
    } else {
        format!("{v:.1} {s}")
    }
}
struct Sensors {
    cpu: Vec<PathBuf>,
    gpu: Option<PathBuf>,
    gpu_temp: Vec<PathBuf>,
    gpu_label: String,
}
fn temps(p: impl AsRef<Path>) -> Vec<PathBuf> {
    paths(p)
        .into_iter()
        .filter(|p| {
            let n = p.file_name().unwrap().to_string_lossy();
            n.starts_with("temp") && n.ends_with("_input")
        })
        .collect()
}
impl Sensors {
    fn discover() -> Self {
        let mut cpu: Vec<PathBuf> = paths("/sys/class/hwmon")
            .into_iter()
            .filter(|p| {
                ["k10temp", "coretemp", "zenpower", "cpu_thermal"]
                    .iter()
                    .any(|n| read(p.join("name")).contains(n))
            })
            .flat_map(temps)
            .collect();
        cpu.sort_by_key(|p| {
            let v = read_u64(p);
            if v > 0 && v < 200000 { 0 } else { 1 }
        });
        let gpu = paths("/sys/class/drm")
            .into_iter()
            .filter(|p| {
                let n = p.file_name().unwrap().to_string_lossy();
                n.strip_prefix("card")
                    .is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()))
            })
            .map(|p| p.join("device"))
            .find(|p| p.exists());
        let mut gpu_temp: Vec<PathBuf> = gpu
            .as_ref()
            .map(|p| paths(p.join("hwmon")).into_iter().flat_map(temps).collect())
            .unwrap_or_default();
        gpu_temp.sort_by_key(|p| {
            let v = read_u64(p);
            if v > 0 && v < 200000 { 0 } else { 1 }
        });
        let gpu_label = crate::hardware::gpu_label(gpu.as_deref());
        let gpu = gpu
            .map(|p| p.join("gpu_busy_percent"))
            .filter(|p| p.exists());
        Self {
            cpu,
            gpu,
            gpu_temp,
            gpu_label,
        }
    }
}
#[derive(Default)]
struct MetricFiles {
    stat: Option<fs::File>,
    net_dev: Option<fs::File>,
    net_route: Option<fs::File>,
    meminfo: Option<fs::File>,
    uptime: Option<fs::File>,
    cpufreq: Option<fs::File>,
    cpu_temp: Option<fs::File>,
    gpu_temp: Option<fs::File>,
    gpu_busy: Option<fs::File>,
}

fn read_proc_buf<'a>(
    file_opt: &mut Option<fs::File>,
    path: impl AsRef<Path>,
    buf: &'a mut [u8],
) -> Option<&'a [u8]> {
    use std::io::{Read, Seek};
    if file_opt.is_none() {
        *file_opt = fs::File::open(path.as_ref()).ok();
    }
    let file = file_opt.as_mut()?;
    if file.seek(io::SeekFrom::Start(0)).is_err() {
        *file_opt = fs::File::open(path.as_ref()).ok();
        let file = file_opt.as_mut()?;
        let n = file.read(buf).ok()?;
        return Some(&buf[..n]);
    }
    let n = file.read(buf).ok()?;
    Some(&buf[..n])
}

fn read_file_u64(file_opt: &mut Option<fs::File>, path: impl AsRef<Path>) -> u64 {
    let mut buf = [0u8; 48];
    read_proc_buf(file_opt, path, &mut buf).map_or(0, parse_ascii_u64)
}

fn temperature(file_opt: &mut Option<fs::File>, paths: &[PathBuf]) -> String {
    if let Some(first) = paths.first() {
        let v = read_file_u64(file_opt, first);
        if v > 0 && v < 200000 {
            return format!("{}°C", v / 1000);
        }
    }
    paths
        .iter()
        .skip(1)
        .map(read_u64)
        .find(|v| *v > 0 && *v < 200000)
        .map(|v| format!("{}°C", v / 1000))
        .unwrap_or_else(|| "—".into())
}
#[derive(Default)]
struct Previous {
    total: u64,
    idle: u64,
    rx: u64,
    tx: u64,
    time: Option<Instant>,
}
fn trim_ascii(mut b: &[u8]) -> &[u8] {
    while let Some((&first, rest)) = b.split_first() {
        if first.is_ascii_whitespace() {
            b = rest;
        } else {
            break;
        }
    }
    while let Some((&last, rest)) = b.split_last() {
        if last.is_ascii_whitespace() {
            b = rest;
        } else {
            break;
        }
    }
    b
}
fn emit_metrics(
    out_buf: &mut String,
    files: &mut MetricFiles,
    prev: &mut Previous,
    sensors: &Sensors,
    cpu_name: &str,
) -> io::Result<()> {
    let mut buf = [0u8; 4096];
    let (total, idle) = {
        if let Some(data) = read_proc_buf(&mut files.stat, "/proc/stat", &mut buf) {
            let first_line = data.split(|&b| b == b'\n').next().unwrap_or(&[]);
            let mut it = first_line
                .split(|&b| b.is_ascii_whitespace())
                .filter(|s| !s.is_empty())
                .skip(1);
            let mut tot = 0u64;
            let mut idl = 0u64;
            for index in 0..8 {
                let Some(val_bytes) = it.next() else { break };
                let val = parse_ascii_u64(val_bytes);
                tot += val;
                if index == 3 || index == 4 {
                    idl += val;
                }
            }
            (tot, idl)
        } else {
            (0, 0)
        }
    };

    let (mut rx, mut tx) = (0u64, 0u64);
    let mut fallback_buf = [0u8; 32];
    let mut fallback_len = 0;
    if let Some(data) = read_proc_buf(&mut files.net_dev, "/proc/net/dev", &mut buf) {
        for l in data.split(|&b| b == b'\n') {
            if let Some(colon) = l.iter().position(|&b| b == b':') {
                let name = trim_ascii(&l[..colon]);
                if name == b"lo" || name.is_empty() {
                    continue;
                }
                if fallback_len == 0 {
                    let len = name.len().min(fallback_buf.len());
                    fallback_buf[..len].copy_from_slice(&name[..len]);
                    fallback_len = len;
                }
                let mut values = l[colon + 1..]
                    .split(|&b| b.is_ascii_whitespace())
                    .filter(|s| !s.is_empty());
                if let Some(r) = values.next() {
                    rx += parse_ascii_u64(r);
                }
                if let Some(t) = values.nth(7) {
                    tx += parse_ascii_u64(t);
                }
            }
        }
    }
    let fallback = std::str::from_utf8(&fallback_buf[..fallback_len]).unwrap_or("unknown");

    let mut iface_buf = [0u8; 32];
    let mut iface_len = 0;
    if let Some(data) = read_proc_buf(&mut files.net_route, "/proc/net/route", &mut buf) {
        for l in data.split(|&b| b == b'\n').skip(1) {
            let mut v = l.split(|&b| b.is_ascii_whitespace()).filter(|s| !s.is_empty());
            let Some(name) = v.next() else { continue };
            if v.next() == Some(b"00000000") {
                let len = name.len().min(iface_buf.len());
                iface_buf[..len].copy_from_slice(&name[..len]);
                iface_len = len;
                break;
            }
        }
    }
    let interface = if iface_len > 0 {
        std::str::from_utf8(&iface_buf[..iface_len]).unwrap_or(fallback)
    } else {
        fallback
    };

    let now = Instant::now();
    let elapsed = prev
        .time
        .map(|t| now.duration_since(t).as_secs_f64())
        .unwrap_or(0.);
    let dt = total.saturating_sub(prev.total);
    let di = idle.saturating_sub(prev.idle);
    let cpu = if prev.time.is_some() && dt > 0 {
        dt.saturating_sub(di) * 100 / dt
    } else {
        0
    };
    let (rr, tr) = if elapsed > 0.05 {
        (
            rx.saturating_sub(prev.rx) as f64 / elapsed,
            tx.saturating_sub(prev.tx) as f64 / elapsed,
        )
    } else {
        (0., 0.)
    };
    *prev = Previous {
        total,
        idle,
        rx,
        tx,
        time: Some(now),
    };

    let (mut mt, mut ma) = (0u64, 0u64);
    if let Some(data) = read_proc_buf(&mut files.meminfo, "/proc/meminfo", &mut buf) {
        for l in data.split(|&b| b == b'\n') {
            if l.starts_with(b"MemTotal:") {
                let mut it = l[9..].split(|&b| b.is_ascii_whitespace()).filter(|s| !s.is_empty());
                if let Some(n) = it.next() {
                    mt = parse_ascii_u64(n);
                }
            } else if l.starts_with(b"MemAvailable:") {
                let mut it = l[13..].split(|&b| b.is_ascii_whitespace()).filter(|s| !s.is_empty());
                if let Some(n) = it.next() {
                    ma = parse_ascii_u64(n);
                }
            }
        }
    }

    let mut uptime_buf = [0u8; 64];
    let mins = if let Some(data) = read_proc_buf(&mut files.uptime, "/proc/uptime", &mut uptime_buf) {
        let first = data.split(|&b| b.is_ascii_whitespace()).next().unwrap_or(&[]);
        std::str::from_utf8(first)
            .ok()
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.) as u64
            / 60
    } else {
        0
    };
    let (days, hours, minutes) = (mins / 1440, (mins % 1440) / 60, mins % 60);
    let freq = read_file_u64(&mut files.cpufreq, "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq");
    let gpu = sensors.gpu.as_ref().map(|p| read_file_u64(&mut files.gpu_busy, p)).unwrap_or(0);
    let used = mt.saturating_sub(ma);
    let cpu_temp = temperature(&mut files.cpu_temp, &sensors.cpu);
    let gpu_temp = temperature(&mut files.gpu_temp, &sensors.gpu_temp);
    let mem_used = human(used * 1024);
    let mem_total = human(mt * 1024);
    let mem_usage = (used * 100).checked_div(mt).unwrap_or(0);
    let gpu_usage = if gpu <= 100 { gpu } else { 0 };

    out_buf.clear();
    use std::fmt::Write as FmtWrite;
    let _ = write!(out_buf, "{{\"type\":\"metrics\",\"data\":{{\"uptime\":\"");
    if days > 0 {
        let _ = write!(out_buf, "{days}d {hours}h {minutes}m");
    } else {
        let _ = write!(out_buf, "{hours}h {minutes}m");
    }
    let _ = write!(out_buf, "\",\"cpu\":{{\"model\":\"{cpu_name}\",\"frequency\":\"");
    if freq > 0 {
        let _ = write!(out_buf, "{:.2} GHz", freq as f64 / 1000000.);
    } else {
        let _ = write!(out_buf, "—");
    }
    let _ = write!(out_buf, "\",\"temperature\":\"{cpu_temp}\",\"usage\":{cpu}}},\"gpu\":{{\"model\":\"{}\",\"temperature\":\"{gpu_temp}\",\"usage\":{gpu_usage}}},\"memory\":{{\"used\":\"{mem_used}\",\"total\":\"{mem_total}\",\"usage\":{mem_usage}}},\"network\":{{\"interface\":\"{interface}\",\"receive\":\"{:.1} MB/s\",\"send\":\"{:.1} MB/s\"}}}}}}\n", sensors.gpu_label, rr / 1048576., tr / 1048576.);

    use std::io::Write as IoWrite;
    let out = io::stdout();
    let mut out = out.lock();
    out.write_all(out_buf.as_bytes())?;
    out.flush()
}
fn extension_icon(p: &Path) -> &'static str {
    let Some(e) = p.extension().and_then(|s| s.to_str()) else {
        return "text-plain";
    };
    if e.eq_ignore_ascii_case("png")
        || e.eq_ignore_ascii_case("jpg")
        || e.eq_ignore_ascii_case("jpeg")
        || e.eq_ignore_ascii_case("webp")
        || e.eq_ignore_ascii_case("svg")
        || e.eq_ignore_ascii_case("jxl")
        || e.eq_ignore_ascii_case("gif")
        || e.eq_ignore_ascii_case("bmp")
        || e.eq_ignore_ascii_case("ico")
        || e.eq_ignore_ascii_case("avif")
        || e.eq_ignore_ascii_case("heic")
        || e.eq_ignore_ascii_case("heif")
        || e.eq_ignore_ascii_case("tiff")
        || e.eq_ignore_ascii_case("tif")
    {
        "image-x-generic"
    } else if is_video_path(p) {
        "video-x-generic"
    } else if e.eq_ignore_ascii_case("mp3")
        || e.eq_ignore_ascii_case("wav")
        || e.eq_ignore_ascii_case("flac")
        || e.eq_ignore_ascii_case("ogg")
        || e.eq_ignore_ascii_case("m4a")
    {
        "audio-x-generic"
    } else if e.eq_ignore_ascii_case("zip")
        || e.eq_ignore_ascii_case("tar")
        || e.eq_ignore_ascii_case("gz")
        || e.eq_ignore_ascii_case("7z")
        || e.eq_ignore_ascii_case("xz")
        || e.eq_ignore_ascii_case("rar")
        || e.eq_ignore_ascii_case("iso")
        || e.eq_ignore_ascii_case("img")
    {
        "package-x-generic"
    } else if e.eq_ignore_ascii_case("py")
        || e.eq_ignore_ascii_case("sh")
        || e.eq_ignore_ascii_case("js")
        || e.eq_ignore_ascii_case("ts")
        || e.eq_ignore_ascii_case("html")
        || e.eq_ignore_ascii_case("css")
        || e.eq_ignore_ascii_case("json")
        || e.eq_ignore_ascii_case("md")
    {
        "text-x-script"
    } else if e.eq_ignore_ascii_case("pdf") {
        "application-pdf"
    } else if e.eq_ignore_ascii_case("apk") {
        "application-vnd.android.package-archive"
    } else {
        "text-plain"
    }
}

fn is_video_path(p: &Path) -> bool {
    let Some(e) = p.extension().and_then(|s| s.to_str()) else {
        return false;
    };
    e.eq_ignore_ascii_case("mp4")
        || e.eq_ignore_ascii_case("mkv")
        || e.eq_ignore_ascii_case("avi")
        || e.eq_ignore_ascii_case("webm")
        || e.eq_ignore_ascii_case("mov")
        || e.eq_ignore_ascii_case("flv")
        || e.eq_ignore_ascii_case("wmv")
        || e.eq_ignore_ascii_case("m4v")
        || e.eq_ignore_ascii_case("ts")
        || e.eq_ignore_ascii_case("3gp")
}

fn freedesktop_hash(p: &Path) -> Option<String> {
    let path_str = p.to_str()?;
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut uri = String::with_capacity(7 + path_str.len() * 3);
    uri.push_str("file://");
    for &b in path_str.as_bytes() {
        if b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'.' || b == b'~' || b == b'/' {
            uri.push(b as char);
        } else {
            uri.push('%');
            uri.push(HEX[(b >> 4) as usize] as char);
            uri.push(HEX[(b & 0x0F) as usize] as char);
        }
    }
    let digest = md5::compute(uri.as_bytes());
    const LOWER_HEX: &[u8; 16] = b"0123456789abcdef";
    let mut hash_bytes = [0u8; 32];
    for (i, &b) in digest.0.iter().enumerate() {
        hash_bytes[i * 2] = LOWER_HEX[(b >> 4) as usize];
        hash_bytes[i * 2 + 1] = LOWER_HEX[(b & 0x0f) as usize];
    }
    Some(String::from_utf8(hash_bytes.to_vec()).unwrap())
}

fn find_cached_thumbnail(p: &Path) -> Option<PathBuf> {
    static THUMB_LARGE: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    static THUMB_NORMAL: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    let hash = freedesktop_hash(p)?;
    let file_name = format!("{hash}.png");
    let large = THUMB_LARGE
        .get_or_init(|| home().join(".cache/thumbnails/large"))
        .join(&file_name);
    if large.exists() {
        return Some(large);
    }
    let normal = THUMB_NORMAL
        .get_or_init(|| home().join(".cache/thumbnails/normal"))
        .join(&file_name);
    if normal.exists() {
        return Some(normal);
    }
    None
}

static THUMB_SENDER: std::sync::OnceLock<std::sync::mpsc::SyncSender<PathBuf>> = std::sync::OnceLock::new();

fn start_thumbnail_worker(wake_fd: std::os::unix::io::RawFd) {
    let (tx, rx) = std::sync::mpsc::sync_channel::<PathBuf>(64);
    let _ = THUMB_SENDER.set(tx);
    std::thread::Builder::new()
        .name("thumb-worker".into())
        .spawn(move || {
            let thumb_dir = home().join(".cache/thumbnails/normal");
            let _ = std::fs::create_dir_all(&thumb_dir);
            let mut failed = std::collections::HashSet::new();
            while let Ok(video_path) = rx.recv() {
                if let Some(hash) = freedesktop_hash(&video_path) {
                    if failed.contains(&hash) {
                        continue;
                    }
                    let out_path = thumb_dir.join(format!("{}.png", hash));
                    if !out_path.exists() {
                        let ok = std::process::Command::new("ffmpegthumbnailer")
                            .args(["-i", video_path.to_str().unwrap_or_default(), "-o", out_path.to_str().unwrap_or_default(), "-s", "128"])
                            .status()
                            .map(|s| s.success())
                            .unwrap_or(false);
                        let success = if ok {
                            true
                        } else {
                            std::process::Command::new("ffmpeg")
                                .args(["-y", "-ss", "00:00:01", "-i", video_path.to_str().unwrap_or_default(), "-vframes", "1", "-vf", "scale=128:-1", out_path.to_str().unwrap_or_default()])
                                .status()
                                .map(|s| s.success())
                                .unwrap_or(false)
                        };
                        if !success {
                            failed.insert(hash);
                            continue;
                        }
                    }
                }
                let _ = unsafe { libc::write(wake_fd, [1u8].as_ptr().cast(), 1) };
            }
        })
        .ok();
}

fn queue_video_thumbnail(video_path: &Path) {
    if let Some(tx) = THUMB_SENDER.get() {
        let _ = tx.try_send(video_path.to_path_buf());
    }
}

fn ends_with_ignore_ascii_case(s: &str, suffix: &str) -> bool {
    s.len() >= suffix.len() && s[s.len() - suffix.len()..].eq_ignore_ascii_case(suffix)
}

#[derive(Clone)]
pub struct DesktopCacheEntry {
    mtime: std::time::SystemTime,
    len: u64,
    item: Value,
    has_thumb: bool,
}

pub fn desktop(cache: &mut std::collections::HashMap<PathBuf, DesktopCacheEntry>) -> Value {
    let home = home();
    let mut items = vec![
        json!({"name":"This PC","icon":"computer","path":"/mnt","exec":["xdg-open","/mnt"],"isSpecial":true}),
        json!({"name":std::env::var("USER").ok().filter(|s|!s.is_empty()).unwrap_or("Home".into()),"icon":"user-home","path":home,"exec":["xdg-open",home],"isSpecial":true}),
        json!({"name":"Trash","icon":"user-trash","path":"trash:///","exec":["xdg-open","trash:///"],"isSpecial":true}),
    ];
    let desktop_paths = paths(home.join("Desktop"));
    let mut seen = std::collections::HashSet::with_capacity(desktop_paths.len());

    for p in desktop_paths {
        let filename = p.file_name().unwrap().to_string_lossy();
        if filename.starts_with('.') || filename == "Desktop" {
            continue;
        }
        let Ok(meta) = p.symlink_metadata() else {
            continue;
        };
        seen.insert(p.clone());
        let mtime = meta.modified().unwrap_or(std::time::UNIX_EPOCH);
        let len = meta.len();

        if let Some(entry) = cache.get_mut(&p) {
            if entry.mtime == mtime && entry.len == len {
                if !entry.has_thumb {
                    let is_video = entry.item["isVideo"].as_bool().unwrap_or(false);
                    let is_image = entry.item["isImage"].as_bool().unwrap_or(false);
                    if is_video || is_image {
                        if let Some(thumb) = find_cached_thumbnail(&p) {
                            entry.item["thumbnail"] = json!(thumb);
                            entry.has_thumb = true;
                        }
                    }
                }
                items.push(entry.item.clone());
                continue;
            }
        }

        let mut name = filename.to_string();
        let mut icon = extension_icon(&p).to_string();
        let is_dir = meta.is_dir();
        let is_desktop =
            !is_dir && filename.len() > 8 && ends_with_ignore_ascii_case(&filename, ".desktop");
        if is_dir {
            icon = "folder".into()
        } else if is_desktop {
            name.truncate(name.len() - 8);
            icon = "application-x-executable".into();
            for l in read(&p).lines() {
                if let Some(v) = l.strip_prefix("Name=") {
                    name = v.into()
                } else if let Some(v) = l.strip_prefix("Icon=") {
                    icon = v.into()
                }
            }
        }
        let is_image = !is_dir && !is_desktop && icon == "image-x-generic";
        let is_video = !is_dir && !is_desktop && icon == "video-x-generic";
        let mut item = json!({"name":name,"icon":icon,"path":p,"exec":if is_desktop{json!(["gio","launch",p])}else{json!(["xdg-open",p])}});
        let mut has_thumb = false;
        if is_image {
            item["isImage"] = json!(true);
            if let Some(thumb) = find_cached_thumbnail(&p) {
                item["thumbnail"] = json!(thumb);
                has_thumb = true;
            } else {
                item["thumbnail"] = json!(p);
                has_thumb = true;
            }
        } else if is_video {
            item["isVideo"] = json!(true);
            if let Some(thumb) = find_cached_thumbnail(&p) {
                item["thumbnail"] = json!(thumb);
                has_thumb = true;
            } else if meta.len() > 0 {
                queue_video_thumbnail(&p);
            }
        } else if !is_dir && !is_desktop {
            if let Some(thumb) = find_cached_thumbnail(&p) {
                item["thumbnail"] = json!(thumb);
                has_thumb = true;
            }
        }
        item[if is_dir {
            "isDir"
        } else if is_desktop {
            "isDesktop"
        } else {
            "isFile"
        }] = json!(true);

        cache.insert(p, DesktopCacheEntry {
            mtime,
            len,
            item: item.clone(),
            has_thumb,
        });
        items.push(item);
    }
    cache.retain(|k, _| seen.contains(k));
    json!({"type":"desktop","items":items})
}
fn watch(fd: i32, p: &Path) -> i32 {
    let Ok(p) = CString::new(p.as_os_str().as_bytes()) else {
        return -1;
    };
    unsafe {
        libc::inotify_add_watch(
            fd,
            p.as_ptr(),
            libc::IN_ATTRIB
                | libc::IN_CLOSE_WRITE
                | libc::IN_CREATE
                | libc::IN_DELETE
                | libc::IN_MOVED_FROM
                | libc::IN_MOVED_TO
                | libc::IN_DELETE_SELF
                | libc::IN_MOVE_SELF,
        )
    }
}
pub fn main() -> Result<()> {
    let fd = unsafe { libc::inotify_init1(libc::IN_CLOEXEC | libc::IN_NONBLOCK) };
    if fd < 0 {
        return Err(io::Error::last_os_error().into());
    }
    let ino = unsafe { OwnedFd::from_raw_fd(fd) };
    let home = home();
    let desktop_path = home.join("Desktop");
    let parent_watch = watch(fd, &home);
    let mut desktop_watch = watch(fd, &desktop_path);
    let mut network_bus = crate::bus::NetworkBus::new().ok();
    let mut devices = Devices::new();
    let mut gamma: Option<crate::bus::GammaBus> = None;
    let mut sensors = Sensors::discover();
    let cpu_name = read("/proc/cpuinfo")
        .lines()
        .find_map(|l| {
            l.strip_prefix("model name")
                .and_then(|l| l.split_once(':'))
                .map(|(_, s)| s.trim().to_string())
        })
        .unwrap_or_else(|| "CPU".into());
    let mut prev = Previous::default();
    let mut metric_files = MetricFiles::default();
    let mut metrics_out_buf = String::with_capacity(1024);
    let mut interval = 1000u64;
    let mut next = Instant::now();
    let mut sleep_inhibitor = None;
    let mut disk = crate::disk_worker::Worker::new().ok();
    let mut desktop_cache = std::collections::HashMap::new();
    let mut last_desktop = desktop(&mut desktop_cache);
    emit(&last_desktop)?;
    let mut input = Vec::with_capacity(4096);
    let mut buf = [0u8; 65536];
    let mut pipe_fds = [-1i32; 2];
    if unsafe { libc::pipe2(pipe_fds.as_mut_ptr(), libc::O_CLOEXEC | libc::O_NONBLOCK) } == 0 {
        start_thumbnail_worker(pipe_fds[1]);
    }
    nonblock(0);
    loop {
        let left = next.saturating_duration_since(Instant::now());
        let mut timeout = if left.is_zero() {
            0
        } else {
            left.as_millis().saturating_add(1).min(i32::MAX as u128) as i32
        };
        let mut gamma_fd = libc::pollfd {
            fd: -1,
            events: 0,
            revents: 0,
        };
        if let Some(bus) = gamma.as_ref() {
            match bus.poll_state() {
                Ok((fd, wait)) => {
                    gamma_fd = fd;
                    timeout = timeout.min(wait);
                }
                Err(_) => gamma = None,
            }
        }
        let (disk_fd, disk_timeout) = disk.as_ref().map_or(
            (
                libc::pollfd {
                    fd: -1,
                    events: 0,
                    revents: 0,
                },
                i32::MAX,
            ),
            |d| d.poll(),
        );
        timeout = timeout.min(disk_timeout);
        let mut fds = [
            libc::pollfd {
                fd: 0,
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: ino.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: devices.fd(),
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: network_bus.as_ref().map_or(-1, |b| b.fd()),
                events: libc::POLLIN,
                revents: 0,
            },
            gamma_fd,
            disk_fd,
            libc::pollfd {
                fd: pipe_fds[0],
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        if unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as _, timeout) } < 0 {
            if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            break;
        }
        if fds[0].revents & (libc::POLLHUP | libc::POLLERR) != 0 {
            break;
        }
        if fds[0].revents & libc::POLLIN != 0 {
            let n = unsafe { libc::read(0, buf.as_mut_ptr().cast(), 4096) };
            if n == 0 {
                break;
            }
            if n > 0 {
                input.extend_from_slice(&buf[..n as usize]);
                let mut start = 0;
                while let Some(rel) = input[start..].iter().position(|b| *b == b'\n') {
                    let i = start + rel;
                    let s = String::from_utf8_lossy(&input[start..i]);
                    start = i + 1;
                    if let Some(v) = s
                        .strip_prefix("interval ")
                        .and_then(|s| s.parse::<i64>().ok())
                    {
                        interval = v.clamp(250, 60000) as u64;
                        next = next.min(Instant::now() + Duration::from_millis(interval));
                    } else if let Some(raw) = s.strip_prefix("gamma ") {
                        if let Ok((id, name, value)) =
                            serde_json::from_str::<(u64, String, f64)>(raw)
                        {
                            if gamma.is_none() {
                                gamma = crate::bus::GammaBus::new().ok();
                            }
                            if !gamma
                                .as_mut()
                                .is_some_and(|b| b.set(id, &name, value).is_ok())
                            {
                                crate::bus::gamma_reply(id, false);
                            }
                        }
                    } else if s == "recording on" {
                        match network_bus
                            .as_ref()
                            .ok_or_else(|| "System bus unavailable".into())
                            .and_then(|b| b.inhibit())
                        {
                            Ok(fd) => sleep_inhibitor = Some(fd),
                            Err(e) => {
                                emit(
                                    &json!({"type":"recording-warning","message":format!("Suspend protection unavailable: {e}")}),
                                )?;
                            }
                        }
                    } else if s == "recording off" {
                        sleep_inhibitor.take();
                    } else if s == "drives" {
                        if disk.is_none() {
                            disk = crate::disk_worker::Worker::new().ok();
                        }
                    } else if s == "refresh" {
                        next = Instant::now()
                    }
                }
                if start > 0 {
                    input.drain(..start);
                }
                if input.len() > 4096 {
                    input.clear();
                }
            }
        }
        let mut desktop_changed = false;
        if pipe_fds[0] >= 0 && fds[6].revents & libc::POLLIN != 0 {
            let mut drain = [0u8; 64];
            while unsafe { libc::read(pipe_fds[0], drain.as_mut_ptr().cast(), drain.len()) } > 0 {}
            desktop_changed = true;
        }
        if fds[1].revents & libc::POLLIN != 0 {
            loop {
                let n = unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) };
                if n <= 0 {
                    break;
                }
                let mut pos = 0;
                while pos + std::mem::size_of::<libc::inotify_event>() <= n as usize {
                    let ev = unsafe {
                        std::ptr::read_unaligned(
                            buf.as_ptr().add(pos).cast::<libc::inotify_event>(),
                        )
                    };
                    let end = pos + 16 + ev.len as usize;
                    if end > n as usize {
                        break;
                    }
                    let name = &buf[pos + 16..end];
                    if ev.wd == desktop_watch || ev.mask & libc::IN_Q_OVERFLOW != 0 {
                        desktop_changed = true;
                        if ev.mask & (libc::IN_IGNORED | libc::IN_MOVE_SELF | libc::IN_DELETE_SELF)
                            != 0
                        {
                            if ev.mask & libc::IN_IGNORED == 0 {
                                unsafe {
                                    libc::inotify_rm_watch(fd, desktop_watch);
                                }
                            }
                            desktop_watch = -1;
                        }
                    }
                    if ev.wd == parent_watch && name.split(|b| *b == 0).next() == Some(b"Desktop") {
                        desktop_changed = true;
                    }
                    pos = end;
                }
            }
            if desktop_watch < 0 {
                desktop_watch = watch(fd, &desktop_path);
            }
        }
        if desktop_changed {
            let d = desktop(&mut desktop_cache);
            if d != last_desktop {
                emit(&d)?;
                last_desktop = d;
            }
        }
        if fds[2].revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0 {
            devices.disconnect();
        }
        if fds[2].revents & libc::POLLIN != 0 && devices.drain() {
            sensors = Sensors::discover();
        }
        if fds[3].revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0 {
            network_bus = None;
        }
        if fds[3].revents & libc::POLLIN != 0 {
            if let Some(bus) = network_bus.as_mut() {
                match bus.process() {
                    Ok(true) => emit(&json!({"type":"network-changed"}))?,
                    Ok(false) => (),
                    Err(_) => {
                        network_bus = None;
                    }
                }
            }
        }
        if fds[4].revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
            || gamma.as_mut().is_some_and(|b| b.process().is_err())
        {
            gamma = None;
        }
        if disk.as_mut().is_some_and(|d| d.process().unwrap_or(true)) {
            disk = None;
        }
        if Instant::now() >= next {
            if network_bus.is_none() {
                network_bus = crate::bus::NetworkBus::new().ok();
                if network_bus.is_some() {
                    emit(&json!({"type":"network-changed"}))?;
                }
            }
            if devices.fd() < 0 {
                devices = Devices::new();
                if devices.fd() >= 0 {
                    sensors = Sensors::discover();
                }
            }
            emit_metrics(&mut metrics_out_buf, &mut metric_files, &mut prev, &sensors, &cpu_name)?;
            next = Instant::now() + Duration::from_millis(interval);
        }
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn formats() {
        assert_eq!(human(0), "0 B");
        assert_eq!(human(1024), "1.0 KiB");
        assert_eq!(human(1 << 30), "1.0 GiB");
    }

    #[test]
    fn video_paths() {
        assert!(is_video_path(Path::new("video.mp4")));
        assert!(is_video_path(Path::new("movie.mkv")));
        assert!(is_video_path(Path::new("clip.webm")));
        assert!(is_video_path(Path::new("test.avi")));
        assert!(!is_video_path(Path::new("image.png")));
        assert!(!is_video_path(Path::new("audio.mp3")));
    }

    #[test]
    fn freedesktop_hash_matches_spec() {
        let path = Path::new("/home/pc/Desktop/download.png");
        let hash = freedesktop_hash(path).unwrap();
        assert_eq!(hash, "afdad784558cfbb55ea21ee3821a333d");
    }
}
