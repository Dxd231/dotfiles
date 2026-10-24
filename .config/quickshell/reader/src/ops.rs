//! Request handlers.

use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::thread;

use rusqlite::params;
use serde_json::{json, Map, Value};

use crate::archive;
use crate::db::{self, Vol};
use crate::export;
use crate::kavita;
use crate::ocr;
use crate::scan;
use crate::state::State;
use crate::thumbs;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
const COVER_W: u32 = 360;

fn num(req: &Value, k: &str) -> Result<i64, String> {
    req.get(k).and_then(Value::as_i64).ok_or_else(|| format!("missing {k}"))
}

fn now() -> f64 {
    chrono::Utc::now().timestamp_millis() as f64 / 1000.0
}

fn path_json(p: &Path) -> Value {
    Value::String(p.to_string_lossy().into())
}

fn all_vols(st: &State) -> Vec<Vol> {
    let con = st.db.lock().unwrap();
    let mut q = con
        .prepare("select id from volumes where gone = 0 order by series_id, coalesce(number, 100000), name")
        .unwrap();
    let ids: Vec<i64> = q.query_map([], |r| r.get(0)).unwrap().flatten().collect();
    ids.into_iter().filter_map(|id| db::vol(&con, id).ok()).collect()
}

fn library(st: &State) -> Result<Value, String> {
    let con = st.db.lock().unwrap();
    let mut q = con
        .prepare(
            "select s.id, s.key, s.title, v.id, v.number, v.title, v.name, v.pages, v.kind, v.path, v.mtime,
                    p.page, p.max_page, p.finished, p.updated, p.vol_id is not null,
                    (select count(*) from ocr o where o.vol_id = v.id)
             from series s join volumes v on v.series_id = s.id and v.gone = 0
             left join progress p on p.vol_id = v.id
             order by s.title collate nocase, coalesce(v.number, 100000), v.name",
        )
        .map_err(|e| e.to_string())?;
    let mut out: Vec<Value> = Vec::new();
    let mut rows = q.query([]).map_err(|e| e.to_string())?;
    while let Some(r) = rows.next().map_err(|e| e.to_string())? {
        let sid: i64 = r.get(0).unwrap();
        let v = Vol {
            id: r.get(3).unwrap(),
            series_id: sid,
            path: r.get(9).unwrap(),
            kind: r.get(8).unwrap(),
            name: r.get(6).unwrap(),
            number: r.get(4).unwrap(),
            title: r.get(5).unwrap(),
            pages: r.get(7).unwrap(),
            mtime: r.get(10).unwrap(),
        };
        let started: bool = r.get(15).unwrap();
        let cover = thumbs::thumb_path(st, &v, 0, COVER_W);
        let vj = json!({
            "id": v.id, "number": v.number, "title": v.title, "name": v.name, "pages": v.pages, "kind": v.kind,
            "page": r.get::<_, Option<i64>>(11).unwrap().unwrap_or(0), "max": r.get::<_, Option<i64>>(12).unwrap().unwrap_or(0),
            "finished": r.get::<_, Option<i64>>(13).unwrap().unwrap_or(0) != 0, "updated": r.get::<_, Option<f64>>(14).unwrap().unwrap_or(0.0),
            "started": started, "cover": path_json(&cover), "ocr": r.get::<_, i64>(16).unwrap(),
        });
        if out.last().and_then(|s| s.get("id")).and_then(Value::as_i64) != Some(sid) {
            out.push(json!({ "id": sid, "key": r.get::<_, String>(1).unwrap(), "title": r.get::<_, String>(2).unwrap(), "volumes": [] }));
        }
        out.last_mut().unwrap()["volumes"].as_array_mut().unwrap().push(vj);
    }
    Ok(json!({ "series": out }))
}

