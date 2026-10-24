//! Page text: a queue thread feeds pages to scripts/manga_ocr_worker.py (comic-text-detector + CPT-flex) and keeps
//! the result in the `ocr` table. The open volume always runs, from the page being read onwards; other volumes only
//! while background reading is on and the computer is idle. The worker lives while there is work.

use std::collections::{HashMap, HashSet, VecDeque};
use std::env;
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use rusqlite::params;
use serde_json::{json, Value};

use crate::db::{self, Vol};
use crate::ops;
use crate::state::State;
use crate::thumbs;

pub const ENGINE: &str = "ctd+cpt-flex";
pub const VER: i64 = 1;
const FAILED: &str = "failed";
/// The worker needs about 1.5 GB of RAM; below this we ask the shell to stop its snip engines first.
const MIN_FREE_KB: u64 = 2_500_000;
const RATE_WINDOW: Duration = Duration::from_secs(300);

#[derive(Default)]
pub struct Plan {
    pub focus: Option<(i64, i64)>,
    pub bg: bool,
    pub idle: bool,
    pub paused: bool,
    pub quit: bool,
    kick: bool,
}

#[derive(Default)]
pub struct Live {
    state: String,
    error: String,
    current: Option<(i64, i64)>,
    done_times: VecDeque<Instant>,
    device: String,
    pid: u32,
}

pub struct Ocr {
    pub plan: Mutex<Plan>,
    cv: Condvar,
    live: Mutex<Live>,
}

impl Ocr {
    pub fn new(bg: bool, paused: bool) -> Self {
        Ocr { plan: Mutex::new(Plan { bg, paused, ..Plan::default() }), cv: Condvar::new(), live: Mutex::new(Live { state: "off".into(), ..Live::default() }) }
    }

    /// The process is ending: the queue thread stops its worker and returns.
    pub fn shutdown(&self) {
        self.plan.lock().unwrap().quit = true;
        self.cv.notify_all();
    }

    fn wake(&self) {
        self.plan.lock().unwrap().kick = true;
        self.cv.notify_all();
    }
}

// ---------------------------------------------------------------- choosing the next page

#[derive(Clone, Debug)]
pub struct VolInfo {
    pub id: i64,
    pub pages: i64,
    pub started: bool,
    pub finished: bool,
    pub updated: f64,
}

#[derive(Debug, Default, PartialEq)]
pub struct Pick {
    pub page: Option<(i64, i64)>,
    /// the first volume that has work but is an archive not yet extracted
    pub extract: Option<i64>,
    /// there is background work, but the computer is not idle
    pub waiting_idle: bool,
}

fn first_pending(v: &VolInfo, from: i64, done: &HashSet<(i64, i64)>) -> Option<i64> {
    let from = from.clamp(0, v.pages.max(1) - 1);
    (from..v.pages).chain(0..from).find(|i| !done.contains(&(v.id, *i)))
}

/// The page to read next. `vols` is in library order; `ready` says whether a volume's pages are on disk.
pub fn next_job(focus: Option<(i64, i64)>, bg: bool, idle: bool, vols: &[VolInfo], done: &HashSet<(i64, i64)>, ready: &dyn Fn(i64) -> bool) -> Pick {
    let mut pick = Pick::default();
    let consider = |v: &VolInfo, from: i64, pick: &mut Pick| -> bool {
        match first_pending(v, from, done) {
            None => false,
            Some(i) if ready(v.id) => {
                pick.page = Some((v.id, i));
                true
            }
            Some(_) => {
                pick.extract.get_or_insert(v.id);
                false
            }
        }
    };
    if let Some((fv, fp)) = focus {
        if let Some(v) = vols.iter().find(|v| v.id == fv) {
            if consider(v, fp, &mut pick) {
                return pick;
            }
        }
    }
    if !bg {
        return pick;
    }
    // started volumes (newest first), then finished ones, then everything else in library order
    let mut started: Vec<&VolInfo> = vols.iter().filter(|v| v.started && !v.finished).collect();
    started.sort_by(|a, b| b.updated.partial_cmp(&a.updated).unwrap_or(std::cmp::Ordering::Equal));
    let mut finished: Vec<&VolInfo> = vols.iter().filter(|v| v.finished).collect();
    finished.sort_by(|a, b| b.updated.partial_cmp(&a.updated).unwrap_or(std::cmp::Ordering::Equal));
    let rest = vols.iter().filter(|v| !v.started && !v.finished);
    let order: Vec<&VolInfo> = started.into_iter().chain(finished).chain(rest).collect();
    for v in order {
        if !idle {
            if first_pending(v, 0, done).is_some() {
                pick.waiting_idle = true;
                return pick;
            }
        } else if consider(v, 0, &mut pick) {
            return pick;
        }
    }
    pick
}

