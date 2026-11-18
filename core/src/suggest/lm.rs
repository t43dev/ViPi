//! Mô hình từ cho thanh gợi ý: cách gõ tiếp từ đang gõ, từ tiếp theo, xác suất chữ/phím kế tiếp, đọc lại các lần
//! chạm của một từ. Katz back-off trên bộ ba, cặp và từ đơn đếm từ FineWeb và Reddit (tiếng Anh) hay văn bản tiếng
//! Việt (âm tiết), file VKLM0002 ánh xạ vào bộ nhớ: mở ra không đọc gì, mỗi lần tra chỉ chạm vài trang.
//!
//! Chuyển từ Vikey (github.com/tonyminibot/Vikey, GPL-3.0), commit 5f2bfb0, iOS/Keyboard/SuggestLM.swift (bản ViPi:
//! ios/ViPiKeyboard/Suggest/SuggestLM.swift). Giữ đúng phép tính và thứ tự của bản Swift, kể cả chỗ dùng Float
//! (tổng cộng dồn, `extra`, khoảng cách chạm), để ra cùng số (core/tests/suggest.rs so với đáp án Swift).
//!
//! `LmData` là phần chỉ đọc, dùng chung giữa các luồng; `SuggestLm` là một người dùng nó, với các bộ nhớ đệm
//! của riêng mình (ngữ cảnh vừa đọc, trạng thái của mạng), nên mọi hàm của nó lấy `&mut self`.

use std::path::Path;
use std::sync::{Arc, OnceLock};

use super::nn::{NnData, NnState};
use super::text;
use crate::table::Bytes;

const DISCOUNT: f64 = 0.75;

/// Ô của một phím chữ (toạ độ của bàn phím) và chữ của nó, cho `read_taps`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct KeyRect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    /// chữ thường a…z (byte ASCII)
    pub letter: u8,
}

/// Hai token trước từ ở con trỏ: id của từ, <s> sau . ! ? hay xuống dòng, <,> sau , ; :.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Context {
    pub before: Option<usize>,
    pub last: Option<usize>,
    /// hàng của (before, last) trong bảng bộ ba, tra một lần
    pub tri: Option<usize>,
}

/// Một cách đọc các lần chạm: từ, id, độ gần (log) và log P(từ | các từ trước).
#[derive(Clone, Debug, PartialEq)]
pub struct Reading {
    pub word: String,
    pub id: usize,
    pub closeness: f64,
    pub likelihood: f64,
}

impl Reading {
    pub fn score(&self) -> f64 {
        self.closeness + self.likelihood
    }
}

/// Các từ tiếng Việt hay gặp nhất viết bằng phím Telex, sắp theo phím: dấu mũ/móc ở chỗ của nó (aa aw ee oo ow uw
/// dd), dấu thanh (s f r x j) để riêng vì người ta gõ nó ở cuối hay ở giữa. "ươ" có thêm dạng "uow" (một w).
#[derive(Default, Debug)]
pub struct TelexIndex {
    keys: Vec<u8>,
    start: Vec<u32>,
    word: Vec<u32>,
    tone: Vec<u8>,
    share: Vec<f32>,
}

impl TelexIndex {
    fn len(&self) -> usize {
        self.word.len()
    }

    fn key(&self, i: usize) -> &[u8] {
        &self.keys[self.start[i] as usize..self.start[i + 1] as usize]
    }
}

/// Các cách viết Telex của một từ (phím, phím dấu thanh hay 0, phần của số đếm): "người" → nguwowi + f, nguowi + f.
pub fn telex_spellings(word: &str) -> Vec<(Vec<u8>, u8, f32)> {
    let mut base: Vec<u8> = vec![];
    let mut tone = 0u8;
    for u in text::nfd(&text::lower(word)) {
        match u as u32 {
            0x61..=0x7A => base.push(u as u8),
            0x111 => base.extend([100, 100]), // đ
            0x302 => {
                if let Some(&l) = base.last() {
                    base.push(l) // â ê ô
                }
            }
            0x306 | 0x31B => base.push(119), // ă, ơ ư: w
            0x301 => tone = 115,
            0x300 => tone = 102,
            0x309 => tone = 114,
            0x303 => tone = 120,
            0x323 => tone = 106,
            _ => return vec![],
        }
    }
    if base.is_empty() {
        return vec![];
    }
    if let Some(i) = base.windows(4).position(|w| w == b"uwow") {
        let mut one = base.clone();
        one.remove(i + 1); // uow
        return vec![(base, tone, 0.5), (one, tone, 0.5)];
    }
    vec![(base, tone, 1.0)]
}

/// Khoá tra của một chữ: chữ thường, ’ thành ', NFC (chữ ASCII đi đường nhanh).
pub(crate) fn key_bytes(s: &str) -> Vec<u8> {
    if s.is_ascii() {
        return s.bytes().map(|b| b.to_ascii_lowercase()).collect();
    }
    text::nfc(&text::lower(s).replace('’', "'")).into_bytes()
}

/// Phần chỉ đọc của một mô hình: file VKLM0002 (và mạng VKNN0001 của nó), cộng các bảng dựng lúc làm nóng.
pub struct LmData {
    bytes: Bytes,
    word_count: usize,
    tri_count: usize,
    bi_count: usize,
    tri_entries: usize,
    total: f64,
    key_offs: usize,
    blob: usize,
    uni: usize,
    bi_start: usize,
    bi_total: usize,
    bi_beta: usize,
    bi_ids: usize,
    bi_counts: usize,
    tri_keys: usize,
    tri_start: usize,
    tri_total: usize,
    tri_beta: usize,
    tri_ids: usize,
    tri_counts: usize,
    top: usize,
    pub(crate) nn: Option<NnData>,
    /// phần xác suất của một từ lấy từ mạng (đọc xa hơn hai từ); phần còn lại của số đếm
    network_share: f64,
    cumulative: OnceLock<Vec<f32>>,
    telex: OnceLock<TelexIndex>,
    word_of_network_id: OnceLock<Vec<i32>>,
}

