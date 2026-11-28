// =============================================================================
// lk — LogKlerk v0.0.2 (experimental) — single-file Rust version
//
// Port of the original POSIX shell modules (lk.sh + modules/*.sh) into one
// binary with no external dependencies (std only). The Markdown log format is
// identical to the shell version, so existing vaults keep working.
//
// Build:   cargo build --release
// Target:  Linux / macOS / BSD (needs localtime_r from libc)
// =============================================================================

#![allow(dead_code)]

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::io::{self, BufRead, Write};
use std::os::raw::{c_char, c_int, c_long};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

mod default_tags;
use default_tags::{BUILTIN_EXCLUSIVE, BUILTIN_TAGS};

const LK_STATUS: &str = "experimental";
const LK_VERSION: &str = "v0.0.2";

// ----------------------------------------------------------------------------
// Color palette (ANSI true-color)
// ----------------------------------------------------------------------------
const RESET: &str = "\x1b[0m";
const AMBER: &str = "\x1b[38;2;255;204;0m";
const LIME: &str = "\x1b[38;2;100;255;0m";
const GREY: &str = "\x1b[38;2;150;150;150m";
const CYAN: &str = "\x1b[38;2;0;255;255m";
const ORANGE: &str = "\x1b[38;2;255;102;0m";
const MAGENTA: &str = "\x1b[38;2;255;100;255m";
const PURPLE: &str = "\x1b[38;2;170;100;255m";
const HEADER_ORG: &str = "\x1b[38;2;255;117;0m";
const RED: &str = "\x1b[31m";
const DIM: &str = "\x1b[2m";
const PATH_GREY: &str = "\x1b[38;2;85;85;85m";
const DARK: &str = "\x1b[38;2;70;70;70m";
const DARKGREY: &str = "\x1b[38;2;90;90;90m";
const GOLD: &str = "\x1b[38;2;255;215;0m";
const LRED: &str = "\x1b[38;2;255;50;50m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const WHITE: &str = "\x1b[37m";
const B_RED: &str = "\x1b[91m";
const GREY245: &str = "\x1b[38;5;245m";
const ARROW: &str = "\x1b[38;2;255;102;0m->\x1b[0m";
// lkweight palette
const W_MERAHTUA: &str = "\x1b[38;2;170;0;0m";
const W_MERAH: &str = "\x1b[38;2;255;50;50m";
const W_KUNING: &str = "\x1b[38;2;255;200;0m";
const W_HIJAU: &str = "\x1b[38;2;100;255;0m";
const W_BIRU: &str = "\x1b[38;2;0;200;255m";
const W_BIRUTUA: &str = "\x1b[38;2;100;100;255m";

// ----------------------------------------------------------------------------
// Local time (localtime_r straight from libc, no crates)
// ----------------------------------------------------------------------------
#[repr(C)]
struct CTm {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: *const c_char,
}

extern "C" {
    fn localtime_r(t: *const c_long, out: *mut CTm) -> *mut CTm;
    fn signal(sig: c_int, handler: usize) -> usize;
}

#[derive(Clone, Copy)]
struct Now {
    y: i32,
    mo: u32,
    d: u32,
    h: u32,
    mi: u32,
    s: u32,
}

impl Now {
    fn year(&self) -> String {
        format!("{:04}", self.y)
    }
    fn month(&self) -> String {
        format!("{:04}-{:02}", self.y, self.mo)
    }
    fn date(&self) -> String {
        format!("{:04}-{:02}-{:02}", self.y, self.mo, self.d)
    }
    fn hour(&self) -> String {
        format!("{:02}:00", self.h)
    }
    fn hh(&self) -> String {
        format!("{:02}", self.h)
    }
    fn time(&self) -> String {
        format!("{:02}:{:02}:{:02}", self.h, self.mi, self.s)
    }
}

fn now() -> Now {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as c_long)
        .unwrap_or(0);
    let mut tm = CTm {
        tm_sec: 0,
        tm_min: 0,
        tm_hour: 0,
        tm_mday: 1,
        tm_mon: 0,
        tm_year: 70,
        tm_wday: 0,
        tm_yday: 0,
        tm_isdst: 0,
        tm_gmtoff: 0,
        tm_zone: std::ptr::null(),
    };
    unsafe {
        localtime_r(&secs, &mut tm);
    }
    Now {
        y: tm.tm_year + 1900,
        mo: (tm.tm_mon + 1) as u32,
        d: tm.tm_mday as u32,
        h: tm.tm_hour as u32,
        mi: tm.tm_min as u32,
        s: tm.tm_sec as u32,
    }
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = (if y >= 0 { y } else { y - 399 }) / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719468;
    let era = (if z >= 0 { z } else { z - 146096 }) / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn days_in_month(y: i64, m: i64) -> i64 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ => {
            if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 {
                29
            } else {
                28
            }
        }
    }
}

// ----------------------------------------------------------------------------
// Configuration
// ----------------------------------------------------------------------------
struct Cfg {
    home: PathBuf,
    config_dir: PathBuf,
    config_file: PathBuf,
    modules_dir: PathBuf,
    taxonomy_file: PathBuf,
    lk_dir: PathBuf,
    fmt: String,
    tail: usize,
    cmd_tail: usize,
    set_tail: usize,
    snap_dir: PathBuf,
}

static CFG: OnceLock<Cfg> = OnceLock::new();

fn cfg() -> &'static Cfg {
    CFG.get_or_init(load_cfg)
}

fn expand_vars(v: &str, vars: &HashMap<String, String>) -> String {
    let mut out = v.to_string();
    for (k, val) in vars.iter() {
        out = out.replace(&format!("${{{}}}", k), val);
    }
    // Plain $VAR: longest names first so $HOME_X is not mangled
    let mut keys: Vec<&String> = vars.keys().collect();
    keys.sort_by(|a, b| b.len().cmp(&a.len()));
    for k in keys {
        out = out.replace(&format!("${}", k), &vars[k]);
    }
    out
}

fn strip_quotes(s: &str) -> String {
    let t = s.trim();
    let t = t.strip_prefix('"').or_else(|| t.strip_prefix('\'')).unwrap_or(t);
    let t = t.strip_suffix('"').or_else(|| t.strip_suffix('\'')).unwrap_or(t);
    t.to_string()
}

fn parse_conf(text: &str, vars: &mut HashMap<String, String>) {
    for raw in text.lines() {
        let l = raw.trim();
        if l.is_empty() || l.starts_with('#') {
            continue;
        }
        let eq = match l.find('=') {
            Some(i) => i,
            None => continue,
        };
        let key = l[..eq].trim();
        if key.is_empty() || !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            continue;
        }
        let val_raw = &l[eq + 1..];
        // Dynamic shell values ($(...), `...`) are not evaluated.
        if val_raw.contains("$(") || val_raw.contains('`') {
            continue;
        }
        let val = expand_vars(&strip_quotes(val_raw), vars);
        vars.insert(key.to_string(), val);
    }
}

fn load_cfg() -> Cfg {
    let home = PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".to_string()));
    let config_dir = home
        .join(".config")
        .join("lk")
        .join(LK_STATUS)
        .join(LK_VERSION);
    let config_file = config_dir.join("lk.conf");

    if !config_dir.is_dir() {
        let _ = fs::create_dir_all(&config_dir);
        let _ = fs::create_dir_all(home.join("lk"));
        let _ = fs::write(
            &config_file,
            format!(
                "LK_DIR=\"{}/lk\"\nLK_TAIL_LINES=\"10\"\nLK_DEFAULT_FORMAT=\".md\"\n",
                home.display()
            ),
        );
    }

    let mut vars: HashMap<String, String> = HashMap::new();
    vars.insert("HOME".to_string(), home.display().to_string());
    vars.insert("LK_STATUS".to_string(), LK_STATUS.to_string());
    vars.insert("LK_VERSION".to_string(), LK_VERSION.to_string());
    vars.insert(
        "LK_CONFIG_DIR".to_string(),
        config_dir.display().to_string(),
    );
    if let Ok(text) = fs::read(&config_file) {
        parse_conf(&String::from_utf8_lossy(&text), &mut vars);
    }

    let mut lk_dir = std::env::var("LK_DIR")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| vars.get("LK_DIR").cloned())
        .unwrap_or_else(|| format!("{}/lk", home.display()));
    while lk_dir.len() > 1 && lk_dir.ends_with('/') {
        lk_dir.pop();
    }

    let num = |key: &str, def: usize| -> usize {
        vars.get(key)
            .and_then(|v| v.trim().parse::<usize>().ok())
            .unwrap_or(def)
    };
    let fmt = vars
        .get("LK_DEFAULT_FORMAT")
        .cloned()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| ".md".to_string());
    let snap = vars
        .get("LK_SNAP_DIR")
        .cloned()
        .unwrap_or_else(|| format!("{}/snapshots/lk", home.display()));

    let modules_dir = config_dir.join("modules");
    Cfg {
        taxonomy_file: modules_dir.join("context.sh"),
        modules_dir,
        tail: num("LK_TAIL_LINES", 10),
        cmd_tail: num("LK_COMMAND_TAIL_LINES", 3),
        set_tail: num("LKSET_TAIL_LINES", 5),
        lk_dir: PathBuf::from(lk_dir),
        fmt,
        snap_dir: PathBuf::from(snap.trim_end_matches('/')),
        config_dir,
        config_file,
        home,
    }
}

// ----------------------------------------------------------------------------
// File utilities
// ----------------------------------------------------------------------------
fn read_text(p: &Path) -> String {
    fs::read(p)
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .unwrap_or_default()
}

fn read_lines(p: &Path) -> Vec<String> {
    read_text(p).lines().map(|s| s.to_string()).collect()
}

fn write_lines(p: &Path, lines: &[String]) -> io::Result<()> {
    let mut body = lines.join("\n");
    body.push('\n');
    write_atomic(p, &body)
}

fn write_atomic(p: &Path, body: &str) -> io::Result<()> {
    if let Some(parent) = p.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let tmp = PathBuf::from(format!("{}.tmp", p.display()));
    fs::write(&tmp, body)?;
    fs::rename(&tmp, p)
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    if let Ok(rd) = fs::read_dir(dir) {
        for e in rd.flatten() {
            let p = e.path();
            match e.file_type() {
                Ok(ft) if ft.is_dir() => walk(&p, out),
                Ok(_) => out.push(p),
                Err(_) => {}
            }
        }
    }
}

fn fname(p: &Path) -> String {
    p.file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn is_digit(b: u8) -> bool {
    b.is_ascii_digit()
}

fn all_digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(is_digit)
}

fn is_date_file(name: &str) -> bool {
    let b = name.as_bytes();
    b.len() == 13
        && name.ends_with(".md")
        && b[..4].iter().all(|c| is_digit(*c))
        && b[4] == b'-'
        && is_digit(b[5])
        && is_digit(b[6])
        && b[7] == b'-'
        && is_digit(b[8])
        && is_digit(b[9])
}

fn date_of(p: &Path) -> String {
    fname(p).chars().take(10).collect()
}

fn is_date_str(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 10
        && b[..4].iter().all(|c| is_digit(*c))
        && b[4] == b'-'
        && is_digit(b[5])
        && is_digit(b[6])
        && b[7] == b'-'
        && is_digit(b[8])
        && is_digit(b[9])
}

fn is_month_str(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 7 && b[..4].iter().all(|c| is_digit(*c)) && b[4] == b'-' && is_digit(b[5]) && is_digit(b[6])
}

fn date_files_in(dir: &Path) -> Vec<PathBuf> {
    let mut v = Vec::new();
    walk(dir, &mut v);
    v.retain(|p| is_date_file(&fname(p)));
    v.sort();
    v
}

fn day_path(date: &str) -> PathBuf {
    // date = YYYY-MM-DD
    let y = &date[..4];
    let m = &date[..7];
    cfg().lk_dir.join(y).join(m).join(format!("{}{}", date, cfg().fmt))
}

fn today_path(n: &Now) -> PathBuf {
    cfg()
        .lk_dir
        .join(n.year())
        .join(n.month())
        .join(format!("{}{}", n.date(), cfg().fmt))
}

fn run_editor(path: &Path) {
    let ed = std::env::var("EDITOR")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| std::env::var("VISUAL").ok().filter(|s| !s.is_empty()))
        .unwrap_or_else(|| "vi".to_string());
    let _ = Command::new("sh")
        .arg("-c")
        .arg(format!("{} \"$1\"", ed))
        .arg("lk-editor")
        .arg(path)
        .status();
}

fn flush() {
    let _ = io::stdout().flush();
}

fn tail_of(path: &Path, n: usize) -> Vec<String> {
    let lines = read_lines(path);
    let start = lines.len().saturating_sub(n);
    lines[start..].to_vec()
}

// mkdir-based lock (atomic on every filesystem) with stale-lock detection.
fn with_lock<T, F: FnOnce() -> T>(file: &Path, f: F) -> T {
    let lock = PathBuf::from(format!("{}.lock.d", file.display()));
    if let Some(parent) = lock.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut waited = 0u32;
    loop {
        match fs::create_dir(&lock) {
            Ok(_) => break,
            Err(_) => {
                std::thread::sleep(std::time::Duration::from_millis(20));
                waited += 1;
                if waited > 500 {
                    // 10 seconds: treat the lock as stale (previous process died)
                    let _ = fs::remove_dir(&lock);
                    waited = 0;
                }
            }
        }
    }
    let r = f();
    let _ = fs::remove_dir(&lock);
    r
}

// ----------------------------------------------------------------------------
// Line pattern matchers (replace the awk regexes, ASCII prefixes only)
// ----------------------------------------------------------------------------
fn is_ws(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

fn hhmmss_at(b: &[u8], i: usize) -> bool {
    b.len() >= i + 8
        && (b'0'..=b'2').contains(&b[i])
        && is_digit(b[i + 1])
        && b[i + 2] == b':'
        && (b'0'..=b'5').contains(&b[i + 3])
        && is_digit(b[i + 4])
        && b[i + 5] == b':'
        && (b'0'..=b'5').contains(&b[i + 6])
        && is_digit(b[i + 7])
}

fn hh00_at(b: &[u8], i: usize) -> bool {
    b.len() >= i + 5
        && (b'0'..=b'2').contains(&b[i])
        && is_digit(b[i + 1])
        && b[i + 2] == b':'
        && b[i + 3] == b'0'
        && b[i + 4] == b'0'
}

// ^ {4}- (## )?HH:00  -> (hour, index after "HH:00")
fn hour_hdr_core(line: &str) -> Option<(u32, usize)> {
    let b = line.as_bytes();
    if b.len() < 6 || &b[..4] != b"    " || b[4] != b'-' || b[5] != b' ' {
        return None;
    }
    let mut i = 6;
    if b.len() >= i + 3 && &b[i..i + 3] == b"## " {
        i += 3;
    }
    if !hh00_at(b, i) {
        return None;
    }
    let h = ((b[i] - b'0') as u32) * 10 + (b[i + 1] - b'0') as u32;
    Some((h, i + 5))
}

// awk-style variant requiring a space after HH:00 (used by the chronological inserter)
fn hdr_hour_sp(line: &str) -> Option<u32> {
    let (h, e) = hour_hdr_core(line)?;
    if line.as_bytes().get(e) == Some(&b' ') {
        Some(h)
    } else {
        None
    }
}

// loose variant, trailing space not required
fn hdr_hour_loose(line: &str) -> Option<u32> {
    hour_hdr_core(line).map(|(h, _)| h)
}

// ^ {4}- (## )?HH:00[[:space:]]*-?[[:space:]]*  -> prefix length
fn hour_hdr_prefix(line: &str) -> Option<usize> {
    let (_, mut i) = hour_hdr_core(line)?;
    let b = line.as_bytes();
    while i < b.len() && is_ws(b[i]) {
        i += 1;
    }
    if i < b.len() && b[i] == b'-' {
        i += 1;
    }
    while i < b.len() && is_ws(b[i]) {
        i += 1;
    }
    Some(i)
}

// ^[[:space:]]*- (## )?HH:00 -   (used by lksum / lkcd)
fn hourly_summary_line(line: &str) -> bool {
    let t = line.trim_start_matches(|c| c == ' ' || c == '\t');
    let b = t.as_bytes();
    if b.len() < 2 || b[0] != b'-' || b[1] != b' ' {
        return false;
    }
    let mut i = 2;
    if b.len() >= i + 3 && &b[i..i + 3] == b"## " {
        i += 3;
    }
    hh00_at(b, i) && b.len() >= i + 7 && &b[i + 5..i + 7] == b" -"
}

fn hourly_summary_line_sp(line: &str) -> bool {
    // ^[[:space:]]*- (## )?HH:00<space>
    let t = line.trim_start_matches(|c| c == ' ' || c == '\t');
    let b = t.as_bytes();
    if b.len() < 2 || b[0] != b'-' || b[1] != b' ' {
        return false;
    }
    let mut i = 2;
    if b.len() >= i + 3 && &b[i..i + 3] == b"## " {
        i += 3;
    }
    hh00_at(b, i) && b.get(i + 5) == Some(&b' ')
}

// ^ {8}- HH:MM:SS -<space>
fn is_log_line8(line: &str) -> bool {
    let b = line.as_bytes();
    b.len() >= 21 && &b[..8] == b"        " && b[8] == b'-' && b[9] == b' ' && hhmmss_at(b, 10) && &b[18..21] == b" - "
}

// ^[[:space:]]*- HH:MM:SS -<space>  -> (time, rest of message)
fn log_ts(line: &str) -> Option<(String, String)> {
    let b = line.as_bytes();
    let mut i = 0;
    while i < b.len() && is_ws(b[i]) {
        i += 1;
    }
    if i + 2 > b.len() || b[i] != b'-' || b[i + 1] != b' ' {
        return None;
    }
    i += 2;
    if !hhmmss_at(b, i) {
        return None;
    }
    if b.len() < i + 11 || &b[i + 8..i + 11] != b" - " {
        return None;
    }
    Some((line[i..i + 8].to_string(), line[i + 11..].to_string()))
}

// Timestamp marker only, no trailing space: ^[ws]*- HH:MM:SS -
fn log_ts_loose(line: &str) -> Option<String> {
    let b = line.as_bytes();
    let mut i = 0;
    while i < b.len() && is_ws(b[i]) {
        i += 1;
    }
    if i + 2 > b.len() || b[i] != b'-' || b[i + 1] != b' ' {
        return None;
    }
    i += 2;
    if !hhmmss_at(b, i) {
        return None;
    }
    if b.len() < i + 10 || &b[i + 8..i + 10] != b" -" {
        return None;
    }
    Some(line[i..i + 8].to_string())
}

fn skip_ws(b: &[u8], mut i: usize) -> usize {
    while i < b.len() && is_ws(b[i]) {
        i += 1;
    }
    i
}

// ^[ws]*-[ws]*#?[ws]*\[\[YYYY(-MM){0,2}\]\][ws]*-?[ws]*
// -> (end of "]]", end of full prefix)
fn sum_head(line: &str, allow_lead_ws: bool) -> Option<(usize, usize)> {
    let b = line.as_bytes();
    let mut i = 0;
    if allow_lead_ws {
        i = skip_ws(b, i);
    }
    if i >= b.len() || b[i] != b'-' {
        return None;
    }
    i += 1;
    i = skip_ws(b, i);
    if i < b.len() && b[i] == b'#' {
        i += 1;
    }
    i = skip_ws(b, i);
    let e = bracket_date_end(b, i)?;
    let mut j = skip_ws(b, e);
    if j < b.len() && b[j] == b'-' {
        j += 1;
    }
    j = skip_ws(b, j);
    Some((e, j))
}

// [[YYYY(-dd){0,2}]] starting at i -> index after "]]"
fn bracket_date_end(b: &[u8], i: usize) -> Option<usize> {
    if b.len() < i + 6 || &b[i..i + 2] != b"[[" {
        return None;
    }
    if !b[i + 2..i + 6].iter().all(|c| is_digit(*c)) {
        return None;
    }
    let mut j = i + 6;
    let mut groups = 0;
    while groups < 2 && b.len() >= j + 3 && b[j] == b'-' && is_digit(b[j + 1]) && is_digit(b[j + 2]) {
        j += 3;
        groups += 1;
    }
    if b.len() >= j + 2 && &b[j..j + 2] == b"]]" {
        Some(j + 2)
    } else {
        None
    }
}

// sed: s/^[ws]*-[ws]*#*[ws]*\[\[TAG\]\]/  (is this the summary line for TAG)
fn summary_tag_end(line: &str, tag: &str) -> Option<usize> {
    let b = line.as_bytes();
    let mut i = skip_ws(b, 0);
    if i >= b.len() || b[i] != b'-' {
        return None;
    }
    i += 1;
    i = skip_ws(b, i);
    while i < b.len() && b[i] == b'#' {
        i += 1;
    }
    i = skip_ws(b, i);
    let want = format!("[[{}]]", tag);
    if line[i..].starts_with(&want) {
        Some(i + want.len())
    } else {
        None
    }
}

fn is_summary_for(line: &str, tag: &str) -> bool {
    summary_tag_end(line, tag).is_some()
}

// sed -n "s/^...\[\[TAG\]\][ws]*-[ws]*//p"  -> previous summary text
fn summary_text_for(line: &str, tag: &str) -> Option<String> {
    let e = summary_tag_end(line, tag)?;
    let b = line.as_bytes();
    let mut i = skip_ws(b, e);
    if i >= b.len() || b[i] != b'-' {
        return None;
    }
    i += 1;
    i = skip_ws(b, i);
    Some(line[i..].to_string())
}

// ^!\[[^\]]+\]!  -> length
fn bang_at_start(s: &str) -> Option<usize> {
    match_delim(s, 0, "![", "]!").filter(|(st, _)| *st == 0).map(|(_, e)| e)
}

// find the leftmost occurrence of open + [^\]]+ + close starting at 'from'
fn match_delim(s: &str, from: usize, open: &str, close: &str) -> Option<(usize, usize)> {
    let mut pos = from;
    while pos <= s.len() {
        let idx = match s[pos..].find(open) {
            Some(i) => pos + i,
            None => return None,
        };
        let body_start = idx + open.len();
        if body_start <= s.len() {
            let rest = &s[body_start..];
            if let Some(rb) = rest.find(']') {
                if rb >= 1 && rest[rb..].starts_with(close) {
                    return Some((idx, body_start + rb + close.len()));
                }
            }
        }
        // advance one character (never split UTF-8)
        let mut next = idx + 1;
        while next < s.len() && !s.is_char_boundary(next) {
            next += 1;
        }
        pos = next;
    }
    None
}

fn find_all_delim(s: &str, open: &str, close: &str) -> Vec<(usize, usize)> {
    let mut v = Vec::new();
    let mut from = 0;
    while let Some((a, b)) = match_delim(s, from, open, close) {
        v.push((a, b));
        from = b;
    }
    v
}

fn remove_all_delim(s: &str, open: &str, close: &str, trim_after_ws: bool) -> String {
    let mut out = String::new();
    let mut last = 0;
    for (a, b) in find_all_delim(s, open, close) {
        out.push_str(&s[last..a]);
        let mut e = b;
        if trim_after_ws {
            let bytes = s.as_bytes();
            while e < s.len() && is_ws(bytes[e]) {
                e += 1;
            }
        }
        last = e;
    }
    out.push_str(&s[last..]);
    out
}

// ^\[\[.*\]\] >>  (greedy)
fn greedy_wiki_tag(rest: &str) -> Option<usize> {
    if !rest.starts_with("[[") {
        return None;
    }
    rest[2..].rfind("]] >>").map(|i| 2 + i + 5)
}

// ^\[[a-zA-Z0-9._-]+\] >>
fn single_tag(rest: &str) -> Option<usize> {
    let b = rest.as_bytes();
    if b.is_empty() || b[0] != b'[' {
        return None;
    }
    let mut i = 1;
    while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'.' || b[i] == b'_' || b[i] == b'-') {
        i += 1;
    }
    if i == 1 {
        return None;
    }
    if rest[i..].starts_with("] >>") {
        Some(i + 4)
    } else {
        None
    }
}

fn tag_col(tag: &str) -> &'static str {
    if tag == "![PLAN]!" {
        MAGENTA
    } else {
        ORANGE
    }
}

fn trim_left_ws(s: &str) -> &str {
    s.trim_start_matches(|c: char| c == ' ' || c == '\t')
}

// ----------------------------------------------------------------------------
// Line colorizer (one engine for every reader)
// ----------------------------------------------------------------------------
fn colorize_line(line: &str, monthly_rule: bool) -> String {
    // 1. Daily / monthly / yearly summary
    if let Some((_, pe)) = sum_head(line, false) {
        let prefix = &line[..pe];
        let rest = &line[pe..];
        if let Some(n) = bang_at_start(rest) {
            let tag = &rest[..n];
            return format!("{}{}{}{}{}{}{}{}{}", AMBER, prefix, RESET, tag_col(tag), tag, RESET, GREY, &rest[n..], RESET);
        }
        return format!("{}{}{}{}{}{}", AMBER, prefix, RESET, GREY, rest, RESET);
    }
    // 2. Monthly summary item inside a yearly file
    if monthly_rule && line.starts_with("    - [[") {
        let b = line.as_bytes();
        if b.len() >= 17
            && b[8..12].iter().all(|c| is_digit(*c))
            && b[12] == b'-'
            && is_digit(b[13])
            && is_digit(b[14])
            && &b[15..17] == b"]]"
        {
            return format!("{}{}{}", CYAN, line, RESET);
        }
    }
    // 3. Hour header
    if let Some(pe) = hour_hdr_prefix(line) {
        let prefix = &line[..pe];
        let rest = &line[pe..];
        if let Some(n) = bang_at_start(rest) {
            let tag = &rest[..n];
            return format!("{}{}{}{}{}{}{}{}{}", CYAN, prefix, RESET, tag_col(tag), tag, RESET, GREY, &rest[n..], RESET);
        }
        return format!("{}{}{}{}{}{}", CYAN, prefix, RESET, GREY, rest, RESET);
    }
    // 4. Log line
    if is_log_line8(line) {
        let ts = &line[..21];
        let rest = &line[21..];
        if let Some(n) = greedy_wiki_tag(rest).or_else(|| single_tag(rest)) {
            let tag = &rest[..n];
            let msg = &rest[n..];
            if let Some(m) = bang_at_start(msg) {
                let sub = &msg[..m];
                return format!(
                    "{}{}{}{}{}{}{}{}{}{}",
                    LIME, ts, ORANGE, tag, RESET, tag_col(sub), sub, RESET, GREY, format!("{}{}", &msg[m..], RESET)
                );
            }
            return format!("{}{}{}{}{}{}{}", LIME, ts, ORANGE, tag, GREY, msg, RESET);
        }
        if let Some(n) = bang_at_start(rest) {
            let tag = &rest[..n];
            return format!("{}{}{}{}{}{}{}{}{}", LIME, ts, RESET, tag_col(tag), tag, RESET, GREY, &rest[n..], RESET);
        }
        return format!("{}{}{}{}{}", LIME, ts, GREY, rest, RESET);
    }
    format!("{}{}{}", GREY, line, RESET)
}

// tr -d '\033\015\010\007' then colorize line by line
fn colorize_lines(lines: &[String], monthly_rule: bool) -> String {
    let mut out = String::new();
    for l in lines {
        let clean: String = l
            .chars()
            .filter(|c| *c != '\x1b' && *c != '\r' && *c != '\x08' && *c != '\x07')
            .collect();
        out.push_str(&colorize_line(&clean, monthly_rule));
        out.push('\n');
    }
    out
}

fn print_colored(lines: &[String], monthly_rule: bool) {
    print!("{}", colorize_lines(lines, monthly_rule));
}

// Highlight a leading ![TAG]! in summary text: tag + space + body
fn hl_summary(txt: &str) -> String {
    if let Some(n) = bang_at_start(txt) {
        let tag = &txt[..n];
        let msg = trim_left_ws(&txt[n..]);
        format!("{}{}{} {}{}{}", tag_col(tag), tag, RESET, GREY, msg, RESET)
    } else {
        format!("{}{}{}", GREY, txt, RESET)
    }
}

// First summary of a file (line "- # [[YYYY...]] - text"), text only.
fn summary_of_file(path: &Path, anchored: bool) -> Option<String> {
    for line in read_lines(path) {
        if let Some((e, _)) = sum_head(&line, !anchored) {
            // sub(^ws*-ws*#?ws*\[\[..\]\]ws*[-:]?ws*) -> remaining summary text
            let b = line.as_bytes();
            let mut i = skip_ws(b, e);
            if i < b.len() && (b[i] == b'-' || b[i] == b':') {
                i += 1;
            }
            i = skip_ws(b, i);
            return Some(line[i..].trim_end().to_string());
        }
    }
    None
}

