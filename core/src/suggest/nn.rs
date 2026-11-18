//! Mạng dự đoán từ tiếp theo (LSTM trên các từ trước con trỏ, file VKNN0001): `SuggestLm` trộn phân bố của nó với
//! số đếm, vốn chỉ thấy hai từ trước. Trọng số float32 đọc thẳng trong file ánh xạ vào bộ nhớ. Trạng thái giữ giữa
//! các lần gọi: thêm một từ tốn một bước LSTM và một lượt qua lớp ra.
//!
//! Chuyển từ Vikey (github.com/tonyminibot/Vikey, GPL-3.0), commit 5f2bfb0, iOS/Keyboard/SuggestNN.swift (bản ViPi:
//! ios/ViPiKeyboard/Suggest/SuggestNN.swift). Bản Swift nhân ma trận bằng vDSP; ở đây là vòng f32 thường (8 tổng
//! song song để trình dịch dùng SIMD); các xác suất lệch bản Swift tới ~1e-4 tương đối (core/tests/suggest.rs).

use std::path::Path;

use super::lm::LmData;
use super::text;
use crate::table::Bytes;

/// Số token đọc lại khi bắt đầu từ đầu.
const WINDOW: usize = 32;

pub struct NnData {
    bytes: Bytes,
    pub(crate) v: usize,
    e: usize,
    h: usize,
    n_words: usize,
    nn_of: usize,
    emb: usize,
    wih: usize,
    whh: usize,
    bias: usize,
    proj_w: usize,
    proj_b: usize,
    out_b: usize,
}

impl NnData {
    pub(crate) fn open(path: &Path) -> Option<NnData> {
        Self::parse(Bytes::open(path).ok()?)
    }

    pub(crate) fn from_bytes(b: Vec<u8>) -> Option<NnData> {
        Self::parse(Bytes::Owned(b))
    }

    fn parse(bytes: Bytes) -> Option<NnData> {
        let b = bytes.as_slice();
        if b.len() <= 24
            || &b[0..8] != b"VKNN0001"
            || cfg!(target_endian = "big")
            || !(b.as_ptr() as usize).is_multiple_of(4)
        {
            return None;
        }
        // u128: bốn số 32 bit nhân với nhau không tràn, file hỏng chỉ cho bố cục sai
        let hd = |i: usize| u32::from_le_bytes(b[8 + 4 * i..12 + 4 * i].try_into().unwrap()) as u128;
        let (v, e, hid, n) = (hd(0), hd(1), hd(2), hd(3));
        let nn_of: u128 = 8 + 16;
        let emb = (nn_of + 2 * n + 3) & !3;
        let wih = emb + 4 * v * e;
        let whh = wih + 4 * 4 * hid * e;
        let bias = whh + 4 * 4 * hid * hid;
        let proj_w = bias + 4 * 4 * hid;
        let proj_b = proj_w + 4 * e * hid;
        let out_b = proj_b + 4 * e;
        let o = out_b + 4 * v;
        if o != b.len() as u128 || v < 4 || e == 0 || hid == 0 {
            return None; // không phải bố cục mà mã này đọc
        }
        Some(NnData {
            v: v as usize,
            e: e as usize,
            h: hid as usize,
            n_words: n as usize,
            nn_of: nn_of as usize,
            emb: emb as usize,
            wih: wih as usize,
            whh: whh as usize,
            bias: bias as usize,
            proj_w: proj_w as usize,
            proj_b: proj_b as usize,
            out_b: out_b as usize,
            bytes,
        })
    }

    pub(crate) fn bytes(&self) -> &[u8] {
        self.bytes.as_slice()
    }

    /// Id trong mạng của một id từ của SuggestLm (0: không phải từ của mạng).
    pub(crate) fn network_id(&self, word: usize) -> usize {
        if word >= self.n_words {
            return 0;
        }
        let at = self.nn_of + 2 * word;
        u16::from_le_bytes([self.bytes()[at], self.bytes()[at + 1]]) as usize
    }

