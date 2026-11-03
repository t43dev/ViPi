//! So khớp lõi Rust với đáp án mẫu xuất từ bộ gõ Swift (scripts/make-golden.sh, Tests/ViPiCoreTests/GoldenTests.swift).

use std::collections::HashSet;
use std::io::Read;
use std::path::PathBuf;
use std::sync::Arc;

use vipi_core::autoswitch::AutoSwitch;
use vipi_core::bigram::BigramModel;
use vipi_core::convert::ChineseConverter;
use vipi_core::pinyin::{FuzzyRule, PinyinDictionary, PinyinEngine};
use vipi_core::telex::{render, telex_keys, MacroTable, TelexEngine, TextEdit, VietnameseLexicon};
use vipi_core::userdict::PinyinUserDictionary;

fn resources() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../Resources")
}

fn golden(name: &str) -> Vec<String> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/golden").join(format!("{name}.gz"));
    let mut text = String::new();
    flate2::read::GzDecoder::new(std::fs::File::open(&path).expect("golden file")).read_to_string(&mut text).unwrap();
    text.lines().map(String::from).collect()
}

/// Gom các dòng lệch, in vài dòng đầu, rồi báo lỗi nếu có.
struct Report {
    name: &'static str,
    total: usize,
    bad: Vec<String>,
}

impl Report {
    fn new(name: &'static str) -> Report {
        Report { name, total: 0, bad: vec![] }
    }

    fn check(&mut self, want: &str, got: &str, context: &str) {
        self.total += 1;
        if want != got {
            self.bad.push(format!("{context}\n   want: {want:?}\n    got: {got:?}"));
        }
    }

    fn finish(self) {
        println!("{}: {} checks, {} mismatches", self.name, self.total, self.bad.len());
        for b in self.bad.iter().take(15) {
            println!("  {b}");
        }
        assert!(self.bad.is_empty(), "{}: {} of {} differ from Swift", self.name, self.bad.len(), self.total);
    }
}

fn enc(e: Option<TextEdit>) -> String {
    e.map(|e| format!("{}:{}", e.backspaces, e.insert)).unwrap_or_else(|| "-".into())
}

#[test]
fn telex_matches_swift() {
    let lexicon = Arc::new(VietnameseLexicon::new(
        &std::fs::read_to_string(resources().join("vietnamese-syllables.txt")).unwrap(),
    ));
    let macros =
        MacroTable::new(&[("vn", "Việt Nam"), ("đc", "được"), ("ko", "không"), ("hn", "Hà Nội"), ("tp", "thành phố")]);
    let mut r = Report::new("telex");
    for line in golden("telex.txt") {
        let f: Vec<&str> = line.split('\t').collect();
        if f[0] == "keys" {
            r.check(f[2], &telex_keys(f[1]).into_iter().collect::<String>(), &format!("telexKeys {}", f[1]));
            continue;
        }
        let (modern, spell) = match f[0] {
            "c1" => (false, true),
            "m1" => (true, true),
            "c0" => (false, false),
            _ => (true, false),
        };
        let engine = || {
            let mut e = TelexEngine::new();
            e.modern_tone_style = modern;
            e.spell_check = spell;
            e.lexicon = spell.then(|| lexicon.clone());
            e
        };
        let keys: Vec<char> = f[1].chars().collect();
        let mut a = engine();
        let edits: Vec<String> = keys.iter().map(|&k| enc(Some(a.type_key(k)))).collect();
        let output = a.output();
        let finish = enc(a.finish_word());
        let mut b = engine();
        for &k in &keys {
            b.type_key(k);
        }
        b.backspace();
        let back1 = format!("{}/{}", b.output(), b.keys().iter().collect::<String>());
        let after = enc(Some(b.type_key('s')));
        let after_out = b.output();
        let mut c = engine();
        for &k in &keys {
            c.type_key(k);
        }
        let macro_edit = enc(c.expand_macro(&macros));
        let got = [f[0], f[1], &edits.join("|"), &output, &finish, &back1, &after, &after_out, &macro_edit].join("\t");
        r.check(&line, &got, &format!("{} {}", f[0], f[1]));
    }
    r.finish();
}

#[test]
fn auto_switch_matches_swift() {
    let mut auto = AutoSwitch::open(&resources()).unwrap();
    let mut r = Report::new("autoswitch");
    for line in golden("autoswitch.txt") {
        let f: Vec<&str> = line.split('\t').collect();
        let prev: Option<Vec<char>> = if f[0] == "-" { None } else { Some(f[0].chars().collect()) };
        let keys: Vec<char> = f[1].chars().collect();
        let shown = render(&keys, false, true);
        let b = |v: bool| if v { "1" } else { "0" };
        auto.remember(prev.clone(), true); // đang gõ tiếng Việt
        let pe = b(auto.prefers_english(&keys, &shown));
        let fo = b(auto.is_foreign(&keys, &shown));
        auto.remember(prev, false); // đang gõ tiếng Anh
        let vn = auto.vietnamese_for(&keys, false).unwrap_or_else(|| "-".into());
        let vnm = auto.vietnamese_for(&keys, true).unwrap_or_else(|| "-".into());
        let got = [f[0], f[1], &shown, pe, fo, &vn, &vnm].join("\t");
        r.check(&line, &got, &format!("prev={} {}", f[0], f[1]));
    }
    r.finish();
}