// Summary column with truncation + padding (used by lksort/lkcy/lkword/lkweight)
fn fmt_summary(summary: &str, max_len: usize, plan_col: &str, bad_col: &str) -> (String, usize) {
    let is_bad = summary.starts_with("[Anomaly")
        || summary.starts_with("[Empty")
        || summary.starts_with("(Empty")
        || summary.starts_with("[Summary Not Found")
        || summary.starts_with("[No Sum");
    if is_bad {
        return (format!("{}{}{}", bad_col, summary, RESET), summary.chars().count());
    }
    let mut tag_str = String::new();
    let mut rest_str = summary.to_string();
    let mut tcol = ORANGE;
    if let Some(n) = bang_at_start(summary) {
        tag_str = summary[..n].to_string();
        rest_str = trim_left_ws(&summary[n..]).to_string();
        if tag_str == "![PLAN]!" {
            tcol = plan_col;
        }
    }
    let tl = tag_str.chars().count();
    let sep = if tag_str.is_empty() { 0 } else { 1 };
    let mut raw_len = tl + sep + rest_str.chars().count();
    if max_len != 9999 && raw_len > max_len {
        let avail = max_len as isize - tl as isize - sep as isize;
        if avail < 3 {
            let joined = if tag_str.is_empty() {
                rest_str.clone()
            } else {
                format!("{} {}", tag_str, rest_str)
            };
            let cut: String = joined.chars().take(max_len.saturating_sub(3)).collect();
            let raw_txt = format!("{}...", cut);
            let rl = raw_txt.chars().count();
            return (format!("{}{}{}", GREY, raw_txt, RESET), rl);
        } else {
            let cut: String = rest_str.chars().take(avail as usize - 3).collect();
            rest_str = format!("{}...", cut);
        }
    }
    let colored = if tag_str.is_empty() {
        raw_len = rest_str.chars().count();
        format!("{}{}{}", GREY, rest_str, RESET)
    } else {
        raw_len = tl + 1 + rest_str.chars().count();
        format!("{}{}{} {}{}{}", tcol, tag_str, RESET, GREY, rest_str, RESET)
    };
    (colored, raw_len)
}

fn spaces(n: usize) -> String {
    " ".repeat(n)
}

fn bar_str(filled: usize, total: usize, fill: &str, empty: &str) -> String {
    let f = filled.min(total);
    format!("{}{}", fill.repeat(f), empty.repeat(total - f))
}

// printf "%-Ns" awk-style (counts bytes, including ANSI escapes)
fn pad_bytes(s: &str, w: usize) -> String {
    if s.len() >= w {
        s.to_string()
    } else {
        format!("{}{}", s, spaces(w - s.len()))
    }
}

