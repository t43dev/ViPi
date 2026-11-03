//! Tự đổi tiếng Anh / tiếng Việt khi kết thúc một từ, theo độ phổ biến của hai cách đọc cùng một chuỗi phím.
//! Cách làm và bảng tần suất lấy từ Vikey (GPL-3.0, github.com/tonyminibot/Vikey, Engine/Engine.cpp
//! "Auto switch language from typing behavior"); tần suất gốc: FrequencyWords (Hermit Dave), OpenSubtitles 2018,
//! CC BY-SA 4.0. Bản thử nghiệm: chưa có sửa ngược từ trước, cặp từ, hoàn tác bằng Backspace.

use std::path::Path;

use crate::table::SortedTable;
use crate::telex::{decompose, lower, render, telex_keys};
use crate::CoreError;

pub struct AutoSwitch {
    /// Điểm = 10·log10(số lần trên một triệu từ). Khoá tiếng Việt là phím Telex chuẩn hoá ("trên" → "treen").
    vietnamese_table: SortedTable,
    english_table: SortedTable,
    previous: Option<Vec<char>>, // từ ngay trước, cách đúng một dấu cách
}

const PREFER: i32 = 10; // cách đọc kia phải phổ biến hơn ≥ 10 lần
const VIETNAMESE_FLOOR: i32 = 10; // từ Việt dùng ≥ ~10 lần/triệu từ thì không bao giờ bỏ
const TIE_AFTER_ENGLISH: i32 = 5; // ngay sau một từ rõ là tiếng Anh, nghiêng về tiếng Anh ≥ 3 lần là đủ
const ACRONYM_FLOOR: i32 = 5; // NAS, HDD: chỉ giữ tiếng Việt nếu âm tiết đủ phổ biến

impl AutoSwitch {
    /// `dir` chứa autoswitch-vi.bin và autoswitch-en.bin (scripts/build-tables.py).
    pub fn open(dir: &Path) -> Result<AutoSwitch, CoreError> {
        Ok(Self::new(
            SortedTable::open(&dir.join("autoswitch-vi.bin"))?,
            SortedTable::open(&dir.join("autoswitch-en.bin"))?,
        ))
    }

    pub fn new(vietnamese_table: SortedTable, english_table: SortedTable) -> AutoSwitch {
        AutoSwitch { vietnamese_table, english_table, previous: None }
    }

    fn vietnamese(&self, key: &str) -> Option<i32> {
        self.vietnamese_table.get(key).map(|v| v[0] as i8 as i32)
    }

    fn english(&self, word: &str) -> Option<i32> {
        self.english_table.get(word).map(|v| v[0] as i8 as i32)
    }

    /// Từ vừa kết thúc bằng một dấu cách: nhớ làm ngữ cảnh cho từ sau. Ranh giới khác (Enter, dấu câu, click): quên.
    pub fn remember(&mut self, keys: Option<Vec<char>>) {
        self.previous = keys;
    }