pub fn mem_available_kb(meminfo: &str) -> Option<u64> {
    meminfo.lines().find_map(|l| l.strip_prefix("MemAvailable:")).and_then(|r| r.split_whitespace().next()).and_then(|n| n.parse().ok())
}

fn free_kb() -> u64 {
    std::fs::read_to_string("/proc/meminfo").ok().and_then(|t| mem_available_kb(&t)).unwrap_or(u64::MAX)
}

fn min_free_kb() -> u64 {
    env::var("QS_MANGA_OCR_MIN_KB").ok().and_then(|v| v.parse().ok()).unwrap_or(MIN_FREE_KB)
}

// ---------------------------------------------------------------- the worker process

struct Worker {
    child: Child,
    stdin: ChildStdin,
    rx: Receiver<Value>,
    device: String,
}

fn spawn_worker(st: &State) -> Result<Worker, String> {
    let mut child = Command::new(&st.cfg.ocr_python)
        .arg("-I")
        .arg(&st.cfg.ocr_worker)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| format!("{}: {e}", st.cfg.ocr_python.display()))?;
    let stdin = child.stdin.take().unwrap();
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel::<Value>();
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if let Ok(v) = serde_json::from_str::<Value>(&line) {
                if tx.send(v).is_err() {
                    break;
                }
            }
        }
    });
    let mut w = Worker { child, stdin, rx, device: String::new() };
    match w.rx.recv_timeout(Duration::from_secs(240)) {
        Ok(v) if v.get("ready").and_then(Value::as_bool) == Some(true) => {
            w.device = v.get("device").and_then(Value::as_str).unwrap_or("").to_string();
            Ok(w)
        }
        Ok(v) => {
            w.kill();
            Err(format!("unexpected first message: {v}"))
        }
        Err(_) => {
            w.kill();
            Err("the worker did not start".into())
        }
    }
}

impl Worker {
    fn kill(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }

    /// Close stdin and give it a few seconds to leave, then make sure.
    fn stop(mut self) {
        drop(self.stdin);
        for _ in 0..50 {
            if matches!(self.child.try_wait(), Ok(Some(_))) {
                return;
            }
            thread::sleep(Duration::from_millis(100));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }

    /// Err = the worker is gone or stuck; Ok(reply) may still carry a page-level "error".
    fn read(&mut self, id: i64, path: &str) -> Result<Value, String> {
        let req = json!({ "id": id, "path": path });
        writeln!(self.stdin, "{req}").and_then(|_| self.stdin.flush()).map_err(|e| format!("worker pipe: {e}"))?;
        let deadline = Instant::now() + Duration::from_secs(180);
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.rx.recv_timeout(left) {
                Ok(v) if v.get("id").and_then(Value::as_i64) == Some(id) => return Ok(v),
                Ok(_) => continue,
                Err(mpsc::RecvTimeoutError::Timeout) => return Err("the worker took too long".into()),
                Err(_) => return Err("the worker exited".into()),
            }
        }
    }
}

// ---------------------------------------------------------------- the queue thread

