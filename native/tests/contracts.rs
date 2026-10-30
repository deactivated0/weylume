//! Regression tests run only in temporary directories, without a live session.
use serde_json::{json, Value};
use std::{
    fs,
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
    sync::atomic::{AtomicUsize, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
struct Fixture(PathBuf);
static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(0);
impl Fixture {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "weylume-test-{}-{}-{}",
            std::process::id(),
            NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&p).unwrap();
        fs::create_dir_all(p.join("home/Desktop")).unwrap();
        fs::create_dir_all(p.join("bin")).unwrap();
        let bin_src = env!("CARGO_BIN_EXE_weylume-native");
        let bin_dst = p.join("weylume-native");
        {
            let mut reader = fs::File::open(bin_src).unwrap();
            let mut writer = fs::OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&bin_dst)
                .unwrap();
            std::io::copy(&mut reader, &mut writer).unwrap();
            let _ = writer.sync_all();
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&bin_dst, fs::Permissions::from_mode(0o755));
        }
        Self(p)
    }
    fn command(&self) -> Command {
        let mut c = Command::new(self.0.join("weylume-native"));
        c.env("HOME", self.0.join("home"))
            .env("XDG_CONFIG_HOME", self.0.join("config"))
            .env("XDG_CACHE_HOME", self.0.join("cache"))
            .env("XDG_DATA_HOME", self.0.join("data"))
            .env("PATH", self.0.join("bin"))
            .env_remove("LABWC_PID")
            .env_remove("CLIPBOARD_STATE");
        c
    }
    fn spawn_cmd(cmd: &mut Command) -> std::io::Result<std::process::Child> {
        for _ in 0..20 {
            match cmd.spawn() {
                Ok(c) => return Ok(c),
                Err(e) if e.raw_os_error() == Some(26) => {
                    std::thread::sleep(Duration::from_millis(15));
                }
                Err(e) => return Err(e),
            }
        }
        cmd.spawn()
    }
    fn output_cmd(cmd: &mut Command) -> std::io::Result<std::process::Output> {
        for _ in 0..20 {
            match cmd.output() {
                Ok(o) => return Ok(o),
                Err(e) if e.raw_os_error() == Some(26) => {
                    std::thread::sleep(Duration::from_millis(15));
                }
                Err(e) => return Err(e),
            }
        }
        cmd.output()
    }
    fn status_cmd(cmd: &mut Command) -> std::io::Result<std::process::ExitStatus> {
        for _ in 0..20 {
            match cmd.status() {
                Ok(s) => return Ok(s),
                Err(e) if e.raw_os_error() == Some(26) => {
                    std::thread::sleep(Duration::from_millis(15));
                }
                Err(e) => return Err(e),
            }
        }
        cmd.status()
    }
    fn json(&self, args: &[&str]) -> Value {
        let mut c = self.command();
        c.args(args);
        let o = Self::output_cmd(&mut c).unwrap();
        assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stdout));
        serde_json::from_slice(&o.stdout).unwrap()
    }
    fn capture(&self, bytes: &[u8]) -> std::process::Output {
        let mut c = self.command();
        c.arg("clipboard-capture")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped());
        let mut p = Self::spawn_cmd(&mut c).unwrap();
        p.stdin.take().unwrap().write_all(bytes).unwrap();
        let output = p.wait_with_output().unwrap();
        assert!(output.status.success());
        output
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
#[test]
fn xml_edit_preserves_namespace_custom_keys_and_backup() {
    let f = Fixture::new();
    fs::create_dir_all(f.0.join("config/labwc")).unwrap();
    let rc = f.0.join("config/labwc/rc.xml");
    let original = r#"<labwc_config xmlns="http://openbox.org/3.4/rc"><keyboard><keybind key="W-1"><action name="Execute" command="custom"/></keybind></keyboard><core><gap>7</gap></core></labwc_config>"#;
    fs::write(&rc, original).unwrap();
    f.json(&["labwc-set", "workspaceCount", "4"]);
    let xml = fs::read_to_string(&rc).unwrap();
    assert!(xml.contains("command=\"custom\""));
    assert!(xml.contains("http://openbox.org/3.4/rc"));
    assert!(xml.contains("W-S-4"));
    assert_eq!(
        fs::read_to_string(rc.with_file_name("rc.xml.weylume.bak")).unwrap(),
        original
    );
    let d = f.json(&["labwc-data"]);
    assert_eq!(d["data"]["gap"], 7);
    assert_eq!(d["data"]["workspaceCount"], 4);
    fs::write(&rc, "<broken").unwrap();
    let o = f
        .command()
        .args(["labwc-set", "gap", "9"])
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert_eq!(fs::read_to_string(rc).unwrap(), "<broken");
}
#[test]
fn state_repair_backs_up_and_skips_identical_marker() {
    let f = Fixture::new();
    fs::write(f.0.join("settings.json"), "broken").unwrap();
    let d = f.json(&["state-validate"]);
    assert!(d["data"]["repaired"]
        .as_array()
        .unwrap()
        .contains(&json!("settings.json")));
    let marker = f.0.join(".state-version.json");
    let modified = marker.metadata().unwrap().modified().unwrap();
    f.json(&["state-validate"]);
    assert_eq!(marker.metadata().unwrap().modified().unwrap(), modified);
    assert!(fs::read_dir(&f.0).unwrap().flatten().any(|e| e
        .file_name()
        .to_string_lossy()
        .starts_with("settings.json.corrupt-")));
}
#[test]
fn desktop_rename_preserves_positions_and_rejects_overwrite() {
    let f = Fixture::new();
    let desktop = f.0.join("home/Desktop");
    let a = desktop.join("A.desktop");
    let b = desktop.join("B.desktop");
    fs::write(&a, "[Desktop Entry]\nName=A\n").unwrap();
    fs::write(
        f.0.join("desktop_positions.json"),
        serde_json::to_vec(&json!({a.to_str().unwrap():{"x":12,"y":24}})).unwrap(),
    )
    .unwrap();
    let mut cmd1 = f.command();
    cmd1.args(["desktop", "rename", a.to_str().unwrap(), "B"]);
    let o = Fixture::output_cmd(&mut cmd1).unwrap();
    assert!(o.status.success());
    assert!(b.exists());
    assert!(!a.exists());
    let v: Value =
        serde_json::from_slice(&fs::read(f.0.join("desktop_positions.json")).unwrap()).unwrap();
    assert_eq!(v[b.to_str().unwrap()]["x"], 12);
    fs::write(&a, "keep").unwrap();
    let mut cmd2 = f.command();
    cmd2.args(["desktop", "rename", b.to_str().unwrap(), "A"]);
    assert!(!Fixture::status_cmd(&mut cmd2).unwrap().success());
    assert_eq!(fs::read_to_string(a).unwrap(), "keep");
}
#[test]
fn clipboard_bounded_unicode_and_sensitive_inputs() {
    let f = Fixture::new();
    for (bytes, want) in [
        ("é العربية\n".as_bytes(), true),
        (b"x\0y".as_slice(), false),
        (b"\xff".as_slice(), false),
        (b"  \n".as_slice(), false),
    ] {
        let mut cmd = f.command();
        cmd.arg("clipboard-capture")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped());
        let mut p = Fixture::spawn_cmd(&mut cmd).unwrap();
        p.stdin.take().unwrap().write_all(bytes).unwrap();
        let o = p.wait_with_output().unwrap();
        assert!(o.status.success());
        assert_eq!(!o.stdout.is_empty(), want);
        if want {
            let v: Value = serde_json::from_slice(&o.stdout).unwrap();
            assert_eq!(v["text"], std::str::from_utf8(bytes).unwrap());
        }
    }
    let mut cmd_sens = f.command();
    cmd_sens.arg("clipboard-capture")
        .env("CLIPBOARD_STATE", "sensitive")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped());
    let mut p = Fixture::spawn_cmd(&mut cmd_sens).unwrap();
    let _ = p.stdin.take().unwrap().write_all(b"hidden");
    assert!(p.wait_with_output().unwrap().stdout.is_empty());
}
#[test]
fn clipboard_image_stays_private_and_cannot_escape_cache() {
    use std::os::unix::fs::PermissionsExt;
    let f = Fixture::new();
    let mut cmd_cap = f.command();
    cmd_cap.arg("clipboard-capture")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped());
    let mut p = Fixture::spawn_cmd(&mut cmd_cap).unwrap();
    p.stdin
        .take()
        .unwrap()
        .write_all(b"\x89PNG\r\n\x1a\nabc")
        .unwrap();
    let o = p.wait_with_output().unwrap();
    let v: Value = serde_json::from_slice(&o.stdout).unwrap();
    let path = PathBuf::from(v["path"].as_str().unwrap());
    assert!(path.exists());
    assert_eq!(path.metadata().unwrap().permissions().mode() & 0o777, 0o600);
    let outside = f.0.join("keep");
    fs::write(&outside, "keep").unwrap();
    let o = f
        .command()
        .args(["clipboard-image-delete", outside.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(outside.exists());
    f.json(&["clipboard-image-delete", path.to_str().unwrap()]);
    assert!(
        path.exists(),
        "new capture lease protects an in-flight save"
    );
    fs::File::open(&path)
        .unwrap()
        .set_times(fs::FileTimes::new().set_modified(UNIX_EPOCH))
        .unwrap();
    f.json(&["clipboard-image-delete", path.to_str().unwrap()]);
    assert!(!path.exists());
}
#[test]
fn clipboard_limits_keep_text_and_image_boundaries() {
    let f = Fixture::new();
    let text = vec![b'a'; 131072];
    let accepted: Value = serde_json::from_slice(&f.capture(&text).stdout).unwrap();
    assert_eq!(accepted["text"].as_str().unwrap().len(), text.len());
    assert!(f.capture(&vec![b'a'; 131073]).stdout.is_empty());
    assert!(f.capture(&vec![b'a'; 8 * 1024 * 1024]).stdout.is_empty());
    let mut image = vec![0; 8 * 1024 * 1024];
    image[..8].copy_from_slice(b"\x89PNG\r\n\x1a\n");
    let accepted: Value = serde_json::from_slice(&f.capture(&image).stdout).unwrap();
    assert_eq!(
        fs::metadata(accepted["path"].as_str().unwrap())
            .unwrap()
            .len(),
        image.len() as u64
    );
    image.push(0);
    assert!(f.capture(&image).stdout.is_empty());
}
#[test]
fn clipboard_retains_pins_and_collects_only_expired_unreferenced_files() {
    use std::os::unix::fs::symlink;
    let f = Fixture::new();
    let dir = f.0.join("cache/weylume/clipboard");
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join(".hidden"), "keep").unwrap();
    fs::create_dir(dir.join("folder")).unwrap();
    symlink("missing", dir.join("link")).unwrap();
    for i in 0..99 {
        let file = fs::File::create(dir.join(format!("old-{i:03}.png"))).unwrap();
        file.set_times(
            fs::FileTimes::new().set_modified(UNIX_EPOCH + Duration::from_secs(1000 + i)),
        )
        .unwrap();
    }
    fs::write(
        f.0.join("clipboard_history.json"),
        serde_json::to_vec(
            &json!({"history":[{"type":"image","path":dir.join("old-001.png"),"pinned":true}]}),
        )
        .unwrap(),
    )
    .unwrap();
    f.capture(b"\x89PNG\r\n\x1a\nfirst");
    assert!(!dir.join("old-000.png").exists());
    f.capture(b"\x89PNG\r\n\x1a\nsecond");
    assert!(!dir.join("old-000.png").exists());
    assert!(dir.join("old-001.png").exists());
    assert!(dir.join(".hidden").exists());
    assert!(dir.join("folder").is_dir());
    assert!(dir.join("link").symlink_metadata().unwrap().is_symlink());
}
#[test]
fn backend_exits_on_stdin_close() {
    let f = Fixture::new();
    let mut cmd = f.command();
    cmd.arg("backend")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut p = Fixture::spawn_cmd(&mut cmd).unwrap();
    drop(p.stdin.take());
    let start = std::time::Instant::now();
    loop {
        if let Some(status) = p.try_wait().unwrap() {
            assert!(status.success());
            break;
        }
        if start.elapsed() > Duration::from_secs(3) {
            let _ = p.kill();
            let _ = p.wait();
            panic!("backend did not exit after stdin closed")
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn dangling_symlink_actions_do_not_touch_targets() {
    use std::os::unix::fs::symlink;
    let f = Fixture::new();
    let desktop = f.0.join("home/Desktop");
    let missing = desktop.join("missing-target");
    let a = desktop.join("link");
    let b = desktop.join("renamed");
    symlink(&missing, &a).unwrap();
    let mut cmd1 = f.command();
    cmd1.args(["desktop", "rename", a.to_str().unwrap(), "renamed"]);
    assert!(Fixture::status_cmd(&mut cmd1).unwrap().success());
    assert_eq!(fs::read_link(&b).unwrap(), missing);
    let folder = desktop.join("folder");
    fs::create_dir(&folder).unwrap();
    let mut cmd2 = f.command();
    cmd2.args([
        "desktop",
        "move",
        b.to_str().unwrap(),
        folder.to_str().unwrap(),
    ]);
    assert!(Fixture::status_cmd(&mut cmd2).unwrap().success());
    let moved = folder.join("renamed");
    assert_eq!(fs::read_link(&moved).unwrap(), missing);
    assert!(f
        .command()
        .args(["desktop", "trash", moved.to_str().unwrap()])
        .status()
        .unwrap()
        .success());
    assert!(moved.symlink_metadata().is_err());
    assert!(!missing.exists());
}

#[test]
fn active_interval_shortens_pending_idle_deadline() {
    use std::{
        io::{BufRead, BufReader},
        sync::mpsc,
        thread,
    };
    let f = Fixture::new();
    let mut cmd = f.command();
    cmd.arg("backend")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut p = Fixture::spawn_cmd(&mut cmd).unwrap();
    let (tx, rx) = mpsc::channel();
    let stdout = p.stdout.take().unwrap();
    let reader = thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if serde_json::from_str::<Value>(&line).is_ok_and(|v| v["type"] == "metrics")
                && tx.send(()).is_err()
            {
                break;
            }
        }
    });
    // Force a sample which schedules the next one ten seconds away.
    p.stdin
        .as_mut()
        .unwrap()
        .write_all(b"interval 10000\nrefresh\n")
        .unwrap();
    let first = rx.recv_timeout(Duration::from_secs(3));
    // Drain a possible startup sample before measuring the active transition.
    thread::sleep(Duration::from_millis(100));
    while rx.try_recv().is_ok() {}
    p.stdin
        .as_mut()
        .unwrap()
        .write_all(b"interval 250\n")
        .unwrap();
    let active = rx.recv_timeout(Duration::from_secs(2));
    let _ = p.kill();
    let _ = p.wait();
    reader.join().unwrap();
    assert!(first.is_ok(), "backend did not produce initial sample");
    assert!(
        active.is_ok(),
        "active interval retained the ten-second idle deadline"
    );
}

