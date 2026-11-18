//! Gợi ý từ: so với đáp án của bộ gợi ý Swift (scripts/make-suggest-golden.sh, ios/Tools/suggest-golden/main.swift),
//! và các hành vi của bàn phím iOS đã kiểm tra trên máy ảo. Cần 4 file mô hình (scripts/suggest-models.sh) ở
//! VIPI_SUGGEST_MODELS hoặc build/suggest; không có thì các bài này in một dòng rồi bỏ qua.
//!
//! So khớp: chữ, id, chỉ số phím và mọi quyết định (ô gợi ý, chữ sửa) phải y hệt; số thực lệch tương đối tới 1e-4.
//! Chỉ các số qua mạng (SuggestNN: comp, next, prob, độ hợp câu của taps) lệch đáng kể, lớn nhất ~9e-5 (2026-11-18);
//! bản Rust cộng các tích bằng f64 cũng lệch y như thế, nên không phải do thứ tự cộng bên Rust. Số đếm, xác suất chữ /
//! phím kế tiếp và khoảng cách chạm lệch ở bit cuối (~1e-16) hoặc không lệch. Bài in lệch lớn nhất theo từng loại dòng.

use std::collections::HashSet;
use std::io::Read;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use vipi_core::suggest::{tap, telex_spellings, Models, Suggester, TapKind, TouchKey};

fn models_dir() -> Option<PathBuf> {
    let dir = std::env::var_os("VIPI_SUGGEST_MODELS")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../build/suggest"));
    let all =
        ["SuggestEN.bin", "SuggestNN.bin", "SuggestVI.bin", "SuggestVINN.bin"].iter().all(|f| dir.join(f).is_file());
    if !all {
        println!("suggest: no model files in {} (scripts/suggest-models.sh): skipped", dir.display());
    }
    all.then_some(dir)
}

fn resources() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../Resources")
}

const KNOWN: [&str; 4] = ["ok", "lol", "ntn", "anh"];

fn suggester(dir: PathBuf) -> Suggester {
    let models = Models::open(dir, resources());
    models.warm(false);
    assert!(models.ready(false) && models.ready(true));
    let known: HashSet<&str> = KNOWN.into_iter().collect();
    Suggester::new(models, Box::new(move |w| known.contains(w)))
}

fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            match it.next() {
                Some('t') => out.push('\t'),
                Some('n') => out.push('\n'),
                Some(o) => out.push(o),
                None => {}
            }
        } else {
            out.push(c);
        }
    }
    out
}

fn golden() -> Vec<(Vec<String>, Vec<String>)> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/golden/suggest.txt.gz");
    let mut text = String::new();
    flate2::read::GzDecoder::new(std::fs::File::open(&path).expect("golden file")).read_to_string(&mut text).unwrap();
    text.lines()
        .map(|l| {
            let f: Vec<String> = l.split('\t').map(unescape).collect();
            let eq = f.iter().position(|x| x == "=").expect("=");
            (f[..eq].to_vec(), f[eq + 1..].to_vec())
        })
        .collect()
}

thread_local! {
    /// lệch tương đối lớn nhất đã gặp, theo lệnh của dòng đang so (để in ra)
    static OP: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
    static WORST: std::cell::RefCell<std::collections::BTreeMap<String, f64>> =
        const { std::cell::RefCell::new(std::collections::BTreeMap::new()) };
}

fn close(a: f64, b: f64) -> bool {
    if a == b {
        return true;
    }
    let rel = (a - b).abs() / a.abs().max(b.abs());
    let op = OP.with(|o| o.borrow().clone());
    WORST.with(|w| {
        let mut w = w.borrow_mut();
        let x = w.entry(op).or_insert(0.0);
        *x = x.max(rel);
    });
    (a - b).abs() <= 1e-4 * a.abs().max(b.abs()) + 1e-12
}

#[derive(Default)]
struct Tally {
    lines: usize,
    exact: usize,
    tolerance: usize,
    ties: usize,
    bad: Vec<String>,
}

impl Tally {
    fn line(&mut self, ok: Result<Kind, String>, what: &str) {
        self.lines += 1;
        match ok {
            Ok(Kind::Exact) => self.exact += 1,
            Ok(Kind::Tolerance) => self.tolerance += 1,
            Ok(Kind::Tie) => self.ties += 1,
            Err(e) => self.bad.push(format!("{what}\n    {e}")),
        }
    }
}

