//! Bộ điều phối dùng chung cho mọi nền tảng: nhận phím (đã giải mã) theo chế độ Việt / Trung / Anh, gọi Telex,
//! Pinyin, gõ tắt và tự đổi Anh/Việt, rồi trả về việc nền tảng phải làm (xoá/chèn chữ, cho phím đi qua, đổi chế độ).
//! Phần riêng của từng nền tảng (bắt phím, gửi phím giả, vẽ khung chọn chữ, vị trí con trỏ) nằm ngoài.
//! Hành vi giống InputController.swift của bản macOS 0.4.0.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::autoswitch::AutoSwitch;
use crate::bigram::BigramModel;
use crate::convert::ChineseConverter;
use crate::pinyin::{PinyinCandidate, PinyinDictionary, PinyinEngine};
use crate::telex::{MacroTable, TelexEngine, TextEdit, VietnameseLexicon};
use crate::userdict::PinyinUserDictionary;
use crate::CoreError;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    Vietnamese,
    Chinese,
    English,
}

/// Phím đã giải mã. `Char` là ký tự in được đúng như người dùng gõ (đã tính Shift / bố cục bàn phím).
/// Phím có Command / Control / Option: nền tảng gọi `cancel()` và cho đi qua, không gửi vào đây.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Key {
    Char(char),
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
    /// Phím không in ra chữ khác (Home, End, F1…): kết thúc từ, cho đi qua.
    Other,
}

impl Key {
    /// Ký tự phím này gõ ra (như chuỗi Unicode của sự kiện phím trên macOS).
    fn typed(self) -> Option<char> {
        match self {
            Key::Char(c) => Some(c),
            Key::Space => Some(' '),
            Key::Enter => Some('\r'),
            Key::Tab => Some('\t'),
            Key::Escape => Some('\u{1b}'),
            _ => None,
        }
    }
}

/// Việc nền tảng phải làm sau một phím.
#[derive(Clone, PartialEq, Eq, Debug, Default)]
pub struct KeyResult {
    /// false: phím gốc đi thẳng tới ứng dụng như bình thường (không có `edit`).
    /// true: phím gốc bị chặn; áp `edit` (nếu có), rồi gửi lại phím gốc nếu `repost_key`.
    pub handled: bool,
    pub edit: Option<TextEdit>,
    /// `edit` thay cả từ đang gõ (xoá lùi tới tận đầu từ).
    pub whole_word: bool,
    pub repost_key: bool,
    /// Tự đổi Anh/Việt vừa đổi chế độ (Composer đã tự đổi; nền tảng cập nhật giao diện).
    pub switched_to: Option<Mode>,
    /// Khung chọn chữ Hán cần vẽ lại (`panel()`), hoặc ẩn nếu `panel()` là None.
    pub panel_changed: bool,
}

impl KeyResult {
    fn pass() -> KeyResult {
        KeyResult::default()
    }

    fn swallow() -> KeyResult {
        KeyResult { handled: true, ..Default::default() }
    }
}

/// Một trang của khung chọn chữ Hán.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Panel {
    pub preedit: String,
    pub items: Vec<String>,
    pub highlight: usize,
    pub has_prev: bool,
    pub has_next: bool,
    /// Chỉ số (trong `candidates()`) của ô đầu trang.
    pub first_index: usize,
}

const WORD_END_FOR_AUTO_SWITCH: &str = " \r\t,.;!?)'\"";

/// Ngay sau một lần tự đổi: Backspace xoá chữ đã sửa cùng phím kết thúc từ (`remove`), gõ lại `text`
/// (chữ trước khi sửa) và về chế độ cũ, như Vikey.
struct Undo {
    remove: usize,
    text: String,
    keys: Vec<char>,
    mode: Mode,
}

