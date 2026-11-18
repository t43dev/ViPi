//! Gợi ý từ, tự sửa lỗi chạm lệch phím và vùng chạm theo câu cho bàn phím Việt · Anh, theo Vikey
//! (github.com/tonyminibot/Vikey, GPL-3.0: D26 phần thanh gợi ý, D63 đến D66). Chuyển từ
//! ios/ViPiKeyboard/Suggest/Suggester.swift với đúng các điều kiện và ngưỡng của nó; bàn phím báo từng phím và hỏi lại
//! kết quả, như KeyboardViewController.swift.
//!
//! Khác Vikey: ViPi không có bộ máy C++ của Vikey, nên
//! - "từ đã biết" hỏi lõi (`Composer::knows_word`), danh sách giữ nguyên (`KeepWords`) và từ vựng của hai mô hình;
//! - hoàn thành từ và tự sửa chỉ có ở trạng thái Anh (chữ trong ô là đúng các phím đã gõ); ở trạng thái Việt thanh
//!   vẫn là hai lựa chọn "phím đã gõ" / "chữ có dấu" của nền tảng, cộng với từ tiếp theo và vùng chạm theo câu.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use super::keep::KeepWords;
use super::lm::{KeyRect, LmData, SuggestLm};
use super::tap::{self, TapKind, TouchKey};
use super::text;

/// Tên các file mô hình (tiếng Anh, tiếng Việt: số đếm, mạng).
pub const EN_FILES: [&str; 2] = ["SuggestEN.bin", "SuggestNN.bin"];
pub const VI_FILES: [&str; 2] = ["SuggestVI.bin", "SuggestVINN.bin"];
/// Phần của mạng trong xác suất một từ, cả hai thứ tiếng (Vikey: 0,25–0,75 đều trong độ nhiễu).
const NETWORK_SHARE: f64 = 0.5;

struct Lang {
    files: [&'static str; 2],
    data: OnceLock<Option<Arc<LmData>>>,
    ready: AtomicBool,
}

impl Lang {
    fn new(files: [&'static str; 2]) -> Lang {
        Lang { files, data: OnceLock::new(), ready: AtomicBool::new(false) }
    }
}

/// Các mô hình của hai thứ tiếng và danh sách giữ nguyên, trong một thư mục. Dùng chung giữa các luồng: `warm` chạy
/// ở luồng nền và không khoá gì mà `Suggester` cần, nên một lượt làm nóng đang chạy không bao giờ làm chậm phím.
///
/// Mở ra không đọc gì. `warm` mở file, đọc từng trang vào bộ nhớ và dựng các bảng (tổng cộng dồn, chỉ mục Telex),
/// rồi mới đánh dấu thứ tiếng đó sẵn sàng; trước đó mọi lần hỏi coi như không có mô hình (Vikey D64: đọc ~70 MB lúc
/// bàn phím mở làm nó lên chậm, iOS có lúc bỏ cuộc).
pub struct Models {
    dir: PathBuf,
    keep_dir: PathBuf,
    en: Lang,
    vi: Lang,
    generation: AtomicU64,
    warming: Mutex<()>,
    keep: OnceLock<KeepWords>,
}

impl Models {
    /// Mô hình và danh sách giữ nguyên trong cùng thư mục `dir`.
    pub fn new(dir: impl Into<PathBuf>) -> Arc<Models> {
        let dir = dir.into();
        Self::open(dir.clone(), dir)
    }

    /// Mô hình trong `dir`, danh sách giữ nguyên trong `keep_dir`.
    pub fn open(dir: impl Into<PathBuf>, keep_dir: impl Into<PathBuf>) -> Arc<Models> {
        Arc::new(Models {
            dir: dir.into(),
            keep_dir: keep_dir.into(),
            en: Lang::new(EN_FILES),
            vi: Lang::new(VI_FILES),
            generation: AtomicU64::new(0),
            warming: Mutex::new(()),
            keep: OnceLock::new(),
        })
    }

    fn lang(&self, vietnamese: bool) -> &Lang {
        if vietnamese {
            &self.vi
        } else {
            &self.en
        }
    }