struct Pinyin {
    dict: Arc<PinyinDictionary>,
    bigram: Arc<BigramModel>,
    traditional: Arc<ChineseConverter>,
}

impl Pinyin {
    fn load() -> Pinyin {
        Pinyin {
            dict: Arc::new(PinyinDictionary::open(&resources()).unwrap()),
            bigram: Arc::new(BigramModel::open(&resources().join("bigram.bin")).unwrap()),
            traditional: Arc::new(ChineseConverter::open(&resources().join("s2t.bin")).unwrap()),
        }
    }

    fn engine(&self, cfg: &str) -> PinyinEngine {
        let mut e = PinyinEngine::new(self.dict.clone());
        if cfg.starts_with('b') {
            e.set_bigram(Some(self.bigram.clone()));
        }
        if cfg == "bf" {
            e.set_fuzzy_rules(FuzzyRule::ALL.iter().map(|r| r.id()).collect::<HashSet<String>>());
        }
        if cfg == "bt" {
            e.set_converter(Some(self.traditional.clone()));
        }
        e
    }
}

fn cands(e: &PinyinEngine, n: usize) -> String {
    e.candidates().iter().take(n).map(|c| format!("{}\u{1f}{}", c.text, c.length)).collect::<Vec<_>>().join("\u{1e}")
}

#[test]
fn pinyin_matches_swift() {
    let py = Pinyin::load();
    let lines = golden("pinyin.txt");
    let mut r = Report::new("pinyin");
    let mut engines: Vec<(String, PinyinEngine)> = vec![];
    for line in &lines {
        let f: Vec<&str> = line.split('\t').collect();
        if engines.last().is_none_or(|(c, _)| c != f[0]) {
            engines.push((f[0].to_string(), py.engine(f[0])));
        }
        let e = &mut engines.last_mut().unwrap().1;
        e.reset();
        for c in f[1].chars() {
            e.type_char(c);
        }
        let got = [f[0], f[1], &e.preedit(), &cands(e, usize::MAX)].join("\t");
        r.check(line, &got, &format!("{} {}", f[0], f[1]));
    }
    r.finish();

    // chọn từng phần, Backspace, Enter, học từ: đúng thủ tục của GoldenTests.swift
    let inputs: Vec<String> =
        lines.iter().filter(|l| l.starts_with("u\t")).map(|l| l.split('\t').nth(1).unwrap().to_string()).collect();
    let mut r = Report::new("pinyin-select");
    let steps = golden("pinyin-select.txt");
    let mut it = steps.iter();
    for cfg in ["u", "b", "bf", "bt"] {
        let mut e = py.engine(cfg);
        e.user_dictionary = Some(PinyinUserDictionary::in_memory());
        for (n, input) in inputs.iter().enumerate().filter(|(n, _)| n % 3 == 0) {
            e.reset();
            for c in input.chars() {
                e.type_char(c);
            }
            let mut log: Vec<String> = vec![];
            let mut step = 0;
            while e.is_composing() && step < 12 {
                if step == 2 && n % 2 == 0 {
                    e.backspace();
                    log.push(format!("B>{}@{}", e.input(), e.preedit()));
                }
                if e.candidates().is_empty() {
                    log.push(format!("R>{}", e.commit_raw()));
                    break;
                }
                let i = (step * 2 + n) % e.candidates().len().min(4);
                let out = e.select(i).unwrap_or_else(|| "-".into());
                log.push(format!("{i}>{out}@{}@{}", e.input(), e.preedit()));
                step += 1;
            }
            if e.is_composing() {
                log.push(format!("R>{}", e.commit_raw()));
            }
            for c in input.chars() {
                e.type_char(c);
            }
            log.push(format!("again>{}", cands(&e, 5)));
            e.reset();
            let want = it.next().expect("select line");
            r.check(want, &[cfg, input, &log.join("\u{1d}")].join("\t"), &format!("{cfg} {input}"));
        }
    }
    assert!(it.next().is_none(), "select lines left over");
    r.finish();
}

#[test]
fn traditional_and_bigram_match_swift() {
    let py = Pinyin::load();
    let mut r = Report::new("convert");
    for line in golden("convert.txt") {
        let (phrase, want) = line.split_once('\t').unwrap();
        r.check(want, &py.traditional.convert(phrase), phrase);
    }
    r.finish();
    let mut r = Report::new("bigram");
    for line in golden("bigram.txt") {
        let f: Vec<&str> = line.split('\t').collect();
        r.check(f[2], &py.bigram.log_prob(f[0], f[1], 1e-5).to_bits().to_string(), &format!("{} {}", f[0], f[1]));
    }
    r.finish();
}