#[derive(PartialEq, PartialOrd, Clone, Copy)]
enum Kind {
    Exact,
    Tolerance,
    Tie,
}

fn floats(want: &[String], got: &[f64]) -> Result<Kind, String> {
    if want.len() != got.len() {
        return Err(format!("want {want:?}, got {got:?}"));
    }
    let mut k = Kind::Exact;
    for (w, g) in want.iter().zip(got) {
        let w: f64 = w.parse().map_err(|_| format!("bad number {w}"))?;
        if w != *g {
            if !close(w, *g) {
                return Err(format!("want {want:?}, got {got:?}"));
            }
            k = Kind::Tolerance;
        }
    }
    Ok(k)
}

fn opt_floats(want: &[String], got: Option<Vec<f64>>) -> Result<Kind, String> {
    match got {
        None if want == ["-"] => Ok(Kind::Exact),
        Some(g) if want != ["-"] => floats(want, &g),
        g => Err(format!("want {want:?}, got {g:?}")),
    }
}

/// Danh sách (từ, điểm): cùng từ theo cùng thứ tự, điểm trong mức; hai từ đổi chỗ (hay từ cuối khác) chỉ khi điểm của
/// hai bên bằng nhau trong mức.
fn scored(want: &[String], got: &[(String, f64)]) -> Result<Kind, String> {
    let w: Vec<(String, f64)> = want.chunks(2).map(|c| (c[0].clone(), c[1].parse().unwrap())).collect();
    let err = || format!("want {w:?}, got {got:?}");
    if w.len() != got.len() {
        return Err(err());
    }
    let mut k = Kind::Exact;
    for ((ww, wp), (gw, gp)) in w.iter().zip(got) {
        if !close(*wp, *gp) {
            return Err(err());
        }
        if ww != gw {
            k = Kind::Tie;
        } else if wp != gp && k == Kind::Exact {
            k = Kind::Tolerance;
        }
    }
    Ok(k)
}