    /// Làm nóng cả hai thứ tiếng (thứ tiếng của bàn phím trước). Chạy lâu (đọc tới 65 MB lần đầu): luồng nền.
    /// `cool_down` trong lúc chạy thì cả lượt không tính.
    pub fn warm(&self, vietnamese_first: bool) {
        let pass = self.generation.load(Ordering::SeqCst);
        self.warm_lang(vietnamese_first, pass);
        self.warm_lang(!vietnamese_first, pass);
    }

    /// Làm nóng một thứ tiếng; trả về nó đã sẵn sàng chưa (không, khi thiếu file hay `cool_down` đã được gọi trong
    /// lúc chạy). Hai lượt cùng lúc thì lượt sau đợi lượt trước.
    pub fn warm_one(&self, vietnamese: bool) -> bool {
        self.warm_lang(vietnamese, self.generation.load(Ordering::SeqCst))
    }

    /// `pass`: lượt bàn phím hiện lúc bắt đầu làm nóng (số `cool_down` đã gọi).
    fn warm_lang(&self, vietnamese: bool, pass: u64) -> bool {
        let _one_at_a_time = self.warming.lock().unwrap_or_else(|e| e.into_inner());
        let l = self.lang(vietnamese);
        if self.generation.load(Ordering::SeqCst) != pass {
            return false; // bàn phím đã đi mất
        }
        if l.ready.load(Ordering::SeqCst) {
            return self.ready(vietnamese);
        }
        let data = l.data.get_or_init(|| {
            let nn = self.dir.join(l.files[1]);
            LmData::open(&self.dir.join(l.files[0]), Some(&nn), NETWORK_SHARE).map(Arc::new)
        });
        if let Some(d) = data {
            d.touch_pages();
            d.build_warm(vietnamese);
        }
        // một lượt bắt đầu trước lần bàn phím đi mất gần nhất không tính (kiểm lại sau khi đánh dấu: cool_down có thể
        // chen vào giữa)
        if self.generation.load(Ordering::SeqCst) == pass {
            l.ready.store(true, Ordering::SeqCst);
            if self.generation.load(Ordering::SeqCst) != pass {
                l.ready.store(false, Ordering::SeqCst);
            }
        }
        self.ready(vietnamese)
    }

    /// Thứ tiếng này đã làm nóng xong và có mô hình.
    pub fn ready(&self, vietnamese: bool) -> bool {
        self.data(vietnamese).is_some()
    }

    /// Bàn phím đi mất: hệ điều hành có thể bỏ các trang trước khi nó quay lại, nên lần mở sau làm nóng lại (một lượt
    /// đang chạy không còn tính).
    pub fn cool_down(&self) {
        self.generation.fetch_add(1, Ordering::SeqCst);
        self.en.ready.store(false, Ordering::SeqCst);
        self.vi.ready.store(false, Ordering::SeqCst);
    }

    /// Mô hình của một thứ tiếng nếu đã sẵn sàng. Không bao giờ đợi.
    pub(crate) fn data(&self, vietnamese: bool) -> Option<&Arc<LmData>> {
        let l = self.lang(vietnamese);
        if !l.ready.load(Ordering::SeqCst) {
            return None;
        }
        l.data.get()?.as_ref()
    }

