use crate::{bus::Bus, util::*};
use serde_json::json;
use std::{
    ffi::{c_char, c_int, c_void, CString},
    fs::{self, OpenOptions},
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    path::Path,
    ptr,
    time::SystemTime,
};
#[link(name = "libgio-2.0.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn g_file_new_for_path(p: *const c_char) -> *mut c_void;
    fn g_file_trash(f: *mut c_void, c: *mut c_void, e: *mut *mut c_void) -> c_int;
    fn g_file_move(
        s: *mut c_void,
        d: *mut c_void,
        flags: c_int,
        c: *mut c_void,
        progress: *mut c_void,
        data: *mut c_void,
        e: *mut *mut c_void,
    ) -> c_int;
}
#[link(name = "libgobject-2.0.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn g_object_unref(o: *mut c_void);
}
#[link(name = "libglib-2.0.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn g_error_free(e: *mut c_void);
}
struct GFile(*mut c_void);
impl Drop for GFile {
    fn drop(&mut self) {
        unsafe {
            g_object_unref(self.0);
        }
    }
}
fn file(p: &Path) -> Result<GFile> {
    let c = CString::new(p.as_os_str().as_bytes())?;
    let p = unsafe { g_file_new_for_path(c.as_ptr()) };
    if p.is_null() {
        Err("GIO allocation failed".into())
    } else {
        Ok(GFile(p))
    }
}
fn gio(source: &Path, destination: Option<&Path>) -> Result<()> {
    let src = file(source)?;
    let mut error = ptr::null_mut();
    let ok = unsafe {
        if let Some(p) = destination {
            let dst = file(p)?;
            g_file_move(
                src.0,
                dst.0,
                4 | 8,
                ptr::null_mut(),
                ptr::null_mut(),
                ptr::null_mut(),
                &mut error,
            )
        } else {
            g_file_trash(src.0, ptr::null_mut(), &mut error)
        }
    };
    if !error.is_null() {
        unsafe { g_error_free(error) }
    }
    if ok == 0 {
        Err("Filesystem operation failed".into())
    } else {
        Ok(())
    }
}
fn positions(source: &Path, destination: Option<&Path>) -> Result<()> {
    let p = shell().join("desktop_positions.json");
    let _lock = Lock::new(&shell().join(".desktop.lock"))?;
    let mut v = json_file(&p);
    if let Some(m) = v.as_object_mut() {
        let src_key = source.to_string_lossy();
        if let Some(val) = m.remove(src_key.as_ref()) {
            if let Some(d) = destination {
                m.insert(d.to_string_lossy().into_owned(), val);
            }
            save_json(&p, &v)?;
        }
    }
    Ok(())
}
fn valid_name(s: &str) -> bool {
    !s.is_empty() && s != "." && s != ".." && !s.contains(['\0', '/'])
}
pub fn action(args: &[String]) -> Result<()> {
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    match a.as_slice() {
        ["rename", src, name] => {
            let source = Path::new(src);
            let mut name = name.trim().to_string();
            if source.symlink_metadata().is_err() || !valid_name(&name) {
                return Err("Invalid source or name".into());
            }
            if source.extension().is_some_and(|e| e == "desktop") && !name.ends_with(".desktop") {
                name.push_str(".desktop")
            }
            let dest = source.with_file_name(name);
            if dest == source || dest.symlink_metadata().is_ok() {
                return Err("Destination exists".into());
            }
            let s = CString::new(source.as_os_str().as_bytes())?;
            let d = CString::new(dest.as_os_str().as_bytes())?;
            if unsafe {
                libc::renameat2(
                    libc::AT_FDCWD,
                    s.as_ptr(),
                    libc::AT_FDCWD,
                    d.as_ptr(),
                    libc::RENAME_NOREPLACE,
                )
            } < 0
            {
                return Err(std::io::Error::last_os_error().into());
            }
            positions(source, Some(&dest))
        }
        ["move", src, folder] => {
            let (source, folder) = (Path::new(src), Path::new(folder));
            if source.symlink_metadata().is_err() || !folder.is_dir() {
                return Err("Invalid source or directory".into());
            }
            let dest = folder.join(source.file_name().ok_or("Source has no name")?);
            if dest.symlink_metadata().is_ok() {
                return Err("Destination exists".into());
            }
            gio(source, Some(&dest))?;
            positions(source, None)
        }
        ["trash", src] => {
            let p = Path::new(src);
            if p.symlink_metadata().is_ok() {
                gio(p, None)?;
                positions(p, None)?;
            }
            Ok(())
        }
        ["delete", src] => {
            let p = Path::new(src);
            if p.symlink_metadata().is_ok() {
                if p.is_dir() && !p.is_symlink() {
                    fs::remove_dir_all(p)?;
                } else {
                    fs::remove_file(p)?;
                }
                positions(p, None)?;
            }
            Ok(())
        }
        ["copy", src, folder] => {
            let (source, folder) = (Path::new(src), Path::new(folder));
            if source.symlink_metadata().is_err() || !folder.is_dir() {
                return Err("Invalid source or directory".into());
            }
            let dest = folder.join(source.file_name().ok_or("Source has no name")?);
            if dest.symlink_metadata().is_ok() {
                return Err("Destination exists".into());
            }
            copy_recursive(source, &dest)?;
            Ok(())
        }
        ["duplicate", src] => {
            let source = Path::new(src);
            if source.symlink_metadata().is_err() {
                return Err("Source does not exist".into());
            }
            let parent = source.parent().unwrap_or_else(|| Path::new("."));
            let file_name = source.file_name().ok_or("Invalid source name")?.to_string_lossy();
            let (stem, ext) = if let Some(dot) = file_name.rfind('.') {
                if dot > 0 && !source.is_dir() {
                    (&file_name[..dot], Some(&file_name[dot..]))
                } else {
                    (file_name.as_ref(), None)
                }
            } else {
                (file_name.as_ref(), None)
            };
            let mut counter = 1;
            let dest = loop {
                let name = if counter == 1 {
                    format!("{} (copy){}", stem, ext.unwrap_or(""))
                } else {
                    format!("{} (copy {}){}", stem, counter, ext.unwrap_or(""))
                };
                let p = parent.join(&name);
                if p.symlink_metadata().is_err() {
                    break p;
                }
                counter += 1;
                if counter > 1000 {
                    return Err("Too many copies exist".into());
                }
            };
            copy_recursive(source, &dest)?;
            let p_store = shell().join("desktop_positions.json");
            if let Ok(_lock) = Lock::new(&shell().join(".desktop.lock")) {
                let mut v = json_file(&p_store);
                if let Some(m) = v.as_object_mut() {
                    if let Some(pos) = m.get(source.to_string_lossy().as_ref()).cloned() {
                        let mut new_pos = pos.clone();
                        if let Some(pos_obj) = new_pos.as_object_mut() {
                            if let Some(x) = pos_obj.get("x").and_then(|x| x.as_f64()) {
                                pos_obj.insert("x".into(), json!(x + 24.0));
                            }
                            if let Some(y) = pos_obj.get("y").and_then(|y| y.as_f64()) {
                                pos_obj.insert("y".into(), json!(y + 24.0));
                            }
                        }
                        m.insert(dest.to_string_lossy().into_owned(), new_pos);
                        let _ = save_json(&p_store, &v);
                    }
                }
            }
            Ok(())
        }
        ["copy-content", src] => {
            let p = Path::new(src);
            let meta = p.symlink_metadata()?;
            if meta.is_dir() {
                return Err("Cannot copy directory content".into());
            }
            if meta.len() > 30 * 1024 * 1024 {
                return Err("File too large for clipboard".into());
            }
            let is_png = p.extension().is_some_and(|e| e.eq_ignore_ascii_case("png"));
            let is_jpg = p.extension().is_some_and(|e| e.eq_ignore_ascii_case("jpg") || e.eq_ignore_ascii_case("jpeg"));
            let mime = if is_png {
                "image/png"
            } else if is_jpg {
                "image/jpeg"
            } else {
                "text/plain;charset=utf-8"
            };
            let content = fs::read(p)?;
            let mut child = std::process::Command::new("wl-copy")
                .args(["--type", mime])
                .stdin(std::process::Stdio::piped())
                .spawn()?;
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                stdin.write_all(&content)?;
            }
            let status = child.wait()?;
            if !status.success() {
                return Err("wl-copy failed".into());
            }
            Ok(())
        }
        ["copy-uri", src] => {
            let p = Path::new(src);
            if p.symlink_metadata().is_err() {
                return Err("File does not exist".into());
            }
            let abs = p.canonicalize().unwrap_or_else(|_| p.to_path_buf());
            let uri = format!("file://{}\r\n", abs.display());
            let mut child = std::process::Command::new("wl-copy")
                .args(["--type", "text/uri-list"])
                .stdin(std::process::Stdio::piped())
                .spawn()?;
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                stdin.write_all(uri.as_bytes())?;
            }
            let status = child.wait()?;
            if !status.success() {
                return Err("wl-copy failed".into());
            }
            Ok(())
        }
        ["compress", src] => {
            let source = Path::new(src);
            if source.symlink_metadata().is_err() {
                return Err("Source does not exist".into());
            }
            let parent = source.parent().unwrap_or_else(|| Path::new("."));
            let name = source.file_name().ok_or("Invalid source name")?.to_string_lossy();
            let dest = parent.join(format!("{}.zip", name));
            let status = std::process::Command::new("zip")
                .arg("-r")
                .arg(&dest)
                .arg(name.as_ref())
                .current_dir(parent)
                .status()?;
            if !status.success() {
                return Err("Compression failed".into());
            }
            Ok(())
        }
        ["extract", src] => {
            let source = Path::new(src);
            let parent = source.parent().unwrap_or_else(|| Path::new("."));
            let file_name = source.file_name().ok_or("Invalid source name")?.to_string_lossy();
            let stem = file_name.split('.').next().unwrap_or(&file_name);
            let dest = parent.join(stem);
            fs::create_dir_all(&dest)?;
            extract_archive(source, &dest)
        }
        ["extract-here", src] => {
            let source = Path::new(src);
            let parent = source.parent().unwrap_or_else(|| Path::new("."));
            extract_archive(source, parent)
        }
        ["extract-to", src, dest] => {
            let (source, dest) = (Path::new(src), Path::new(dest));
            fs::create_dir_all(dest)?;
            extract_archive(source, dest)
        }
        ["create", kind, name] => {
            let name = name.trim();
            if !valid_name(name) {
                return Err("Invalid name".into());
            }
            let dir = home().join("Desktop");
            fs::create_dir_all(&dir)?;
            let p = dir.join(name);
            if *kind == "folder" {
                fs::create_dir_all(p)?;
            } else {
                let f = OpenOptions::new()
                    .create(true)
                    .truncate(false)
                    .write(true)
                    .open(&p)?;
                f.set_modified(SystemTime::now())?;
                if ["shell", "sh"].contains(kind) {
                    let mut perm = f.metadata()?.permissions();
                    perm.set_mode(perm.mode() | 0o111);
                    f.set_permissions(perm)?;
                }
            }
            Ok(())
        }
        ["wallpaper", raw] => {
            let raw = raw.strip_prefix("file://").unwrap_or(raw);
            let fixed = raw.replace("Wallpaperios_", "Wallpaper/ios_");
            let raw = if raw.contains("Wallpaperios_")
                && !Path::new(raw).exists()
                && Path::new(&fixed).exists()
            {
                fixed.as_str()
            } else {
                raw
            };
            let p = expand(raw).canonicalize()?;
            save_json(&shell().join("wallpaper.json"), &json!({"path":p}))?;
            if let Ok(bus) = Bus::user() {
                let _ = bus.notify(
                    "Weylume",
                    "Wallpaper Set",
                    &p.file_name().unwrap_or_default().to_string_lossy(),
                    "preferences-desktop-wallpaper",
                );
            }
            Ok(())
        }
        _ => Err("Unsupported desktop action".into()),
    }
}

