//! Những từ tự sửa lỗi gõ không bao giờ đụng tới: viết tắt, tiếng lóng, tên thương hiệu người ta gõ thật (ntn, cta,
//! xog…), theo phím đã gõ. `keep-words.txt` là KeepWords.inc của Vikey (github.com/tonyminibot/Vikey, GPL-3.0, D26);
//! `keep-words-chat.txt` là phần ViPi thêm (viết tắt và tiếng lóng tiếng Việt không dấu: afk, inb, nhma, mlem…).
//! Mỗi dòng một từ, sắp theo byte: tìm nhị phân ngay trên file ánh xạ vào bộ nhớ (như KeepWords.swift).

use std::path::Path;

use crate::table::Bytes;

pub const FILES: [&str; 2] = ["keep-words.txt", "keep-words-chat.txt"];

pub struct KeepWords {
    files: Vec<Bytes>,
}

impl KeepWords {
    /// Các danh sách có trong `dir` (thiếu file nào thì bỏ file đó).
    pub fn open(dir: &Path) -> KeepWords {
        KeepWords { files: FILES.iter().filter_map(|f| Bytes::open(&dir.join(f)).ok()).collect() }
    }

    /// Từ các dòng cho sẵn (thử nghiệm).
    pub fn from_lists(lists: &[&str]) -> KeepWords {
        KeepWords { files: lists.iter().map(|s| Bytes::Owned(s.as_bytes().to_vec())).collect() }
    }

    pub fn contains(&self, word: &str) -> bool {
        if word.is_empty() {
            return false;
        }
        let key = super::text::lower(word);
        self.files.iter().any(|f| find(key.as_bytes(), f.as_slice()))
    }
}

fn find(key: &[u8], b: &[u8]) -> bool {
    let (mut lo, mut hi) = (0, b.len()); // khoảng byte còn phải xét, luôn bắt đầu ở đầu một dòng
    while lo < hi {
        let mut start = (lo + hi) / 2;
        while start > lo && b[start - 1] != 10 {
            start -= 1;
        }
        let mut end = start;
        while end < hi && b[end] != 10 {
            end += 1;
        }
        let line = &b[start..end];
        if line == key {
            return true;
        }
        if line < key {
            lo = (end + 1).min(hi);
        } else {
            hi = start;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_every_line_and_nothing_else() {
        let k = KeepWords::from_lists(&["afk\ncta\nmlem\nntn\nxog\n", "aaa\nzz"]);
        for w in ["afk", "cta", "mlem", "ntn", "xog", "aaa", "zz", "NTN", "Cta"] {
            assert!(k.contains(w), "{w}");
        }
        for w in ["", "af", "afkk", "b", "ml", "zzz", "a"] {
            assert!(!k.contains(w), "{w}");
        }
    }

    #[test]
    fn real_lists() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../Resources");
        let k = KeepWords::open(&dir);
        assert_eq!(k.files.len(), 2);
        for f in FILES {
            let text = std::fs::read_to_string(dir.join(f)).unwrap();
            for w in text.lines() {
                assert!(k.contains(w), "{f}: {w}");
                assert!(!k.contains(&format!("{w}qq")) || text.lines().any(|l| l == format!("{w}qq")));
            }
        }
        assert!(k.contains("ntn") && k.contains("mlem") && !k.contains("thinkx"));
    }
}
