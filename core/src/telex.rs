//! Bộ gõ Telex: mỗi phím gõ được xử lý lại từ đầu trên chuỗi phím thô của từ hiện tại,
//! rồi so với chuỗi đang hiển thị để ra số backspace + chuỗi cần chèn.
//! Bảng nguyên âm hợp lệ lấy theo VSeqList của Unikey (ukengine.cpp, GPL).

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, OnceLock};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tone {
    None = 0,
    Acute,
    Grave,
    Hook,
    Tilde,
    Dot,
}

impl Tone {
    const ALL: [Tone; 6] = [Tone::None, Tone::Acute, Tone::Grave, Tone::Hook, Tone::Tilde, Tone::Dot];

    fn from_telex_key(k: char) -> Option<Tone> {
        match k {
            's' => Some(Tone::Acute),
            'f' => Some(Tone::Grave),
            'r' => Some(Tone::Hook),
            'x' => Some(Tone::Tilde),
            'j' => Some(Tone::Dot),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Mark {
    None,
    Circumflex,
    Breve,
    Horn,
    Stroke,
}

#[derive(Clone, Copy, PartialEq, Debug)]
struct VChar {
    base: char, // a-z, chữ thường
    mark: Mark,
    upper: bool,
    from_w: bool, // ư sinh ra từ phím w đứng riêng
}

impl VChar {
    fn new(base: char, upper: bool) -> VChar {
        VChar { base, mark: Mark::None, upper, from_w: false }
    }

    fn is_vowel(&self) -> bool {
        "aeiouy".contains(self.base)
    }

    /// Chữ không dấu thanh, vd "ơ", "đ".
    fn letter(&self) -> char {
        match (self.base, self.mark) {
            ('a', Mark::Circumflex) => 'â',
            ('a', Mark::Breve) => 'ă',
            ('e', Mark::Circumflex) => 'ê',
            ('o', Mark::Circumflex) => 'ô',
            ('o', Mark::Horn) => 'ơ',
            ('u', Mark::Horn) => 'ư',
            ('d', Mark::Stroke) => 'đ',
            (b, _) => b,
        }
    }
}

/// Kết quả của một phím: xoá `backspaces` ký tự trước con trỏ rồi chèn `insert`.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct TextEdit {
    pub backspaces: usize,
    pub insert: String,
}

impl TextEdit {
    pub fn new(backspaces: usize, insert: impl Into<String>) -> TextEdit {
        TextEdit { backspaces, insert: insert.into() }
    }
}

pub(crate) fn lower(c: char) -> char {
    c.to_lowercase().next().unwrap_or(c)
}

fn upper_str(c: char) -> String {
    c.to_uppercase().collect()
}

pub struct TelexEngine {
    /// true: đặt dấu kiểu mới (hoà, khoẻ, thuý); false: kiểu cũ (hòa, khỏe, thúy) — mặc định như Unikey.
    pub modern_tone_style: bool,
    /// false: bỏ kiểm tra chính tả — mọi phím dấu đều được áp dụng, không trả lại chữ tiếng Anh.
    pub spell_check: bool,
    /// Có danh sách âm tiết thì khi kết thúc từ, chữ không phải tiếng Việt được trả lại như đã gõ.
    pub lexicon: Option<Arc<VietnameseLexicon>>,
    keys: Vec<char>,   // phím thô của từ hiện tại (giữ hoa/thường)
    output: Vec<char>, // chuỗi đang hiển thị cho từ hiện tại
}

impl Default for TelexEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl TelexEngine {
    pub fn new() -> TelexEngine {
        TelexEngine { modern_tone_style: false, spell_check: true, lexicon: None, keys: vec![], output: vec![] }
    }

    pub fn keys(&self) -> &[char] {
        &self.keys
    }

    pub fn output(&self) -> String {
        self.output.iter().collect()
    }

    pub fn output_len(&self) -> usize {
        self.output.len()
    }

    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }

    pub fn reset(&mut self) {
        self.keys.clear();
        self.output.clear();
    }

    /// Xử lý một chữ cái a-z/A-Z. Ký tự khác: caller phải reset() vì là ranh giới từ.
    pub fn type_key(&mut self, key: char) -> TextEdit {
        self.keys.push(key);
        let new = render(&self.keys, self.modern_tone_style, self.spell_check);
        self.update(new.chars().collect())
    }

    /// Kết thúc từ (Space, dấu câu, Enter…) rồi reset. Chữ có dấu mà không phải âm tiết tiếng Việt có thật
    /// thì trả về sửa đổi để gõ lại đúng các phím đã gõ ("ủe" → "user"). Giữ nguyên chữ ASCII — kể cả khi
    /// người gõ dùng phím đôi để bỏ dấu ("tessting" → "testing") — và chữ không có nguyên âm ("100đ").
    pub fn finish_word(&mut self) -> Option<TextEdit> {
        let result = self.restore_edit();
        self.reset();
        result
    }

    fn restore_edit(&self) -> Option<TextEdit> {
        let lexicon = self.lexicon.as_ref()?;
        if !self.spell_check || self.output == self.keys || self.output.iter().all(|c| c.is_ascii()) {
            return None;
        }
        let has_vowel = self.output.iter().any(|&c| decompose(c).is_some_and(|(l, _)| "aăâeêioôơuưy".contains(l)));
        let output = self.output();
        if !has_vowel || lexicon.contains(&output) {
            return None;
        }
        Some(TextEdit::new(self.output.len(), self.keys.iter().collect::<String>()))
    }

    /// Backspace đã được gửi cho ứng dụng (không chặn): xoá ký tự cuối và dựng lại phím thô.
    pub fn backspace(&mut self) {
        if self.output.is_empty() {
            self.keys.clear();
            return;
        }
        self.output.pop();
        let output = self.output();
        self.keys = telex_keys(&output);
        // Chuỗi dựng lại phải hiển thị y hệt; nếu không (hiếm) thì coi như nhập lại từ đầu.
        if render(&self.keys, self.modern_tone_style, self.spell_check) != output {
            self.keys = self.output.clone();
        }
    }

    fn update(&mut self, new: Vec<char>) -> TextEdit {
        let common = self.output.iter().zip(&new).take_while(|(a, b)| a == b).count();
        let edit = TextEdit::new(self.output.len() - common, new[common..].iter().collect::<String>());
        self.output = new;
        edit
    }

    /// Kết thúc từ bằng gõ tắt: khớp chữ đang hiện, phím thô, hoặc chữ dựng không kiểm tra chính tả
    /// (để "ddc" khớp từ khoá "đc"). Có thì trả về sửa đổi thay cả từ và reset.
    pub fn expand_macro(&mut self, macros: &MacroTable) -> Option<TextEdit> {
        if self.is_empty() {
            return None;
        }
        let raw: String = self.keys.iter().collect();
        let candidates = [self.output(), raw, render(&self.keys, self.modern_tone_style, false)];
        let text = candidates.iter().find_map(|c| macros.expansion(c))?;
        let edit = TextEdit::new(self.output.len(), text);
        self.reset();
        Some(edit)
    }
}

// MARK: - Render

/// Dựng chuỗi hiển thị từ chuỗi phím thô.
pub fn render(keys: &[char], modern: bool, spell_check: bool) -> String {
    let mut s = State { spell_check, chars: vec![], tone: Tone::None, literal: false };
    for &k in keys {
        s.apply(k);
    }
    if s.literal || s.acceptable() {
        s.text(modern)
    } else {
        keys.iter().collect()
    }
}

#[derive(Clone)]
struct State {
    spell_check: bool,
    chars: Vec<VChar>,
    tone: Tone,
    literal: bool, // sau khi gõ huỷ (aaa, ss, ww...) thì các phím sau là chữ thường
}

impl State {
    /// Tắt kiểm tra chính tả thì chữ nào cũng được biến đổi.
    fn acceptable(&self) -> bool {
        !self.spell_check || self.is_valid()
    }