fn comma(n: u64) -> String {
    let s = n.to_string();
    let mut out = String::new();
    let len = s.len();
    for (i, c) in s.chars().enumerate() {
        if i > 0 && (len - i) % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    out
}

fn human(x: u64) -> String {
    let f = x as f64;
    if x >= 1073741824 {
        format!("{:5.1} GiB", f / 1073741824.0)
    } else if x >= 1048576 {
        format!("{:5.1} MiB", f / 1048576.0)
    } else if x >= 1024 {
        format!("{:5.1} KiB", f / 1024.0)
    } else {
        format!("{:5} B  ", x)
    }
}

// Word count like awk's NF (space/tab separated)
fn nf(s: &str) -> usize {
    s.split(|c: char| c == ' ' || c == '\t' || c == '\n')
        .filter(|w| !w.is_empty())
        .count()
}

fn err(msg: &str) {
    println!("{}[Error]{} {}", RED, RESET, msg);
}

fn hdr(msg: &str) {
    println!("{}{}{}", HEADER_ORG, msg, RESET);
}

// ============================================================================
// Taxonomy (alias -> tag): built-ins plus the user's context.sh-compatible file.
// ============================================================================
#[derive(Clone)]
enum TagKind {
    Ctx(String),         // prefix, e.g. "[[TODO]] >>"
    Exc(String, String), // folder, prefix
    Note(PathBuf),       // static note file
}

fn parse_quoted_after(line: &str, marker: &str) -> Option<String> {
    let i = line.find(marker)?;
    Some(line[i + marker.len()..].to_string())
}

fn parse_taxonomy_line(line: &str) -> Option<(String, TagKind)> {
    let t = line.trim_start();
    let name: String = t
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if name.is_empty() {
        return None;
    }
    let rest = t[name.len()..].trim_start();
    if !rest.starts_with("()") {
        return None;
    }
    let body = rest[2..].trim_start();
    if !body.starts_with('{') {
        return None;
    }
    if let Some(after) = parse_quoted_after(body, "lk_exclusive_context \"") {
        let sep = after.find("\" \"")?;
        let folder = after[..sep].to_string();
        let tail = &after[sep + 3..];
        let end = tail.rfind("\" \"$@\"")?;
        return Some((name, TagKind::Exc(folder, tail[..end].to_string())));
    }
    if let Some(after) = parse_quoted_after(body, "lk_context \"") {
        let end = after.rfind("\" \"$@\"")?;
        return Some((name, TagKind::Ctx(after[..end].to_string())));
    }
    if let Some(after) = parse_quoted_after(body, "local tgt=\"") {
        let end = after.find('"')?;
        return Some((name, TagKind::Note(PathBuf::from(&after[..end]))));
    }
    None
}

fn taxonomy() -> Vec<(String, TagKind)> {
    let mut map: Vec<(String, TagKind)> = Vec::new();
    let mut idx: HashMap<String, usize> = HashMap::new();
    let mut put = |name: String, kind: TagKind, map: &mut Vec<(String, TagKind)>| {
        if let Some(i) = idx.get(&name) {
            map[*i] = (name.clone(), kind);
        } else {
            idx.insert(name.clone(), map.len());
            map.push((name, kind));
        }
    };
    for (a, p) in BUILTIN_TAGS {
        put(a.to_string(), TagKind::Ctx(p.to_string()), &mut map);
    }
    for (a, f, p) in BUILTIN_EXCLUSIVE {
        put(a.to_string(), TagKind::Exc(f.to_string(), p.to_string()), &mut map);
    }
    for line in read_lines(&cfg().taxonomy_file) {
        if let Some((n, k)) = parse_taxonomy_line(&line) {
            put(n, k, &mut map);
        }
    }
    map
}

fn lookup_alias(name: &str) -> Option<TagKind> {
    taxonomy().into_iter().find(|(n, _)| n == name).map(|(_, k)| k)
}

// ============================================================================
// Core log writing
// ============================================================================
fn daily_header_lines(date: &str, time: &str, title: &str) -> Vec<String> {
    vec![
        format!("- # [[{}]] - {}", date, title),
        format!("    created: [[{}]] - {}", date, time),
    ]
}

fn append_entry(file: &Path, date: &str, now_t: &Now, time: &str, log_line: &str, title: &str) -> io::Result<()> {
    with_lock(file, || -> io::Result<()> {
        if !file.exists() {
            write_lines(file, &daily_header_lines(date, time, title))?;
        }
        let lines = read_lines(file);
        let hdr = format!("    - ## {} - (Hourly Summary)", now_t.hour());
        let out = insert_chrono(lines, now_t.h, &hdr, log_line);
        write_lines(file, &out)
    })
}

fn insert_chrono(lines: Vec<String>, t_hr: u32, n_hdr: &str, n_log: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::with_capacity(lines.len() + 2);
    let mut inserted = false;
    let mut in_target = false;
    for line in lines {
        if let Some(cur) = hdr_hour_sp(&line) {
            if cur == t_hr {
                in_target = true;
                out.push(line);
                continue;
            } else if cur > t_hr && !inserted {
                if in_target {
                    out.push(n_log.to_string());
                } else {
                    out.push(n_hdr.to_string());
                    out.push(n_log.to_string());
                }
                inserted = true;
                in_target = false;
                out.push(line);
                continue;
            } else {
                in_target = false;
                out.push(line);
                continue;
            }
        }
        out.push(line);
    }
    if !inserted {
        if in_target {
            out.push(n_log.to_string());
        } else {
            out.push(n_hdr.to_string());
            out.push(n_log.to_string());
        }
    }
    out
}

fn log_line_fmt(time: &str, prefix: &str, text: &str) -> String {
    if prefix.is_empty() {
        format!("        - {} - {}", time, text)
    } else {
        format!("        - {} - {} {}", time, prefix, text)
    }
}

// "✔" feedback for `lk <text>`
fn feedback_plain(cat: &str, text: &str, ts: &str) {
    let cat_disp = if cat.is_empty() {
        String::new()
    } else {
        format!("{}{} {}", ORANGE, cat, RESET)
    };
    if let Some(n) = bang_at_start(text) {
        let tag = &text[..n];
        let msg = trim_left_ws(&text[n..]);
        println!(
            "{}✔{}        - {}{}{} - {}{}{}{} {}{}{}",
            GREEN, RESET, LIME, ts, RESET, cat_disp, tag_col(tag), tag, RESET, GREY, msg, RESET
        );
    } else {
        println!(
            "{}✔{}        - {}{}{} - {}{}{}{}",
            GREEN, RESET, LIME, ts, RESET, cat_disp, GREY, text, RESET
        );
    }
}

fn lk_write(cat: &str, text: &str) -> i32 {
    if text.is_empty() {
        println!("{}[Error]{} No Input.", RED, RESET);
        return 1;
    }
    let n = now();
    let file = today_path(&n);
    let line = log_line_fmt(&n.time(), cat, text);
    if let Err(e) = append_entry(&file, &n.date(), &n, &n.time(), &line, "(Daily Summary)") {
        eprintln!("{}[Error]{} Failed to write {}: {}", RED, RESET, file.display(), e);
        return 1;
    }
    feedback_plain(cat, text, &n.time());
    let tl = cfg().tail;
    if tl > 0 {
        println!(
            "{}--- Tail: Last {} lines from {}{} ---{}",
            DIM,
            tl,
            n.date(),
            cfg().fmt,
            RESET
        );
        print_colored(&tail_of(&file, tl), false);
        println!("{}------------------------------------------------------------{}", DIM, RESET);
    }
    0
}

// lk_context: log with a taxonomy prefix
fn lk_context(prefix: &str, msg: &str) -> i32 {
    if msg.is_empty() {
        return lki(prefix.to_string());
    }
    let n = now();
    let file = today_path(&n);
    let line = log_line_fmt(&n.time(), prefix, msg);
    if let Err(e) = append_entry(&file, &n.date(), &n, &n.time(), &line, "(Daily Summary)") {
        eprintln!("{}[Error]{} Failed to write {}: {}", RED, RESET, file.display(), e);
        return 1;
    }
    println!(
        "{}✔{}      - {} - {}{}{} {}{}{}",
        LIME, RESET, n.time(), ORANGE, prefix, RESET, GREY, msg, RESET
    );
    println!(
        "{}--- Tail: Last {} lines from {} ---{}",
        AMBER,
        cfg().tail,
        fname(&file),
        RESET
    );
    print_colored(&tail_of(&file, cfg().tail), false);
    0
}

fn lk_exclusive(folder: &str, prefix: &str, msg: &str) -> i32 {
    if msg.is_empty() {
        return lki(prefix.to_string());
    }
    let n = now();
    let file = cfg().lk_dir.join(folder).join(format!("{}{}", n.date(), cfg().fmt));
    let line = log_line_fmt(&n.time(), prefix, msg);
    let title = format!("(Exclusive Log: {})", folder);
    if let Err(e) = append_entry(&file, &n.date(), &n, &n.time(), &line, &title) {
        eprintln!("{}[Error]{} Failed to write {}: {}", RED, RESET, file.display(), e);
        return 1;
    }
    println!(
        "{}[Exclusive: /{}]{} - {} - {}{}{} {}{}{}",
        ORANGE, folder, RESET, n.time(), ORANGE, prefix, RESET, GREY, msg, RESET
    );
    println!(
        "{}--- Tail: Last {} lines from {} ---{}",
        AMBER,
        cfg().tail,
        fname(&file),
        RESET
    );
    print_colored(&tail_of(&file, cfg().tail), false);
    0
}

fn run_note(path: &Path, args: &[String]) -> i32 {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if !path.exists() {
        let _ = fs::write(path, "");
    }
    if args.is_empty() {
        run_editor(path);
    } else if args[0] == "-v" || args[0] == "view" {
        print!("{}", read_text(path));
    } else {
        let mut body = read_text(path);
        body.push_str(&format!("- {}\n", args.join(" ")));
        let _ = write_atomic(path, &body);
        let rel = path
            .strip_prefix(cfg().lk_dir.join("note"))
            .map(|p| p.display().to_string())
            .unwrap_or_else(|_| path.display().to_string());
        println!("\x1b[38;2;100;255;0m✔\x1b[0m Note appended to \x1b[38;2;0;255;255m{}\x1b[0m", rel);
    }
    0
}

fn run_alias(kind: &TagKind, args: &[String]) -> i32 {
    match kind {
        TagKind::Ctx(p) => lk_context(p, &args.join(" ")),
        TagKind::Exc(f, p) => lk_exclusive(f, p, &args.join(" ")),
        TagKind::Note(path) => run_note(path, args),
    }
}

// ============================================================================
// Banner & interactive header
// ============================================================================
const DEFAULT_BANNER: &str = r##"\   _    _  __      _                   _  __ _           _    _               /
/  | |  | |/ /  |  | |                 | |/ /| |         | |  (_)              \
\  | |  | ' /   |  | |     ___   __/\  | ' / | | ___ _ __| | ___ _ __   _ /\   /
/  | |  |  <    |  | |    / _ \ / _` \ |  <  | |/ _ \ '__| |/ / | '_ \ / _` \  \
\  | |__| . \   |  | |___| (_) | (_| | | . \ | |  __/ |  |   <| | | | | (_| |  /
/  |____|_|\_\  |  \____/ \___/ \__, / |_|\_\|_|\___|_|  |_|\_\_|_| |_|\__, |  \
\                             ____| |                                ____| |   /
/                             \_____/                                \_____/   \
\______________________________________________________________________________/
"##;

fn banner_text() -> String {
    let p = cfg().config_dir.join("assets").join("banner.txt");
    if p.is_file() {
        read_text(&p)
    } else {
        DEFAULT_BANNER.to_string()
    }
}

fn draw_header(hour: &str) {
    print!("\x1b[2J\x1b[H");
    print!("{}{}{}", ORANGE, banner_text(), RESET);
    println!(
        "{} | LK LogKlerk {} {} | Github: https://github.com/regawaras/lk/ |{}",
        ORANGE, LK_STATUS, LK_VERSION, RESET
    );
    println!(
        "{} | ''Just Open Terminal, Type, Enter, Forget Brutal'' -LK LogKlerking Creator |{}",
        ORANGE, RESET
    );
    println!(
        "{} | -------------- LK Interactive Mode (Hybrid Shell & Context) -------------- |{}",
        GREY, RESET
    );
    println!(
        "{} | Commands: lkc lkcd lkch lkcm lkcy lks lksum lkstat ... (type lkh) | exit: -q |{}",
        GREY, RESET
    );
    println!(
        "{} | Hour Block: {}{}{} | Source: {} |{}\n",
        GREY,
        CYAN,
        hour,
        GREY,
        cfg().config_dir.display(),
        RESET
    );
    flush();
}

// Minimal shell-style line splitter: spaces separate, "..." and '...' group.
fn split_quoted(s: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    let mut has = false;
    for c in s.chars() {
        match quote {
            Some(q) => {
                if c == q {
                    quote = None;
                } else {
                    cur.push(c);
                }
            }
            None => {
                if c == '"' || c == '\'' {
                    quote = Some(c);
                    has = true;
                } else if c == ' ' || c == '\t' {
                    if has || !cur.is_empty() {
                        out.push(std::mem::take(&mut cur));
                        has = false;
                    }
                } else {
                    cur.push(c);
                }
            }
        }
    }
    if has || !cur.is_empty() {
        out.push(cur);
    }
    out
}

fn command_exists(cmd: &str) -> bool {
    const BUILTINS: &[&str] = &[
        "cd", "echo", "pwd", "export", "alias", "type", "test", "printf", "set", "unset", "source", ".",
        "read", "wait", "umask", "ulimit", "exec", "eval", "true", "false", "history", "jobs", "command",
    ];
    if BUILTINS.contains(&cmd) {
        return true;
    }
    if cmd.contains('/') {
        return Path::new(cmd).exists();
    }
    if let Ok(path) = std::env::var("PATH") {
        for dir in path.split(':') {
            if dir.is_empty() {
                continue;
            }
            if Path::new(dir).join(cmd).is_file() {
                return true;
            }
        }
    }
    false
}

fn user_shell() -> String {
    match std::env::var("SHELL") {
        Ok(s) if !s.is_empty() && Path::new(&s).exists() => s,
        _ => "sh".to_string(),
    }
}

fn lki(category: String) -> i32 {
    let mut category = category;
    let shell = user_shell();
    let shell_name = Path::new(&shell)
        .file_name()
        .map(|s| s.to_string_lossy().trim_start_matches('-').to_string())
        .unwrap_or_else(|| "sh".to_string());
    let shell_tag = format!("[[{}]] >>", shell_name);
    let taxo = taxonomy();

    let n0 = now();
    draw_header(&n0.hour());
    let stdin = io::stdin();

    loop {
        let pn = now();
        let prompt_file = today_path(&pn);
        let disp_prompt = category.strip_suffix(" >>").unwrap_or(&category).to_string();
        let mut disp_file = prompt_file.display().to_string();
        let home = cfg().home.display().to_string();
        if let Some(rest) = disp_file.strip_prefix(&format!("{}/", home)) {
            disp_file = format!("~/{}", rest);
        }
        if !disp_prompt.is_empty() {
            print!("{}Log As {} to {}\n>> {}", ORANGE, disp_prompt, disp_file, RESET);
        } else {
            print!("{}Log to {}\n>> {}", ORANGE, disp_file, RESET);
        }
        flush();

        let mut raw = String::new();
        match stdin.lock().read_line(&mut raw) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        let line = raw.trim_end_matches(|c| c == '\n' || c == '\r').to_string();
        let n = now();
        let file = today_path(&n);
        let curr_ts = n.time();
        print!("\x1b[F\x1b[K\x1b[F\x1b[K");

        if line.is_empty() {
            continue;
        }
        println!("{}❯ {}{}", MAGENTA, line, RESET);

        let (cmd, args) = match line.find(' ') {
            Some(i) => (line[..i].to_string(), line[i + 1..].to_string()),
            None => (line.clone(), String::new()),
        };

        if cmd == "-exit" || cmd == "-q" || cmd == "exit" || cmd == "quit" {
            break;
        }
        if cmd == "clear" {
            draw_header(&n.hour());
            continue;
        }

        let override_tag: Option<String> = taxo.iter().find_map(|(name, k)| {
            if *name == cmd {
                if let TagKind::Ctx(p) = k {
                    return Some(p.clone());
                }
            }
            None
        });

        let fullscreen = matches!(
            cmd.as_str(),
            "vim" | "vi" | "nano" | "htop" | "top" | "less" | "man" | "tmux" | "screen"
        );
        let internal_module = cmd != "lki" && MODULE_NAMES.contains(&cmd.as_str());
        let mut tail_n = cfg().tail;
        let active_tag: String;
        let log_text: String;

        if let Some(ov) = override_tag {
            if args.is_empty() {
                category = ov;
                continue;
            }
            active_tag = ov;
            log_text = args.clone();
        } else if internal_module {
            // lkc, lkcy, lkcm, lkcd, ... are run directly by this binary
            let margs = split_quoted(&args);
            println!();
            dispatch(&cmd, &margs);
            if cmd == "lkv" {
                draw_header(&n.hour());
            }
            println!();
            flush();
            continue;
        } else if fullscreen {
            run_shell_line(&shell, &line);
            draw_header(&n.hour());
            active_tag = shell_tag.clone();
            log_text = line.clone();
            tail_n = cfg().cmd_tail;
        } else if command_exists(&cmd) {
            run_shell_line(&shell, &line);
            active_tag = shell_tag.clone();
            log_text = line.clone();
            tail_n = cfg().cmd_tail;
        } else {
            active_tag = category.clone();
            log_text = line.clone();
        }

        let entry = log_line_fmt(&curr_ts, &active_tag, &log_text);
        if let Err(e) = append_entry(&file, &n.date(), &n, &curr_ts, &entry, "(Daily Summary)") {
            eprintln!("{}[Error]{} {}", RED, RESET, e);
            continue;
        }
        println!("{}--- Last {} Lines ---{}", DIM, tail_n, RESET);
        print_colored(&tail_of(&file, tail_n), false);
        println!("{}------------------------------------------------------------{}", DIM, RESET);
    }
    0
}

fn run_shell_line(shell: &str, line: &str) {
    let first = line.split_whitespace().next().unwrap_or("");
    if first == "cd" {
        let target = line[2..].trim();
        let dest = if target.is_empty() || target == "~" {
            cfg().home.clone()
        } else if let Some(rest) = target.strip_prefix("~/") {
            cfg().home.join(rest)
        } else {
            PathBuf::from(target)
        };
        if let Err(e) = std::env::set_current_dir(&dest) {
            println!("cd: {}: {}", dest.display(), e);
        }
        return;
    }
    let _ = Command::new(shell).arg("-c").arg(line).status();
}

// ============================================================================
// lkc — chronological reader
// ============================================================================
fn extract_first_summaries(files: &[PathBuf]) -> Vec<String> {
    let mut v = Vec::new();
    for f in files {
        for line in read_lines(f) {
            if sum_head(&line, true).is_some() {
                v.push(line);
                break;
            }
        }
    }
    v
}

fn md_files_under(dir: &Path) -> Vec<PathBuf> {
    let mut v = Vec::new();
    walk(dir, &mut v);
    v.retain(|p| fname(p).ends_with(".md"));
    v
}

fn norm_date(arg: &str) -> String {
    if arg.len() == 8 {
        format!("{}-{}-{}", &arg[..4], &arg[4..6], &arg[6..8])
    } else {
        arg.to_string()
    }
}

fn show_day(date: &str) {
    let f = day_path(date);
    if f.is_file() {
        println!("{}| LK (LogKlerk) --- All Activities of the Day ({}) ---{}", HEADER_ORG, date, RESET);
        print_colored(&read_lines(&f), true);
        println!("{}----------------------------------------{}", HEADER_ORG, RESET);
    } else {
        println!("\x1b[31m[Warning]\x1b[0m File does not exist yet: {}", f.display());
    }
}

fn digits_only_trim_zero(s: &str) -> u32 {
    let d: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
    let t = d.trim_start_matches('0');
    if t.is_empty() {
        0
    } else {
        t.parse::<u32>().unwrap_or(0)
    }
}

fn lkc(args: &[String]) -> i32 {
    let n = now();
    let today = n.date();
    let lk_dir = cfg().lk_dir.clone();

    if args.is_empty() {
        let f = today_path(&n);
        if f.is_file() {
            show_day(&today);
        } else {
            println!("\x1b[31m[Warning]\x1b[0m File does not exist yet.");
        }
        return 0;
    }
    let a = args[0].as_str();
    match a {
        "-a" | "-all" | "--all" => {
            println!("{}--- All Daily Summaries ---{}", HEADER_ORG, RESET);
            let mut v = extract_first_summaries(&md_files_under(&lk_dir));
            v.sort();
            print_colored(&v, true);
            println!("{}----------------------------------------{}", HEADER_ORG, RESET);
            return 0;
        }
        "-y" | "-year" | "--year" => {
            let d = lk_dir.join(n.year());
            if d.is_dir() {
                let mut v = extract_first_summaries(&md_files_under(&d));
                v.sort();
                print_colored(&v, true);
            }
            return 0;
        }
        "-m" | "-month" | "--month" => {
            let d = lk_dir.join(n.year()).join(n.month());
            if d.is_dir() {
                let mut v = extract_first_summaries(&md_files_under(&d));
                v.sort();
                print_colored(&v, true);
            }
            return 0;
        }
        _ => {}
    }
    if (a.len() == 8 && all_digits(a)) || is_date_str(a) {
        show_day(&norm_date(a));
        return 0;
    }
    let f = today_path(&n);
    if !f.is_file() {
        return 1;
    }
    let lines = read_lines(&f);
    let mut out: Vec<String> = Vec::new();
    if a.contains('-') {
        let mut parts = a.splitn(2, '-');
        let s = digits_only_trim_zero(parts.next().unwrap_or(""));
        let e = digits_only_trim_zero(parts.next().unwrap_or(""));
        let end_limit = format!("{:02}:00", e);
        let mut found = false;
        for l in &lines {
            if let Some(h) = hdr_hour_loose(l) {
                if h == s {
                    found = true;
                }
            }
            if found {
                if let Some(h) = hdr_hour_loose(l) {
                    let hh = format!("{:02}:00", h);
                    if hh > end_limit {
                        found = false;
                    }
                }
            }
            if found {
                out.push(l.clone());
            }
        }
    } else {
        let h = digits_only_trim_zero(a);
        let mut found = false;
        for l in &lines {
            if let Some(cur) = hdr_hour_loose(l) {
                if cur == h {
                    found = true;
                    out.push(l.clone());
                    continue;
                }
                found = false;
            }
            if found {
                out.push(l.clone());
            }
        }
    }
    print_colored(&out, true);
    0
}

fn parse_day_arg(arg: &str) -> Option<String> {
    if arg.is_empty() {
        return Some(now().date());
    }
    if arg.len() == 8 && all_digits(arg) {
        return Some(norm_date(arg));
    }
    if is_date_str(arg) {
        return Some(arg.to_string());
    }
    None
}

fn lkcd(args: &[String]) -> i32 {
    let arg = args.get(0).map(|s| s.as_str()).unwrap_or("");
    let date = match parse_day_arg(arg) {
        Some(d) => d,
        None => {
            println!("\x1b[31m[Error]\x1b[0m Invalid date format. Use YYYYMMDD or YYYY-MM-DD.");
            return 1;
        }
    };
    let f = day_path(&date);
    if !f.is_file() {
        println!("\x1b[31m[Warning]\x1b[0m Log file for date \x1b[38;2;255;255;0m{}\x1b[0m not found.", date);
        return 1;
    }
    println!("{}| LK (LogKlerk) --- Daily Hourly Summary ({}) ---{}", HEADER_ORG, date, RESET);
    let lines = read_lines(&f);
    let first = extract_first_summaries(&[f.clone()]);
    print_colored(&first, false);
    let mut seen: HashSet<String> = HashSet::new();
    let mut hs: Vec<String> = Vec::new();
    for l in &lines {
        if hourly_summary_line_sp(l) {
            let line = format!("    {}", l.trim_start_matches(|c| c == ' ' || c == '\t'));
            if seen.insert(line.clone()) {
                hs.push(line);
            }
        }
    }
    // sort -k2,2 : key = 2nd field
    hs.sort_by(|a, b| {
        let ka = a.trim_start().splitn(2, ' ').nth(1).unwrap_or("").split(' ').next().unwrap_or("").to_string();
        let kb = b.trim_start().splitn(2, ' ').nth(1).unwrap_or("").split(' ').next().unwrap_or("").to_string();
        ka.cmp(&kb).then(a.cmp(b))
    });
    print_colored(&hs, false);
    println!("{}----------------------------------{}", HEADER_ORG, RESET);
    0
}

fn lkch() -> i32 {
    let n = now();
    println!("{}| LK (LogKlerk) --- Hourly Summary ({}:00) ---{}", HEADER_ORG, n.hh(), RESET);
    lkc(&[n.hh()])
}

fn lkcm_for(year: &str, month: &str) -> i32 {
    let tdir = cfg().lk_dir.join(year).join(month);
    if !tdir.is_dir() {
        println!("\x1b[31m[Warning]\x1b[0m Log directory for month \x1b[38;2;255;255;0m{}\x1b[0m not found.", month);
        return 1;
    }
    println!("{}| LK (LogKlerk) --- Monthly Daily Summary ({}) ---{}", HEADER_ORG, month, RESET);
    let mut v = extract_first_summaries(&md_files_under(&tdir));
    v.sort();
    print_colored(&v, true);
    0
}

fn lkcm(args: &[String]) -> i32 {
    let arg = args.get(0).map(|s| s.as_str()).unwrap_or("");
    if arg.is_empty() {
        let n = now();
        return lkcm_for(&n.year(), &n.month());
    }
    if arg.len() == 6 && all_digits(arg) {
        return lkcm_for(&arg[..4], &format!("{}-{}", &arg[..4], &arg[4..]));
    }
    if is_month_str(arg) {
        return lkcm_for(&arg[..4], arg);
    }
    println!("\x1b[31m[Error]\x1b[0m Invalid month format.");
    1
}

fn lkcy(args: &[String]) -> i32 {
    let lk_dir = cfg().lk_dir.clone();
    let mut target = lk_dir.clone();
    let mut view = "default";
    let mut max_len: usize = 38;
    let mut full = false;
    for a in args {
        match a.as_str() {
            "min" | "mini" => {
                view = "mini";
                max_len = 25;
            }
            "mid" | "med" | "medium" => {
                view = "mid";
                max_len = 55;
            }
            "max" | "maximum" => {
                view = "max";
                max_len = 80;
            }
            "fit" => {
                view = "fit";
                max_len = 120;
            }
            "full" => {
                view = "full";
                max_len = 9999;
                full = true;
            }
            y if y.len() == 4 && all_digits(y) => {
                if lk_dir.join(y).is_dir() {
                    target = lk_dir.join(y);
                } else {
                    println!("\x1b[31m[Error]\x1b[0m Year folder {} not found.", y);
                    return 1;
                }
            }
            other => {
                println!("\x1b[31m[Error]\x1b[0m Unknown argument: {}", other);
                println!("Usage: lkcy [YYYY] [min|mid|max|fit|full]");
                return 1;
            }
        }
    }
    if full {
        print!("\x1b[?7l");
    }
    println!(
        "{}| LK (LogKlerk) --- Historical Genesis Timeline (ASC) [View: {}] ---{}",
        HEADER_ORG, view, RESET
    );
    for f in date_files_in(&target) {
        let rel = f
            .strip_prefix(&lk_dir)
            .map(|p| p.display().to_string())
            .unwrap_or_else(|_| f.display().to_string());
        let date = date_of(&f);
        let dt = format!("[[{}]]", date);
        let mut found = false;
        let mut txt = String::new();
        for line in read_lines(&f) {
            if let Some((e, _)) = sum_head(&line, true) {
                let b = line.as_bytes();
                let mut i = skip_ws(b, e);
                if i < b.len() && (b[i] == b'-' || b[i] == b':') {
                    i += 1;
                }
                i = skip_ws(b, i);
                txt = line[i..].to_string();
                found = true;
                break;
            }
        }
        if !found {
            txt = "[Summary Not Found/Not Yet Summarized]".to_string();
        }
        let txt = txt.trim_end().to_string();
        let txt = if txt.is_empty() && found {
            "(Empty Summary)".to_string()
        } else if txt.is_empty() {
            "[Empty File / Anomaly]".to_string()
        } else {
            txt
        };
        let (colored, raw_len) = fmt_summary(&txt, max_len, MAGENTA, RED);
        let pad = if max_len != 9999 && raw_len < max_len { spaces(max_len - raw_len) } else { String::new() };
        println!(
            "{}{:<14}{} {}{} {}({}){}",
            AMBER, dt, RESET, colored, pad, PATH_GREY, rel, RESET
        );
    }
    println!("{}------------------------------------------------------------{}", HEADER_ORG, RESET);
    if full {
        print!("\x1b[?7h");
    }
    0
}

// ============================================================================
// lks — search
// ============================================================================
fn lks(args: &[String]) -> i32 {
    let mut pattern_kind = 0; // 0 = all .md, 1 = exact date, 2 = prefix
    let mut pattern_val = String::new();
    let mut hour = String::new();
    let mut kw = String::new();
    let mut msg_time = "all notes".to_string();
    let mut mode = "fast".to_string();

    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        match a {
            "fast" | "oldest" | "newest" => mode = a.to_string(),
            "latest" => mode = "newest".to_string(),
            "-t" | "-today" => {
                let d = now().date();
                pattern_kind = 1;
                pattern_val = d.clone();
                msg_time = format!("today ({})", d);
            }
            h if h.len() == 3 && h.starts_with('-') && h[1..].bytes().all(is_digit) && (b'0'..=b'2').contains(&h.as_bytes()[1]) => {
                hour = h[1..].to_string();
            }
            d if d.len() == 8 && all_digits(d) => {
                let nd = norm_date(d);
                pattern_kind = 1;
                pattern_val = nd.clone();
                msg_time = format!("date {}", nd);
            }
            d if is_date_str(d) => {
                pattern_kind = 1;
                pattern_val = d.to_string();
                msg_time = format!("date {}", d);
            }
            m if m.len() == 6 && all_digits(m) => {
                pattern_kind = 2;
                pattern_val = format!("{}-{}-", &m[..4], &m[4..]);
                msg_time = format!("month {}-{}", &m[..4], &m[4..]);
            }
            m if is_month_str(m) => {
                pattern_kind = 2;
                pattern_val = format!("{}-", m);
                msg_time = format!("month {}", m);
            }
            y if y.len() == 4 && all_digits(y) => {
                pattern_kind = 2;
                pattern_val = format!("{}-", y);
                msg_time = format!("year {}", y);
            }
            other => {
                if kw.is_empty() {
                    kw = other.to_string();
                } else {
                    kw = format!("{} {}", kw, other);
                }
            }
        }
        i += 1;
    }
    if kw.is_empty() {
        println!("\x1b[31m[Error]\x1b[0m Usage: lks [fast|oldest|newest|latest] [-t] [-HH] [YYYY-MM-DD | YYYYMMDD | YYYYMM] <keyword>");
        return 1;
    }
    let mut msg = format!("Searching for '{}' in {} [Mode: {}]", kw, msg_time, mode);
    if !hour.is_empty() {
        msg = format!("{} hour {}:xx", msg, hour);
    }
    println!("{}--- {} ---{}", ORANGE, msg, RESET);

    let mut files = md_files_under(&cfg().lk_dir);
    files.retain(|p| {
        let name = fname(p);
        match pattern_kind {
            1 => name == format!("{}.md", pattern_val),
            2 => name.starts_with(&pattern_val) && name.ends_with(".md"),
            _ => true,
        }
    });
    files.sort();

    let lower_kw = kw.to_lowercase();
    let hour_needle = if hour.is_empty() { String::new() } else { format!("- {}:", hour) };
    let mut res: Vec<String> = Vec::new();
    let mut match_count = 0usize;
    let file_count = files.len();

    for f in &files {
        let date_str = date_of(f);
        for l in read_lines(f) {
            if !l.to_lowercase().contains(&lower_kw) {
                continue;
            }
            if !hour_needle.is_empty() && !l.contains(&hour_needle) {
                continue;
            }
            match_count += 1;
            let raw = trim_left_ws(&l).to_string();
            let line = format!("[[{}]] {}", date_str, raw);
            let colored = color_search_line(&line, &date_str);
            if mode == "fast" {
                println!("{}", colored);
            } else {
                res.push(colored);
            }
        }
    }
    if file_count == 0 {
        println!("No matching notes found.");
    } else if match_count == 0 {
        println!("Keyword not found in the selected scope.");
    } else if mode != "fast" {
        if mode == "oldest" {
            for l in res.iter().rev() {
                println!("{}", l);
            }
        } else {
            for l in &res {
                println!("{}", l);
            }
        }
    }
    0
}

fn color_search_line(line: &str, _date_str: &str) -> String {
    // line = "[[YYYY-MM-DD]] " + line body (leading whitespace already removed)
    let date_part = &line[..14usize.min(line.len())];
    let raw = if line.len() > 15 { &line[15..] } else { "" };
    let after = if line.len() > 14 { &line[14..] } else { "" };
    if let Some(rest) = after.strip_prefix(" - ") {
        let rest2 = rest.strip_prefix("## ").unwrap_or(rest);
        // 1. summary: "[[D]] - (## )?[[D]]"
        if bracket_date_end(rest2.as_bytes(), 0) == Some(14) {
            return format!("{}{}{}", AMBER, line, RESET);
        }
        // 2. hour header: "[[D]] - (## )?HH:00"
        if hh00_at(rest2.as_bytes(), 0) {
            return format!("{}{}{} {}{}{}", AMBER, date_part, RESET, CYAN, raw, RESET);
        }
        // 3. log line: "[[D]] - HH:MM:SS - "
        let rb = rest.as_bytes();
        if hhmmss_at(rb, 0) && rb.len() >= 11 && &rb[8..11] == b" - " && line.len() >= 28 {
            let ts_part = &line[15..28];
            let rest_part = &line[28..];
            if let Some(n) = greedy_wiki_tag(rest_part).or_else(|| single_tag(rest_part)) {
                return format!(
                    "{}{}{} {}{}{}{}{}{}{}",
                    AMBER, date_part, RESET, LIME, ts_part, ORANGE, &rest_part[..n], GREY, &rest_part[n..], RESET
                );
            }
            return format!(
                "{}{}{} {}{}{}{}{}",
                AMBER, date_part, RESET, LIME, ts_part, GREY, rest_part, RESET
            );
        }
    }
    format!("{}{}{} {}{}{}", AMBER, date_part, RESET, GREY, raw, RESET)
}

// ============================================================================
// lksum / lkplan — yearly, monthly, daily and hourly summaries
// ============================================================================
fn is_yaml_fence(l: &str) -> bool {
    l.starts_with("---") && l[3..].chars().all(|c| c == ' ' || c == '\t')
}

// Insert a summary line after the YAML block (or at start / end of file)
fn yaml_insert(lines: Vec<String>, add: &str, blank_after_yaml: bool) -> Vec<String> {
    let mut out: Vec<String> = Vec::with_capacity(lines.len() + 2);
    let mut yaml = false;
    let mut done = false;
    for (i, l) in lines.into_iter().enumerate() {
        let nr = i + 1;
        let fence = is_yaml_fence(&l);
        if nr == 1 && fence {
            yaml = true;
            out.push(l);
            continue;
        }
        if yaml && fence {
            yaml = false;
            out.push(l);
            if blank_after_yaml {
                out.push(String::new());
            }
            out.push(add.to_string());
            done = true;
            continue;
        }
        if yaml {
            out.push(l);
            continue;
        }
        if nr == 1 && !yaml {
            out.push(add.to_string());
            done = true;
            out.push(l);
            continue;
        }
        out.push(l);
    }
    if !done {
        out.push(add.to_string());
    }
    out
}

fn replace_summary(lines: &[String], tag: &str, new_line: &str) -> (Vec<String>, bool) {
    let mut found = false;
    let mut out = Vec::with_capacity(lines.len());
    for l in lines {
        if is_summary_for(l, tag) {
            found = true;
            out.push(new_line.to_string());
        } else {
            out.push(l.clone());
        }
    }
    (out, found)
}

fn prev_summary(lines: &[String], tag: &str) -> String {
    for l in lines {
        if let Some(t) = summary_text_for(l, tag) {
            if !t.is_empty() {
                return t;
            }
        }
    }
    "(Empty)".to_string()
}

fn hl_inline(txt: &str) -> String {
    hl_summary(txt)
}

fn highlight_diff(txt: &str) -> String {
    // used for the per-hour diff log
    hl_summary(txt)
}

fn summary_usage(cmd: &str, noun: &str, plan: bool) {
    println!("{}[Error]{} {} text is empty.", RED, RESET, noun);
    println!("Usage:");
    let w = if plan { "Plan" } else { "Summary" };
    println!("  {} {}2026{} \"Text\"        {}(Update Yearly {}){}", cmd, AMBER, RESET, GREY, w, RESET);
    println!("  {} {}202604{} \"Text\"      {}(Update Monthly {}){}", cmd, CYAN, RESET, GREY, w, RESET);
    println!("  {} {}20260422{} \"Text\"    {}(Update Daily {}){}", cmd, ORANGE, RESET, GREY, w, RESET);
    println!("  {} {}14{} \"Text\"          {}(Update Hourly {} for Today){}", cmd, LIME, RESET, GREY, w, RESET);
    println!("  {} {}01-03{} \"Text\"       {}(Update Batch Hourly {}){}", cmd, LIME, RESET, GREY, w, RESET);
}

fn show_hourly(lines: &[String], date: &str, plan: bool) {
    let col = if plan { MAGENTA } else { HEADER_ORG };
    let title = if plan { "Hourly Plan & Summaries" } else { "Hourly Summaries" };
    println!("\n{}| LK (LogKlerk) --- {} ({}) ---{}", col, title, date, RESET);
    let d_sum = lines
        .iter()
        .find(|l| is_summary_for(l, date))
        .cloned()
        .unwrap_or_else(|| "(No Daily Summary Found)".to_string());
    println!("{}{}{}", AMBER, d_sum, RESET);
    let mut hs: Vec<String> = lines
        .iter()
        .filter(|l| hourly_summary_line(l))
        .map(|l| l.trim_start_matches(|c| c == ' ' || c == '\t').to_string())
        .collect();
    hs.sort();
    for t in hs {
        let b = t.as_bytes();
        let mut i = 2;
        if b.len() >= i + 3 && &b[i..i + 3] == b"## " {
            i += 3;
        }
        i += 5; // HH:00
        i += 2; // " -"
        let hr = t[..i].to_string();
        let rest_start = skip_ws(b, i);
        let rest = &t[rest_start..];
        if let Some(n) = bang_at_start(rest) {
            let tag = &rest[..n];
            let msg = trim_left_ws(&rest[n..]);
            let hr_col = if plan && tag == "![PLAN]!" { MAGENTA } else { CYAN };
            println!("    {}{} {}{}{}{} {}{}{}", hr_col, hr, RESET, tag_col(tag), tag, RESET, GREY, msg, RESET);
        } else {
            println!("    {}{} {}{}{}{}", CYAN, hr, RESET, GREY, rest, RESET);
        }
    }
    println!("{}---------------------------------------------------{}", col, RESET);
}

// Replace hour blocks [s..=e]; returns (new lines, diff log)
fn hourly_replace(lines: Vec<String>, s: u32, e: u32, new_txt: &str, hr_col: &str) -> (Vec<String>, String) {
    let mut targets: HashSet<u32> = (s..=e).collect();
    let mut out: Vec<String> = Vec::new();
    let mut diff = String::new();
    let mk = |fmt: &str, old: &str| -> String {
        format!("    {}{}{} | {} {} {}\n", hr_col, fmt, RESET, hl_summary(old), ARROW, hl_summary(new_txt))
    };
    for line in lines {
        if let Some(cur) = hdr_hour_loose(&line) {
            for i in s..=e {
                if targets.contains(&i) && i < cur {
                    let fmt = format!("{:02}:00", i);
                    out.push(format!("    - ## {} - {}", fmt, new_txt));
                    diff.push_str(&mk(&fmt, "(Empty)"));
                    targets.remove(&i);
                }
            }
            if cur >= s && cur <= e && targets.contains(&cur) {
                let fmt = format!("{:02}:00", cur);
                let pe = hour_hdr_prefix(&line).unwrap_or(0);
                let mut old = line[pe..].to_string();
                if old.is_empty() {
                    old = "(Empty)".to_string();
                }
                out.push(format!("    - ## {} - {}", fmt, new_txt));
                diff.push_str(&mk(&fmt, &old));
                targets.remove(&cur);
                continue;
            }
        }
        out.push(line);
    }
    for i in s..=e {
        if targets.contains(&i) {
            let fmt = format!("{:02}:00", i);
            out.push(format!("    - ## {} - {}", fmt, new_txt));
            diff.push_str(&mk(&fmt, "(Empty)"));
        }
    }
    (out, diff)
}

fn summary_cmd(args: &[String], plan: bool) -> i32 {
    let cmd_name = if plan { "lkplan" } else { "lksum" };
    let noun = if plan { "Plan" } else { "Summary" };
    if args.is_empty() || args.len() < 2 {
        if args.is_empty() || args[1..].join(" ").is_empty() {
            summary_usage(cmd_name, noun, plan);
            return 1;
        }
    }
    let target = args[0].clone();
    let raw_text = args[1..].join(" ");
    if raw_text.is_empty() {
        summary_usage(cmd_name, noun, plan);
        return 1;
    }
    if !target.chars().all(|c| c.is_ascii_digit() || c == '-') || target.is_empty() {
        println!(
            "{}[Error]{} Invalid target format: '{}'. Target must be a valid Time/Date numeric string.",
            RED, RESET, target
        );
        return 1;
    }
    let text = if plan { format!("![PLAN]! {}", raw_text) } else { raw_text };
    let n = now();
    let curr_ts = n.time();
    let fmt = cfg().fmt.clone();
    let lk_dir = cfg().lk_dir.clone();
    let pcol = if plan { MAGENTA } else { CYAN };
    let kind = if plan { "Plan" } else { "Summary" };

    // ---------------- Yearly ----------------
    if target.len() == 4 && all_digits(&target) {
        let y = target.clone();
        let file = lk_dir.join(&y).join(format!("{}{}", y, fmt));
        let new_line = format!("- # [[{}]] - {}", y, text);
        let prev;
        if !file.exists() {
            prev = "(Empty)".to_string();
            let lines = vec![new_line.clone(), format!("    created: [[{}-01-01]] - {}", y, curr_ts)];
            let _ = write_lines(&file, &lines);
        } else {
            let lines = read_lines(&file);
            prev = prev_summary(&lines, &y);
            let (mut out, found) = replace_summary(&lines, &y, &new_line);
            if !found {
                out = yaml_insert(lines, &new_line, true);
            }
            let _ = write_lines(&file, &out);
        }
        println!("{}✔{} Yearly {} {}({}){} {}Updated.{}", LIME, RESET, kind, pcol, y, RESET, GREY, RESET);
        println!("    {}{}{} | {} {} {}", CYAN, y, RESET, hl_summary(&prev), ARROW, hl_summary(&text));
        return 0;
    }

    // ---------------- Monthly ----------------
    if (target.len() == 6 && all_digits(&target)) || is_month_str(&target) {
        let (y, m) = if target.len() == 6 {
            (target[..4].to_string(), target[4..].to_string())
        } else {
            (target[..4].to_string(), target[5..].to_string())
        };
        let file = lk_dir.join(&y).join(format!("{}{}", y, fmt));
        if !file.exists() {
            let lines = vec![
                format!("- # [[{}]] - (Yearly Summary)", y),
                format!("    created: [[{}-01-01]] - {}", y, curr_ts),
            ];
            let _ = write_lines(&file, &lines);
        }
        let tag = format!("{}-{}", y, m);
        let new_line = format!("    - # [[{}]] - {}", tag, text);
        let lines = read_lines(&file);
        let prev = prev_summary(&lines, &tag);
        let (mut out, found) = replace_summary(&lines, &tag, &new_line);
        if !found {
            out = yaml_insert(lines, &new_line, true);
        }
        let _ = write_lines(&file, &out);
        println!("{}✔{} Monthly {} {}({}-{}){} {}Updated.{}", LIME, RESET, kind, pcol, y, m, RESET, GREY, RESET);
        println!("    {}{}-{}{} | {} {} {}", CYAN, y, m, RESET, hl_summary(&prev), ARROW, hl_summary(&text));
        return 0;
    }

    // ---------------- Daily ----------------
    if (target.len() == 8 && all_digits(&target)) || is_date_str(&target) {
        let date = norm_date(&target);
        let y = date[..4].to_string();
        let m = date[5..7].to_string();
        let file = day_path(&date);
        let new_line = format!("- # [[{}]] - {}", date, text);
        let prev;
        if !file.exists() {
            prev = "(Empty)".to_string();
            let lines = vec![new_line.clone(), format!("    created: [[{}]] - {}", date, curr_ts)];
            let _ = write_lines(&file, &lines);
        } else {
            let lines = read_lines(&file);
            prev = prev_summary(&lines, &date);
            let (mut out, found) = replace_summary(&lines, &date, &new_line);
            if !found {
                out = yaml_insert(lines, &new_line, false);
            }
            let _ = write_lines(&file, &out);
        }
        println!("{}✔{} Daily {} {}({}){} {}Updated.{}", LIME, RESET, kind, pcol, date, RESET, GREY, RESET);
        println!("    {}{}{} | {} {} {}\n", CYAN, date, RESET, hl_summary(&prev), ARROW, hl_summary(&text));
        lkcm_for(&y, &format!("{}-{}", y, m));
        return 0;
    }

    // ---------------- Hourly ----------------
    let file = today_path(&n);
    if !file.exists() {
        let _ = write_lines(&file, &daily_header_lines(&n.date(), &curr_ts, "(Daily Summary)"));
    }
    let (s_raw, e_raw) = if target.contains('-') {
        let mut it = target.splitn(2, '-');
        let a = it.next().unwrap_or("").to_string();
        let b = it.next().unwrap_or("").to_string();
        (a, b)
    } else {
        (target.clone(), target.clone())
    };
    let start = digits_only_trim_zero(&s_raw);
    let end = digits_only_trim_zero(&e_raw);
    if end < start {
        println!(
            "{}[Error]{} Invalid hour range: End hour ({}) cannot be less than Start hour ({}).",
            RED, RESET, end, start
        );
        return 1;
    }
    let lines = read_lines(&file);
    let hr_col = if plan { MAGENTA } else { CYAN };
    let (out, diff) = hourly_replace(lines, start, end, &text, hr_col);
    let _ = write_lines(&file, &out);
    println!(
        "{}✔{} Hourly {} {}({:02}:00-{:02}:00){} {}Updated.{}",
        LIME, RESET, kind, pcol, start, end, RESET, GREY, RESET
    );
    print!("{}", diff);
    show_hourly(&read_lines(&file), &n.date(), plan);
    0
}

// ============================================================================
// lkset / lkfiles / lknote — taxonomy alias creators
// ============================================================================
fn valid_alias(a: &str) -> bool {
    !a.is_empty() && a.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn ensure_taxonomy_writable() -> Result<(), String> {
    let f = &cfg().taxonomy_file;
    if let Some(parent) = f.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if !f.exists() {
        let _ = fs::write(f, "");
    }
    match fs::OpenOptions::new().append(true).open(f) {
        Ok(_) => Ok(()),
        Err(_) => Err(format!(
            "{}[Error]{} Permission denied on context.sh.\nRun outside LKI: {}sudo chown $USER:$USER {}{}",
            RED,
            RESET,
            AMBER,
            f.display(),
            RESET
        )),
    }
}

fn append_taxonomy(line: &str) -> io::Result<()> {
    let mut f = fs::OpenOptions::new().append(true).create(true).open(&cfg().taxonomy_file)?;
    writeln!(f, "{}", line)
}

fn tag_tail_colorize(line: &str) -> String {
    let name: String = line
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if !name.is_empty() {
        let rest = &line[name.len()..];
        if let (Some(st), Some(en)) = (rest.find("\"[["), rest.rfind("]] >>\"")) {
            let en = en + 6;
            if en > st {
                return format!(
                    "    {}{}{}{}{}{}{}{}{}",
                    PURPLE, name, GREY, &rest[..st], ORANGE, &rest[st..en], GREY, &rest[en..], RESET
                );
            }
        }
    }
    format!("    {}{}{}", CYAN, line, RESET)
}

fn print_taxonomy_tail(kind: &str) {
    println!(
        "\n{}--- Tail: Last {} lines from {} ---{}",
        AMBER,
        cfg().set_tail,
        fname(&cfg().taxonomy_file),
        RESET
    );
    for l in tail_of(&cfg().taxonomy_file, cfg().set_tail) {
        println!("{}", tag_tail_colorize(&l));
    }
    let _ = kind;
    println!("{}------------------------------------------------{}", HEADER_ORG, RESET);
}

fn lkset(args: &[String]) -> i32 {
    let first = args.get(0).cloned().unwrap_or_default();
    if first.is_empty() || !first.contains('=') {
        println!("{}[Syntax Error]{} Format must be alias=\"[[Tag]]\"", RED, RESET);
        println!("Example: lkset wbl=\"[[Website Links]]\"");
        return 1;
    }
    let eq = first.find('=').unwrap();
    let alias = first[..eq].to_string();
    let tag = strip_quotes(&first[eq + 1..]);
    if !valid_alias(&alias) {
        println!(
            "{}[Error]{} Invalid alias name: '{}'. Use alphanumeric and underscores only.",
            RED, RESET, alias
        );
        return 1;
    }
    if tag.is_empty() {
        println!("{}[Error]{} Tag cannot be empty.", RED, RESET);
        return 1;
    }
    if let Err(m) = ensure_taxonomy_writable() {
        println!("{}", m);
        return 1;
    }
    if lookup_alias(&alias).is_some() {
        println!(
            "\x1b[33m[Warning]\x1b[0m {}Alias '{}' is already registered in context.sh. Aborting.{}",
            RED, alias, RESET
        );
        return 0;
    }
    let func = format!("{}() {{ lk_context \"{} >>\" \"$@\"; }}", alias, tag);
    if let Err(e) = append_taxonomy(&func) {
        println!("{}[Error]{} {}", RED, RESET, e);
        return 1;
    }
    println!("{}✔{} Taxonomy Context Added", LIME, RESET);
    println!("    Alias    : {}{}{}", PURPLE, alias, RESET);
    println!("    Tag      : {}{} >>{}", ORANGE, tag, RESET);
    println!("    Location : {}{}{}", GREY, cfg().taxonomy_file.display(), RESET);
    print_taxonomy_tail("ctx");
    0
}

fn lkfiles(args: &[String]) -> i32 {
    let first = args.get(0).cloned().unwrap_or_default();
    if first.is_empty() || !first.contains('=') {
        println!("{}[Syntax Error]{} Format must be alias=\"[[Tag]]\"", RED, RESET);
        println!("Example: lkfiles priv=\"[[Private]]\"");
        return 1;
    }
    if let Err(m) = ensure_taxonomy_writable() {
        println!("{}", m);
        return 1;
    }
    let eq = first.find('=').unwrap();
    let alias = first[..eq].to_string();
    let tag = strip_quotes(&first[eq + 1..]);
    if !valid_alias(&alias) {
        println!(
            "{}[Error]{} Invalid alias name: '{}'. Use alphanumeric and underscores only.",
            RED, RESET, alias
        );
        return 1;
    }
    if tag.is_empty() {
        println!("{}[Error]{} Tag cannot be empty.", RED, RESET);
        return 1;
    }
    let folder = tag
        .strip_prefix("[[")
        .unwrap_or(&tag)
        .strip_suffix("]]")
        .unwrap_or(tag.strip_prefix("[[").unwrap_or(&tag))
        .to_string();
    if lookup_alias(&alias).is_some() {
        println!(
            "{}[Warning]{} {}Alias '{}' is already registered in context.sh. Aborting.{}",
            ORANGE, RESET, RED, alias, RESET
        );
        return 0;
    }
    let func = format!(
        "{}() {{ lk_exclusive_context \"{}\" \"{} >>\" \"$@\"; }}",
        alias, folder, tag
    );
    if let Err(e) = append_taxonomy(&func) {
        println!("{}[Error]{} {}", RED, RESET, e);
        return 1;
    }
    println!("{}✔{} Exclusive Context Added", LIME, RESET);
    println!("    Alias    : {}{}{}", PURPLE, alias, RESET);
    println!("    Folder   : {}{}{}", CYAN, folder, RESET);
    println!("    Tag      : {}{} >>{}", ORANGE, tag, RESET);
    println!("    Location : {}{}{}", GREY, cfg().taxonomy_file.display(), RESET);
    print_taxonomy_tail("exc");
    0
}

fn note_dir() -> PathBuf {
    cfg().lk_dir.join("note")
}

fn lknote(args: &[String]) -> i32 {
    let _ = fs::create_dir_all(note_dir());
    let a0 = args.get(0).map(|s| s.as_str()).unwrap_or("");
    match a0 {
        "" => {
            println!("\n{}| LK (LogKlerk) --- Quick Notes Manager (lknote) Help ---{}", HEADER_ORG, RESET);
            println!("  \x1b[38;2;170;100;255mlknote\x1b[0m \x1b[38;2;100;255;0mlist\x1b[0m                         \x1b[90mList all notes in LK_DIR/note/\x1b[0m");
            println!("  \x1b[38;2;170;100;255mlknote\x1b[0m \x1b[38;2;100;255;0mfind <keyword>\x1b[0m               \x1b[90mFilter/Search for specific notes\x1b[0m");
            println!("  \x1b[38;2;170;100;255mlknote\x1b[0m \x1b[38;2;0;255;255m<alias>=\"<file.md>\"\x1b[0m          \x1b[90mRegister a smart alias to a file\x1b[0m");
            println!("  \x1b[38;2;170;100;255mlknote\x1b[0m \x1b[38;2;0;255;255m<alias>=\"<Dir/file.md>\"\x1b[0m      \x1b[90mRegister with specific sub-directory\x1b[0m");
            println!("  \x1b[38;2;170;100;255mlknote\x1b[0m \x1b[38;2;170;100;255m<alias>\x1b[0m                      \x1b[90mExecute the alias directly\x1b[0m");
            println!("{}-------------------------------------------------------{}", HEADER_ORG, RESET);
            println!("{}[Smart Alias Features after creation]:{}", AMBER, RESET);
            println!("  {}<alias>{}                              \x1b[90mOpen file in $EDITOR\x1b[0m", PURPLE, RESET);
            println!("  {}<alias>{} \x1b[38;2;100;255;0m\"Your quick idea\"{}            \x1b[90mAppend text to file silently\x1b[0m", PURPLE, RESET, RESET);
            println!("  {}<alias>{} \x1b[38;2;225;102;0m-v{}                           \x1b[90mView (cat) file contents\x1b[0m", PURPLE, RESET, RESET);
            println!();
            0
        }
        "list" | "ls" | "-ls" | "--list" => {
            println!("\n{}| LK (LogKlerk) --- Notes Directory List ---{}", HEADER_ORG, RESET);
            let mut v = Vec::new();
            walk(&note_dir(), &mut v);
            v.sort();
            if v.is_empty() {
                println!("  {}(Empty / No notes created yet){}", GREY, RESET);
            } else {
                for f in v {
                    let rel = f.strip_prefix(note_dir()).map(|p| p.display().to_string()).unwrap_or_default();
                    println!("  {}- {}{}", CYAN, rel, RESET);
                }
            }
            println!("{}--------------------------------------------{}", HEADER_ORG, RESET);
            0
        }
        "filter" | "find" | "f" | "-f" => {
            let q = args.get(1).cloned().unwrap_or_default();
            if q.is_empty() {
                println!("{}[Error]{} Please provide a keyword to find. (e.g., lknote f projects)", RED, RESET);
                return 1;
            }
            println!("\n{}| LK (LogKlerk) --- Filtering Notes for: '{}' ---{}", HEADER_ORG, q, RESET);
            let mut v = Vec::new();
            walk(&note_dir(), &mut v);
            v.sort();
            let ql = q.to_lowercase();
            let hits: Vec<String> = v
                .iter()
                .map(|f| f.display().to_string())
                .filter(|s| s.to_lowercase().contains(&ql))
                .collect();
            if hits.is_empty() {
                println!("  {}(No notes found matching '{}'){}", GREY, q, RESET);
            } else {
                let prefix = format!("{}/", note_dir().display());
                for h in hits {
                    let rel = h.strip_prefix(&prefix).unwrap_or(&h).to_string();
                    println!("  {}- {}{}", CYAN, rel, RESET);
                }
            }
            println!("{}---------------------------------------------------{}", HEADER_ORG, RESET);
            0
        }
        s if s.contains('=') => {
            let eq = s.find('=').unwrap();
            let alias = s[..eq].to_string();
            let target = strip_quotes(&s[eq + 1..]);
            if !valid_alias(&alias) {
                println!(
                    "{}[Error]{} Invalid alias name: '{}'. Use alphanumeric and underscores only.",
                    RED, RESET, alias
                );
                return 1;
            }
            if target.is_empty() {
                println!("{}[Error]{} Target file cannot be empty.", RED, RESET);
                return 1;
            }
            if let Err(m) = ensure_taxonomy_writable() {
                println!("{}", m);
                return 1;
            }
            if lookup_alias(&alias).is_some() {
                println!(
                    "{}[Warning]{} {}Alias '{}' is already registered in context.sh. Aborting.{}",
                    ORANGE, RESET, RED, alias, RESET
                );
                return 0;
            }
            let full = note_dir().join(&target);
            let func = format!(
                "{a}() {{ local tgt=\"{p}\"; mkdir -p \"${{tgt%/*}}\" 2>/dev/null; [ ! -f \"$tgt\" ] && touch \"$tgt\"; if [ $# -eq 0 ]; then ${{EDITOR:-vi}} \"$tgt\"; elif [ \"$1\" = \"-v\" ] || [ \"$1\" = \"view\" ]; then cat \"$tgt\"; else printf -- \"- %s\\n\" \"$*\" >> \"$tgt\"; printf \"\\033[38;2;100;255;0m✔\\033[0m Note appended to \\033[38;2;0;255;255m{t}\\033[0m\\n\"; fi; }}",
                a = alias,
                p = full.display(),
                t = target
            );
            if let Err(e) = append_taxonomy(&func) {
                println!("{}[Error]{} {}", RED, RESET, e);
                return 1;
            }
            println!("{}✔{} Smart Note Alias Created", LIME, RESET);
            println!("    Alias    : {}{}{}", PURPLE, alias, RESET);
            println!("    Target   : {}{}{}", CYAN, target, RESET);
            println!("    Location : {}{}{}", GREY, full.display(), RESET);
            println!(
                "\n{}--- Tail: Last {} lines from context.sh ---{}",
                AMBER,
                cfg().set_tail,
                RESET
            );
            for l in tail_of(&cfg().taxonomy_file, cfg().set_tail) {
                println!("{}", note_tail_colorize(&l));
            }
            println!("{}------------------------------------------------{}", HEADER_ORG, RESET);
            0
        }
        alias => {
            if let Some(kind) = lookup_alias(alias) {
                return run_alias(&kind, &args[1..]);
            }
            println!("{}[Context Not Found]{} The alias '{}' does not exist.", ORANGE, RESET, alias);
            println!("{}[Tutorial]{} Make it by typing:", LIME, RESET);
            println!("  \x1b[38;2;170;100;255mlknote\x1b[0m {}=\"{}.md\"", alias, alias);
            println!("  \x1b[90m(or with specific directory)\x1b[0m");
            println!("  \x1b[38;2;170;100;255mlknote\x1b[0m {}=\"dir/subdir/{}.md\"", alias, alias);
            1
        }
    }
}

fn note_tail_colorize(line: &str) -> String {
    let name: String = line
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if !name.is_empty() {
        let rest = &line[name.len()..];
        if let Some(st) = rest.find("local tgt=\"") {
            let ps = st + 11;
            if let Some(len) = rest[ps..].find('"') {
                return format!(
                    "    {}{}{}{}{}{}{}{}{}",
                    PURPLE, name, GREY, &rest[..ps], CYAN, &rest[ps..ps + len], GREY, &rest[ps + len..], RESET
                );
            }
        }
    }
    format!("    {}{}{}", CYAN, line, RESET)
}

// ============================================================================
// lkconf — configuration editor (upsert KEY="VALUE")
// ============================================================================
fn lkconf(args: &[String]) -> i32 {
    let versioned = cfg().config_file.clone();
    let global = cfg().home.join(".config").join("lk").join("lk.conf");
    let conf_file = if versioned.is_file() {
        versioned
    } else if global.is_file() {
        global
    } else {
        if let Some(parent) = versioned.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::write(&versioned, "");
        versioned
    };
    let raw = args.join(" ");
    if raw.is_empty() || !raw.contains('=') {
        println!("{}[Syntax Error]{} Format must be KEY=\"VALUE\"", RED, RESET);
        println!("Example: lkconf LK_TAIL_LINES=\"5\"");
        println!("Example: lkconf LK_USER=\"Jane Doe\"");
        return 1;
    }
    let eq = raw.find('=').unwrap();
    let key = raw[..eq].to_string();
    let val = strip_quotes(&raw[eq + 1..]);
    if !valid_alias(&key) {
        println!(
            "{}[Error]{} Invalid key name: '{}'. Use alphanumeric and underscores only.",
            RED, RESET, key
        );
        return 1;
    }
    let entry = format!("{}=\"{}\"", key, val);
    if fs::OpenOptions::new().append(true).open(&conf_file).is_err() {
        println!("{}[Error]{} Permission denied on {}.", RED, RESET, conf_file.display());
        return 1;
    }
    let mut lines = read_lines(&conf_file);
    let key_eq = format!("{}=", key);
    let pos = lines.iter().position(|l| trim_left_ws(l).starts_with(&key_eq));
    let (action, acol) = match pos {
        Some(i) => {
            lines[i] = entry.clone();
            ("Updated", CYAN)
        }
        None => {
            lines.push(entry.clone());
            ("Added", LIME)
        }
    };
    let _ = write_lines(&conf_file, &lines);
    println!("{}✔{} Configuration {}{}{}", LIME, RESET, acol, action, RESET);
    println!("    Key      : {}{}{}", PURPLE, key, RESET);
    println!("    Value    : {}\"{}\"{}", ORANGE, val, RESET);
    println!("    Location : {}{}{}", GREY, conf_file.display(), RESET);

    let target_ln = pos.map(|i| i + 1).unwrap_or(lines.len());
    let total = lines.len();
    let tl = cfg().set_tail.max(1);
    let half = tl / 2;
    let mut start = if target_ln > half { target_ln - half } else { 1 };
    if start < 1 {
        start = 1;
    }
    let mut end = start + tl - 1;
    if end > total {
        end = total;
    }
    if end + 1 - start < tl {
        start = if end + 1 > tl { end + 1 - tl } else { 1 };
    }
    println!(
        "\n{}--- Context: Lines {}-{} from {} ---{}",
        AMBER,
        start,
        end,
        fname(&conf_file),
        RESET
    );
    for ln in start..=end {
        let l = &lines[ln - 1];
        let t = trim_left_ws(l);
        let kend = t.find('=');
        let is_kv = match kend {
            Some(e) => e > 0 && t[..e].chars().all(|c| c.is_ascii_alphanumeric() || c == '_'),
            None => false,
        };
        if is_kv {
            let e = kend.unwrap();
            let k = &t[..e];
            let prefix = if k == key { format!("  {}> {}", CYAN, RESET) } else { "    ".to_string() };
            println!("{}{}{}{}={}{}{}", prefix, PURPLE, k, GREY, ORANGE, &t[e + 1..], RESET);
        } else {
            println!("    {}{}{}", GREY, l, RESET);
        }
    }
    println!("{}------------------------------------------------{}", HEADER_ORG, RESET);
    0
}

// ============================================================================
// lkv — visual editor
// ============================================================================
fn lkv(args: &[String]) -> i32 {
    let a0 = args.get(0).map(|s| s.as_str()).unwrap_or("");
    let lk_dir = cfg().lk_dir.clone();
    match a0 {
        "-h" | "-help" | "--help" | "help" => {
            let mut mods: Vec<String> = Vec::new();
            if let Ok(rd) = fs::read_dir(&cfg().modules_dir) {
                for e in rd.flatten() {
                    let n = fname(&e.path());
                    if let Some(stem) = n.strip_suffix(".sh") {
                        mods.push(stem.to_string());
                    }
                }
            }
            mods.sort();
            println!("\n{}| LK (LogKlerk) --- Visual Editor (lkv) Help ---{}", AMBER, RESET);
            println!("  {}{:<15}{} {}Open today's log{}", PURPLE, "lkv", RESET, GREY, RESET);
            println!("  {}{:<15}{} {}Open specific date's log{}", PURPLE, "lkv YYYYMMDD", RESET, GREY, RESET);
            println!("  {}{:<15}{} {}Edit module file (context = taxonomy){}", PURPLE, "lkv <mod_name>", RESET, GREY, RESET);
            println!("  {}{:<15}{} {}Edit lk.conf{}", PURPLE, "lkv conf", RESET, GREY, RESET);
            println!("  {}{:<15}{} {}Edit banner{}", PURPLE, "lkv banner", RESET, GREY, RESET);
            println!("  {}Available:{} {}{}{}", ORANGE, RESET, CYAN, mods.join(", "), RESET);
            println!("{}------------------------------------------------{}", ORANGE, RESET);
            0
        }
        "conf" | "config" | "-conf" | "-config" => {
            run_editor(&cfg().config_file);
            0
        }
        "lk" | "-lk" => {
            println!(
                "{}[Info]{} The core router is compiled into the 'lk' binary; there is no lk.sh to edit.",
                CYAN, RESET
            );
            0
        }
        "banner" | "-banner" => {
            let p = cfg().config_dir.join("assets").join("banner.txt");
            if !p.exists() {
                if let Some(parent) = p.parent() {
                    let _ = fs::create_dir_all(parent);
                }
                let _ = fs::write(&p, DEFAULT_BANNER);
            }
            run_editor(&p);
            0
        }
        "" => {
            let n = now();
            let f = today_path(&n);
            if let Some(parent) = f.parent() {
                let _ = fs::create_dir_all(parent);
            }
            run_editor(&f);
            0
        }
        d if (d.len() == 8 && all_digits(d)) || is_date_str(d) => {
            let date = norm_date(d);
            let f = day_path(&date);
            if let Some(parent) = f.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let _ = &lk_dir;
            run_editor(&f);
            0
        }
        other => {
            let target = other.trim_start_matches('-');
            let m = cfg().modules_dir.join(format!("{}.sh", target));
            if target == "context" && !m.exists() {
                let _ = fs::create_dir_all(&cfg().modules_dir);
                let _ = fs::write(&m, "");
            }
            if m.is_file() {
                run_editor(&m);
                0
            } else {
                println!("{}[Error]{} Module or Date '{}' not found.", RED, RESET, other);
                1
            }
        }
    }
}

// ============================================================================
// Help
// ============================================================================
fn help_row(cmd: &str, desc: &str) {
    println!("  {}{:<34}{} : {}{}{}", CYAN, cmd, RESET, GREY, desc, RESET);
}

fn lkh() -> i32 {
    println!("\n{}========================================================================{}", ORANGE, RESET);
    println!("{}                LogKlerk (LK) {} {} Manual (Rust)               {}", ORANGE, LK_VERSION, LK_STATUS, RESET);
    println!("{}========================================================================{}\n", ORANGE, RESET);

    println!("{}[1. Core Logging & TUI]{}", LIME, RESET);
    help_row("lk [text]", "Log standard text to the current timestamp instantly.");
    help_row("lk  /  lki", "Open Interactive Mode (Hybrid Shell + TUI).");
    help_row("lk -v \"[text]\"", "Log text with an automatic LogKlerk version tag.");
    help_row("lk @<alias> [text]", "Log with a taxonomy alias (empty text = enter LKI with that tag).");
    help_row("lk -e  /  lk -pwd  /  lk -c", "Edit today's log / print vault path / show configuration.");
    println!();

    println!("{}[2. Context & Taxonomy Engine]{}", LIME, RESET);
    help_row("lkset <alias>=\"[[Tag]]\"", "Create a dynamic tag alias (e.g., lkset wbl=\"[[Web]]\").");
    help_row("lkfiles <alias>=\"[[Dir]]\"", "Create an alias to an exclusive directory (standalone logs).");
    help_row("lk tags", "List every registered alias.");
    help_row("lk -install <dir>", "Create symlinks (todo, ideas, lkc, ...) pointing to this binary.");
    println!();

    println!("{}[3. Quick Notes (lknote)]{}", LIME, RESET);
    help_row("lknote list | find <kw>", "List / filter static notes stored in LK_DIR/note/.");
    help_row("lknote <alias>=\"<file.md>\"", "Register a smart alias for a note file.");
    help_row("lknote <alias> \"text\" | -v", "Append text to the note / view it.");
    println!();

    println!("{}[4. Summaries & Plans]{}", LIME, RESET);
    help_row("lksum 2026|202604|20260422 \"T\"", "Update Yearly / Monthly / Daily summary.");
    help_row("lksum 14 \"T\"  |  lksum 01-03 \"T\"", "Update hourly summary (single or batch).");
    help_row("lkplan <same targets> \"T\"", "Same as lksum but tagged ![PLAN]!.");
    println!();

    println!("{}[5. Chronological Reader]{}", LIME, RESET);
    help_row("lkc [date|HH|HH-HH|-a|-y|-m]", "Read logs (today by default).");
    help_row("lkcd [YYYYMMDD]", "Daily + hourly summary recap.");
    help_row("lkch", "Logs within the current hour block.");
    help_row("lkcm [YYYYMM]", "All Daily Summaries in a month.");
    help_row("lkcy [YYYY] [min|mid|max|fit|full]", "Historical genesis timeline.");
    println!();

    println!("{}[6. Search & Analytics]{}", LIME, RESET);
    help_row("lks [scope] <keyword>", "Chronological search (-t, -HH, YYYY-MM, ...).");
    help_row("lksort [scope] [metric] [order]", "Dashboard table (date|size|words|lines).");
    help_row("lkstat [scope]", "Quantum analytics engine.");
    help_row("lkrank [mode] [scope] [N]", "Frequency ranker (tags, taxonomies, links, hashtags).");
    help_row("lkchart <mode>", "Word-volume charts.");
    help_row("lkword [scope] [date|context] <kw>", "Keyword frequency per day.");
    help_row("lkwords analyze|add|set|ignore", "Semantic categorisation matrix.");
    help_row("lkdiversity [scope] [metric]", "Lexical diversity (RTTR/TTR/uniq).");
    help_row("lkyaml [scope] keys|values|timeline|dump", "YAML frontmatter telemetry.");
    help_row("lkweight add|list|rm|judge|why|unjudged", "Karmic weight scoring.");
    help_row("lkdistraction add|list|rm|track", "Distraction pattern tracker.");
    help_row("lkvoid | lkhour | lkminute | lksecond", "Temporal silence / hour / minute / second analyzers.");
    println!();

    println!("{}[7. Maintenance]{}", LIME, RESET);
    help_row("lkv [date|conf|banner|context]", "Open files in $EDITOR.");
    help_row("lkconf KEY=\"VALUE\"", "Upsert a setting in lk.conf.");
    help_row("lkspace <time> <var> <value>", "Inject YAML frontmatter (add var=\"Long Name\" to map).");
    help_row("lksnap [name]", "Incremental hard-link snapshot of the vault.");

    println!("\n{}========================================================================{}", ORANGE, RESET);
    0
}

// ============================================================================
// Shared time scopes (replace many `find ... -name` calls)
// ============================================================================
#[derive(Clone)]
enum Sc {
    All,
    Year(String),
    Month(String), // YYYY-MM
    Day(String),   // YYYY-MM-DD
    YearRange(i64, i64),
    DateRange(String, String),
}

fn parse_scope(a: &str) -> Option<(Sc, String)> {
    let b = a.as_bytes();
    if a.len() == 4 && all_digits(a) {
        return Some((Sc::Year(a.to_string()), format!("Yearly Scope ({})", a)));
    }
    if (a.len() == 6 && all_digits(a)) || is_month_str(a) {
        let ym = if a.len() == 6 { format!("{}-{}", &a[..4], &a[4..]) } else { a.to_string() };
        return Some((Sc::Month(ym.clone()), format!("Monthly Scope ({})", ym)));
    }
    if (a.len() == 8 && all_digits(a)) || is_date_str(a) {
        let d = norm_date(a);
        return Some((Sc::Day(d.clone()), format!("Daily Scope ({})", d)));
    }
    if a.len() == 9 && b[4] == b'-' && all_digits(&a[..4]) && all_digits(&a[5..]) {
        let s: i64 = a[..4].parse().unwrap_or(0);
        let e: i64 = a[5..].parse().unwrap_or(0);
        return Some((Sc::YearRange(s, e), format!("Yearly Range ({} to {})", s, e)));
    }
    if a.len() == 17 && b[8] == b'-' && all_digits(&a[..8]) && all_digits(&a[9..]) {
        let s = norm_date(&a[..8]);
        let e = norm_date(&a[9..]);
        return Some((Sc::DateRange(s.clone(), e.clone()), format!("Range {} to {}", s, e)));
    }
    if a.len() == 21 && is_date_str(&a[..10]) && b[10] == b'-' && is_date_str(&a[11..]) {
        let s = a[..10].to_string();
        let e = a[11..].to_string();
        return Some((Sc::DateRange(s.clone(), e.clone()), format!("Range {} to {}", s, e)));
    }
    None
}

fn ymd_of(d: &str) -> (i64, i64, i64) {
    (
        d[..4].parse().unwrap_or(1970),
        d[5..7].parse().unwrap_or(1),
        d[8..10].parse().unwrap_or(1),
    )
}

fn scope_files(sc: &Sc) -> Vec<PathBuf> {
    let root = cfg().lk_dir.clone();
    match sc {
        Sc::All => date_files_in(&root),
        Sc::Year(y) => date_files_in(&root.join(y)),
        Sc::Month(ym) => date_files_in(&root.join(&ym[..4]).join(ym)),
        Sc::Day(d) => {
            let p = day_path(d);
            if p.is_file() {
                vec![p]
            } else {
                vec![]
            }
        }
        Sc::YearRange(a, b) => {
            let mut v = Vec::new();
            let mut y = *a;
            while y <= *b && y - *a < 500 {
                v.extend(date_files_in(&root.join(format!("{:04}", y))));
                y += 1;
            }
            v.sort();
            v
        }
        Sc::DateRange(s, e) => {
            let (sy, sm, sd) = ymd_of(s);
            let (ey, em, ed) = ymd_of(e);
            let mut cur = days_from_civil(sy, sm, sd);
            let end = days_from_civil(ey, em, ed);
            let mut v = Vec::new();
            while cur <= end {
                let (y, m, d) = civil_from_days(cur);
                let date = format!("{:04}-{:02}-{:02}", y, m, d);
                let p = day_path(&date);
                if p.is_file() {
                    v.push(p);
                }
                cur += 1;
            }
            v
        }
    }
}

fn vault_check() -> bool {
    if !cfg().lk_dir.is_dir() {
        println!("{}[Error]{} LK Vault ({}) not found.", RED, RESET, cfg().lk_dir.display());
        return false;
    }
    true
}

fn secs_of(t: &str) -> i64 {
    let p: Vec<i64> = t.split(':').map(|x| x.parse().unwrap_or(0)).collect();
    if p.len() == 3 {
        p[0] * 3600 + p[1] * 60 + p[2]
    } else {
        0
    }
}

// ============================================================================
// lksort
// ============================================================================
fn lksort(args: &[String]) -> i32 {
    if args.is_empty() {
        println!("{}| LK Analytics --- Universal Dashboard Engine ---{}", ORANGE, RESET);
        println!("Usage: lksort [filter] [metric] [order]\n");
        println!("{}[filter]{} (Optional)", CYAN, RESET);
        println!("  YYYY       : Filter by year (e.g., 2026)");
        println!("  YYYYMM     : Filter by month (e.g., 202604)");
        println!("  YYYY-MM    : Filter by month (e.g., 2026-04)\n");
        println!("{}[metric]{} (Optional, Default: date)", LIME, RESET);
        println!("  date       : Sort by chronology");
        println!("  size       : Sort by file size");
        println!("  words      : Sort by word count");
        println!("  lines      : Sort by line count\n");
        println!("{}[order]{}  (Optional, Default: asc)", AMBER, RESET);
        println!("  asc        : Smallest/oldest to largest/newest");
        println!("  desc       : Largest/newest to smallest/oldest\n");
        println!("{}Examples:", GREY);
        println!("  lksort 202604             -> Chronological dashboard for April 2026");
        println!("  lksort 2026 words desc  -> Highest word count files in 2026{}", RESET);
        return 0;
    }
    let mut rest: &[String] = args;
    let mut sc = Sc::All;
    let mut label = "All Notes".to_string();
    let a = args[0].as_str();
    if (a.len() == 4 || a.len() == 6 || is_month_str(a)) && parse_scope(a).is_some() {
        if let Some((s, _)) = parse_scope(a) {
            label = match &s {
                Sc::Year(y) => y.clone(),
                Sc::Month(m) => m.clone(),
                _ => label,
            };
            sc = s;
            rest = &args[1..];
        }
    }
    let files = scope_files(&sc);
    let dir_ok = match &sc {
        Sc::All => cfg().lk_dir.is_dir(),
        Sc::Year(y) => cfg().lk_dir.join(y).is_dir(),
        Sc::Month(m) => cfg().lk_dir.join(&m[..4]).join(m).is_dir(),
        _ => true,
    };
    if !dir_ok {
        println!("\x1b[31m[Error]\x1b[0m Data or directory for '\x1b[38;2;255;255;0m{}\x1b[0m' not found.", label);
        return 1;
    }
    let (metric, order) = if rest.is_empty() {
        ("date".to_string(), "asc".to_string())
    } else {
        (rest[0].clone(), rest.get(1).cloned().unwrap_or_else(|| "asc".to_string()))
    };
    let desc = order != "asc";
    let mut rows: Vec<(usize, usize, usize, PathBuf)> = Vec::new();
    for f in &files {
        let bytes = fs::read(f).unwrap_or_default();
        let text = String::from_utf8_lossy(&bytes).into_owned();
        let lines = bytes.iter().filter(|c| **c == b'\n').count();
        rows.push((lines, nf(&text), bytes.len(), f.clone()));
    }
    match metric.as_str() {
        "table" | "date" => rows.sort_by(|a, b| a.3.cmp(&b.3)),
        "lines" => rows.sort_by(|a, b| a.0.cmp(&b.0).then(a.3.cmp(&b.3))),
        "words" | "wordcount" => rows.sort_by(|a, b| a.1.cmp(&b.1).then(a.3.cmp(&b.3))),
        "size" => rows.sort_by(|a, b| a.2.cmp(&b.2).then(a.3.cmp(&b.3))),
        _ => {
            println!("\x1b[31m[Error]\x1b[0m Metric '{}' unknown. Type 'lksort' for help.", metric);
            return 1;
        }
    }
    if desc {
        rows.reverse();
    }
    print!("\x1b[?7l");
    println!(
        "{}| LK Analytics Dashboard --- [{}] sorted by {} ({}) ---{}",
        ORANGE, label, metric, order, RESET
    );
    let max_words = rows.iter().map(|r| r.1).max().unwrap_or(1).max(1);
    let base = format!("{}/", cfg().lk_dir.display());
    for (lines, words, bytes, path) in &rows {
        let date = date_of(path);
        let summary = summary_of_file(path, true).filter(|s| !s.is_empty()).unwrap_or_else(|| "[Summary Not Found/Not Yet Summarized]".to_string());
        let (colored, raw_len) = fmt_summary(&summary, 38, MAGENTA, RED);
        let pad = if raw_len < 38 { spaces(38 - raw_len) } else { String::new() };
        let mut val = ((*words as f64 / max_words as f64) * 8.0 + 0.5) as usize;
        if val == 0 && *words > 0 {
            val = 1;
        }
        let chart = bar_str(val, 8, "■", "·");
        let rel = path.display().to_string();
        let rel = rel.strip_prefix(&base).unwrap_or(&rel).to_string();
        println!(
            "{}{}{} {}{} {}│ {}{}{} │ {}{:>6} W{} │ {}{:>5} L{} │ {}{:>9}{} │ {}{}{}",
            AMBER, date, RESET, colored, pad, GREY, CYAN, chart, GREY, CYAN, words, RESET, LIME, lines, RESET, LIME, human(*bytes as u64), RESET, PATH_GREY, rel, RESET
        );
    }
    print!("\x1b[?7h");
    0
}

// ============================================================================
// lkrank
// ============================================================================
fn is_ym_like(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() >= 7 && b[..4].iter().all(|c| is_digit(*c)) && b[4] == b'-' && is_digit(b[5]) && is_digit(b[6])
}

fn rank_sorted(m: &HashMap<String, usize>) -> Vec<(usize, String)> {
    let mut v: Vec<(usize, String)> = m.iter().map(|(k, c)| (*c, k.clone())).collect();
    v.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)));
    v
}