    /// Danh sách giữ nguyên (mở lần đầu cần tới; hai file nhỏ, ánh xạ vào bộ nhớ).
    pub fn keep_words(&self) -> &KeepWords {
        self.keep.get_or_init(|| KeepWords::open(&self.keep_dir))
    }
}

/// Một ô trên thanh gợi ý khi gõ Việt · Anh.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Suggestion {
    pub text: String,
    /// từ đúng như đã gõ, trong ngoặc kép: chạm vào thì giữ nguyên nó
    pub quoted: bool,
    /// chữ mà dấu cách sẽ đưa vào thay cho từ đã gõ
    pub highlighted: bool,
    /// từ tiếp theo (chưa gõ chữ nào của nó)
    pub next: bool,
}

#[derive(Default)]
struct State {
    context: String,    // chữ trước con trỏ
    shown: String,      // từ đang gõ như hiện trong ô (các chữ cái cuối của context)
    english: bool,      // lõi đang ở trạng thái Anh
    telex_keys: String, // trạng thái Việt: các phím Telex của từ đang gõ
}

const SLIP_MARGIN: f64 = 3.0;
/// Từ thay vào phải đủ hợp với câu: log P(từ | các từ trước) trên mức này. Vikey không có ngưỡng này; với nó, trong
/// mô phỏng chạm lệch (8 pt) chữ chat gõ đúng mà bị đổi giảm từ 4,6% xuống 0,16%, còn từ tiếng Anh gõ lệch được sửa
/// đúng 61 trên 70 (không ngưỡng: 66).
const SLIP_LIKELIHOOD_FLOOR: f64 = -9.0;

/// Dạng chữ không phải lỗi gõ: không có nguyên âm (viết tắt), ba chữ giống nhau liền nhau hoặc nguyên âm cuối gõ đôi
/// (kéo dài chữ: "oiii", "nhaa").
pub fn looks_typed(low: &str) -> bool {
    let c: Vec<&str> = text::clusters(low);
    let vowel = |s: &str| s.len() == 1 && "aeiouy".contains(s);
    if !c.iter().any(|s| vowel(s)) {
        return false;
    }
    if c.len() >= 3 && (2..c.len()).any(|i| c[i] == c[i - 1] && c[i] == c[i - 2]) {
        return false;
    }
    let n = c.len();
    if n >= 2 && c[n - 1] == c[n - 2] && vowel(c[n - 1]) {
        return false;
    }
    true
}

/// Từ đang gõ, kết quả sau mỗi phím, và vùng chạm. Không dùng chung giữa các luồng (bọc trong một khoá nếu cần).
pub struct Suggester {
    pub suggestions_on: bool,
    pub auto_correct_on: bool,
    /// Lõi có coi chuỗi chữ cái này là từ đã biết không (tiếng Anh, phím Telex của từ tiếng Việt, chữ chat).
    knows: Box<dyn Fn(&str) -> bool + Send + Sync>,
    models: Arc<Models>,
    en: Option<SuggestLm>,
    vi: Option<SuggestLm>,
    keys: Vec<TouchKey>,
    letter_rects: Vec<KeyRect>,
    // từ đang gõ: các chữ cái (như đã gõ) và chỗ chạm của từng chữ
    typed: String,
    xs: Vec<f32>,
    ys: Vec<f32>,
    /// từ vừa được trả lại bằng Backspace hoặc được chọn giữ nguyên: không sửa nó nữa
    keep_word: Option<String>,
    /// lần tự sửa gần nhất (đã gõ, đã chèn): Backspace ngay sau đó trả lại từ đã gõ
    last_correction: Option<(String, String)>,
    state: State,
    fix: Option<(String, String)>,
    odds: Option<(Vec<f64>, bool)>,
    /// kết quả của lần `update` cuối còn đúng cho lần chạm: chưa có phím, Backspace hay `invalidate` nào sau nó
    fresh: bool,
}

impl Suggester {
    pub fn new(models: Arc<Models>, knows: Box<dyn Fn(&str) -> bool + Send + Sync>) -> Suggester {
        Suggester {
            suggestions_on: true,
            auto_correct_on: true,
            knows,
            models,
            en: None,
            vi: None,
            keys: vec![],
            letter_rects: vec![],
            typed: String::new(),
            xs: vec![],
            ys: vec![],
            keep_word: None,
            last_correction: None,
            state: State::default(),
            fix: None,
            odds: None,
            fresh: false,
        }
    }

    pub fn models(&self) -> &Arc<Models> {
        &self.models
    }

    /// Mô hình của một thứ tiếng, nếu đã sẵn sàng (cùng bộ nhớ đệm mà các gợi ý dùng).
    pub fn lm(&mut self, vietnamese: bool) -> Option<&mut SuggestLm> {
        let data = Arc::clone(self.models.data(vietnamese)?);
        let slot = if vietnamese { &mut self.vi } else { &mut self.en };
        if slot.as_ref().is_none_or(|l| !Arc::ptr_eq(l.data(), &data)) {
            *slot = Some(SuggestLm::new(data));
        }
        slot.as_mut()
    }

