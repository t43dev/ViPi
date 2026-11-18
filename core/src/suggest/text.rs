//! Chuỗi theo cách Swift thấy, để lõi ra đúng các số của bản iOS: đếm và cắt theo cụm ký tự (Character của
//! Swift: chữ cùng các dấu đi theo, emoji ghép), "chữ cái" là ký tự đầu của cụm có thuộc tính Alphabetic,
//! viết thường từng ký tự, và dạng chuẩn NFC/NFD cho chữ Latin.
//!
//! Gần đúng, khác Swift ở chỗ ít gặp: tách cụm theo một phần của UAX #29 (dấu, ZWJ + emoji, cặp cờ, CR LF; không có
//! Hangul jamo, SpacingMark, Prepend); NFC/NFD chỉ cho chữ Latin dựng sẵn (U+00C0–024F, U+1E00–1EFF); so sánh chuỗi
//! theo byte, không theo tương đương chính tắc.

use std::collections::HashMap;
use std::sync::OnceLock;

use super::unicode_tables::{CCC, LATIN, MN};

/// Dấu không chiếm chỗ (Mn).
pub(crate) fn is_mn(c: char) -> bool {
    let v = c as u32;
    MN.binary_search_by(|&(a, b)| {
        if b < v {
            std::cmp::Ordering::Less
        } else if a > v {
            std::cmp::Ordering::Greater
        } else {
            std::cmp::Ordering::Equal
        }
    })
    .is_ok()
}

/// Ký tự dính vào cụm trước nó (Grapheme_Cluster_Break = Extend, gần đúng).
fn is_extend(c: char) -> bool {
    let v = c as u32;
    is_mn(c)
        || v == 0x200D
        || (0x20DD..=0x20E4).contains(&v)
        || (0xFE00..=0xFE0F).contains(&v)
        || (0x1F3FB..=0x1F3FF).contains(&v)
        || (0xE0020..=0xE007F).contains(&v)
        || (0xE0100..=0xE01EF).contains(&v)
}

/// Emoji có thể đứng sau ZWJ trong một cụm (Extended_Pictographic, gần đúng).
fn is_pictographic(c: char) -> bool {
    let v = c as u32;
    matches!(v, 0xA9 | 0xAE | 0x203C | 0x2049 | 0x2122 | 0x2139 | 0x24C2 | 0x3030 | 0x303D | 0x3297 | 0x3299)
        || (0x2194..=0x21AA).contains(&v)
        || (0x231A..=0x23FF).contains(&v)
        || (0x25AA..=0x25FE).contains(&v)
        || (0x2600..=0x27BF).contains(&v)
        || (0x2934..=0x2935).contains(&v)
        || (0x2B05..=0x2B55).contains(&v)
        || (0x1F000..=0x1FFFF).contains(&v)
}

fn is_regional(c: char) -> bool {
    (0x1F1E6..=0x1F1FF).contains(&(c as u32))
}

/// Vị trí byte bắt đầu của từng cụm.
pub(crate) fn starts(s: &str) -> Vec<usize> {
    let mut out = Vec::with_capacity(s.len());
    let mut prev: Option<char> = None;
    let mut regional = 0; // số chỉ báo vùng liền nhau trong cụm đang xét
    let mut zwj_after_pict = false; // cụm đang xét: emoji rồi ZWJ ở cuối
    let mut pict = false;
    for (i, c) in s.char_indices() {
        let joins = match prev {
            None => false,
            Some('\r') => c == '\n',
            Some(p) if p.is_control() || p == '\n' => false,
            Some(_) if c.is_control() => false,
            Some(_) if is_extend(c) => true,
            Some(_) if zwj_after_pict && is_pictographic(c) => true,
            Some(p) if is_regional(p) && is_regional(c) => regional % 2 == 1,
            Some(_) => false,
        };
        if !joins {
            out.push(i);
            regional = 0;
            pict = false;
        }
        if is_regional(c) {
            regional += 1;
        }
        if is_pictographic(c) {
            pict = true;
        }
        zwj_after_pict = c == '\u{200D}' && pict;
        prev = Some(c);
    }
    out
}

/// Số cụm ký tự (String.count của Swift).
pub(crate) fn count(s: &str) -> usize {
    starts(s).len()
}