impl LmData {
    /// Mở `lm` (và mạng `nn` nếu có). None khi thiếu file hay file không đúng dạng: "không có mô hình".
    pub fn open(lm: &Path, nn: Option<&Path>, network_share: f64) -> Option<LmData> {
        let bytes = Bytes::open(lm).ok()?;
        let mut d = Self::parse(bytes, network_share)?;
        d.nn = nn.and_then(NnData::open);
        Some(d)
    }

    /// Như `open`, từ một vùng nhớ (thử nghiệm).
    pub fn from_bytes(lm: Vec<u8>, nn: Option<Vec<u8>>, network_share: f64) -> Option<LmData> {
        let mut d = Self::parse(Bytes::Owned(lm), network_share)?;
        d.nn = nn.and_then(NnData::from_bytes);
        Some(d)
    }

    fn parse(bytes: Bytes, network_share: f64) -> Option<LmData> {
        let b = bytes.as_slice();
        if b.len() <= 32 || &b[0..8] != b"VKLM0002" {
            return None;
        }
        // u64: các số 32 bit nhân với hằng nhỏ rồi cộng lại không tràn; khác độ dài file thì bỏ trước khi dùng
        let h = |i: usize| u32::from_le_bytes(b[8 + 4 * i..12 + 4 * i].try_into().unwrap()) as u64;
        let (n, n_tri, n_bi, n_tri_e, blob_bytes, total) = (h(0), h(1), h(2), h(3), h(4), h(5));
        let n_ctx = n + 2;
        let align = |x: u64| (x + 3) & !3;
        let mut o: u64 = 8 + 24;
        let take = |len: u64, o: &mut u64| {
            let at = *o;
            *o += len;
            at as usize
        };
        let key_offs = take(4 * (n + 1), &mut o);
        let blob = o as usize;
        o = align(o + blob_bytes);
        let uni = take(4 * n, &mut o);
        let bi_start = take(4 * (n_ctx + 1), &mut o);
        let bi_total = take(4 * n_ctx, &mut o);
        let bi_beta = take(4 * n_ctx, &mut o);
        let bi_ids = take(2 * n_bi, &mut o);
        let bi_counts = o as usize;
        o = align(o + 2 * n_bi);
        let tri_keys = take(4 * n_tri, &mut o);
        let tri_start = take(4 * (n_tri + 1), &mut o);
        let tri_total = take(4 * n_tri, &mut o);
        let tri_beta = take(4 * n_tri, &mut o);
        let tri_ids = take(2 * n_tri_e, &mut o);
        let tri_counts = o as usize;
        o = align(o + 2 * n_tri_e);
        let top = take(2 * 64, &mut o);
        if o != b.len() as u64 || n == 0 || n > 65536 {
            return None; // không phải bố cục mà mã này đọc (id là u16)
        }
        Some(LmData {
            word_count: n as usize,
            tri_count: n_tri as usize,
            bi_count: n_bi as usize,
            tri_entries: n_tri_e as usize,
            total: total as f64,
            key_offs,
            blob,
            uni,
            bi_start,
            bi_total,
            bi_beta,
            bi_ids,
            bi_counts,
            tri_keys,
            tri_start,
            tri_total,
            tri_beta,
            tri_ids,
            tri_counts,
            top,
            nn: None,
            network_share,
            cumulative: OnceLock::new(),
            telex: OnceLock::new(),
            word_of_network_id: OnceLock::new(),
            bytes,
        })
    }

    pub fn word_count(&self) -> usize {
        self.word_count
    }

    pub fn has_network(&self) -> bool {
        self.nn.is_some()
    }

    // MARK: file (mọi lần đọc đều trong file: dữ liệu hỏng cho số sai, không làm sập)

    fn b(&self) -> &[u8] {
        self.bytes.as_slice()
    }

    /// `n` byte ở phần `section`, mục thứ `i` (None khi ra ngoài file; phép tính không tràn cả trên máy 32 bit).
    fn at<const N: usize>(&self, section: usize, i: usize) -> Option<[u8; N]> {
        let a = i.checked_mul(N)?.checked_add(section)?;
        self.b().get(a..a.checked_add(N)?)?.try_into().ok()
    }

    fn u32(&self, section: usize, i: usize) -> usize {
        self.at::<4>(section, i).map_or(0, |x| u32::from_le_bytes(x) as usize)
    }

    fn u16(&self, section: usize, i: usize) -> usize {
        self.at::<2>(section, i).map_or(0, |x| u16::from_le_bytes(x) as usize)
    }

    fn f32(&self, section: usize, i: usize) -> f64 {
        self.at::<4>(section, i).map_or(0.0, |x| f32::from_le_bytes(x) as f64)
    }

    /// Số đếm của một cặp hay bộ ba, lưu dạng round(ln(count) * 2000).
    fn count_at(&self, section: usize, i: usize) -> f64 {
        (self.u16(section, i) as f64 / 2000.0).exp()
    }

    /// Cả mục của từ `id` trong khối chữ: "khoá" hoặc "khoá\tdạng hiện".
    fn entry(&self, id: usize) -> &[u8] {
        let (s, e) = (self.u32(self.key_offs, id), self.u32(self.key_offs, id.saturating_add(1)));
        let (Some(a), Some(z)) = (self.blob.checked_add(s), self.blob.checked_add(e.max(s))) else { return &[] };
        self.b().get(a..z).unwrap_or(&[])
    }

    fn key(&self, id: usize) -> &[u8] {
        let e = self.entry(id);
        e.iter().position(|&c| c == 9).map_or(e, |t| &e[..t])
    }

    /// Dạng hiện của một từ: "I", "YouTube", "don't".
    pub fn form(&self, id: usize) -> String {
        let e = self.entry(id);
        let f = e.iter().position(|&c| c == 9).map_or(e, |t| &e[t + 1..]);
        String::from_utf8_lossy(f).into_owned()
    }