    /// Các phím tham gia chọn phím (chữ a…z, cách, xoá, Shift) của trang chữ đang hiện, với ô vẽ; rỗng ở trang khác.
    /// Các phím chữ cũng là bàn phím mà tự sửa lỗi chạm đọc lại các lần chạm.
    pub fn set_keys(&mut self, keys: Vec<TouchKey>) {
        self.letter_rects = keys
            .iter()
            .filter_map(|k| match k.kind {
                TapKind::Letter(l) if l < 26 => {
                    Some(KeyRect { x: k.x as f32, y: k.y as f32, w: k.w as f32, h: k.h as f32, letter: b'a' + l })
                }
                _ => None,
            })
            .collect();
        self.keys = keys;
    }

    // MARK: từ đang gõ

    /// Một chữ cái ASCII vừa vào từ đang gõ, với chỗ chạm (NaN khi không có: bàn phím cứng).
    pub fn letter(&mut self, ch: char, x: f32, y: f32) {
        self.typed.push(ch);
        self.xs.push(x);
        self.ys.push(y);
        self.fresh = false;
    }

    pub fn backspace(&mut self) {
        self.fresh = false;
        if self.typed.pop().is_some() {
            self.xs.pop();
            self.ys.pop();
        }
    }

    /// Từ kết thúc, con trỏ dời đi, đổi ô nhập: bỏ từ đang theo dõi.
    pub fn end_word(&mut self) {
        self.typed.clear();
        self.xs.clear();
        self.ys.clear();
        self.fix = None;
        self.odds = None;
        self.fresh = false;
    }

    /// Phím khác Backspace vừa được gõ: hết cơ hội hoàn tác lần sửa trước.
    pub fn forget_correction(&mut self) {
        self.last_correction = None;
    }

    pub fn reset(&mut self) {
        self.end_word();
        self.keep_word = None;
        self.last_correction = None;
        self.state = State::default();
    }

    /// Chữ trước con trỏ có thể đã đổi (bàn phím vừa hẹn tính lại): các xác suất phím của lần tính trước không dùng
    /// cho lần chạm nữa, tới `update` sau.
    pub fn invalidate(&mut self) {
        self.fresh = false;
    }

    pub fn last_correction(&self) -> Option<(&str, &str)> {
        self.last_correction.as_ref().map(|(a, b)| (a.as_str(), b.as_str()))
    }

    // MARK: kết quả sau mỗi phím

    fn before(&self) -> &str {
        text::drop_last(&self.state.context, text::count(&self.state.shown))
    }

    /// Từ đang gõ như hiện trong ô (lúc tính gần nhất).
    pub fn shown_word(&self) -> &str {
        &self.state.shown
    }

    /// Kết quả đang giữ có được tính cho đúng chữ trước con trỏ này không. Phải hỏi trước khi xoá hay thay chữ trong
    /// ô: con trỏ có thể đã dời mà bộ gợi ý chưa kịp tính lại.
    pub fn is_current(&self, context: &str) -> bool {
        self.state.context == context
    }