    fn append(&mut self, k: char) {
        self.chars.push(VChar::new(lower(k), k.is_uppercase()));
    }

    fn apply(&mut self, key: char) {
        let k = lower(key);
        // từ đã sai chính tả (đang hiện phím thô) thì không biến đổi nữa
        if self.literal || !k.is_ascii() || !k.is_alphabetic() || !self.acceptable() {
            self.append(key);
            return;
        }
        // chỉ nhận biến đổi nếu kết quả còn hợp lệ (vd "ngoeo": o thứ hai là chữ, không phải ô)
        let mut t = self.clone();
        if t.transform(key, k) && (t.literal || t.acceptable()) {
            *self = t;
        } else {
            self.append(key);
        }
    }

    /// false: phím không phải phím biến đổi.
    fn transform(&mut self, key: char, k: char) -> bool {
        let parts = Syllable::new(&self.chars);

        if let Some(t) = Tone::from_telex_key(k) {
            if !parts.vowels.is_empty() {
                if self.tone == t {
                    self.tone = Tone::None;
                    self.append(key);
                    self.literal = true;
                } else {
                    self.tone = t;
                }
                return true;
            }
        }
        if k == 'z' && self.tone != Tone::None && !parts.vowels.is_empty() {
            self.tone = Tone::None;
            return true;
        }
        if k == 'd' && self.chars.first().is_some_and(|c| c.base == 'd') {
            if self.chars[0].mark == Mark::Stroke {
                self.chars[0].mark = Mark::None;
                self.append(key);
                self.literal = true;
            } else {
                self.chars[0].mark = Mark::Stroke;
            }
            return true;
        }
        if "aeo".contains(k) {
            if let Some(&i) = parts.vowels.iter().rev().find(|&&i| self.chars[i].base == k) {
                if self.chars[i].mark == Mark::Circumflex {
                    self.chars[i].mark = Mark::None;
                    self.append(key);
                    self.literal = true;
                } else {
                    self.chars[i].mark = Mark::Circumflex;
                }
                return true;
            }
        }
        if k == 'w' {
            return self.apply_w(key, &parts);
        }
        false
    }