fn load_vols(st: &State) -> Vec<(Vol, VolInfo)> {
    let con = st.db.lock().unwrap();
    let mut q = con
        .prepare(
            "select v.id, p.vol_id is not null, coalesce(p.finished, 0), coalesce(p.updated, 0)
             from volumes v left join progress p on p.vol_id = v.id
             where v.gone = 0 order by v.series_id, coalesce(v.number, 100000), v.name",
        )
        .unwrap();
    let rows: Vec<(i64, bool, bool, f64)> = q.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get::<_, i64>(2)? != 0, r.get(3)?))).unwrap().flatten().collect();
    rows.into_iter()
        .filter_map(|(id, started, finished, updated)| {
            let v = db::vol(&con, id).ok()?;
            let info = VolInfo { id, pages: v.pages, started, finished, updated };
            Some((v, info))
        })
        .collect()
}

fn load_done(st: &State) -> HashSet<(i64, i64)> {
    let con = st.db.lock().unwrap();
    let mut q = con.prepare("select vol_id, idx from ocr").unwrap();
    let rows = q.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().flatten().collect();
    rows
}

fn store(st: &State, vol: i64, idx: i64, w: i64, h: i64, blocks: &Value, engine: &str) {
    let con = st.db.lock().unwrap();
    let _ = con.execute(
        "insert or replace into ocr(vol_id, idx, w, h, blocks, engine, ver, at) values(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![vol, idx, w, h, blocks.to_string(), engine, VER, chrono::Utc::now().timestamp_millis() as f64 / 1000.0],
    );
}

fn idle_secs() -> u64 {
    env::var("QS_MANGA_OCR_IDLE").ok().and_then(|v| v.parse().ok()).unwrap_or(300)
}

fn set_state(st: &State, state: &str, error: &str) {
    let mut l = st.ocr.live.lock().unwrap();
    l.state = state.into();
    l.error = error.into();
}

