//! Composer: gõ cả chuỗi phím qua đúng đường đi của bàn phím thật và kiểm chữ trên "màn hình".

use std::path::PathBuf;

use vipi_core::{Composer, Key, KeyResult, Mode};

fn resources() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../Resources")
}

/// Ô văn bản giả: áp kết quả của từng phím như một nền tảng thật.
struct Screen {
    text: Vec<char>,
}

impl Screen {
    fn apply(&mut self, key: Key, r: &KeyResult) {
        if let Some(e) = &r.edit {
            assert!(r.handled, "edit without handled: {r:?}");
            self.text.truncate(self.text.len() - e.backspaces);
            self.text.extend(e.insert.chars());
        }
        if !r.handled || r.repost_key {
            match key {
                Key::Char(c) => self.text.push(c),
                Key::Space => self.text.push(' '),
                Key::Enter => self.text.push('\n'),
                Key::Backspace => {
                    self.text.pop();
                }
                _ => {}
            }
        }
    }
}

fn key_for(c: char) -> Key {
    match c {
        ' ' => Key::Space,
        '\n' => Key::Enter,
        '⌫' => Key::Backspace,
        '⎋' => Key::Escape,
        '→' => Key::Right,
        '↓' => Key::Down,
        c => Key::Char(c),
    }
}

fn type_all(c: &mut Composer, keys: &str) -> String {
    let mut s = Screen { text: vec![] };
    for ch in keys.chars() {
        let k = key_for(ch);
        let r = c.handle_key(k);
        s.apply(k, &r);
    }
    s.text.iter().collect()
}

fn composer() -> Composer {
    let mut c = Composer::open(&resources()).unwrap();
    c.set_vietnamese_options(false, true, true);
    c
}

#[test]
fn vietnamese_words_and_restore() {
    let mut c = composer();
    assert_eq!(type_all(&mut c, "tieengs Vieetj laf ngoon nguwx "), "tiếng Việt là ngôn ngữ ");
    assert_eq!(type_all(&mut c, "user data class "), "user data class ");
    assert_eq!(type_all(&mut c, "tessting "), "testing ");
    assert_eq!(type_all(&mut c, "vieejt⌫n "), "viện ");
    c.set_vietnamese_options(true, true, true);
    assert_eq!(type_all(&mut c, "hoaf khoer "), "hoà khoẻ ");
}

#[test]
fn shortcuts_only_for_standalone_words() {
    let mut c = composer();
    let pairs = vec![("vn".to_string(), "Việt Nam".to_string()), ("đc".to_string(), "được".to_string())];
    c.set_macros(&pairs, true, true);
    assert_eq!(type_all(&mut c, "vn VN ddc "), "Việt Nam VIỆT NAM được ");
    assert_eq!(type_all(&mut c, "call2vn@ "), "call2vn@ ");
    c.set_mode(Mode::English);
    assert_eq!(type_all(&mut c, "Vn ok "), "Việt Nam ok ");
}

/// Ca thử lấy từ Tools/autoswitch/rules/rules.tsv của Vikey (GPL-3.0), như AutoSwitchTests.swift.
fn check_auto(cases: &[(&str, &str, bool)], start: Mode) {
    for (keys, want, want_vi) in cases {
        let mut c = composer();
        c.set_vietnamese_options(true, true, true);
        c.set_auto_switch(true);
        c.set_mode(start);
        assert_eq!(type_all(&mut c, keys), *want, "keys: {keys}");
        assert_eq!(c.mode() == Mode::Vietnamese, *want_vi, "final mode, keys: {keys}");
    }
}

