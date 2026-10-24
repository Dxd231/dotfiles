//! SQLite store: library, pages, progress, prefs, sessions, page text (ocr).

use std::fs;
use std::path::Path;

use rusqlite::{params, Connection};

const SCHEMA: &str = "
create table if not exists series(
    id integer primary key, key text unique not null, title text not null);
create table if not exists volumes(
    id integer primary key, series_id integer, path text unique not null, kind text not null,
    name text not null, gkey text not null default '', number integer, title text not null default '',
    pages integer not null default 0, mtime integer not null default 0, gone integer not null default 0);
create table if not exists pages(
    vol_id integer not null, idx integer not null, w integer not null default 0, h integer not null default 0,
    name text not null, primary key(vol_id, idx));
create table if not exists progress(
    vol_id integer primary key, page integer not null default 0, max_page integer not null default 0,
    finished integer not null default 0, updated real not null default 0);
create table if not exists prefs(vol_id integer primary key, json text not null default '{}');
create table if not exists sessions(
    vol_id integer not null, day text not null, secs real not null default 0, pages integer not null default 0,
    modified real not null default 0, primary key(vol_id, day));
create table if not exists ocr(
    vol_id integer not null, idx integer not null, w integer not null default 0, h integer not null default 0,
    blocks text not null, engine text not null, ver integer not null default 1, at real not null default 0,
    primary key(vol_id, idx));
create table if not exists bookmarks(
    vol_id integer not null, idx integer not null, at real not null default 0, primary key(vol_id, idx));
create table if not exists meta(k text primary key, v text);
";

pub fn open(path: &Path) -> Result<Connection, String> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    }
    let con = Connection::open(path).map_err(|e| e.to_string())?;
    con.pragma_update(None, "journal_mode", "WAL").map_err(|e| e.to_string())?;
    con.busy_timeout(std::time::Duration::from_secs(5)).map_err(|e| e.to_string())?;
    con.execute_batch(SCHEMA).map_err(|e| e.to_string())?;
    Ok(con)
}

#[derive(Clone, Debug)]
pub struct Vol {
    pub id: i64,
    pub series_id: i64,
    pub path: String,
    pub kind: String,
    pub name: String,
    pub number: Option<i64>,
    pub title: String,
    pub pages: i64,
    pub mtime: i64,
}

pub fn vol(con: &Connection, id: i64) -> Result<Vol, String> {
    con.query_row(
        "select id, coalesce(series_id, 0), path, kind, name, number, title, pages, mtime from volumes where id = ?1 and gone = 0",
        params![id],
        |r| {
            Ok(Vol {
                id: r.get(0)?,
                series_id: r.get(1)?,
                path: r.get(2)?,
                kind: r.get(3)?,
                name: r.get(4)?,
                number: r.get(5)?,
                title: r.get(6)?,
                pages: r.get(7)?,
                mtime: r.get(8)?,
            })
        },
    )
    .map_err(|_| format!("no such volume: {id}"))
}

pub fn meta_get(con: &Connection, k: &str) -> Option<String> {
    con.query_row("select v from meta where k = ?1", params![k], |r| r.get(0)).ok()
}

pub fn meta_set(con: &Connection, k: &str, v: &str) {
    let _ = con.execute("insert into meta(k, v) values(?1, ?2) on conflict(k) do update set v = ?2", params![k, v]);
}
