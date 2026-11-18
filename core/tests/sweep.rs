//! Quét một danh sách từ lớn (không nằm trong repo) để tìm từ tiếng Anh bị bộ gõ sửa nhầm.
//!   VIPI_SWEEP_WORDS=/usr/share/dict/words cargo test --release --test sweep -- --ignored --nocapture
//! In ra các từ mà chữ trên màn hình (còn là ASCII) khác chữ đã gõ, ở trạng thái Anh và trạng thái Việt.

use std::path::PathBuf;

use vipi_core::{Composer, Key, Mode};

fn type_word(c: &mut Composer, mode: Mode, word: &str) -> String {
    c.set_mode(mode);
    c.cancel();
    let mut out: Vec<char> = vec![];
    for ch in word.chars().chain([' ']) {
        let key = if ch == ' ' { Key::Space } else { Key::Char(ch) };
        let r = c.handle_key(key);
        if let Some(e) = &r.edit {
            out.truncate(out.len() - e.backspaces);
            out.extend(e.insert.chars());
        }
        if !r.handled || r.repost_key {
            out.push(ch);
        }
    }
    out.pop();
    out.into_iter().collect()
}

#[test]
#[ignore]
fn sweep_word_list() {
    let Ok(path) = std::env::var("VIPI_SWEEP_WORDS") else { return };
    let mut c = Composer::open(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../Resources")).unwrap();
    c.set_vietnamese_options(false, true, true);
    c.set_auto_switch(true);
    let text = std::fs::read_to_string(path).unwrap();
    let words: Vec<&str> = text.lines().filter(|w| w.len() >= 2 && w.chars().all(|c| c.is_ascii_alphabetic())).collect();
    for (name, mode) in [("english", Mode::English), ("vietnamese", Mode::Vietnamese)] {
        let changed: Vec<String> = words
            .iter()
            .filter_map(|w| {
                let got = type_word(&mut c, mode, w);
                (got.is_ascii() && got != *w).then(|| format!("{w}→{got}"))
            })
            .collect();
        println!("{name}: {} of {} words changed", changed.len(), words.len());
        for line in changed.chunks(12) {
            println!("  {}", line.join(" "));
        }
    }
}
