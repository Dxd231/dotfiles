//! Library scan: volumes are folders holding >= 3 images, or archives; series are grouped by work name.

use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::time::UNIX_EPOCH;

use rusqlite::params;
use serde_json::{json, Value};

use crate::archive;
use crate::db;
use crate::names;
use crate::state::State;

struct Cand {
    path: String,
    parent: String,
    kind: &'static str,
    name: String,
    mtime: i64,
}

fn mtime(p: &Path) -> i64 {
    fs::metadata(p).and_then(|m| m.modified()).ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map_or(0, |d| d.as_secs() as i64)
}

fn walk(dir: &Path, ignore: &[String], out: &mut Vec<Cand>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    let (mut images, mut dirs, mut archives) = (0, Vec::new(), Vec::new());
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        if name.starts_with('.') || ignore.contains(&name) {
            continue;
        }
        let Ok(ft) = e.file_type() else { continue };
        if ft.is_dir() {
            dirs.push(e.path());
        } else if names::is_image(&name) {
            images += 1;
        } else if names::is_archive(&name) {
            archives.push(e.path());
        }
    }
    if images >= 3 {
        let name = dir.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        out.push(Cand {
            path: dir.to_string_lossy().into(),
            parent: dir.parent().map(|p| p.to_string_lossy().into()).unwrap_or_default(),
            kind: "folder",
            name,
            mtime: mtime(dir),
        });
        return;
    }
    for a in archives {
        out.push(Cand {
            path: a.to_string_lossy().into(),
            parent: dir.to_string_lossy().into(),
            kind: "archive",
            name: a.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default(),
            mtime: mtime(&a),
        });
    }
    for d in dirs {
        walk(&d, ignore, out);
    }
}

fn folder_pages(dir: &str) -> Vec<(String, i64, i64)> {
    let mut names_: Vec<String> = fs::read_dir(dir)
        .map(|rd| rd.flatten().map(|e| e.file_name().to_string_lossy().to_string()).filter(|n| !n.starts_with('.') && names::is_image(n)).collect())
        .unwrap_or_default();
    names_.sort_by(|a, b| names::natural(a, b));
    // headers are read a few at a time: the library is on a spinning disk, and the queue helps
    let mut dims = vec![(0i64, 0i64); names_.len()];
    let chunk = names_.len().div_ceil(8).max(1);
    std::thread::scope(|sc| {
        for (ns, ds) in names_.chunks(chunk).zip(dims.chunks_mut(chunk)) {
            sc.spawn(move || {
                for (n, d) in ns.iter().zip(ds.iter_mut()) {
                    *d = imagesize::size(Path::new(dir).join(n)).map(|s| (s.width as i64, s.height as i64)).unwrap_or((0, 0));
                }
            });
        }
    });
    names_.into_iter().zip(dims).map(|(n, (w, h))| (n, w, h)).collect()
}