    /// Id đầu tiên có khoá ≥ `k` (theo byte).
    fn lower_bound(&self, k: &[u8]) -> usize {
        let (mut lo, mut hi) = (0, self.word_count);
        while lo < hi {
            let mid = (lo + hi) / 2;
            if self.key(mid) < k {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        lo
    }

    /// Id của các từ bắt đầu bằng `prefix` (liền nhau: khoá sắp theo byte).
    fn range(&self, prefix: &[u8]) -> std::ops::Range<usize> {
        let mut up = prefix.to_vec();
        up.push(0xFF);
        self.lower_bound(prefix)..self.lower_bound(&up)
    }

    fn id_of_key(&self, k: &[u8]) -> Option<usize> {
        let i = self.lower_bound(k);
        (i < self.word_count && self.key(i) == k).then_some(i)
    }

    pub fn id(&self, word: &str) -> Option<usize> {
        self.id_of_key(&key_bytes(word))
    }

    /// Có từ nào bắt đầu bằng `prefix` không (chính nó cũng tính).
    pub fn starts_word(&self, prefix: &str) -> bool {
        !self.range(&key_bytes(prefix)).is_empty()
    }

    /// Số lần gặp từ (0 khi không phải một từ ở đây).
    pub fn count(&self, word: &str) -> usize {
        self.id(word).map_or(0, |i| self.u32(self.uni, i))
    }

    fn p1(&self, w: usize) -> f64 {
        self.u32(self.uni, w) as f64 / self.total
    }

    /// Vị trí đầu tiên trong một đoạn id (đã sắp) có id ≥ w.
    fn lower(&self, ids: usize, run: std::ops::Range<usize>, w: usize) -> usize {
        let (mut lo, mut hi) = (run.start, run.end);
        while lo < hi {
            let mid = (lo + hi) / 2;
            if self.u16(ids, mid) < w {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        lo
    }

    fn tri_index(&self, a: usize, b: usize) -> Option<usize> {
        let k = (a << 16) | b;
        let (mut lo, mut hi) = (0, self.tri_count);
        while lo < hi {
            let mid = (lo + hi) / 2;
            let x = self.u32(self.tri_keys, mid);
            if x == k {
                return Some(mid);
            }
            if x < k {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        None
    }

    /// Các cặp theo sau token `b` (đoạn trong bảng cặp), giới hạn trong bảng.
    fn bi_run(&self, b: usize) -> std::ops::Range<usize> {
        let (s, e) = (self.u32(self.bi_start, b).min(self.bi_count), self.u32(self.bi_start, b + 1).min(self.bi_count));
        s..e.max(s)
    }

    fn tri_run(&self, t: usize) -> std::ops::Range<usize> {
        let (s, e) =
            (self.u32(self.tri_start, t).min(self.tri_entries), self.u32(self.tri_start, t + 1).min(self.tri_entries));
        s..e.max(s)
    }

    /// P(w | ngữ cảnh), từ số đếm của (last, w) và (before, last, w) nếu được giữ.
    fn p(&self, w: usize, ctx: &Context, pair: Option<f64>, triple: Option<f64>) -> f64 {
        let Some(b) = ctx.last else { return self.p1(w) };
        let n = self.u32(self.bi_total, b);
        let p2 = if n == 0 {
            self.p1(w)
        } else {
            pair.map_or_else(|| self.f32(self.bi_beta, b) * self.p1(w), |c| (c - DISCOUNT) / n as f64)
        };
        let Some(t) = ctx.tri else { return p2 };
        triple.map_or_else(|| self.f32(self.tri_beta, t) * p2, |c| (c - DISCOUNT) / self.u32(self.tri_total, t) as f64)
    }

    /// Mọi id trong `r` với P(w | ngữ cảnh): một lượt dọc các cặp và bộ ba của ngữ cảnh (sắp theo id).
    fn scan(&self, r: std::ops::Range<usize>, ctx: &Context, mut body: impl FnMut(usize, f64)) {
        let bi = ctx.last.map_or(0..0, |b| self.bi_run(b));
        let tri = ctx.tri.map_or(0..0, |t| self.tri_run(t));
        let mut i = self.lower(self.bi_ids, bi.clone(), r.start);
        let mut j = self.lower(self.tri_ids, tri.clone(), r.start);
        for w in r {
            while i < bi.end && self.u16(self.bi_ids, i) < w {
                i += 1;
            }
            while j < tri.end && self.u16(self.tri_ids, j) < w {
                j += 1;
            }
            let pair = (i < bi.end && self.u16(self.bi_ids, i) == w).then(|| self.count_at(self.bi_counts, i));
            let triple = (j < tri.end && self.u16(self.tri_ids, j) == w).then(|| self.count_at(self.tri_counts, j));
            body(w, self.p(w, ctx, pair, triple));
        }
    }

    /// Đọc hai token cuối của `text` (chữ trước từ ở con trỏ).
    fn read_context(&self, text: &str) -> Context {
        let sentence = self.word_count;
        let comma = self.word_count + 1;
        let tail = text::suffix(text, 120);
        let cut = tail.len() != text.len();
        let mut toks: Vec<Option<usize>> = if cut { vec![] } else { vec![Some(sentence)] }; // đuôi bị cắt: giữa câu
        let mut word = String::new();
        let mut first = cut; // từ đầu của đoạn cắt có thể dở: bỏ
        let end_word = |word: &mut String, first: &mut bool, toks: &mut Vec<Option<usize>>| {
            if !word.is_empty() {
                if !*first {
                    toks.push(self.id(word));
                }
                word.clear();
            }
            *first = false;
        };
        // theo từng ký tự, không theo cụm: dấu kết hợp là một phần của chữ
        for ch in tail.chars() {
            if ch.is_alphabetic() || text::is_mn(ch) || ((ch == '\'' || ch == '’') && !word.is_empty()) {
                word.push(ch);
                continue;
            }
            end_word(&mut word, &mut first, &mut toks);
            match ch {
                '.' | '!' | '?' | '\n' => toks = vec![Some(sentence)],
                ',' | ';' | ':' => toks = vec![Some(comma)],
                ' ' => {}
                _ => {
                    // dấu ngoặc kép hay ngoặc đơn có thể mở đầu câu
                    if !("\"“(['‘".contains(ch) && toks == [Some(sentence)]) {
                        toks = vec![None];
                    }
                }
            }
        }
        end_word(&mut word, &mut first, &mut toks);
        // một từ lạ cắt ngữ cảnh: không gì trước nó còn tính
        if let Some(i) = toks.iter().rposition(|t| t.is_none()) {
            toks.drain(..=i);
        }
        let n = toks.len();
        let mut c = Context {
            before: if n >= 2 { toks[n - 2] } else { None },
            last: toks.last().copied().flatten(),
            tri: None,
        };
        if let (Some(a), Some(b)) = (c.before, c.last) {
            c.tri = self.tri_index(a, b);
        }
        c
    }

    // MARK: làm nóng

    /// Một lần đọc mỗi trang của file (mô hình và mạng): các trang vào bộ nhớ đệm của hệ điều hành.
    pub(crate) fn touch_pages(&self) -> usize {
        let mut sum = 0usize;
        let mut touch = |b: &[u8]| {
            for i in (0..b.len()).step_by(4096) {
                sum = sum.wrapping_add(b[i] as usize);
            }
        };
        touch(self.b());
        if let Some(nn) = &self.nn {
            touch(nn.bytes());
        }
        std::hint::black_box(sum)
    }

    /// Dựng các bảng cho làm nóng (tổng cộng dồn; chỉ mục Telex nếu `telex`; id của mạng về id từ). Gọi lại không
    /// làm gì.
    pub(crate) fn build_warm(&self, telex: bool) {
        self.cumulative.get_or_init(|| self.running_sums());
        if telex {
            self.telex.get_or_init(|| self.build_telex(25000));
        }
        self.word_of_network_id.get_or_init(|| {
            let Some(nn) = &self.nn else { return vec![] };
            let mut m = vec![-1i32; nn.v];
            for w in 0..self.word_count {
                let k = nn.network_id(w);
                if k > 0 && k < m.len() {
                    m[k] = w as i32;
                }
            }
            m
        });
    }

    /// Tổng cộng dồn của P(w) theo id: phần của một đoạn bất kỳ trong hai lần đọc.
    fn running_sums(&self) -> Vec<f32> {
        let mut out = vec![0f32; self.word_count + 1];
        let mut s = 0.0f64;
        for w in 0..self.word_count {
            s += self.p1(w);
            out[w + 1] = s as f32;
        }
        out
    }

    fn build_telex(&self, limit: usize) -> TelexIndex {
        let mut ids: Vec<usize> = (0..self.word_count).collect();
        ids.sort_by_key(|&w| std::cmp::Reverse(self.u32(self.uni, w))); // ổn định, như sorted của Swift
        let mut entries: Vec<(Vec<u8>, u8, u32, f32)> = vec![];
        for &w in ids.iter().take(limit) {
            for (k, t, s) in telex_spellings(&self.form(w)) {
                entries.push((k, t, w as u32, s));
            }
        }
        entries.sort_by(|a, b| a.0.cmp(&b.0));
        let mut t = TelexIndex { start: vec![0], ..Default::default() };
        for (k, tone, w, s) in entries {
            t.keys.extend_from_slice(&k);
            t.start.push(t.keys.len() as u32);
            t.word.push(w);
            t.tone.push(tone);
            t.share.push(s);
        }
        t
    }
}

/// Một người dùng mô hình: các hàm tra, với bộ nhớ đệm riêng (ngữ cảnh vừa đọc, xác suất bổ sung cho phím Telex,
/// trạng thái của mạng). Các bảng làm nóng (tổng cộng dồn, chỉ mục Telex) chỉ được đọc khi đã có: chưa có thì
/// `next_letters` / `next_keys` trả None, không bao giờ đợi.
pub struct SuggestLm {
    data: Arc<LmData>,
    last_context: Option<(String, Context)>,
    extra: Vec<f32>,
    extra_set: Vec<usize>,
    extra_text: Option<String>,
    extra_beta: f64,
    nn: Option<NnState>,
}

impl SuggestLm {
    pub fn new(data: Arc<LmData>) -> SuggestLm {
        let nn = data.nn.as_ref().map(NnState::new);
        SuggestLm { data, last_context: None, extra: vec![], extra_set: vec![], extra_text: None, extra_beta: 1.0, nn }
    }

    /// Mở và dựng ngay các bảng làm nóng (thử nghiệm, công cụ).
    pub fn open_now(lm: &Path, nn: Option<&Path>, network_share: f64, telex: bool) -> Option<SuggestLm> {
        let d = LmData::open(lm, nn, network_share)?;
        d.build_warm(telex);
        Some(SuggestLm::new(Arc::new(d)))
    }

    pub fn data(&self) -> &Arc<LmData> {
        &self.data
    }

    pub fn id(&self, word: &str) -> Option<usize> {
        self.data.id(word)
    }

    pub fn starts_word(&self, prefix: &str) -> bool {
        self.data.starts_word(prefix)
    }

    pub fn count(&self, word: &str) -> usize {
        self.data.count(word)
    }

    pub fn form(&self, id: usize) -> String {
        self.data.form(id)
    }

    pub fn context(&mut self, text: &str) -> Context {
        if let Some((t, c)) = &self.last_context {
            if t == text {
                return *c;
            }
        }
        let c = self.data.read_context(text);
        self.last_context = Some((text.to_string(), c));
        c
    }

    /// Phân bố của mạng sau `before` (theo id của mạng), None khi không có mạng.
    fn network(&mut self, before: &str) -> Option<&[f32]> {
        let nn = self.nn.as_mut()?;
        let data = self.data.nn.as_ref()?;
        Some(nn.next(data, &self.data, before))
    }

    /// P(w) trộn với phân bố của mạng `nnp` sau cùng chữ.
    fn blend(data: &LmData, p: f64, w: usize, nnp: Option<&[f32]>) -> f64 {
        let (Some(nnp), Some(nn)) = (nnp, &data.nn) else { return p };
        let k = nn.network_id(w);
        (1.0 - data.network_share) * p
            + data.network_share * if k > 0 { nnp.get(k).copied().unwrap_or(0.0) as f64 } else { 0.0 }
    }

    /// Các chữ đã gõ là một từ đang gõ dở hơn là gõ lỗi của `word` (một cách sửa không phải cách gõ tiếp chúng): sau
    /// `before`, các từ chúng mở đầu có khả năng ít nhất 2% của từ sửa ("spee" → speed sau "high", không phải
    /// "see"), hoặc từ sửa không có trong mô hình.
    pub fn prefers_finishing(&mut self, prefix: &str, word: &str, before: &str) -> bool {
        let k = key_bytes(prefix);
        let r = self.data.range(&k);
        if r.is_empty() || key_bytes(word).starts_with(&k) {
            return false;
        }
        let Some(fix) = self.id(word) else { return true };
        let ctx = self.context(before);
        let (mut finishing, mut p_fix) = (0.0, 0.0);
        self.data.scan(r, &ctx, |_, p| finishing += p);
        self.data.scan(fix..fix + 1, &ctx, |_, p| p_fix = p);
        finishing >= 0.02 * p_fix
    }

    // MARK: chạm lệch

    /// Các từ mà các lần chạm có thể định gõ: mỗi chữ gần lần chạm của nó (bằng số lần chạm, tối đa `max_slips` chữ
    /// không phải phím gần nhất), với độ gần (Gauss hai chiều quanh mỗi phím, theo bề rộng và chiều cao phím) và
    /// log P(từ | before). Tốt nhất trước, theo tổng hai số.
    #[allow(clippy::too_many_arguments)]
    pub fn read_taps_with(
        &mut self,
        taps: &[(f32, f32)],
        keys: &[KeyRect],
        before: &str,
        max_slips: usize,
        limit: usize,
        sigma: f32,
        sigma_y: f32,
    ) -> Vec<Reading> {
        if taps.is_empty() || taps.len() >= 24 {
            return vec![];
        }
        // với mỗi lần chạm: các chữ đủ gần để là chữ định gõ (trong ~3 độ tản), gần nhất trước
        let near: Vec<Vec<(u8, f64)>> = taps
            .iter()
            .map(|&(tx, ty)| {
                let mut c: Vec<(u8, f64)> = vec![];
                for k in keys {
                    let dx = (tx - (k.x + k.w / 2.0)) / (k.w * sigma);
                    let dy = (ty - (k.y + k.h / 2.0)) / (k.h * sigma_y);
                    let s = -0.5 * (dx * dx + dy * dy) as f64;
                    if s > -4.5 {
                        c.push((k.letter, s));
                    }
                }
                c.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
                c
            })
            .collect();
        let data_arc = Arc::clone(&self.data);
        let data = &*data_arc;
        let mut found: Vec<(usize, f64)> = vec![];
        let mut prefix: Vec<u8> = vec![];
        #[allow(clippy::too_many_arguments)]
        fn walk(
            data: &LmData,
            near: &[Vec<(u8, f64)>],
            i: usize,
            closeness: f64,
            slips: usize,
            max_slips: usize,
            prefix: &mut Vec<u8>,
            found: &mut Vec<(usize, f64)>,
        ) {
            if i == near.len() {
                if let Some(w) = data.id_of_key(prefix) {
                    found.push((w, closeness));
                }
                return;
            }
            for (j, &(letter, s)) in near[i].iter().enumerate() {
                let sl = slips + usize::from(j != 0);
                if sl > max_slips {
                    continue;
                }
                prefix.push(letter);
                if !data.range(prefix).is_empty() {
                    walk(data, near, i + 1, closeness + s, sl, max_slips, prefix, found);
                    // có từ bắt đầu như thế
                }
                prefix.pop();
            }
        }
        walk(data, &near, 0, 0.0, 0, max_slips, &mut prefix, &mut found);
        if found.is_empty() {
            return vec![];
        }
        let forms: Vec<String> = found.iter().map(|&(w, _)| data.form(w)).collect();
        let p = self.probabilities(&forms, before);
        let mut out: Vec<Reading> = found
            .iter()
            .zip(forms)
            .zip(p)
            .map(|((&(id, closeness), word), p)| Reading { word, id, closeness, likelihood: p.max(1e-12).ln() })
            .collect();
        out.sort_by(|a, b| b.score().partial_cmp(&a.score()).unwrap_or(std::cmp::Ordering::Equal));
        out.truncate(limit);
        out
    }

    /// `read_taps_with` với các số của Vikey: tối đa 2 chữ lệch, 4 cách đọc, độ tản 0,35 bề rộng / 0,25 chiều cao.
    pub fn read_taps(&mut self, taps: &[(f32, f32)], keys: &[KeyRect], before: &str) -> Vec<Reading> {
        self.read_taps_with(taps, keys, before, 2, 4, 0.35, 0.25)
    }

    // MARK: chữ kế tiếp

    /// Khả năng của từng chữ kế tiếp sau `prefix` (các chữ của từ đến giờ) và `before`: phần của các từ đi tiếp
    /// bằng a…z (26 số), rồi khả năng từ dừng ở đây (số thứ 27). Chỉ số đếm. None khi không từ nào bắt đầu như
    /// thế, hoặc chưa làm nóng.
    pub fn next_letters(&mut self, prefix: &str, before: &str) -> Option<Vec<f64>> {
        let k = key_bytes(prefix);
        let r = self.data.range(&k);
        if r.is_empty() {
            return None;
        }
        let data = Arc::clone(&self.data);
        let d = &*data;
        let cum = d.cumulative.get()?;
        let l = k.len();
        // byte sau tiền tố trong một từ của r: -1 khi từ là chính tiền tố; không giảm dọc theo r
        let next = |w: usize| -> i32 {
            let e = d.entry(w);
            match e.get(l) {
                None | Some(9) => -1,
                Some(&b) => b as i32,
            }
        };
        let bin = |w: usize| -> i32 {
            let b = next(w);
            if b < 0 {
                26
            } else if (97..=122).contains(&b) {
                b - 97
            } else {
                -1
            }
        };
        let first = |from: usize, at_least: i32| -> usize {
            let (mut lo, mut hi) = (from, r.end);
            while lo < hi {
                let m = (lo + hi) / 2;
                if next(m) < at_least {
                    lo = m + 1;
                } else {
                    hi = m;
                }
            }
            lo
        };
        let mut runs = [(0usize, 0usize); 27];
        let mut lo = r.start;
        if lo < r.end && next(lo) < 0 {
            runs[26] = (lo, lo + 1);
            lo += 1;
        }
        lo = first(lo, 97);
        for (c, run) in runs.iter_mut().take(26).enumerate() {
            if lo >= r.end {
                break;
            }
            let end = first(lo, 98 + c as i32);
            *run = (lo, end);
            lo = end;
        }
        let uni = |(a, b): (usize, usize)| -> f64 {
            (cum.get(b).copied().unwrap_or(0.0) - cum.get(a).copied().unwrap_or(0.0)) as f64
        };
        let mut mass: Vec<f64> = runs.iter().map(|&run| uni(run)).collect(); // P(w) cộng lại, trước ngữ cảnh
        let ctx = self.context(before);
        if let Some(b_row) = ctx.last {
            if d.u32(d.bi_total, b_row) > 0 {
                let n = d.u32(d.bi_total, b_row) as f64;
                let beta = d.f32(d.bi_beta, b_row);
                let bi = d.bi_run(b_row);
                // cặp: p2 = (c - D) / n khi (last, w) được giữ, beta * p1 ở chỗ khác
                let mut p2: Vec<f64> = mass.iter().map(|m| beta * m).collect();
                let mut i = d.lower(d.bi_ids, bi.clone(), r.start);
                while i < bi.end && d.u16(d.bi_ids, i) < r.end {
                    let w = d.u16(d.bi_ids, i);
                    let c = bin(w);
                    if c >= 0 {
                        p2[c as usize] += (d.count_at(d.bi_counts, i) - DISCOUNT) / n - beta * d.p1(w);
                    }
                    i += 1;
                }
                mass = p2.clone();
                if let Some(t) = ctx.tri {
                    let tn = d.u32(d.tri_total, t) as f64;
                    let tb = d.f32(d.tri_beta, t);
                    let tri = d.tri_run(t);
                    mass = p2.iter().map(|m| tb * m).collect();
                    let mut j = d.lower(d.tri_ids, tri.clone(), r.start);
                    while j < tri.end && d.u16(d.tri_ids, j) < r.end {
                        let w = d.u16(d.tri_ids, j);
                        let c = bin(w);
                        if c >= 0 {
                            let ip = d.lower(d.bi_ids, bi.clone(), w);
                            let pw = if ip < bi.end && d.u16(d.bi_ids, ip) == w {
                                (d.count_at(d.bi_counts, ip) - DISCOUNT) / n
                            } else {
                                beta * d.p1(w)
                            };
                            mass[c as usize] += (d.count_at(d.tri_counts, j) - DISCOUNT) / tn - tb * pw;
                        }
                        j += 1;
                    }
                }
            }
        }
        let total = mass.iter().fold(0.0, |s, m| s + m.max(0.0));
        (total > 0.0).then(|| mass.iter().map(|m| m.max(0.0) / total).collect())
    }

    // MARK: tiếng Việt: phím Telex kế tiếp

    /// Các từ theo sau ngữ cảnh, dạng P(w | ngữ cảnh) - beta * P(w) (Katz: phần còn lại là beta * P(w)): một ô cho
    /// mỗi id từ, điền cho các cặp và bộ ba của ngữ cảnh, xoá khi chữ trước từ đổi.
    fn context_extra(&mut self, before: &str) -> f64 {
        if self.extra_text.as_deref() == Some(before) {
            return self.extra_beta;
        }
        if self.extra.is_empty() {
            self.extra = vec![0.0; self.data.word_count];
        }
        for &w in &self.extra_set {
            self.extra[w] = 0.0;
        }
        self.extra_set.clear();
        self.extra_text = Some(before.to_string());
        self.extra_beta = 1.0;
        let ctx = self.context(before);
        let d = Arc::clone(&self.data);
        let Some(b_row) = ctx.last else { return 1.0 };
        if d.u32(d.bi_total, b_row) == 0 {
            return 1.0;
        }
        let n = d.u32(d.bi_total, b_row) as f64;
        let bb = d.f32(d.bi_beta, b_row);
        let tb = ctx.tri.map_or(1.0, |t| d.f32(d.tri_beta, t));
        self.extra_beta = tb * bb;
        for i in d.bi_run(b_row) {
            let w = d.u16(d.bi_ids, i);
            if w >= self.extra.len() {
                continue;
            }
            self.extra[w] = (tb * ((d.count_at(d.bi_counts, i) - DISCOUNT) / n - bb * d.p1(w))) as f32;
            self.extra_set.push(w);
        }
        if let Some(t) = ctx.tri {
            let tn = d.u32(d.tri_total, t) as f64;
            for j in d.tri_run(t) {
                let w = d.u16(d.tri_ids, j);
                if w >= self.extra.len() {
                    continue;
                }
                let p2 = bb * d.p1(w) + self.extra[w] as f64 / tb;
                self.extra[w] += ((d.count_at(d.tri_counts, j) - DISCOUNT) / tn - tb * p2) as f32;
                self.extra_set.push(w);
            }
        }
        self.extra_beta
    }

    /// Khả năng của từng phím kế tiếp khi gõ một từ tiếng Việt bằng Telex (`typed`: các phím đến giờ) sau
    /// `before`: 26 phím, rồi từ kết thúc (27). Dấu thanh còn chờ cũng có thể là phím kế tiếp (`tone_now` của số lần
    /// khi còn chữ phía sau). None khi không từ nào trong chỉ mục đi tiếp từ các phím này, hoặc chưa làm nóng.
    pub fn next_keys(&mut self, typed: &str, before: &str, tone_now: f64) -> Option<Vec<f64>> {
        let data = Arc::clone(&self.data);
        let tx = data.telex.get()?;
        if typed.is_empty() {
            return None;
        }
        let mut base: Vec<u8> = vec![];
        let mut typed_tone = 0u8;
        let mut vowel = false;
        for b in text::lower(typed).bytes() {
            if vowel && matches!(b, b's' | b'f' | b'r' | b'x' | b'j') {
                if typed_tone == b {
                    return None; // gõ hai lần: bộ gõ bỏ dấu và thôi đọc Telex
                }
                typed_tone = b;
                continue;
            }
            if matches!(b, b'a' | b'e' | b'i' | b'o' | b'u' | b'y') {
                vowel = true;
            }
            base.push(b);
        }
        // đoạn các mục có phím bắt đầu bằng base
        let lower = |k: &[u8], upper: bool| -> usize {
            let (mut lo, mut hi) = (0, tx.len());
            while lo < hi {
                let m = (lo + hi) / 2;
                let e = tx.key(m);
                let less = if upper { e.starts_with(k) || e < k } else { e < k };
                if less {
                    lo = m + 1;
                } else {
                    hi = m;
                }
            }
            lo
        };
        let (a, b) = (lower(&base, false), lower(&base, true));
        if a >= b {
            return None;
        }
        let beta = self.context_extra(before);
        let mut out = vec![0.0f64; 27];
        let l = base.len();
        for i in a..b {
            let w = tx.word[i] as usize;
            let t = tx.tone[i];
            if typed_tone != 0 && t != typed_tone {
                continue;
            }
            let p = (beta * data.p1(w) + self.extra.get(w).copied().unwrap_or(0.0) as f64) * tx.share[i] as f64;
            if p <= 0.0 || p.is_nan() {
                continue;
            }
            let k = tx.key(i);
            let pending = vowel && typed_tone == 0 && t != 0; // phím dấu thanh chỉ có tác dụng sau nguyên âm
            if k.len() > l {
                let c = k[l] as i32 - 97;
                if !(0..26).contains(&c) {
                    continue;
                }
                out[c as usize] += if pending { p * (1.0 - tone_now) } else { p };
                if pending {
                    out[t as usize - 97] += p * tone_now;
                }
            } else if pending {
                out[t as usize - 97] += p;
            } else {
                out[26] += p;
            }
        }
        let total: f64 = out.iter().sum();
        (total > 0.0).then(|| out.iter().map(|x| x / total).collect())
    }

    // MARK: gợi ý

    /// Các cách gõ tiếp `prefix` tốt nhất sau `before` (chữ trước từ), khả năng cao trước, theo dạng hiện ("I",
    /// "don't"). Không có chính tiền tố.
    pub fn completions(&mut self, prefix: &str, before: &str, limit: usize) -> Vec<String> {
        if prefix.is_empty() || limit == 0 {
            return vec![];
        }
        let k = key_bytes(prefix);
        let r = self.data.range(&k);
        if r.is_empty() {
            return vec![];
        }
        let data = Arc::clone(&self.data);
        let ctx = self.context(before);
        let nnp = self.network(before);
        let mut best: Vec<(f64, usize)> = vec![];
        data.scan(r, &ctx, |w, p| {
            let s = Self::blend(&data, p, w, nnp);
            if best.len() == limit && s <= best[limit - 1].0 {
                return;
            }
            if data.key(w) == k.as_slice() {
                return;
            }
            let at = best.iter().position(|b| s > b.0).unwrap_or(best.len());
            best.insert(at, (s, w));
            best.truncate(limit);
        });
        best.iter().map(|&(_, w)| data.form(w)).collect()
    }

    /// P(từ) sau `before` cho từng từ, như thanh gợi ý xếp chúng (số đếm và mạng trộn lại); 0 cho từ không biết.
    pub fn probabilities<S: AsRef<str>>(&mut self, words: &[S], before: &str) -> Vec<f64> {
        let ctx = self.context(before);
        let data = Arc::clone(&self.data);
        let nnp = self.network(before);
        words
            .iter()
            .map(|word| {
                let Some(w) = data.id(word.as_ref()) else { return 0.0 };
                let mut r = 0.0;
                data.scan(w..w + 1, &ctx, |w, p| r = Self::blend(&data, p, w, nnp));
                r
            })
            .collect()
    }

    /// Các từ tiếp theo dễ gặp nhất sau `before` (kết thúc bằng dấu cách): các cặp của ngữ cảnh, các từ hay gặp
    /// nhất, và các từ mạng thích nhất.
    pub fn next_words(&mut self, before: &str, limit: usize) -> Vec<String> {
        self.next_words_scored(before, limit).into_iter().map(|(w, _)| w).collect()
    }

    pub fn next_words_scored(&mut self, before: &str, limit: usize) -> Vec<(String, f64)> {
        if limit == 0 {
            return vec![];
        }
        let ctx = self.context(before);
        let data = Arc::clone(&self.data);
        let d = &*data;
        let nnp = self.network(before);
        let mut best: Vec<(f64, usize)> = vec![];
        let mut consider = |w: usize, s: f64| {
            if best.len() == limit && s <= best[limit - 1].0 {
                return;
            }
            if best.iter().any(|b| b.1 == w) {
                return;
            }
            let at = best.iter().position(|b| s > b.0).unwrap_or(best.len());
            best.insert(at, (s, w));
            best.truncate(limit);
        };
        if let Some(b) = ctx.last {
            let bi = d.bi_run(b);
            let tri = ctx.tri.map_or(0..0, |t| d.tri_run(t));
            let mut j = tri.start;
            for i in bi {
                let w = d.u16(d.bi_ids, i);
                while j < tri.end && d.u16(d.tri_ids, j) < w {
                    j += 1;
                }
                let triple = (j < tri.end && d.u16(d.tri_ids, j) == w).then(|| d.count_at(d.tri_counts, j));
                consider(w, Self::blend(d, d.p(w, &ctx, Some(d.count_at(d.bi_counts, i)), triple), w, nnp));
            }
        }
        let mut extra: Vec<usize> = (0..64).map(|i| d.u16(d.top, i)).collect();
        if let (Some(nnp), Some(nn)) = (nnp, &d.nn) {
            // 16 từ mạng thích nhất
            let mut picks: Vec<(f32, usize)> = Vec::with_capacity(17);
            for (k, &pk) in nnp.iter().enumerate().take(nn.v).skip(4) {
                if picks.len() < 16 || pk > picks[15].0 {
                    // chèn sau mọi phần tử ≥ nó: như append rồi sort ổn định giảm dần
                    let at = picks.iter().position(|p| p.0 < pk).unwrap_or(picks.len());
                    picks.insert(at, (pk, k));
                    picks.truncate(16);
                }
            }
            if let Some(m) = d.word_of_network_id.get() {
                extra.extend(picks.iter().filter_map(|&(_, k)| m.get(k).filter(|&&w| w >= 0).map(|&w| w as usize)));
            }
        }
        for w in extra {
            if w < d.word_count {
                d.scan(w..w + 1, &ctx, |w, p| consider(w, Self::blend(d, p, w, nnp)));
            }
        }
        best.iter().map(|&(s, w)| (d.form(w), s)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Dãy byte giả ngẫu nhiên (thử dữ liệu hỏng).
    fn noise(n: usize, seed: &mut u64) -> Vec<u8> {
        (0..n)
            .map(|_| {
                *seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                (*seed >> 33) as u8
            })
            .collect()
    }

    /// File đúng bố cục VKLM0002 / VKNN0001 mà thân là rác: mọi hàm trả về gì đó, không sập.
    #[test]
    fn garbage_body_never_panics() {
        let mut seed = 7u64;
        for _ in 0..200 {
            let r = noise(6, &mut seed);
            let (n, n_tri, n_bi, n_tri_e, blob) =
                (1 + r[0] as u64 % 40, r[1] as u64 % 9, r[2] as u64 % 50, r[3] as u64 % 30, r[4] as u64 % 200);
            let align = |x: u64| (x + 3) & !3;
            let nctx = n + 2;
            let mut o = align(32 + 4 * (n + 1) + blob) + 4 * n + 4 * (nctx + 1) + 8 * nctx + 2 * n_bi;
            o = align(o + 2 * n_bi) + 4 * n_tri + 4 * (n_tri + 1) + 8 * n_tri + 2 * n_tri_e;
            let size = align(o + 2 * n_tri_e) + 128;
            let mut lm = b"VKLM0002".to_vec();
            for h in [n, n_tri, n_bi, n_tri_e, blob, 1 + r[5] as u64] {
                lm.extend((h as u32).to_le_bytes());
            }
            lm.extend(noise(size as usize - 32, &mut seed));
            let (v, e, h, nw) = (4 + r[0] as u64 % 10, 1 + r[1] as u64 % 5, 1 + r[2] as u64 % 6, r[3] as u64 % 50);
            let nn_size = ((24 + 2 * nw + 3) & !3) + 4 * (v * e + 4 * h * e + 4 * h * h + 4 * h + e * h + e + v);
            let mut nn = b"VKNN0001".to_vec();
            for x in [v, e, h, nw] {
                nn.extend((x as u32).to_le_bytes());
            }
            nn.extend(noise(nn_size as usize - 24, &mut seed));
            let d = LmData::from_bytes(lm, Some(nn), 0.5).expect("layout");
            assert!(d.has_network());
            d.build_warm(true);
            let mut m = SuggestLm::new(Arc::new(d));
            let keys: Vec<KeyRect> =
                (0..26u8).map(|i| KeyRect { x: 10.0 * i as f32, y: 0.0, w: 9.0, h: 9.0, letter: b'a' + i }).collect();
            for before in ["", "the ", "a b. c, d ", "x"] {
                for p in ["", "a", "th", "\u{1}", "zz"] {
                    m.completions(p, before, 3);
                    m.next_letters(p, before);
                    m.next_keys(p, before, 0.1);
                    m.prefers_finishing(p, "the", before);
                    m.read_taps(&[(5.0, 4.0), (25.0, 4.0)], &keys, before);
                    m.id(p);
                    m.count(p);
                }
                m.next_words(before, 3);
                m.probabilities(&["a", "b"], before);
            }
            for i in 0..50 {
                m.form(i);
            }
        }
    }

    #[test]
    fn bad_headers_are_no_model() {
        assert!(LmData::from_bytes(b"VKLM0001".repeat(10), None, 0.5).is_none());
        assert!(LmData::from_bytes(b"VKLM0002".to_vec(), None, 0.5).is_none());
        let mut huge = b"VKLM0002".to_vec();
        huge.extend([0xFF; 40]);
        assert!(LmData::from_bytes(huge, None, 0.5).is_none());
        assert!(NnData::from_bytes(b"VKNN0001".repeat(4)).is_none());
        assert!(LmData::open(Path::new("/nonexistent/SuggestEN.bin"), None, 0.5).is_none());
    }

    #[test]
    fn telex_spellings_of_vietnamese_words() {
        let s = |w: &str| {
            telex_spellings(w)
                .into_iter()
                .map(|(k, t, sh)| format!("{}/{}/{sh}", String::from_utf8(k).unwrap(), t as char))
                .collect::<Vec<_>>()
        };
        assert_eq!(s("người"), ["nguwowi/f/0.5", "nguowi/f/0.5"]);
        assert_eq!(s("Đường"), ["dduwowng/f/0.5", "dduowng/f/0.5"]);
        assert_eq!(s("việt"), ["vieet/j/1"]);
        assert_eq!(s("anh"), ["anh/\u{0}/1"]);
        assert!(s("liềᴜ").is_empty() && s("").is_empty() && s("x1").is_empty());
    }
}
