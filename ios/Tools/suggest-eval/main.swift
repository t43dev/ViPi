import Foundation

// Mô phỏng gõ chạm trên bàn chữ điện thoại của ViPi (iPhone 402 pt): mỗi chữ là một lần chạm lệch ngẫu nhiên quanh
// tâm phím, chữ được gõ là phím ở chỗ chạm. Đo việc tự sửa lỗi chạm (Suggester.slipFix) với vài mức ngưỡng: trên
// chữ chat không có trong danh sách nào (chat.txt: gõ đúng mà bị đổi là sửa nhầm) và trên câu tiếng Anh (sentences.txt).
// Chạy trên Mac, trong một thư mục có 4 file mô hình (scripts/ios-suggest-models.sh), keep-words.txt, chat.txt,
// sentences.txt và known.txt (các từ lõi đã biết, có thể để trống):
//   swiftc -O main.swift ../../ViPiKeyboard/Suggest/{SuggestLM,SuggestNN,KeyRect}.swift -o suggest-eval
//   ./suggest-eval <thư mục> [độ lệch chạm tính bằng pt, mặc định 8]
// Kết quả 2026-11-18 (8 pt): như Vikey 4,61% chữ chat bị đổi, 66/70 từ tiếng Anh gõ lệch được sửa đúng; ngưỡng -9 và
// kiểm tra dạng chữ (đang dùng): 0,16% và 61/70; ngưỡng -7: 0,04% và 41/70. Không lần nào sửa sai từ tiếng Anh.
struct Rng { var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func gauss() -> Double { let u = max(unit(), 1e-12), v = unit(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
}
let unit = 39.46, side = 3.7, gapX = 6.0, gapY = 11.0, rowH = 54.0
let rows: [(String, Double)] = [("qwertyuiop", 0), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)]
var rects: [KeyRect] = [], centre: [Character: (Double, Double)] = [:], frames: [(Character, Int, Double, Double)] = []
for (r, (letters, off)) in rows.enumerated() {
    for (i, ch) in letters.enumerated() {
        let x0 = side + (off + Double(i)) * unit, y0 = Double(r) * rowH
        rects.append(KeyRect(x: Float(x0 + gapX / 2), y: Float(y0 + gapY / 2), w: Float(unit - gapX), h: Float(rowH - gapY), letter: CChar(ch.asciiValue!)))
        centre[ch] = (x0 + unit / 2, y0 + rowH / 2)
        frames.append((ch, r, x0, x0 + unit))
    }
}
func keyAt(_ x: Double, _ y: Double) -> Character {
    let r = min(max(Int(y / rowH), 0), 2)
    var best: Character = " ", bd = Double.greatestFiniteMagnitude
    for (ch, row, a, b) in frames where row == r {
        if x >= a && x < b { return ch }
        let d = abs((a + b) / 2 - x); if d < bd { bd = d; best = ch }
    }
    return best
}
let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1])
func lines(_ name: String) -> [String] { ((try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
let sigma = Double(args.count > 2 ? args[2] : "8") ?? 8
SuggestLM.warmUpNow()
let lm = SuggestLM.shared
precondition(!lm.isEmpty, "no model")
let known = Set(lines("known.txt")), keep = Set(lines("keep-words.txt"))

struct Variant { let name: String; let floor: Double; let shape: Bool }
let variants = [Variant(name: "vikey", floor: -1e9, shape: false), Variant(name: "floor-11", floor: -11, shape: true),
                Variant(name: "floor-9", floor: -9, shape: true), Variant(name: "floor-7", floor: -7, shape: true)]

func shapeOK(_ low: String) -> Bool {
    let c = Array(low)
    guard c.contains(where: { "aeiouy".contains($0) }) else { return false }           // không nguyên âm: viết tắt
    for i in 2..<max(c.count, 2) where c[i] == c[i - 1] && c[i] == c[i - 2] { return false }   // ba chữ liền: kéo dài
    if c.count >= 2, c[c.count - 1] == c[c.count - 2], "aeiouy".contains(c[c.count - 1]) { return false }   // "oii", "nhaa"
    return true
}
func slipFix(_ low: String, _ taps: [(x: Float, y: Float)], before: String, _ v: Variant) -> String? {
    guard low.count >= 3, lm.id(low) == nil, !known.contains(low), !keep.contains(low) else { return nil }
    if v.shape, !shapeOK(low) { return nil }
    let reads = lm.readTaps(taps, keys: rects, before: before)
    guard let best = reads.first, best.word.lowercased() != low else { return nil }
    let typedScore = reads.first { $0.word.lowercased() == low }?.score ?? -40
    guard best.score - typedScore > 3, best.likelihood > v.floor else { return nil }
    return lm.prefersFinishing(low, over: best.word, before: before) ? nil : best.word
}
func typeWord(_ w: String, _ rng: inout Rng) -> (typed: String, taps: [(x: Float, y: Float)]) {
    var typed = "", taps: [(x: Float, y: Float)] = []
    for ch in w { let c = centre[ch]!; let x = c.0 + rng.gauss() * sigma, y = c.1 + rng.gauss() * sigma
        typed.append(keyAt(x, y)); taps.append((Float(x), Float(y))) }
    return (typed, taps)
}
// 1. chữ chat không có lớp bảo vệ nào: gõ đúng mà bị đổi là sửa nhầm
let chat = lines("chat.txt").filter { $0.allSatisfy { centre[$0] != nil } }
for v in variants {
    var rng = Rng(s: 42), n = 0, wrong = 0, examples: [String] = []
    for w in chat { for before in ["ok ", "", "em "] { for _ in 0..<10 {
        let (typed, taps) = typeWord(w, &rng)
        guard typed == w else { continue }
        n += 1
        if let f = slipFix(typed, taps, before: before, v) { wrong += 1; if examples.count < 12 { examples.append("\(w)→\(f)") } }
    } } }
    print("chat  \(v.name): typed right \(n), changed \(wrong) (\(String(format: "%.2f", 100 * Double(wrong) / Double(max(n, 1))))%)  \(examples.joined(separator: " "))")
}
// 2. câu tiếng Anh: từ gõ lệch được sửa đúng / sửa sai / để yên
let sentences = lines("sentences.txt")
for v in variants {
    var rng = Rng(s: 7), words = 0, slipped = 0, fixed = 0, misfixed = 0, examples: [String] = []
    for _ in 0..<8 { for s in sentences {
        var before = ""
        for w in s.split(separator: " ").map(String.init) {
            let low = w.lowercased()
            guard low.count >= 3, low.allSatisfy({ centre[$0] != nil }), lm.id(low) != nil else { before += w + " "; continue }
            let (typed, taps) = typeWord(low, &rng)
            words += 1
            if typed != low {
                slipped += 1
                let f = slipFix(typed, taps, before: before, v)
                if f?.lowercased() == low { fixed += 1 } else if let f { misfixed += 1; if examples.count < 8 { examples.append("\(low):\(typed)→\(f)") } }
            }
            before += w + " "
        }
    } }
    print("en    \(v.name): words \(words), mistyped \(slipped), fixed right \(fixed), fixed wrong \(misfixed)  \(examples.joined(separator: " "))")
}
