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