fn lkrank(args: &[String]) -> i32 {
    if !vault_check() {
        return 1;
    }
    let mut mode = "all";
    let mut top: usize = 10;
    let mut explicit = false;
    let mut sc = Sc::All;
    let mut scope_label = "Global Lifetime".to_string();
    let n = now();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        match a {
            "-n" => {
                top = args.get(i + 1).and_then(|s| s.parse().ok()).unwrap_or(10);
                explicit = true;
                i += 2;
                continue;
            }
            "-x" | "tax" => mode = "tax",
            x if x.starts_with("taxonomy") => mode = "tax",
            "-t" | "ctx" => mode = "ctx",
            x if x.starts_with("context") => mode = "ctx",
            "-l" | "lnk" => mode = "lnk",
            x if x.starts_with("hyperlink") => mode = "lnk",
            "-h" | "hsh" => mode = "hsh",
            x if x.starts_with("hashtag") => mode = "hsh",
            "-a" | "all" => mode = "all",
            "max" | "full" | "unlimited" => {
                top = 999999;
                explicit = true;
            }
            "m" | "month" | "-m" | "--month" => {
                sc = Sc::Month(n.month());
                scope_label = format!("Monthly Scope ({})", n.month());
            }
            d if all_digits(d) => {
                let len = d.len();
                let year_ok = len == 4 && d.parse::<i32>().map(|y| (1900..=2100).contains(&y)).unwrap_or(false);
                if len == 8 || len == 6 || year_ok {
                    if let Some((s, l)) = parse_scope(d) {
                        sc = s;
                        scope_label = l;
                    }
                } else {
                    top = d.parse().unwrap_or(10);
                    explicit = true;
                }
            }
            d => {
                if let Some((s, l)) = parse_scope(d) {
                    sc = s;
                    scope_label = l;
                }
            }
        }
        i += 1;
    }
    if !explicit && mode != "all" {
        top = 50;
    }
    print!("{}--- Crunching Frequencies for {}... ---{}\r", CYAN, scope_label, RESET);
    let mut ctx: HashMap<String, usize> = HashMap::new();
    let mut tax: HashMap<String, usize> = HashMap::new();
    let mut lnk: HashMap<String, usize> = HashMap::new();
    let mut hsh: HashMap<String, usize> = HashMap::new();
    for f in scope_files(&sc) {
        for line in read_lines(&f) {
            if mode == "all" || mode == "ctx" {
                for (a, b) in find_all_delim(&line, "![", "]!") {
                    let t = &line[a + 2..b - 2];
                    if t != "PLAN" {
                        *ctx.entry(t.to_string()).or_insert(0) += 1;
                    }
                }
            }
            if mode == "all" || mode == "tax" {
                for (a, b) in find_all_delim(&line, "[[", "]] >>") {
                    let t = &line[a + 2..b - 5];
                    if !is_ym_like(t) {
                        *tax.entry(t.to_string()).or_insert(0) += 1;
                    }
                }
            }
            if mode == "all" || mode == "lnk" {
                for (a, b) in find_all_delim(&line, "[[", "]]") {
                    let t = &line[a + 2..b - 2];
                    if !line[b..].starts_with(" >>") && !is_ym_like(t) {
                        *lnk.entry(t.to_string()).or_insert(0) += 1;
                    }
                }
            }
            if mode == "all" || mode == "hsh" {
                let b = line.as_bytes();
                let mut j = 0;
                while j < b.len() {
                    if b[j] == b'#' && (j == 0 || is_ws(b[j - 1])) {
                        let mut k = j + 1;
                        while k < b.len() && (b[k].is_ascii_alphanumeric() || b[k] == b'_' || b[k] == b'-') {
                            k += 1;
                        }
                        if k > j + 1 {
                            *hsh.entry(line[j..k].to_string()).or_insert(0) += 1;
                            j = k;
                            continue;
                        }
                    }
                    j += 1;
                }
            }
        }
    }
    print!("\x1b[2K\r");
    let label = if top == 999999 { "Full/Max Scope".to_string() } else { format!("Top {}", top) };
    println!("{}| LK (LogKlerk) --- Frequency Ranker [{}] ---{}", HEADER_ORG, label, RESET);
    println!("  {}Scope: {}{}\n", GREY, scope_label, RESET);
    let mut any = false;
    let sections: [(&str, &HashMap<String, usize>, &str); 4] = [
        ("[ Context Tags (![x]!) ]", &ctx, MAGENTA),
        ("[ Taxonomies ([[x]] >>) ]", &tax, ORANGE),
        ("[ Hyperlinks ([[x]]) ]", &lnk, CYAN),
        ("[ Hashtags (#x) ]", &hsh, LIME),
    ];
    for (title, map, col) in sections.iter() {
        let v = rank_sorted(map);
        if v.is_empty() {
            continue;
        }
        any = true;
        println!("  \x1b[38;2;170;100;255m{}\x1b[0m", title);
        for (c, name) in v.iter().take(top) {
            println!("    {}{}{} ({}{}x{})", col, name, RESET, GREY, c, RESET);
        }
        println!();
    }
    if !any {
        println!("  {}No data matched the query.{}\n", GREY, RESET);
    }
    println!("{}-------------------------------------------------------{}", HEADER_ORG, RESET);
    0
}

