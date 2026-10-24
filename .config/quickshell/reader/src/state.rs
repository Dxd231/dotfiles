use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::sync::Mutex;

use rusqlite::Connection;

use crate::config::Config;
use crate::ocr::Ocr;
use crate::proto::Out;

pub struct State {
    pub cfg: Config,
    pub out: Out,
    pub db: Mutex<Connection>,
    pub scan_lock: Mutex<()>,
    pub extracting: Mutex<HashSet<i64>>,
    pub export: Mutex<Sender<()>>,
    pub export_path: PathBuf,
    pub ocr: Ocr,
}

impl State {
    pub fn pages_dir(&self) -> PathBuf {
        self.cfg.cache.join("pages")
    }
    pub fn thumbs_dir(&self) -> PathBuf {
        self.cfg.cache.join("thumbs")
    }
    pub fn touch_export(&self) {
        let _ = self.export.lock().unwrap().send(());
    }
}