pub fn run(st: Arc<State>) {
    let mut worker: Option<Worker> = None;
    let mut last_job = Instant::now();
    let mut fails = 0u32;
    let mut hold_until: Option<Instant> = None;
    let mut last_emit = Instant::now() - Duration::from_secs(10);
    let mut last_state = String::new();
    loop {
        let (focus, bg, idle, paused, quit) = {
            let p = st.ocr.plan.lock().unwrap();
            (p.focus, p.bg, p.idle, p.paused, p.quit)
        };
        if quit {
            if let Some(w) = worker.take() {
                w.stop();
            }
            return;
        }
        let held = hold_until.is_some_and(|t| Instant::now() < t);
        let vols = load_vols(&st);
        let done = load_done(&st);
        let infos: Vec<VolInfo> = vols.iter().map(|v| v.1.clone()).collect();
        let by_id: HashMap<i64, &Vol> = vols.iter().map(|v| (v.0.id, &v.0)).collect();
        let ready = |id: i64| by_id.get(&id).is_none_or(|v| v.kind == "folder" || st.pages_dir().join(thumbs::vol_hash(v)).join(".done").exists());
        let pick = if paused || held { Pick::default() } else { next_job(focus, bg, idle, &infos, &done, &ready) };
        if let Some(id) = pick.extract {
            if let Some(v) = by_id.get(&id) {
                ops::start_extract(&st, (*v).clone());
            }
        }

        if let Some((vol, idx)) = pick.page {
            // room for the models first: the shell frees its snip engines when we ask
            if worker.is_none() {
                if free_kb() < min_free_kb() {
                    st.out.event("ocr_room", json!({}));
                    thread::sleep(Duration::from_secs(5));
                    if free_kb() < min_free_kb() {
                        set_state(&st, "waiting_memory", "");
                        hold_until = Some(Instant::now() + Duration::from_secs(60));
                        emit_state(&st, &mut last_emit, &mut last_state, true);
                        continue;
                    }
                }
                st.ocr.live.lock().unwrap().current = Some((vol, idx));
                set_state(&st, "reading", "");
                emit_state(&st, &mut last_emit, &mut last_state, true);
                match spawn_worker(&st) {
                    Ok(w) => {
                        {
                            let mut l = st.ocr.live.lock().unwrap();
                            l.device = w.device.clone();
                            l.pid = w.child.id();
                        }
                        worker = Some(w);
                    }
                    Err(e) => {
                        eprintln!("qs-manga: ocr: {e}");
                        if e.contains("No such file") || e.contains("not found") {
                            set_state(&st, "missing", &e);
                            hold_until = Some(Instant::now() + Duration::from_secs(600));
                        } else {
                            fails += 1;
                            set_state(&st, "error", &e);
                            hold_until = Some(Instant::now() + Duration::from_secs(if fails >= 3 { 600 } else { 60 }));
                        }
                        emit_state(&st, &mut last_emit, &mut last_state, true);
                        continue;
                    }
                }
            }
            let name: Option<String> = st.db.lock().unwrap().query_row("select name from pages where vol_id = ?1 and idx = ?2", params![vol, idx], |r| r.get(0)).ok();
            let path = name.as_ref().and_then(|n| by_id.get(&vol).map(|v| thumbs::page_path(&st, v, n)));
            let Some(path) = path.filter(|p| p.exists()) else {
                store(&st, vol, idx, 0, 0, &json!([]), FAILED);
                continue;
            };
            {
                let mut l = st.ocr.live.lock().unwrap();
                l.current = Some((vol, idx));
                l.state = "reading".into();
            }
            let id = vol * 100_000 + idx;
            match worker.as_mut().unwrap().read(id, &path.to_string_lossy()) {
                Ok(r) => {
                    fails = 0;
                    if r.get("error").is_some() {
                        eprintln!("qs-manga: ocr: vol {vol} page {idx}: {}", r["error"]);
                        store(&st, vol, idx, 0, 0, &json!([]), FAILED);
                    } else {
                        let blocks = r.get("blocks").cloned().unwrap_or_else(|| json!([]));
                        store(&st, vol, idx, r.get("w").and_then(Value::as_i64).unwrap_or(0), r.get("h").and_then(Value::as_i64).unwrap_or(0), &blocks, ENGINE);
                    }
                    last_job = Instant::now();
                    {
                        let mut l = st.ocr.live.lock().unwrap();
                        l.done_times.push_back(Instant::now());
                        while l.done_times.front().is_some_and(|t| t.elapsed() > RATE_WINDOW) {
                            l.done_times.pop_front();
                        }
                    }
                    st.out.event("ocr", json!({ "vol": vol, "idx": idx }));
                    emit_state(&st, &mut last_emit, &mut last_state, false);
                }
                Err(e) => {
                    eprintln!("qs-manga: ocr: {e}");
                    if let Some(mut w) = worker.take() {
                        w.kill();
                    }
                    fails += 1;
                    set_state(&st, "error", &e);
                    hold_until = Some(Instant::now() + Duration::from_secs(if fails >= 3 { 600 } else { 10 }));
                    emit_state(&st, &mut last_emit, &mut last_state, true);
                }
            }
            continue;
        }

        // nothing to read right now
        let stop_now = paused || pick.waiting_idle;
        if worker.is_some() && (stop_now || last_job.elapsed() > Duration::from_secs(idle_secs())) {
            if let Some(w) = worker.take() {
                w.stop();
            }
            let mut l = st.ocr.live.lock().unwrap();
            l.current = None;
            l.pid = 0;
        }
        if !held {
            hold_until = None;
            let state = if paused {
                "paused"
            } else if pick.waiting_idle {
                "waiting_idle"
            } else if pick.extract.is_some() {
                "reading"
            } else if bg {
                "idle"
            } else {
                "off"
            };
            set_state(&st, state, "");
            if state != "reading" {
                st.ocr.live.lock().unwrap().current = None;
            }
        }
        emit_state(&st, &mut last_emit, &mut last_state, false);
        let mut p = st.ocr.plan.lock().unwrap();
        if !p.kick {
            let (g, _) = st.ocr.cv.wait_timeout(p, Duration::from_secs(2)).unwrap();
            p = g;
        }
        p.kick = false;
    }
}

fn emit_state(st: &State, last: &mut Instant, last_state: &mut String, force: bool) {
    let s = status(st);
    let key = format!("{}|{}|{}", s["state"], s["done"], s["current"]);
    if !force && (*last_state == key || last.elapsed() < Duration::from_secs(1)) {
        return;
    }
    *last_state = key;
    *last = Instant::now();
    st.out.event("ocr_state", s);
}

// ---------------------------------------------------------------- ops