pub struct Composer {
    mode: Mode,
    pub full_width_punctuation: bool,
    macros: Option<MacroTable>,         // gõ tắt khi gõ tiếng Việt, None: tắt
    english_macros: Option<MacroTable>, // gõ tắt khi gõ tiếng Anh, None: tắt
    auto_switch_tables: Option<AutoSwitch>,
    auto_switch_enabled: bool,
    auto_switch_paused_until: Option<Instant>,
    english_word: Vec<char>,        // chữ cái của từ đang gõ ở chế độ tiếng Anh
    undo: Option<Undo>,             // ngay sau một lần tự đổi: Backspace trả lại chữ trước đó
    undone_keys: Option<Vec<char>>, // từ vừa được trả lại bằng Backspace: kết thúc lại nó thì không tự đổi nữa
    at_word_start: bool,            // từ đang gõ đứng sau dấu cách/đầu dòng (không dính sau số, @, ...)
    telex: TelexEngine,
    lexicon: Option<Arc<VietnameseLexicon>>,
    restore_non_vietnamese: bool,
    pinyin: Option<PinyinEngine>,
    bigram: Option<Arc<BigramModel>>,
    traditional: Option<Arc<ChineseConverter>>,
    page: usize,
    highlight: usize,
    pub page_size: usize,
}

/// Các file trong thư mục dữ liệu (Resources của app).
pub struct ResourceFiles;

impl ResourceFiles {
    pub const SYLLABLES: &'static str = "vietnamese-syllables.txt";
    pub const BIGRAM: &'static str = "bigram.bin";
    pub const TRADITIONAL: &'static str = "s2t.bin";
}

impl Composer {
    /// Không có dữ liệu: chỉ Telex (không trả lại chữ không phải tiếng Việt), không có Pinyin / tự đổi.
    pub fn bare() -> Composer {
        Composer {
            mode: Mode::Vietnamese,
            full_width_punctuation: true,
            macros: None,
            english_macros: None,
            auto_switch_tables: None,
            auto_switch_enabled: false,
            auto_switch_paused_until: None,
            english_word: vec![],
            undo: None,
            undone_keys: None,
            at_word_start: true,
            telex: TelexEngine::new(),
            lexicon: None,
            restore_non_vietnamese: true,
            pinyin: None,
            bigram: None,
            traditional: None,
            page: 0,
            highlight: 0,
            page_size: 9,
        }
    }

    /// Nạp toàn bộ dữ liệu từ thư mục `dir` (danh sách âm tiết, từ điển pinyin, bigram, phồn thể, tự đổi).
    pub fn open(dir: &Path) -> Result<Composer, CoreError> {
        let mut c = Composer::bare();
        let syllables = std::fs::read_to_string(dir.join(ResourceFiles::SYLLABLES))
            .map_err(|e| CoreError::Io(format!("{}: {e}", ResourceFiles::SYLLABLES)))?;
        c.lexicon = Some(Arc::new(VietnameseLexicon::new(&syllables)));
        c.bigram = Some(Arc::new(BigramModel::open(&dir.join(ResourceFiles::BIGRAM))?));
        c.traditional = Some(Arc::new(ChineseConverter::open(&dir.join(ResourceFiles::TRADITIONAL))?));
        let mut py = PinyinEngine::new(Arc::new(PinyinDictionary::open(dir)?));
        py.set_bigram(c.bigram.clone());
        c.pinyin = Some(py);
        c.auto_switch_tables = Some(AutoSwitch::open(dir)?);
        c.apply_lexicon();
        Ok(c)
    }

    // MARK: - Cài đặt

    pub fn mode(&self) -> Mode {
        self.mode
    }

    /// Đổi chế độ (bằng tay hoặc tự đổi): bỏ phần đang gõ dở.
    pub fn set_mode(&mut self, mode: Mode) {
        self.mode = mode;
        self.cancel();
    }

