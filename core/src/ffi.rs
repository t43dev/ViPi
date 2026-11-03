//! Giao diện cho Swift (iOS, macOS) và Kotlin (Android), sinh bằng uniffi:
//!   cargo run --features bindgen --bin uniffi-bindgen -- generate --library <libvipi_core> --language kotlin|swift
//! Một `ViPiComposer` cho mỗi bàn phím; mọi hàm an toàn khi gọi từ nhiều luồng (khoá bên trong).

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};

use crate::composer::{self, Composer};
use crate::pinyin::FuzzyRule;
use crate::CoreError;

#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum InputMode {
    Vietnamese,
    Chinese,
    English,
}

impl From<composer::Mode> for InputMode {
    fn from(m: composer::Mode) -> Self {
        match m {
            composer::Mode::Vietnamese => InputMode::Vietnamese,
            composer::Mode::Chinese => InputMode::Chinese,
            composer::Mode::English => InputMode::English,
        }
    }
}

impl From<InputMode> for composer::Mode {
    fn from(m: InputMode) -> Self {
        match m {
            InputMode::Vietnamese => composer::Mode::Vietnamese,
            InputMode::Chinese => composer::Mode::Chinese,
            InputMode::English => composer::Mode::English,
        }
    }
}

/// Phím đã giải mã. `Text` mang đúng một ký tự in được (chữ, số, dấu câu) như người dùng gõ.
#[derive(uniffi::Enum, Clone, PartialEq, Eq, Debug)]
pub enum KeyInput {
    Text { text: String },
    Space,
    Enter,
    Tab,
    Backspace,
    Escape,
    Left,
    Right,
    Up,
    Down,
    PageUp,
    PageDown,
    Other,
}

impl From<KeyInput> for composer::Key {
    fn from(k: KeyInput) -> Self {
        use composer::Key as K;
        match k {
            KeyInput::Text { text } => {
                let mut cs = text.chars();
                match (cs.next(), cs.next()) {
                    (Some(' '), None) => K::Space,
                    (Some(c), None) => K::Char(c),
                    _ => K::Other,
                }
            }
            KeyInput::Space => K::Space,
            KeyInput::Enter => K::Enter,
            KeyInput::Tab => K::Tab,
            KeyInput::Backspace => K::Backspace,
            KeyInput::Escape => K::Escape,
            KeyInput::Left => K::Left,
            KeyInput::Right => K::Right,
            KeyInput::Up => K::Up,
            KeyInput::Down => K::Down,
            KeyInput::PageUp => K::PageUp,
            KeyInput::PageDown => K::PageDown,
            KeyInput::Other => K::Other,
        }
    }
}

/// Xoá `backspaces` ký tự trước con trỏ rồi chèn `insert`.
#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct Edit {
    pub backspaces: u32,
    pub insert: String,
}

/// Việc nền tảng phải làm sau một phím (xem composer::KeyResult).
#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct KeyOutcome {
    pub handled: bool,
    pub edit: Option<Edit>,
    pub whole_word: bool,
    pub repost_key: bool,
    pub switched_to: Option<InputMode>,
    pub panel_changed: bool,
}

impl From<composer::KeyResult> for KeyOutcome {
    fn from(r: composer::KeyResult) -> Self {
        KeyOutcome {
            handled: r.handled,
            edit: r.edit.map(|e| Edit { backspaces: e.backspaces as u32, insert: e.insert }),
            whole_word: r.whole_word,
            repost_key: r.repost_key,
            switched_to: r.switched_to.map(Into::into),
            panel_changed: r.panel_changed,
        }
    }
}

#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct CandidatePanel {
    pub preedit: String,
    pub items: Vec<String>,
    pub highlight: u32,
    pub has_prev: bool,
    pub has_next: bool,
    pub first_index: u32,
}

#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct Candidate {
    pub text: String,
    pub length: u32,
}

#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct FuzzyOption {
    pub id: String,
    pub label: String,
}

#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct Shortcut {
    pub key: String,
    pub text: String,
}