#[test]
fn auto_switch_from_vietnamese() {
    check_auto(
        &[
            ("as ", "á ", true),
            ("boss ", "boss ", false),
            ("more ", "more ", false),
            ("server ", "server ", false),
            ("car ", "cả ", true),
            ("too ", "tô ", true),
            ("this ", "thí ", true),
            ("the best test must pass ", "the best test must pass ", false),
            ("tooi ddi hocj owr truwowngf ddaij hocj ", "tôi đi học ở trường đại học ", true),
            ("khoer khoong ", "khoẻ không ", true),
            ("var x ", "vả x ", true),
            ("tooi nghix gif ddos ", "tôi nghĩ gì đó ", true),
            ("cais testflight build ", "cái testflight build ", false),
            ("analytics dashboard ", "analytics dashboard ", false),
            ("tooi thicsh lanwm ", "tôi thích lanwm ", true),
            ("video call this ", "video call this ", false),
            ("deploy leen server nhes ", "deploy lên server nhé ", true),
            // cặp từ (Vikey D30): cách đọc nào hay đứng sau từ trước hơn trong văn bản thật
            ("cho con bus ", "cho con bú ", true),
            ("ddi xe bus ", "đi xe bus ", false),
            ("owr been ", "ở bên ", true),
            ("sang mix ", "sang mĩ ", true),
            ("cachs mix ddoof ", "cách mix đồ ", true),
            // sửa ngược từ ngay trước (Vikey D8, D13, D20, D42)
            ("this makes sense ", "this makes sense ", false),
            ("last week i lost my test, it is the best ", "last week i lost my test, it is the best ", false),
            ("(this create ", "(this create ", false),
            ("\"this create ", "\"this create ", false),
            ("tooi thaays bee app bij loix ", "tôi thấy bê app bị lõi ", true),
            ("been USA ", "bên USA ", false),
            ("been server ", "bên server ", false),
            ("car server ", "cả server ", false),
            ("queen deploy ", "quên deploy ", true),
            // Telex nuốt phím: tên biến, từ nhiều âm tiết, viết tắt, tên riêng (D18, D19, D23)
            ("currentState ", "currentState ", false),
            ("currentWindow ", "currentWindow ", false),
            // gõ đôi để bỏ dấu trong từ ghép tiếng Anh không có trong danh sách: giữ chữ đang hiện
            ("tesstflight ", "testflight ", true),
            ("posstgres ", "postgres ", true),
            ("USSD ", "USSD ", false),
            // chữ gõ đôi thật, không có dấu hiệu đang gõ Telex: giữ như đã gõ
            ("ussd ", "ussd ", false),
            ("Ussd ", "Ussd ", false),
            // chữ đôi thật trước nguyên âm, kể cả từ không có trong danh sách: giữ như đã gõ
            ("correlate assail ", "correlate assail ", false),
            ("mirrorless ", "mirrorless ", false),
            ("terrorizer ", "terrorizer ", false),
            ("cheese, ", "cheese, ", false),
            ("ASUS ", "ASUS ", false),
            ("Momo ", "Momo ", false),
            ("been Momo ", "bên Momo ", false),
            // dạng từ tiếng Anh (D60): "rêts" không phải chữ nào, dù cùng khoá với "rết"
            ("resets ", "resets ", false),
            ("quests ", "quests ", false),
            ("phis ", "phí ", true),
            // đ viết tắt, số (D27, D33)
            ("ddc ", "đc ", true),
            ("abc1def ", "abc1def ", true),
            ("sacj 2w ", "sạc 2w ", true),
            ("mua 1casi ", "mua 1cái ", true),
        ],
        Mode::Vietnamese,
    );
}

#[test]
fn auto_switch_after_digits_and_symbols() {
    // số và dấu khác dấu cách cũng kết thúc từ: từ tiếng Anh Telex gõ sai được trả lại như khi gõ dấu cách
    check_auto(
        &[
            ("pass1 ", "pass1 ", false),
            ("affair-based ", "affair-based ", false),
            ("java2shell ", "java2shell ", true),
            ("access_token ", "access_token ", false),
            ("phongf2 ", "phòng2 ", true),
            ("ddaij-hocj ", "đại-học ", true),
        ],
        Mode::Vietnamese,
    );
}

#[test]
fn auto_switch_from_english() {
    check_auto(
        &[
            ("treen ", "trên ", true),
            ("truowfng ", "trường ", true),
            ("truongwf ", "trường ", true),
            ("Truowfng Sa ", "Trường Sa ", true),
            // gõ đôi phím thanh theo thói quen Telex trong từ tiếng Anh: chữ tiếng Anh, ở lại tiếng Anh
            ("tesstflight ", "testflight ", false),
            ("posstgres ", "postgres ", false),
            ("tesst1 ", "test1 ", false),
            ("currentState ", "currentState ", false),
            ("boss pass ", "boss pass ", false),
            ("USS USSD ", "USS USSD ", false),
            // chữ đôi thật trước nguyên âm, kể cả từ không có trong danh sách: giữ như đã gõ
            ("correlate assail ", "correlate assail ", false),
            ("con ban an ", "con ban an ", false),
            ("the theme of rust and axis ", "the theme of rust and axis ", false),
            ("i must trust the rest of the list ", "i must trust the rest of the list ", false),
            ("car been ", "car been ", false),
            ("USA EST IRS ", "USA EST IRS ", false),
            ("var x ", "var x ", false),
            ("const deps refs uri ", "const deps refs uri ", false),
            ("git push origin main ", "git push origin main ", false),
            ("obj.dir my_dir ", "obj.dir my_dir ", false),
            ("deploy leen server nhes ", "deploy lên server nhé ", true),
            ("Hey guys, cos ai ddi khoong ", "Hey guys, có ai đi không ", true),
            ("video call cos ", "video call cos ", false),
            ("ok vaayj thi mai gaawpj nhes ", "ok vậy thi mai gặp nhé ", true),
            ("the bus ", "the bus ", false),
            // cặp từ rõ là tiếng Việt thắng luật "ngay sau từ tiếng Anh" (D34)
            ("test cos work ", "test có work ", false),
            ("this get resets ", "this get resets ", false),
            ("ddc ", "đc ", true),
            // Caps Lock gõ tiếng Việt (D23, D41); viết tắt thì giữ
            ("THOONG ", "THÔNG ", true),
            ("TOOI DDI HOCJ ", "TÔI ĐI HỌC ", true),
            ("DDaf Nawngx ", "Đà Nẵng ", true),
            ("HDD DDR ", "HDD DDR ", false),
        ],
        Mode::English,
    );
}

