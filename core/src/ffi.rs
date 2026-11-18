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
    pub reopened: u32,
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
            reopened: r.reopened as u32,
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

    pub fn current_keys(&self) -> String {
        self.lock().current_keys()
    }

    pub fn preedit(&self) -> String {
        self.lock().preedit()
    }

    pub fn is_composing_chinese(&self) -> bool {
        self.lock().is_composing_chinese()
    }

    pub fn knows_word(&self, letters: String) -> bool {
        self.lock().knows_word(&letters)
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

// MARK: - Gợi ý từ (bàn phím Việt · Anh)

/// Loại phím tham gia chọn phím khi chạm: chữ a…z, cách, xoá, Shift.
#[derive(uniffi::Enum, Clone, PartialEq, Eq, Debug)]
pub enum TouchKind {
    /// `letter`: chữ thường của phím, "a"…"z"
    Letter { letter: String },
    Space,
    Backspace,
    Shift,
}

/// Một phím của trang chữ: chỉ số của nó trong mảng phím của bàn phím (cái `touch_pick` trả về), loại, hàng (0 là
/// hàng chữ trên cùng; phím cách ở hàng ngay dưới hàng chữ cuối), và ô vẽ (không gồm khe giữa các phím), cùng hệ
/// toạ độ với chỗ chạm.
#[derive(uniffi::Record, Clone, PartialEq, Debug)]
pub struct TouchKeyRect {
    pub index: u32,
    pub kind: TouchKind,
    pub row: u32,
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

/// Một ô trên thanh gợi ý (xem suggest::Suggestion).
#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct SuggestCell {
    pub text: String,
    /// từ đúng như đã gõ, trong ngoặc kép: chạm vào thì giữ nguyên nó (gọi `keep_shown` rồi gõ dấu cách)
    pub quoted: bool,
    /// chữ mà dấu cách sẽ đưa vào thay cho từ đã gõ
    pub highlighted: bool,
    /// từ tiếp theo (chưa gõ chữ nào của nó): chèn mà không xoá gì
    pub next: bool,
}

/// Hoàn tác một lần tự sửa: xoá `delete` ký tự trước con trỏ rồi chèn `insert`.
#[derive(uniffi::Record, Clone, PartialEq, Eq, Debug)]
pub struct UndoCorrection {
    pub delete: u32,
    pub insert: String,
}

#[derive(uniffi::Record, Clone, PartialEq, Debug)]
pub struct TouchOdds {
    /// a…z rồi "từ kết thúc"
    pub odds: Vec<f64>,
    pub vietnamese: bool,
}

/// Gợi ý từ, tự sửa lỗi chạm lệch phím và vùng chạm theo câu, cho một bàn phím. Khoá riêng, không dính tới khoá của
/// `ViPiComposer` (chỉ hỏi nó `knows_word`): một lần `update` lâu không làm chậm `handle_key`. `warm` không giữ khoá
/// nào mà các hàm khác cần.
#[derive(uniffi::Object)]
pub struct ViPiSuggest {
    models: Arc<crate::suggest::Models>,
    inner: Mutex<crate::suggest::Suggester>,
}

impl ViPiSuggest {
    fn lock(&self) -> MutexGuard<'_, crate::suggest::Suggester> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
}

#[uniffi::export]
impl ViPiSuggest {
    /// `data_dir`: thư mục chứa SuggestEN.bin, SuggestNN.bin, SuggestVI.bin, SuggestVINN.bin, keep-words.txt và
    /// keep-words-chat.txt (thiếu file nào thì phần đó như không có). Không đọc file nào: gọi `warm` sau khi bàn phím
    /// đã hiện.
    #[uniffi::constructor]
    pub fn new(data_dir: String, composer: Arc<ViPiComposer>) -> Arc<Self> {
        let models = crate::suggest::Models::new(PathBuf::from(data_dir));
        let knows = Box::new(move |w: &str| composer.knows_word(w.to_string()));
        let inner = Mutex::new(crate::suggest::Suggester::new(Arc::clone(&models), knows));
        Arc::new(ViPiSuggest { models, inner })
    }

    /// Ở luồng nền, sau khi bàn phím hiện: đọc các file vào bộ nhớ và dựng các bảng, thứ tiếng của bàn phím trước.
    /// Chạy tới vài trăm ms lần đầu; nhanh khi các trang còn trong bộ nhớ.
    pub fn warm(&self, vietnamese_first: bool) {
        self.models.warm(vietnamese_first)
    }

    /// Như `warm` cho một thứ tiếng, để làm mới thanh gợi ý ngay khi thứ tiếng đầu xong. Trả về nó đã sẵn sàng chưa.
    pub fn warm_one(&self, vietnamese: bool) -> bool {
        self.models.warm_one(vietnamese)
    }

    pub fn ready_en(&self) -> bool {
        self.models.ready(false)
    }

    pub fn ready_vi(&self) -> bool {
        self.models.ready(true)
    }

    /// Bàn phím ẩn đi: lần hiện sau phải `warm` lại (một lượt `warm` đang chạy không còn tính).
    pub fn cool_down(&self) {
        self.models.cool_down()
    }

    /// `suggestions`: thanh gợi ý (cách gõ tiếp, từ tiếp theo); `auto_correct`: tự sửa lỗi chạm lệch và vùng chạm.
    pub fn set_options(&self, suggestions: bool, auto_correct: bool) {
        let mut s = self.lock();
        s.suggestions_on = suggestions;
        s.auto_correct_on = auto_correct;
    }

    /// Mỗi lần bố cục phím đổi: các phím chữ, cách, xoá, Shift của trang chữ; rỗng ở trang khác.
    pub fn set_keys(&self, keys: Vec<TouchKeyRect>) {
        use crate::suggest::{TapKind, TouchKey};
        let keys = keys
            .into_iter()
            .filter_map(|k| {
                let kind = match k.kind {
                    TouchKind::Letter { letter } => match letter.as_bytes() {
                        [c @ b'a'..=b'z'] => TapKind::Letter(c - b'a'),
                        [c @ b'A'..=b'Z'] => TapKind::Letter(c - b'A'),
                        _ => return None,
                    },
                    TouchKind::Space => TapKind::Space,
                    TouchKind::Backspace => TapKind::Backspace,
                    TouchKind::Shift => TapKind::Shift,
                };
                Some(TouchKey {
                    index: k.index as usize,
                    kind,
                    row: k.row as i32,
                    x: k.x as f64,
                    y: k.y as f64,
                    w: k.width as f64,
                    h: k.height as f64,
                })
            })
            .collect();
        self.lock().set_keys(keys)
    }

    /// Phím mà một lần chạm xuống gõ (`default_index`: phím ở chỗ chạm). Chỉ gọi trên trang chữ của điện thoại, khi
    /// không gõ tiếng Trung và ô nhập cho gợi ý; ngoài ra dùng thẳng phím ở chỗ chạm. Vài µs, không tính mô hình.
    pub fn touch_pick(&self, x: f32, y: f32, default_index: u32) -> u32 {
        self.lock().touch_pick(x as f64, y as f64, default_index as usize) as u32
    }

    /// Phím chữ cái ASCII vừa gửi đi (sau `handle_key`), với chỗ chạm của nó; NaN khi không có (bàn phím cứng).
    pub fn letter(&self, letter: String, x: f32, y: f32) {
        if let Some(c) = letter.chars().next() {
            self.lock().letter(c, x, y)
        }
    }

    /// Backspace vừa gửi đi.
    pub fn backspace(&self) {
        self.lock().backspace()
    }

    /// Phím khác vừa gửi đi, con trỏ dời, đổi chế độ hay ô nhập: bỏ từ đang theo dõi.
    pub fn end_word(&self) {
        self.lock().end_word()
    }

    /// Mọi phím khác Backspace, trước khi xử lý: hết cơ hội hoàn tác lần tự sửa trước.
    pub fn forget_correction(&self) {
        self.lock().forget_correction()
    }

    /// Bàn phím ẩn đi.
    pub fn reset(&self) {
        self.lock().reset()
    }

    /// Mỗi khi hẹn tính lại thanh gợi ý mà không qua `letter`/`backspace`/`end_word` (con trỏ dời, ô đổi): lần chạm
    /// tới `update` sau không dùng xác suất cũ.
    pub fn invalidate(&self) {
        self.lock().invalidate()
    }

    /// Sau mỗi phím, khi chữ của nó đã vào ô (đăng lên luồng chính, gộp các phím gõ nhanh): các ô của thanh gợi ý.
    /// `context`: chữ trước con trỏ; `english`: lõi ở trạng thái Anh; `telex_keys`: trạng thái Việt, các phím Telex
    /// của từ đang gõ (`ViPiComposer::current_keys`); `capitalize`: Shift đang bật cho chữ đầu câu. Vài µs khi gõ giữa
    /// từ; tới vài ms khi mạng phải đọc lại câu.
    pub fn update(&self, context: String, english: bool, telex_keys: String, capitalize: bool) -> Vec<SuggestCell> {
        self.lock()
            .update(&context, english, &telex_keys, capitalize)
            .into_iter()
            .map(|c| SuggestCell { text: c.text, quoted: c.quoted, highlighted: c.highlighted, next: c.next })
            .collect()
    }

    /// Kết quả đang giữ có được tính cho đúng chữ trước con trỏ này không (hỏi trước khi thay chữ theo một ô hay một
    /// lần tự sửa; không thì gọi lại `update`).
    pub fn is_current(&self, context: String) -> bool {
        self.lock().is_current(&context)
    }

    /// Từ đang gõ như lúc `update` gần nhất thấy (chọn một ô không phải từ tiếp theo: xoá từng ấy ký tự).
    pub fn shown_word(&self) -> String {
        self.lock().shown_word().to_string()
    }

    /// Trạng thái Anh, phím kết thúc từ (cách, . , ? ! ; :), trước `handle_key`: chữ thay cho `shown_word`, nếu có.
    pub fn correction(&self) -> Option<String> {
        self.lock().correction().map(str::to_string)
    }

    /// Đã thay `typed` bằng `inserted` (từ sửa cộng chữ của phím kết thúc).
    pub fn did_correct(&self, typed: String, inserted: String) {
        self.lock().did_correct(&typed, &inserted)
    }

    /// Backspace, trước `handle_key`: hoàn tác lần tự sửa ngay trước đó nếu chữ đã sửa còn trước con trỏ (rồi gọi
    /// `cancel` của lõi, không đưa Backspace cho lõi).
    pub fn undo_correction(&self, context: String) -> Option<UndoCorrection> {
        self.lock().undo_correction(&context).map(|(d, insert)| UndoCorrection { delete: d as u32, insert })
    }

    /// Người dùng chạm vào ô trong ngoặc kép: giữ nguyên từ đó (rồi gõ dấu cách như thường).
    pub fn keep_shown(&self) {
        self.lock().keep_shown()
    }

    /// Xác suất phím kế tiếp của lần `update` gần nhất (để vẽ hay gỡ lỗi; `touch_pick` đã dùng chúng).
    pub fn touch_odds(&self) -> Option<TouchOdds> {
        self.lock().touch_odds().map(|(o, v)| TouchOdds { odds: o.to_vec(), vietnamese: v })
    }

    /// Từ tiếng Anh đang gõ đã trọn và không từ nào gõ tiếp bằng `letter` (luật khe trên phím cách; `touch_pick`
    /// đã dùng nó).
    pub fn word_ends(&self, letter: String) -> bool {
        self.lock().word_ends(&letter)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ViPiSuggest qua giao diện FFI, với lõi thật (knows_word) và bố cục 402 pt. Cần 4 file mô hình
    /// (VIPI_SUGGEST_MODELS hoặc build/suggest); không có thì bỏ qua.
    #[test]
    fn suggest_object() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..");
        let models =
            std::env::var_os("VIPI_SUGGEST_MODELS").map(PathBuf::from).unwrap_or_else(|| root.join("build/suggest"));
        if !models.join("SuggestNN.bin").is_file() {
            println!("no model files in {}: skipped", models.display());
            return;
        }
        // một thư mục có cả mô hình và danh sách giữ nguyên, như thư mục dữ liệu của app
        let dir = std::env::temp_dir().join(format!("vipi-suggest-ffi-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for f in ["SuggestEN.bin", "SuggestNN.bin", "SuggestVI.bin", "SuggestVINN.bin"] {
            std::fs::copy(models.join(f), dir.join(f)).unwrap();
        }
        for f in ["keep-words.txt", "keep-words-chat.txt"] {
            std::fs::copy(root.join("Resources").join(f), dir.join(f)).unwrap();
        }
        let composer = ViPiComposer::new(root.join("Resources").to_string_lossy().into_owned()).unwrap();
        let s = ViPiSuggest::new(dir.to_string_lossy().into_owned(), composer);
        assert!(!s.ready_en() && s.update("I want to th".into(), true, String::new(), false).len() == 1);
        assert!(s.warm_one(false));
        assert!(s.ready_en() && !s.ready_vi());
        s.warm(true);
        assert!(s.ready_vi());
        let mut keys = vec![];
        for (r, (letters, off)) in [("qwertyuiop", 0.0f32), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)].iter().enumerate() {
            for (i, c) in letters.chars().enumerate() {
                let cx = 3.7 + 39.46 * (off + i as f32 + 0.5);
                keys.push(TouchKeyRect {
                    index: keys.len() as u32,
                    kind: TouchKind::Letter { letter: c.to_string() },
                    row: r as u32,
                    x: cx - 16.73,
                    y: 593.5 + 54.0 * r as f32,
                    width: 33.46,
                    height: 43.0,
                });
            }
        }
        keys.push(TouchKeyRect {
            index: 40,
            kind: TouchKind::Space,
            row: 3,
            x: 102.4,
            y: 755.5,
            width: 197.3,
            height: 43.0,
        });
        s.set_keys(keys);
        let cells = s.update("I want to th".into(), true, String::new(), false);
        let texts: Vec<&str> = cells.iter().map(|c| c.text.as_str()).collect();
        assert_eq!(texts, ["th", "think", "throw"]);
        assert!(cells[0].quoted && s.touch_odds().is_some_and(|o| o.odds.len() == 27 && !o.vietnamese));
        assert_eq!(s.touch_pick(3.7 + 39.46 * 7.0 - 2.0, 615.0, 6), 7, "2 pt trong u: i");
        // knows_word của lõi: "thanhf" là phím Telex của "thành", mô hình tiếng Anh không có từ nào như thế
        s.update("I want to thanhf".into(), true, String::new(), false);
        assert!(s.word_ends("n".into()));
        s.update("I want to thanhq".into(), true, String::new(), false);
        assert!(!s.word_ends("n".into()));
        // tự sửa và hoàn tác
        s.end_word();
        for (c, x, y) in [('r', 158.0, 615.0), ('h', 3.7 + 39.46 * 6.0, 669.0), ('o', 323.0, 615.0)] {
            s.letter(c.to_string(), x, y);
        }
        for (c, x) in [('n', 3.7 + 39.46 * 7.0), ('k', 3.7 + 39.46 * 8.0)] {
            s.letter(c.to_string(), x, if c == 'n' { 723.0 } else { 669.0 });
        }
        s.update("I want to rhonk".into(), true, String::new(), false);
        assert_eq!(s.correction().as_deref(), Some("think"));
        s.did_correct("rhonk".into(), "think ".into());
        let undo = s.undo_correction("I want to think ".into());
        assert_eq!(undo, Some(UndoCorrection { delete: 6, insert: "rhonk".into() }));
        s.cool_down();
        assert!(!s.ready_en() && !s.ready_vi());
        std::fs::remove_dir_all(&dir).ok();
    }
}