/// `n` cụm cuối (suffix của Swift).
pub(crate) fn suffix(s: &str, n: usize) -> &str {
    let st = starts(s);
    if n >= st.len() {
        s
    } else if n == 0 {
        ""
    } else {
        &s[st[st.len() - n]..]
    }
}

/// Bỏ `n` cụm cuối (dropLast của Swift).
pub(crate) fn drop_last(s: &str, n: usize) -> &str {
    let st = starts(s);
    if n >= st.len() {
        ""
    } else if n == 0 {
        s
    } else {
        &s[..st[st.len() - n]]
    }
}

/// Cụm cuối.
pub(crate) fn last(s: &str) -> Option<&str> {
    starts(s).last().map(|&i| &s[i..])
}

/// Cụm đầu.
pub(crate) fn first(s: &str) -> Option<&str> {
    let st = starts(s);
    st.first().map(|_| &s[..st.get(1).copied().unwrap_or(s.len())])
}

/// Các cụm theo thứ tự.
pub(crate) fn clusters(s: &str) -> Vec<&str> {
    let st = starts(s);
    st.iter().enumerate().map(|(k, &i)| &s[i..st.get(k + 1).copied().unwrap_or(s.len())]).collect()
}

/// Character.isLetter: ký tự đầu của cụm là Alphabetic.
pub(crate) fn is_letter(cluster: &str) -> bool {
    cluster.chars().next().is_some_and(char::is_alphabetic)
}

/// Character.isASCII (CR LF cũng tính).
pub(crate) fn is_ascii(cluster: &str) -> bool {
    cluster == "\r\n" || (cluster.len() == 1 && cluster.as_bytes()[0] < 0x80)
}

/// Character.isWhitespace.
pub(crate) fn is_whitespace(cluster: &str) -> bool {
    cluster.chars().next().is_some_and(char::is_whitespace)
}

/// Character.isUppercase: có thuộc tính Uppercase, hoặc viết hoa không đổi mà là chữ có hoa thường.
pub(crate) fn is_uppercase(cluster: &str) -> bool {
    let mut cs = cluster.chars();
    if let (Some(c), None) = (cs.next(), cs.clone().next()) {
        if c.is_uppercase() {
            return true;
        }
    }
    let up = upper(cluster);
    up == cluster && (cluster.chars().any(char::is_lowercase) || lower(cluster) != cluster)
}

/// lowercased() của Swift: từng ký tự, không theo ngữ cảnh (Σ cuối từ vẫn là σ).
pub(crate) fn lower(s: &str) -> String {
    if s.is_ascii() {
        return s.to_ascii_lowercase();
    }
    s.chars().flat_map(char::to_lowercase).collect()
}

pub(crate) fn upper(s: &str) -> String {
    if s.is_ascii() {
        return s.to_ascii_uppercase();
    }
    s.chars().flat_map(char::to_uppercase).collect()
}

/// `s` có bắt đầu bằng `p` theo cụm ký tự không (hasPrefix): byte giống và chỗ cắt là ranh giới cụm.
pub(crate) fn has_prefix(s: &str, p: &str) -> bool {
    s.starts_with(p) && (s.len() == p.len() || p.is_empty() || !s[p.len()..].chars().next().is_some_and(is_extend))
}

// MARK: dạng chuẩn

fn ccc(c: char) -> u8 {
    let v = c as u32;
    match CCC.binary_search_by_key(&v, |&(m, _)| m) {
        Ok(i) => CCC[i].1,
        Err(_) if is_mn(c) => 230,
        Err(_) => 0,
    }
}

fn decompose_into(c: char, out: &mut Vec<char>) {
    match LATIN.binary_search_by_key(&(c as u32), |&(p, _, _)| p) {
        Ok(i) => {
            let (_, base, mark) = LATIN[i];
            decompose_into(char::from_u32(base).unwrap_or(c), out);
            out.push(char::from_u32(mark).unwrap_or(c));
        }
        Err(_) => out.push(c),
    }
}

