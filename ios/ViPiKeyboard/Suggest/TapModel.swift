import UIKit

/// Phím nào được gõ khi một từ đang gõ dở, theo cách của Vikey (github.com/tonyminibot/Vikey, GPL-3.0, D65 và D66,
/// iOS/Keyboard/TapModel.swift; các hệ số do Vikey đo: tiếng Anh khớp trên bàn phím của Apple, tiếng Việt trên bộ gõ
/// thử của chính họ). Mỗi phím gần chỗ chạm được chấm điểm: chạm gần tâm phím tới đâu (Gauss quanh phím) cộng với
/// phím đó có hay là phím kế tiếp không (SuggestLM.nextLetters / nextKeys; với phím cách là khả năng từ kết thúc).
/// Chạm vào phần giữa của một phím thì luôn là phím đó.
enum TapModel {
    struct Params {
        var sigmaX = 0.3, sigmaY = 0.25   // độ tản, theo bề rộng phím chữ / chiều cao phím
        var weight = 0.6                  // xác suất phím kế tiếp nặng tới đâu
        var floor = 0.001, spaceFloor = 0.001, delete = 0.03, shift = 0.001
        var sure = 0.7                    // trong phần này của phím (tính từ tâm) thì phím đó thắng luôn
        var offsetY = -0.05               // chỗ chạm được tính cao hơn một chút, theo chiều cao phím
    }
    static let english = Params()
    static let vietnamese = Params(weight: 0.8, sure: 0.5)

    enum Kind: Equatable { case letter(Int), space, backspace, shift }   // letter: 0…25 = a…z

    /// `keys`: các phím tham gia (chỉ số, loại, ô vẽ của phím). `odds`: 27 giá trị (a…z rồi "từ kết thúc").
    /// Trả về chỉ số phím được chọn, nil khi không có phím chữ nào.
    static func pick(_ p: CGPoint, keys: [(index: Int, kind: Kind, frame: CGRect)], odds: [Double], _ m: Params) -> Int? {
        guard odds.count == 27,
              let letterW = keys.first(where: { if case .letter = $0.kind { return true }; return false })?.frame.width, letterW > 0 else { return nil }
        for k in keys {
            let rx = abs(Double(p.x - k.frame.midX)) / Double(k.frame.width / 2), ry = abs(Double(p.y - k.frame.midY)) / Double(k.frame.height / 2)
            if max(rx, ry) <= m.sure { return k.index }
        }
        var best: (score: Double, index: Int)?
        for k in keys {
            let f = k.frame
            // phím rộng (cách, xoá, Shift) là một phím chữ có phần giữa dài hơn
            let halfExtra = Double(max(f.width - letterW, 0) / 2 / letterW)
            let dx = max(abs(Double(p.x - f.midX) / Double(letterW)) - halfExtra, 0) / m.sigmaX
            let dy = (Double(p.y - f.midY) / Double(f.height) + m.offsetY) / m.sigmaY
            let prior: Double
            switch k.kind {
            case .letter(let i): prior = (1 - m.floor) * odds[i] + m.floor / 26
            case .space: prior = odds[26] + m.spaceFloor
            case .backspace: prior = m.delete
            case .shift: prior = m.shift
            }
            let s = -0.5 * (dx * dx + dy * dy) + m.weight * log(prior)
            if best == nil || s > best!.score { best = (s, k.index) }
        }
        return best?.index
    }
}