    pub fn set_vietnamese_options(&mut self, modern_tone_style: bool, spell_check: bool, restore_non_vietnamese: bool) {
        self.telex.modern_tone_style = modern_tone_style;
        self.telex.spell_check = spell_check;
        self.restore_non_vietnamese = restore_non_vietnamese;
        self.apply_lexicon();
    }

    fn apply_lexicon(&mut self) {
        self.telex.lexicon =
            if self.telex.spell_check && self.restore_non_vietnamese { self.lexicon.clone() } else { None };
    }

    /// Gõ tắt: cùng một danh sách, bật riêng cho tiếng Việt và tiếng Anh.
    pub fn set_macros(&mut self, pairs: &[(String, String)], in_vietnamese: bool, in_english: bool) {
        let table = MacroTable::new(pairs);
        self.macros = in_vietnamese.then(|| table.clone());
        self.english_macros = in_english.then_some(table);
    }

    pub fn set_fuzzy_rules(&mut self, rules: HashSet<String>) {
        if let Some(py) = &mut self.pinyin {
            if *py.fuzzy_rules() != rules {
                py.set_fuzzy_rules(rules);
            }
        }
    }

    pub fn set_traditional(&mut self, on: bool) {
        let converter = if on { self.traditional.clone() } else { None };
        if let Some(py) = &mut self.pinyin {
            if py.has_converter() != converter.is_some() {
                py.set_converter(converter);
            }
        }
    }

    /// Học từ người dùng chọn. `file`: nơi lưu (JSON), None = chỉ trong bộ nhớ. `on` = false: tắt.
    pub fn set_learning(&mut self, on: bool, file: Option<PathBuf>) {
        let Some(py) = &mut self.pinyin else { return };
        if !on {
            py.user_dictionary = None;
            return;
        }
        let same = py.user_dictionary.as_ref().is_some_and(|d| d.file() == file.as_ref());
        if !same {
            py.user_dictionary = Some(match file {
                Some(f) => PinyinUserDictionary::with_file(f),
                None => PinyinUserDictionary::in_memory(),
            });
        }
    }

    pub fn clear_learned(&mut self) {
        if let Some(d) = self.pinyin.as_mut().and_then(|p| p.user_dictionary.as_mut()) {
            d.clear();
        }
    }

    pub fn learned_count(&self) -> usize {
        self.pinyin.as_ref().and_then(|p| p.user_dictionary.as_ref()).map_or(0, |d| d.count())
    }

    /// Tự đổi Anh/Việt (thử nghiệm). Bật lên thì nền tảng nên chuyển sang tiếng Anh như bản macOS.
    pub fn set_auto_switch(&mut self, on: bool) {
        self.auto_switch_enabled = on && self.auto_switch_tables.is_some();
        if !self.auto_switch_enabled {
            if let Some(a) = &mut self.auto_switch_tables {
                a.remember(None, false);
            }
        }
    }

    pub fn auto_switch_available(&self) -> bool {
        self.auto_switch_tables.is_some()
    }

    /// Người dùng tự đổi bộ gõ: tạm dừng tự đổi 5 giây (cách của Vikey).
    pub fn pause_auto_switch(&mut self) {
        self.pause_auto_switch_for(Duration::from_secs(5));
    }

    pub fn pause_auto_switch_for(&mut self, d: Duration) {
        self.auto_switch_paused_until = Some(Instant::now() + d);
    }

    // MARK: - Trạng thái

    /// Chữ đang hiện của từ tiếng Việt đang gõ (để nền tảng có ô soạn thảo hiển thị gạch chân).
    pub fn current_word(&self) -> String {
        self.telex.output()
    }

    pub fn is_composing_chinese(&self) -> bool {
        self.pinyin.as_ref().is_some_and(|p| p.is_composing())
    }

    pub fn preedit(&self) -> String {
        self.pinyin.as_ref().filter(|p| p.is_composing()).map(|p| p.preedit()).unwrap_or_default()
    }

