//! Bộ gõ Pinyin: tách chuỗi pinyin thành âm tiết, tra từ điển rime-ice (GPL-3.0, pinyin-words.bin),
//! ghép câu bằng Viterbi trên lưới từ, và cho chọn từng phần như các bộ gõ Trung thông thường.
//! Bên trong luôn là giản thể; phồn thể (converter) chỉ áp ở đầu ra: candidates, preedit, kết quả commit.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use crate::bigram::BigramModel;
use crate::convert::ChineseConverter;
use crate::table::{u32_at, SortedTable};
use crate::userdict::PinyinUserDictionary;
use crate::CoreError;

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct PinyinEntry {
    pub word: String,
    pub weight: i64,
}

pub struct PinyinDictionary {
    words: SortedTable,  // "ni hao" → [你好, 拟好...] theo weight giảm dần (pinyin-words.bin)
    abbrev: SortedTable, // "nh" → vị trí các mục trong words: từ 2-4 chữ viết tắt bằng phụ âm đầu
    syllables: HashSet<String>,
    by_prefix: HashMap<String, Vec<String>>, // "zh" → [zha, zhai, ...] (sắp xếp)
    pub total_weight: f64,                   // tổng weight: P(w) = weight / total_weight
}

const MAX_SYLLABLE_LENGTH: usize = 6;

impl PinyinDictionary {
    /// `dir` chứa pinyin-words.bin và pinyin-abbrev.bin (scripts/build-tables.py từ pinyin.tsv).
    pub fn open(dir: &Path) -> Result<PinyinDictionary, CoreError> {
        Ok(Self::new(
            SortedTable::open(&dir.join("pinyin-words.bin"))?,
            SortedTable::open(&dir.join("pinyin-abbrev.bin"))?,
        ))
    }

    pub fn new(words: SortedTable, abbrev: SortedTable) -> PinyinDictionary {
        let mut syllables = HashSet::new();
        for i in 0..words.len() {
            let k = words.key(i);
            if !k.contains(&b' ') {
                syllables.insert(String::from_utf8_lossy(k).into_owned());
            }
        }
        let mut by_prefix: HashMap<String, Vec<String>> = HashMap::new();
        for s in &syllables {
            let chars: Vec<char> = s.chars().collect();
            for n in 1..chars.len() {
                by_prefix.entry(chars[..n].iter().collect()).or_default().push(s.clone());
            }
        }
        // thứ tự cố định để ứng viên cùng weight luôn ra cùng một thứ tự
        for v in by_prefix.values_mut() {
            v.sort();
        }
        let total_weight = words.meta();
        PinyinDictionary { words, abbrev, syllables, by_prefix, total_weight }
    }

    pub fn syllables(&self) -> &HashSet<String> {
        &self.syllables
    }

    pub fn lookup(&self, key: &str) -> Vec<PinyinEntry> {
        let Some(v) = self.words.get(key) else { return vec![] };
        let mut out = vec![];
        let mut o = 0;
        while o < v.len() {
            out.push(Self::entry(v, &mut o));
        }
        out
    }

    fn abbreviation(&self, key: &str) -> Vec<PinyinEntry> {
        let Some(refs) = self.abbrev.get(key) else { return vec![] };
        (0..refs.len())
            .step_by(4)
            .map(|i| {
                let at = u32_at(refs, i);
                let n = self.words.values_at(at, 1)[0] as usize;
                let mut o = 0;
                Self::entry(self.words.values_at(at, 1 + n + 4), &mut o)
            })
            .collect()
    }

    fn completions(&self, prefix: &str) -> &[String] {
        self.by_prefix.get(prefix).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// "ni", "ni hao" là đầu (theo âm tiết) của khoá "ni hao ma": cắt nhánh khi dò.
    fn has_key_prefix(&self, prefix: &str) -> bool {
        let p = prefix.as_bytes();
        let i = self.words.lower_bound(p);
        if i >= self.words.len() {
            return false;
        }
        let k = self.words.key(i);
        if k.len() == p.len() {
            k == p
        } else {
            k.starts_with(p) && k.get(p.len()) == Some(&b' ')
        }
    }

    /// Mục: độ dài từ (1 byte), từ UTF-8, weight (u32).
    fn entry(v: &[u8], o: &mut usize) -> PinyinEntry {
        let n = v[*o] as usize;
        let word = String::from_utf8_lossy(&v[*o + 1..*o + 1 + n]).into_owned();
        let weight = u32_at(v, *o + 1 + n) as i64;
        *o += 1 + n + 4;
        PinyinEntry { word, weight }
    }
}

/// Âm mờ (模糊音): coi hai cách phát âm là một, vd z = zh, in = ing.
#[derive(Clone, Copy, Debug)]
pub struct FuzzyRule {
    pub a: &'static str,
    pub b: &'static str,
    pub is_initial: bool, // phụ âm đầu (thay ở đầu âm tiết) hay vần (thay ở cuối)
}

impl FuzzyRule {
    pub fn id(&self) -> String {
        format!("{}={}", self.a, self.b)
    }

