//! Cầu nối NAPI từ lõi ViPi (Rust) sang bàn phím HarmonyOS: `import vipi from 'libvipi.so'`.
//! Mỗi tiến trình bàn phím có đúng một Composer (biến toàn cục có khoá). Mỗi phím là một lần gọi: kết quả trả về
//! gồm cả việc phải làm với ô nhập lẫn trạng thái để vẽ lại thanh gợi ý, nên ArkTS không phải gọi thêm.
//! Theo lưu ý của ohos-rs: không dùng tham số Option (ArkTS báo typeof sai), "không có" là -1 hoặc chuỗi rỗng.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};

use napi_derive_ohos::napi;
use vipi_core::composer::{Composer, Key, KeyResult, Mode};
use vipi_core::pinyin::FuzzyRule;

static ENGINE: Mutex<Option<Composer>> = Mutex::new(None);

/// Ứng viên chữ Hán gửi sang ArkTS mỗi phím: đủ cho thanh ứng viên và lưới mở rộng.
const MAX_CANDIDATES: usize = 300;

fn engine() -> MutexGuard<'static, Option<Composer>> {
    ENGINE.lock().unwrap_or_else(|e| e.into_inner())
}

fn mode_code(m: Mode) -> i32 {
    match m {
        Mode::Vietnamese => 0,
        Mode::Chinese => 1,
        Mode::English => 2,
    }
}

fn mode_from(code: i32) -> Mode {
    match code {
        1 => Mode::Chinese,
        2 => Mode::English,
        _ => Mode::Vietnamese,
    }
}

/// Mã phím từ ArkTS (khớp `KeyKind` trong Engine.ets).
fn key_from(kind: i32, text: &str) -> Key {
    match kind {
        0 => {
            let mut cs = text.chars();
            match (cs.next(), cs.next()) {
                (Some(' '), None) => Key::Space,
                (Some(c), None) => Key::Char(c),
                _ => Key::Other,
            }
        }
        1 => Key::Space,
        2 => Key::Enter,
        3 => Key::Tab,
        4 => Key::Backspace,
        5 => Key::Escape,
        6 => Key::Left,
        7 => Key::Right,
        8 => Key::Up,
        9 => Key::Down,
        10 => Key::PageUp,
        11 => Key::PageDown,
        _ => Key::Other,
    }
}

/// Việc phải làm sau một phím, cùng trạng thái mới của lõi.
#[napi(object)]
pub struct Outcome {
    /// false: phím đi thẳng tới ô nhập như bàn phím thường.
    pub handled: bool,
    /// Có `edit`: xoá `backspaces` ký tự trước con trỏ rồi chèn `insert`.
    pub has_edit: bool,
    pub backspaces: i32,
    pub insert: String,
    pub whole_word: bool,
    /// Sau `edit`, gửi lại phím gốc.
    pub repost_key: bool,
    /// Tự đổi Anh/Việt vừa đổi chế độ: mã chế độ mới, -1 nếu không đổi.
    pub switched_to: i32,
    /// 0 Việt, 1 Trung, 2 Anh.
    pub mode: i32,
    /// Từ tiếng Việt đang gõ: chữ đang hiện và các phím đã gõ.
    pub word: String,
    pub keys: String,
    /// Pinyin đang gõ (chưa chọn chữ Hán).
    pub preedit: String,
    pub composing_chinese: bool,
    pub candidates: Vec<String>,
}

fn outcome(c: &Composer, r: KeyResult) -> Outcome {
    let (has_edit, backspaces, insert) = match r.edit {
        Some(e) => (true, e.backspaces as i32, e.insert),
        None => (false, 0, String::new()),
    };
    let composing = c.is_composing_chinese();
    Outcome {
        handled: r.handled,
        has_edit,
        backspaces,
        insert,
        whole_word: r.whole_word,
        repost_key: r.repost_key,
        switched_to: r.switched_to.map(mode_code).unwrap_or(-1),
        mode: mode_code(c.mode()),
        word: c.current_word(),
        keys: c.current_keys(),
        preedit: c.preedit(),
        composing_chinese: composing,
        candidates: if composing {
            c.candidates().iter().take(MAX_CANDIDATES).map(|x| x.text.clone()).collect()
        } else {
            Vec::new()
        },
    }
}

