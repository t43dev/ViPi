//! Chuyển giản thể → phồn thể bằng bảng OpenCC (Apache-2.0; s2t.bin dựng từ s2t.tsv: `giản<TAB>phồn`).
//! Khớp dài nhất trước, nên 头发 → 頭髮 còn 发 một mình → 發.

use std::path::Path;

use crate::table::SortedTable;
use crate::CoreError;

pub struct ChineseConverter {
    table: SortedTable,
}

impl ChineseConverter {
    pub fn open(path: &Path) -> Result<ChineseConverter, CoreError> {
        Ok(ChineseConverter { table: SortedTable::open(path)? })
    }

    pub fn from_table(table: SortedTable) -> ChineseConverter {
        ChineseConverter { table }
    }

    pub fn convert(&self, text: &str) -> String {
        let s: Vec<char> = text.chars().collect();
        let mut out = String::new();
        let mut i = 0;
        while i < s.len() {
            let mut best: Option<(usize, &str)> = None;
            let mut key = String::new();
            let mut j = i;
            while j < s.len() {
                key.push(s[j]);
                if !self.table.has_key_with_prefix(&key) {
                    break;
                }
                if let Some(v) = self.table.get(&key) {
                    best = Some((j - i + 1, std::str::from_utf8(v).unwrap_or("")));
                }
                j += 1;
            }
            match best {
                Some((len, value)) => {
                    out.push_str(value);
                    i += len;
                }
                None => {
                    out.push(s[i]);
                    i += 1;
                }
            }
        }
        out
    }
}