    fn apply_w(&mut self, key: char, parts: &Syllable) -> bool {
        let v = &parts.vowels;
        // ư sinh từ w đứng riêng: gõ w lần nữa thì trả lại chữ w
        if let Some(&i) = v.iter().find(|&&i| self.chars[i].from_w) {
            self.chars[i] = VChar::new('w', self.chars[i].upper);
            self.literal = true;
            return true;
        }
        if v.is_empty() {
            if !parts.final_.is_empty() || parts.initial == "q" || parts.initial == "qu" {
                return false;
            }
            self.chars.push(VChar { base: 'u', mark: Mark::Horn, upper: key.is_uppercase(), from_w: true });
            return true;
        }
        let cluster: String = v.iter().map(|&i| self.chars[i].base).collect();
        let Some(marks) = horn_marks(&cluster) else { return false };
        let current: Vec<Mark> = v.iter().map(|&i| self.chars[i].mark).collect();
        if current.iter().zip(marks).all(|(c, m)| *m == Mark::None || c == m) {
            // đã có đủ dấu móc/trăng → huỷ
            for (&i, m) in v.iter().zip(marks) {
                if *m != Mark::None {
                    self.chars[i].mark = Mark::None;
                }
            }
            self.append(key);
            self.literal = true;
        } else {
            for (&i, m) in v.iter().zip(marks) {
                if *m != Mark::None {
                    self.chars[i].mark = *m;
                }
            }
        }
        true
    }

    fn is_valid(&self) -> bool {
        let p = Syllable::new(&self.chars);
        if !p.ok {
            return false;
        }
        if p.vowels.is_empty() {
            return p.final_.is_empty();
        }
        let cluster: String = p.vowels.iter().map(|&i| self.chars[i].letter()).collect();
        if !tables().vowel_clusters.contains(cluster.as_str()) {
            return false;
        }
        if !p.final_.is_empty() {
            if !FINALS.contains(&p.final_.as_str()) || !tables().clusters_taking_final.contains(cluster.as_str()) {
                return false;
            }
            if ["c", "ch", "p", "t"].contains(&p.final_.as_str())
                && ![Tone::None, Tone::Acute, Tone::Dot].contains(&self.tone)
            {
                return false;
            }
        }
        true
    }