fn empty() -> Outcome {
    Outcome {
        handled: false,
        has_edit: false,
        backspaces: 0,
        insert: String::new(),
        whole_word: false,
        repost_key: false,
        switched_to: -1,
        mode: 2,
        word: String::new(),
        keys: String::new(),
        preedit: String::new(),
        composing_chinese: false,
        candidates: Vec::new(),
    }
}

/// Nạp dữ liệu từ `dir` (thư mục chứa vietnamese-syllables.txt và các file .bin).
/// Trả về "" nếu được, hoặc lời báo lỗi. Gọi lại khi đã nạp thì không làm gì.
#[napi]
pub fn open(dir: String) -> String {
    let mut g = engine();
    if g.is_some() {
        return String::new();
    }
    match Composer::open(Path::new(&dir)) {
        Ok(mut c) => {
            // Việt và Anh là một bộ gõ, luôn tự nhận diện (như Android)
            c.set_auto_switch(true);
            *g = Some(c);
            String::new()
        }
        Err(e) => e.to_string(),
    }
}

#[napi]
pub fn is_open() -> bool {
    engine().is_some()
}

#[napi]
pub fn handle_key(kind: i32, text: String) -> Outcome {
    let mut g = engine();
    let Some(c) = g.as_mut() else { return empty() };
    let r = c.handle_key(key_from(kind, &text));
    outcome(c, r)
}

#[napi]
pub fn select_candidate(index: i32) -> Outcome {
    let mut g = engine();
    let Some(c) = g.as_mut() else { return empty() };
    let r = c.select_candidate(index.max(0) as usize);
    outcome(c, r)
}

/// Trạng thái hiện tại (không có việc gì với ô nhập).
#[napi]
pub fn state() -> Outcome {
    let g = engine();
    match g.as_ref() {
        Some(c) => outcome(c, KeyResult::default()),
        None => empty(),
    }
}

/// Bỏ phần đang gõ dở (đổi ô nhập, con trỏ bị dời, bàn phím ẩn).
#[napi]
pub fn cancel() {
    if let Some(c) = engine().as_mut() {
        c.cancel();
    }
}

#[napi]
pub fn set_mode(mode: i32) {
    if let Some(c) = engine().as_mut() {
        c.set_mode(mode_from(mode));
    }
}

/// Người dùng tự đổi chế độ: tự đổi Anh/Việt nghỉ một lúc.
#[napi]
pub fn pause_auto_switch() {
    if let Some(c) = engine().as_mut() {
        c.pause_auto_switch();
    }
}

/// Áp cài đặt. `learn_file`: nơi lưu từ đã học, "" = chỉ trong bộ nhớ.
#[napi]
#[allow(clippy::too_many_arguments)]
pub fn configure(
    modern_tone: bool,
    spell_check: bool,
    restore: bool,
    full_width: bool,
    traditional: bool,
    learn: bool,
    learn_file: String,
    fuzzy: Vec<String>,
) {
    let mut g = engine();
    let Some(c) = g.as_mut() else { return };
    c.set_vietnamese_options(modern_tone, spell_check, restore);
    c.full_width_punctuation = full_width;
    c.set_traditional(traditional);
    c.set_fuzzy_rules(fuzzy.into_iter().collect::<HashSet<String>>());
    c.set_learning(learn, (!learn_file.is_empty()).then(|| PathBuf::from(learn_file)));
}

#[napi]
pub fn clear_learned() {
    if let Some(c) = engine().as_mut() {
        c.clear_learned();
    }
}

#[napi]
pub fn learned_count() -> i32 {
    engine().as_ref().map(|c| c.learned_count() as i32).unwrap_or(0)
}

#[napi(object)]
pub struct FuzzyOption {
    pub id: String,
    pub label: String,
}

/// Các âm mờ có thể bật (id dùng cho `configure`).
#[napi]
pub fn fuzzy_options() -> Vec<FuzzyOption> {
    FuzzyRule::ALL.iter().map(|r| FuzzyOption { id: r.id(), label: r.label() }).collect()
}