    /// Đang gõ tiếng Việt, từ `keys` hiện thành `shown`: true = trả lại các phím đã gõ và sang tiếng Anh.
    pub fn prefers_english(&self, keys: &[char], shown: &str) -> bool {
        if keys.len() < 2 {
            return false;
        }
        let Some(raw) = letters(keys) else { return false };
        let en = self.english(&raw);
        if shown.is_ascii() {
            // Telex đã nuốt một phím ("less" → "les"): trả lại từ tiếng Anh
            if shown.chars().ne(keys.iter().copied()) {
                return en.is_some();
            }
            // kiểm tra chính tả đã giữ nguyên phím ngay khi gõ ("server", "testflight"): Telex lẽ ra đã thêm dấu,
            // nên đây là từ nước ngoài → sang tiếng Anh. Từ viết giống nhau ở hai chế độ ("deploy", "ban"): ở lại.
            let marked = render(keys, false, false);
            return marked != shown && self.vietnamese(&raw).is_none() && self.is_foreign(keys, &marked);
        }
        let vn = self.vietnamese(&key(shown));
        // 2 chữ hoa trở lên (NAS, HDD) mà Telex biến thành âm tiết hiếm hoặc không có: viết tắt
        if keys.iter().filter(|c| c.is_uppercase()).count() >= 2
            && vn.unwrap_or(i32::MIN) < ACRONYM_FLOOR
            && shown.chars().any(|c| !c.is_ascii() && is_vowel(c))
        {
            return true; // VĐV, HĐND chỉ có đ: giữ
        }
        let Some(en) = en else { return false }; // không phải từ tiếng Anh: để kiểm tra chính tả lo
        let Some(vn) = vn else { return true };
        // "video call thí": ngay sau một từ tiếng Anh viết giống nhau ở hai chế độ
        if en - vn >= TIE_AFTER_ENGLISH {
            if let Some(p) = &self.previous {
                if let Some(praw) = letters(p) {
                    if self.english(&praw).is_some()
                        && render(p, false, true).chars().eq(p.iter().copied())
                        && self.vietnamese(&praw).is_none()
                    {
                        return true;
                    }
                }
            }
        }
        vn < VIETNAMESE_FLOOR && en - vn >= PREFER
    }

    /// Đang gõ tiếng Việt, kiểm tra chính tả đã trả lại các phím của một từ không có thật: từ nước ngoài
    /// (TestFlight, analytics) thì sang tiếng Anh; gõ nhầm tiếng Việt (có â ê ô ă ơ ư đ, một cụm nguyên âm) thì ở lại.
    pub fn is_foreign(&self, keys: &[char], shown: &str) -> bool {
        if keys.len() < 3 {
            return false;
        }
        let mut groups = 0;
        let mut in_vowel = false;
        for &k in keys {
            let v = "aeiouy".contains(lower(k));
            if v && !in_vowel {
                groups += 1;
            }
            in_vowel = v;
        }
        groups > 1 || !shown.chars().any(|c| decompose(c).is_some_and(|(l, _)| "âêôăơưđ".contains(l)))
    }

    /// Đang gõ tiếng Anh: chữ tiếng Việt thay cho các phím đã gõ ("treen" → "trên"), None = giữ tiếng Anh.
    pub fn vietnamese_for(&self, keys: &[char], modern: bool) -> Option<String> {
        if keys.len() < 2 {
            return None;
        }
        let raw = letters(keys)?;
        if keys.iter().filter(|c| c.is_uppercase()).count() >= 2 {
            return None; // viết tắt, tên biến, Caps Lock
        }
        let shown = render(keys, modern, true);
        if shown.chars().eq(keys.iter().copied()) {
            return None;
        }
        let vn = self.vietnamese(&key(&shown))?;
        if let Some(en) = self.english(&raw) {
            if vn - en < PREFER {
                return None;
            }
            // "the theme", "video call cos": ngay sau một từ rõ là tiếng Anh thì giữ tiếng Anh
            if let Some(p) = &self.previous {
                if let Some(praw) = letters(p) {
                    if let Some(pen) = self.english(&praw) {
                        let pshown = render(p, modern, true);
                        let pvn =
                            if pshown.chars().eq(p.iter().copied()) { None } else { self.vietnamese(&key(&pshown)) };
                        match pvn {
                            None => return None,
                            Some(pvn) if pen - pvn >= PREFER => return None,
                            _ => {}
                        }
                    }
                }
            }
        }
        Some(shown)
    }
}

/// Chữ thường a-z của các phím, None nếu có phím không phải chữ cái.
fn letters(keys: &[char]) -> Option<String> {
    let s: String = keys.iter().collect::<String>().to_lowercase();
    s.chars().all(|c| c.is_ascii_alphabetic()).then_some(s)
}

fn key(word: &str) -> String {
    telex_keys(&word.to_lowercase()).into_iter().collect()
}

fn is_vowel(c: char) -> bool {
    decompose(c).is_some_and(|(l, _)| "aăâeêioôơuưy".contains(l))
}
