use serde_json::Value;
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd, OwnedFd},
        unix::{fs::OpenOptionsExt, process::CommandExt},
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::OnceLock,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub fn home() -> &'static Path {
    static HOME: OnceLock<PathBuf> = OnceLock::new();
    HOME.get_or_init(|| {
        env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp"))
    })
}
pub fn config() -> &'static Path {
    static CONFIG: OnceLock<PathBuf> = OnceLock::new();
    CONFIG.get_or_init(|| {
        env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home().join(".config"))
    })
}
pub fn current_exe() -> &'static Path {
    static EXE: OnceLock<PathBuf> = OnceLock::new();
    EXE.get_or_init(|| env::current_exe().unwrap())
}
pub fn shell() -> &'static Path {
    static DIRECTORY: OnceLock<PathBuf> = OnceLock::new();
    DIRECTORY.get_or_init(|| current_exe().parent().unwrap().to_path_buf())
}
pub fn cache() -> &'static Path {
    static CACHE: OnceLock<PathBuf> = OnceLock::new();
    CACHE.get_or_init(|| {
        env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home().join(".cache"))
    })
}
pub fn expand(s: &str) -> PathBuf {
    if s == "~" {
        home().to_path_buf()
    } else if let Some(t) = s.strip_prefix("~/") {
        home().join(t)
    } else {
        PathBuf::from(s)
    }
}
pub fn read(p: impl AsRef<Path>) -> String {
    fs::read_to_string(p).unwrap_or_default()
}
pub fn json_file(p: impl AsRef<Path>) -> Value {
    fs::read(p)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or(Value::Null)
}
pub fn parse_ascii_u64(bytes: &[u8]) -> u64 {
    let mut n = 0u64;
    let mut started = false;
    for &b in bytes {
        if b.is_ascii_digit() {
            started = true;
            n = n.saturating_mul(10).saturating_add((b - b'0') as u64);
        } else if started {
            break;
        } else if !b.is_ascii_whitespace() {
            return 0;
        }
    }
    n
}
pub fn read_buf<'a>(p: impl AsRef<Path>, buf: &'a mut [u8]) -> Option<&'a [u8]> {
    let mut f = File::open(p).ok()?;
    let n = f.read(buf).ok()?;
    Some(&buf[..n])
}
pub fn read_u64(p: impl AsRef<Path>) -> u64 {
    let mut buf = [0u8; 48];
    read_buf(p, &mut buf).map_or(0, parse_ascii_u64)
}
pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
pub fn which(name: &str) -> Option<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    env::split_paths(&env::var_os("PATH").unwrap_or_default())
        .map(|p| p.join(name))
        .find(|p| {
            p.metadata()
                .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        })
}
pub fn has(s: &str) -> bool {
    which(s).is_some()
}
pub fn atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path.parent().ok_or("Path has no parent")?;
    fs::create_dir_all(parent)?;
    let mut seq = 0;
    let (temp, mut f) = loop {
        let p = parent.join(format!(
            ".{}.{}.{seq}.tmp",
            path.file_name().unwrap().to_string_lossy(),
            std::process::id()
        ));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&p)
        {
            Ok(f) => break (p, f),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => seq += 1,
            Err(e) => return Err(e.into()),
        }
    };
    let result = (|| -> Result<()> {
        f.write_all(bytes)?;
        f.sync_all()?;
        fs::rename(&temp, path)?;
        File::open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}
pub fn save_json(path: &Path, value: &Value) -> Result<()> {
    let mut b = serde_json::to_vec_pretty(value)?;
    b.push(b'\n');
    atomic(path, &b)
}
pub struct Lock(File);
impl Lock {
    pub fn new(p: &Path) -> Result<Self> {
        Self::open(p, false)
    }
    pub fn try_new(p: &Path) -> Result<Self> {
        Self::open(p, true)
    }
    fn open(p: &Path, nonblocking: bool) -> Result<Self> {
        fs::create_dir_all(p.parent().ok_or("No parent")?)?;
        let f = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(p)?;
        if unsafe {
            libc::flock(
                f.as_raw_fd(),
                libc::LOCK_EX | if nonblocking { libc::LOCK_NB } else { 0 },
            )
        } < 0
        {
            return Err(io::Error::last_os_error().into());
        }
        Ok(Self(f))
    }
}
impl Drop for Lock {
    fn drop(&mut self) {
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}
pub fn nonblock(fd: i32) {
    unsafe {
        let f = libc::fcntl(fd, libc::F_GETFL);
        if f >= 0 {
            libc::fcntl(fd, libc::F_SETFL, f | libc::O_NONBLOCK);
        }
    }
}
pub fn emit(v: &Value) -> io::Result<()> {
    let out = io::stdout();
    let mut out = out.lock();
    serde_json::to_writer(&mut out, v)?;
    out.write_all(b"\n")?;
    out.flush()
}
pub fn spawn(args: &[&str]) -> bool {
    if args.is_empty() {
        return false;
    }
    let mut c = Command::new(args[0]);
    c.args(&args[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    unsafe {
        c.pre_exec(|| {
            if libc::setsid() < 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    c.spawn().is_ok()
}
// Drain both output pipes and feed input with poll. No wait/sleep loop, shell,
// detached worker, or async runtime. Bound elapsed time and retained output.
pub fn execute(args: &[&str], seconds: u64, input: Option<&[u8]>) -> (i32, String, String) {
    let run = || -> Result<(i32, String, String)> {
        let mut cmd = Command::new(args.first().ok_or("Empty command")?);
        cmd.args(&args[1..])
            .stdin(if input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        unsafe {
            cmd.pre_exec(|| {
                libc::setpgid(0, 0);
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL);
                Ok(())
            });
        }
        let mut child = cmd.spawn()?;
        let mut stdout = child.stdout.take().unwrap();
        let mut stderr = child.stderr.take().unwrap();
        let mut stdin = child.stdin.take();
        let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, child.id(), 0) as i32 };
        if fd < 0 {
            let _ = child.kill();
            let _ = child.wait();
            return Err("Linux pidfd_open is required (kernel 5.3+)".into());
        }
        let pidfd = unsafe { OwnedFd::from_raw_fd(fd) };
        nonblock(stdout.as_raw_fd());
        nonblock(stderr.as_raw_fd());
        if let Some(ref f) = stdin {
            nonblock(f.as_raw_fd())
        }
        let deadline = Instant::now() + Duration::from_secs(seconds);
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let mut sent = 0;
        let data = input.unwrap_or(&[]);
        if data.is_empty() {
            stdin.take();
        }
        let mut buf = [0u8; 8192];
        let mut failed = None;
        let (mut out_open, mut err_open) = (true, true);
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                failed = Some("Command timed out");
                break;
            }
            let mut fds = [
                libc::pollfd {
                    fd: if out_open { stdout.as_raw_fd() } else { -1 },
                    events: libc::POLLIN,
                    revents: 0,
                },
                libc::pollfd {
                    fd: if err_open { stderr.as_raw_fd() } else { -1 },
                    events: libc::POLLIN,
                    revents: 0,
                },
                libc::pollfd {
                    fd: stdin.as_ref().map_or(-1, AsRawFd::as_raw_fd),
                    events: libc::POLLOUT,
                    revents: 0,
                },
                libc::pollfd {
                    fd: pidfd.as_raw_fd(),
                    events: libc::POLLIN,
                    revents: 0,
                },
            ];
            let n = unsafe {
                libc::poll(
                    fds.as_mut_ptr(),
                    4,
                    left.as_millis().saturating_add(1).min(i32::MAX as u128) as i32,
                )
            };
            if n < 0 {
                if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                failed = Some("Command poll failed");
                break;
            }
            if fds[2].revents != 0 {
                if let Some(ref mut f) = stdin {
                    match f.write(&data[sent..]) {
                        Ok(n) => sent += n,
                        Err(e) if e.kind() == io::ErrorKind::WouldBlock => (),
                        Err(_) => {
                            sent = data.len();
                        }
                    }
                }
                if sent == data.len() {
                    stdin.take();
                }
            }
            for (reader, dest, open) in [
                (&mut stdout as &mut dyn Read, &mut out, &mut out_open),
                (&mut stderr as &mut dyn Read, &mut err, &mut err_open),
            ] {
                if !*open {
                    continue;
                }
                loop {
                    match reader.read(&mut buf) {
                        Ok(0) => {
                            *open = false;
                            break;
                        }
                        Ok(n) => {
                            if dest.len() + n > 4 * 1024 * 1024 {
                                failed = Some("Command output exceeds 4 MiB");
                                break;
                            }
                            dest.extend_from_slice(&buf[..n]);
                        }
                        Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                        Err(_) => break,
                    }
                }
            }
            if failed.is_some() || fds[3].revents != 0 {
                break;
            }
        }
        if failed.is_some() {
            unsafe {
                libc::kill(-(child.id() as i32), libc::SIGKILL);
            }
        }
        let status = child.wait()?;
        Ok((
            if failed.is_some() {
                124
            } else {
                status.code().unwrap_or(1)
            },
            decode_output(out),
            failed
                .map(str::to_string)
                .unwrap_or_else(|| decode_output(err)),
        ))
    };
    run().unwrap_or_else(|e| (127, String::new(), e.to_string()))
}
fn decode_output(bytes: Vec<u8>) -> String {
    String::from_utf8(bytes).unwrap_or_else(|e| String::from_utf8_lossy(e.as_bytes()).into_owned())
}
pub fn output(args: &[&str]) -> String {
    execute(args, 15, None).1
}
pub fn run(args: &[&str]) -> (bool, String) {
    let (c, o, e) = execute(args, 20, None);
    (c == 0, if e.is_empty() { o } else { e }.trim().into())
}
pub fn stamp(format: &str) -> String {
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let mut b = [0u8; 128];
        let fmt = std::ffi::CString::new(format).unwrap();
        let n = libc::strftime(b.as_mut_ptr().cast(), b.len(), fmt.as_ptr(), &tm);
        String::from_utf8_lossy(&b[..n]).into_owned()
    }
}