// ============================================================================
// lkvoid
// ============================================================================
fn fmt_time(sec: i64) -> String {
    let h = sec / 3600;
    let rem = sec % 3600;
    let m = rem / 60;
    let s = rem % 60;
    if h > 0 {
        format!("{:02}h {:02}m", h, m)
    } else if m > 0 {
        format!("{:02}m {:02}s", m, s)
    } else {
        format!("    {:02}s", s)
    }
}

fn lkvoid(args: &[String]) -> i32 {
    let mut sc = Sc::All;
    let mut label = "Global Lifetime".to_string();
    if let Some(a) = args.get(0) {
        if let Some((s, _)) = parse_scope(a) {
            match &s {
                Sc::Year(y) => label = y.clone(),
                Sc::Month(m) => label = m.clone(),
                _ => {}
            }
            sc = s;
        }
    }
    let ok = match &sc {
        Sc::All => cfg().lk_dir.is_dir(),
        Sc::Year(y) => cfg().lk_dir.join(y).is_dir(),
        Sc::Month(m) => cfg().lk_dir.join(&m[..4]).join(m).is_dir(),
        _ => true,
    };
    if !ok {
        println!("{}[Error]{} Data for '{}' not found.", RED, RESET, label);
        return 1;
    }
    println!("{}| LK Analytics --- The Void Cartography [{}] ---{}", MAGENTA, label, RESET);
    let mut rows: Vec<(i64, String, i64, i64)> = Vec::new();
    for f in scope_files(&sc) {
        let mut prev: i64 = -1;
        let (mut maxg, mut tot, mut cnt) = (0i64, 0i64, 0i64);
        for l in read_lines(&f) {
            if let Some(t) = log_ts_loose(&l) {
                let cur = secs_of(&t);
                if prev != -1 && cur >= prev {
                    let gap = cur - prev;
                    if gap > maxg {
                        maxg = gap;
                    }
                    tot += gap;
                    cnt += 1;
                }
                prev = cur;
            }
        }
        if cnt > 0 {
            rows.push((maxg, f.display().to_string(), tot, cnt));
        }
    }
    rows.sort_by(|a, b| {
        a.0.cmp(&b.0).then_with(|| {
            format!("{}|{}|{}|{}", a.0, a.1, a.2, a.3).cmp(&format!("{}|{}|{}|{}", b.0, b.1, b.2, b.3))
        })
    });
    println!("  {}Desc   : Measures the longest temporal silence (The Void) in each log.{}", GREY, RESET);
    println!("  {}Note   : Excludes legacy logs with only 1 timestamp (Daily Summaries).{}", GREY, RESET);
    println!("  {}Top Ranks{}    : Days with massive uninterrupted silence (Sleep/Dissociation).", MAGENTA, RESET);
    println!("  {}Bottom Ranks{} : Days with hyper-continuous cognitive flow.\n", LIME, RESET);
    if rows.is_empty() {
        return 0;
    }
    let max_void = rows[rows.len() - 1].0;
    for idx in (0..rows.len()).rev() {
        let (gap, path, tot, cnt) = &rows[idx];
        let avg = tot / cnt;
        let date: String = fname(Path::new(path)).chars().take(10).collect();
        let color = if *gap >= 28800 {
            MAGENTA
        } else if *gap >= 14400 {
            ORANGE
        } else if *gap >= 7200 {
            AMBER
        } else {
            LIME
        };
        let mut filled = if max_void > 0 { ((*gap as f64 / max_void as f64) * 10.0 + 0.5) as usize } else { 0 };
        if filled == 0 && *gap > 0 {
            filled = 1;
        }
        let bar = bar_str(filled, 10, "■", "·");
        println!(
            " {}{:03}.{} {}{}{} │ {}[{}]{} {} Deepest Void: {:<7}{} │ {}(Avg Velocity: {:<7} / log){}",
            GREY, idx + 1, RESET, AMBER, date, RESET, color, bar, RESET, color, fmt_time(*gap), RESET, GREY, fmt_time(avg), RESET
        );
    }
    0
}

// ============================================================================
// lksnap — incremental snapshot (hard-links unchanged files)
// ============================================================================
fn copy_tree(src: &Path, dst: &Path, prev: Option<&Path>, root_src: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;
    for e in fs::read_dir(src)? {
        let e = e?;
        let p = e.path();
        let ft = e.file_type()?;
        let target = dst.join(e.file_name());
        if ft.is_dir() {
            copy_tree(&p, &target, prev, root_src)?;
        } else if ft.is_file() {
            let meta = fs::metadata(&p)?;
            let mut linked = false;
            if let Some(pv) = prev {
                if let Ok(rel) = p.strip_prefix(root_src) {
                    let old = pv.join(rel);
                    if let Ok(om) = fs::metadata(&old) {
                        if om.len() == meta.len() && om.modified().ok() == meta.modified().ok() {
                            if fs::hard_link(&old, &target).is_ok() {
                                linked = true;
                            }
                        }
                    }
                }
            }
            if !linked {
                fs::copy(&p, &target)?;
                if let Ok(mt) = meta.modified() {
                    if let Ok(f) = fs::OpenOptions::new().write(true).open(&target) {
                        let _ = f.set_modified(mt);
                    }
                }
            }
        }
    }
    Ok(())
}

fn lksnap(args: &[String]) -> i32 {
    let suffix = if args.is_empty() {
        String::new()
    } else {
        format!("-{}", args.join("_").replace(' ', "_"))
    };
    let src = cfg().lk_dir.clone();
    if !src.is_dir() {
        println!("{}[Fatal]{} Source Vault ({}) not found.", RED, RESET, src.display());
        return 1;
    }
    let snap_dir = cfg().snap_dir.clone();
    if fs::create_dir_all(&snap_dir).is_err() {
        println!("{}[Fatal]{} Cannot create snapshot directory at {}.", RED, RESET, snap_dir.display());
        return 1;
    }
    let n = now();
    let ts = format!("{:04}{:02}{:02}-{:02}{:02}{:02}", n.y, n.mo, n.d, n.h, n.mi, n.s);
    let target = snap_dir.join(format!("lk-snapshot-{}{}", ts, suffix));
    println!("{}--- Initializing LogKlerk Archival ---{}", CYAN, RESET);
    println!(" Source : {}{}{}", PURPLE, src.display(), RESET);
    println!(" Target : {}{}{}", PURPLE, target.display(), RESET);
    let mut snaps: Vec<PathBuf> = fs::read_dir(&snap_dir)
        .map(|rd| rd.flatten().map(|e| e.path()).collect())
        .unwrap_or_default();
    snaps.retain(|p| fname(p).starts_with("lk-snapshot-") && p.is_dir());
    snaps.sort();
    let latest = snaps.last().cloned();
    match &latest {
        Some(l) => println!(" Method : {}Incremental Hard-Link{} (Referencing {})", MAGENTA, RESET, fname(l)),
        None => println!(" Method : {}Full Clone{} (first snapshot)", AMBER, RESET),
    }
    if let Err(e) = copy_tree(&src, &target, latest.as_deref(), &src) {
        println!("{}[Error]{} Snapshot failed during filesystem copy operation: {}", RED, RESET, e);
        return 1;
    }
    let mut files = Vec::new();
    walk(&target, &mut files);
    let bytes: u64 = files.iter().filter_map(|f| fs::metadata(f).ok()).map(|m| m.len()).sum();
    let size = if bytes >= 1048576 {
        format!("{:.2} MiB", bytes as f64 / 1048576.0)
    } else if bytes >= 1024 {
        format!("{:.2} KiB", bytes as f64 / 1024.0)
    } else {
        format!("{} B", bytes)
    };
    println!("{}✔{} Snapshot successful! [ Logical Size: {}{}{} ]", LIME, RESET, AMBER, size, RESET);
    println!(
        " {}Hint: To rollback, run: rm -rf {}/* && cp -a {}/* {}/{}",
        GREY,
        src.display(),
        target.display(),
        src.display(),
        RESET
    );
    0
}

// ============================================================================
// lkminute / lkhour / lksecond — chronometric analysis
// ============================================================================
fn chrono_header(title: &str, pad: &str) {
    println!("{}||======================================================={}||{}", HEADER_ORG, "", RESET);
    println!("{}|| {}{}{}{}||{}", HEADER_ORG, GOLD, title, HEADER_ORG, pad, RESET);
    println!("{}||======================================================={}||{}", HEADER_ORG, "", RESET);
}

fn all_dates_or_void() -> Option<Vec<PathBuf>> {
    if !cfg().lk_dir.is_dir() {
        println!("\x1b[31m[Blasphemy]\x1b[0m The Chronometric Vault ({}) does not exist.", cfg().lk_dir.display());
        return None;
    }
    let f = scope_files(&Sc::All);
    if f.is_empty() {
        println!("\x1b[31m[Void]\x1b[0m No timeline found. The genesis has not begun.");
        return None;
    }
    Some(f)
}

fn date_name(p: &Path) -> String {
    fname(p).trim_end_matches(".md").to_string()
}

fn lkminute() -> i32 {
    let files = match all_dates_or_void() {
        Some(f) => f,
        None => return if cfg().lk_dir.is_dir() { 0 } else { 1 },
    };
    let days = files.len() as i64;
    let genesis_d = date_name(&files[0]);
    let zen = date_name(&files[files.len() - 1]);
    let mut pulses: i64 = 0;
    let mut captured: i64 = 0;
    let mut freq: BTreeMap<String, i64> = BTreeMap::new();
    for f in &files {
        let mut seen: HashSet<String> = HashSet::new();
        for l in read_lines(f) {
            if let Some(t) = log_ts_loose(&l) {
                pulses += 1;
                let hm = t[..5].to_string();
                if seen.insert(hm.clone()) {
                    captured += 1;
                    *freq.entry(hm).or_insert(0) += 1;
                }
            }
        }
    }
    let quota = days * 1440;
    let void = quota - captured;
    let avg = if days > 0 { captured as f64 / days as f64 } else { 0.0 };
    let coh = if captured > 0 { pulses as f64 / captured as f64 } else { 0.0 };
    let ret = if quota > 0 { captured as f64 / quota as f64 * 100.0 } else { 0.0 };
    let mut maxf = 0;
    let mut apex = "00:00".to_string();
    for (k, v) in &freq {
        if *v > maxf {
            maxf = *v;
            apex = k.clone();
        }
    }
    let rank = if ret < 1.0 {
        "Drifter of the 60th Fraction"
    } else if ret < 5.0 {
        "Warden of the Blocks"
    } else if ret < 10.0 {
        "Weaver of the Minute Hand"
    } else {
        "Architect of the Hourglass"
    };
    chrono_header("LK (LogKlerk) --- CHRONOMETRIC MINUTE ANALYZER", "        ");
    println!("  {}Domain  : Genesis {}{}[[{}]]{}{} to Zenith {}{}[[{}]]{}", GREY, RESET, AMBER, genesis_d, RESET, GREY, RESET, CYAN, zen, RESET);
    println!("  {}Status  : {}{}{}\n", GREY, MAGENTA, rank, RESET);
    println!("  {}✦ THE MORTAL QUOTA (BLOCKS){}", HEADER_ORG, RESET);
    println!("    {}Active Days Recorded : {}{}{} Days{}", GREY, RESET, CYAN, comma(days as u64), RESET);
    println!("    {}Total Usable Minutes : {}{}{} Mins {}(1,440m / day){}\n", GREY, RESET, AMBER, comma(quota as u64), GREY, RESET);
    println!("  {}✦ THE SACRED CAPTURE{}", HEADER_ORG, RESET);
    println!("    {}Minutes Mastered     : {}{}{} Blocks Claimed{}", GREY, RESET, LIME, comma(captured as u64), RESET);
    println!("    {}Chronological Void   : {}{}{} Blocks Lost to the Void{}", GREY, RESET, RED, comma(void as u64), RESET);
    println!("    {}Average Blocks/Day   : {}{}{:.1} Minutes/Day{}", GREY, RESET, CYAN, avg, RESET);
    println!("    {}Temporal Cohesion    : {}{}{:.2} Pulses per Minute{}", GREY, RESET, GOLD, coh, RESET);
    println!("    {}Apex Minute (Peak)   : {}{}{} {}({} days captured this exact minute){}\n", GREY, RESET, MAGENTA, apex, GREY, comma(maxf as u64), RESET);
    let mut filled = ((ret / 5.0) * 40.0) as usize;
    if filled > 40 {
        filled = 40;
    }
    if filled == 0 && captured > 0 {
        filled = 1;
    }
    println!("  {}✦ MINUTE RETENTION RATE{}", HEADER_ORG, RESET);
    println!("    {}{:.2}%{} {}[{}{}{}]{}", LIME, ret, RESET, GREY, RESET, CYAN, bar_str(filled, 40, "█", "·"), GREY);
    print!("{}", RESET);
    if coh > 1.5 {
        println!("\n    {}High Cohesion: You log in dense, hyper-focused bursts.{}", GOLD, RESET);
    } else {
        println!("\n    {}Steady Flow: Your consciousness is evenly spread across time.{}", LIME, RESET);
    }
    println!("{}-----------------------------------------------------------{}", HEADER_ORG, RESET);
    0
}

fn lkhour(args: &[String]) -> i32 {
    if !cfg().lk_dir.is_dir() {
        println!("\x1b[31m[Blasphemy]\x1b[0m The Chronometric Vault ({}) does not exist.", cfg().lk_dir.display());
        return 1;
    }
    let mut chrono = false;
    let mut sc = Sc::All;
    let mut label = "Global Lifetime".to_string();
    let n = now();
    for a in args {
        match a.as_str() {
            "-c" | "chrono" | "--chrono" => chrono = true,
            "-r" | "rank" | "--rank" => chrono = false,
            "m" | "month" | "-m" | "--month" => {
                sc = Sc::Month(n.month());
                label = format!("Monthly Scope ({})", n.month());
            }
            "y" | "year" | "-y" | "--year" => {
                sc = Sc::Year(n.year());
                label = format!("Yearly Scope ({})", n.year());
            }
            "all" => {}
            x if x.starts_with(|c: char| c.is_ascii_digit()) => match parse_scope(x) {
                Some((s, l)) => {
                    sc = s;
                    label = l;
                }
                None => {
                    println!("{}[Error]{} Invalid time target format.", RED, RESET);
                    return 1;
                }
            },
            _ => {}
        }
    }
    let files = scope_files(&sc);
    if files.is_empty() {
        println!("\x1b[31m[Void]\x1b[0m No timeline found. The genesis has not begun.");
        return 0;
    }
    let days = files.len() as i64;
    let genesis_d = date_name(&files[0]);
    let zen = date_name(&files[files.len() - 1]);
    let mut pulse = [0i64; 24];
    let mut total = 0i64;
    let mut captured = 0i64;
    for f in &files {
        let mut seen = HashSet::new();
        for l in read_lines(f) {
            if let Some(t) = log_ts_loose(&l) {
                let h: usize = t[..2].parse().unwrap_or(0);
                if h < 24 {
                    total += 1;
                    pulse[h] += 1;
                    if seen.insert(h) {
                        captured += 1;
                    }
                }
            }
        }
    }
    let quota = days * 24;
    let void = quota - captured;
    let avg = captured as f64 / days as f64;
    let coh = if captured > 0 { total as f64 / captured as f64 } else { 0.0 };
    let ret = if quota > 0 { captured as f64 / quota as f64 * 100.0 } else { 0.0 };
    let rank = if ret < 10.0 {
        "Drifter of the Cycle"
    } else if ret < 25.0 {
        "Warden of the Watch"
    } else if ret < 50.0 {
        "Master of the Dial"
    } else {
        "Architect of Chronos"
    };
    println!("\x1b[2K\r");
    chrono_header("LK (LogKlerk) --- CHRONOMETRIC HOUR ANALYZER", "          ");
    println!("  {}Domain  : {}{}[[{}]]{}{} to {}{}[[{}]]{}", GREY, RESET, AMBER, genesis_d, RESET, GREY, RESET, CYAN, zen, RESET);
    println!("  {}Scope   : {}{}", GREY, RESET, label);
    println!("  {}Status  : {}{}{}\n", GREY, MAGENTA, rank, RESET);
    println!("  {}✦ THE MORTAL QUOTA (PILLARS){}", HEADER_ORG, RESET);
    println!("    {}Active Days Recorded : {}{}{} Days{}", GREY, RESET, CYAN, comma(days as u64), RESET);
    println!("    {}Total Usable Pillars : {}{}{} Hours {}(24h / day){}\n", GREY, RESET, AMBER, comma(quota as u64), GREY, RESET);
    println!("  {}✦ THE SACRED CAPTURE{}", HEADER_ORG, RESET);
    println!("    {}Hours Mastered       : {}{}{} Pillars Claimed{}", GREY, RESET, LIME, comma(captured as u64), RESET);
    println!("    {}Chronological Void   : {}{}{} Pillars Lost to the Void{}", GREY, RESET, RED, comma(void as u64), RESET);
    println!("    {}Average Pillars/Day  : {}{}{:.1} Hours/Day{}", GREY, RESET, CYAN, avg, RESET);
    println!("    {}Temporal Cohesion    : {}{}{:.2} Pulses per Hour{}\n", GREY, RESET, GOLD, coh, RESET);
    let mut filled = ((ret / 100.0) * 40.0) as usize;
    if filled > 40 {
        filled = 40;
    }
    if filled == 0 && captured > 0 {
        filled = 1;
    }
    println!("  {}✦ PILLAR RETENTION RATE{}", HEADER_ORG, RESET);
    println!("    {}{:.2}%{} {}[{}{}{}{}]{}\n", LIME, ret, RESET, GREY, RESET, CYAN, bar_str(filled, 40, "█", "·"), GREY, RESET);
    let title = if chrono { "Chronological 24-Hour Distribution" } else { "Ranked by Activity Volume" };
    println!("  {}✦ [ {} ] ✦{}", PURPLE, title, RESET);
    let max_v = *pulse.iter().max().unwrap_or(&0);
    let mut idx: Vec<usize> = (0..24).collect();
    if !chrono {
        idx.sort_by(|a, b| pulse[*b].cmp(&pulse[*a]));
    }
    for (rank_i, h) in idx.iter().enumerate() {
        let count = pulse[*h];
        let blen = if max_v > 0 { ((count as f64 / max_v as f64) * 30.0) as usize } else { 0 };
        let bar = bar_str(blen, 30, "█", " ");
        let bcol = if count == max_v && count > 0 {
            ORANGE
        } else if count as f64 > max_v as f64 * 0.7 {
            CYAN
        } else if count as f64 > max_v as f64 * 0.3 {
            GREY
        } else {
            "\x1b[38;2;80;80;80m"
        };
        if !chrono {
            let r = rank_i + 1;
            let rc = if r == 1 { ORANGE } else if r <= 3 { CYAN } else { GREY };
            println!("   {}{:02}{} | {}{:02}:xx{} | {}{}{} {}({} pulses){}", rc, r, RESET, CYAN, h, RESET, bcol, bar, RESET, GREY, count, RESET);
        } else {
            println!("   {}{:02}:xx{} | {}{}{} {}({} pulses){}", CYAN, h, RESET, bcol, bar, RESET, GREY, count, RESET);
        }
    }
    println!("{}-----------------------------------------------------------{}", HEADER_ORG, RESET);
    0
}

fn lksecond() -> i32 {
    let files = match all_dates_or_void() {
        Some(f) => f,
        None => return if cfg().lk_dir.is_dir() { 0 } else { 1 },
    };
    let days = files.len() as i64;
    let genesis_d = date_name(&files[0]);
    let zen = date_name(&files[files.len() - 1]);
    let mut pulses = 0i64;
    let mut hours: BTreeMap<String, i64> = BTreeMap::new();
    for f in &files {
        for l in read_lines(f) {
            if let Some(t) = log_ts_loose(&l) {
                pulses += 1;
                *hours.entry(t[..2].to_string()).or_insert(0) += 1;
            }
        }
    }
    let quota = days * 86400;
    let void = quota - pulses;
    let avg = pulses as f64 / days as f64;
    let ret = pulses as f64 / quota as f64 * 100.0;
    let (mut maxp, mut apex) = (0i64, "00".to_string());
    for (h, c) in &hours {
        if *c > maxp {
            maxp = *c;
            apex = h.clone();
        }
    }
    let rank = if ret < 0.1 {
        "Initiate of the Void"
    } else if ret < 0.5 {
        "Acolyte of Seconds"
    } else if ret < 1.0 {
        "Weaver of the Timeline"
    } else {
        "Architect of Chronos"
    };
    chrono_header("LK (LogKlerk) --- CHRONOMETRIC MASS ANALYZER", "        ");
    println!("  {}Domain  : Genesis {}{}[[{}]]{}{} to Zenith {}{}[[{}]]{}", GREY, RESET, AMBER, genesis_d, RESET, GREY, RESET, CYAN, zen, RESET);
    println!("  {}Status  : {}{}{}\n", GREY, MAGENTA, rank, RESET);
    println!("  {}✦ THE MORTAL QUOTA{}", HEADER_ORG, RESET);
    println!("    {}Active Days Recorded : {}{}{} Days{}", GREY, RESET, CYAN, comma(days as u64), RESET);
    println!("    {}Total Usable Seconds : {}{}{} Sec {}(86,400s / day){}\n", GREY, RESET, AMBER, comma(quota as u64), GREY, RESET);
    println!("  {}✦ THE SACRED CAPTURE{}", HEADER_ORG, RESET);
    println!("    {}Captured Pulses      : {}{}{} Seconds Defied Entropy{}", GREY, RESET, LIME, comma(pulses as u64), RESET);
    println!("    {}Chronological Void   : {}{}{} Seconds Lost to the Void{}", GREY, RESET, RED, comma(void as u64), RESET);
    println!("    {}Average Capture/Day  : {}{}{:.2} Seconds/Day{}", GREY, RESET, CYAN, avg, RESET);
    println!("    {}Apex Hour (Densest)  : {}{}{}:00 {}({} pulses localized here){}\n", GREY, RESET, MAGENTA, apex, GREY, comma(maxp as u64), RESET);
    let mut filled = ((ret / 1.0) * 40.0) as usize;
    if filled > 40 {
        filled = 40;
    }
    if filled == 0 && pulses > 0 {
        filled = 1;
    }
    println!("  {}✦ PULSE RETENTION RATE{}", HEADER_ORG, RESET);
    println!("    {}{:.3}%{} {}[{}{}{}]{}", LIME, ret, RESET, GREY, RESET, CYAN, bar_str(filled, 40, "█", "·"), RESET);
    if ret < 0.05 {
        println!("\n    {}WARNING: Heavy entropy detected. Time is bleeding.{}", RED, RESET);
    } else {
        println!("\n    {}Entropy contained. The Timeline acknowledges your effort.{}", LIME, RESET);
    }
    println!("{}-----------------------------------------------------------{}", HEADER_ORG, RESET);
    0
}

// ============================================================================
// lkspace — YAML metadata injection (chronotope)
// ============================================================================
const DEFAULT_SPACE_MAP: &str = "os=\"Operating System\"\nlocation=\"Location\"\nwm=\"Window Manager\"\nkernel=\"Kernel\"\ndevice=\"Device\"\ntools=\"Tools\"\nhyperfocus=\"Hyperfocus\"\nposition=\"Position\"\nday=\"Day\"\ntidiness=\"Tidiness\"\nneatness=\"Neatness\"\nmood=\"Mood\"\ncoffee=\"Coffee\"\nbudget=\"Budget\"\nhealth=\"Health Rate\"\n";

