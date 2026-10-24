//! Thumbnails and covers: small jpegs in the cache, keyed by (volume path, mtime, page, width).

use std::fs;
use std::io::Cursor;
use std::path::PathBuf;

use image::imageops::FilterType;
use sha1::{Digest, Sha1};

use crate::archive;
use crate::db::Vol;
use crate::state::State;

pub fn vol_hash(v: &Vol) -> String {
    let mut h = Sha1::new();
    h.update(format!("{}|{}", v.path, v.mtime));
    h.finalize().iter().take(6).map(|b| format!("{b:02x}")).collect()
}

/// Where a page lives on disk (it may not exist yet for an archive that has not been extracted).
pub fn page_path(st: &State, v: &Vol, name: &str) -> PathBuf {
    if v.kind == "folder" { PathBuf::from(&v.path).join(name) } else { st.pages_dir().join(vol_hash(v)).join(name) }
}

pub fn thumb_path(st: &State, v: &Vol, idx: i64, w: u32) -> PathBuf {
    st.thumbs_dir().join(format!("{}-{}-{}.jpg", vol_hash(v), idx, w))
}

/// Make (or find) the thumbnail of page `idx`; returns its path.
pub fn thumb(st: &State, v: &Vol, idx: i64, name: &str, w: u32) -> Result<PathBuf, String> {
    let dst = thumb_path(st, v, idx, w);
    if dst.exists() {
        return Ok(dst);
    }
    let local = page_path(st, v, name);
    let img = if local.exists() {
        // the content decides the format, not the extension (a PNG named .jpeg is common)
        image::ImageReader::open(&local).map_err(|e| format!("{}: {e}", local.display()))?.with_guessed_format().map_err(|e| e.to_string())?.decode().map_err(|e| format!("{}: {e}", local.display()))?
    } else if v.kind == "archive" {
        let bytes = archive::read_entry(&v.path, name)?;
        image::ImageReader::new(Cursor::new(bytes)).with_guessed_format().map_err(|e| e.to_string())?.decode().map_err(|e| e.to_string())?
    } else {
        return Err(format!("missing page {}", local.display()));
    };
    let small = img.resize(w, w * 4, FilterType::Triangle).to_rgb8();
    fs::create_dir_all(st.thumbs_dir()).map_err(|e| e.to_string())?;
    let tmp = dst.with_extension("tmp");
    {
        let f = fs::File::create(&tmp).map_err(|e| e.to_string())?;
        let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(f, 82);
        enc.encode_image(&small).map_err(|e| e.to_string())?;
    }
    fs::rename(&tmp, &dst).map_err(|e| e.to_string())?;
    Ok(dst)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_by_content_not_extension() {
        let dir = std::env::temp_dir().join(format!("qs-thumb-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("x.jpeg");
        image::RgbaImage::new(8, 12).save_with_format(&f, image::ImageFormat::Png).unwrap();
        let img = image::ImageReader::open(&f).unwrap().with_guessed_format().unwrap().decode().unwrap();
        assert_eq!((img.width(), img.height()), (8, 12));
        std::fs::remove_dir_all(&dir).ok();
    }
}
