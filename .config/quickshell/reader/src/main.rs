//! qs-manga: manga library/reader backend for the Quickshell shell.
//!
//! Speaks JSON lines on stdin/stdout, like scripts/lexicon.py:
//!   request  {"id": 1, "op": "ping", ...}
//!   reply    {"id": 1, ...} or {"id": 1, "error": "..."}
//!   event    {"event": "...", ...}   (unsolicited)
//! On start it prints {"ready": true, "version": "..."}.

mod archive;
mod config;
mod db;
mod export;
mod kavita;
mod names;
mod ocr;
mod ops;
mod proto;
mod scan;
mod state;
mod thumbs;
mod watch;

use std::collections::HashSet;
use std::env;
use std::io::{self, BufRead};
use std::path::PathBuf;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use crossbeam_channel::unbounded;
use serde_json::{json, Value};

use proto::Out;
use state::State;

fn export_path() -> PathBuf {
    if let Ok(p) = env::var("QS_MANGA_OUT") {
        return PathBuf::from(p);
    }
    let state = env::var("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from(env::var("HOME").unwrap_or_default()).join(".local/state"));
    state.join("quickshell/immersion/manga.json")
}

fn main() {
    let cfg = config::Config::load();
    let out = Out::new();
    let con = match db::open(&cfg.db) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("qs-manga: {e}");
            std::process::exit(2);
        }
    };
    let bg = db::meta_get(&con, "ocr_bg").as_deref() == Some("1");
    let paused = db::meta_get(&con, "ocr_paused").as_deref() == Some("1");
    let (etx, erx) = mpsc::channel::<()>();
    let st = Arc::new(State {
        cfg,
        out: out.clone(),
        db: Mutex::new(con),
        scan_lock: Mutex::new(()),
        extracting: Mutex::new(HashSet::new()),
        export: Mutex::new(etx),
        export_path: export_path(),
        ocr: ocr::Ocr::new(bg, paused),
    });
    out.send(json!({ "ready": true, "version": ops::VERSION }));

    // manga.json is rewritten at most once a second however often progress changes
    {
        let st = st.clone();
        thread::spawn(move || {
            while erx.recv().is_ok() {
                thread::sleep(Duration::from_millis(900));
                while erx.try_recv().is_ok() {}
                if let Err(e) = export::write(&st) {
                    eprintln!("qs-manga: export: {e}");
                }
            }
        });
    }
    // page text: one queue thread, one worker process while there is something to read
    let ocr_thread = {
        let st = st.clone();
        thread::spawn(move || ocr::run(st))
    };
    // first scan, then follow the folders
    {
        let st = st.clone();
        thread::spawn(move || {
            if let Err(e) = ops::rescan(&st) {
                eprintln!("qs-manga: scan: {e}");
            }
            watch::run(st);
        });
    }

    // Slow ops run on worker threads so a long scan never blocks a ping.
    let (tx, rx) = unbounded::<Value>();
    let mut workers = Vec::new();
    for _ in 0..4 {
        let rx = rx.clone();
        let st = st.clone();
        workers.push(thread::spawn(move || {
            for req in rx {
                let id = req.get("id").cloned().unwrap_or(Value::Null);
                let op = req.get("op").and_then(Value::as_str).unwrap_or("").to_string();
                let mut reply = match ops::handle(&op, &req, &st) {
                    Ok(v) => v,
                    Err(e) => json!({ "error": e }),
                };
                if let Some(o) = reply.as_object_mut() {
                    o.insert("id".into(), id);
                }
                st.out.send(reply);
            }
        }));
    }
    drop(rx);

    for line in io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        match serde_json::from_str::<Value>(&line) {
            Ok(v) if v.get("quit").and_then(Value::as_bool) == Some(true) => break,
            Ok(v) => {
                let _ = tx.send(v);
            }
            Err(e) => eprintln!("qs-manga: bad request: {e}"),
        }
    }

    // stdin closed or quit requested: let queued requests finish, and the last export, before exiting.
    drop(tx);
    for w in workers {
        let _ = w.join();
    }
    let _ = export::write(&st);
    // the page text worker: close its stdin and let it leave, rather than have the process die around it
    st.ocr.shutdown();
    for _ in 0..80 {
        if ocr_thread.is_finished() {
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }
}
