//! Tự đổi tiếng Anh / tiếng Việt khi kết thúc một từ, theo độ phổ biến của hai cách đọc cùng một chuỗi phím.
//! Cách làm và bảng tần suất lấy từ Vikey (GPL-3.0, github.com/tonyminibot/Vikey, Engine/Engine.cpp
//! "Auto switch language from typing behavior"); tần suất gốc: FrequencyWords (Hermit Dave), OpenSubtitles 2018,
//! CC BY-SA 4.0. Cặp từ (Vikey D30, D34): từ đọc được cả hai cách (bus/bú, been/bên) theo từ đứng trước trong văn bản
//! thật (FineWeb-2 / FineWeb, ODC-By; HPLT 2, CC0; MADLAD-400, ODC-By; Reddit). Dạng từ tiếng Anh (D60): SCOWL en_US,
//! © Kevin Atkinson. Sửa ngược từ ngay trước khi đã chắc là tiếng Anh (D8, D13). Chưa có: bộ ba từ.

use std::path::Path;

use crate::table::SortedTable;
use crate::telex::{decompose, lower, render, telex_keys};
use crate::CoreError;

pub struct AutoSwitch {
    /// Điểm = 10·log10(số lần trên một triệu từ). Khoá tiếng Việt là phím Telex chuẩn hoá ("trên" → "treen").
    vietnamese_table: SortedTable,
    english_table: SortedTable,
    pairs_table: Option<SortedTable>, // "từ trước<TAB>từ sau" → 8·log2(số lần)
    previous: Option<Previous>,
}

/// Từ ngay trước (cách đúng một dấu cách).
struct Previous {
    keys: Vec<char>,
    vietnamese: bool,     // gõ ở chế độ tiếng Việt
    shown: Option<String>, // chữ đang hiện nếu bộ gõ không đụng tới lúc kết thúc từ
}

const PREFER: i32 = 10; // cách đọc kia phải phổ biến hơn ≥ 10 lần
const VIETNAMESE_FLOOR: i32 = 10; // từ Việt dùng ≥ ~10 lần/triệu từ thì không bao giờ bỏ
const TIE_AFTER_ENGLISH: i32 = 5; // ngay sau một từ rõ là tiếng Anh, nghiêng về tiếng Anh ≥ 3 lần là đủ
const ACRONYM_FLOOR: i32 = 5; // NAS, HDD: chỉ giữ tiếng Việt nếu âm tiết đủ phổ biến
const PAIR_OVERRIDES_TIE: i32 = 10; // cặp từ nghiêng tiếng Việt ≥ 10 lần thắng luật "ngay sau từ tiếng Anh" (D34)
const PAIR_WEIGHT: f64 = 2.0;
const PAIR_MIN_COUNT: i64 = 3;
const LOOK_BACK_LEAN: i32 = 10; // từ trước chỉ được sửa khi tiếng Anh phổ biến hơn ≥ 10 lần: "bên server", "cả server" giữ nguyên
const PLAIN_MARGIN: i32 = 15; // "thí create": từ trước phải nghiêng tiếng Anh ~30 lần mới đủ làm từ sau sang tiếng Anh
const CAPS_FLOOR: i32 = 15; // cả từ viết hoa chỉ đổi sang âm tiết phổ biến (IRS giữ nguyên, không thành Í)

impl AutoSwitch {
    /// `dir` chứa autoswitch-vi.bin, autoswitch-en.bin và autoswitch-pairs.bin (scripts/build-tables.py).
    pub fn open(dir: &Path) -> Result<AutoSwitch, CoreError> {
        Ok(Self::new(
            SortedTable::open(&dir.join("autoswitch-vi.bin"))?,
            SortedTable::open(&dir.join("autoswitch-en.bin"))?,
            SortedTable::open(&dir.join("autoswitch-pairs.bin")).ok(),
        ))
    }

    pub fn new(
        vietnamese_table: SortedTable,
        english_table: SortedTable,
        pairs_table: Option<SortedTable>,
    ) -> AutoSwitch {
        AutoSwitch { vietnamese_table, english_table, pairs_table, previous: None }
    }

    fn vietnamese(&self, key: &str) -> Option<i32> {
        self.vietnamese_table.get(key).map(|v| v[0] as i8 as i32)
    }