    /// Tính lại sau một phím (chữ của phím đã vào ô): xác suất phím kế tiếp cho lần chạm sau, chữ dấu cách sẽ đưa vào,
    /// và các ô của thanh gợi ý. `capitalize`: Shift đang bật cho chữ đầu câu. Thứ tiếng chưa sẵn sàng thì như không
    /// có mô hình; không bao giờ đợi `warm`.
    pub fn update(&mut self, context: &str, english: bool, telex_keys: &str, capitalize: bool) -> Vec<Suggestion> {
        let cl = text::clusters(context);
        let n = cl.iter().rev().take_while(|c| text::is_letter(c)).count();
        let shown: String = cl[cl.len() - n..].concat();
        self.state =
            State { context: context.to_string(), shown: shown.clone(), english, telex_keys: telex_keys.to_string() };
        self.odds = self.next_key_odds();
        self.fix = None;
        self.fresh = true;
        if shown.is_empty() {
            // chưa gõ chữ nào của từ mới: từ tiếp theo
            if !self.suggestions_on || !(context.is_empty() || text::last(context) == Some(" ")) {
                return vec![];
            }
            return self
                .next_words(capitalize)
                .into_iter()
                .map(|text| Suggestion { text, next: true, ..Default::default() })
                .collect();
        }
        if !english || !text::clusters(&shown).iter().all(|c| text::is_ascii(c)) {
            return vec![];
        }
        let has_lm = self.models.ready(false);
        if self.auto_correct_on && has_lm {
            if let Some(word) = self.slip_fix() {
                self.fix = Some((self.cased(&word), shown.clone()));
            }
        }
        if !self.suggestions_on && self.fix.is_none() {
            return vec![];
        }
        let mut cells = vec![Suggestion { text: shown.clone(), quoted: true, ..Default::default() }];
        let mut seen: HashSet<String> = HashSet::from([text::lower(&shown)]);
        if let Some((word, _)) = &self.fix {
            seen.insert(text::lower(word));
            cells.push(Suggestion { text: word.clone(), highlighted: true, ..Default::default() });
        }
        if self.suggestions_on && has_lm {
            let low = text::lower(&shown);
            let before = self.before().to_string();
            if let Some(lm) = self.lm(false) {
                let mut finishes = lm.completions(&low, &before, 3);
                // từ đã trọn mà ít cách gõ tiếp: dạng sở hữu, như bàn phím hệ thống
                if finishes.len() < 2 && lm.id(&low).is_some() && !low.ends_with("'s") {
                    finishes.push(format!("{low}'s"));
                }
                for f in finishes {
                    if cells.len() >= 3 {
                        break;
                    }
                    let t = self.cased(&f);
                    if seen.insert(text::lower(&t)) {
                        cells.push(Suggestion { text: t, ..Default::default() });
                    }
                }
            }
        }
        if cells.len() == 1 {
            cells[0].quoted = false;
        }
        cells
    }

    /// Chữ mà phím kết thúc từ sẽ đưa vào thay cho từ đang hiện, nếu có (tính cho đúng từ đó).
    pub fn correction(&self) -> Option<&str> {
        let (word, shown) = self.fix.as_ref()?;
        (*shown == self.state.shown).then_some(word.as_str())
    }

    pub fn did_correct(&mut self, typed: &str, inserted: &str) {
        self.last_correction = Some((typed.to_string(), inserted.to_string()));
        self.end_word();
    }

    /// Backspace ngay sau một lần tự sửa: (số ký tự phải xoá, chữ gõ lại) nếu chữ đã sửa còn ngay trước con trỏ.
    pub fn undo_correction(&mut self, context: &str) -> Option<(usize, String)> {
        let (typed, inserted) = self.last_correction.take()?;
        if !context.ends_with(&inserted) {
            return None;
        }
        self.keep_word = Some(text::lower(&typed));
        self.end_word();
        Some((text::count(&inserted), typed))
    }

    /// Người dùng chạm vào từ trong ngoặc kép: giữ nguyên nó.
    pub fn keep_shown(&mut self) {
        self.keep_word = Some(text::lower(&self.state.shown));
        self.fix = None;
    }

    // MARK: vùng chạm (D65, D66)

    /// 27 xác suất cho lần chạm kế tiếp (a…z rồi "từ kết thúc") và thứ tiếng của chúng, đã tính sau phím trước; None
    /// thì bàn phím tự chọn phím theo chỗ chạm. Không tính gì lúc chạm.
    pub fn touch_odds(&self) -> Option<(&[f64], bool)> {
        if !self.auto_correct_on {
            return None;
        }
        self.odds.as_ref().map(|(o, v)| (o.as_slice(), *v))
    }