    pub fn label(&self) -> String {
        format!("{} ↔ {}", self.a, self.b)
    }

    pub const ALL: [FuzzyRule; 9] = [
        FuzzyRule { a: "z", b: "zh", is_initial: true },
        FuzzyRule { a: "c", b: "ch", is_initial: true },
        FuzzyRule { a: "s", b: "sh", is_initial: true },
        FuzzyRule { a: "n", b: "l", is_initial: true },
        FuzzyRule { a: "f", b: "h", is_initial: true },
        FuzzyRule { a: "l", b: "r", is_initial: true },
        FuzzyRule { a: "an", b: "ang", is_initial: false },
        FuzzyRule { a: "en", b: "eng", is_initial: false },
        FuzzyRule { a: "in", b: "ing", is_initial: false },
    ];

    /// Âm tiết gõ theo luật mờ → các âm tiết thật trong từ điển. `rules` là các id ("z=zh") đang bật.
    pub fn aliases(rules: &HashSet<String>, syllables: &HashSet<String>) -> HashMap<String, Vec<String>> {
        let active: Vec<&FuzzyRule> = Self::ALL.iter().filter(|r| rules.contains(&r.id())).collect();
        let mut out: HashMap<String, Vec<String>> = HashMap::new();
        if active.is_empty() {
            return out;
        }
        for s in syllables {
            for r in &active {
                let v = if r.is_initial {
                    if let Some(rest) = s.strip_prefix(r.b) {
                        Some(format!("{}{rest}", r.a))
                    } else {
                        s.strip_prefix(r.a).map(|rest| format!("{}{rest}", r.b))
                    }
                } else if let Some(rest) = s.strip_suffix(r.b) {
                    Some(format!("{rest}{}", r.a))
                } else {
                    s.strip_suffix(r.a).map(|rest| format!("{rest}{}", r.b))
                };
                if let Some(v) = v {
                    if &v != s {
                        let list = out.entry(v).or_default();
                        if !list.contains(s) {
                            list.push(s.clone());
                        }
                    }
                }
            }
        }
        for v in out.values_mut() {
            v.sort(); // thứ tự cố định, không theo thứ tự duyệt HashSet
        }
        out
    }
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct PinyinCandidate {
    pub text: String,
    pub length: usize, // số ký tự input (kể cả dấu ') mà ứng viên này dùng hết
}

pub struct PinyinEngine {
    pub dict: Arc<PinyinDictionary>,
    pub max_input: usize,
    fuzzy_rules: HashSet<String>,
    converter: Option<Arc<ChineseConverter>>,
    /// Có thì học từ/cụm người dùng chọn và đưa lên đầu lần sau.
    pub user_dictionary: Option<PinyinUserDictionary>,
    bigram: Option<Arc<BigramModel>>,
    input: Vec<char>,                 // phần pinyin chưa chọn
    chosen: Vec<(String, String)>,    // các đoạn đã chọn (giản thể, phím), chưa commit
    candidates: Vec<PinyinCandidate>, // đã chuyển phồn thể nếu bật
    internal: Vec<PinyinCandidate>,   // giản thể, cùng chỉ số với candidates
    aliases: HashMap<String, Vec<String>>,
}

impl PinyinEngine {
    pub fn new(dict: Arc<PinyinDictionary>) -> PinyinEngine {
        PinyinEngine {
            dict,
            max_input: 48,
            fuzzy_rules: HashSet::new(),
            converter: None,
            user_dictionary: None,
            bigram: None,
            input: vec![],
            chosen: vec![],
            candidates: vec![],
            internal: vec![],
            aliases: HashMap::new(),
        }
    }

    /// Âm mờ đang bật (id của FuzzyRule, vd "z=zh").
    pub fn set_fuzzy_rules(&mut self, rules: HashSet<String>) {
        self.aliases = FuzzyRule::aliases(&rules, &self.dict.syllables);
        self.fuzzy_rules = rules;
        self.refresh();
    }