fn volume(st: &State, id: i64) -> Result<Value, String> {
    let con = st.db.lock().unwrap();
    let v = db::vol(&con, id)?;
    let mut q = con.prepare("select idx, w, h, name from pages where vol_id = ?1 order by idx").map_err(|e| e.to_string())?;
    let pages: Vec<Value> = q
        .query_map(params![id], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?, r.get::<_, String>(3)?)))
        .map_err(|e| e.to_string())?
        .flatten()
        .map(|(i, w, h, name)| {
            let p = thumbs::page_path(st, &v, &name);
            json!({ "i": i, "w": w, "h": h, "name": name, "path": if p.exists() { path_json(&p) } else { Value::Null } })
        })
        .collect();
    let mut q = con.prepare("select id, title from volumes where series_id = ?1 and gone = 0 order by coalesce(number, 100000), name").map_err(|e| e.to_string())?;
    let sibs: Vec<(i64, String)> = q.query_map(params![v.series_id], |r| Ok((r.get(0)?, r.get(1)?))).map_err(|e| e.to_string())?.flatten().collect();
    let at = sibs.iter().position(|s| s.0 == id);
    let prev = at.and_then(|i| i.checked_sub(1)).map(|i| &sibs[i]);
    let next = at.and_then(|i| sibs.get(i + 1));
    let series: String = con.query_row("select title from series where id = ?1", params![v.series_id], |r| r.get(0)).unwrap_or_default();
    let prog = con
        .query_row("select page, max_page, finished from progress where vol_id = ?1", params![id], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)? != 0)))
        .ok();
    let prefs: Value = con
        .query_row("select json from prefs where vol_id = ?1", params![id], |r| r.get::<_, String>(0))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| json!({}));
    let extracted = v.kind == "folder" || thumbs_done(st, &v);
    Ok(json!({
        "vol": id, "title": v.title, "name": v.name, "series": series, "seriesId": v.series_id, "number": v.number, "kind": v.kind,
        "pages": pages, "extracted": extracted,
        "prev": prev.map(|p| json!({ "id": p.0, "title": p.1 })), "next": next.map(|p| json!({ "id": p.0, "title": p.1 })),
        "progress": prog.map(|p| json!({ "page": p.0, "max": p.1, "finished": p.2 })), "prefs": prefs,
        "cover": path_json(&thumbs::thumb_path(st, &v, 0, COVER_W)),
    }))
}

fn thumbs_done(st: &State, v: &Vol) -> bool {
    st.pages_dir().join(thumbs::vol_hash(v)).join(".done").exists()
}

fn evict(st: &State, keep: &str) {
    let Ok(rd) = fs::read_dir(st.pages_dir()) else { return };
    fn size(p: &Path) -> u64 {
        fs::read_dir(p).map(|rd| rd.flatten().map(|e| if e.path().is_dir() { size(&e.path()) } else { e.metadata().map_or(0, |m| m.len()) }).sum()).unwrap_or(0)
    }
    let mut dirs: Vec<_> = rd
        .flatten()
        .filter(|e| e.path().is_dir())
        .map(|e| (e.metadata().and_then(|m| m.modified()).ok(), size(&e.path()), e.path(), e.file_name().to_string_lossy().to_string()))
        .collect();
    let mut total: u64 = dirs.iter().map(|d| d.1).sum();
    let cap = (st.cfg.cache_gb * 1e9) as u64;
    dirs.sort_by_key(|d| d.0);
    for d in dirs {
        if total <= cap {
            break;
        }
        if d.3 != keep {
            let _ = fs::remove_dir_all(&d.2);
            total = total.saturating_sub(d.1);
        }
    }
}

