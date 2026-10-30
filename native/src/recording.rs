//! Recorder acknowledgements and output checks, active only on user actions.
use crate::util::*;
use serde_json::{json, Value};
use std::{
    fs,
    io::{BufRead, BufReader, Read, Write},
    os::unix::{fs::DirBuilderExt, net::UnixStream},
    time::Duration,
};
pub fn prepare(container: &str) -> Result<Value> {
    if !["mkv", "mp4", "webm"].contains(&container) {
        return Err("Unsupported recording container".into());
    }
    let directory = home().join("Videos");
    fs::create_dir_all(&directory)?;
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .ok_or("XDG_RUNTIME_DIR is unset")?
        .join("weylume");
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&runtime)?;
    let token = format!("{}-{}", now(), std::process::id());
    let path = directory.join(format!(
        "{}-{token}.{container}",
        stamp("Weylume_%Y-%m-%d_%H-%M-%S")
    ));
    let (_, out, err) = execute(&["gpu-screen-recorder", "--help"], 5, None);
    let help = out + &err;
    let ipc = help.contains("-ipc");
    let timestamp = help.contains("-write-first-frame-ts");
    if timestamp {
        atomic(&path.with_extension(format!("{container}.ts")), b"")?;
    }
    Ok(
        json!({"path":path,"socket":runtime.join(format!("record-{token}.sock")),"ipc":ipc,"timestamp":timestamp}),
    )
}
pub fn control(path: &str, action: &str) -> Result<Value> {
    let name = match action {
        "stop" => "stop",
        "pause" | "resume" => "set-paused",
        _ => return Err("Invalid recorder action".into()),
    };
    let mut socket = UnixStream::connect(path)?;
    let timeout = Duration::from_secs(if name == "stop" { 25 } else { 3 });
    socket.set_read_timeout(Some(timeout))?;
    socket.set_write_timeout(Some(Duration::from_secs(3)))?;
    let request = json!({"id":1,"name":name,"data":if name=="set-paused"{json!(action=="pause")}else{Value::Null}});
    serde_json::to_writer(&mut socket, &request)?;
    socket.write_all(b"\n")?;
    let mut line = String::new();
    BufReader::new(socket).take(65537).read_line(&mut line)?;
    if line.len() > 65536 {
        return Err("Recorder reply too large".into());
    }
    let reply: Value = serde_json::from_str(&line)?;
    if reply["id"] != 1 || reply["result"] != "ok" {
        return Err(reply["data"]
            .as_str()
            .unwrap_or("Recorder rejected the request")
            .into());
    }
    Ok(json!({"action":action,"path":reply["data"],"acknowledged":true}))
}
pub fn check(path: &str) -> Result<Value> {
    let file = fs::File::open(path)?;
    let size = file.metadata()?.len();
    if size < 1024 {
        return Err("Recording is empty or incomplete".into());
    }
    file.sync_all()?;
    Ok(json!({"path":path,"bytes":size}))
}