    pub fn fuzzy_rules(&self) -> &HashSet<String> {
        &self.fuzzy_rules
    }

    /// Có thì đầu ra là phồn thể.
    pub fn set_converter(&mut self, converter: Option<Arc<ChineseConverter>>) {
        self.converter = converter;
        self.refresh();
    }

    pub fn has_converter(&self) -> bool {
        self.converter.is_some()
    }

    /// Có thì ghép câu theo ngữ cảnh (từ trước quyết định từ sau), không thì chỉ theo tần suất.
    pub fn set_bigram(&mut self, bigram: Option<Arc<BigramModel>>) {
        self.bigram = bigram;
        self.refresh();
    }

    pub fn input(&self) -> String {
        self.input.iter().collect()
    }

    pub fn candidates(&self) -> &[PinyinCandidate] {
        &self.candidates
    }

    pub fn is_composing(&self) -> bool {
        !self.input.is_empty() || !self.chosen.is_empty()
    }

    /// Chuỗi hiển thị trong ô gợi ý: phần đã chọn + pinyin còn lại tách âm tiết.
    pub fn preedit(&self) -> String {
        let chosen: String = self.chosen.iter().map(|c| c.0.as_str()).collect();
        self.output(&chosen) + &self.segment_for_display(&self.input)
    }

    pub fn reset(&mut self) {
        self.input.clear();
        self.chosen.clear();
        self.candidates.clear();
        self.internal.clear();
    }

    /// a-z hoặc dấu ' (v thay cho ü).
    pub fn type_char(&mut self, c: char) {
        if self.input.len() >= self.max_input {
            return;
        }
        if c == '\'' && (self.input.is_empty() || self.input.last() == Some(&'\'')) {
            return;
        }
        self.input.push(c);
        self.refresh();
    }

    pub fn backspace(&mut self) {
        if !self.input.is_empty() {
            self.input.pop();
        } else if let Some((_, raw)) = self.chosen.pop() {
            self.input = raw.chars().collect();
        }
        self.refresh();
    }

    /// Chọn ứng viên; trả về chuỗi cần commit khi đã dùng hết input, None nếu còn phải chọn tiếp.
    pub fn select(&mut self, index: usize) -> Option<String> {
        let c = self.internal.get(index)?.clone();
        let raw: String = self.input[..c.length].iter().collect();
        if let Some(ud) = &mut self.user_dictionary {
            ud.record(&letters(&raw), &c.text);
        }
        self.chosen.push((c.text, raw));
        self.input.drain(..c.length);
        while self.input.first() == Some(&'\'') {
            self.input.remove(0);
        }
        if self.input.is_empty() {
            let text: String = self.chosen.iter().map(|c| c.0.as_str()).collect();
            // cụm ghép từ nhiều lần chọn: học cả cụm để lần sau ra một phát
            if self.chosen.len() >= 2 && text.chars().count() <= 10 {
                let raw: String = self.chosen.iter().map(|c| c.1.as_str()).collect();
                if let Some(ud) = &mut self.user_dictionary {
                    ud.record(&letters(&raw), &text);
                }
            }
            self.reset();
            return Some(self.output(&text));
        }
        self.refresh();
        None
    }

    /// Enter: commit phần đã chọn + pinyin thô còn lại.
    pub fn commit_raw(&mut self) -> String {
        let chosen: String = self.chosen.iter().map(|c| c.0.as_str()).collect();
        let text = self.output(&chosen) + &letters(&self.input());
        self.reset();
        text
    }

    fn output(&self, simplified: &str) -> String {
        match &self.converter {
            Some(c) => c.convert(simplified),
            None => simplified.to_string(),
        }
    }

    fn refresh(&mut self) {
        if self.input.is_empty() {
            self.candidates.clear();
            self.internal.clear();
            return;
        }
        let mut list = candidates(&self.input, &self.dict, &self.aliases, self.bigram.as_deref());
        if let Some(ud) = &self.user_dictionary {
            // từ/cụm đã học cho đúng chuỗi đang gõ lên đầu
            let learned: Vec<PinyinCandidate> = ud
                .words(&letters(&self.input()))
                .into_iter()
                .map(|text| PinyinCandidate { text, length: self.input.len() })
                .collect();
            if !learned.is_empty() {
                let top: HashSet<String> = learned.iter().map(|c| c.text.clone()).collect();
                list.retain(|c| !top.contains(&c.text));
                list.splice(0..0, learned);
            }
        }
        self.internal.clear();
        self.candidates.clear();
        let mut seen = HashSet::new();
        for c in list {
            let shown = self.output(&c.text);
            if seen.insert(shown.clone()) {
                self.candidates.push(PinyinCandidate { text: shown, length: c.length });
                self.internal.push(c);
            }
        }
    }