fn yaml_inject(lines: Vec<String>, key: &str, val: &str) -> Vec<String> {
    let q = format!("\"{}\"", val);
    let mut out = Vec::new();
    let mut in_yaml = false;
    let mut injected = false;
    let key_colon = format!("{}:", key);
    for (i, l) in lines.into_iter().enumerate() {
        let fence = is_yaml_fence(&l);
        if i == 0 && fence {
            in_yaml = true;
            out.push(l);
            continue;
        }
        if in_yaml && fence {
            if !injected {
                out.push(format!("{}: {}", key, q));
                injected = true;
            }
            in_yaml = false;
            out.push(l);
            continue;
        }
        if in_yaml {
            if l.starts_with(&key_colon) {
                out.push(format!("{}: {}", key, q));
                injected = true;
            } else {
                out.push(l);
            }
            continue;
        }
        if i == 0 {
            out.push("---".to_string());
            out.push(format!("{}: {}", key, q));
            out.push("---".to_string());
            out.push(String::new());
            out.push(l);
            injected = true;
            continue;
        }
        out.push(l);
    }
    out
}

fn lkspace(args: &[String]) -> i32 {
    let map_file = cfg().modules_dir.join("lkspace.map");
    let _ = fs::create_dir_all(&cfg().modules_dir);
    if !map_file.exists() {
        let _ = fs::write(&map_file, DEFAULT_SPACE_MAP);
    }
    if args.get(0).map(|s| s.as_str()) == Some("add") {
        let a = args.get(1).cloned().unwrap_or_default();
        if a.is_empty() || !a.contains('=') {
            println!("{}[Syntax Error]{} Format must be: lkspace add var=\"Long Name\"", RED, RESET);
            println!("Example: lkspace add os=\"Operating System\"");
            return 1;
        }
        let eq = a.find('=').unwrap();
        let k = a[..eq].to_string();
        let v = strip_quotes(&a[eq + 1..]);
        let prefix = format!("{}=", k);
        let mut lines: Vec<String> = read_lines(&map_file).into_iter().filter(|l| !l.starts_with(&prefix)).collect();
        lines.push(format!("{}=\"{}\"", k, v));
        let _ = write_lines(&map_file, &lines);
        println!("{}✔{} Space Variable Mapped: {}{}{} -> {}{}{}", LIME, RESET, PURPLE, k, RESET, CYAN, v, RESET);
        return 0;
    }
    if args.len() < 3 {
        println!("{}[Syntax Error]{} Usage: lkspace [TIME] [VAR] [VALUE]", RED, RESET);
        println!("Examples:\n  lkspace 202510 os NixOS\n  lkspace 2024-03-19 os \"Ubuntu Linux\"");
        return 1;
    }
    let target_time = args[0].clone();
    let target_var = args[1].clone();
    let target_val = strip_quotes(&args[2..].join(" "));
    let prefix = format!("{}=", target_var);
    let mapped = read_lines(&map_file)
        .into_iter()
        .find(|l| l.starts_with(&prefix))
        .map(|l| strip_quotes(&l[prefix.len()..]))
        .unwrap_or_default();
    let mapped = if mapped.is_empty() {
        println!("{}[Warn]{} Variable '{}' is not mapped. Using raw name.", AMBER, RESET, target_var);
        target_var.clone()
    } else {
        mapped
    };

    let lk_dir = cfg().lk_dir.clone();
    let mut files: Vec<PathBuf> = Vec::new();
    let scope_name: String;
    let t = target_time.as_str();
    let touch = |p: &Path| {
        if let Some(par) = p.parent() {
            let _ = fs::create_dir_all(par);
        }
        if !p.exists() {
            let _ = fs::write(p, "");
        }
    };
    if t.len() == 4 && all_digits(t) {
        let mut v = Vec::new();
        walk(&lk_dir.join(t), &mut v);
        v.retain(|p| fname(p).ends_with(".md"));
        v.sort();
        files = v;
        scope_name = format!("Year {}", t);
    } else if (t.len() == 6 && all_digits(t)) || is_month_str(t) {
        let (y, m) = if t.len() == 6 { (&t[..4], &t[4..]) } else { (&t[..4], &t[5..]) };
        let mut v = Vec::new();
        walk(&lk_dir.join(y).join(format!("{}-{}", y, m)), &mut v);
        v.retain(|p| fname(p).ends_with(".md"));
        v.sort();
        files = v;
        scope_name = format!("Month {}-{}", y, m);
    } else if (t.len() == 8 && all_digits(t)) || is_date_str(t) {
        let d = norm_date(t);
        let f = day_path(&d);
        touch(&f);
        files.push(f);
        scope_name = format!("Date {}", d);
    } else if t.len() == 17 && t.as_bytes()[8] == b'-' && all_digits(&t[..8]) && all_digits(&t[9..]) {
        let s = norm_date(&t[..8]);
        let e = norm_date(&t[9..]);
        let (sy, sm, sd) = ymd_of(&s);
        let (ey, em, ed) = ymd_of(&e);
        let mut cur = days_from_civil(sy, sm, sd);
        let end = days_from_civil(ey, em, ed);
        while cur <= end {
            let (y, m, d) = civil_from_days(cur);
            let f = day_path(&format!("{:04}-{:02}-{:02}", y, m, d));
            touch(&f);
            files.push(f);
            cur += 1;
        }
        scope_name = format!("Range {} to {}", s, e);
    } else {
        println!("{}[Error]{} Invalid time target format.", RED, RESET);
        return 1;
    }
    if files.is_empty() {
        println!("{}[Info]{} No files found for temporal target: {}", CYAN, RESET, scope_name);
        return 0;
    }
    println!("{}--- Injecting Chronotope Metadata ---{}", CYAN, RESET);
    println!(" Scope : {}{}{} ({} files)", PURPLE, scope_name, RESET, files.len());
    println!(" Key   : {}{}{}", LIME, mapped, RESET);
    println!(" Value : {}\"{}\"{}", CYAN, target_val, RESET);
    for f in &files {
        let meta_len = fs::metadata(f).map(|m| m.len()).unwrap_or(0);
        if meta_len == 0 {
            let body = format!("---\n{}: \"{}\"\n---\n\n", mapped, target_val);
            let _ = write_atomic(f, &body);
            continue;
        }
        let out = yaml_inject(read_lines(f), &mapped, &target_val);
        let _ = write_lines(f, &out);
    }
    println!("{}✔{} Injection Complete.", LIME, RESET);
    0
}

// ============================================================================
// lkchart
// ============================================================================
fn lkchart(args: &[String]) -> i32 {
    if !vault_check() {
        return 1;
    }
    let n = now();
    if args.is_empty() || matches!(args[0].as_str(), "help" | "-h" | "--help") {
        println!("{}| LK (LogKlerk) --- Visualization Engine Help ---{}", HEADER_ORG, RESET);
        println!("Usage: lkchart [mode]\n");
        println!("{}[Shortcuts]{}", LIME, RESET);
        println!("  {}m, month{}      : Daily chart for the current month (Default scope)", CYAN, RESET);
        println!("  {}d, day{}        : Hourly chart for the current day\n", AMBER, RESET);
        println!("{}[Global Modes]{}", LIME, RESET);
        println!("  y, year       : Global yearly chart");
        println!("  ym, yyyymm    : Global monthly chart");
        println!("  ymd, yyyymmdd : Global daily chart\n");
        println!("{}[Scoped Modes]{}", LIME, RESET);
        println!("  YYYY          : Monthly chart for a specific year");
        println!("  YYYYMM        : Daily chart for a specific month");
        println!("  YYYYMMDD      : Hourly chart for a specific day\n");
        return 0;
    }
    let a = args[0].as_str();
    let mode: &str;
    let files: Vec<PathBuf>;
    let gl: usize;
    let title: String;
    let hourly_date: Option<String>;
    match a {
        "m" | "month" | "-m" | "--month" => {
            mode = "DAILY_SCOPED";
            files = scope_files(&Sc::Month(n.month()));
            gl = 10;
            title = format!("Daily Matrix Scope ({})", n.month());
            hourly_date = None;
        }
        "d" | "day" | "-d" | "--day" => {
            mode = "HOURLY_SCOPED";
            files = vec![];
            gl = 0;
            title = format!("Hourly Execution Matrix ({})", n.date());
            hourly_date = Some(n.date());
        }
        "-y" | "-Y" | "y" | "Y" | "yyyy" | "YYYY" | "year" | "-year" | "--year" => {
            mode = "YEARLY";
            files = scope_files(&Sc::All);
            gl = 4;
            title = "Global Yearly Matrix".to_string();
            hourly_date = None;
        }
        "-ym" | "-YM" | "ym" | "YM" | "yyyymm" | "YYYYMM" => {
            mode = "MONTHLY";
            files = scope_files(&Sc::All);
            gl = 7;
            title = "Global Monthly Matrix".to_string();
            hourly_date = None;
        }
        "-ymd" | "-YMD" | "ymd" | "YMD" | "yyyymmdd" | "YYYYMMDD" => {
            mode = "DAILY";
            files = scope_files(&Sc::All);
            gl = 10;
            title = "Global Daily Genesis Matrix".to_string();
            hourly_date = None;
        }
        x if x.len() == 4 && all_digits(x) => {
            mode = "MONTHLY_SCOPED";
            files = scope_files(&Sc::Year(x.to_string()));
            gl = 7;
            title = format!("Monthly Matrix Scope ({})", x);
            hourly_date = None;
        }
        x if (x.len() == 6 && all_digits(x)) || is_month_str(x) => {
            let ym = if x.len() == 6 { format!("{}-{}", &x[..4], &x[4..]) } else { x.to_string() };
            mode = "DAILY_SCOPED";
            files = scope_files(&Sc::Month(ym.clone()));
            gl = 10;
            title = format!("Daily Matrix Scope ({})", ym);
            hourly_date = None;
        }
        x if (x.len() == 8 && all_digits(x)) || is_date_str(x) => {
            let d = norm_date(x);
            mode = "HOURLY_SCOPED";
            files = vec![];
            gl = 0;
            title = format!("Hourly Execution Matrix ({})", d);
            hourly_date = Some(d);
        }
        _ => {
            println!("{}[Error]{} Unknown mode '{}'. Type 'lkchart' for help.", RED, RESET, a);
            return 1;
        }
    }
    print!("{}--- Rendering {}... ---{}\r", CYAN, title, RESET);
    let mut agg: BTreeMap<String, (usize, usize)> = BTreeMap::new();
    if let Some(d) = &hourly_date {
        let f = day_path(d);
        if !f.is_file() {
            println!("\x1b[2K\r{}[Error]{} Log file for {} not found.", RED, RESET, d);
            return 1;
        }
        for l in read_lines(&f) {
            if is_log_line8(&l) {
                let hh = &l[10..12];
                let e = agg.entry(format!("{}:00", hh)).or_insert((0, 0));
                e.0 += nf(&l[21..]);
                e.1 += 1;
            }
        }
    } else {
        if files.is_empty() && matches!(mode, "DAILY_SCOPED" | "MONTHLY_SCOPED") {
            println!("\x1b[2K\r{}[Error]{} Log directory for {} not found.", RED, RESET, title);
            return 1;
        }
        for f in &files {
            let bytes = fs::read(f).unwrap_or_default();
            let text = String::from_utf8_lossy(&bytes).into_owned();
            let lines = bytes.iter().filter(|c| **c == b'\n').count();
            let key: String = fname(f).chars().take(gl).collect();
            let e = agg.entry(key).or_insert((0, 0));
            e.0 += nf(&text);
            e.1 += lines;
        }
    }
    println!("\n{}| LK (LogKlerk) --- Visualization Engine ---{}", HEADER_ORG, RESET);
    println!("  {}[ {} (By Word Volume) ]{}\n", PURPLE, title, RESET);
    if agg.is_empty() {
        println!("    {}[Error]{} No data found to chart.", RED, RESET);
        return 0;
    }
    let max_words = agg.values().map(|v| v.0).max().unwrap_or(0).max(1);
    let mut cur_year = String::new();
    let (mut yw, mut yl) = (0usize, 0usize);
    let sepl = format!("    {}----------------------------------------{}", DARKGREY, RESET);
    let tot = |y: &str, w: usize, l: usize| {
        println!("{}", sepl);
        println!(
            "    {}=== [[ {} ]] Total Contribution: {}{} words {}| {} lines ==={}",
            AMBER, y, CYAN, w, DARKGREY, l, RESET
        );
        println!("{}", sepl);
    };
    for (prefix, (words, lines)) in &agg {
        if mode == "MONTHLY" {
            let ty = prefix[..4usize.min(prefix.len())].to_string();
            if !cur_year.is_empty() && ty != cur_year {
                tot(&cur_year, yw, yl);
                yw = 0;
                yl = 0;
            }
            cur_year = ty;
            yw += words;
            yl += lines;
        }
        let mut blocks = words * 30 / max_words;
        if blocks == 0 && *words > 0 {
            blocks = 1;
        }
        let bar = "#".repeat(blocks);
        let wtxt = format!("{} words", words);
        if mode == "HOURLY_SCOPED" {
            println!("    {}[[{}]]{} {}{:<30}{} {}{:<11}{} {}| {} lines{}", CYAN, prefix, RESET, LIME, bar, RESET, ORANGE, wtxt, RESET, DARKGREY, lines, RESET);
        } else {
            println!("    {}[[{}]]{} {}{:<30}{} {}{:<11}{} {}| {} lines{}", AMBER, prefix, RESET, ORANGE, bar, RESET, CYAN, wtxt, RESET, DARKGREY, lines, RESET);
        }
    }
    if mode == "MONTHLY" && !cur_year.is_empty() {
        tot(&cur_year, yw, yl);
    }
    println!("\n{}-------------------------------------------------------{}\n", HEADER_ORG, RESET);
    0
}

// ============================================================================
// lkstat — analytics engine
// ============================================================================
fn strip_log_prefix(line: &str, hourly: bool) -> Option<String> {
    let b = line.as_bytes();
    let mut i = skip_ws(b, 0);
    if i + 2 > b.len() || b[i] != b'-' || b[i + 1] != b' ' {
        return None;
    }
    i += 2;
    if hourly {
        if b.len() < i + 3 || &b[i..i + 3] != b"## " {
            return None;
        }
        i += 3;
        if !hh00_at(b, i) {
            return None;
        }
        i += 5;
    } else {
        if !hhmmss_at(b, i) {
            return None;
        }
        i += 8;
    }
    if b.len() < i + 2 || &b[i..i + 2] != b" -" {
        return None;
    }
    i += 2;
    i = skip_ws(b, i);
    Some(line[i..].to_string())
}

// ^ws*- #* ?[[x]] -ws*
fn strip_summary_prefix(line: &str) -> Option<String> {
    let b = line.as_bytes();
    let mut i = skip_ws(b, 0);
    if i + 2 > b.len() || b[i] != b'-' || b[i + 1] != b' ' {
        return None;
    }
    i += 2;
    while i < b.len() && b[i] == b'#' {
        i += 1;
    }
    if i < b.len() && b[i] == b' ' {
        i += 1;
    }
    let (a, e) = match_delim(line, i, "[[", "]]")?;
    if a != i {
        return None;
    }
    if line.len() < e + 2 || &line[e..e + 2] != " -" {
        return None;
    }
    let j = skip_ws(b, e + 2);
    Some(line[j..].to_string())
}

fn manual_text(line: &str) -> String {
    let mut s = line.to_string();
    if let Some(r) = strip_log_prefix(&s, false) {
        s = r;
    }
    if let Some(r) = strip_log_prefix(&s, true) {
        s = r;
    }
    s = remove_all_delim(&s, "[[", "]] >>", true);
    s = remove_all_delim(&s, "![", "]!", true);
    if let Some(r) = strip_summary_prefix(&s) {
        s = r;
    }
    s
}

fn top3(m: &HashMap<String, usize>) -> Vec<(String, usize)> {
    let mut v: Vec<(String, usize)> = m.iter().map(|(k, c)| (k.clone(), *c)).collect();
    v.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    v.truncate(3);
    v
}

fn lkstat(args: &[String]) -> i32 {
    if !vault_check() {
        return 1;
    }
    let mut sc = Sc::All;
    let mut scope = "Global Lifetime".to_string();
    let mut is_month = false;
    let mut month_days = 30i64;
    if let Some(a) = args.get(0) {
        match parse_scope(a) {
            Some((s, l)) if !matches!(s, Sc::DateRange(_, _)) => {
                if let Sc::Month(ym) = &s {
                    is_month = true;
                    let (y, m, _) = ymd_of(&format!("{}-01", ym));
                    month_days = days_in_month(y, m);
                }
                sc = s;
                scope = l;
            }
            _ => {
                println!("{}[Error]{} Invalid scope. Use YYYY, YYYY-MM, YYYY-MM-DD, or YYYY-YYYY.", RED, RESET);
                return 1;
            }
        }
    }
    print!("{}--- Initializing Quantum Analytics for {}... ---{}\r", CYAN, scope, RESET);
    let all = scope_files(&Sc::All);
    let genesis = all.first().map(|p| date_name(p)).unwrap_or_else(|| "Unknown".to_string());
    let gl_files = all.len();
    let gl_words: usize = all.iter().map(|f| nf(&read_text(f))).sum();

    let files = scope_files(&sc);
    let gl_prefix = if scope.starts_with("Yearly Scope") {
        7
    } else if scope.starts_with("Monthly Scope") {
        10
    } else if scope.starts_with("Daily Scope") {
        0
    } else {
        4
    };
    let (mut raw_t, mut man_t, mut auto_t) = (0usize, 0usize, 0usize);
    let mut total_logs = 0usize;
    let mut hours: HashMap<String, usize> = HashMap::new();
    let mut tags: HashMap<String, usize> = HashMap::new();
    let mut taxs: HashMap<String, usize> = HashMap::new();
    let (mut pure_w, mut alpha_w, mut piped_w, mut sym_w) = (0usize, 0usize, 0usize, 0usize);
    let (mut max_vw, mut max_vd) = (0usize, String::new());
    let (mut max_fl, mut max_fn) = (0usize, String::new());
    let mut growth: BTreeMap<String, usize> = BTreeMap::new();
    let mut order: Vec<String> = Vec::new();
    let mut max_growth = 0usize;

    for f in &files {
        let fnm = fname(f);
        let date_str: String = fnm.chars().take(10).collect();
        let mut fman = 0usize;
        let mut flines = 0usize;
        for line in read_lines(f) {
            flines += 1;
            let raw_nf = nf(&line);
            let man = manual_text(&line);
            let man_nf = nf(&man);
            let auto_nf = raw_nf.saturating_sub(man_nf);
            raw_t += raw_nf;
            man_t += man_nf;
            auto_t += auto_nf;
            fman += man_nf;
            if let Some((t, _)) = log_ts(&line) {
                *hours.entry(t[..2].to_string()).or_insert(0) += 1;
                total_logs += 1;
            }
            for (a, b) in find_all_delim(&line, "![", "]!") {
                let t = &line[a + 2..b - 2];
                if t != "PLAN" {
                    *tags.entry(t.to_string()).or_insert(0) += 1;
                }
            }
            for (a, b) in find_all_delim(&line, "[[", "]] >>") {
                let t = &line[a + 2..b - 5];
                if !is_ym_like(t) {
                    *taxs.entry(t.to_string()).or_insert(0) += 1;
                }
            }
            for w in man.split(|c: char| c == ' ' || c == '\t').filter(|w| !w.is_empty()) {
                if w.chars().all(|c| c.is_ascii_alphabetic()) {
                    pure_w += 1;
                } else if w.chars().all(|c| c.is_ascii_alphanumeric()) {
                    alpha_w += 1;
                } else if w.contains('|') {
                    piped_w += 1;
                } else {
                    sym_w += 1;
                }
            }
        }
        if fman > max_vw {
            max_vw = fman;
            max_vd = date_str.clone();
        }
        if flines > max_fl {
            max_fl = flines;
            max_fn = fnm.clone();
        }
        if gl_prefix > 0 {
            let p: String = date_str.chars().take(gl_prefix).collect();
            if !growth.contains_key(&p) {
                order.push(p.clone());
            }
            let e = growth.entry(p).or_insert(0);
            *e += fman;
            if *e > max_growth {
                max_growth = *e;
            }
        }
    }
    print!("\x1b[2K\r\n");
    println!("{}| LK (LogKlerk) --- Analytics Engine : {} ---{}", HEADER_ORG, scope, RESET);
    if files.is_empty() {
        println!("  {}[Error]{} No data found in this scope.", RED, RESET);
        return 0;
    }
    let scoped = files.len();
    let scope_pct = if gl_words > 0 { raw_t * 100 / gl_words } else { 0 };
    let man_pct = if raw_t > 0 { man_t * 100 / raw_t } else { 0 };
    let auto_pct = 100 - man_pct as i64;
    let avg_logs = total_logs / scoped;
    let avg_wpl = if total_logs > 0 { man_t / total_logs } else { 0 };
    println!("  {}[ 1. Universal Origin & Scale ]{}", PURPLE, RESET);
    println!("    System Genesis       : {}{}{} (First recorded entry)", AMBER, genesis, RESET);
    println!("    Scope Contribution   : {}{}{} raw words ({}{}%{} of Global Vault)", CYAN, raw_t, RESET, ORANGE, scope_pct, RESET);
    println!("    Scope Active Days    : {}{}{} / {}{}{} Global Active Days\n", CYAN, scoped, RESET, GREY, gl_files, RESET);
    if gl_prefix > 0 {
        println!("  {}[ Pure Cognitive Growth Matrix (Manual Word Volume) ]{}", PURPLE, RESET);
        for p in &order {
            let w = growth[p];
            if max_growth > 0 && w > 0 {
                let mut bl = w * 30 / max_growth;
                if bl == 0 {
                    bl = 1;
                }
                println!("    {}[[{}]]{} {}{}{} {}{} words{}", GREY, p, RESET, LIME, "#".repeat(bl), RESET, CYAN, w, RESET);
            }
        }
        println!();
    }
    println!("  {}[ 2. Lexical & Verbosity Analysis ]{}", PURPLE, RESET);
    println!("    Total Words Recorded : {}{}{} words", GREY, raw_t, RESET);
    println!("      ├── Manual Typed   : {}{}{} words ({}{}%{} Biological)", CYAN, man_t, RESET, LIME, man_pct, RESET);
    println!("      └── Auto-Generated : {}{}{} words ({}{}%{} Cybernetic)", GREY, auto_t, RESET, ORANGE, auto_pct, RESET);
    println!("    Manual Lexical Breakdown:");
    println!("      ├── Pure Words     : {}{}{} (a-z)", GREY, pure_w, RESET);
    println!("      ├── Alphanumeric   : {}{}{} (a-z, 0-9)", GREY, alpha_w, RESET);
    println!("      ├── Piped Phrases  : {}{}{} (x|y|z formatting)", LIME, piped_w, RESET);
    println!("      └── Sym/Punctuation: {}{}{}", GREY, sym_w, RESET);
    println!("    Average Verbosity    : {}{}{} manual words / log entry\n", CYAN, avg_wpl, RESET);
    println!("  {}[ 3. Conceptual Dominance (Top Metadata) ]{}", PURPLE, RESET);
    println!("    {}Top Context Tags (![...]):{}", AMBER, RESET);
    let tt = top3(&tags);
    for (k, v) in &tt {
        println!("      ├── {}{}{} ({} mentions)", MAGENTA, k, RESET, v);
    }
    if tt.is_empty() {
        println!("      └── {}None recorded.{}", GREY, RESET);
    }
    println!("    {}Top Taxonomies ([[...]] >>):{}", ORANGE, RESET);
    let tx = top3(&taxs);
    for (k, v) in &tx {
        println!("      ├── {}{}{} ({} mentions)", ORANGE, k, RESET, v);
    }
    if tx.is_empty() {
        println!("      └── {}None recorded.{}", GREY, RESET);
    }
    println!();
    println!("  {}[ 4. Local Bests (Scope Extremes) ]{}", PURPLE, RESET);
    println!("    Most Verbose Day     : {}{}{} ({}{}{} manual words)", CYAN, max_vd, RESET, ORANGE, max_vw, RESET);
    println!("    Average Activity     : {}{}{} logs / active day", CYAN, avg_logs, RESET);
    println!("    Largest Log File     : {}{}{} ({}{}{} lines)\n", CYAN, max_fn, RESET, GREY, max_fl, RESET);
    let mut peak_hr = "N/A".to_string();
    let mut peak_c = 0usize;
    let mut hv: Vec<(&String, &usize)> = hours.iter().collect();
    hv.sort();
    for (h, c) in hv {
        if *c > peak_c {
            peak_c = *c;
            peak_hr = h.clone();
        }
    }
    let mut persona = "Unknown";
    if peak_hr != "N/A" {
        let h: u32 = peak_hr.parse().unwrap_or(0);
        persona = if h >= 22 || h <= 3 {
            "Nocturnal (Night Owl)"
        } else if (4..=8).contains(&h) {
            "Early Riser (Morning Bird)"
        } else if (9..=15).contains(&h) {
            "Daylight Worker"
        } else {
            "Evening Grinder"
        };
    }
    println!("  {}[ 5. Behavioral Metrics ]{}", PURPLE, RESET);
    println!("    System Persona       : {}{}{}", AMBER, persona, RESET);
    println!("    Peak Productivity    : {}{}:xx{} ({} logs recorded in scope)", LIME, peak_hr, RESET, peak_c);
    if is_month && month_days > 0 {
        let cons = (scoped as i64 * 100 / month_days) as usize;
        println!("    Monthly Consistency  : {}{}/{}{} days recorded in {}", CYAN, scoped, month_days, RESET, scope);
        let filled = (cons * 20 / 100).min(20);
        println!(
            "    Consistency Rate     : [{}{}{}{}{}] {}{}%{}",
            LIME, "#".repeat(filled), GREY, "-".repeat(20 - filled), RESET, LIME, cons, RESET
        );
    }
    println!("\n{}-------------------------------------------------------{}\n", HEADER_ORG, RESET);
    0
}

// ============================================================================
// lkweight — karmic scoring
// ============================================================================
fn weight_file() -> PathBuf {
    cfg().config_dir.join("weights.list")
}

fn load_weights() -> Vec<(i64, String, String)> {
    let mut v = Vec::new();
    for l in read_lines(&weight_file()) {
        if l.contains('|') {
            let parts: Vec<&str> = l.split('|').collect();
            let w: i64 = parts[0].trim().parse().unwrap_or(0);
            let orig = parts.get(1).copied().unwrap_or("").to_string();
            v.push((w, orig.to_lowercase(), orig));
        }
    }
    v
}

fn count_occ(hay: &str, pat: &str) -> i64 {
    if pat.is_empty() {
        return 0;
    }
    hay.matches(pat).count() as i64
}

fn tier_of(sc: i64) -> (&'static str, &'static str, &'static str) {
    if sc >= 5000 {
        ("Ascended / God-Tier", W_BIRUTUA, "+")
    } else if sc >= 1000 {
        ("Highly Productive", W_BIRU, "+")
    } else if sc > 0 {
        ("Net Positive", W_HIJAU, "+")
    } else if sc == 0 {
        ("Absolute Neutral", GREY245, "")
    } else if sc > -1000 {
        ("Friction / Distracted", W_KUNING, "")
    } else if sc > -5000 {
        ("Void Exposure", W_MERAH, "")
    } else {
        ("Catastrophic Hijack", W_MERAHTUA, "")
    }
}

fn weight_calc() -> Vec<(i64, String, String)> {
    let weights = load_weights();
    let mut out = Vec::new();
    for f in scope_files(&Sc::All) {
        let mut score = 0i64;
        for l in read_lines(&f) {
            let low = l.to_lowercase();
            for (w, pat, _) in &weights {
                score += w * count_occ(&low, pat);
            }
        }
        let mut summary = summary_of_file(&f, true).unwrap_or_default();
        if summary.is_empty() {
            summary = "[Summary Not Found/Not Yet Summarized]".to_string();
        }
        out.push((score, date_of(&f), summary.trim_end().to_string()));
    }
    out
}