#[test]
fn clipboard_generation_conflict_does_not_overwrite_pins() {
    let f = Fixture::new();
    let image: Value = serde_json::from_slice(&f.capture(b"\x89PNG\r\n\x1a\npin").stdout).unwrap();
    let save = |state: &Value| {
        let mut cmd = f.command();
        cmd.arg("clipboard-store")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped());
        let mut p = Fixture::spawn_cmd(&mut cmd).unwrap();
        p.stdin
            .take()
            .unwrap()
            .write_all(&serde_json::to_vec(state).unwrap())
            .unwrap();
        p.wait_with_output().unwrap()
    };
    let state =
        json!({"generation":0,"history":[{"type":"image","path":image["path"],"pinned":true}]});
    assert!(save(&state).status.success());
    assert!(!save(&json!({"generation":0,"history":[]})).status.success());
    let current: Value =
        serde_json::from_slice(&fs::read(f.0.join("clipboard_history.json")).unwrap()).unwrap();
    assert_eq!(current["generation"], 1);
    assert_eq!(current["history"][0]["pinned"], true);
    assert!(save(&json!({"generation":1,"history":[]})).status.success());
    assert!(PathBuf::from(image["path"].as_str().unwrap()).exists());
}
#[test]
fn workspace_sixteen_and_invalid_root() {
    let f = Fixture::new();
    f.json(&["labwc-set", "workspaceCount", "16"]);
    let path = f.0.join("config/labwc/rc.xml");
    let xml = fs::read_to_string(&path).unwrap();
    assert!(xml.contains("W-0"));
    assert!(xml.contains("W-F6"));
    assert!(xml.contains("W-S-F6"));
    fs::write(&path, "<unrelated/>").unwrap();
    assert!(!f
        .command()
        .args(["labwc-set", "gap", "5"])
        .output()
        .unwrap()
        .status
        .success());
    assert_eq!(fs::read_to_string(path).unwrap(), "<unrelated/>");
}
