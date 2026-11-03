//! Bảng khoá → giá trị trong file nhị phân VPST (docs/data-format.md, dựng bằng scripts/build-tables.py):
//! khoá UTF-8 sắp xếp theo byte, tra bằng tìm kiếm nhị phân. Đọc thẳng từ file ánh xạ vào bộ nhớ (mmap)
//! hoặc từ một vùng nhớ có sẵn (Android: asset không nén).

use std::cmp::Ordering;
use std::fs::File;
use std::path::Path;

use crate::CoreError;

/// Dữ liệu chỉ đọc: file mmap hoặc bản sao trong bộ nhớ.
pub(crate) enum Bytes {
    Mapped(memmap2::Mmap),
    Owned(Vec<u8>),
}

impl Bytes {
    pub(crate) fn open(path: &Path) -> Result<Bytes, CoreError> {
        let file = File::open(path).map_err(|e| CoreError::Io(format!("{}: {e}", path.display())))?;
        // SAFETY: file dữ liệu đi kèm app, chỉ đọc, không ai ghi vào khi đang chạy
        let map =
            unsafe { memmap2::Mmap::map(&file) }.map_err(|e| CoreError::Io(format!("{}: {e}", path.display())))?;
        Ok(Bytes::Mapped(map))
    }

    pub(crate) fn as_slice(&self) -> &[u8] {
        match self {
            Bytes::Mapped(m) => m,
            Bytes::Owned(v) => v,
        }
    }
}

pub(crate) fn u32_at(b: &[u8], at: usize) -> usize {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]]) as usize
}

pub struct SortedTable {
    data: Bytes,
    count: usize,
    meta: f64,
    keys: usize,
    values: usize,
}

const KEY_OFFSETS: usize = 24;

impl SortedTable {
    pub fn open(path: &Path) -> Result<SortedTable, CoreError> {
        Self::new(Bytes::open(path)?)
    }

    pub fn from_bytes(bytes: Vec<u8>) -> Result<SortedTable, CoreError> {
        Self::new(Bytes::Owned(bytes))
    }

    fn new(data: Bytes) -> Result<SortedTable, CoreError> {
        let b = data.as_slice();
        let size = b.len();
        if size < 24 || &b[0..4] != b"VPST" || u32_at(b, 4) != 1 {
            return Err(CoreError::BadFormat("VPST header".into()));
        }
        let count = u32_at(b, 8);
        let keys = 24 + 2 * (count + 1) * 4;
        if keys > size || keys + u32_at(b, 24 + count * 4) + u32_at(b, keys - 4) != size {
            return Err(CoreError::BadFormat("VPST size".into()));
        }
        let meta = f64::from_bits(u64::from_le_bytes(b[16..24].try_into().unwrap()));
        let values = keys + u32_at(b, 24 + count * 4);
        Ok(SortedTable { data, count, meta, keys, values })
    }

    pub fn len(&self) -> usize {
        self.count
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }

    /// Số riêng của từng bảng (pinyin-words.bin: tổng weight).
    pub fn meta(&self) -> f64 {
        self.meta
    }

    fn bytes(&self) -> &[u8] {
        self.data.as_slice()
    }

    /// Byte UTF-8 của khoá thứ `i`.
    pub fn key(&self, i: usize) -> &[u8] {
        let b = self.bytes();
        let start = u32_at(b, KEY_OFFSETS + i * 4);
        let end = u32_at(b, KEY_OFFSETS + i * 4 + 4);
        &b[self.keys + start..self.keys + end]
    }

    /// Giá trị của khoá thứ `i`.
    pub fn value(&self, i: usize) -> &[u8] {
        let b = self.bytes();
        let vo = KEY_OFFSETS + (self.count + 1) * 4;
        let start = u32_at(b, vo + i * 4);
        let end = u32_at(b, vo + i * 4 + 4);
        &b[self.values + start..self.values + end]
    }

    /// `n` byte bắt đầu tại vị trí `offset` của khối giá trị (bảng trỏ sang mục của bảng khác).
    pub fn values_at(&self, offset: usize, n: usize) -> &[u8] {
        &self.bytes()[self.values + offset..self.values + offset + n]
    }

    /// Chỉ số khoá đầu tiên ≥ `key` (so theo byte).
    pub fn lower_bound(&self, key: &[u8]) -> usize {
        let (mut lo, mut hi) = (0, self.count);
        while lo < hi {
            let mid = (lo + hi) / 2;
            if self.key(mid).cmp(key) == Ordering::Less {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        lo
    }

    pub fn index_of(&self, key: &str) -> Option<usize> {
        let k = key.as_bytes();
        let i = self.lower_bound(k);
        (i < self.count && self.key(i) == k).then_some(i)
    }

    pub fn get(&self, key: &str) -> Option<&[u8]> {
        self.index_of(key).map(|i| self.value(i))
    }

    /// Có khoá nào bắt đầu bằng `prefix` không.
    pub fn has_key_with_prefix(&self, prefix: &str) -> bool {
        let p = prefix.as_bytes();
        let i = self.lower_bound(p);
        i < self.count && self.key(i).starts_with(p)
    }
}