fn lkweight(args: &[String]) -> i32 {
    let _ = fs::create_dir_all(&cfg().config_dir);
    let wf = weight_file();
    if !wf.exists() {
        let _ = fs::write(&wf, "");
    }
    let cmd = args.get(0).map(|s| s.as_str()).unwrap_or("");
    let rest: &[String] = if args.is_empty() { &[] } else { &args[1..] };
    match cmd {
        "add" => {
            let a1 = rest.get(0).cloned().unwrap_or_default();
            let (weight, pattern) = if a1.contains('=') {
                let e = a1.find('=').unwrap();
                (a1[..e].to_string(), a1[e + 1..].to_string())
            } else {
                (a1.clone(), rest.get(1).cloned().unwrap_or_default())
            };
            let pattern = strip_quotes(&pattern);
            let wd = weight.strip_prefix('-').unwrap_or(&weight);
            if !all_digits(wd) {
                println!("{}[Error]{} Weight must be an integer.", W_MERAH, RESET);
                return 1;
            }
            if pattern.is_empty() {
                println!("{}[Error]{} Pattern cannot be empty.", W_MERAH, RESET);
                return 1;
            }
            let mut body = read_text(&wf);
            body.push_str(&format!("{}|{}\n", weight, pattern));
            let _ = write_atomic(&wf, &body);
            let col = if weight.starts_with('-') { W_MERAH } else { W_HIJAU };
            println!("{}[Added]{} {}{}{} -> {}{}{}", W_BIRU, RESET, col, weight, RESET, W_KUNING, pattern, RESET);
            println!("{}Saved to: {}{}", GREY245, wf.display(), RESET);
            0
        }
        "list" => {
            println!("{}--- Karmic Rules (Weight Contexts) ---{}", W_BIRUTUA, RESET);
            let lines = read_lines(&wf);
            if lines.is_empty() {
                println!("  {}No rules defined.{}", WHITE, RESET);
            } else {
                for (i, l) in lines.iter().enumerate() {
                    let parts: Vec<&str> = l.split('|').collect();
                    let w = parts[0].trim();
                    let wn: i64 = w.parse().unwrap_or(0);
                    let col = if wn < 0 { W_MERAH } else { W_HIJAU };
                    println!("  \x1b[36m[{}]\x1b[0m {}{:>6}\x1b[0m -> \x1b[33m{}\x1b[0m", i + 1, col, w, parts.get(1).copied().unwrap_or(""));
                }
            }
            println!("{}Config Path: {}{}", GREY245, wf.display(), RESET);
            0
        }
        "rm" | "remove" => {
            let n: usize = match rest.get(0).and_then(|s| s.parse().ok()) {
                Some(n) => n,
                None => {
                    println!("{}[Error]{} Provide line number to remove.", W_MERAH, RESET);
                    return 1;
                }
            };
            let mut lines = read_lines(&wf);
            if n >= 1 && n <= lines.len() {
                lines.remove(n - 1);
                let _ = write_lines(&wf, &lines);
            }
            println!("{}[Removed]{} Rule at line {} deleted.", W_KUNING, RESET, n);
            0
        }
        "why" => weight_why(rest.get(0).cloned().unwrap_or_default()),
        "judge" => weight_judge(rest),
        "unjudged" => {
            if read_text(&wf).is_empty() {
                println!("{}[Error]{} Weight list is empty.", W_MERAH, RESET);
                return 1;
            }
            let mut d: Vec<String> = weight_calc().into_iter().filter(|r| r.0 == 0).map(|r| r.1).collect();
            d.sort();
            print!("\x1b[2K\r");
            println!("{}| LK (LogKlerk) --- Unjudged / Karmic Neutral Days ---{}\n", W_BIRU, RESET);
            for (i, dt) in d.iter().enumerate() {
                println!("  {}[{:4}]{} [[{}]] {}(No karmic weight detected){}", GREY245, i + 1, RESET, dt, GREY245, RESET);
            }
            println!("\n  Total Unjudged Days: {}{}{}\n\n{}------------------------------------------------------------{}", W_BIRU, d.len(), RESET, GREY245, RESET);
            0
        }
        _ => {
            println!("{}Usage:{} lkweight {{add|list|rm|judge|why|unjudged}} [args]", W_KUNING, RESET);
            println!("  lkweight add 5000 \"Deep Work\"");
            println!("  lkweight judge       {}(Shows Juxtaposition of Top/Bottom 15 days){}", DIM, RESET);
            println!("  lkweight judge 30    {}(Shows Juxtaposition of Top/Bottom 30 days){}", DIM, RESET);
            println!("  lkweight judge date  {}(Renders Dynamic Axis Shifting Chart){}", DIM, RESET);
            println!("  lkweight why <date>  {}(Executes a Karmic Autopsy sorted by weight total){}", DIM, RESET);
            println!("  lkweight unjudged    {}(Lists all days with a score of exactly 0){}", DIM, RESET);
            0
        }
    }
}

fn weight_why(date_in: String) -> i32 {
    if date_in.is_empty() {
        println!("{}[Error]{} Provide a date (e.g., 'lkweight why 2026-05-14' or 'today').", W_MERAH, RESET);
        return 1;
    }
    let date = if date_in == "today" { now().date() } else { norm_date(&date_in) };
    if date.len() < 10 {
        println!("{}[LK Axiom]{} Log for [[{}]] not found in Vault.", W_KUNING, RESET, date);
        return 0;
    }
    let f = day_path(&date);
    if !f.is_file() {
        println!("{}[LK Axiom]{} Log for [[{}]] not found in Vault.", W_KUNING, RESET, date);
        return 0;
    }
    print!("{}--- Performing Karmic Autopsy for [[{}]]... ---{}\r", W_BIRU, date, RESET);
    let weights = load_weights();
    let mut hits = vec![0i64; weights.len()];
    for l in read_lines(&f) {
        let low = l.to_lowercase();
        for (i, (_, pat, _)) in weights.iter().enumerate() {
            hits[i] += count_occ(&low, pat);
        }
    }
    let mut total = 0i64;
    let mut pos: Vec<(i64, String)> = Vec::new();
    let mut neg: Vec<(i64, String)> = Vec::new();
    for (i, (w, _, orig)) in weights.iter().enumerate() {
        if hits[i] > 0 {
            let sub = hits[i] * w;
            total += sub;
            let quoted = format!("\"{}\"", orig);
            if *w > 0 {
                pos.push((sub, format!("  {}+{} {:4}x {}{:<30}{} {}(@ +{:<4}){} -> {}+{}{}", W_HIJAU, RESET, hits[i], W_BIRU, quoted, RESET, GREY245, w, RESET, W_HIJAU, sub, RESET)));
            } else {
                neg.push((sub, format!("  {}-{} {:4}x {}{:<30}{} {}(@ {:<5}){} -> {}{}{}", W_MERAH, RESET, hits[i], W_KUNING, quoted, RESET, GREY245, w, RESET, W_MERAH, sub, RESET)));
            }
        }
    }
    pos.sort_by(|a, b| a.0.cmp(&b.0));
    neg.sort_by(|a, b| a.0.abs().cmp(&b.0.abs()));
    print!("\x1b[2K\r");
    println!("{}| LK (LogKlerk) --- Karmic Autopsy : [[{}]] ---{}", W_BIRUTUA, date, RESET);
    if !pos.is_empty() {
        println!("\n  {}[ Ascending Catalysts (Positives) ]{}", W_BIRU, RESET);
        for (_, s) in &pos {
            println!("{}", s);
        }
    }
    if !neg.is_empty() {
        println!("\n  {}[ Void Pullers (Negatives) ]{}", W_MERAH, RESET);
        for (_, s) in &neg {
            println!("{}", s);
        }
    }
    if pos.is_empty() && neg.is_empty() {
        println!("\n  {}(No karmic weights detected. Absolute Neutral Day.){}", GREY245, RESET);
    }
    let (tier, col, sign) = tier_of(total);
    println!("\n{}----------------------------------------------------------------{}", GREY245, RESET);
    println!("  Net Karmic Resonance: {}{}{}{} {}({}){}", col, sign, total, RESET, GREY245, tier, RESET);
    println!("{}----------------------------------------------------------------{}", GREY245, RESET);
    0
}

fn weight_judge(rest: &[String]) -> i32 {
    if read_text(&weight_file()).is_empty() {
        println!("{}[Error]{} Weight list is empty.", W_MERAH, RESET);
        return 1;
    }
    let sub = rest.get(0).map(|s| s.as_str()).unwrap_or("");
    if sub == "today" {
        let today = now().date();
        print!("{}--- Scanning Karmic Resonance for Today ({})... ---{}\r", W_BIRU, today, RESET);
        let r = weight_calc().into_iter().find(|r| r.1 == today);
        let (score, _, summary) = match r {
            Some(x) => x,
            None => {
                println!("\x1b[2K\r{}[LK Axiom]{} No log found for today yet.", W_KUNING, RESET);
                return 0;
            }
        };
        let (tier, col, sign) = tier_of(score);
        let summary_colored = if let Some(n) = bang_at_start(&summary) {
            format!("\x1b[38;2;225;102;0m{}{} {}{}{}", &summary[..n], RESET, GREY245, trim_left_ws(&summary[n..]), RESET)
        } else {
            format!("{}{}{}", GREY245, summary, RESET)
        };
        print!("\x1b[2K\r");
        println!("{}| LK (LogKlerk) --- Today's Axiological Audit ---{}", W_BIRU, RESET);
        println!("  Date     : \x1b[38;2;255;200;0m[[{}]]{}", today, RESET);
        println!("  Summary  : {}", summary_colored);
        println!("  Karmic   : {}{}{}{} ({}){}", col, sign, score, RESET, tier, RESET);
        println!("{}---------------------------------------------------{}", GREY245, RESET);
        return 0;
    }
    if sub == "date" {
        print!("{}--- Rendering Axiological Chronology Matrix... ---{}\r", W_BIRU, RESET);
        let mut rows = weight_calc();
        rows.sort_by(|a, b| a.1.cmp(&b.1));
        print!("\x1b[2K\r");
        println!("{}| LK (LogKlerk) --- Axiological Chronology Matrix ---{}", W_BIRUTUA, RESET);
        let max_pos = rows.iter().map(|r| r.0).max().unwrap_or(0).max(0);
        let min_neg = rows.iter().map(|r| r.0).min().unwrap_or(0).min(0);
        let abs_neg = if min_neg < 0 { -min_neg } else { 0 };
        let total_range = abs_neg + max_pos;
        let total_bars = 20i64;
        let mut left_space: i64;
        let mut right_space: i64;
        if total_range == 0 {
            left_space = 10;
            right_space = 10;
        } else {
            left_space = ((abs_neg as f64 / total_range as f64) * total_bars as f64 + 0.5) as i64;
            right_space = total_bars - left_space;
            if abs_neg > 0 && left_space == 0 {
                left_space = 1;
                right_space = total_bars - 1;
            }
            if max_pos > 0 && right_space == 0 {
                right_space = 1;
                left_space = total_bars - 1;
            }
        }
        for (sc, dt, summary) in &rows {
            let (_, col, _) = tier_of(*sc);
            let left_side: String;
            let right_side: String;
            let sign: &str;
            if *sc < 0 {
                let abs_sc = -*sc;
                let mut bl = ((abs_sc as f64 / abs_neg as f64) * left_space as f64 + 0.5) as i64;
                if bl == 0 && abs_sc > 0 {
                    bl = 1;
                }
                let mut l = String::new();
                for x in 1..=left_space {
                    l.push_str(if x <= left_space - bl { "·" } else { "■" });
                }
                left_side = format!("{}{}{}", col, l, RESET);
                right_side = format!("{}{}{}", GREY245, "·".repeat(right_space as usize), RESET);
                sign = "";
            } else if *sc > 0 {
                left_side = format!("{}{}{}", GREY245, "·".repeat(left_space as usize), RESET);
                let mut bl = ((*sc as f64 / max_pos as f64) * right_space as f64 + 0.5) as i64;
                if bl == 0 {
                    bl = 1;
                }
                let mut r = String::new();
                for x in 1..=right_space {
                    r.push_str(if x <= bl { "■" } else { "·" });
                }
                right_side = format!("{}{}{}", col, r, RESET);
                sign = "+";
            } else {
                left_side = format!("{}{}{}", GREY245, "·".repeat(left_space as usize), RESET);
                right_side = format!("{}{}{}", GREY245, "·".repeat(right_space as usize), RESET);
                sign = " ";
            }
            let (colored, raw_len) = fmt_summary(summary, 38, W_BIRUTUA, W_MERAH);
            let pad = if raw_len < 38 { spaces(38 - raw_len) } else { String::new() };
            println!(
                "{}{}{} {}{} │ {}│{} │ {}{}{:<6}{}",
                "\x1b[38;2;255;200;0m", dt, RESET, colored, pad, left_side, right_side, col, sign, sc, RESET
            );
        }
        return 0;
    }
    let limit: usize = if sub == "all" { 999999 } else { rest.get(0).and_then(|s| s.parse().ok()).unwrap_or(15) };
    print!("{}--- Rendering Axiological Juxtaposition... ---{}\r", W_BIRU, RESET);
    let raw = weight_calc();
    let mut best: Vec<&(i64, String, String)> = raw.iter().filter(|r| r.0 > 0).collect();
    best.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)));
    best.truncate(limit);
    let mut worst: Vec<&(i64, String, String)> = raw.iter().filter(|r| r.0 < 0).collect();
    worst.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    worst.truncate(limit);
    let lbl = if limit >= 999999 { "(ALL RECORDED DAYS)".to_string() } else { format!("(TOP {} DAYS)", limit) };
    print!("\x1b[2K\r");
    println!("{}  [ ASCENDED DAYS {} ]  {}||{}  [ CATASTROPHIC DAYS {} ]{}", W_BIRUTUA, lbl, GREY245, W_MERAHTUA, lbl, RESET);
    let sep = "--------------------------------------------------------------------------------------";
    println!("{}{}{}", GREY245, sep, RESET);
    let mut max_lines = best.len().max(worst.len());
    if limit < max_lines {
        max_lines = limit;
    }
    for i in 0..max_lines {
        let left = if let Some(b) = best.get(i) {
            let lc = if b.0 >= 5000 { W_BIRUTUA } else if b.0 >= 1000 { W_BIRU } else { W_HIJAU };
            format!("{}{:4}.{} [[{}]] {}+{:<6}{}", GREY245, i + 1, RESET, b.1, lc, b.0, RESET)
        } else {
            spaces(44)
        };
        let right = if let Some(w) = worst.get(i) {
            let rc = if w.0 <= -5000 { W_MERAHTUA } else if w.0 <= -1000 { W_MERAH } else { W_KUNING };
            format!("{}{:4}.{} [[{}]] {}{:<6}{}", GREY245, i + 1, RESET, w.1, rc, w.0, RESET)
        } else {
            String::new()
        };
        println!("{} {}||{} {}", pad_bytes(&left, 57), GREY245, RESET, right);
    }
    println!("{}{}{}", GREY245, sep, RESET);
    0
}

// ============================================================================
// lkdistraction
// ============================================================================
fn lkdistraction(args: &[String]) -> i32 {
    let _ = fs::create_dir_all(&cfg().config_dir);
    let df = cfg().config_dir.join("distractions.list");
    if !df.exists() {
        let _ = fs::write(&df, "");
    }
    let cmd = args.get(0).map(|s| s.as_str()).unwrap_or("");
    let rest: &[String] = if args.is_empty() { &[] } else { &args[1..] };
    match cmd {
        "add" => {
            let p = rest.get(0).cloned().unwrap_or_default();
            if p.is_empty() {
                println!("{}[Error]{} Please provide a distraction pattern (e.g., \"Scrolling on Social Media\").", B_RED, RESET);
                return 1;
            }
            let mut body = read_text(&df);
            body.push_str(&format!("{}\n", p));
            let _ = write_atomic(&df, &body);
            println!("{}[Added]{} Cognitive hijack pattern: {}{}{}", GREEN, RESET, YELLOW, p, RESET);
            0
        }
        "list" => {
            println!("\x1b[36m--- Known Cognitive Hijackers (Distraction Patterns) ---{}", RESET);
            let lines = read_lines(&df);
            if lines.is_empty() {
                println!("  {}No distraction patterns defined yet.{}", WHITE, RESET);
            }
            for (i, l) in lines.iter().enumerate() {
                println!("  \x1b[35m[{}]{} {}", i + 1, RESET, l);
            }
            0
        }
        "rm" | "remove" => {
            let n: usize = match rest.get(0).and_then(|s| s.parse().ok()) {
                Some(n) => n,
                None => {
                    println!("{}[Error]{} Provide line number to remove.", B_RED, RESET);
                    return 1;
                }
            };
            let mut lines = read_lines(&df);
            if n >= 1 && n <= lines.len() {
                lines.remove(n - 1);
                let _ = write_lines(&df, &lines);
            }
            println!("{}[Removed]{} Pattern at line {} deleted.", YELLOW, RESET, n);
            0
        }
        "track" => {
            if !cfg().lk_dir.is_dir() {
                println!("{}[Error]{} LK Vault not found.", B_RED, RESET);
                return 1;
            }
            let pats: Vec<String> = read_lines(&df).into_iter().filter(|l| !l.is_empty()).collect();
            if pats.is_empty() {
                println!("{}[Error]{} Distraction list is empty. Add patterns using 'lkdistraction add'.", B_RED, RESET);
                return 1;
            }
            print!("\x1b[36m--- Initializing Neural Distraction Scan... ---{}\r", RESET);
            let sc = match rest.get(0).and_then(|a| parse_scope(a)) {
                Some((s @ Sc::Year(_), _)) | Some((s @ Sc::Month(_), _)) => s,
                _ => Sc::All,
            };
            let lows: Vec<String> = pats.iter().map(|p| p.to_lowercase()).collect();
            let (mut total, mut focus, mut dis) = (0usize, 0usize, 0usize);
            let mut hijack: HashMap<String, usize> = HashMap::new();
            let mut vuln: HashMap<String, usize> = HashMap::new();
            for f in scope_files(&sc) {
                for line in read_lines(&f) {
                    let b = line.as_bytes();
                    let mut i = 0;
                    while i < b.len() && b[i] == b' ' {
                        i += 1;
                    }
                    if i + 2 <= b.len() && b[i] == b'-' && b[i + 1] == b' ' && hhmmss_at(b, i + 2) && line[i + 10..].starts_with(" - ") {
                        let hr = line[i + 2..i + 4].to_string();
                        total += 1;
                        let low = line.to_lowercase();
                        let mut hit = false;
                        for (k, lp) in lows.iter().enumerate() {
                            if low.contains(lp.as_str()) {
                                *hijack.entry(pats[k].clone()).or_insert(0) += 1;
                                *vuln.entry(hr.clone()).or_insert(0) += 1;
                                hit = true;
                                dis += 1;
                                break;
                            }
                        }
                        if !hit {
                            focus += 1;
                        }
                    }
                }
            }
            print!("\x1b[2K\r\n");
            println!("\x1b[36m| LK (LogKlerk) --- Neural Distraction Analytics ---{}", RESET);
            if total == 0 {
                println!("  {}No logs found to analyze.{}", RED, RESET);
                return 0;
            }
            let dp = dis * 100 / total;
            let fp = 100 - dp;
            println!("  \x1b[35m[ 1. The Dopamine Leak Ratio ]{}", RESET);
            println!("    Total Timestamps Scanned : {}{}{} logs", WHITE, total, RESET);
            println!("    Focus / Productive State : {}{}{} logs ({}{}%{})", GREEN, focus, RESET, GREEN, fp, RESET);
            println!("    Cognitive Hijack State   : {}{}{} logs ({}{}%{})\n", B_RED, dis, RESET, B_RED, dp, RESET);
            println!("  \x1b[35m[ 2. Executive Function Vulnerability (By Hour) ]{}", RESET);
            let mut vv: Vec<(&String, &usize)> = vuln.iter().collect();
            vv.sort_by(|a, b| b.1.cmp(a.1).then(a.0.cmp(b.0)));
            if let Some((h, c)) = vv.first() {
                println!("    Peak Distraction Hour : {}{}:00{} ({}{} incidents{})", B_RED, h, RESET, YELLOW, c, RESET);
                println!("    Timeframe Persona     : {}This is when your willpower battery is depleted.{}", WHITE, RESET);
            } else {
                println!("    {}No vulnerability pattern detected.{}", GREEN, RESET);
            }
            println!();
            println!("  \x1b[35m[ 3. Dominant Hijackers (Top 5 Distractions) ]{}", RESET);
            let mut hv: Vec<(&String, &usize)> = hijack.iter().collect();
            hv.sort_by(|a, b| b.1.cmp(a.1).then(a.0.cmp(b.0)));
            for (p, c) in hv.iter().take(5) {
                println!("    ├── {}{}{} : {}{}{} occurrences", RED, p, RESET, YELLOW, c, RESET);
            }
            println!("\n\x1b[36m------------------------------------------------------------{}", RESET);
            0
        }
        _ => {
            println!("{}Usage:{} lkdistraction {{add|list|rm|track}} [args]", YELLOW, RESET);
            0
        }
    }
}

// ============================================================================
// lkyaml
// ============================================================================
fn lkyaml(args: &[String]) -> i32 {
    if !vault_check() {
        return 1;
    }
    let mut action = "help";
    let mut t_key = String::new();
    let mut sc = Sc::All;
    let mut scope = "Global Lifetime".to_string();
    let n = now();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        match a {
            "keys" | "k" => action = "keys",
            "values" | "v" | "val" => {
                action = "values";
                t_key = args.get(i + 1).cloned().unwrap_or_default();
                i += 1;
            }
            "timeline" | "t" | "time" => {
                action = "timeline";
                t_key = args.get(i + 1).cloned().unwrap_or_default();
                i += 1;
            }
            "dump" | "d" => action = "dump",
            "m" | "month" | "-m" | "--month" => {
                sc = Sc::Month(n.month());
                scope = format!("Monthly Scope ({})", n.month());
            }
            other => {
                if let Some((s, l)) = parse_scope(other) {
                    if !matches!(s, Sc::YearRange(_, _) | Sc::DateRange(_, _)) {
                        sc = s;
                        scope = l;
                    }
                }
            }
        }
        i += 1;
    }
    if action == "help" {
        println!("{}| LK (LogKlerk) --- YAML Telemetry Analyzer ---{}", HEADER_ORG, RESET);
        println!(" Usage: lkyaml [TIME] [ACTION] [ARGS]\n");
        println!(" Actions:");
        println!("   {}keys{}             : Rank all unique YAML keys.", LIME, RESET);
        println!("   {}values [Key]{}     : Rank all unique values for a specific Key.", CYAN, RESET);
        println!("   {}timeline [Key]{}   : Show chronological state transitions for a Key.", ORANGE, RESET);
        println!("   {}dump{}             : Raw extraction of all YAML blocks.\n", CYAN, RESET);
        return 0;
    }
    print!("{}--- Analyzing YAML Telemetry for {}... ---{}\r", CYAN, scope, RESET);
    print!("\x1b[2K\r");
    if action == "keys" {
        println!("{}| LK (LogKlerk) --- YAML Keys Frequency ---{}", HEADER_ORG, RESET);
        println!("  {}Scope: {}{}\n", GREY, scope, RESET);
    } else if action == "values" {
        println!("{}| LK (LogKlerk) --- YAML Values Analyzer ---{}", HEADER_ORG, RESET);
        println!("  {}Scope: {} | Key: [{}]{}\n", GREY, scope, t_key, RESET);
    } else if action == "timeline" {
        println!("{}| LK (LogKlerk) --- YAML Chronological Timeline ---{}", HEADER_ORG, RESET);
        println!("  {}Scope: {} | Key: [{}]{}\n", GREY, scope, t_key, RESET);
    }
    let mut key_arr: HashMap<String, usize> = HashMap::new();
    let mut val_arr: HashMap<String, usize> = HashMap::new();
    let (mut prev_val, mut start_dt, mut end_dt) = (String::new(), String::new(), String::new());
    let mut display_key = t_key.clone();
    let print_range = |prev: &str, s: &str, e: &str, dk: &str| {
        if !prev.is_empty() {
            let ds = if s == e {
                format!("{}[[{}]]{}                  ", AMBER, s, RESET)
            } else {
                format!("{}[[{}]]{}{} -> {}{}[[{}]]{}", AMBER, s, RESET, GREY, RESET, AMBER, e, RESET)
            };
            println!("    {} | {}{}:{} {}\"{}\"{}", ds, ORANGE, dk, RESET, CYAN, prev, RESET);
        }
    };
    for f in scope_files(&sc) {
        let dt = date_name(&f);
        let mut in_yaml = false;
        for line in read_lines(&f) {
            if is_yaml_fence(&line) {
                if !in_yaml {
                    in_yaml = true;
                    continue;
                } else {
                    if action == "dump" {
                        println!("---");
                    }
                    break;
                }
            }
            if !in_yaml {
                continue;
            }
            let colon = match line.find(':') {
                Some(c) if c > 0 => c,
                _ => continue,
            };
            if action == "dump" {
                println!("{}{}{}", CYAN, line, RESET);
                continue;
            }
            let k = line[..colon].to_string();
            let v = line[colon + 1..]
                .trim_start_matches(|c: char| c == '"' || c == '\'' || c == ' ' || c == '\t')
                .trim_end_matches(|c: char| c == '"' || c == '\'' || c == ' ' || c == '\t')
                .to_string();
            if action == "keys" {
                *key_arr.entry(k).or_insert(0) += 1;
            } else if action == "values" && k.to_lowercase() == t_key.to_lowercase() {
                *val_arr.entry(v).or_insert(0) += 1;
            } else if action == "timeline" && k.to_lowercase() == t_key.to_lowercase() {
                display_key = k;
                if !prev_val.is_empty() && v != prev_val {
                    print_range(&prev_val, &start_dt, &end_dt, &display_key);
                    start_dt = dt.clone();
                } else if prev_val.is_empty() {
                    start_dt = dt.clone();
                }
                prev_val = v;
                end_dt = dt.clone();
            }
        }
    }
    if action == "keys" {
        for (c, name) in rank_sorted(&key_arr) {
            println!("    {}{}{} ({}{}x{})", LIME, name, RESET, GREY, c, RESET);
        }
    } else if action == "values" {
        let v = rank_sorted(&val_arr);
        for (c, name) in &v {
            println!("    {}{}{} ({}{}x{})", CYAN, name, RESET, GREY, c, RESET);
        }
        if v.is_empty() {
            println!("    {}No values found for key: {}{}", GREY, t_key, RESET);
        }
    } else if action == "timeline" && !prev_val.is_empty() {
        print_range(&prev_val, &start_dt, &end_dt, &display_key);
    }
    println!("{}-------------------------------------------{}", HEADER_ORG, RESET);
    0
}

// ============================================================================
// lkdiversity — lexical diversity
// ============================================================================
fn month_range_files(y1: i64, m1: i64, y2: i64, m2: i64) -> Vec<PathBuf> {
    let mut v = Vec::new();
    let mut cur = y1 * 12 + m1;
    let end = y2 * 12 + m2;
    while cur <= end && cur - (y1 * 12 + m1) < 6000 {
        let vy = (cur - 1) / 12;
        let vm = cur - vy * 12;
        v.extend(scope_files(&Sc::Month(format!("{:04}-{:02}", vy, vm))));
        cur += 1;
    }
    v
}