    fn text(&self, modern: bool) -> String {
        let mut cs = self.chars.clone();
        let p = Syllable::new(&cs);
        // "ưo"/"uơ" + phụ âm cuối / i / u → "ươ" (người, được, rượu)
        let v = &p.vowels;
        if v.len() >= 2
            && cs[v[0]].base == 'u'
            && cs[v[1]].base == 'o'
            && (v.len() == 3 || !p.final_.is_empty())
            && (cs[v[0]].mark == Mark::Horn || cs[v[1]].mark == Mark::Horn)
        {
            cs[v[0]].mark = Mark::Horn;
            cs[v[1]].mark = Mark::Horn;
        }
        let mut out: Vec<String> =
            cs.iter().map(|c| if c.upper { upper_str(c.letter()) } else { c.letter().to_string() }).collect();
        if self.tone != Tone::None {
            if let Some(i) = tone_position(&cs, &p, modern) {
                out[i] = toned(cs[i].letter(), self.tone, cs[i].upper).to_string();
            }
        }
        out.concat()
    }
}

fn tone_position(cs: &[VChar], p: &Syllable, modern: bool) -> Option<usize> {
    let v = &p.vowels;
    if v.is_empty() {
        return None;
    }
    if let Some(&marked) = v.iter().rev().find(|&&i| cs[i].mark != Mark::None) {
        return Some(marked);
    }
    if v.len() == 1 {
        return Some(v[0]);
    }
    if !p.final_.is_empty() {
        return v.last().copied();
    }
    if v.len() >= 3 {
        return Some(v[1]);
    }
    let pair: String = v.iter().map(|&i| cs[i].base).collect();
    if ["oa", "oe", "uy"].contains(&pair.as_str()) {
        return Some(if modern { v[1] } else { v[0] });
    }
    Some(v[0])
}

fn horn_marks(cluster: &str) -> Option<&'static [Mark]> {
    use Mark::{Breve, Horn, None as N};
    Some(match cluster {
        "a" => &[Breve],
        "o" => &[Horn],
        "u" => &[Horn],
        "oa" => &[N, Breve],
        "oi" => &[Horn, N],
        "ua" => &[Horn, N],
        "ui" => &[Horn, N],
        // uo + w → uơ (thuở, huơ); có âm theo sau thì text() đổi thành ươ (người, được)
        "uo" => &[N, Horn],
        "uu" => &[Horn, N],
        "uoi" => &[N, Horn, N],
        "uou" => &[N, Horn, N],
        _ => return None,
    })
}

// MARK: - Ngược: chuỗi tiếng Việt → phím Telex (dùng khi backspace)

pub fn telex_keys(word: &str) -> Vec<char> {
    let mut keys = vec![];
    let mut tone = Tone::None;
    for ch in word.chars() {
        let Some((letter, t)) = decompose(ch) else {
            keys.push(ch);
            continue;
        };
        if t != Tone::None {
            tone = t;
        }
        let upper = ch.is_uppercase();
        let put = |keys: &mut Vec<char>, s: &str| {
            for c in s.chars() {
                if upper {
                    keys.extend(c.to_uppercase());
                } else {
                    keys.push(c);
                }
            }
        };
        match letter {
            'â' => put(&mut keys, "aa"),
            'ă' => put(&mut keys, "aw"),
            'ê' => put(&mut keys, "ee"),
            'ô' => put(&mut keys, "oo"),
            'ơ' => put(&mut keys, "ow"),
            'ư' => put(&mut keys, "uw"),
            'đ' => put(&mut keys, "dd"),
            l => put(&mut keys, &l.to_string()),
        }
    }
    match tone {
        Tone::None => {}
        Tone::Acute => keys.push('s'),
        Tone::Grave => keys.push('f'),
        Tone::Hook => keys.push('r'),
        Tone::Tilde => keys.push('x'),
        Tone::Dot => keys.push('j'),
    }
    keys
}

/// Các âm tiết tiếng Việt có thật (mỗi dòng một âm tiết). So khớp không phân biệt hoa/thường
/// và vị trí dấu thanh ("hòa" = "hoà").
pub struct VietnameseLexicon {
    entries: HashSet<String>,
}

impl VietnameseLexicon {
    pub fn new(text: &str) -> VietnameseLexicon {
        let entries = text.split(is_newline).filter(|l| !l.is_empty()).map(Self::key).collect();
        VietnameseLexicon { entries }
    }

