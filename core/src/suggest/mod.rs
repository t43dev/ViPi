//! Gợi ý từ cho bàn phím Việt · Anh: mô hình từ (`lm`, `nn`), mô hình chạm (`tap`), danh sách giữ nguyên (`keep`)
//! và các luật của ViPi nối chúng với bàn phím (`suggester`). Chuyển từ bản iOS (ios/ViPiKeyboard/Suggest/), vốn lấy
//! từ Vikey (github.com/tonyminibot/Vikey, GPL-3.0), để Android và HarmonyOS dùng qua FFI.
//!
//! Dữ liệu: bốn file mô hình (SuggestEN/NN/VI/VINN.bin, scripts/suggest-models.sh) và Resources/keep-words*.txt,
//! cùng một thư mục.

mod keep;
pub mod lm;
mod nn;
mod suggester;
pub mod tap;
mod text;
#[rustfmt::skip]
mod unicode_tables;

pub use keep::KeepWords;
pub use lm::{telex_spellings, Context, KeyRect, LmData, Reading, SuggestLm};
pub use suggester::{looks_typed, Models, Suggester, Suggestion, EN_FILES, VI_FILES};
pub use tap::{TapKind, TapParams, TouchKey};