    /// Chạm vào khe giữa hàng chữ dưới cùng và phím cách khi chưa có xác suất phím kế tiếp: là dấu cách khi từ tiếng
    /// Anh đang gõ đã là một từ và không từ nào gõ tiếp bằng `letter` ("thank" rồi chạm dưới n).
    pub fn word_ends(&self, letter: &str) -> bool {
        if !self.auto_correct_on || !self.state.english {
            return false;
        }
        let l = text::lower(letter);
        if !l.chars().next().is_some_and(|c| c.is_ascii_lowercase()) {
            return false;
        }
        let w = text::lower(&self.state.shown);
        let cl = text::clusters(&w);
        if cl.len() < 2 || !cl.iter().all(|c| text::is_ascii(c) && text::is_letter(c)) {
            return false;
        }
        let Some(lm) = self.models.data(false) else { return false };
        if !((self.knows)(&w) || lm.id(&w).is_some()) {
            return false;
        }
        !lm.starts_word(&format!("{w}{l}"))
    }

    /// Phím mà một lần chạm xuống gõ, trên trang chữ của điện thoại khi một từ đang gõ dở, như KeyboardView.pickKey:
    /// chạm gần ranh giới hai phím thì theo chữ nào hay đi tiếp hơn (TapModel), và chạm vào khe phía trên phím cách
    /// sau một từ đã trọn là dấu cách. `default_index`: phím ở chỗ chạm (theo ô của bàn phím); trả về nó khi không có
    /// xác suất, khi kết quả cũ (`fresh`), hoặc khi nó không phải phím tham gia. Chỉ so điểm, không tính mô hình.
    pub fn touch_pick(&self, x: f64, y: f64, default_index: usize) -> usize {
        let Some(def) = self.keys.iter().find(|k| k.index == default_index) else { return default_index };
        if !self.fresh {
            return default_index;
        }
        if let Some((odds, vietnamese)) = self.touch_odds() {
            let m = if vietnamese { tap::VIETNAMESE } else { tap::ENGLISH };
            if let Some(j) = tap::pick(x, y, &self.keys, odds, &m) {
                return j;
            }
        }
        if let TapKind::Letter(l) = def.kind {
            if let Some(sp) = self.keys.iter().find(|k| k.kind == TapKind::Space) {
                if def.row + 1 == sp.row
                    && y > def.max_y()
                    && x >= sp.x
                    && x <= sp.max_x()
                    && self.word_ends(&((b'a' + l.min(25)) as char).to_string())
                {
                    return sp.index;
                }
            }
        }
        default_index
    }

    fn next_key_odds(&mut self) -> Option<(Vec<f64>, bool)> {
        if !self.auto_correct_on {
            return None;
        }
        let before = self.before().to_string();
        if self.state.english {
            let w = &self.state.shown;
            if w.is_empty() || !text::clusters(w).iter().all(|c| text::is_ascii(c)) {
                return None;
            }
            let w = text::lower(w);
            let o = self.lm(false)?.next_letters(&w, &before)?;
            return (o.len() == 27).then_some((o, false));
        }
        if self.state.telex_keys.is_empty() {
            return None;
        }
        let keys = self.state.telex_keys.clone();
        let o = self.lm(true)?.next_keys(&keys, &before, 0.03)?;
        (o.len() == 27).then_some((o, true))
    }

    // MARK: tự sửa lỗi chạm lệch phím (D63, theo các giới hạn của D26)