    pub fn candidates(&self) -> &[PinyinCandidate] {
        self.pinyin.as_ref().map(|p| p.candidates()).unwrap_or(&[])
    }

    /// Trang hiện tại của khung chọn chữ, None khi không gõ chữ Hán.
    pub fn panel(&self) -> Option<Panel> {
        let py = self.pinyin.as_ref().filter(|p| p.is_composing())?;
        let start = self.page * self.page_size;
        let items = py.candidates().iter().skip(start).take(self.page_size).map(|c| c.text.clone()).collect();
        Some(Panel {
            preedit: py.preedit(),
            items,
            highlight: self.highlight,
            has_prev: self.page > 0,
            has_next: start + self.page_size < py.candidates().len(),
            first_index: start,
        })
    }

    /// Bỏ phần đang gõ dở (click chuột, phím tắt có Command/Control, đổi ô nhập).
    pub fn cancel(&mut self) {
        self.at_word_start = true;
        self.undo = None;
        self.undone_keys = None;
        if let Some(a) = &mut self.auto_switch_tables {
            a.remember(None, false);
        }
        self.english_word.clear();
        self.telex.reset();
        if let Some(py) = &mut self.pinyin {
            py.reset();
        }
        self.page = 0;
        self.highlight = 0;
    }

    // MARK: - Phím

    pub fn handle_key(&mut self, key: Key) -> KeyResult {
        if key == Key::Backspace {
            if let Some(u) = self.undo.take() {
                return self.undo_auto_switch(u);
            }
        }
        self.undo = None;
        match self.mode {
            Mode::English => self.handle_english(key),
            Mode::Vietnamese => self.handle_vietnamese(key),
            Mode::Chinese => self.handle_chinese(key),
        }
    }

    fn active_auto_switch(&self, typed: Option<char>) -> bool {
        self.auto_switch_enabled
            && self.auto_switch_paused_until.is_none_or(|t| Instant::now() >= t)
            && typed.is_some_and(|c| WORD_END_FOR_AUTO_SWITCH.contains(c))
    }

    fn remember(&mut self, word: Option<Vec<char>>, vietnamese: bool) {
        if self.auto_switch_enabled {
            if let Some(a) = &mut self.auto_switch_tables {
                a.remember(word, vietnamese);
            }
        }
    }

    /// Backspace ngay sau một lần tự đổi: bỏ chữ đã sửa và phím kết thúc từ, gõ lại chữ trước đó, về chế độ cũ.
    /// Về tiếng Anh thì các phím đó lại là từ đang gõ ("vaay" ⌫ rồi "j" → "vậy"); kết thúc lại y nguyên thì giữ.
    fn undo_auto_switch(&mut self, u: Undo) -> KeyResult {
        self.set_mode(u.mode);
        if u.mode == Mode::English {
            self.english_word = u.keys.clone();
            self.at_word_start = true;
            self.undone_keys = Some(u.keys);
        }
        KeyResult {
            handled: true,
            edit: Some(TextEdit::new(u.remove, u.text)),
            switched_to: Some(u.mode),
            ..Default::default()
        }
    }

