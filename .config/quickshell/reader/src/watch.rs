//! Follow the library roots: any change, then 2 s of quiet, triggers a rescan.

use std::path::Path;
use std::sync::mpsc::{channel, RecvTimeoutError};
use std::sync::Arc;
use std::time::Duration;

use notify::{RecursiveMode, Watcher};

use crate::ops;
use crate::state::State;

pub fn run(st: Arc<State>) {
    let (tx, rx) = channel();
    let mut w = match notify::recommended_watcher(move |ev: notify::Result<notify::Event>| {
        if let Ok(e) = ev {
            let _ = tx.send(e);
        }
    }) {
        Ok(w) => w,
        Err(e) => {
            eprintln!("qs-manga: watch: {e}");
            return;
        }
    };
    for r in &st.cfg.roots {
        if let Err(e) = w.watch(Path::new(r), RecursiveMode::Recursive) {
            eprintln!("qs-manga: watch {r}: {e}");
        }
    }
    let relevant = |e: &notify::Event| {
        !matches!(e.kind, notify::EventKind::Access(_))
            && e.paths.iter().any(|p| !p.components().any(|c| st.cfg.ignore.iter().any(|i| c.as_os_str() == i.as_str())))
    };
    loop {
        match rx.recv() {
            Ok(e) if relevant(&e) => {}
            Ok(_) => continue,
            Err(_) => return,
        }
        loop {
            match rx.recv_timeout(Duration::from_secs(2)) {
                Ok(_) => continue,
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => return,
            }
        }
        if let Err(e) = ops::rescan(&st) {
            eprintln!("qs-manga: rescan: {e}");
        }
    }
}
