//! Bounded local VEVENT import. Unsupported recurrence is reported, never guessed.
use crate::util::*;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    ffi::{c_char, c_int, c_void, CString},
    io::Read,
};
#[link(name = "libglib-2.0.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn g_time_zone_new_identifier(id: *const c_char) -> *mut c_void;
    fn g_time_zone_new_local() -> *mut c_void;
    fn g_time_zone_unref(t: *mut c_void);
    fn g_date_time_new(
        z: *mut c_void,
        y: c_int,
        m: c_int,
        d: c_int,
        h: c_int,
        min: c_int,
        s: f64,
    ) -> *mut c_void;
    fn g_date_time_to_unix(t: *mut c_void) -> i64;
    fn g_date_time_unref(t: *mut c_void);
}
fn unescape(s: &str) -> String {
    let mut out = String::new();
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            if let Some(c) = chars.next() {
                out.push(if c == 'n' || c == 'N' { '\n' } else { c });
            }
        } else {
            out.push(c);
        }
    }
    out
}
fn date(raw: &str, params: &str) -> Result<i64> {
    let s = raw.trim();
    if ![8, 15, 16].contains(&s.len()) || !s.is_ascii() {
        return Err("Unsupported calendar date".into());
    }
    let number = |a, b| -> Result<i32> { Ok(s[a..b].parse()?) };
    let (y, m, d) = (number(0, 4)?, number(4, 6)?, number(6, 8)?);
    let (h, min, sec) = if s.len() > 8 {
        if &s[8..9] != "T" {
            return Err("Invalid calendar time".into());
        }
        (number(9, 11)?, number(11, 13)?, number(13, 15)?)
    } else {
        (0, 0, 0)
    };
    let zone = params.split(';').find_map(|p| p.strip_prefix("TZID="));
    unsafe {
        let z = if s.ends_with('Z') {
            g_time_zone_new_identifier(c"UTC".as_ptr())
        } else if let Some(zone) = zone {
            let c = CString::new(zone.trim_matches('"'))?;
            g_time_zone_new_identifier(c.as_ptr())
        } else {
            g_time_zone_new_local()
        };
        if z.is_null() {
            return Err("Unknown calendar time zone".into());
        }
        let dt = g_date_time_new(z, y, m, d, h, min, sec as f64);
        g_time_zone_unref(z);
        if dt.is_null() {
            return Err("Invalid calendar date or time".into());
        }
        let stamp = g_date_time_to_unix(dt) * 1000;
        g_date_time_unref(dt);
        Ok(stamp)
    }
}
fn reminder(raw: &str) -> Option<i64> {
    let rest = raw.strip_prefix("-PT")?;
    let unit = rest.chars().last()?;
    let n: i64 = rest[..rest.len() - 1].parse().ok()?;
    if n < 0 {
        return None;
    }
    let multiplier = match unit {
        'M' => 60_000,
        'H' => 3_600_000,
        'S' => 1000,
        _ => return None,
    };
    n.checked_mul(multiplier)
}
pub fn import(raw: &str) -> Result<Value> {
    let path = expand(raw);
    let mut text = String::new();
    std::fs::File::open(path)?
        .take(8 * 1024 * 1024 + 1)
        .read_to_string(&mut text)?;
    if text.len() > 8 * 1024 * 1024 {
        return Err("Calendar exceeds 8 MiB".into());
    }
    parse(&text)
}
fn parse(text: &str) -> Result<Value> {
    if !text.lines().any(|s| s.trim_end() == "BEGIN:VCALENDAR") {
        return Err("Expected an iCalendar file".into());
    }
    let mut lines: Vec<String> = Vec::new();
    for line in text.lines() {
        let line = line.trim_end_matches('\r');
        if line.starts_with([' ', '\t']) {
            if let Some(last) = lines.last_mut() {
                last.push_str(&line[1..]);
            }
        } else {
            lines.push(line.into());
        }
    }
    let (mut fields, mut events, mut warnings) = (
        BTreeMap::<String, (String, String)>::new(),
        Vec::new(),
        Vec::new(),
    );
    let (mut inside, mut alarm) = (false, false);
    for line in lines {
        if line == "BEGIN:VEVENT" {
            if inside {
                return Err("Nested VEVENT".into());
            }
            fields.clear();
            inside = true;
            continue;
        }
        if !inside {
            continue;
        }
        if line == "BEGIN:VALARM" {
            alarm = true;
            continue;
        }
        if line == "END:VALARM" {
            alarm = false;
            continue;
        }
        if line == "END:VEVENT" {
            inside = false;
            if events.len() >= 2000 {
                return Err("Calendar exceeds 2000 events".into());
            }
            let get = |k: &str| fields.get(k).map_or("", |(_, v)| v.as_str());
            let uid = if get("UID").is_empty() {
                format!(
                    "{:x}",
                    Sha256::digest(format!("{}{}", get("DTSTART"), get("SUMMARY")).as_bytes())
                )
            } else {
                get("UID").chars().take(512).collect()
            };
            let id = format!("ics:{uid}");
            if get("STATUS") == "CANCELLED" {
                events.push(json!({"id":id,"cancelled":true}));
                continue;
            }
            if fields.contains_key("RRULE")
                || fields.contains_key("RDATE")
                || fields.contains_key("RECURRENCE-ID")
            {
                warnings.push(format!(
                    "{}: recurrence is not supported; export expanded occurrences",
                    get("SUMMARY")
                ));
                continue;
            }
            let Some((params, start)) = fields.get("DTSTART") else {
                warnings.push(format!("{}: missing DTSTART", get("SUMMARY")));
                continue;
            };
            let start = date(start, params)?;
            let end = if let Some((p, v)) = fields.get("DTEND") {
                date(v, p)?
            } else {
                start + 3_600_000
            };
            if end < start {
                return Err("Calendar event ends before it starts".into());
            }
            events.push(json!({"id":id,"title":unescape(get("SUMMARY")).chars().take(1024).collect::<String>(),"startTimestamp":start,"endTimestamp":end,"meta":unescape(get("LOCATION")).chars().take(2048).collect::<String>(),"type":"meeting","completed":false,"reminderTimestamp":start-reminder(get("TRIGGER")).unwrap_or(15*60_000),"imported":true}));
            continue;
        }
        if let Some((key, value)) = line.split_once(':') {
            let name = key.split(';').next().unwrap_or("");
            if (!alarm || name == "TRIGGER")
                && [
                    "UID",
                    "SUMMARY",
                    "DTSTART",
                    "DTEND",
                    "LOCATION",
                    "STATUS",
                    "RRULE",
                    "RDATE",
                    "RECURRENCE-ID",
                    "TRIGGER",
                ]
                .contains(&name)
            {
                fields.insert(name.into(), (key.into(), value.into()));
            }
        }
    }
    if inside {
        return Err("Truncated calendar event".into());
    }
    Ok(json!({"events":events,"warnings":warnings}))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn import_validation() {
        let v=parse("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:one\r\nDTSTART:20261001T090000Z\r\nSUMMARY:One\\, two\r\n continued\r\nEND:VEVENT\r\nEND:VCALENDAR").unwrap();
        assert_eq!(v["events"][0]["title"], "One, twocontinued");
        assert_eq!(v["events"][0]["startTimestamp"], 1790845200000i64);
        assert!(date("20261301", "").is_err());
        assert!(parse("BEGIN:VCALENDAR\nBEGIN:VEVENT").is_err());
    }
}