fn lkdiversity(args: &[String]) -> i32 {
    if !vault_check() {
        return 1;
    }
    let min_words = 50usize;
    let mut label = "Global Lifetime".to_string();
    let mut metric = "rttr".to_string();
    let mut order = "asc".to_string();
    let mut files: Vec<PathBuf> = Vec::new();
    let mut scoped = false;
    for a in args {
        let s = a.as_str();
        let b = s.as_bytes();
        match s {
            "asc" | "desc" => order = s.to_string(),
            "date" | "ttr" | "rttr" | "uniq" => metric = s.to_string(),
            _ if s.len() == 14 && &s[6..8] == "--" && all_digits(&s[..6]) && all_digits(&s[8..]) => {
                let (y1, m1): (i64, i64) = (s[..4].parse().unwrap_or(0), s[4..6].parse().unwrap_or(1));
                let (y2, m2): (i64, i64) = (s[8..12].parse().unwrap_or(0), s[12..14].parse().unwrap_or(1));
                label = format!("{:04}-{:02} to {:04}-{:02}", y1, m1, y2, m2);
                files.extend(month_range_files(y1, m1, y2, m2));
                scoped = true;
            }
            _ if (s.len() == 9 && b[4] == b'-' && all_digits(&s[..4]) && all_digits(&s[5..]))
                || (s.len() == 10 && &s[4..6] == "--" && all_digits(&s[..4]) && all_digits(&s[6..])) =>
            {
                let y1: i64 = s[..4].parse().unwrap_or(0);
                let y2: i64 = s[s.len() - 4..].parse().unwrap_or(0);
                label = format!("{} to {}", y1, y2);
                files.extend(scope_files(&Sc::YearRange(y1, y2)));
                scoped = true;
            }
            _ if (s.len() == 6 && all_digits(s)) || is_month_str(s) => {
                let (sc, l) = parse_scope(s).unwrap();
                let l2 = l.trim_start_matches("Monthly Scope (").trim_end_matches(')').to_string();
                label = if label == "Global Lifetime" { l2 } else { format!("{}, {}", label, l2) };
                files.extend(scope_files(&sc));
                scoped = true;
            }
            _ if s.len() == 4 && all_digits(s) => {
                label = if label == "Global Lifetime" { s.to_string() } else { format!("{}, {}", label, s) };
                files.extend(scope_files(&Sc::Year(s.to_string())));
                scoped = true;
            }
            _ => {
                println!("{}[Error]{} Argument '{}' unknown.", RED, RESET, s);
                return 1;
            }
        }
    }
    if !scoped {
        files = scope_files(&Sc::All);
    }
    files.sort();
    files.dedup();
    if files.is_empty() {
        println!("{}[Error]{} No data matching '{}' found.", RED, RESET, label);
        return 1;
    }
    println!(
        "{}| LK Analytics --- Lexical Diversity [{}] via {} ({}) ---{}",
        ORANGE, label, metric, order, RESET
    );
    // (score, date, uniq, total, ttr, rttr)
    let mut rows: Vec<(f64, String, usize, usize, f64, f64)> = Vec::new();
    for f in &files {
        let mut total = 0usize;
        let mut uniq: HashSet<String> = HashSet::new();
        for line in read_lines(f) {
            let l = remove_all_delim(&line, "![", "]!", false);
            let l = remove_all_delim(&l, "[[", "]]", false);
            let l: String = l
                .chars()
                .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { ' ' })
                .collect();
            for w in l.split_whitespace() {
                total += 1;
                uniq.insert(w.to_string());
            }
        }
        if total >= min_words {
            let uc = uniq.len();
            let ttr = uc as f64 / total as f64 * 100.0;
            let rttr = uc as f64 / (total as f64).sqrt();
            let score = match metric.as_str() {
                "ttr" => ttr,
                "uniq" => uc as f64,
                _ => rttr,
            };
            rows.push((score, date_of(f), uc, total, ttr, rttr));
        }
    }
    let key = |r: &(f64, String, usize, usize, f64, f64)| format!("{:09.4}|{}|{}|{}|{:.2}|{:.2}", r.0, r.1, r.2, r.3, r.4, r.5);
    if metric == "date" {
        rows.sort_by(|a, b| a.1.cmp(&b.1).then(key(a).cmp(&key(b))));
        if order != "asc" {
            rows.reverse();
        }
    } else {
        rows.sort_by(|a, b| {
            let fa = format!("{:09.4}", a.0).parse::<f64>().unwrap_or(0.0);
            let fb = format!("{:09.4}", b.0).parse::<f64>().unwrap_or(0.0);
            fa.partial_cmp(&fb).unwrap_or(std::cmp::Ordering::Equal).then(key(a).cmp(&key(b)))
        });
        if order != "asc" {
            rows.reverse();
        }
    }
    println!("  {}Filter : Min {} words. Metric: {}{}", GREY, min_words, metric.to_uppercase(), RESET);
    match metric.as_str() {
        "rttr" => println!("  {}Desc   : Root TTR (Guiraud's Index). Best balance of volume and diversity.{}", GREY, RESET),
        "ttr" => println!("  {}Desc   : Raw Type-Token Ratio. Favors extremely short, dense logs.{}", GREY, RESET),
        "uniq" => println!("  {}Desc   : Raw Unique Words. Favors extremely long logs.{}", GREY, RESET),
        _ => println!("  {}Desc   : Chronological view of Cognitive Expansion.{}", GREY, RESET),
    }
    println!();
    println!(
        "  {}[■]{} Ascended Range | {}[■]{} Healthy Range | {}[■]{} Focus Range | {}[■]{} Loop/Echo Chamber\n",
        MAGENTA, RESET, CYAN, RESET, LIME, RESET, ORANGE, RESET
    );
    let mut max_score = 0.0f64;
    for r in &rows {
        if metric == "date" {
            if r.5 > max_score {
                max_score = r.5;
            }
        } else {
            max_score = r.0; // original behavior: value of the last row
        }
    }
    for (i, r) in rows.iter().enumerate() {
        let (_, date_str, uq, total, ttr, rttr) = r;
        let color = if *rttr >= 25.0 {
            MAGENTA
        } else if *rttr >= 18.0 {
            CYAN
        } else if *rttr >= 12.0 {
            LIME
        } else {
            ORANGE
        };
        let mut filled = if max_score > 0.0 { ((rttr / max_score) * 10.0 + 0.5) as usize } else { 0 };
        if filled == 0 && *rttr > 0.0 {
            filled = 1;
        }
        if filled > 10 {
            filled = 10;
        }
        let bar = bar_str(filled, 10, "■", "·");
        let (disp, suffix) = match metric.as_str() {
            "ttr" => (format!("{:5.2}", ttr), "%   "),
            "uniq" => (format!("{:5}", uq), "Wrds"),
            _ => (format!("{:5.2}", rttr), "Idx "),
        };
        println!(
            " {}{:03}.{} {}[[{}]]{} │ {}[{}]{} {}{} {}{} │ {}{:4} Uniq{} / {}{:4} Totl{} │ {}(RTTR: {:05.2}){}",
            GREY, i + 1, RESET, AMBER, date_str, RESET, color, bar, RESET, color, disp, suffix, RESET, CYAN, uq, RESET, GREY, total, RESET, GREY, rttr, RESET
        );
    }
    0
}

// ============================================================================
// lkword — keyword frequency
// ============================================================================
fn tokens_lower(s: &str) -> Vec<String> {
    let t: String = s
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { ' ' })
        .collect();
    t.split_whitespace().map(|x| x.to_string()).collect()
}

fn lkword(args: &[String]) -> i32 {
    if args.is_empty() {
        println!("{}| LK Analytics --- Lexical Keyword Frequency ---{}", ORANGE, RESET);
        println!("Usage: lkword [time_scope] [metric] <keyword>\n");
        println!("{}Time Scope Examples:{}", CYAN, RESET);
        println!("  lkword rust                  {}(Global Lifetime){}", GREY, RESET);
        println!("  lkword date rust             {}(Chronological Timeline){}", GREY, RESET);
        println!("  lkword today context vi      {}(Context of 'vi' strictly for today){}", GREY, RESET);
        println!("  lkword 2026-05-14 vi         {}(Stats for a specific day){}", GREY, RESET);
        return 0;
    }
    let mut sc = Sc::All;
    let mut label = "Global Lifetime".to_string();
    let mut metric = "rank";
    let mut kw = String::new();
    for a in args {
        let s = a.as_str();
        if s == "date" || s == "context" {
            metric = if s == "date" { "date" } else { "context" };
        } else if s == "today" {
            let d = now().date();
            label = format!("Today ({})", d);
            sc = Sc::Day(d);
        } else if s.len() == 13 && s.as_bytes()[6] == b'-' && all_digits(&s[..6]) && all_digits(&s[7..]) {
            let (y1, m1): (i64, i64) = (s[..4].parse().unwrap_or(0), s[4..6].parse().unwrap_or(1));
            let (y2, m2): (i64, i64) = (s[7..11].parse().unwrap_or(0), s[11..13].parse().unwrap_or(1));
            label = format!("{:04}-{:02} to {:04}-{:02}", y1, m1, y2, m2);
            // built as a union of months; stored as a DateRange
            let last = days_in_month(y2, m2);
            sc = Sc::DateRange(format!("{:04}-{:02}-01", y1, m1), format!("{:04}-{:02}-{:02}", y2, m2, last));
        } else if let Some((s2, l2)) = parse_scope(s).filter(|(x, _)| !matches!(x, Sc::DateRange(_, _))) {
            label = match &s2 {
                Sc::Year(y) => y.clone(),
                Sc::Month(m) => m.clone(),
                Sc::Day(d) => d.clone(),
                Sc::YearRange(_, _) => s.to_string(),
                _ => l2,
            };
            sc = s2;
        } else if kw.is_empty() {
            kw = s.to_string();
        } else {
            kw = format!("{} {}", kw, s);
        }
    }
    if kw.is_empty() {
        println!("{}[Error]{} Keyword is required. See 'lkword' for help.", RED, RESET);
        return 1;
    }
    if !vault_check() {
        return 1;
    }
    let files = scope_files(&sc);
    let target = kw.to_lowercase();
    if metric == "context" {
        println!("{}--- Retrieving Exact Standalone Context for '{}' [{}]... ---{}", CYAN, kw, label, RESET);
        for f in &files {
            let date = date_of(f);
            for l in read_lines(f) {
                if tokens_lower(&l).iter().any(|w| *w == target) {
                    if let Some((ts, msg)) = log_ts(&l) {
                        println!(
                            "\x1b[38;2;255;200;0m{}{} │ \x1b[36m{}{} │ {}{}{}",
                            date, RESET, ts, RESET, GREY245, msg, RESET
                        );
                    }
                }
            }
        }
        println!("{}------------------------------------------------------------------{}", CYAN, RESET);
        return 0;
    }
    println!("{}| LK Analytics --- Lexical Keyword Matrix [{}] ---{}", ORANGE, label, RESET);
    // (count, date, total_words, summary)
    let mut rows: Vec<(usize, String, usize, String)> = Vec::new();
    for f in &files {
        let mut mc = 0usize;
        let mut tw = 0usize;
        let mut summary = String::new();
        for line in read_lines(f) {
            if summary.is_empty() {
                if let Some((e, _)) = sum_head(&line, false) {
                    let b = line.as_bytes();
                    let mut i = skip_ws(b, e);
                    if i < b.len() && (b[i] == b'-' || b[i] == b':') {
                        i += 1;
                    }
                    i = skip_ws(b, i);
                    summary = line[i..].to_string();
                }
            }
            let toks = tokens_lower(&line);
            tw += toks.len();
            mc += toks.iter().filter(|w| **w == target).count();
        }
        if summary.is_empty() {
            summary = "[No Summary]".to_string();
        }
        if mc > 0 {
            rows.push((mc, date_of(f), tw, summary.trim_end().to_string()));
        }
    }
    if metric == "date" {
        rows.sort_by(|a, b| a.1.cmp(&b.1));
    } else {
        rows.sort_by(|a, b| {
            let ka = format!("{}|{}|{}|{}", a.0, a.1, a.2, a.3);
            let kb = format!("{}|{}|{}|{}", b.0, b.1, b.2, b.3);
            b.0.cmp(&a.0).then(kb.cmp(&ka))
        });
    }
    println!("  {}Keyword : '{}'{}", GREY, kw, RESET);
    if metric == "date" {
        println!("  {}Order   : Chronological Timeline{}", GREY, RESET);
    } else {
        println!("  {}Order   : Frequency Ranking (Highest Frequency at the Bottom){}", GREY, RESET);
    }
    println!();
    if rows.is_empty() {
        println!("  \x1b[31m[No Matches]\x1b[0m Keyword '{}' not found in this scope.", kw);
        return 0;
    }
    let max_count = if metric == "date" { rows.iter().map(|r| r.0).max().unwrap_or(0) } else { rows[0].0 };
    let total_hits: usize = rows.iter().map(|r| r.0).sum();
    let total_ranks = rows.len();
    for idx in 1..=total_ranks {
        let i = if metric == "rank" { total_ranks - idx } else { idx - 1 };
        let (count, dt, tw, sm) = &rows[i];
        let (colored, raw_len) = fmt_summary(sm, 38, MAGENTA, RED);
        let pad = if raw_len < 38 { spaces(38 - raw_len) } else { String::new() };
        let mut filled = if max_count > 0 { ((*count as f64 / max_count as f64) * 8.0 + 0.5) as usize } else { 0 };
        if filled == 0 && *count > 0 {
            filled = 1;
        }
        let bar = bar_str(filled, 8, "■", "·");
        println!(
            " {}{}{} {}{} │ {}{}{} │ {}{:4}{} uses │ {}{:5}{} words",
            AMBER, dt, RESET, colored, pad, CYAN, bar, RESET, ORANGE, count, RESET, LIME, tw, RESET
        );
    }
    println!("\n{}  Total Accumulation: {}{} mentions{} across {}{} days.{}", ORANGE, CYAN, total_hits, RESET, CYAN, total_ranks, RESET);
    0
}

// ============================================================================
// lkwords — semantic categorization matrix
// ============================================================================
fn lkwords(args: &[String]) -> i32 {
    let dir = cfg().config_dir.join("lkwords");
    let _ = fs::create_dir_all(&dir);
    let ign_f = dir.join("ignore.list");
    let cat_f = dir.join("categories.list");
    let map_f = dir.join("mappings.list");
    for f in [&ign_f, &cat_f, &map_f] {
        if !f.exists() {
            let _ = fs::write(f, "");
        }
    }
    let cmd = args.get(0).map(|s| s.as_str()).unwrap_or("");
    let rest: &[String] = if args.is_empty() { &[] } else { &args[1..] };
    match cmd {
        "add" => {
            if rest.get(0).map(|s| s.as_str()) == Some("category") {
                let name = rest.get(1).cloned().unwrap_or_default();
                if name.is_empty() {
                    println!("{}[Error]{} Provide a category name (e.g., 'lkwords add category verbs').", B_RED, RESET);
                    return 1;
                }
                let mut lines = read_lines(&cat_f);
                if lines.contains(&name) {
                    println!("{}[Notice]{} Category '{}' already exists.", YELLOW, RESET, name);
                } else {
                    lines.push(name.clone());
                    let _ = write_lines(&cat_f, &lines);
                    println!("{}[Added]{} Semantic Category \x1b[35m[{}]{} registered.", "\x1b[36m", RESET, name, RESET);
                }
            } else {
                println!("{}[Error]{} Usage: lkwords add category <name>", B_RED, RESET);
            }
            0
        }
        "set" => {
            if rest.len() < 2 {
                println!("{}[Error]{} Usage: lkwords set <word1> [word2...] <category>", B_RED, RESET);
                return 1;
            }
            let cat = rest[rest.len() - 1].clone();
            let mut lines = read_lines(&map_f);
            let mut mapped = String::new();
            for w in &rest[..rest.len() - 1] {
                let wl = w.to_lowercase();
                let pre = format!("{}|", wl);
                lines.retain(|l| !l.starts_with(&pre));
                lines.push(format!("{}|{}", wl, cat));
                mapped.push(' ');
                mapped.push_str(&wl);
            }
            let _ = write_lines(&map_f, &lines);
            println!("{}[Mapped]{} Words\x1b[36m{}{} assigned to \x1b[35m[{}]{}.", GREEN, RESET, mapped, RESET, cat, RESET);
            0
        }
        "ignore" => {
            if rest.is_empty() {
                println!("{}[Error]{} Provide words to ignore (e.g., 'lkwords ignore the and of').", B_RED, RESET);
                return 1;
            }
            let mut lines = read_lines(&ign_f);
            let mut added = String::new();
            for w in rest {
                let wl = w.to_lowercase();
                if !lines.contains(&wl) {
                    lines.push(wl.clone());
                    added.push(' ');
                    added.push_str(&wl);
                }
            }
            if !added.is_empty() {
                let _ = write_lines(&ign_f, &lines);
                println!("\x1b[36m[Ignored]{} Words{}{}{} added to Stopwords filter.", RESET, GREY245, added, RESET);
            } else {
                println!("{}[Notice]{} Words already ignored.", YELLOW, RESET);
            }
            0
        }
        "analyze" => {
            let limit: usize = rest.get(0).and_then(|s| s.parse().ok()).unwrap_or(25);
            print!("\x1b[36m--- Extracting & Categorizing Biological Lexicon... ---{}\r", RESET);
            let mut ignored: HashSet<String> = read_lines(&ign_f).into_iter().filter(|w| !w.is_empty()).map(|w| w.to_lowercase()).collect();
            for s in "lkdistraction lksort lkweight lkwords logklerk lki lkc lkv lkrank".split(' ') {
                ignored.insert(s.to_string());
            }
            let mut mapping: HashMap<String, String> = HashMap::new();
            for l in read_lines(&map_f) {
                if !l.is_empty() {
                    let p: Vec<&str> = l.split('|').collect();
                    mapping.insert(p[0].to_string(), p.get(1).copied().unwrap_or("").to_string());
                }
            }
            let mut freq: HashMap<String, usize> = HashMap::new();
            for f in scope_files(&Sc::All) {
                for line in read_lines(&f) {
                    let t = trim_left_ws(&line);
                    if t.starts_with("- #") {
                        let after = trim_left_ws(&t[3..]);
                        if after.starts_with("[[") {
                            continue;
                        }
                    }
                    if t.starts_with("created:") {
                        continue;
                    }
                    if t.starts_with("- #") {
                        let tb = t.as_bytes();
                        let mut i = 3;
                        if i < tb.len() && tb[i] == b'#' {
                            i += 1;
                        }
                        if i < tb.len() && tb[i] == b' ' && hh00_at(tb, i + 1) {
                            continue;
                        }
                    }
                    let mut text = line.clone();
                    if let Some((_, msg)) = log_ts(&line) {
                        text = msg;
                        if let Some((0, e)) = match_delim(&text, 0, "[[", "]] >> ") {
                            text = text[e..].to_string();
                        } else if let Some((0, e)) = match_delim(&text, 0, "[", "] >> ") {
                            text = text[e..].to_string();
                        }
                    }
                    for w in tokens_lower(&text) {
                        if w.len() > 1 && !all_digits(&w) && !ignored.contains(&w) {
                            *freq.entry(w).or_insert(0) += 1;
                        }
                    }
                }
            }
            let mut rows: Vec<(String, usize, String)> = freq
                .into_iter()
                .map(|(w, c)| {
                    let cat = mapping.get(&w).cloned().filter(|x| !x.is_empty()).unwrap_or_else(|| "Unmapped".to_string());
                    (cat, c, w)
                })
                .collect();
            rows.sort_by(|a, b| {
                a.0.cmp(&b.0).then(b.1.cmp(&a.1)).then_with(|| {
                    format!("{}|{}|{}", a.0, a.1, a.2).cmp(&format!("{}|{}|{}", b.0, b.1, b.2))
                })
            });
            print!("\x1b[2K\r");
            println!("\x1b[35m| LK (LogKlerk) --- Semantic Categorization Matrix (Top {}) ---{}", limit, RESET);
            let mut cats: Vec<String> = read_lines(&cat_f).into_iter().filter(|c| !c.is_empty()).collect();
            cats.push("Unmapped".to_string());
            let known: HashSet<String> = cats.iter().cloned().collect();
            let col_width = 24usize;
            let mut count: HashMap<String, usize> = HashMap::new();
            let mut matrix: HashMap<(String, usize), String> = HashMap::new();
            let mut max_row = 0usize;
            for (cat, freq, word) in &rows {
                if known.contains(cat) {
                    let c = count.entry(cat.clone()).or_insert(0);
                    *c += 1;
                    if *c <= limit {
                        let val = format!("{} ({}x)", word, freq);
                        let pad = col_width.saturating_sub(val.chars().count());
                        matrix.insert(
                            (cat.clone(), *c),
                            format!("\x1b[36m{}{} {}({}x){}{}", word, RESET, "\x1b[38;2;225;102;0m", freq, RESET, spaces(pad)),
                        );
                        if *c > max_row {
                            max_row = *c;
                        }
                    }
                }
            }
            let mut hdr_s = "  ".to_string();
            let mut sep = "  ".to_string();
            for c in &cats {
                let pad = col_width.saturating_sub(c.chars().count());
                hdr_s.push_str(&format!("\x1b[35m{}{}{} │ ", c, RESET, spaces(pad)));
                sep.push_str(&format!("{}{}─┼─{}", GREY245, "─".repeat(col_width), RESET));
            }
            println!("{}", hdr_s);
            println!("{}", sep);
            for r in 1..=max_row {
                let mut row = "  ".to_string();
                for c in &cats {
                    let val = matrix.get(&(c.clone(), r)).cloned().unwrap_or_else(|| spaces(col_width));
                    row.push_str(&format!("{} {}│{} ", val, GREY245, RESET));
                }
                println!("{}", row);
            }
            let mut bot = "  ".to_string();
            for _ in &cats {
                bot.push_str(&format!("{}{}─┴─{}", GREY245, "─".repeat(col_width), RESET));
            }
            println!("{}", bot);
            0
        }
        "trend" | "vs" | "context" => {
            println!("{}[Notice]{} Semantic feature '{}' is temporarily delegated while Tabular Matrix is active.", YELLOW, RESET, cmd);
            0
        }
        _ => {
            println!("{}Usage:{} lkwords {{analyze|add category|set|ignore}} [args]", YELLOW, RESET);
            println!("  lkwords add category verbs   {}(Creates a new column 'verbs' in the dashboard){}", DIM, RESET);
            println!("  lkwords set \"is\" \"are\" verbs  {}(Assigns 'is' and 'are' to the 'verbs' column){}", DIM, RESET);
            println!("  lkwords ignore \"the\" \"and\"   {}(Hides multiple words from calculations){}", DIM, RESET);
            println!("  lkwords analyze 30           {}(Renders the Semantic Matrix Dashboard){}", DIM, RESET);
            0
        }
    }
}

// ============================================================================
// Main router
// ============================================================================
const MODULE_NAMES: &[&str] = &[
    "lki", "lkc", "lkcd", "lkch", "lkcm", "lkcy", "lks", "lksum", "lkplan", "lkset", "lkfiles", "lknote", "lkconf",
    "lkv", "lksort", "lkrank", "lkvoid", "lksnap", "lkminute", "lkhour", "lksecond", "lkspace", "lkstat", "lkweight",
    "lkdistraction", "lkchart", "lkyaml", "lkdiversity", "lkword", "lkwords", "lkh",
];

fn dispatch(name: &str, args: &[String]) -> Option<i32> {
    Some(match name {
        "lki" => lki(String::new()),
        "lkc" => lkc(args),
        "lkcd" => lkcd(args),
        "lkch" => lkch(),
        "lkcm" => lkcm(args),
        "lkcy" => lkcy(args),
        "lks" => lks(args),
        "lksum" => summary_cmd(args, false),
        "lkplan" => summary_cmd(args, true),
        "lkset" => lkset(args),
        "lkfiles" => lkfiles(args),
        "lknote" => lknote(args),
        "lkconf" => lkconf(args),
        "lkv" => lkv(args),
        "lksort" => lksort(args),
        "lkrank" => lkrank(args),
        "lkvoid" => lkvoid(args),
        "lksnap" => lksnap(args),
        "lkminute" => lkminute(),
        "lkhour" => lkhour(args),
        "lksecond" => lksecond(),
        "lkspace" => lkspace(args),
        "lkstat" => lkstat(args),
        "lkweight" => lkweight(args),
        "lkdistraction" | "lkdistracton" => lkdistraction(args),
        "lkchart" => lkchart(args),
        "lkyaml" => lkyaml(args),
        "lkdiversity" => lkdiversity(args),
        "lkword" => lkword(args),
        "lkwords" => lkwords(args),
        "lkh" => lkh(),
        _ => return None,
    })
}

fn print_conf() -> i32 {
    let c = cfg();
    println!("{}| LK (LogKlerk) {} {} --- Configuration ---{}", HEADER_ORG, LK_STATUS, LK_VERSION, RESET);
    println!("  {}LK_DIR              {}: {}{}{}", GREY, RESET, CYAN, c.lk_dir.display(), RESET);
    println!("  {}Config file        {}: {}{}{}", GREY, RESET, CYAN, c.config_file.display(), RESET);
    println!("  {}Taxonomy file      {}: {}{}{}", GREY, RESET, CYAN, c.taxonomy_file.display(), RESET);
    println!("  {}LK_DEFAULT_FORMAT  {}: {}{}{}", GREY, RESET, AMBER, c.fmt, RESET);
    println!("  {}LK_TAIL_LINES      {}: {}{}{}", GREY, RESET, AMBER, c.tail, RESET);
    println!("  {}LK_COMMAND_TAIL    {}: {}{}{}", GREY, RESET, AMBER, c.cmd_tail, RESET);
    println!("  {}LKSET_TAIL_LINES   {}: {}{}{}", GREY, RESET, AMBER, c.set_tail, RESET);
    println!("  {}LK_SNAP_DIR        {}: {}{}{}", GREY, RESET, CYAN, c.snap_dir.display(), RESET);
    println!("  {}Aliases registered {}: {}{}{}", GREY, RESET, LIME, taxonomy().len(), RESET);
    0
}

fn list_tags() -> i32 {
    for (name, k) in taxonomy() {
        match k {
            TagKind::Ctx(p) => println!("{}{:<16}{} {}{}{}", PURPLE, name, RESET, ORANGE, p, RESET),
            TagKind::Exc(f, p) => println!("{}{:<16}{} {}{}{} {}[exclusive: /{}]{}", PURPLE, name, RESET, ORANGE, p, RESET, GREY, f, RESET),
            TagKind::Note(p) => println!("{}{:<16}{} {}[note: {}]{}", PURPLE, name, RESET, CYAN, p.display(), RESET),
        }
    }
    0
}

fn install_links(dir: &str) -> i32 {
    use std::os::unix::fs::symlink;
    let exe = match std::env::current_exe() {
        Ok(e) => e,
        Err(e) => {
            println!("{}[Error]{} Cannot locate binary: {}", RED, RESET, e);
            return 1;
        }
    };
    let d = PathBuf::from(dir);
    if fs::create_dir_all(&d).is_err() {
        println!("{}[Error]{} Cannot create {}", RED, RESET, d.display());
        return 1;
    }
    let mut names: Vec<String> = MODULE_NAMES.iter().map(|s| s.to_string()).collect();
    for (n, _) in taxonomy() {
        names.push(n);
    }
    let mut made = 0;
    for n in names {
        if n == "lk" {
            continue;
        }
        let link = d.join(&n);
        if link.exists() || fs::symlink_metadata(&link).is_ok() {
            continue;
        }
        if symlink(&exe, &link).is_ok() {
            made += 1;
        }
    }
    println!("{}✔{} {} symlinks created in {}", LIME, RESET, made, d.display());
    println!("{}Hint:{} add {} to your PATH.", GREY, RESET, d.display());
    0
}

fn main() {
    unsafe {
        signal(13, 0); // SIGPIPE -> default (avoid a panic on `| head`)
    }
    let argv: Vec<String> = std::env::args().collect();
    let prog = Path::new(&argv[0])
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "lk".to_string());
    let args: Vec<String> = argv[1..].to_vec();

    // Busybox mode: binary invoked through a symlink (todo, lkc, ...)
    if prog != "lk" && !prog.starts_with("lk-") && !prog.starts_with("lk_") {
        if let Some(code) = dispatch(&prog, &args) {
            std::process::exit(code);
        }
        if let Some(kind) = lookup_alias(&prog) {
            std::process::exit(run_alias(&kind, &args));
        }
    }

    let first = args.get(0).map(|s| s.as_str()).unwrap_or("");
    let rest: &[String] = if args.is_empty() { &[] } else { &args[1..] };
    let code = match first {
        "" => lki(String::new()),
        "-h" | "--help" | "help" => lkh(),
        "-i" | "interactive" => lki(String::new()),
        "-c" | "conf" | "config" | "--conf" => print_conf(),
        "-e" | "edit" => {
            let f = today_path(&now());
            if f.is_file() {
                run_editor(&f);
                0
            } else {
                println!("{}[Warning]{} Today's log does not exist yet.", YELLOW, RESET);
                1
            }
        }
        "-pwd" | "pwd" => {
            println!("{}", cfg().lk_dir.display());
            0
        }
        "-v" | "--version" | "version" => {
            if rest.is_empty() {
                println!("LogKlerk {} {} (Rust)", LK_STATUS, LK_VERSION);
                0
            } else {
                lk_write(&format!("[[LogKlerk {}]] >>", LK_VERSION), &rest.join(" "))
            }
        }
        "-install" | "--install" => install_links(rest.get(0).map(|s| s.as_str()).unwrap_or("~/.local/bin")),
        "tags" | "-tags" => list_tags(),
        a if a.starts_with('@') && a.len() > 1 => match lookup_alias(&a[1..]) {
            Some(kind) => run_alias(&kind, rest),
            None => {
                println!("{}[Error]{} Alias '{}' not found. Try: lk tags", RED, RESET, &a[1..]);
                1
            }
        },
        other => match dispatch(other, rest) {
            Some(c) => c,
            None => lk_write("", &args.join(" ")),
        },
    };
    flush();
    std::process::exit(code);
}