#[test]
fn auto_switch_pauses_after_manual_switch() {
    let mut c = composer();
    c.set_auto_switch(true);
    c.set_mode(Mode::English);
    c.pause_auto_switch();
    assert_eq!(type_all(&mut c, "treen "), "treen ");
    assert_eq!(c.mode(), Mode::English);
    c.pause_auto_switch_for(std::time::Duration::ZERO);
    assert_eq!(type_all(&mut c, "treen "), "trên ");
    assert_eq!(c.mode(), Mode::Vietnamese);
}

#[test]
fn chinese_composition() {
    let mut c = composer();
    c.set_mode(Mode::Chinese);
    assert_eq!(type_all(&mut c, "nihao "), "你好");
    assert_eq!(type_all(&mut c, "woshizhongguoren\n"), "woshizhongguoren");
    assert_eq!(type_all(&mut c, "xiexie,"), "谢谢，");
    assert_eq!(type_all(&mut c, "nihao1"), "你好");
    // pinyin không có ứng viên: số không bị nuốt
    assert_eq!(type_all(&mut c, "java2"), "java2");
    assert_eq!(type_all(&mut c, "nihao⎋"), "");
    // chọn từng phần: "你好" dùng hết "nihao", còn "ma"
    let mut s = Screen { text: vec![] };
    for ch in "nihaoma".chars() {
        let r = c.handle_key(Key::Char(ch));
        s.apply(Key::Char(ch), &r);
    }
    let i = c.candidates().iter().position(|x| x.text == "你好").unwrap();
    let r = c.select_candidate(i);
    assert!(r.edit.is_none() && r.panel_changed);
    assert_eq!(c.preedit(), "你好ma");
    let i = c.candidates().iter().position(|x| x.text == "吗").unwrap();
    let r = c.select_candidate(i);
    s.apply(Key::Other, &r);
    assert_eq!(s.text.iter().collect::<String>(), "你好吗");
    assert!(c.panel().is_none());
    // chữ hoa khi đang gõ: chọn ứng viên đầu rồi cho chữ đi qua
    assert_eq!(type_all(&mut c, "nihaoA"), "你好A");
}

#[test]
fn chinese_paging_and_traditional() {
    let mut c = composer();
    c.set_mode(Mode::Chinese);
    for ch in "shi".chars() {
        c.handle_key(Key::Char(ch));
    }
    let p = c.panel().unwrap();
    assert_eq!((p.items.len(), p.has_prev, p.has_next, p.first_index), (9, false, true, 0));
    c.handle_key(Key::Down);
    let p = c.panel().unwrap();
    assert_eq!((p.has_prev, p.first_index, p.highlight), (true, 9, 0));
    c.handle_key(Key::Right);
    assert_eq!(c.panel().unwrap().highlight, 1);
    c.cancel();
    c.set_traditional(true);
    assert_eq!(type_all(&mut c, "toufa "), "頭髮");
}

#[test]
fn english_mode_passes_keys_through() {
    let mut c = composer();
    c.set_mode(Mode::English);
    for ch in "hello world".chars() {
        let r = c.handle_key(key_for(ch));
        assert!(!r.handled && r.edit.is_none());
    }
}

/// Sửa cả hai từ thì Backspace chỉ xoá như thường, không dựng lại "thí" (Vikey D20).
#[test]
fn look_back_has_no_undo() {
    let mut c = composer();
    c.set_vietnamese_options(true, true, true);
    c.set_auto_switch(true);
    c.set_mode(Mode::Vietnamese);
    assert_eq!(type_all(&mut c, "this create ⌫s"), "this creates");
    assert_eq!(c.mode(), Mode::English);
}