#[test]
fn suggest_matches_swift() {
    let Some(dir) = models_dir() else { return };
    let mut s = suggester(dir);
    let mut keys: Vec<TouchKey> = vec![];
    let mut odds: Vec<f64> = vec![];
    let mut t = Tally::default();
    let lang = |l: &str| l == "vi";
    for (f, want) in golden() {
        let what = f.join(" | ");
        OP.with(|o| *o.borrow_mut() = f[0].clone());
        let a: Vec<&str> = f.iter().map(String::as_str).collect();
        let r: Result<Kind, String> = match a[0] {
            "key" => {
                let n = |i: usize| a[i].parse::<f64>().unwrap();
                let kind = match a[2] {
                    "shift" => TapKind::Shift,
                    "back" => TapKind::Backspace,
                    "space" => TapKind::Space,
                    l => TapKind::Letter(l.as_bytes()[0] - b'a'),
                };
                keys.push(TouchKey {
                    index: n(1) as usize,
                    kind,
                    row: n(3) as i32,
                    x: n(4),
                    y: n(5),
                    w: n(6),
                    h: n(7),
                });
                s.set_keys(keys.clone());
                continue;
            }
            "telex" => {
                let got: Vec<String> = telex_spellings(a[1])
                    .into_iter()
                    .map(|(k, tone, share)| {
                        let tone = if tone == 0 { "-".to_string() } else { (tone as char).to_string() };
                        format!("{}/{}/{:?}", String::from_utf8(k).unwrap(), tone, share)
                    })
                    .collect();
                if got == want {
                    Ok(Kind::Exact)
                } else {
                    Err(format!("want {want:?}, got {got:?}"))
                }
            }
            op @ ("id" | "starts" | "count" | "form" | "ctx") => {
                let lm = s.lm(lang(a[1])).unwrap();
                let got = match op {
                    "id" => vec![lm.id(a[2]).map_or("-".into(), |i| i.to_string())],
                    "starts" => vec![if lm.starts_word(a[2]) { "1" } else { "0" }.to_string()],
                    "count" => vec![lm.count(a[2]).to_string()],
                    "form" => vec![lm.form(a[2].parse().unwrap())],
                    _ => {
                        let c = lm.context(a[2]);
                        let o = |x: Option<usize>| x.map_or("-".into(), |i| i.to_string());
                        vec![o(c.before), o(c.last), o(c.tri)]
                    }
                };
                if got == want {
                    Ok(Kind::Exact)
                } else {
                    Err(format!("want {want:?}, got {got:?}"))
                }
            }
            "next" => {
                let lm = s.lm(lang(a[1])).unwrap();
                let words = lm.next_words(a[2], a[3].parse().unwrap());
                let p = lm.probabilities(&words, a[2]);
                scored(&want, &words.into_iter().zip(p).collect::<Vec<_>>())
            }
            "comp" => {
                let lm = s.lm(lang(a[1])).unwrap();
                let words = lm.completions(a[2], a[3], a[4].parse().unwrap());
                let p = lm.probabilities(&words, a[3]);
                scored(&want, &words.into_iter().zip(p).collect::<Vec<_>>())
            }
            "prob" => floats(&want, &s.lm(lang(a[1])).unwrap().probabilities(&a[3..], a[2])),
            "pf" => {
                let got = s.lm(lang(a[1])).unwrap().prefers_finishing(a[2], a[3], a[4]);
                if want[0] == if got { "1" } else { "0" } {
                    Ok(Kind::Exact)
                } else {
                    Err(format!("want {want:?}, got {got}"))
                }
            }
            "letters" => {
                if want != ["-"] {
                    odds = want.iter().map(|x| x.parse().unwrap()).collect();
                }
                let got = s.lm(lang(a[1])).unwrap().next_letters(a[2], a[3]);
                opt_floats(&want, got)
            }
            "keys" => {
                if want != ["-"] {
                    odds = want.iter().map(|x| x.parse().unwrap()).collect();
                }
                let got = s.lm(lang(a[1])).unwrap().next_keys(a[2], a[3], a[4].parse().unwrap());
                opt_floats(&want, got)
            }
            "pick" => {
                // xác suất của dòng letters/keys ngay trước (số của Swift): chỉ so mô hình chạm
                let m = if lang(a[1]) { tap::VIETNAMESE } else { tap::ENGLISH };
                let got = tap::pick(a[2].parse().unwrap(), a[3].parse().unwrap(), &keys, &odds, &m);
                let got = got.map_or("-".into(), |i| i.to_string());
                if want == [got.clone()] {
                    Ok(Kind::Exact)
                } else {
                    Err(format!("want {want:?}, got {got}"))
                }
            }
            "taps" => {
                let taps: Vec<(f32, f32)> = a[3]
                    .split(';')
                    .map(|p| {
                        let (x, y) = p.split_once(',').unwrap();
                        (x.parse().unwrap(), y.parse().unwrap())
                    })
                    .collect();
                let rects = keys
                    .iter()
                    .filter_map(|k| match k.kind {
                        TapKind::Letter(l) => Some(vipi_core::suggest::KeyRect {
                            x: k.x as f32,
                            y: k.y as f32,
                            w: k.w as f32,
                            h: k.h as f32,
                            letter: b'a' + l,
                        }),
                        _ => None,
                    })
                    .collect::<Vec<_>>();
                let got = s.lm(lang(a[1])).unwrap().read_taps(&taps, &rects, a[2]);
                let w: Vec<(String, usize, f64, f64)> = want
                    .chunks(4)
                    .map(|c| (c[0].clone(), c[1].parse().unwrap(), c[2].parse().unwrap(), c[3].parse().unwrap()))
                    .collect();
                let err = || format!("want {w:?}, got {got:?}");
                if w.len() != got.len() {
                    Err(err())
                } else {
                    let mut k = Kind::Exact;
                    let mut res = Ok(());
                    for (x, g) in w.iter().zip(&got) {
                        WORST.with(|m| {
                            let mut m = m.borrow_mut();
                            let d = m.entry("taps log-likelihood (absolute)".into()).or_insert(0.0);
                            *d = d.max((x.3 - g.likelihood).abs());
                        });
                        if !close(x.2, g.closeness) || (x.3 - g.likelihood).abs() > 1e-4 {
                            res = Err(err());
                        } else if x.0 != g.word || x.1 != g.id {
                            if !close(x.2 + x.3, g.score()) {
                                res = Err(err());
                            }
                            k = Kind::Tie;
                        } else if (x.2 != g.closeness || x.3 != g.likelihood) && k == Kind::Exact {
                            k = Kind::Tolerance;
                        }
                    }
                    res.map(|_| k)
                }
            }
            "s.forget" => {
                s.forget_correction();
                continue;
            }
            "s.end" => {
                s.end_word();
                continue;
            }
            "s.back" => {
                s.backspace();
                continue;
            }
            "s.reset" => {
                s.reset();
                continue;
            }
            "s.keep" => {
                s.keep_shown();
                continue;
            }
            "s.letter" => {
                let x: f64 = a[2].parse().unwrap();
                let y: f64 = a[3].parse().unwrap();
                s.letter(a[1].chars().next().unwrap(), x as f32, y as f32);
                continue;
            }
            "s.did" => {
                s.did_correct(a[1], a[2]);
                continue;
            }
            "s.opts" => {
                s.suggestions_on = a[1] == "1";
                s.auto_correct_on = a[2] == "1";
                continue;
            }
            "s.correction" => {
                let got = s.correction().map(str::to_string);
                if got.as_deref() == Some(want[0].as_str()) {
                    Ok(Kind::Exact)
                } else {
                    Err(format!("want {want:?}, got {got:?}"))
                }
            }
            "s.undo" => {
                let got = s.undo_correction(a[1]).map_or(vec!["-".to_string()], |(d, i)| vec![d.to_string(), i]);
                if got == want {
                    Ok(Kind::Exact)
                } else {
                    Err(format!("want {want:?}, got {got:?}"))
                }
            }
            "s.ends" => {
                let got = s.word_ends(a[1]);
                if want[0] == if got { "1" } else { "0" } {
                    Ok(Kind::Exact)
                } else {
                    Err(format!("want {want:?}, got {got}"))
                }
            }
            "s.update" => {
                let cells = s.update(a[1], a[2] == "1", a[3], a[4] == "1");
                let mut got: Vec<String> = cells
                    .iter()
                    .map(|c| {
                        let flags = format!(
                            "{}{}{}",
                            if c.quoted { "q" } else { "" },
                            if c.highlighted { "h" } else { "" },
                            if c.next { "n" } else { "" }
                        );
                        format!("{}/{flags}", c.text)
                    })
                    .collect();
                got.extend(["|".to_string(), s.correction().unwrap_or("-").to_string(), "|".to_string()]);
                let bar = want.iter().rposition(|x| x == "|").unwrap();
                if got != want[..=bar] {
                    // ô "từ tiếp theo" hay "cách gõ tiếp" có thể đổi chỗ khi hai từ gần bằng điểm: xem kết quả từng
                    // dòng next/comp; ở đây phải giống hệt
                    Err(format!("want {:?}, got {got:?}", &want[..=bar]))
                } else {
                    let w = &want[bar + 1..];
                    match s.touch_odds() {
                        None if w == ["-"] => Ok(Kind::Exact),
                        Some((o, v)) if w.len() == 28 && w[0] == if v { "vi" } else { "en" } => floats(&w[1..], o),
                        o => Err(format!("odds: want {w:?}, got {o:?}")),
                    }
                }
            }
            op => panic!("unknown golden op {op}"),
        };
        t.line(r, &what);
    }
    println!(
        "suggest: {} lines checked: {} exact, {} within 1e-4, {} near-ties reordered, {} mismatches",
        t.lines,
        t.exact,
        t.tolerance,
        t.ties,
        t.bad.len()
    );
    WORST.with(|w| {
        let w: Vec<String> = w.borrow().iter().map(|(op, x)| format!("{op} {x:.1e}")).collect();
        println!("suggest: largest relative difference by line kind: {}", w.join(", "));
    });
    for b in t.bad.iter().take(20) {
        println!("  {b}");
    }
    assert!(t.bad.is_empty(), "{} of {} lines differ from Swift", t.bad.len(), t.lines);
}