    pub fn contains(&self, syllable: &str) -> bool {
        self.entries.contains(&Self::key(syllable))
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    fn key(s: &str) -> String {
        telex_keys(&s.to_lowercase()).into_iter().collect()
    }
}

/// Như Character.isNewline của Swift.
pub(crate) fn is_newline(c: char) -> bool {
    matches!(c, '\n' | '\r' | '\u{0B}' | '\u{0C}' | '\u{85}' | '\u{2028}' | '\u{2029}')
}

/// Tách âm tiết: phụ âm đầu / cụm nguyên âm / phụ âm cuối.
struct Syllable {
    initial: String,
    vowels: Vec<usize>,
    final_: String,
    ok: bool,
}

impl Syllable {
    fn new(cs: &[VChar]) -> Syllable {
        let b: Vec<char> = cs.iter().map(|c| if c.mark == Mark::Stroke { 'đ' } else { c.base }).collect();
        let mut s = Syllable { initial: String::new(), vowels: vec![], final_: String::new(), ok: true };
        let mut i = 0;
        for cons in INITIALS {
            let cc: Vec<char> = cons.chars().collect();
            if b.len() >= cc.len() && b[..cc.len()] == cc[..] {
                let mut n = cc.len();
                if *cons == "gi" && !(b.len() > 2 && cs[2].is_vowel()) {
                    n = 1; // "gì": i là nguyên âm
                }
                if *cons == "qu" && cs[1].mark != Mark::None {
                    n = 1;
                }
                s.initial = b[..n].iter().collect();
                i = n;
                break;
            }
        }
        while i < cs.len() && cs[i].is_vowel() {
            s.vowels.push(i);
            i += 1;
        }
        s.final_ = b[i..].iter().collect();
        if s.final_.chars().any(|c| "aeiouy".contains(c)) {
            s.ok = false;
        }
        s
    }
}

// dài trước ngắn để khớp tham lam
const INITIALS: &[&str] = &[
    "ngh", "ng", "nh", "ch", "gh", "gi", "kh", "ph", "th", "tr", "qu", "b", "c", "d", "đ", "g", "h", "k", "l", "m",
    "n", "p", "q", "r", "s", "t", "v", "x",
];

const FINALS: &[&str] = &["c", "ch", "m", "n", "ng", "nh", "p", "t"];

// VSeqList của Unikey (gồm cả dạng chưa hoàn chỉnh khi đang gõ)
const VOWEL_CLUSTERS: &[&str] = &[
    "a", "â", "ă", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y", "ai", "ao", "au", "ay", "âu", "ây", "eo", "eu", "êu",
    "ia", "ie", "iê", "iu", "oa", "oă", "oe", "oi", "ôi", "ơi", "oo", "ua", "uâ", "ue", "uê", "ui", "uo", "uô", "uơ",
    "uu", "uy", "ưa", "ưi", "ưo", "ươ", "ưu", "ye", "yê", "ieu", "iêu", "oai", "oay", "oeo", "uay", "uây", "uoi",
    "uou", "uôi", "uơi", "uơu", "uya", "uye", "uyê", "uyu", "ưoi", "ưou", "ươi", "ươu", "yeu", "yêu",
];

const CLUSTERS_TAKING_FINAL: &[&str] = &[
    "a", "â", "ă", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y", "ie", "iê", "oa", "oă", "oe", "oo", "ua", "uâ", "ue",
    "uê", "uo", "uô", "uơ", "uy", "ưo", "ươ", "ye", "yê", "uye", "uyê",
];

// thứ tự: không dấu, sắc, huyền, hỏi, ngã, nặng
const LOWER_TABLE: &[(char, &str)] = &[
    ('a', "aáàảãạ"),
    ('ă', "ăắằẳẵặ"),
    ('â', "âấầẩẫậ"),
    ('e', "eéèẻẽẹ"),
    ('ê', "êếềểễệ"),
    ('i', "iíìỉĩị"),
    ('o', "oóòỏõọ"),
    ('ô', "ôốồổỗộ"),
    ('ơ', "ơớờởỡợ"),
    ('u', "uúùủũụ"),
    ('ư', "ưứừửữự"),
    ('y', "yýỳỷỹỵ"),
];
const UPPER_TABLE: &[(char, &str)] = &[
    ('a', "AÁÀẢÃẠ"),
    ('ă', "ĂẮẰẲẴẶ"),
    ('â', "ÂẤẦẨẪẬ"),
    ('e', "EÉÈẺẼẸ"),
    ('ê', "ÊẾỀỂỄỆ"),
    ('i', "IÍÌỈĨỊ"),
    ('o', "OÓÒỎÕỌ"),
    ('ô', "ÔỐỒỔỖỘ"),
    ('ơ', "ƠỚỜỞỠỢ"),
    ('u', "UÚÙỦŨỤ"),
    ('ư', "ƯỨỪỬỮỰ"),
    ('y', "YÝỲỶỸỴ"),
];

struct Tables {
    vowel_clusters: HashSet<&'static str>,
    clusters_taking_final: HashSet<&'static str>,
    lower: HashMap<char, Vec<char>>,
    upper: HashMap<char, Vec<char>>,
    decompose: HashMap<char, (char, Tone)>,
}

fn tables() -> &'static Tables {
    static T: OnceLock<Tables> = OnceLock::new();
    T.get_or_init(|| {
        let row = |t: &[(char, &str)]| t.iter().map(|(l, r)| (*l, r.chars().collect::<Vec<char>>())).collect();
        let lower: HashMap<char, Vec<char>> = row(LOWER_TABLE);
        let upper: HashMap<char, Vec<char>> = row(UPPER_TABLE);
        let mut decompose = HashMap::new();
        for table in [&lower, &upper] {
            for (letter, chars) in table {
                for (i, c) in chars.iter().enumerate() {
                    decompose.insert(*c, (*letter, Tone::ALL[i]));
                }
            }
        }
        decompose.insert('đ', ('đ', Tone::None));
        decompose.insert('Đ', ('đ', Tone::None));
        Tables {
            vowel_clusters: VOWEL_CLUSTERS.iter().copied().collect(),
            clusters_taking_final: CLUSTERS_TAKING_FINAL.iter().copied().collect(),
            lower,
            upper,
            decompose,
        }
    })
}

