//! Mô hình bigram từ (dữ liệu libpinyin, GPL-3; dựng bằng scripts/make-bigram.py): P(w2 | w1) nội suy với unigram
//! của từ điển, để khi ghép câu chọn 在/再, 是/时/事 theo từ đứng trước thay vì chỉ theo tần suất riêng lẻ.
//! bigram.bin (VPBG, docs/data-format.md): mảng khoá FNV-1a 64 đã sắp xếp + mảng số đếm, tra bằng tìm kiếm nhị phân.

use std::path::Path;

use crate::table::{u32_at, Bytes};
use crate::CoreError;

pub struct BigramModel {
    data: Bytes,
    uni_keys: usize,
    uni_counts: usize,
    pair_keys: usize,
    pair_counts: usize,
    unigrams: usize,
    pairs: usize,
    /// Trọng số của bigram so với unigram khi nội suy (0.7 đúng nhất trên bộ 50 câu thử).
    pub lambda: f64,
}

impl BigramModel {
    pub fn open(path: &Path) -> Result<BigramModel, CoreError> {
        Self::new(Bytes::open(path)?)
    }

    pub fn from_bytes(bytes: Vec<u8>) -> Result<BigramModel, CoreError> {
        Self::new(Bytes::Owned(bytes))
    }

    fn new(data: Bytes) -> Result<BigramModel, CoreError> {
        let b = data.as_slice();
        if b.len() < 16 || &b[0..4] != b"VPBG" || u32_at(b, 4) != 1 {
            return Err(CoreError::BadFormat("VPBG header".into()));
        }
        let unigrams = u32_at(b, 8);
        let pairs = u32_at(b, 12);
        let uni_keys = 16;
        let uni_counts = uni_keys + unigrams * 8;
        let pair_keys = uni_counts + unigrams * 4;
        let pair_counts = pair_keys + pairs * 8;
        if pair_counts + pairs * 4 != b.len() {
            return Err(CoreError::BadFormat("VPBG size".into()));
        }
        Ok(BigramModel { data, uni_keys, uni_counts, pair_keys, pair_counts, unigrams, pairs, lambda: 0.7 })
    }

    pub(crate) fn fnv1a(s: &str) -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        for b in s.bytes() {
            h = (h ^ b as u64).wrapping_mul(0x0000_0100_0000_01b3);
        }
        h
    }

    fn count(&self, key: u64, keys: usize, counts: usize, n: usize) -> Option<u32> {
        let b = self.data.as_slice();
        let (mut lo, mut hi) = (0, n);
        while lo < hi {
            let mid = (lo + hi) / 2;
            let at = keys + mid * 8;
            let k = u64::from_le_bytes(b[at..at + 8].try_into().unwrap());
            if k == key {
                return Some(u32_at(b, counts + mid * 4) as u32);
            }
            if k < key {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        None
    }

    /// log P(w2 | w1) = log(λ·c12/c1 + (1-λ)·P(w2)). w1 không có trong corpus coi như c12 = 0,
    /// vẫn chịu hệ số (1-λ) để từ hiếm không được "miễn phạt" khi đứng trước.
    pub fn log_prob(&self, w1: &str, w2: &str, unigram: f64) -> f64 {
        let c1 = self.count(Self::fnv1a(w1), self.uni_keys, self.uni_counts, self.unigrams);
        let c12 = self.count(Self::fnv1a(&format!("{w1}\t{w2}")), self.pair_keys, self.pair_counts, self.pairs);
        match (c1, c12) {
            (Some(c1), Some(c12)) if c1 > 0 => {
                (self.lambda * c12 as f64 / c1 as f64 + (1.0 - self.lambda) * unigram).ln()
            }
            _ => ((1.0 - self.lambda) * unigram).ln(),
        }
    }
}