// MARK: hành vi đã kiểm tra trên máy ảo iOS (bàn phím 402 pt)

/// Phím chữ i của một hàng có tâm x = 3,7 + 39,46·(i + 0,5) (hàng 2 lùi nửa phím, hàng 3 một phím rưỡi), ô vẽ rộng
/// 33,46, cao 43, các hàng cách 54 (tâm y 615, 669, 723); phím cách 102,4…299,7 ở hàng dưới (tâm 777).
fn phone_keys() -> (Vec<TouchKey>, impl Fn(char) -> (f64, f64)) {
    let rows = [("qwertyuiop", 0.0), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)];
    let mut keys = vec![];
    for (r, (letters, off)) in rows.iter().enumerate() {
        let y = 615.0 + 54.0 * r as f64;
        if r == 2 {
            keys.push(TouchKey { index: 19, kind: TapKind::Shift, row: 2, x: 6.7, y: y - 21.5, w: 47.19, h: 43.0 });
        }
        for (i, ch) in letters.bytes().enumerate() {
            let cx = 3.7 + 39.46 * (off + i as f64 + 0.5);
            keys.push(TouchKey {
                index: keys.len(),
                kind: TapKind::Letter(ch - b'a'),
                row: r as i32,
                x: cx - 16.73,
                y: y - 21.5,
                w: 33.46,
                h: 43.0,
            });
        }
        if r == 2 {
            keys.push(TouchKey {
                index: 27,
                kind: TapKind::Backspace,
                row: 2,
                x: 348.11,
                y: y - 21.5,
                w: 47.19,
                h: 43.0,
            });
        }
    }
    keys.push(TouchKey { index: 29, kind: TapKind::Space, row: 3, x: 102.4, y: 755.5, w: 197.3, h: 43.0 });
    let k2 = keys.clone();
    let centre = move |c: char| {
        let k = k2.iter().find(|k| k.kind == TapKind::Letter(c as u8 - b'a')).unwrap();
        (k.mid_x(), k.mid_y())
    };
    (keys, centre)
}