/// NFD (chữ Latin dựng sẵn được tách; dấu xếp theo lớp kết hợp).
pub(crate) fn nfd(s: &str) -> Vec<char> {
    let mut out = Vec::with_capacity(s.len());
    for c in s.chars() {
        decompose_into(c, &mut out);
    }
    // xếp lại từng đoạn dấu (ổn định, theo lớp kết hợp)
    let mut i = 0;
    while i < out.len() {
        if ccc(out[i]) == 0 {
            i += 1;
            continue;
        }
        let start = i;
        while i < out.len() && ccc(out[i]) != 0 {
            i += 1;
        }
        out[start..i].sort_by_key(|&c| ccc(c));
    }
    out
}

fn compositions() -> &'static HashMap<(u32, u32), u32> {
    static MAP: OnceLock<HashMap<(u32, u32), u32>> = OnceLock::new();
    MAP.get_or_init(|| LATIN.iter().map(|&(p, b, m)| ((b, m), p)).collect())
}

/// NFC (precomposedStringWithCanonicalMapping), cho chữ Latin.
pub(crate) fn nfc(s: &str) -> String {
    if s.is_ascii() {
        return s.to_string();
    }
    let d = nfd(s);
    let map = compositions();
    let mut out: Vec<char> = Vec::with_capacity(d.len());
    let mut starter: Option<usize> = None;
    let mut last_ccc: i32 = -1; // lớp của ký tự cuối sau starter (-1: liền sau starter)
    for c in d {
        let k = ccc(c) as i32;
        if let Some(si) = starter {
            let blocked = last_ccc != -1 && (last_ccc == 0 || last_ccc >= k);
            if !blocked {
                if let Some(&p) = map.get(&(out[si] as u32, c as u32)) {
                    out[si] = char::from_u32(p).unwrap_or(out[si]);
                    continue;
                }
            }
        }
        if k == 0 {
            starter = Some(out.len());
            last_ccc = -1;
        } else {
            last_ccc = k;
        }
        out.push(c);
    }
    out.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clusters_like_swift() {
        // cùng các mẫu đã hỏi Swift trên Mac
        let probes: [(&str, &[&str]); 9] = [
            ("e\u{301}x", &["e\u{301}", "x"]),
            ("👍🏽a", &["👍🏽", "a"]),
            ("👨\u{200D}👩\u{200D}👧b", &["👨\u{200D}👩\u{200D}👧", "b"]),
            ("🇻🇳c", &["🇻🇳", "c"]),
            ("a\r\nb", &["a", "\r\n", "b"]),
            ("\u{301}a", &["\u{301}", "a"]),
            (" \u{301}a", &[" \u{301}", "a"]),
            ("x\u{200D}y", &["x\u{200D}", "y"]),
            ("a\u{FE0F}b", &["a\u{FE0F}", "b"]),
        ];
        for (s, want) in probes {
            assert_eq!(clusters(s), want, "{s:?}");
        }
        assert_eq!(count("🇻🇳🇺🇸"), 2);
        assert_eq!(suffix("ab👍🏽", 1), "👍🏽");
        assert_eq!(drop_last("tiê\u{301}ng", 2), "tiê\u{301}");
    }

    #[test]
    fn normal_forms() {
        assert_eq!(nfc("e\u{302}\u{323}"), "ệ");
        assert_eq!(nfc("e\u{323}\u{302}"), "ệ");
        assert_eq!(nfc("u\u{31B}\u{301}"), "ứ");
        assert_eq!(nfc("Ư\u{300}"), "Ừ");
        assert_eq!(nfc("a\u{306}\u{309}"), "ẳ");
        assert_eq!(nfc("o\u{301}\u{31B}"), "ớ");
        assert_eq!(nfd("người"), vec!['n', 'g', 'u', '\u{31B}', 'o', '\u{31B}', '\u{300}', 'i']);
        assert_eq!(nfd("ệ"), vec!['e', '\u{323}', '\u{302}']);
    }

    #[test]
    fn letters_and_case() {
        assert!(is_letter("ệ") && is_letter("e\u{301}") && !is_letter("1") && !is_letter("'"));
        assert!(is_uppercase("T") && !is_uppercase("t") && is_uppercase("ĸ") && !is_uppercase("1"));
        assert_eq!(lower("ΣΑΣ"), "σασ");
    }
}
