//! Lõi bộ gõ ViPi, dùng chung cho Android, iOS và macOS: Telex tiếng Việt, Pinyin tiếng Trung,
//! tự đổi Anh/Việt, gõ tắt, và `Composer` điều phối theo chế độ. Dữ liệu là các bảng nhị phân
//! trong Resources/ (docs/data-format.md), đọc bằng mmap.
//!
//! Nguồn: luật Telex và bảng nguyên âm theo UniKey (GPL); từ điển Pinyin rime-ice (GPL-3.0); mô hình bigram
//! từ libpinyin (GPL-3.0); bảng phồn thể OpenCC (Apache-2.0); tự đổi Anh/Việt theo Vikey (GPL-3.0) với tần suất
//! từ FrequencyWords (CC BY-SA 4.0); danh sách âm tiết từ danh sách từ của Hồ Ngọc Đức (GPL).

pub mod autoswitch;
pub mod bigram;
pub mod composer;
pub mod convert;
pub mod pinyin;
pub mod table;
pub mod telex;
pub mod userdict;

#[cfg(feature = "uniffi")]
mod ffi;

#[cfg(feature = "uniffi")]
uniffi::setup_scaffolding!();

pub use composer::{Composer, Key, KeyResult, Mode, Panel};
pub use telex::{MacroTable, TelexEngine, TextEdit, VietnameseLexicon};

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Error))]
pub enum CoreError {
    Io(String),
    BadFormat(String),
}

impl std::fmt::Display for CoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CoreError::Io(s) => write!(f, "cannot read {s}"),
            CoreError::BadFormat(s) => write!(f, "bad data file: {s}"),
        }
    }
}

impl std::error::Error for CoreError {}