/// Xoá lùi ra ngoài từ đang gõ rồi gõ từ khác: không sửa ngược từ đã xoá (trước đây xoá lùi quá tay vào chữ trước).
#[test]
fn look_back_forgets_a_deleted_word() {
    let typed = |keys: &str| {
        let mut c = composer();
        c.set_vietnamese_options(true, true, true);
        c.set_auto_switch(true);
        c.set_mode(Mode::Vietnamese);
        type_all(&mut c, keys)
    };
    assert_eq!(typed("xin chao this ⌫⌫⌫⌫server "), "xin chao server ");
    assert_eq!(typed("this ⌫⌫⌫⌫server "), "server ");
}

/// Backspace khi đang gõ pinyin đưa khung chọn về trang đầu: Space chọn ứng viên đầu, không phải mục của trang cũ.
#[test]
fn chinese_backspace_returns_to_first_page() {
    let mut c = composer();
    c.set_mode(Mode::Chinese);
    let first = type_all(&mut c, "zhongguo ");
    c.cancel();
    assert_eq!(type_all(&mut c, "zhongguoren=="), "");
    assert_eq!(type_all(&mut c, "⌫⌫⌫ "), first);
}

/// Backspace ngay sau một lần tự đổi (Vikey D61): cái đầu chỉ xoá phím kết thúc từ, chữ đã sửa giữ nguyên;
/// cái thứ hai liền sau trả lại chữ trước đó và chế độ cũ; phím khác chen vào thì hết.
#[test]
fn backspace_undoes_auto_switch() {
    let typed = |mode: Mode, keys: &str| {
        let mut c = composer();
        c.set_vietnamese_options(true, true, true);
        c.set_auto_switch(true);
        c.set_mode(mode);
        (type_all(&mut c, keys), c.mode())
    };
    // tiếng Anh → tiếng Việt: "treen " → "trên "; ⌫ → "trên" (thêm được dấu phẩy); ⌫⌫ → "treen", lại tiếng Anh
    assert_eq!(typed(Mode::English, "treen ⌫"), ("trên".into(), Mode::Vietnamese));
    assert_eq!(typed(Mode::English, "treen ⌫,"), ("trên,".into(), Mode::Vietnamese));
    assert_eq!(typed(Mode::English, "treen ⌫ "), ("trên ".into(), Mode::Vietnamese));
    assert_eq!(typed(Mode::English, "treen,⌫."), ("trên.".into(), Mode::Vietnamese));
    assert_eq!(typed(Mode::English, "treen ⌫⌫"), ("treen".into(), Mode::English));
    assert_eq!(typed(Mode::English, "treen ⌫⌫⌫"), ("tree".into(), Mode::English));
    // kết thúc lại đúng từ đó: giữ như đã gõ
    assert_eq!(typed(Mode::English, "treen ⌫⌫ "), ("treen ".into(), Mode::English));
    // gõ tiếp cho thành từ khác: lại được xét ("vaay" ⌫⌫ … "j" → "vậy")
    assert_eq!(typed(Mode::English, "vaay ⌫⌫j ").0, "vậy ");
    // tiếng Việt → tiếng Anh: "server " giữ "server", sang tiếng Anh; ⌫ giữ nguyên, ⌫⌫ về tiếng Việt
    assert_eq!(typed(Mode::Vietnamese, "server ⌫"), ("server".into(), Mode::English));
    assert_eq!(typed(Mode::Vietnamese, "merge ⌫,"), ("merge,".into(), Mode::English));
    assert_eq!(typed(Mode::Vietnamese, "merge ⌫⌫"), ("merge".into(), Mode::Vietnamese));
    // sau Backspace đầu gõ tiếp chữ cái: chữ vừa sửa lại là từ đang gõ, thêm được dấu (Vikey: "vaay <j ")
    assert_eq!(typed(Mode::English, "vaay ⌫j "), ("vậy ".into(), Mode::Vietnamese));
    // như gõ liền "treenn": không thành chữ Việt thì trả lại các phím đã gõ
    assert_eq!(typed(Mode::English, "treen ⌫n "), ("treenn ".into(), Mode::Vietnamese));
    assert_eq!(typed(Mode::Vietnamese, "server ⌫s "), ("servers ".into(), Mode::English));
    assert_eq!(typed(Mode::English, "vaay ⌫j⌫⌫⌫"), ("".into(), Mode::Vietnamese));
    // phím khác chen vào (trước hay giữa hai Backspace): Backspace chỉ xoá một ký tự như thường
    assert_eq!(typed(Mode::English, "treen a⌫"), ("trên ".into(), Mode::Vietnamese));
    assert_eq!(typed(Mode::English, "treen ⌫,⌫⌫"), ("trê".into(), Mode::Vietnamese));
}