fn index_of(keys: &[TouchKey], c: char) -> usize {
    keys.iter().find(|k| k.kind == TapKind::Letter(c as u8 - b'a')).unwrap().index
}

/// Gõ `word` đúng tâm phím sau `before` (đã có trong ô) rồi tính lại.
fn type_word(s: &mut Suggester, centre: &impl Fn(char) -> (f64, f64), before: &str, word: &str) -> Vec<String> {
    s.end_word();
    let mut ctx = before.to_string();
    let mut cells = vec![];
    for c in word.chars() {
        let (x, y) = centre(c);
        s.letter(c, x as f32, y as f32);
        ctx.push(c);
        cells = s.update(&ctx, true, "", false).into_iter().map(|c| c.text).collect();
    }
    cells
}

#[test]
fn simulator_behaviours() {
    let Some(dir) = models_dir() else { return };
    let mut s = suggester(dir);
    let (keys, centre) = phone_keys();
    s.set_keys(keys.clone());
    let (u, i, n) = (index_of(&keys, 'u'), index_of(&keys, 'i'), index_of(&keys, 'n'));
    // ranh giới ô của u và i (giữa hai ô, gồm khe): x = 3,7 + 39,46·7 = 279,92; "bên trong u" tính từ đó, như trên máy ảo
    let border = 3.7 + 39.46 * 7.0;

    // "I want to th": ô "th", think, throw
    let cells = s.update("I want to th", true, "", false);
    let texts: Vec<&str> = cells.iter().map(|c| c.text.as_str()).collect();
    assert_eq!(texts, ["th", "think", "throw"]);
    assert!(cells[0].quoted && !cells[1].highlighted && !cells[1].next);
    // chạm 2 pt bên trong u, phía i: là i
    assert_eq!(s.touch_pick(border - 2.0, 615.0, u), i);
    // phím cũ (chưa tính lại sau phím): phím ở chỗ chạm
    s.invalidate();
    assert_eq!(s.touch_pick(border - 2.0, 615.0, u), u);

    // khe giữa n và phím cách: sau "thank" là dấu cách, sau "tha" là n
    let gap = (keys[n].mid_x(), 748.0);
    s.update("I want to thank", true, "", false);
    assert_eq!(s.touch_pick(gap.0, gap.1, n), 29);
    s.update("I want to tha", true, "", false);
    assert_eq!(s.touch_pick(gap.0, gap.1, n), n);
    // không có xác suất (tự sửa tắt thì cũng không có luật khe): phím ở chỗ chạm
    s.auto_correct_on = false;
    s.update("I want to thank", true, "", false);
    assert_eq!(s.touch_pick(gap.0, gap.1, n), n);
    s.auto_correct_on = true;

    // "rhonk" lệch về t và i (x 158 và 323 ở hàng trên): sửa thành think; chạm đúng tâm: không sửa
    s.end_word();
    let mut ctx = "I want to ".to_string();
    for c in "rhonk".chars() {
        let (x, y) = match c {
            'r' => (158.0, 615.0),
            'o' => (323.0, 615.0),
            c => centre(c),
        };
        s.letter(c, x as f32, y as f32);
        ctx.push(c);
        s.update(&ctx, true, "", false);
    }
    assert_eq!(s.correction(), Some("think"));
    let cells = s.update(&ctx, true, "", false);
    assert!(cells.iter().any(|c| c.text == "think" && c.highlighted));
    type_word(&mut s, &centre, "I want to ", "rhonk");
    assert_eq!(s.correction(), None);

    // tiếng Việt, phím Telex "th": sau "kỳ " chạm ở x 279,5 (trong u) là i (thi); sau "mùa " chạm ở 280,3 (trong i) là
    // u (thu); không có mô hình thì ngược lại
    s.end_word();
    s.update("kỳ th", false, "th", false);
    assert!(s.touch_odds().is_some_and(|(_, vi)| vi));
    assert_eq!(s.touch_pick(border - 0.4, 615.0, u), i);
    s.update("mùa th", false, "th", false);
    assert_eq!(s.touch_pick(border + 0.4, 615.0, i), u);
    s.end_word();
    assert_eq!(s.touch_pick(border + 0.4, 615.0, i), i);

    // không bao giờ đợi: sau cool_down như không có mô hình, warm lại thì có
    s.models().cool_down();
    assert!(s.update("I want to th", true, "", false).len() == 1 && s.touch_odds().is_none());
    s.models().warm(true);
    assert_eq!(s.update("I want to th", true, "", false).len(), 3);
}