/// Các âm mờ có thể bật (id dùng cho `set_fuzzy_rules`).
#[uniffi::export]
pub fn fuzzy_options() -> Vec<FuzzyOption> {
    FuzzyRule::ALL.iter().map(|r| FuzzyOption { id: r.id(), label: r.label() }).collect()
}

#[derive(uniffi::Object)]
pub struct ViPiComposer {
    inner: Mutex<Composer>,
}

impl ViPiComposer {
    fn lock(&self) -> MutexGuard<'_, Composer> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
}

#[uniffi::export]
impl ViPiComposer {
    /// `resource_dir`: thư mục chứa vietnamese-syllables.txt và các file .bin của ViPi.
    #[uniffi::constructor]
    pub fn new(resource_dir: String) -> Result<Arc<Self>, CoreError> {
        Ok(Arc::new(ViPiComposer { inner: Mutex::new(Composer::open(&PathBuf::from(resource_dir))?) }))
    }

    pub fn handle_key(&self, key: KeyInput) -> KeyOutcome {
        self.lock().handle_key(key.into()).into()
    }

    pub fn select_candidate(&self, index: u32) -> KeyOutcome {
        self.lock().select_candidate(index as usize).into()
    }

    pub fn cancel(&self) {
        self.lock().cancel()
    }

    pub fn mode(&self) -> InputMode {
        self.lock().mode().into()
    }

    pub fn set_mode(&self, mode: InputMode) {
        self.lock().set_mode(mode.into())
    }

    pub fn current_word(&self) -> String {
        self.lock().current_word()
    }

    pub fn preedit(&self) -> String {
        self.lock().preedit()
    }

    pub fn is_composing_chinese(&self) -> bool {
        self.lock().is_composing_chinese()
    }

    pub fn candidates(&self) -> Vec<Candidate> {
        self.lock().candidates().iter().map(|c| Candidate { text: c.text.clone(), length: c.length as u32 }).collect()
    }

    pub fn panel(&self) -> Option<CandidatePanel> {
        self.lock().panel().map(|p| CandidatePanel {
            preedit: p.preedit,
            items: p.items,
            highlight: p.highlight as u32,
            has_prev: p.has_prev,
            has_next: p.has_next,
            first_index: p.first_index as u32,
        })
    }

    pub fn set_page_size(&self, size: u32) {
        self.lock().page_size = size.max(1) as usize;
    }

    pub fn set_vietnamese_options(&self, modern_tone_style: bool, spell_check: bool, restore_non_vietnamese: bool) {
        self.lock().set_vietnamese_options(modern_tone_style, spell_check, restore_non_vietnamese)
    }

    pub fn set_shortcuts(&self, shortcuts: Vec<Shortcut>, in_vietnamese: bool, in_english: bool) {
        let pairs: Vec<(String, String)> = shortcuts.into_iter().map(|s| (s.key, s.text)).collect();
        self.lock().set_macros(&pairs, in_vietnamese, in_english)
    }

    pub fn set_full_width_punctuation(&self, on: bool) {
        self.lock().full_width_punctuation = on;
    }

    pub fn set_fuzzy_rules(&self, ids: Vec<String>) {
        self.lock().set_fuzzy_rules(ids.into_iter().collect::<HashSet<String>>())
    }

    pub fn set_traditional(&self, on: bool) {
        self.lock().set_traditional(on)
    }

    /// `file`: nơi lưu từ đã học (JSON), None = chỉ trong bộ nhớ.
    pub fn set_learning(&self, on: bool, file: Option<String>) {
        self.lock().set_learning(on, file.map(PathBuf::from))
    }

    pub fn clear_learned(&self) {
        self.lock().clear_learned()
    }

    pub fn learned_count(&self) -> u32 {
        self.lock().learned_count() as u32
    }

    pub fn set_auto_switch(&self, on: bool) {
        self.lock().set_auto_switch(on)
    }

    /// Gọi khi người dùng tự đổi chế độ: tự đổi Anh/Việt nghỉ 5 giây.
    pub fn pause_auto_switch(&self) {
        self.lock().pause_auto_switch()
    }
}