    /// Từ mà các lần chạm nhiều khả năng định gõ, khi rõ ràng không phải chính các chữ đã gõ. Không bao giờ sửa: từ
    /// đã biết (cả hai thứ tiếng), chữ gõ ra âm tiết tiếng Việt, từ trong danh sách giữ nguyên, từ dưới 3 chữ, từ có từ
    /// 2 chữ hoa, từ vừa được trả lại, và các chữ đang trên đường tới một từ hay gặp hơn ("peop" → people).
    fn slip_fix(&mut self) -> Option<String> {
        let shown = self.state.shown.clone();
        let low = text::lower(&shown);
        let before = self.before().to_string();
        // chỉ từ đứng riêng: sau dấu cách, đầu ô hoặc dấu mở ngoặc. Chữ dính sau số, dấu chấm, gạch dưới
        // ("report.docx", "abc1xyz", "user_nmae") là tên file, mã, tên biến
        if let Some(c) = text::last(&before) {
            if !(text::is_whitespace(c) || ["\"", "'", "(", "“", "‘", "["].contains(&c)) {
                return None;
            }
        }
        if text::count(&low) < 3
            || text::lower(&self.typed) != low
            || self.xs.iter().any(|x| x.is_nan())
            || self.letter_rects.is_empty()
            || text::clusters(&shown).iter().filter(|c| text::is_uppercase(c)).count() >= 2
            || self.keep_word.as_deref() == Some(low.as_str())
            || !looks_typed(&low)
        {
            return None;
        }
        if self.lm(false)?.id(&low).is_some() || (self.knows)(&low) || self.models.keep_words().contains(&low) {
            return None;
        }
        let taps: Vec<(f32, f32)> = self.xs.iter().copied().zip(self.ys.iter().copied()).collect();
        let rects = self.letter_rects.clone();
        let lm = self.lm(false)?;
        let reads = lm.read_taps(&taps, &rects, &before);
        let best = reads.first()?;
        if text::lower(&best.word) == low {
            return None;
        }
        // các chữ đã gõ không phải một từ: điểm của chính chúng là độ gần ~0 cộng một xác suất rất nhỏ
        let typed_score = reads.iter().find(|r| text::lower(&r.word) == low).map_or(-40.0, |r| r.score());
        if best.score() - typed_score <= SLIP_MARGIN || best.likelihood <= SLIP_LIKELIHOOD_FLOOR {
            return None;
        }
        let word = best.word.clone();
        (!lm.prefers_finishing(&low, &word, &before)).then_some(word)
    }

    // MARK: từ tiếp theo

    fn next_words(&mut self, capitalize: bool) -> Vec<String> {
        let context = self.state.context.clone();
        let vietnamese = !self.state.english;
        let out = self.lm(vietnamese).map(|lm| lm.next_words(&context, 3)).unwrap_or_default();
        if capitalize {
            out.iter().map(|w| capitalized(w)).collect()
        } else {
            out
        }
    }