    fn handle_vietnamese(&mut self, key: Key) -> KeyResult {
        if key == Key::Backspace {
            self.telex.backspace();
            return KeyResult::pass();
        }
        let typed = key.typed();
        let Some(ch) = typed.filter(|c| c.is_ascii_alphabetic()) else {
            // Space/Enter/Tab/dấu câu/số kết thúc từ: gõ tắt ("vn" → "Việt Nam"), hoặc chữ không phải
            // tiếng Việt thì gõ lại như đã gõ ("ủe" → "user"), rồi mới cho phím kết thúc từ đi qua
            let ascii = typed.filter(|c| c.is_ascii());
            let is_space = matches!(ascii, Some(' ' | '\r' | '\t'));
            let word = self.telex.keys().to_vec();
            let shown = self.telex.output();
            // gõ tắt chỉ khi từ đứng riêng và kết thúc bằng Space/Enter/Tab: "call2vn@" giữ nguyên
            let macro_edit = if is_space && self.at_word_start {
                self.macros.as_ref().and_then(|m| self.telex.expand_macro(m))
            } else {
                None
            };
            let auto = self.at_word_start && self.active_auto_switch(typed);
            self.at_word_start = is_space;
            if let Some(a) = ascii.filter(|&a| (' '..='~').contains(&a) || is_space) {
                let mut edit = macro_edit;
                let mut switch_to = None;
                let tables = self.auto_switch_tables.as_ref();
                // tự đổi: từ tiếng Anh gõ ở chế độ tiếng Việt ("server", "more") → trả lại phím đã gõ, sang tiếng Anh
                if edit.is_none() && auto && tables.is_some_and(|t| t.prefers_english(&word, &shown)) {
                    edit = Some(TextEdit::new(shown.chars().count(), word.iter().collect::<String>()));
                    switch_to = Some(Mode::English);
                } else if edit.is_none() {
                    if let Some(restored) = self.telex.finish_word() {
                        edit = Some(restored);
                        if auto && tables.is_some_and(|t| t.is_foreign(&word, &shown)) {
                            switch_to = Some(Mode::English);
                        }
                    }
                }
                self.remember((a == ' ' && !word.is_empty()).then_some(word.clone()), true);
                if let Some(edit) = edit {
                    self.telex.reset();
                    let undo = (a != '\r').then(|| (shown, word, Mode::Vietnamese));
                    return self.word_end_result(edit, switch_to, undo);
                }
            }
            self.telex.reset();
            return KeyResult::pass();
        };
        let shown = self.telex.output_len();
        let edit = self.telex.type_key(ch);
        if edit.backspaces == 0 && edit.insert.chars().eq([ch]) {
            return KeyResult::pass(); // để phím gốc đi qua
        }
        let whole_word = edit.backspaces == shown;
        KeyResult { handled: true, edit: Some(edit), whole_word, ..Default::default() }
    }

    /// Kết thúc từ có sửa đổi: thay cả từ, gửi lại phím kết thúc từ, đổi chế độ nếu tự đổi.
    /// `undo`: chữ trước khi sửa, các phím và chế độ lúc đó, để Backspace ngay sau trả lại (chỉ khi tự đổi).
    fn word_end_result(
        &mut self,
        edit: TextEdit,
        switch_to: Option<Mode>,
        undo: Option<(String, Vec<char>, Mode)>,
    ) -> KeyResult {
        if let Some(m) = switch_to {
            self.set_mode(m);
            if let Some((text, keys, mode)) = undo {
                self.undo = Some(Undo { remove: edit.insert.chars().count() + 1, text, keys, mode });
            }
        }
        KeyResult {
            handled: true,
            edit: Some(edit),
            whole_word: true,
            repost_key: true,
            switched_to: switch_to,
            panel_changed: false,
        }
    }