    fn english(&self, word: &str) -> Option<i32> {
        self.english_table.get(word).map(|v| v[0] as i8 as i32)
    }

    /// Điểm của `shown` nếu đó đúng là một chữ có thật: "rêts" cùng khoá với "rết" nhưng không phải chữ nào (D60).
    fn word_score(&self, shown: &str) -> Option<i32> {
        let k = key(shown);
        let keys: Vec<char> = k.chars().collect();
        let low = shown.to_lowercase();
        (render(&keys, false, true) == low || render(&keys, true, true) == low).then(|| self.vietnamese(&k))?
    }

    /// Từ vừa kết thúc bằng một dấu cách: nhớ làm ngữ cảnh cho từ sau (`vietnamese`: gõ ở chế độ tiếng Việt;
    /// `shown`: chữ đang hiện nếu bộ gõ không sửa gì lúc kết thúc từ). Ranh giới khác (Enter, dấu câu, click): quên.
    pub fn remember(&mut self, keys: Option<Vec<char>>, vietnamese: bool, shown: Option<String>) {
        self.previous = keys.map(|keys| Previous { keys, vietnamese, shown });
    }

    /// Từ trước đang hiện chữ Việt mà đọc tiếng Anh phổ biến hơn hẳn ("thí" = this): (điểm Anh, điểm Việt).
    fn ambiguous_previous(&self) -> Option<(i32, i32)> {
        let p = self.previous.as_ref().filter(|p| p.vietnamese)?;
        let shown = p.shown.as_ref().filter(|s| s.chars().ne(p.keys.iter().copied()))?;
        let (en, vn) = (self.english(&letters_of(&p.keys)?)?, self.word_score(shown)?);
        (en >= vn + LOOK_BACK_LEAN).then_some((en, vn))
    }

    /// `keys` vừa sang tiếng Anh: từ ngay trước cũng trả lại phím đã gõ ("thí makes" → "this makes", D8).
    /// Trả (chữ đang hiện, các phím). Từ viết tắt không nói gì về từ trước ("bên USA", D42).
    pub fn look_back(&self, keys: &[char]) -> Option<(String, String)> {
        if capitals(keys) >= 2 || self.english(&letters_of(keys)?).is_none() {
            return None;
        }
        self.ambiguous_previous()?;
        let p = self.previous.as_ref()?;
        Some((p.shown.clone()?, p.keys.iter().collect()))
    }

    /// "ddc" → "đc": viết tắt chỉ có đ và phụ âm mà tin nhắn hay dùng (D27).
    pub fn shorthand(&self, keys: &[char]) -> Option<String> {
        let raw = letters_of(keys)?;
        if !raw.starts_with("dd") || raw.chars().any(|c| "aeiouy".contains(c)) || self.english(&raw).is_some() {
            return None;
        }
        self.vietnamese(&raw)?;
        Some(render(keys, false, false))
    }

    /// Chữ hiện ra của các chữ cái: chính nó, hoặc cách đọc tiếng Việt (phải là từ có thật).
    fn surface(&self, letters: &str, vietnamese: bool) -> Option<String> {
        if !vietnamese {
            return Some(letters.to_string());
        }
        let chars: Vec<char> = letters.chars().collect();
        let shown = render(&chars, false, true);
        (shown != letters && self.vietnamese(&key(&shown)).is_some()).then_some(shown)
    }

    fn pair_count(&self, key: &str) -> i64 {
        match self.pairs_table.as_ref().and_then(|t| t.get(key)) {
            Some(v) => 2f64.powf(v[0] as f64 / 8.0).round() as i64,
            None => 0,
        }
    }