fn toned(letter: char, tone: Tone, upper: bool) -> char {
    let t = tables();
    match (if upper { &t.upper } else { &t.lower }).get(&letter) {
        Some(row) => row[tone as usize],
        None => letter,
    }
}

/// Ký tự tiếng Việt → (chữ thường không dấu thanh, dấu thanh). None nếu không phải chữ cái.
pub(crate) fn decompose(ch: char) -> Option<(char, Tone)> {
    if let Some(r) = tables().decompose.get(&ch) {
        return Some(*r);
    }
    if ch.is_ascii_alphabetic() {
        return Some((ch.to_ascii_lowercase(), Tone::None));
    }
    None
}

/// Gõ tắt: gõ xong từ khoá (đứng riêng) rồi Space/Enter/Tab thì từ khoá được thay bằng cụm đầy đủ ("vn" → "Việt Nam").
/// Không phân biệt hoa/thường; gõ từ khoá viết hoa chữ đầu / viết hoa toàn bộ thì cụm thay cũng vậy.
#[derive(Default, Clone)]
pub struct MacroTable {
    exact: HashMap<String, String>,
    folded: HashMap<String, String>,
}

impl MacroTable {
    pub fn new<K: AsRef<str>, T: AsRef<str>>(pairs: &[(K, T)]) -> MacroTable {
        let mut m = MacroTable::default();
        for (key, text) in pairs {
            let (key, text) = (key.as_ref(), text.as_ref());
            if key.is_empty() || text.is_empty() {
                continue;
            }
            m.exact.insert(key.to_string(), text.to_string());
            m.folded.entry(key.to_lowercase()).or_insert_with(|| text.to_string());
        }
        m
    }

    pub fn is_empty(&self) -> bool {
        self.exact.is_empty()
    }

    /// Cụm thay thế cho từ vừa gõ, hoặc None.
    pub fn expansion(&self, word: &str) -> Option<String> {
        if let Some(text) = self.exact.get(word) {
            return Some(text.clone());
        }
        let text = self.folded.get(&word.to_lowercase())?;
        let letters: Vec<char> = word.chars().filter(|c| c.is_alphabetic()).collect();
        if letters.len() > 1 && letters.iter().all(|c| c.is_uppercase()) {
            return Some(text.to_uppercase());
        }
        if word.chars().next().is_some_and(|c| c.is_uppercase()) {
            let mut cs = text.chars();
            let first: String = cs.next().map(|c| c.to_uppercase().collect()).unwrap_or_default();
            return Some(first + cs.as_str());
        }
        Some(text.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn type_word(keys: &str, modern: bool) -> String {
        let mut e = TelexEngine::new();
        e.modern_tone_style = modern;
        let mut text: Vec<char> = vec![];
        for k in keys.chars() {
            let edit = e.type_key(k);
            text.truncate(text.len() - edit.backspaces);
            text.extend(edit.insert.chars());
        }
        assert_eq!(text.iter().collect::<String>(), e.output());
        e.output()
    }

    #[test]
    fn basics() {
        for (keys, want) in [
            ("aa", "â"),
            ("w", "ư"),
            ("nguwowif", "người"),
            ("dduowcj", "được"),
            ("tosan", "toán"),
            ("ass", "as"),
            ("www", "ww"),
            ("NGUWOWIF", "NGƯỜI"),
            ("class", "class"),
            ("khuyur", "khuỷu"),
        ] {
            assert_eq!(type_word(keys, false), want, "{keys}");
        }
        assert_eq!(type_word("hoaf", true), "hoà");
    }

    #[test]
    fn tables_are_single_scalars() {
        for (_, row) in LOWER_TABLE.iter().chain(UPPER_TABLE) {
            assert_eq!(row.chars().count(), 6, "{row}");
        }
    }
}