    /// "nihao" → "ni hao" (tách tham lam, dài nhất trước; âm mờ cũng tính là âm tiết).
    pub fn segment_for_display(&self, s: &[char]) -> String {
        let is_syllable = |x: &str| self.dict.syllables.contains(x) || self.aliases.contains_key(x);
        let mut out: Vec<String> = vec![];
        let mut i = 0;
        while i < s.len() {
            if s[i] == '\'' {
                out.push("'".into());
                i += 1;
                continue;
            }
            let mut len = MAX_SYLLABLE_LENGTH.min(s.len() - i);
            while len > 1 && !is_syllable(&s[i..i + len].iter().collect::<String>()) {
                len -= 1;
            }
            out.push(s[i..i + len].iter().collect());
            i += len;
        }
        out.join(" ").replace(" ' ", "'")
    }
}

pub(crate) fn letters(raw: &str) -> String {
    raw.replace('\'', "")
}

// MARK: - Candidate generation

struct WordMatch {
    end: usize,
    entries: Vec<PinyinEntry>,
}

/// Mọi từ trong từ điển bắt đầu tại `start` (đi theo lưới âm tiết, tối đa 8 âm tiết).
/// `aliases`: âm tiết gõ theo âm mờ → âm tiết thật; từ tìm qua âm mờ bị hạ weight để âm đúng thắng.
fn words_from(
    start: usize,
    s: &[char],
    dict: &PinyinDictionary,
    aliases: &HashMap<String, Vec<String>>,
) -> Vec<WordMatch> {
    let mut out = vec![];
    fn walk(
        pos: usize,
        prefix: &mut Vec<String>,
        s: &[char],
        dict: &PinyinDictionary,
        aliases: &HashMap<String, Vec<String>>,
        out: &mut Vec<WordMatch>,
    ) {
        if prefix.len() >= 8 {
            return;
        }
        let mut p = pos;
        while p < s.len() && s[p] == '\'' {
            p += 1;
        }
        if p >= s.len() {
            return;
        }
        let mut len = 1;
        while len <= MAX_SYLLABLE_LENGTH && p + len <= s.len() {
            let piece = &s[p..p + len];
            if piece.contains(&'\'') {
                break;
            }
            let syl: String = piece.iter().collect();
            let end = p + len;
            let mut options: Vec<(&str, bool)> = vec![];
            if dict.syllables.contains(&syl) {
                options.push((&syl, false));
            }
            if let Some(list) = aliases.get(&syl) {
                for a in list {
                    options.push((a, true));
                }
            }
            for (syllable, fuzzy) in options {
                prefix.push(syllable.to_string());
                let joined = prefix.join(" ");
                if dict.has_key_prefix(&joined) {
                    let found = dict.lookup(&joined);
                    if !found.is_empty() {
                        let entries = if fuzzy {
                            found.into_iter().map(|e| PinyinEntry { word: e.word, weight: e.weight / 8 }).collect()
                        } else {
                            found
                        };
                        out.push(WordMatch { end, entries });
                    }
                    walk(end, prefix, s, dict, aliases, out);
                }
                prefix.pop();
            }
            // âm tiết cuối chưa gõ xong: "nih" → ni + (ha, hai, hao, ...)
            if end == s.len() {
                let mut found: Vec<PinyinEntry> = vec![];
                for comp in dict.completions(&syl) {
                    prefix.push(comp.clone());
                    found.extend(dict.lookup(&prefix.join(" ")).into_iter().take(20));
                    prefix.pop();
                }
                if !found.is_empty() {
                    found.sort_by_key(|e| std::cmp::Reverse(e.weight));
                    out.push(WordMatch { end, entries: found });
                }
            }
            len += 1;
        }
    }
    walk(start, &mut vec![], s, dict, aliases, &mut out);
    out
}

#[derive(Clone)]
struct Hyp {
    score: f64,
    word: String,
    prev: Option<(usize, usize)>,
    words: usize,
}

pub(crate) fn candidates(
    s: &[char],
    dict: &PinyinDictionary,
    aliases: &HashMap<String, Vec<String>>,
    bigram: Option<&BigramModel>,
) -> Vec<PinyinCandidate> {
    let n = s.len();
    let mut list: Vec<PinyinCandidate> = vec![];
    let mut seen: HashSet<String> = HashSet::new();
    let mut add = |text: &str, length: usize, list: &mut Vec<PinyinCandidate>| {
        if seen.insert(text.to_string()) {
            list.push(PinyinCandidate { text: text.to_string(), length });
        }
    };

    // Viết tắt toàn phụ âm đầu: "nh" → 你好
    let letters: Vec<char> = s.iter().copied().filter(|&c| c != '\'').collect();
    if (2..=4).contains(&letters.len()) && !letters.iter().any(|c| "aeiouv".contains(*c)) {
        for e in dict.abbreviation(&letters.iter().collect::<String>()).into_iter().take(10) {
            add(&e.word, n, &mut list);
        }
    }

    // Ghép câu: Viterbi trái→phải trên lưới từ, mỗi vị trí giữ `beam` giả thuyết tốt nhất;
    // điểm = Σ log P(w | từ trước) (bigram, hoặc chỉ unigram khi không có mô hình).
    let matches_at: Vec<Vec<WordMatch>> = (0..n).map(|i| words_from(i, s, dict, aliases)).collect();
    let beam = 8;
    let alternatives = if bigram.is_none() { 1 } else { 5 };
    let mut hyps: Vec<Vec<Hyp>> = vec![vec![]; n + 1];
    hyps[0] = vec![Hyp { score: 0.0, word: String::new(), prev: None, words: 0 }];
    fn push(hyps: &mut [Vec<Hyp>], h: Hyp, pos: usize, beam: usize) {
        let list = &mut hyps[pos];
        if list.len() >= beam {
            // giả thuyết kém nhất đầu tiên (như min(by:) của Swift)
            let mut worst = 0;
            for i in 1..list.len() {
                if list[i].score < list[worst].score {
                    worst = i;
                }
            }
            if h.score <= list[worst].score {
                return;
            }
            list.remove(worst);
        }
        list.push(h);
    }
    for i in 0..n {
        if s[i] == '\'' {
            let carried = hyps[i].clone();
            for h in carried {
                push(&mut hyps, h, i + 1, beam);
            }
            continue;
        }
        if hyps[i].is_empty() {
            continue;
        }
        let here = hyps[i].clone();
        for m in &matches_at[i] {
            for e in m.entries.iter().take(alternatives) {
                let p = e.weight.max(1) as f64 / dict.total_weight;
                for (hi, h) in here.iter().enumerate() {
                    let lp = match (h.prev, bigram) {
                        (Some(_), Some(b)) => b.log_prob(&h.word, &e.word, p),
                        _ => p.ln(),
                    };
                    push(
                        &mut hyps,
                        Hyp { score: h.score + lp, word: e.word.clone(), prev: Some((i, hi)), words: h.words + 1 },
                        m.end,
                        beam,
                    );
                }
            }
        }
    }
    // giả thuyết tốt nhất đầu tiên (như max(by:) của Swift)
    let mut best: Option<&Hyp> = None;
    for h in &hyps[n] {
        if best.is_none_or(|b| b.score < h.score) {
            best = Some(h);
        }
    }
    if let Some(last) = best.filter(|h| h.words > 1) {
        let mut parts: Vec<&str> = vec![];
        let mut cur = Some(last);
        while let Some(h) = cur {
            let Some((pos, idx)) = h.prev else { break };
            parts.push(&h.word);
            cur = Some(&hyps[pos][idx]);
        }
        parts.reverse();
        add(&parts.concat(), n, &mut list);
    }

    // Từ bắt đầu ở đầu chuỗi: dài trước, rồi theo weight
    let mut starts: Vec<&WordMatch> = matches_at.first().map(|m| m.iter().collect()).unwrap_or_default();
    starts.sort_by_key(|m| std::cmp::Reverse(m.end));
    let mut by_end: BTreeMap<usize, Vec<&PinyinEntry>> = BTreeMap::new();
    for m in starts {
        by_end.entry(m.end).or_default().extend(m.entries.iter());
    }
    for (&end, entries) in by_end.iter_mut().rev() {
        entries.sort_by_key(|e| std::cmp::Reverse(e.weight));
        for e in entries.iter().take(60) {
            add(&e.word, end, &mut list);
        }
    }
    list.truncate(200);
    list
}
