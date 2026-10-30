//! At most one disposable statvfs worker; a stuck mount never stalls IPC.
use crate::util::*;
use serde_json::{json, Value};
use std::{
    io::Read,
    os::{fd::AsRawFd, unix::process::CommandExt},
    process::{Child, ChildStdout, Command, Stdio},
    time::{Duration, Instant},
};
pub struct Worker {
    child: Child,
    output: ChildStdout,
    bytes: Vec<u8>,
    deadline: Option<Instant>,
}
impl Worker {
    pub fn new() -> Result<Self> {
        let mut command = Command::new(current_exe());
        command
            .arg("disk-metrics")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        unsafe {
            command.pre_exec(|| {
                if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL) < 0 {
                    return Err(std::io::Error::last_os_error());
                }
                if libc::getppid() == 1 {
                    libc::_exit(1);
                }
                Ok(())
            });
        }
        let mut child = command.spawn()?;
        let output = child.stdout.take().unwrap();
        unsafe {
            let flags = libc::fcntl(output.as_raw_fd(), libc::F_GETFL);
            libc::fcntl(output.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK);
        }
        Ok(Self {
            child,
            output,
            bytes: Vec::new(),
            deadline: Some(Instant::now() + Duration::from_secs(2)),
        })
    }
    pub fn poll(&self) -> (libc::pollfd, i32) {
        (
            libc::pollfd {
                fd: self.output.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            },
            self.deadline.map_or(i32::MAX, |d| {
                d.saturating_duration_since(Instant::now())
                    .as_millis()
                    .min(i32::MAX as u128) as i32
            }),
        )
    }
    pub fn process(&mut self) -> Result<bool> {
        let mut buffer = [0; 8192];
        loop {
            match self.output.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => {
                    if self.bytes.len() + n > 65536 {
                        self.child.kill()?;
                        return Err("Disk metrics exceeded limit".into());
                    }
                    self.bytes.extend_from_slice(&buffer[..n]);
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(e) => return Err(e.into()),
            }
        }
        if let Some(status) = self.child.try_wait()? {
            if self.deadline.is_some() && status.success() {
                match serde_json::from_slice::<Value>(&self.bytes) {
                    Ok(data) => emit(&json!({"type":"drives","data":data,"stale":false}))?,
                    Err(_) => emit(
                        &json!({"type":"drives","stale":true,"error":"Invalid disk query response"}),
                    )?,
                }
            } else if self.deadline.is_some() {
                emit(&json!({"type":"drives","stale":true,"error":"Disk usage query failed"}))?;
            }
            return Ok(true);
        }
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            let _ = self.child.kill();
            self.deadline = None;
            emit(
                &json!({"type":"drives","stale":true,"error":"Disk usage query timed out; cached values retained"}),
            )?;
        }
        Ok(false)
    }
}
impl Drop for Worker {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.try_wait();
    }
}