fn rss_mb(pid: u32) -> u64 {
    if pid == 0 {
        return 0;
    }
    std::fs::read_to_string(format!("/proc/{pid}/status"))
        .ok()
        .and_then(|t| t.lines().find_map(|l| l.strip_prefix("VmRSS:").and_then(|r| r.split_whitespace().next()).and_then(|n| n.parse::<u64>().ok())))
        .map_or(0, |kb| kb / 1024)
}

pub fn status(st: &State) -> Value {
    let (plan_focus, bg, idle, paused) = {
        let p = st.ocr.plan.lock().unwrap();
        (p.focus, p.bg, p.idle, p.paused)
    };
    let (state, error, current, device, pid, ppm) = {
        let l = st.ocr.live.lock().unwrap();
        let n = l.done_times.iter().filter(|t| t.elapsed() <= RATE_WINDOW).count();
        let span = l.done_times.front().map_or(0.0, |t| t.elapsed().as_secs_f64()).max(30.0);
        (l.state.clone(), l.error.clone(), l.current, l.device.clone(), l.pid, if n >= 2 { n as f64 / span * 60.0 } else { 0.0 })
    };
    let con = st.db.lock().unwrap();
    let total: i64 = con.query_row("select coalesce(sum(pages), 0) from volumes where gone = 0", [], |r| r.get(0)).unwrap_or(0);
    let done: i64 = con.query_row("select count(*) from ocr o join volumes v on v.id = o.vol_id where v.gone = 0", [], |r| r.get(0)).unwrap_or(0);
    let vol_counts = |id: i64| -> (i64, i64) {
        let d: i64 = con.query_row("select count(*) from ocr where vol_id = ?1", params![id], |r| r.get(0)).unwrap_or(0);
        let p: i64 = con.query_row("select pages from volumes where id = ?1", params![id], |r| r.get(0)).unwrap_or(0);
        (d, p)
    };
    let cur = current.and_then(|(v, i)| {
        let (d, p) = vol_counts(v);
        let (title, series): (String, String) = con
            .query_row("select v.title, s.title from volumes v left join series s on s.id = v.series_id where v.id = ?1", params![v], |r| Ok((r.get(0)?, r.get::<_, Option<String>>(1)?.unwrap_or_default())))
            .unwrap_or_default();
        Some(json!({ "vol": v, "idx": i, "title": title, "series": series, "done": d, "pages": p }))
    });
    let focus = plan_focus.map(|(v, _)| {
        let (d, p) = vol_counts(v);
        json!({ "vol": v, "done": d, "pages": p })
    });
    let remaining = if bg { total - done } else { focus.as_ref().map_or(0, |f| f["pages"].as_i64().unwrap_or(0) - f["done"].as_i64().unwrap_or(0)) };
    let eta = if ppm > 0.0 && remaining > 0 { json!((remaining as f64 / ppm * 60.0).round()) } else { Value::Null };
    json!({
        "state": state, "error": error, "current": cur, "focus": focus, "done": done, "total": total, "bg": bg, "idle": idle, "paused": paused,
        "rate_ppm": (ppm * 10.0).round() / 10.0, "eta_s": eta,
        "worker": { "running": pid != 0, "device": device, "rss_mb": rss_mb(pid) },
    })
}

pub fn get(st: &State, req: &Value) -> Result<Value, String> {
    let vol = req.get("vol").and_then(Value::as_i64).ok_or("missing vol")?;
    let idx = req.get("idx").and_then(Value::as_i64).ok_or("missing idx")?;
    let all = req.get("all").and_then(Value::as_bool).unwrap_or(false);
    let row = st
        .db
        .lock()
        .unwrap()
        .query_row("select w, h, blocks, engine from ocr where vol_id = ?1 and idx = ?2", params![vol, idx], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?)))
        .ok();
    let Some((w, h, blocks, engine)) = row else { return Ok(json!({ "queued": true })) };
    if engine == FAILED {
        return Ok(json!({ "failed": true, "blocks": [] }));
    }
    let mut blocks: Value = serde_json::from_str(&blocks).unwrap_or_else(|_| json!([]));
    if !all {
        if let Some(a) = blocks.as_array_mut() {
            a.retain(|b| b.get("drop").is_none_or(Value::is_null));
        }
    }
    Ok(json!({ "w": w, "h": h, "blocks": blocks }))
}