    /// Cặp từ (D30): > 0 khi cách đọc tiếng Việt của `letters` đứng sau từ trước nhiều hơn cách đọc tiếng Anh
    /// (10 = gấp 10 lần, nhân trọng số 2), < 0 thì ngược lại, 0 khi không đủ dữ liệu.
    fn pair_vote(&self, previous: Option<(&[char], bool)>, letters: &str) -> i32 {
        let Some((pkeys, pvietnamese)) = previous else { return 0 };
        if self.pairs_table.is_none() {
            return 0;
        }
        let Some(praw) = letters_of(pkeys) else { return 0 };
        let pchars: Vec<char> = praw.chars().collect();
        let prev_vietnamese = pvietnamese && render(&pchars, false, true) != praw;
        let (Some(before), Some(vn)) = (self.surface(&praw, prev_vietnamese), self.surface(letters, true)) else {
            return 0;
        };
        let cv = self.pair_count(&format!("{before}\t{vn}"));
        let ce = self.pair_count(&format!("{before}\t{letters}"));
        if cv + ce < PAIR_MIN_COUNT {
            return 0;
        }
        let v = (10.0 * ((cv as f64 + 0.5) / (ce as f64 + 0.5)).log10()).clamp(-30.0, 30.0);
        (v * PAIR_WEIGHT).round() as i32
    }

    fn previous_ref(&self) -> Option<(&[char], bool)> {
        self.previous.as_ref().map(|p| (p.keys.as_slice(), p.vietnamese))
    }