    /// `len` số float32 bắt đầu ở byte `at` (đã kiểm tra khi mở: nằm trong file, căn 4 byte).
    fn f32s(&self, at: usize, len: usize) -> &[f32] {
        let b = &self.bytes()[at..at + 4 * len];
        // SAFETY: b căn 4 byte (đầu file căn 4, mọi phần ở vị trí bội của 4) và dài đúng 4 * len; máy little-endian
        unsafe { std::slice::from_raw_parts(b.as_ptr() as *const f32, len) }
    }
}

/// Tích vô hướng, 8 tổng song song.
#[inline]
fn dot(a: &[f32], b: &[f32]) -> f32 {
    let n = a.len().min(b.len());
    let (a, b) = (&a[..n], &b[..n]);
    let mut acc = [0f32; 8];
    let (ca, ra) = a.as_chunks::<8>();
    let (cb, rb) = b.as_chunks::<8>();
    for (x, y) in ca.iter().zip(cb) {
        for k in 0..8 {
            acc[k] += x[k] * y[k];
        }
    }
    let mut s = (acc[0] + acc[4]) + (acc[1] + acc[5]) + (acc[2] + acc[6]) + (acc[3] + acc[7]);
    for (x, y) in ra.iter().zip(rb) {
        s += x * y;
    }
    s
}

/// y = W·x (+ b), W theo hàng (rows × cols).
fn affine(w: &[f32], cols: usize, x: &[f32], b: Option<&[f32]>, y: &mut [f32]) {
    for (r, out) in y.iter_mut().enumerate() {
        let v = dot(&w[r * cols..(r + 1) * cols], x);
        *out = match b {
            Some(b) => v + b[r],
            None => v,
        };
    }
}

fn sigmoid(x: f32) -> f32 {
    1.0 / (1.0 + (-x).exp())
}

/// Trạng thái của mạng cho một người dùng, và chữ nó đã đọc.
pub(crate) struct NnState {
    hs: Vec<f32>,
    cs: Vec<f32>,
    gates: Vec<f32>,
    scratch: Vec<f32>,
    z: Vec<f32>,
    probs: Vec<f32>,
    fed_text: Option<String>,
    last_token: usize,
    probs_ready: bool,
}

impl NnState {
    pub(crate) fn new(nn: &NnData) -> NnState {
        NnState {
            hs: vec![0.0; nn.h],
            cs: vec![0.0; nn.h],
            gates: vec![0.0; 4 * nn.h],
            scratch: vec![0.0; 4 * nn.h],
            z: vec![0.0; nn.e],
            probs: vec![0.0; nn.v],
            fed_text: None,
            last_token: 1,
            probs_ready: false,
        }
    }

    /// Một bước LSTM: trạng thái đọc token t.
    fn step(&mut self, nn: &NnData, t: usize) {
        let (h, e) = (nn.h, nn.e);
        let g = 4 * h;
        let row = if t < nn.v { t } else { 0 };
        let x = nn.f32s(nn.emb + 4 * row * e, e);
        affine(nn.f32s(nn.wih, g * e), e, x, Some(nn.f32s(nn.bias, g)), &mut self.gates);
        affine(nn.f32s(nn.whh, g * h), h, &self.hs, None, &mut self.scratch);
        for (a, b) in self.gates.iter_mut().zip(&self.scratch) {
            *a += b;
        }
        for j in 0..h {
            let i = sigmoid(self.gates[j]);
            let f = sigmoid(self.gates[h + j]);
            let c = self.gates[2 * h + j].tanh();
            let o = sigmoid(self.gates[3 * h + j]);
            self.cs[j] = f * self.cs[j] + i * c;
            self.hs[j] = o * self.cs[j].tanh();
        }
        self.last_token = t;
    }

