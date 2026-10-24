//! Archives through bsdtar (libarchive): zip/cbz/rar/cbr/7z.

use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};

use crate::names;

/// Image entries of an archive, naturally sorted.
pub fn list(archive: &str) -> Result<Vec<String>, String> {
    let out = Command::new("bsdtar")
        .args(["-tf", archive])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("bsdtar: {e}"))?;
    if !out.status.success() && out.stdout.is_empty() {
        return Err(format!("bsdtar failed on {archive}"));
    }
    let mut v: Vec<String> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.ends_with('/') && names::is_image(l))
        .filter(|l| !l.split('/').any(|p| p.starts_with('.') || p == "__MACOSX"))
        .map(String::from)
        .collect();
    v.sort_by(|a, b| names::natural(a, b));
    Ok(v)
}

fn pattern(entry: &str) -> String {
    let mut s = String::new();
    for c in entry.chars() {
        if matches!(c, '[' | ']' | '*' | '?' | '\\') {
            s.push('\\');
        }
        s.push(c);
    }
    s
}

/// One entry's bytes, without extracting the rest.
pub fn read_entry(archive: &str, entry: &str) -> Result<Vec<u8>, String> {
    let out = Command::new("bsdtar")
        .args(["-xOqf", archive, "--", &pattern(entry)])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|e| format!("bsdtar: {e}"))?;
    if out.stdout.is_empty() {
        return Err(format!("empty entry {entry}"));
    }
    Ok(out.stdout)
}

/// Extract everything into `dir`, calling `progress(done)` per file.
pub fn extract(archive: &str, dir: &Path, mut progress: impl FnMut(usize)) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let mut child = Command::new("bsdtar")
        .args(["-xvf", archive, "-C"])
        .arg(dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("bsdtar: {e}"))?;
    let mut done = 0;
    if let Some(err) = child.stderr.take() {
        for line in BufReader::new(err).lines().map_while(Result::ok) {
            if line.starts_with("x ") {
                done += 1;
                progress(done);
            }
        }
    }
    let st = child.wait().map_err(|e| e.to_string())?;
    if st.success() { Ok(()) } else { Err(format!("bsdtar exited with {st}")) }
}