    /// Đang gõ tiếng Việt, từ `keys` hiện thành `shown`: true = trả lại các phím đã gõ và sang tiếng Anh.
    pub fn prefers_english(&self, keys: &[char], shown: &str) -> bool {
        if keys.len() < 2 {
            return false;
        }
        let Some(raw) = letters_of(keys) else { return false };
        let en = self.english(&raw);
        if shown.is_ascii() {
            // Telex đã nuốt một phím ("less" → "les", "currentState" → "curentState"): trả lại từ tiếng Anh, viết tắt
            // ("ASUS") hay từ không thể là một âm tiết, trừ khi chữ còn lại đã là tiếng Anh ("tessting" → "testing")
            if shown.chars().ne(keys.iter().copied()) {
                return en.is_some()
                    || capitals(keys) >= 2
                    || (self.english(&shown.to_lowercase()).is_none() && literal_shape(keys, false));
            }
            // kiểm tra chính tả đã giữ nguyên phím ngay khi gõ ("server", "testflight"): Telex lẽ ra đã thêm dấu,
            // nên đây là từ nước ngoài → sang tiếng Anh. Từ viết giống nhau ở hai chế độ ("deploy", "ban"): ở lại.
            // Từ tiếng Anh có trong danh sách ("work" → ưởk) thì sang luôn, như Vikey.
            let marked = render(keys, false, false);
            if marked == shown || self.vietnamese(&raw).is_some() {
                // "this create": từ chỉ có tiếng Anh ngay sau một từ gần như chắc là tiếng Anh (D13)
                return en.is_some()
                    && self.vietnamese(&raw).is_none()
                    && self.ambiguous_previous().is_some_and(|(pen, pvn)| pen >= pvn + PLAIN_MARGIN);
            }
            return en.is_some() || self.is_foreign(keys, &marked);
        }
        let vn = self.word_score(shown);
        // 2 chữ hoa trở lên (NAS, HDD) mà Telex biến thành âm tiết hiếm hoặc không có: viết tắt
        if capitals(keys) >= 2
            && vn.unwrap_or(i32::MIN) < ACRONYM_FLOOR
            && shown.chars().any(|c| !c.is_ascii() && is_vowel(c))
        {
            return true; // VĐV, HĐND chỉ có đ: giữ
        }
        // không phải từ tiếng Anh: để kiểm tra chính tả lo, trừ tên riêng không thể là một âm tiết ("Momo" → Môm)
        let Some(en) = en else { return vn.is_none() && literal_shape(keys, true) && self.is_foreign(keys, shown) };
        let Some(vn) = vn else { return true };
        // cặp từ: "cho con bus" → bú, "đi xe bus" → bus
        let vote = self.pair_vote(self.previous_ref(), &raw);
        if vote != 0 {
            return en - vn - vote >= PREFER && (vn < VIETNAMESE_FLOOR || vote <= -PREFER);
        }
        // "video call thí": ngay sau một từ tiếng Anh viết giống nhau ở hai chế độ
        if en - vn >= TIE_AFTER_ENGLISH {
            if let Some(p) = self.previous.as_ref().map(|p| &p.keys) {
                if let Some(praw) = letters_of(p) {
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
        let raw = letters_of(keys)?;
        if let Some(s) = self.shorthand(keys) {
            return Some(s);
        }
        let shown = render(keys, modern, true);
        if shown.chars().eq(keys.iter().copied()) {
            return None;
        }
        let vn = self.word_score(&shown)?;
        let en = self.english(&raw);
        // viết tắt, tên biến; riêng Caps Lock gõ tiếng Việt thì đổi: dấu Telex rõ ràng (THOONG) hoặc ngay sau từ viết hoa (D41)
        if capitals(keys) >= 2 {
            let all_caps = |k: &[char]| k.len() >= 2 && k.iter().all(|c| c.is_uppercase());
            let after_caps = self.previous.as_ref().is_some_and(|p| all_caps(&p.keys));
            if !all_caps(keys) || en.is_some() || vn < CAPS_FLOOR || !((keys.len() >= 4 && telex_marked(&raw)) || after_caps) {
                return None;
            }
        }
        if let Some(en) = en {
            // cặp từ: "cho con bus" → bú; từ trước gõ ở chế độ tiếng Anh nên đọc như chữ đã gõ
            let vote = self.pair_vote(self.previous.as_ref().map(|p| (p.keys.as_slice(), false)), &raw);
            if vn - en + vote < PREFER {
                return None;
            }
            // "the theme", "video call cos": ngay sau một từ rõ là tiếng Anh thì giữ tiếng Anh,
            // trừ khi cặp từ nói rõ là tiếng Việt ("test có work", D34)
            if let Some(p) = self.previous.as_ref().map(|p| &p.keys).filter(|_| vote < PAIR_OVERRIDES_TIE) {
                if let Some(praw) = letters_of(p) {
                    if let Some(pen) = self.english(&praw) {
                        let pshown = render(p, modern, true);
                        let pvn =
                            if pshown.chars().eq(p.iter().copied()) { None } else { self.word_score(&pshown) };
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
fn letters_of(keys: &[char]) -> Option<String> {
    let s: String = keys.iter().collect::<String>().to_lowercase();
    s.chars().all(|c| c.is_ascii_alphabetic()).then_some(s)
}

/// Số chữ hoa; DD tính là một (Đ): "DDaf Nawngx" là Đà Nẵng, còn DDR, DDoS vẫn là hai (D39).
fn capitals(keys: &[char]) -> usize {
    keys.iter().enumerate().filter(|(i, c)| c.is_uppercase() && !(**c == 'D' && *i > 0 && keys[*i - 1] == 'D')).count()
}

/// Có dấu Telex rõ ràng: nguyên âm hoặc d gõ đôi, w sau nguyên âm.
fn telex_marked(raw: &str) -> bool {
    raw.as_bytes().windows(2).any(|w| (w[0] == w[1] && b"aeod".contains(&w[0])) || (w[1] == b'w' && b"aou".contains(&w[0])))
}

/// Dáng không thể là một âm tiết tiếng Việt: chữ hoa giữa từ, hoặc hai cụm nguyên âm cách nhau bởi phụ âm thật
/// (phím thanh và w không tính; `z_is_tone`: z đang là phím bỏ dấu). Có w hay aa/ee/oo/dd thì vẫn là người đang gõ Telex.
fn literal_shape(keys: &[char], z_is_tone: bool) -> bool {
    let low: Vec<char> = keys.iter().map(|&c| lower(c)).collect();
    let capital = keys.windows(2).any(|w| w[1].is_uppercase() && !w[0].is_uppercase());
    if capital && !z_is_tone {
        return true; // Telex đã nuốt phím: currentWindow vẫn là tên biến dù có w
    }
    if low.windows(2).any(|w| w[1] == 'w' || (w[0] == w[1] && "aeod".contains(w[0]))) {
        return false;
    }
    if capital {
        return true;
    }
    let (mut saw_vowel, mut after_consonant) = (false, false);
    for &c in &low {
        if "aeiouy".contains(c) {
            if after_consonant {
                return true;
            }
            saw_vowel = true;
        } else if saw_vowel && !"sfrxjw".contains(c) && !(z_is_tone && c == 'z') {
            after_consonant = true;
        }
    }
    false
}

fn key(word: &str) -> String {
    telex_keys(&word.to_lowercase()).into_iter().collect()
}

fn is_vowel(c: char) -> bool {
    decompose(c).is_some_and(|(l, _)| "aăâeêioôơuưy".contains(l))
}