pub fn set_focus(st: &State, req: &Value) -> Result<Value, String> {
    let vol = req.get("vol").and_then(Value::as_i64).ok_or("missing vol")?;
    let page = req.get("page").and_then(Value::as_i64).unwrap_or(0);
    st.ocr.plan.lock().unwrap().focus = if vol < 0 { None } else { Some((vol, page.max(0))) };
    st.ocr.wake();
    Ok(json!({ "ok": true }))
}

pub fn set_idle(st: &State, req: &Value) -> Result<Value, String> {
    st.ocr.plan.lock().unwrap().idle = req.get("idle").and_then(Value::as_bool).ok_or("missing idle")?;
    st.ocr.wake();
    Ok(json!({ "ok": true }))
}

pub fn set_bg(st: &State, req: &Value) -> Result<Value, String> {
    let on = req.get("on").and_then(Value::as_bool).ok_or("missing on")?;
    st.ocr.plan.lock().unwrap().bg = on;
    db::meta_set(&st.db.lock().unwrap(), "ocr_bg", if on { "1" } else { "0" });
    st.ocr.wake();
    Ok(status(st))
}

pub fn set_paused(st: &State, paused: bool) -> Value {
    st.ocr.plan.lock().unwrap().paused = paused;
    db::meta_set(&st.db.lock().unwrap(), "ocr_paused", if paused { "1" } else { "0" });
    st.ocr.wake();
    status(st)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vol(id: i64, pages: i64, started: bool, finished: bool, updated: f64) -> VolInfo {
        VolInfo { id, pages, started, finished, updated }
    }
    fn all_ready(_: i64) -> bool {
        true
    }

    #[test]
    fn focus_runs_forward_then_wraps() {
        let vols = [vol(1, 5, false, false, 0.0)];
        let mut done: HashSet<(i64, i64)> = HashSet::new();
        assert_eq!(next_job(Some((1, 3)), false, false, &vols, &done, &all_ready).page, Some((1, 3)));
        done.extend([(1, 3), (1, 4)]);
        assert_eq!(next_job(Some((1, 3)), false, false, &vols, &done, &all_ready).page, Some((1, 0)));
        done.extend([(1, 0), (1, 1), (1, 2)]);
        assert_eq!(next_job(Some((1, 3)), false, false, &vols, &done, &all_ready).page, None);
    }

    #[test]
    fn background_waits_for_idle_and_goes_started_first() {
        let vols = [vol(1, 2, false, false, 0.0), vol(2, 2, true, false, 5.0), vol(3, 2, true, true, 9.0), vol(4, 2, true, false, 8.0)];
        let done = HashSet::new();
        let busy = next_job(None, true, false, &vols, &done, &all_ready);
        assert_eq!((busy.page, busy.waiting_idle), (None, true));
        assert_eq!(next_job(None, true, true, &vols, &done, &all_ready).page, Some((4, 0)));
        assert_eq!(next_job(None, false, true, &vols, &done, &all_ready).page, None);
        let mut done: HashSet<(i64, i64)> = HashSet::new();
        done.extend([(4, 0), (4, 1), (2, 0), (2, 1)]);
        assert_eq!(next_job(None, true, true, &vols, &done, &all_ready).page, Some((3, 0)));
        done.extend([(3, 0), (3, 1)]);
        assert_eq!(next_job(None, true, true, &vols, &done, &all_ready).page, Some((1, 0)));
    }

    #[test]
    fn focus_beats_background_and_unready_archives_ask_for_extraction() {
        let vols = [vol(1, 3, false, false, 0.0), vol(2, 3, true, false, 5.0)];
        let done = HashSet::new();
        assert_eq!(next_job(Some((1, 1)), true, true, &vols, &done, &all_ready).page, Some((1, 1)));
        let not_two = |id: i64| id != 2;
        let p = next_job(Some((2, 0)), true, true, &vols, &done, &not_two);
        assert_eq!((p.page, p.extract), (Some((1, 0)), Some(2)));
    }

    #[test]
    fn meminfo_parse() {
        assert_eq!(mem_available_kb("MemTotal: 1 kB\nMemAvailable:    4096 kB\n"), Some(4096));
        assert_eq!(mem_available_kb("nothing"), None);
    }

    #[test]
    fn queue_reads_with_a_stub_worker_and_stops_on_pause() {
        use crate::config::Config;
        use std::fs;
        let dir = std::env::temp_dir().join(format!("qs-ocr-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("vol")).unwrap();
        for n in ["a.png", "bad.png", "c.png"] {
            fs::write(dir.join("vol").join(n), b"x").unwrap();
        }
        fs::write(
            dir.join("stub.py"),
            "import sys, json\nprint(json.dumps({'ready': True, 'device': 'stub'}), flush=True)\nfor l in sys.stdin:\n    r = json.loads(l)\n    if 'bad' in r['path']:\n        print(json.dumps({'id': r['id'], 'error': 'boom'}), flush=True)\n    else:\n        print(json.dumps({'id': r['id'], 'w': 10, 'h': 20, 'ms': 1, 'blocks': [{'text': 'hi', 'drop': None}, {'text': 'x', 'drop': 'nojp'}]}), flush=True)\n",
        )
        .unwrap();
        env::set_var("QS_MANGA_OCR_MIN_KB", "0");
        let cfg = Config {
            roots: vec![],
            ignore: vec![],
            cache_gb: 1.0,
            db: dir.join("t.db"),
            cache: dir.join("cache"),
            ocr_python: "python3".into(),
            ocr_worker: dir.join("stub.py"),
        };
        let con = db::open(&cfg.db).unwrap();
        con.execute("insert into volumes(id, series_id, path, kind, name, pages) values(1, 1, ?1, 'folder', 'v', 3)", params![dir.join("vol").to_string_lossy()]).unwrap();
        for (i, n) in ["a.png", "bad.png", "c.png"].iter().enumerate() {
            con.execute("insert into pages(vol_id, idx, name) values(1, ?1, ?2)", params![i as i64, n]).unwrap();
        }
        let (etx, _erx) = mpsc::channel::<()>();
        let st = Arc::new(State {
            cfg,
            out: crate::proto::Out::new(),
            db: Mutex::new(con),
            scan_lock: Mutex::new(()),
            extracting: Mutex::new(HashSet::new()),
            export: Mutex::new(etx),
            export_path: dir.join("manga.json"),
            ocr: Ocr::new(false, false),
        });
        let st2 = st.clone();
        let t = thread::spawn(move || run(st2));
        set_focus(&st, &json!({ "vol": 1, "page": 2 })).unwrap();
        let t0 = Instant::now();
        while load_done(&st).len() < 3 && t0.elapsed() < Duration::from_secs(20) {
            thread::sleep(Duration::from_millis(100));
        }
        assert_eq!(load_done(&st).len(), 3);
        // c (focus page) first, then the wrap-around; the bad page is marked failed, not retried
        assert_eq!(get(&st, &json!({ "vol": 1, "idx": 0 })).unwrap()["blocks"].as_array().unwrap().len(), 1);
        assert_eq!(get(&st, &json!({ "vol": 1, "idx": 0, "all": true })).unwrap()["blocks"].as_array().unwrap().len(), 2);
        assert_eq!(get(&st, &json!({ "vol": 1, "idx": 1 })).unwrap()["failed"], json!(true));
        assert_eq!(status(&st)["worker"]["running"], json!(true));
        // pause ends the worker process at once
        set_paused(&st, true);
        let t0 = Instant::now();
        while st.ocr.live.lock().unwrap().pid != 0 && t0.elapsed() < Duration::from_secs(10) {
            thread::sleep(Duration::from_millis(100));
        }
        assert_eq!(status(&st)["worker"]["running"], json!(false));
        assert_eq!(status(&st)["state"], json!("paused"));
        st.ocr.plan.lock().unwrap().quit = true;
        st.ocr.wake();
        t.join().unwrap();
        fs::remove_dir_all(&dir).ok();
    }
}