    /// Viết hoa chữ đầu như từ đã gõ ("Teh" → "The").
    fn cased(&self, s: &str) -> String {
        if text::first(&self.state.shown).is_some_and(text::is_uppercase) {
            capitalized(s)
        } else {
            s.to_string()
        }
    }
}

fn capitalized(s: &str) -> String {
    match text::first(s) {
        Some(f) => text::upper(f) + &s[f.len()..],
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn no_models() -> Suggester {
        Suggester::new(Models::new("/nonexistent"), Box::new(|_| false))
    }

    #[test]
    fn looks_typed_rules() {
        for w in ["rhonk", "teh", "helo", "nhaz"] {
            assert!(looks_typed(w), "{w}");
        }
        for w in ["ntn", "xkcd", "oiii", "nhaa", "hmmm", "byy", "ok"] {
            assert_eq!(looks_typed(w), w == "ok", "{w}");
        }
    }

    #[test]
    fn word_tracking_and_undo() {
        let mut s = no_models();
        for (i, c) in "teh".chars().enumerate() {
            s.letter(c, i as f32, 0.0);
        }
        s.backspace();
        assert_eq!(s.typed, "te");
        assert_eq!(s.xs, vec![0.0, 1.0]);
        // không có mô hình: ô duy nhất là từ đã gõ, không ngoặc kép
        let cells = s.update("hi te", true, "", false);
        assert_eq!(cells, vec![Suggestion { text: "te".into(), ..Default::default() }]);
        assert_eq!(s.shown_word(), "te");
        assert!(s.is_current("hi te") && !s.is_current("hi t"));
        assert!(s.touch_odds().is_none() && s.correction().is_none());
        // trạng thái Việt, chữ có dấu: không ô nào
        assert!(s.update("tiếng", false, "tieengs", false).is_empty());
        assert_eq!(s.shown_word(), "tiếng");
        assert!(s.update("tie\u{301}ng", false, "", false).is_empty());
        assert_eq!(s.shown_word(), "tie\u{301}ng");
        // sau dấu cách, không mô hình: không có từ tiếp theo
        assert!(s.update("hi ", true, "", false).is_empty());

        // hoàn tác lần tự sửa: chữ đã sửa còn trước con trỏ
        s.did_correct("teh", "the ");
        assert_eq!(s.last_correction(), Some(("teh", "the ")));
        assert_eq!(s.undo_correction("I said the "), Some((4, "teh".to_string())));
        assert_eq!(s.keep_word.as_deref(), Some("teh"));
        assert_eq!(s.undo_correction("I said the "), None, "chỉ một lần");
        // con trỏ đã dời: không hoàn tác, và cũng hết cơ hội
        s.did_correct("Teh", "The.");
        assert_eq!(s.undo_correction("The"), None);
        assert_eq!(s.last_correction(), None);
        s.did_correct("teh", "the ");
        s.forget_correction();
        assert_eq!(s.undo_correction("the "), None);
        // giữ nguyên từ trong ngoặc kép
        s.update("hi xog", true, "", false);
        s.keep_shown();
        assert_eq!(s.keep_word.as_deref(), Some("xog"));
        s.reset();
        assert!(s.keep_word.is_none() && s.shown_word().is_empty());
    }

    #[test]
    fn touch_pick_without_odds_is_the_touched_key() {
        let mut s = no_models();
        let key = |index, kind, row, x| TouchKey { index, kind, row, x, y: row as f64 * 54.0, w: 33.0, h: 43.0 };
        s.set_keys(vec![
            key(0, TapKind::Letter(0), 0, 0.0),
            key(1, TapKind::Letter(1), 0, 40.0),
            TouchKey { index: 5, kind: TapKind::Space, row: 1, x: 0.0, y: 54.0, w: 200.0, h: 43.0 },
        ]);
        assert_eq!(s.letter_rects.len(), 2);
        assert_eq!(s.letter_rects[1].letter, b'b');
        s.update("ab", true, "", false);
        assert_eq!(s.touch_pick(32.0, 10.0, 0), 0);
        assert_eq!(s.touch_pick(32.0, 48.0, 0), 0, "khe trên phím cách: không mô hình thì không biết từ đã trọn");
        assert_eq!(s.touch_pick(32.0, 10.0, 9), 9, "phím không tham gia");
    }

    #[test]
    fn a_warm_pass_from_before_cool_down_counts_for_nothing() {
        // không có file: "sẵn sàng" chỉ là cờ, mô hình vẫn không có; lượt cũ không được đặt cờ
        let m = Models::new("/nonexistent");
        let pass = m.generation.load(Ordering::SeqCst);
        m.cool_down();
        assert!(!m.warm_lang(false, pass));
        assert!(!m.en.ready.load(Ordering::SeqCst));
        m.warm(false);
        assert!(m.en.ready.load(Ordering::SeqCst) && m.vi.ready.load(Ordering::SeqCst));
        assert!(!m.ready(false), "thiếu file: không có mô hình");
        m.cool_down();
        assert!(!m.en.ready.load(Ordering::SeqCst) && !m.vi.ready.load(Ordering::SeqCst));
    }

    #[test]
    fn missing_or_broken_files_are_no_model() {
        let dir = std::env::temp_dir().join(format!("vipi-suggest-broken-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        // sai mã đầu, cắt ngắn, đúng mã đầu mà thân là rác
        std::fs::write(dir.join(EN_FILES[0]), b"VKLM0001garbage").unwrap();
        let mut body = b"VKLM0002".to_vec();
        body.extend(std::iter::repeat_n(0xAB, 4096));
        std::fs::write(dir.join(VI_FILES[0]), &body).unwrap();
        std::fs::write(dir.join(VI_FILES[1]), b"VKNN0001\x01\x00").unwrap();
        let models = Models::new(&dir);
        assert!(!models.ready(false) && !models.ready(true));
        models.warm(true);
        assert!(!models.ready(false) && !models.ready(true));
        let mut s = Suggester::new(models, Box::new(|_| false));
        assert!(s.update("I want to th", true, "", false).len() == 1);
        assert!(s.update("kỳ th", false, "th", false).is_empty());
        assert!(s.touch_odds().is_none());
        std::fs::remove_dir_all(&dir).ok();
    }
}