fn copy_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    if src.is_dir() {
        fs::create_dir_all(dst)?;
        for entry in fs::read_dir(src)? {
            let entry = entry?;
            let file_type = entry.file_type()?;
            let target = dst.join(entry.file_name());
            if file_type.is_dir() {
                copy_recursive(&entry.path(), &target)?;
            } else {
                fs::copy(entry.path(), target)?;
            }
        }
        Ok(())
    } else {
        fs::copy(src, dst).map(|_| ())
    }
}

fn extract_archive(src: &Path, dest: &Path) -> Result<()> {
    let filename = src.file_name().unwrap_or_default().to_string_lossy().to_lowercase();
    let status = if filename.ends_with(".zip") {
        std::process::Command::new("unzip")
            .arg("-q")
            .arg("-o")
            .arg(src)
            .arg("-d")
            .arg(dest)
            .status()?
    } else if filename.ends_with(".tar.gz") || filename.ends_with(".tgz") {
        std::process::Command::new("tar")
            .args(["-xzf", src.to_str().unwrap(), "-C", dest.to_str().unwrap()])
            .status()?
    } else if filename.ends_with(".tar.xz") {
        std::process::Command::new("tar")
            .args(["-xJf", src.to_str().unwrap(), "-C", dest.to_str().unwrap()])
            .status()?
    } else if filename.ends_with(".tar") {
        std::process::Command::new("tar")
            .args(["-xf", src.to_str().unwrap(), "-C", dest.to_str().unwrap()])
            .status()?
    } else {
        std::process::Command::new("7z")
            .args(["x", "-y", src.to_str().unwrap(), &format!("-o{}", dest.display())])
            .status()?
    };
    if !status.success() {
        return Err("Extraction failed".into());
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn names() {
        for s in ["", ".", "..", "a/b", "a\0b"] {
            assert!(!valid_name(s));
        }
        for s in ["a b", "é", "x.desktop"] {
            assert!(valid_name(s));
        }
    }

    #[test]
    fn duplicate_and_delete() {
        let tmp = std::env::temp_dir().join(format!("weylume-test-dup-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let src = tmp.join("note.txt");
        fs::write(&src, "hello world").unwrap();

        action(&["duplicate".into(), src.to_str().unwrap().into()]).unwrap();
        let dup = tmp.join("note (copy).txt");
        assert!(dup.exists());
        assert_eq!(fs::read_to_string(&dup).unwrap(), "hello world");

        action(&["delete".into(), dup.to_str().unwrap().into()]).unwrap();
        assert!(!dup.exists());

        action(&["delete".into(), src.to_str().unwrap().into()]).unwrap();
        assert!(!src.exists());
        let _ = fs::remove_dir_all(&tmp);
    }
}