pub fn scan(st: &State) -> Result<Value, String> {
    let _guard = st.scan_lock.lock().unwrap();
    let mut cands = Vec::new();
    for root in &st.cfg.roots {
        walk(Path::new(root), &st.cfg.ignore, &mut cands);
    }

    // reading page lists (header reads, archive listings) happens before the db lock is taken
    let known: HashMap<String, (i64, i64, i64)> = {
        let con = st.db.lock().unwrap();
        let mut q = con.prepare("select path, id, mtime, pages from volumes where gone = 0").map_err(|e| e.to_string())?;
        let rows = q.query_map([], |r| Ok((r.get::<_, String>(0)?, (r.get::<_, i64>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?)))).map_err(|e| e.to_string())?;
        rows.flatten().collect()
    };
    let mut fresh: HashMap<String, Vec<(String, i64, i64)>> = HashMap::new();
    for c in &cands {
        if matches!(known.get(&c.path), Some(&(_, m, p)) if m == c.mtime && p > 0) {
            continue;
        }
        let pages = if c.kind == "folder" {
            folder_pages(&c.path)
        } else {
            match archive::list(&c.path) {
                Ok(l) => l.into_iter().map(|n| (n, 0, 0)).collect(),
                Err(e) => {
                    eprintln!("qs-manga: {e}");
                    continue;
                }
            }
        };
        if pages.len() >= 3 || (c.kind == "archive" && !pages.is_empty()) {
            fresh.insert(c.path.clone(), pages);
        }
    }

    // series: one per work name; a folder mixing several names (English next to Japanese) is one series
    struct Meta {
        gk: String,
        display: String,
        number: Option<i64>,
    }
    let metas: Vec<Meta> = cands
        .iter()
        .map(|c| {
            let (work, number) = names::split_name(&names::stem(&c.name));
            Meta { gk: names::group_key(&work), display: names::clean_work(&work), number }
        })
        .collect();
    let mut by_parent: HashMap<&str, HashMap<&str, usize>> = HashMap::new();
    for (c, m) in cands.iter().zip(&metas) {
        *by_parent.entry(&c.parent).or_default().entry(&m.gk).or_default() += 1;
    }
    let mut series_of: Vec<String> = Vec::new();
    for (c, m) in cands.iter().zip(&metas) {
        let counts = &by_parent[c.parent.as_str()];
        let key = if counts.len() == 1 {
            m.gk.clone()
        } else {
            counts.iter().max_by(|a, b| a.1.cmp(b.1).then(b.0.cmp(a.0))).map(|(k, _)| k.to_string()).unwrap_or_default()
        };
        series_of.push(key);
    }
    // the title is the commonest display name among the volumes of the series
    let mut titles: HashMap<&str, HashMap<&str, usize>> = HashMap::new();
    for (key, m) in series_of.iter().zip(&metas) {
        if m.gk == *key {
            *titles.entry(key).or_default().entry(&m.display).or_default() += 1;
        }
    }

    let mut con = st.db.lock().unwrap();
    let tx = con.transaction().map_err(|e| e.to_string())?;
    tx.execute("update volumes set gone = 1", []).map_err(|e| e.to_string())?;
    for ((c, m), key) in cands.iter().zip(&metas).zip(&series_of) {
        let key = if key.is_empty() { names::group_key(&c.parent) } else { key.clone() };
        let title = titles
            .get(key.as_str())
            .and_then(|t| t.iter().max_by(|a, b| a.1.cmp(b.1).then(b.0.cmp(a.0))).map(|(k, _)| k.to_string()))
            .unwrap_or_else(|| m.display.clone());
        tx.execute("insert into series(key, title) values(?1, ?2) on conflict(key) do update set title = ?2", params![key, title])
            .map_err(|e| e.to_string())?;
        let sid: i64 = tx.query_row("select id from series where key = ?1", params![key], |r| r.get(0)).map_err(|e| e.to_string())?;
        let vtitle = m.number.map_or_else(|| names::clean_work(&names::stem(&c.name)), |n| format!("Vol {n}"));
        match fresh.get(&c.path) {
            Some(pages) => {
                tx.execute(
                    "insert into volumes(series_id, path, kind, name, gkey, number, title, pages, mtime, gone)
                     values(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0)
                     on conflict(path) do update set series_id = ?1, kind = ?3, name = ?4, gkey = ?5, number = ?6,
                        title = ?7, pages = ?8, mtime = ?9, gone = 0",
                    params![sid, c.path, c.kind, c.name, m.gk, m.number, vtitle, pages.len() as i64, c.mtime],
                )
                .map_err(|e| e.to_string())?;
                let vid: i64 = tx.query_row("select id from volumes where path = ?1", params![c.path], |r| r.get(0)).map_err(|e| e.to_string())?;
                tx.execute("delete from pages where vol_id = ?1", params![vid]).map_err(|e| e.to_string())?;
                let mut ins = tx.prepare("insert into pages(vol_id, idx, w, h, name) values(?1, ?2, ?3, ?4, ?5)").map_err(|e| e.to_string())?;
                for (i, (n, w, h)) in pages.iter().enumerate() {
                    ins.execute(params![vid, i as i64, w, h, n]).map_err(|e| e.to_string())?;
                }
            }
            None => {
                // unchanged (or unreadable): keep its pages, refresh the grouping
                tx.execute(
                    "update volumes set series_id = ?1, name = ?2, gkey = ?3, number = ?4, title = ?5, gone = case when pages > 0 then 0 else 1 end where path = ?6",
                    params![sid, c.name, m.gk, m.number, vtitle, c.path],
                )
                .map_err(|e| e.to_string())?;
            }
        }
    }
    tx.execute("delete from series where id not in (select series_id from volumes where gone = 0 and series_id is not null)", [])
        .map_err(|e| e.to_string())?;
    tx.commit().map_err(|e| e.to_string())?;
    let (series, volumes): (i64, i64) = (
        con.query_row("select count(*) from series", [], |r| r.get(0)).unwrap_or(0),
        con.query_row("select count(*) from volumes where gone = 0", [], |r| r.get(0)).unwrap_or(0),
    );
    db::meta_set(&con, "scanned", &chrono::Utc::now().timestamp().to_string());
    Ok(json!({ "series": series, "volumes": volumes, "changed": fresh.len() }))
}
