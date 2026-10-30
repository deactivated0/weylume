use crate::util::*;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{self, Read},
    os::unix::fs::DirBuilderExt,
    path::PathBuf,
};
pub fn directory() -> PathBuf {
    cache().join("weylume/clipboard")
}
pub fn capture() -> Result<()> {
    if std::env::var("CLIPBOARD_STATE")
        .is_ok_and(|s| ["sensitive", "nil", "clear"].contains(&s.as_str()))
    {
        return Ok(());
    }
    const MAX_IMAGE: usize = 8 * 1024 * 1024;
    const MAX_TEXT: usize = 131072;
    let mut input = io::stdin().lock();
    let mut data = Vec::with_capacity(4096);
    input.by_ref().take(12).read_to_end(&mut data)?;
    let kind = if data.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some(("image/png", ".png"))
    } else if data.starts_with(b"\xff\xd8\xff") {
        Some(("image/jpeg", ".jpg"))
    } else if data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WEBP") {
        Some(("image/webp", ".webp"))
    } else {
        None
    };
    let limit = if kind.is_some() { MAX_IMAGE } else { MAX_TEXT };
    input
        .by_ref()
        .take((limit + 1 - data.len()) as u64)
        .read_to_end(&mut data)?;
    if data.is_empty() || data.len() > limit {
        // Preserve the original bounded consumption without retaining megabytes
        // of text which the history cannot accept.
        io::copy(
            &mut input.take((MAX_IMAGE + 1 - data.len()) as u64),
            &mut io::sink(),
        )?;
        return Ok(());
    }
    if let Some((mime, ext)) = kind {
        let dir = directory();
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&dir)?;
        let digest = format!("{:x}", Sha256::digest(&data));
        let path = dir.join(format!("{digest}{ext}"));
        let _lock = Lock::new(&dir.join(".store.lock"))?;
        // The persisted history owns retention. Recently captured files have a
        // lease so an older, in-flight history save cannot delete a new copy.
        collect(&json_file(shell().join("clipboard_history.json")))?;
        let used: u64 = fs::read_dir(&dir)?
            .flatten()
            .filter_map(|e| e.metadata().ok())
            .filter(|m| m.is_file())
            .map(|m| m.len())
            .sum();
        if !path.exists() && used.saturating_add(data.len() as u64) > 128 * 1024 * 1024 {
            emit(
                &json!({"type":"clipboard-error","message":"Image history quota reached (128 MiB). Unpin or remove images to free space."}),
            )?;
            return Ok(());
        }
        if path.exists() {
            // Refresh only the lease timestamp; avoid rewriting cached image bytes.
            let file = fs::File::open(&path)?;
            file.set_times(fs::FileTimes::new().set_modified(std::time::SystemTime::now()))?;
        } else {
            atomic(&path, &data)?;
        }
        #[derive(serde::Serialize)]
        struct ImageMessage<'a> {
            r#type: &'static str,
            path: &'a std::path::Path,
            mime: &'a str,
            hash: &'a str,
        }
        let out = io::stdout();
        let mut out = out.lock();
        serde_json::to_writer(&mut out, &ImageMessage { r#type: "image", path: &path, mime, hash: &digest })?;
        use std::io::Write;
        out.write_all(b"\n")?;
        out.flush()?;
    } else if !data.contains(&0) {
        if let Ok(text) = std::str::from_utf8(&data) {
            if !text.trim().is_empty() {
                #[derive(serde::Serialize)]
                struct TextMessage<'a> {
                    r#type: &'static str,
                    text: &'a str,
                }
                let out = io::stdout();
                let mut out = out.lock();
                serde_json::to_writer(&mut out, &TextMessage { r#type: "text", text })?;
                use std::io::Write;
                out.write_all(b"\n")?;
                out.flush()?;
            }
        }
    }
    Ok(())
}
pub fn checked(raw: &str, must_exist: bool) -> Result<PathBuf> {
    let root = directory().canonicalize()?;
    let expanded = expand(raw);
    let p = if must_exist {
        expanded.canonicalize()?
    } else {
        let parent = expanded
            .parent()
            .ok_or("Invalid clipboard path")?
            .canonicalize()?;
        parent.join(expanded.file_name().ok_or("Invalid clipboard path")?)
    };
    if !p.starts_with(&root) || p == root {
        return Err("Invalid clipboard image path".into());
    }
    if must_exist && (!p.is_file() || p.metadata()?.len() > 8 * 1024 * 1024) {
        return Err("Clipboard image is unavailable or too large".into());
    }
    Ok(p)
}

fn collect(state: &Value) -> Result<()> {
    let retained: std::collections::HashSet<&str> = state["history"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| v["path"].as_str())
        .collect();
    for entry in fs::read_dir(directory())?.flatten() {
        let name = entry.file_name();
        if name.as_encoded_bytes().starts_with(b".") {
            continue;
        }
        let Ok(file_type) = entry.file_type() else { continue };
        if !file_type.is_file() {
            continue;
        }
        let path = entry.path();
        if path.to_str().is_some_and(|s| retained.contains(s)) {
            continue;
        }
        if entry
            .metadata()?
            .modified()?
            .elapsed()
            .unwrap_or_default()
            .as_secs()
            >= 60
        {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

pub fn store() -> Result<Value> {
    let mut input = String::new();
    io::stdin()
        .take(16 * 1024 * 1024 + 1)
        .read_to_string(&mut input)?;
    if input.len() > 16 * 1024 * 1024 {
        return Err("Clipboard history exceeds 16 MiB".into());
    }
    let mut state: Value = serde_json::from_str(&input)?;
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory())?;
    let _lock = Lock::new(&directory().join(".store.lock"))?;
    let history = state["history"]
        .as_array_mut()
        .ok_or("Invalid clipboard history")?;
    for item in history {
        if item["type"] == "image" {
            let mut path = checked(item["path"].as_str().ok_or("Invalid image path")?, false)?;
            if path.exists() {
                path = checked(path.to_str().ok_or("Invalid image path")?, true)?;
            }
            item["path"] = json!(path);
        } else if item["text"].as_str().is_none_or(|s| s.len() > 131072) {
            return Err("Invalid clipboard text".into());
        }
    }
    let path = shell().join("clipboard_history.json");
    let old = json_file(&path);
    let generation = old["generation"].as_u64().unwrap_or(0);
    if state["generation"].as_u64().unwrap_or(0) != generation {
        return Err(
            "Clipboard history changed in another shell instance; reload before saving".into(),
        );
    }
    state["generation"] = json!(generation + 1);
    state["version"] = json!(2);
    save_json(&path, &state)?;
    collect(&state)?;
    Ok(json!({"generation":generation + 1}))
}

pub fn remove_unreferenced(raw: &str) -> Result<()> {
    let path = checked(raw, false)?;
    let _lock = Lock::new(&directory().join(".store.lock"))?;
    let state = json_file(shell().join("clipboard_history.json"));
    if state["history"]
        .as_array()
        .into_iter()
        .flatten()
        .any(|v| v["path"].as_str() == path.to_str())
    {
        return Err("Image is still referenced by clipboard history".into());
    }
    // Apply the same lease rule as every other cleanup path.
    collect(&state)
}