/// Luật khe trên phím cách khi không có xác suất phím (không từ nào của mô hình bắt đầu như từ đang gõ) mà lõi biết
/// từ đó: chạm vào khe dưới chữ cuối của từ, trên phím cách, là dấu cách.
#[test]
fn gap_rule_without_odds() {
    let Some(dir) = models_dir() else { return };
    let models = Models::open(dir, resources());
    models.warm(false);
    let mut s = Suggester::new(models, Box::new(|w| w == "vipix"));
    let (keys, _) = phone_keys();
    s.set_keys(keys.clone());
    let (n, h, z) = (index_of(&keys, 'n'), index_of(&keys, 'h'), index_of(&keys, 'z'));
    s.update("I want to vipix", true, "", false);
    assert!(s.touch_odds().is_none());
    assert_eq!(s.touch_pick(keys[n].mid_x(), 748.0, n), 29, "khe dưới n, trên phím cách");
    assert_eq!(s.touch_pick(keys[z].mid_x(), 748.0, z), z, "ngoài phím cách (x < 102,4)");
    assert_eq!(s.touch_pick(keys[h].mid_x(), keys[h].max_y() + 2.0, h), h, "hàng 2 không ngay trên phím cách");
    assert_eq!(s.touch_pick(keys[n].mid_x(), keys[n].mid_y(), n), n, "trong phím");
    s.update("I want to vipi", true, "", false);
    assert_eq!(s.touch_pick(keys[n].mid_x(), 748.0, n), n, "lõi không biết vipi");
}

#[test]
fn update_does_not_wait_for_warm() {
    let Some(dir) = models_dir() else { return };
    let models = Models::open(dir, resources());
    let mut s = Suggester::new(Arc::clone(&models), Box::new(|_| false));
    let warm = {
        let m = Arc::clone(&models);
        std::thread::spawn(move || m.warm(false))
    };
    // trong lúc làm nóng: mỗi lần update trả về ngay (chưa sẵn sàng thì như không có mô hình)
    let mut slowest = 0f64;
    while !warm.is_finished() {
        let t = Instant::now();
        let cells = s.update("I want to th", true, "", false);
        slowest = slowest.max(t.elapsed().as_secs_f64());
        assert!(cells.len() == 1 || cells.len() == 3);
    }
    warm.join().unwrap();
    assert_eq!(s.update("I want to th", true, "", false).len(), 3);
    println!("slowest update while warming: {:.0} µs", slowest * 1e6);
}

