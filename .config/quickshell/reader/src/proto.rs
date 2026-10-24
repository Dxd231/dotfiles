use std::io::Write;
use std::sync::{Arc, Mutex};

use serde_json::Value;

/// Serialised writer for stdout so replies from worker threads never interleave.
#[derive(Clone)]
pub struct Out(Arc<Mutex<()>>);

impl Out {
    pub fn new() -> Self {
        Out(Arc::new(Mutex::new(())))
    }

    pub fn send(&self, v: Value) {
        let _g = self.0.lock().unwrap();
        let mut so = std::io::stdout().lock();
        let _ = writeln!(so, "{v}");
        let _ = so.flush();
    }

    #[allow(dead_code)]
    pub fn event(&self, name: &str, mut v: Value) {
        if let Some(o) = v.as_object_mut() {
            o.insert("event".into(), name.into());
        }
        self.send(v);
    }
}
