//! Phím nào được gõ khi một từ đang gõ dở, theo Vikey (github.com/tonyminibot/Vikey, GPL-3.0, D65 và D66,
//! iOS/Keyboard/TapModel.swift; bản ViPi: ios/ViPiKeyboard/Suggest/TapModel.swift; các hệ số do Vikey đo: tiếng Anh
//! khớp trên bàn phím của Apple, tiếng Việt trên bộ gõ thử của chính họ). Mỗi phím gần chỗ chạm được chấm điểm: chạm
//! gần tâm phím tới đâu (Gauss quanh phím) cộng với phím đó có hay là phím kế tiếp không (`next_letters` /
//! `next_keys`; với phím cách là khả năng từ kết thúc). Chạm vào phần giữa của một phím thì luôn là phím đó.

/// Các hệ số của mô hình chạm.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TapParams {
    /// độ tản, theo bề rộng phím chữ / chiều cao phím
    pub sigma_x: f64,
    pub sigma_y: f64,
    /// xác suất phím kế tiếp nặng tới đâu
    pub weight: f64,
    pub floor: f64,
    pub space_floor: f64,
    pub delete: f64,
    pub shift: f64,
    /// trong phần này của phím (tính từ tâm) thì phím đó thắng luôn
    pub sure: f64,
    /// chỗ chạm được tính cao hơn một chút, theo chiều cao phím
    pub offset_y: f64,
}

pub const ENGLISH: TapParams = TapParams {
    sigma_x: 0.3,
    sigma_y: 0.25,
    weight: 0.6,
    floor: 0.001,
    space_floor: 0.001,
    delete: 0.03,
    shift: 0.001,
    sure: 0.7,
    offset_y: -0.05,
};

pub const VIETNAMESE: TapParams = TapParams { weight: 0.8, sure: 0.5, ..ENGLISH };

/// Loại phím tham gia: chữ (0…25 = a…z), cách, xoá, Shift.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TapKind {
    Letter(u8),
    Space,
    Backspace,
    Shift,
}

/// Một phím tham gia: chỉ số của nó trong mảng phím của bàn phím, loại, hàng, và ô vẽ (không gồm khe giữa các phím).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TouchKey {
    pub index: usize,
    pub kind: TapKind,
    pub row: i32,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl TouchKey {
    pub fn mid_x(&self) -> f64 {
        self.x + self.w / 2.0
    }

    pub fn mid_y(&self) -> f64 {
        self.y + self.h / 2.0
    }

    pub fn max_x(&self) -> f64 {
        self.x + self.w
    }

    pub fn max_y(&self) -> f64 {
        self.y + self.h
    }
}

/// Phím được chọn cho lần chạm (x, y). `odds`: 27 số (a…z rồi "từ kết thúc"). None khi không có phím chữ nào.
pub fn pick(x: f64, y: f64, keys: &[TouchKey], odds: &[f64], m: &TapParams) -> Option<usize> {
    if odds.len() != 27 {
        return None;
    }
    let letter_w = keys.iter().find(|k| matches!(k.kind, TapKind::Letter(_)))?.w;
    if letter_w <= 0.0 {
        return None;
    }
    for k in keys {
        let rx = (x - k.mid_x()).abs() / (k.w / 2.0);
        let ry = (y - k.mid_y()).abs() / (k.h / 2.0);
        if rx.max(ry) <= m.sure {
            return Some(k.index);
        }
    }
    let mut best: Option<(f64, usize)> = None;
    for k in keys {
        // phím rộng (cách, xoá, Shift) là một phím chữ có phần giữa dài hơn
        let half_extra = (k.w - letter_w).max(0.0) / 2.0 / letter_w;
        let dx = (((x - k.mid_x()) / letter_w).abs() - half_extra).max(0.0) / m.sigma_x;
        let dy = ((y - k.mid_y()) / k.h + m.offset_y) / m.sigma_y;
        let prior = match k.kind {
            TapKind::Letter(i) => (1.0 - m.floor) * odds[i.min(25) as usize] + m.floor / 26.0,
            TapKind::Space => odds[26] + m.space_floor,
            TapKind::Backspace => m.delete,
            TapKind::Shift => m.shift,
        };
        let s = -0.5 * (dx * dx + dy * dy) + m.weight * prior.ln();
        if best.is_none_or(|b| s > b.0) {
            best = Some((s, k.index));
        }
    }
    best.map(|b| b.1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn letter(index: usize, l: u8, x: f64) -> TouchKey {
        TouchKey { index, kind: TapKind::Letter(l), row: 0, x, y: 0.0, w: 30.0, h: 40.0 }
    }

    #[test]
    fn centre_always_wins_and_odds_move_the_border() {
        let keys = [letter(0, 0, 0.0), letter(1, 1, 36.0)]; // a: 0…30, b: 36…66, khe 30…36
        let mut odds = vec![0.0; 27];
        odds[1] = 1.0; // chỉ b đi tiếp
                       // phần giữa của a: a dù b chắc chắn hơn
        assert_eq!(pick(15.0 + 0.69 * 15.0, 20.0, &keys, &odds, &ENGLISH), Some(0));
        // mép phải của a, ngoài phần giữa: b thắng nhờ xác suất
        assert_eq!(pick(29.0, 20.0, &keys, &odds, &ENGLISH), Some(1));
        // xác suất ngược lại: a
        odds[1] = 0.0;
        odds[0] = 1.0;
        assert_eq!(pick(37.0, 20.0, &keys, &odds, &ENGLISH), Some(0));
        // không có phím chữ, hay xác suất không đủ 27 số
        assert_eq!(pick(29.0, 20.0, &keys, &odds[..26], &ENGLISH), None);
        let space = [TouchKey { index: 5, kind: TapKind::Space, row: 1, x: 0.0, y: 50.0, w: 200.0, h: 40.0 }];
        assert_eq!(pick(10.0, 60.0, &space, &odds, &ENGLISH), None);
    }

    #[test]
    fn score_matches_the_formula() {
        // một phím chữ và phím cách rộng: điểm của từng phím theo đúng công thức của TapModel.swift
        let keys = [
            letter(0, 13, 0.0),
            TouchKey { index: 1, kind: TapKind::Space, row: 1, x: -60.0, y: 50.0, w: 150.0, h: 40.0 },
        ];
        let mut odds = vec![0.0; 27];
        odds[13] = 0.3;
        odds[26] = 0.7;
        let (x, y) = (15.0, 47.0);
        let m = ENGLISH;
        let score = |k: &TouchKey, prior: f64| {
            let half = (k.w - 30.0).max(0.0) / 2.0 / 30.0;
            let dx = (((x - k.mid_x()) / 30.0).abs() - half).max(0.0) / m.sigma_x;
            let dy = ((y - k.mid_y()) / k.h + m.offset_y) / m.sigma_y;
            -0.5 * (dx * dx + dy * dy) + m.weight * prior.ln()
        };
        let a = score(&keys[0], 0.999 * 0.3 + 0.001 / 26.0);
        let s = score(&keys[1], 0.7 + 0.001);
        assert_eq!(pick(x, y, &keys, &odds, &m), Some(if s > a { 1 } else { 0 }));
        assert!(s > a, "dưới phím chữ, gần phím cách, từ có thể kết thúc: phím cách");
    }
}
