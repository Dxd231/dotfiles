//! One-shot import of Kavita's reading progress (read-only, from a private copy of its db).

use std::fs;

use chrono::NaiveDateTime;
use rusqlite::{params, Connection, OpenFlags};
use serde_json::{json, Value};

use crate::names;
use crate::state::State;

const DEFAULT_DB: &str = "/opt/kavita/config/kavita.db";

fn epoch(s: &str) -> f64 {
    NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S%.f").or_else(|_| NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S%.f")).map_or(0.0, |d| d.and_utc().timestamp() as f64)
}

fn norm(name: &str) -> String {
    names::group_key(&names::stem(name))
}

pub fn import(st: &State, req: &Value) -> Result<Value, String> {
    let src = req.get("db").and_then(Value::as_str).unwrap_or(DEFAULT_DB).to_string();
    let overwrite = req.get("overwrite").and_then(Value::as_bool).unwrap_or(false);
    let tmp = st.cfg.cache.join("kavita-import");
    let _ = fs::remove_dir_all(&tmp);
    fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
    for suffix in ["", "-wal"] {
        let from = format!("{src}{suffix}");
        if std::path::Path::new(&from).exists() {
            fs::copy(&from, tmp.join(format!("k.db{suffix}"))).map_err(|e| format!("{from}: {e}"))?;
        }
    }
    let k = Connection::open_with_flags(tmp.join("k.db"), OpenFlags::SQLITE_OPEN_READ_ONLY).map_err(|e| e.to_string())?;
    let mut q = k
        .prepare(
            "select s.Id, s.Name, s.Pages, sum(p.PagesRead), max(p.LastModifiedUtc)
             from Series s join AppUserProgresses p on p.SeriesId = s.Id group by s.Id",
        )
        .map_err(|e| e.to_string())?;
    let rows: Vec<(i64, String, i64, i64, String)> = q
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get::<_, Option<i64>>(2)?.unwrap_or(0), r.get::<_, Option<i64>>(3)?.unwrap_or(0), r.get::<_, Option<String>>(4)?.unwrap_or_default())))
        .map_err(|e| e.to_string())?
        .flatten()
        .collect();

    let con = st.db.lock().unwrap();
    let vols: Vec<(i64, String, String, Option<i64>, i64)> = {
        let mut q = con.prepare("select id, name, gkey, number, pages from volumes where gone = 0").map_err(|e| e.to_string())?;
        let v = q.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).map_err(|e| e.to_string())?.flatten().collect();
        v
    };
    let (mut matched, mut unmatched, mut kept) = (Vec::new(), Vec::new(), 0);
    for (kid, name, pages, read, modified) in rows {
        if read <= 0 {
            continue;
        }
        let nn = norm(&name);
        let (work, number) = names::split_name(&names::stem(&name));
        let gk = names::group_key(&work);
        let hit = vols
            .iter()
            .find(|v| norm(&v.1) == nn)
            .or_else(|| vols.iter().find(|v| number.is_some() && v.3 == number && v.2 == gk));
        let Some(v) = hit else {
            unmatched.push(json!({ "kavita": name, "id": kid, "read": read }));
            continue;
        };
        let have: Option<i64> = con.query_row("select vol_id from progress where vol_id = ?1", params![v.0], |r| r.get(0)).ok();
        if have.is_some() && !overwrite {
            kept += 1;
            continue;
        }
        let total = if v.4 > 0 { v.4 } else { pages };
        let page = (read - 1).clamp(0, (total - 1).max(0));
        let finished = total > 0 && read >= total;
        let at = epoch(&modified);
        con.execute(
            "insert into progress(vol_id, page, max_page, finished, updated) values(?1, ?2, ?2, ?3, ?4)
             on conflict(vol_id) do update set page = ?2, max_page = ?2, finished = ?3, updated = ?4",
            params![v.0, page, finished as i64, at],
        )
        .map_err(|e| e.to_string())?;
        matched.push(json!({ "kavita": name, "volume": v.1, "id": v.0, "page": page, "finished": finished }));
    }
    let _ = fs::remove_dir_all(&tmp);
    crate::db::meta_set(&con, "kavita_imported", &chrono::Utc::now().timestamp().to_string());
    drop(con);
    st.touch_export();
    Ok(json!({ "matched": matched, "unmatched": unmatched, "kept": kept }))
}
