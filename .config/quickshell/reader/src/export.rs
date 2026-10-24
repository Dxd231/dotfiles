//! immersion/manga.json: the reading history in kavita.json's shape, so Immersion can read it unchanged.

use std::fs;

use serde_json::{json, Value};

use crate::db;
use crate::state::State;
use crate::thumbs;

// ids the shell sees: far above Kavita's, so the frozen history and the reader's rows never collide
const ID_BASE: i64 = 1_000_000;

fn now() -> f64 {
    chrono::Utc::now().timestamp_millis() as f64 / 1000.0
}

pub fn write(st: &State) -> Result<(), String> {
    let con = st.db.lock().unwrap();
    let mut series = Vec::new();
    let mut q = con
        .prepare(
            "select v.id, s.key, s.title, coalesce(p.max_page, 0), coalesce(p.finished, 0), coalesce(p.updated, 0), p.vol_id is not null
             from volumes v join series s on s.id = v.series_id left join progress p on p.vol_id = v.id where v.gone = 0",
        )
        .map_err(|e| e.to_string())?;
    let rows: Vec<(i64, String, String, i64, bool, f64, bool)> = q
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get::<_, i64>(4)? != 0, r.get(5)?, r.get(6)?)))
        .map_err(|e| e.to_string())?
        .flatten()
        .collect();
    let mut modified = 0.0f64;
    let mut last: Option<(f64, i64)> = None;
    for (id, key, title, max_page, finished, updated, started) in rows {
        let v = db::vol(&con, id)?;
        let read = if finished { v.pages } else if started { max_page + 1 } else { 0 };
        let cover = thumbs::thumb_path(st, &v, 0, 360);
        modified = modified.max(updated);
        if started && last.map_or(true, |l| updated >= l.0) {
            last = Some((updated, id));
        }
        series.push(json!({
            "id": ID_BASE + id, "vol": id, "name": v.title, "work": title, "volume": v.number.map_or(String::new(), |n| format!("Vol {n}")),
            "pages": v.pages, "read": read, "progress": if v.pages > 0 { Some((read as f64 / v.pages as f64).min(1.0)) } else { None },
            "cover": if cover.exists() { Value::String(cover.to_string_lossy().into()) } else { Value::Null },
            "modified": updated, "library": Value::Null, "format": Value::Null, "chapter": Value::Null, "group": key,
        }));
    }
    let mut rows = Vec::new();
    let mut q = con
        .prepare("select s.vol_id, s.day, s.secs, s.pages, s.modified, v.title, t.title, v.number from sessions s join volumes v on v.id = s.vol_id join series t on t.id = v.series_id order by s.day, s.modified")
        .map_err(|e| e.to_string())?;
    let it = q
        .query_map([], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, f64>(2)?, r.get::<_, i64>(3)?, r.get::<_, f64>(4)?, r.get::<_, String>(5)?, r.get::<_, String>(6)?, r.get::<_, Option<i64>>(7)?))
        })
        .map_err(|e| e.to_string())?;
    let mut latest = String::new();
    for (sid, day, secs, pages, m, vtitle, work, number) in it.flatten() {
        modified = modified.max(m);
        if day > latest {
            latest = day.clone();
        }
        rows.push(json!({
            "series": format!("{work} {vtitle}"), "work": work, "volume": number.map_or(String::new(), |n| format!("Vol {n}")),
            "sid": ID_BASE + sid, "day": day, "secs": secs, "pages": pages, "modified": m,
        }));
    }
    let active = modified > 0.0 && now() - modified < 120.0;
    let doc = json!({
        "updated": now(), "latest": latest, "rows": rows, "series": series, "active": active,
        "activeSeries": last.map(|l| ID_BASE + l.1), "modified": modified,
    });
    if let Some(dir) = st.export_path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let tmp = st.export_path.with_extension("tmp");
    fs::write(&tmp, serde_json::to_vec(&doc).unwrap()).map_err(|e| e.to_string())?;
    fs::rename(&tmp, &st.export_path).map_err(|e| e.to_string())
}