    /// Các token của `text` như lúc mạng được huấn luyện: từ, 1 sau . ! ? hay xuống dòng, 2 sau , ; :, 3 cho mọi thứ
    /// khác cắt một dãy từ; 1 và 3 lặp lại thì gộp, dấu ngoặc mở đầu câu thì bỏ. `last`: token trước đoạn chữ.
    fn tokens(nn: &NnData, words: &LmData, text_: &str, last: usize) -> Vec<usize> {
        fn emit(out: &mut Vec<usize>, prev: &mut usize, t: usize) {
            if (t == 1 || t == 3) && *prev == t {
                return;
            }
            out.push(t);
            *prev = t;
        }
        let mut out = vec![];
        let mut prev = last;
        let mut word = String::new();
        let word_token = |word: &str| words.id(word).map_or(0, |i| nn.network_id(i));
        for ch in text::clusters(text_) {
            if text::is_letter(ch) || ((ch == "'" || ch == "’") && !word.is_empty()) {
                word.push_str(ch);
                continue;
            }
            if !word.is_empty() {
                emit(&mut out, &mut prev, word_token(&word));
                word.clear();
            }
            match ch {
                "." | "!" | "?" | "\n" => emit(&mut out, &mut prev, 1),
                "," | ";" | ":" => emit(&mut out, &mut prev, 2),
                " " => {}
                _ => {
                    let skip = ["\"", "'", "(", ")", "[", "]", "-", "–", "—", "*"].contains(&ch) && prev == 1;
                    if !skip {
                        emit(&mut out, &mut prev, 3);
                    }
                }
            }
        }
        if !word.is_empty() {
            emit(&mut out, &mut prev, word_token(&word));
        }
        out
    }

    /// Khả năng của từng từ của mạng đi tiếp sau `before` (theo id của mạng). Chữ nối tiếp lần gọi trước chỉ tốn
    /// một bước cho mỗi token mới.
    pub(crate) fn next(&mut self, nn: &NnData, words: &LmData, before: &str) -> &[f32] {
        if self.probs_ready && self.fed_text.as_deref() == Some(before) {
            return &self.probs;
        }
        let resume = match &self.fed_text {
            Some(fed) if !fed.is_empty() && text::has_prefix(before, fed) && text::last(fed) == Some(" ") => {
                Some(fed.len())
            }
            _ => None,
        };
        if let Some(n) = resume {
            for t in Self::tokens(nn, words, &before[n..], self.last_token) {
                self.step(nn, t);
            }
        } else {
            self.hs.fill(0.0);
            self.cs.fill(0.0);
            let tail = text::suffix(before, 300);
            let cut = tail.len() != before.len();
            let mut toks = Self::tokens(nn, words, tail, if cut { 3 } else { 1 });
            if cut && !toks.is_empty() {
                toks.remove(0); // từ đầu của đoạn cắt có thể dở
            }
            self.last_token = 1;
            self.step(nn, 1);
            for &t in &toks[toks.len().saturating_sub(WINDOW)..] {
                self.step(nn, t);
            }
        }
        self.fed_text = Some(before.to_string());
        // z = proj(h); p = softmax(emb · z + outB)
        affine(nn.f32s(nn.proj_w, nn.e * nn.h), nn.h, &self.hs, Some(nn.f32s(nn.proj_b, nn.e)), &mut self.z);
        affine(nn.f32s(nn.emb, nn.v * nn.e), nn.e, &self.z, Some(nn.f32s(nn.out_b, nn.v)), &mut self.probs);
        let mx = self.probs.iter().copied().fold(f32::NEG_INFINITY, f32::max);
        let mut sum = 0f32;
        for p in self.probs.iter_mut() {
            *p = (*p - mx).exp();
            sum += *p;
        }
        let inv = 1.0 / sum;
        for p in self.probs.iter_mut() {
            *p *= inv;
        }
        self.probs_ready = true;
        &self.probs
    }
}
