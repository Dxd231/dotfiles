use std::env;
use std::fs;
use std::path::PathBuf;

use serde::Deserialize;

#[derive(Deserialize, Default)]
struct File {
    roots: Option<Vec<String>>,
    ignore: Option<Vec<String>>,
    #[serde(rename = "cacheGB")]
    cache_gb: Option<f64>,
    #[serde(rename = "ocrPython")]
    ocr_python: Option<String>,
    #[serde(rename = "ocrWorker")]
    ocr_worker: Option<String>,
}

pub struct Config {
    pub roots: Vec<String>,
    pub ignore: Vec<String>,
    pub cache_gb: f64,
    pub db: PathBuf,
    pub cache: PathBuf,
    /// The text recognition worker: its interpreter and script (QS_MANGA_OCR_PY / QS_MANGA_OCR_WORKER win).
    pub ocr_python: PathBuf,
    pub ocr_worker: PathBuf,
}

fn home() -> PathBuf {
    PathBuf::from(env::var("HOME").unwrap_or_else(|_| "/".into()))
}

fn dir_env(var: &str, fallback: &str) -> PathBuf {
    env::var(var).map(PathBuf::from).unwrap_or_else(|_| home().join(fallback))
}

impl Config {
    /// Defaults < ~/.local/state/quickshell/manga/config.json < env (QS_MANGA_ROOTS, QS_MANGA_DB).
    pub fn load() -> Self {
        let state = dir_env("XDG_STATE_HOME", ".local/state").join("quickshell/manga");
        let cache = dir_env("XDG_CACHE_HOME", ".cache").join("quickshell/manga");
        let file: File = fs::read_to_string(state.join("config.json"))
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();

        let mut roots = file.roots.unwrap_or_else(|| vec!["/mnt/GAME_DISK/Manga".into()]);
        if let Ok(r) = env::var("QS_MANGA_ROOTS") {
            roots = r.split(':').filter(|s| !s.is_empty()).map(String::from).collect();
        }
        let db = env::var("QS_MANGA_DB").map(PathBuf::from).unwrap_or_else(|_| state.join("manga.db"));

        let ocr_python = env::var("QS_MANGA_OCR_PY").ok().or(file.ocr_python).map(PathBuf::from).unwrap_or_else(|| home().join(".venv/mokuro/bin/python"));
        let ocr_worker = env::var("QS_MANGA_OCR_WORKER").ok().or(file.ocr_worker).map(PathBuf::from).unwrap_or_else(|| home().join(".config/quickshell/scripts/manga_ocr_worker.py"));

        Config {
            roots,
            ignore: file.ignore.unwrap_or_else(|| vec!["Archives".into(), "Misc".into(), "old".into()]),
            cache_gb: file.cache_gb.unwrap_or(4.0),
            db,
            cache,
            ocr_python,
            ocr_worker,
        }
    }
}