pub fn start_extract(st: &Arc<State>, v: Vol) -> bool {
    if v.kind != "archive" || thumbs_done(st, &v) {
        if v.kind == "archive" {
            let _ = fs::File::open(st.pages_dir().join(thumbs::vol_hash(&v))).and_then(|f| f.set_modified(std::time::SystemTime::now()));
        }
        return false;
    }
    if !st.extracting.lock().unwrap().insert(v.id) {
        return true;
    }
    let st = st.clone();
    thread::spawn(move || {
        let hash = thumbs::vol_hash(&v);
        let dir = st.pages_dir().join(&hash);
        evict(&st, &hash);
        let step = (v.pages / 20).max(1) as usize;
        let res = archive::extract(&v.path, &dir, |done| {
            if done % step == 0 {
                st.out.event("extract", json!({ "vol": v.id, "done": done, "total": v.pages }));
            }
        });
        match res {
            Ok(()) => {
                {
                    let con = st.db.lock().unwrap();
                    let mut q = con.prepare("select idx, name from pages where vol_id = ?1").unwrap();
                    let names: Vec<(i64, String)> = q.query_map(params![v.id], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().flatten().collect();
                    for (i, n) in names {
                        if let Ok(s) = imagesize::size(thumbs::page_path(&st, &v, &n)) {
                            let _ = con.execute("update pages set w = ?1, h = ?2 where vol_id = ?3 and idx = ?4", params![s.width as i64, s.height as i64, v.id, i]);
                        }
                    }
                }
                let _ = fs::write(dir.join(".done"), "");
                st.out.event("extracted", json!({ "vol": v.id }));
            }
            Err(e) => st.out.event("extract_error", json!({ "vol": v.id, "error": e })),
        }
        st.extracting.lock().unwrap().remove(&v.id);
    });
    true
}

pub fn covers(st: &Arc<State>) {
    let mut made = 0;
    for v in all_vols(st) {
        let name: Option<String> = st.db.lock().unwrap().query_row("select name from pages where vol_id = ?1 and idx = 0", params![v.id], |r| r.get(0)).ok();
        if let Some(n) = name {
            if !thumbs::thumb_path(st, &v, 0, COVER_W).exists() && thumbs::thumb(st, &v, 0, &n, COVER_W).is_ok() {
                made += 1;
                if made % 6 == 0 {
                    st.out.event("covers", json!({}));
                }
            }
        }
    }
    if made > 0 {
        st.out.event("covers", json!({}));
        st.touch_export();
    }
}

pub fn rescan(st: &Arc<State>) -> Result<Value, String> {
    let r = scan::scan(st)?;
    st.out.event("library", json!({}));
    let s2 = st.clone();
    thread::spawn(move || covers(&s2));
    st.touch_export();
    Ok(r)
}

fn set_progress(st: &State, req: &Value) -> Result<Value, String> {
    let vol = num(req, "vol")?;
    let page = num(req, "page")?;
    let finished = req.get("finished").and_then(Value::as_bool);
    let reset = req.get("reset").and_then(Value::as_bool).unwrap_or(false);
    let con = st.db.lock().unwrap();
    let v = db::vol(&con, vol)?;
    let page = page.clamp(0, (v.pages - 1).max(0));
    if reset {
        con.execute("delete from progress where vol_id = ?1", params![vol]).map_err(|e| e.to_string())?;
    } else {
        con.execute(
            "insert into progress(vol_id, page, max_page, finished, updated) values(?1, ?2, ?2, ?3, ?4)
             on conflict(vol_id) do update set page = ?2, max_page = max(max_page, ?2), finished = max(finished, ?3), updated = ?4",
            params![vol, page, finished.unwrap_or(false) as i64, now()],
        )
        .map_err(|e| e.to_string())?;
    }
    drop(con);
    st.touch_export();
    Ok(json!({ "ok": true }))
}

fn tick(st: &State, req: &Value) -> Result<Value, String> {
    let vol = num(req, "vol")?;
    let secs = req.get("secs").and_then(Value::as_f64).unwrap_or(15.0).clamp(0.0, 60.0);
    let turns = req.get("turns").and_then(Value::as_i64).unwrap_or(0).max(0);
    let day = chrono::Local::now().format("%Y-%m-%d").to_string();
    let con = st.db.lock().unwrap();
    db::vol(&con, vol)?;
    con.execute(
        "insert into sessions(vol_id, day, secs, pages, modified) values(?1, ?2, ?3, ?4, ?5)
         on conflict(vol_id, day) do update set secs = secs + ?3, pages = pages + ?4, modified = ?5",
        params![vol, day, secs, turns, now()],
    )
    .map_err(|e| e.to_string())?;
    drop(con);
    st.touch_export();
    Ok(json!({ "ok": true }))
}

/// Reading time and pages turned: today, the last 7 days (today included) and in total, overall and per series.
fn stats(st: &State) -> Result<Value, String> {
    let con = st.db.lock().unwrap();
    let today = chrono::Local::now().date_naive();
    let day = |back: i64| (today - chrono::Duration::days(back)).format("%Y-%m-%d").to_string();
    let (d0, d6) = (day(0), day(6));
    let mut q = con
        .prepare("select v.series_id, s.day, s.secs, s.pages from sessions s join volumes v on v.id = s.vol_id")
        .map_err(|e| e.to_string())?;
    let rows: Vec<(i64, String, f64, i64)> = q
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
        .map_err(|e| e.to_string())?
        .flatten()
        .collect();
    Ok(stats_of(&rows, &d0, &d6))
}

fn stats_of(rows: &[(i64, String, f64, i64)], today: &str, week_from: &str) -> Value {
    let (mut t, mut w, mut all) = ((0.0, 0), (0.0, 0), (0.0, 0));
    let mut per: std::collections::BTreeMap<i64, (f64, f64)> = Default::default();
    for (sid, day, secs, pages) in rows {
        all = (all.0 + secs, all.1 + pages);
        let e = per.entry(*sid).or_default();
        e.1 += secs;
        if day.as_str() == today {
            t = (t.0 + secs, t.1 + pages);
        }
        if day.as_str() >= week_from && day.as_str() <= today {
            w = (w.0 + secs, w.1 + pages);
            e.0 += secs;
        }
    }
    let one = |x: (f64, i64)| json!({ "secs": x.0, "pages": x.1 });
    let series: Vec<Value> = per.iter().map(|(id, v)| json!({ "id": id, "week": v.0, "total": v.1 })).collect();
    json!({ "today": one(t), "week": one(w), "total": one(all), "series": series })
}

fn prefs_set(st: &State, req: &Value) -> Result<Value, String> {
    let vol = num(req, "vol")?;
    let patch = req.get("prefs").and_then(Value::as_object).ok_or("missing prefs")?;
    let con = st.db.lock().unwrap();
    let mut cur: Map<String, Value> = con
        .query_row("select json from prefs where vol_id = ?1", params![vol], |r| r.get::<_, String>(0))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default();
    for (k, v) in patch {
        cur.insert(k.clone(), v.clone());
    }
    let text = serde_json::to_string(&cur).unwrap();
    con.execute("insert into prefs(vol_id, json) values(?1, ?2) on conflict(vol_id) do update set json = ?2", params![vol, text]).map_err(|e| e.to_string())?;
    Ok(Value::Object(cur))
}

pub fn handle(op: &str, req: &Value, st: &Arc<State>) -> Result<Value, String> {
    match op {
        "ping" => Ok(json!({ "pong": true, "version": VERSION })),
        "config" => Ok(json!({
            "roots": st.cfg.roots, "ignore": st.cfg.ignore, "cacheGB": st.cfg.cache_gb, "db": st.cfg.db, "cache": st.cfg.cache,
            "export": st.export_path,
        })),
        "quit" => std::process::exit(0),
        "library" => library(st),
        "stats" => stats(st),
        "rescan" => rescan(st),
        "volume" => volume(st, num(req, "vol")?),
        "open" => {
            let id = num(req, "vol")?;
            let v = db::vol(&st.db.lock().unwrap(), id)?;
            let extracting = start_extract(st, v);
            let mut r = volume(st, id)?;
            r["extracting"] = json!(extracting);
            Ok(r)
        }
        "thumb" => {
            let vol = num(req, "vol")?;
            let i = num(req, "i")?;
            let w = req.get("w").and_then(Value::as_u64).unwrap_or(160) as u32;
            let (v, name) = {
                let con = st.db.lock().unwrap();
                let v = db::vol(&con, vol)?;
                let n: String = con.query_row("select name from pages where vol_id = ?1 and idx = ?2", params![vol, i], |r| r.get(0)).map_err(|_| "no such page")?;
                (v, n)
            };
            Ok(json!({ "vol": vol, "i": i, "path": path_json(&thumbs::thumb(st, &v, i, &name, w)?) }))
        }
        "progress" => set_progress(st, req),
        "tick" => tick(st, req),
        "prefs_get" => {
            let vol = num(req, "vol")?;
            let con = st.db.lock().unwrap();
            let p: Value = con
                .query_row("select json from prefs where vol_id = ?1", params![vol], |r| r.get::<_, String>(0))
                .ok()
                .and_then(|t| serde_json::from_str(&t).ok())
                .unwrap_or_else(|| json!({}));
            Ok(json!({ "prefs": p }))
        }
        "prefs_set" => prefs_set(st, req).map(|p| json!({ "prefs": p })),
        "import_kavita" => kavita::import(st, req),
        "ocr" => ocr::get(st, req),
        "ocr_status" => Ok(ocr::status(st)),
        "ocr_focus" => ocr::set_focus(st, req),
        "ocr_idle" => ocr::set_idle(st, req),
        "ocr_bg" => ocr::set_bg(st, req),
        "ocr_pause" => Ok(ocr::set_paused(st, true)),
        "ocr_resume" => Ok(ocr::set_paused(st, false)),
        "export" => export::write(st).map(|_| json!({ "ok": true, "path": st.export_path })),
        _ => Err(format!("unknown op: {op}")),
    }
}


#[cfg(test)]
mod stats_tests {
    use super::stats_of;

    #[test]
    fn sums_today_week_and_total() {
        let rows = vec![
            (1, "2026-10-24".to_string(), 60.0, 5),
            (1, "2026-10-20".to_string(), 120.0, 9),
            (2, "2026-10-10".to_string(), 300.0, 20),
        ];
        let v = stats_of(&rows, "2026-10-24", "2026-10-18");
        assert_eq!(v["today"]["secs"], 60.0);
        assert_eq!(v["week"]["secs"], 180.0);
        assert_eq!(v["week"]["pages"], 14);
        assert_eq!(v["total"]["secs"], 480.0);
        assert_eq!(v["series"][1]["week"], 0.0);
    }
}
