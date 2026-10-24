//! Volume and series naming: a port of scripts/kavita_stats.py `split_name`, plus the grouping key.

use std::sync::OnceLock;

use regex::Regex;
use unicode_normalization::UnicodeNormalization;

fn volume_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(
            r"(?i)^(?P<work>.*?)[\s_\-–]*(?:第\s*(?P<k>[0-9]+)\s*[巻卷]|(?:v|vol\.?|volume)\s*(?P<v>[0-9]+)|#\s*(?P<n>[0-9]+))\D{0,6}$",
        )
        .unwrap()
    })
}

fn bare_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^(.*[^\d\s].*?)\s+([0-9]{1,3})$").unwrap())
}

fn tags_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^(?:\s*\[[^\]]*\]\s*)+").unwrap())
}

/// "ご注文はうさぎですか？ 第04巻" -> ("ご注文はうさぎですか？", Some(4)).
pub fn split_name(name: &str) -> (String, Option<i64>) {
    let name = name.trim();
    if let Some(c) = volume_re().captures(name) {
        let work = c.name("work").map_or("", |m| m.as_str()).trim();
        if !work.is_empty() {
            let n = c.name("k").or(c.name("v")).or(c.name("n")).and_then(|m| m.as_str().parse().ok());
            return (work.trim_end_matches([' ', '-', '–', '_']).to_string(), n);
        }
    }
    if let Some(c) = bare_re().captures(name) {
        return (c[1].trim().to_string(), c[2].parse().ok());
    }
    (name.to_string(), None)
}

/// The work name without a leading "[author] [group]" tag, for display.
pub fn clean_work(work: &str) -> String {
    let t = tags_re().replace(work, "");
    let t = t.trim();
    if t.is_empty() { work.trim().to_string() } else { t.to_string() }
}

/// NFKC, lowercase, letters and digits only: "東方茨歌仙 ～Wild…" and "…-Wild…-" collapse to one key.
pub fn group_key(work: &str) -> String {
    clean_work(work).nfkc().flat_map(char::to_lowercase).filter(|c| c.is_alphanumeric()).collect()
}

pub fn natural(a: &str, b: &str) -> std::cmp::Ordering {
    natord::compare_ignore_case(a, b)
}

pub fn stem(name: &str) -> String {
    match name.rsplit_once('.') {
        Some((s, e)) if e.len() <= 4 && !s.is_empty() => s.to_string(),
        _ => name.to_string(),
    }
}

pub fn is_image(name: &str) -> bool {
    let n = name.to_lowercase();
    ["jpg", "jpeg", "png", "webp", "gif", "bmp", "avif"].iter().any(|e| n.ends_with(&format!(".{e}")))
}

pub fn is_archive(name: &str) -> bool {
    let n = name.to_lowercase();
    ["zip", "cbz", "rar", "cbr", "7z", "cb7"].iter().any(|e| n.ends_with(&format!(".{e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_real_names() {
        assert_eq!(split_name("[koi] ご注文はうさぎですか？ 第04巻"), ("[koi] ご注文はうさぎですか？".into(), Some(4)));
        assert_eq!(split_name("Gochuumon_Usagi_Manga_v12"), ("Gochuumon_Usagi_Manga".into(), Some(12)));
        assert_eq!(split_name("Gochuumon wa Usagi desu ka v10 fix"), ("Gochuumon wa Usagi desu ka".into(), Some(10)));
        assert_eq!(split_name("[比良坂真琴×ZUN] 東方三月精 Visionary Fairies in Shrine. 第02巻w").1, Some(2));
        assert_eq!(split_name("東方酔蝶華 ロータスイーター達の酔醒 7"), ("東方酔蝶華 ロータスイーター達の酔醒".into(), Some(7)));
        assert_eq!(split_name("Touhou Sangetsusei Visionary v01"), ("Touhou Sangetsusei Visionary".into(), Some(1)));
        assert_eq!(split_name("Gochuumon Usagi Manga vHappy Diary").1, None);
    }

    #[test]
    fn groups_author_order_and_punctuation() {
        let a = split_name("[ZUN×あずまあや] 東方茨歌仙 -Wild and Horned Hermit.- 第01巻").0;
        let b = split_name("[あずまあや×ZUN] 東方茨歌仙 ～Wild and Horned Hermit. 第08巻").0;
        assert_eq!(group_key(&a), group_key(&b));
    }

    #[test]
    fn natural_sort() {
        let mut v = vec!["img_10.png", "img_2.png", "img_1.png", "Net-066.jpeg", "Net-02.jpeg"];
        v.sort_by(|a, b| natural(a, b));
        assert_eq!(v, ["img_1.png", "img_2.png", "img_10.png", "Net-02.jpeg", "Net-066.jpeg"]);
    }
}