/// Thời gian (release, sau khi làm nóng): cargo test --release --test suggest -- --ignored --nocapture
#[test]
#[ignore]
fn timings() {
    let Some(dir) = models_dir() else { return };
    let mut s = suggester(dir);
    let (keys, centre) = phone_keys();
    s.set_keys(keys.clone());
    let time = |name: &str, n: usize, f: &mut dyn FnMut(usize)| {
        f(0);
        let t = Instant::now();
        for k in 0..n {
            f(k);
        }
        println!("{name}: {:.1} µs", t.elapsed().as_secs_f64() * 1e6 / n as f64);
    };
    let sentence = "I want to think about this before we decide what to do with the old house";
    // giữa từ, tiếng Anh: chữ trước từ không đổi (mạng đã đọc nó), mỗi phím một update
    let mids: Vec<String> = ["I want to t", "I want to th", "I want to thi", "I want to thin", "I want to think"]
        .iter()
        .chain(&["Thank you so much for y", "Thank you so much for yo", "Thank you so much for you"])
        .map(|x| x.to_string())
        .collect();
    let mut k = 0usize;
    time("update, English mid-word (same text before the word)", 2000, &mut |_| {
        // các phím của một từ liền nhau: đổi câu chỉ khi sang từ khác
        k += 1;
        let c = if (k / 200).is_multiple_of(2) { &mids[k % 5] } else { &mids[5 + k % 3] };
        s.update(c, true, "", false);
    });
    let words: Vec<&str> = sentence.split(' ').collect();
    let mut s2 = suggester(models_dir().unwrap());
    s2.set_keys(keys.clone());
    let mut text = String::new();
    let mut n = 0usize;
    time("update, English, first key of a new word (one network step)", 300, &mut |_| {
        text.push_str(words[n % words.len()]);
        text.push(' ');
        n += 1;
        s2.update(&format!("{text}t"), true, "", false);
    });
    time("update, English, cold network (text changed, ~20 words)", 50, &mut |j| {
        s2.update(&format!("{} {sentence} t", j % 7), true, "", false);
    });
    let vi = [
        ("Hôm nay trời ", "dd", "đ"),
        ("Hôm nay trời ", "ddej", "đẹ"),
        ("tôi muốn ", "nguowf", "ngườ"),
        ("kỳ ", "th", "th"),
    ];
    for (b, k, w) in vi {
        s.update(&format!("{b}{w}"), false, k, false);
    }
    time("update, Vietnamese mid-word", 2000, &mut |j| {
        let (b, k, w) = vi[(j / 200) % vi.len()];
        s.update(&format!("{b}{w}"), false, k, false);
    });
    let nexts = ["I want to ", "Thank you so much for ", "Hôm nay trời "];
    time("update, next words (text already read by the network)", 600, &mut |j| {
        let b = nexts[(j / 200) % 3];
        s.update(b, !b.starts_with('H'), "", false);
    });
    let mut text = String::new();
    let mut n = 0usize;
    time("update, next words after a new word (one network step)", 300, &mut |_| {
        text.push_str(words[n % words.len()]);
        text.push(' ');
        n += 1;
        s2.update(&text, true, "", false);
    });
    s.update("I want to th", true, "", false);
    let u = index_of(&keys, 'u');
    let (ux, uy) = centre('u');
    time("touch_pick (English odds, near a border)", 100_000, &mut |j| {
        std::hint::black_box(s.touch_pick(ux + 14.0 + (j % 5) as f64 * 0.3, uy, u));
    });
    // tự sửa: "rhonk" lệch phím (đọc lại các lần chạm)
    time("update with slip correction (rhonk)", 500, &mut |_| {
        s.end_word();
        for (c, x) in [('r', 158.0), ('h', centre('h').0), ('o', 323.0), ('n', centre('n').0), ('k', centre('k').0)] {
            s.letter(c, x as f32, if "ro".contains(c) { 615.0 } else { centre(c).1 as f32 });
        }
        s.update("I want to rhonk", true, "", false);
    });
}