    /// Tiếng Anh: mọi phím đi qua, chỉ nhớ từ đang gõ để thay gõ tắt khi kết thúc bằng Space/Enter/Tab.
    fn handle_english(&mut self, key: Key) -> KeyResult {
        if self.english_macros.is_none() && !self.auto_switch_enabled {
            return KeyResult::pass();
        }
        if key == Key::Backspace {
            self.english_word.pop();
            return KeyResult::pass();
        }
        let typed = key.typed();
        if let Some(ch) = typed.filter(|c| c.is_ascii_alphabetic()) {
            self.english_word.push(ch);
            return KeyResult::pass();
        }
        // cùng quy tắc với tiếng Việt: từ đứng riêng, kết thúc bằng Space/Enter/Tab
        let ascii = typed.filter(|c| c.is_ascii());
        let is_space = matches!(ascii, Some(' ' | '\r' | '\t'));
        let word = std::mem::take(&mut self.english_word);
        let started = self.at_word_start;
        self.at_word_start = is_space;
        let word_str: String = word.iter().collect();
        let mut text =
            if is_space && started { self.english_macros.as_ref().and_then(|m| m.expansion(&word_str)) } else { None };
        let mut switch_to = None;
        // từ vừa được trả lại bằng Backspace thì giữ như đã gõ
        let undone = self.undone_keys.take().is_some_and(|k| k == word);
        // tự đổi: chữ Telex gõ ở chế độ tiếng Anh ("treen") → chữ tiếng Việt, sang tiếng Việt
        if text.is_none() && started && !undone && self.active_auto_switch(typed) {
            if let Some(v) =
                self.auto_switch_tables.as_ref().and_then(|t| t.vietnamese_for(&word, self.telex.modern_tone_style))
            {
                text = Some(v);
                switch_to = Some(Mode::Vietnamese);
            }
        }
        let backspaces = word.len();
        self.remember((ascii == Some(' ') && !word.is_empty()).then_some(word.clone()), false);
        let undo = (ascii != Some('\r')).then(|| (word_str, word, Mode::English));
        match text {
            Some(text) => self.word_end_result(TextEdit::new(backspaces, text), switch_to, undo),
            None => KeyResult::pass(),
        }
    }

    fn handle_chinese(&mut self, key: Key) -> KeyResult {
        let Some(py) = &mut self.pinyin else { return KeyResult::pass() };
        let ch = key.typed();

        if py.is_composing() {
            match key {
                Key::Backspace => {
                    py.backspace();
                    return self.panel_result();
                }
                Key::Escape => {
                    self.cancel();
                    return self.panel_result();
                }
                Key::Enter => {
                    let text = py.commit_raw();
                    return self.commit(text);
                }
                Key::Space => {
                    let i = self.page * self.page_size + self.highlight;
                    if i < py.candidates().len() {
                        return self.choose(i);
                    }
                    return self.commit_best(KeyResult::swallow());
                }
                Key::Left => return self.move_highlight(-1),
                Key::Right | Key::Tab => return self.move_highlight(1),
                Key::Up | Key::PageUp => return self.turn_page(-1),
                Key::Down | Key::PageDown => return self.turn_page(1),
                _ => {}
            }
            if let Some(c) = ch {
                if c.is_ascii_lowercase() || c == '\'' {
                    py.type_char(c);
                    self.page = 0;
                    self.highlight = 0;
                    return self.panel_result();
                }
                if let Some(d) = c.to_digit(10).filter(|d| (1..=9).contains(d)) {
                    return self.choose(self.page * self.page_size + d as usize - 1);
                }
                if c == '-' || c == '[' {
                    return self.turn_page(-1);
                }
                if c == '=' || c == ']' {
                    return self.turn_page(1);
                }
            }
            // phím khác (dấu câu, chữ hoa...): chọn ứng viên đầu cho hết rồi xử lý tiếp như bình thường
            let committed = self.commit_best(KeyResult::pass());
            let rest = self.handle_chinese_idle(ch);
            return merge(committed, rest);
        }
        self.handle_chinese_idle(ch)
    }

    fn handle_chinese_idle(&mut self, ch: Option<char>) -> KeyResult {
        let Some(ch) = ch else { return KeyResult::pass() };
        if ch.is_ascii_lowercase() {
            if let Some(py) = &mut self.pinyin {
                py.type_char(ch);
            }
            self.page = 0;
            self.highlight = 0;
            return self.panel_result();
        }
        if self.full_width_punctuation {
            if let Some(p) = full_width(ch) {
                return KeyResult { handled: true, edit: Some(TextEdit::new(0, p)), ..Default::default() };
            }
        }
        KeyResult::pass()
    }

    /// Chọn ứng viên số `index` trong `candidates()` (bấm số, Space, hoặc chạm vào ô).
    pub fn select_candidate(&mut self, index: usize) -> KeyResult {
        self.choose(index)
    }

    fn choose(&mut self, index: usize) -> KeyResult {
        let Some(py) = &mut self.pinyin else { return KeyResult::swallow() };
        if index >= py.candidates().len() {
            return KeyResult::swallow();
        }
        match py.select(index) {
            Some(text) => self.commit(text),
            None => {
                self.page = 0;
                self.highlight = 0;
                self.panel_result()
            }
        }
    }

    /// Chọn ứng viên đầu cho tới khi hết phần đang gõ; chữ chèn vào nằm trong `edit` của kết quả.
    fn commit_best(&mut self, base: KeyResult) -> KeyResult {
        let mut text = String::new();
        if let Some(py) = &mut self.pinyin {
            while py.is_composing() {
                if py.candidates().is_empty() {
                    text = py.commit_raw();
                    break;
                }
                if let Some(t) = py.select(0) {
                    text = t;
                    break;
                }
            }
        }
        self.page = 0;
        self.highlight = 0;
        KeyResult { edit: (!text.is_empty()).then(|| TextEdit::new(0, text)), panel_changed: true, ..base }
    }

    fn commit(&mut self, text: String) -> KeyResult {
        self.page = 0;
        self.highlight = 0;
        KeyResult {
            handled: true,
            edit: (!text.is_empty()).then(|| TextEdit::new(0, text)),
            panel_changed: true,
            ..Default::default()
        }
    }

    fn panel_result(&self) -> KeyResult {
        KeyResult { handled: true, panel_changed: true, ..Default::default() }
    }

    fn move_highlight(&mut self, delta: i32) -> KeyResult {
        let total = self.candidates().len();
        let count = self.page_size.min(total.saturating_sub(self.page * self.page_size));
        let h = self.highlight as i32 + delta;
        if h < 0 {
            if self.page > 0 {
                self.page -= 1;
                self.highlight = self.page_size - 1;
            }
        } else if h as usize >= count {
            return self.turn_page(1);
        } else {
            self.highlight = h as usize;
        }
        self.panel_result()
    }

    fn turn_page(&mut self, delta: i32) -> KeyResult {
        let total = self.candidates().len();
        let pages = 1.max(total.div_ceil(self.page_size)) as i32;
        let p = self.page as i32 + delta;
        if p >= 0 && p < pages {
            self.page = p as usize;
            self.highlight = 0;
        }
        self.panel_result()
    }
}

/// Phím kết thúc phần chữ Hán đang gõ rồi tự xử lý tiếp (vd dấu phẩy → chọn ứng viên đầu rồi chèn "，").
fn merge(first: KeyResult, then: KeyResult) -> KeyResult {
    let edit = match (first.edit, then.edit) {
        (Some(a), Some(b)) => Some(TextEdit::new(a.backspaces, a.insert + &b.insert)),
        (a, b) => a.or(b),
    };
    KeyResult {
        handled: then.handled,
        // phím gốc đi qua sau phần chữ vừa chọn: phải chặn rồi gửi lại cho đúng thứ tự
        repost_key: !then.handled && edit.is_some(),
        edit,
        whole_word: false,
        switched_to: None,
        panel_changed: first.panel_changed || then.panel_changed,
    }
    .normalized()
}

impl KeyResult {
    fn normalized(mut self) -> KeyResult {
        if self.repost_key {
            self.handled = true;
        }
        self
    }
}

fn full_width(c: char) -> Option<&'static str> {
    Some(match c {
        ',' => "，",
        '.' => "。",
        '?' => "？",
        '!' => "！",
        ';' => "；",
        ':' => "：",
        '(' => "（",
        ')' => "）",
        '[' => "【",
        ']' => "】",
        '<' => "《",
        '>' => "》",
        '\\' => "、",
        '~' => "～",
        '^' => "……",
        '$' => "￥",
        _ => return None,
    })
}
