import Foundation
import XCTest
@testable import ViPiCore

/// Xuất "đáp án mẫu" của bộ gõ Swift để lõi Rust (core/) so khớp từng kết quả.
/// Chỉ chạy khi có biến môi trường: VIPI_GOLDEN=<thư mục> swift test --filter GoldenTests
/// (scripts/make-golden.sh chạy rồi nén vào core/tests/golden/).
final class GoldenTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources")
    private static func text(_ name: String) -> String {
        (try? String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    /// Sinh số giả ngẫu nhiên cố định (xorshift64*) để bộ mẫu luôn giống nhau.
    struct Rng {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> UInt64 {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    private func write(_ dir: URL, _ name: String, _ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        print("golden \(name): \(lines.count) lines")
    }

    private static func enc(_ e: TextEdit?) -> String { e.map { "\($0.backspaces):\($0.insert)" } ?? "-" }

    func testWriteGolden() throws {
        guard let path = ProcessInfo.processInfo.environment["VIPI_GOLDEN"] else { return }
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeTelex(dir)
        try writeAutoSwitch(dir)
        try writePinyin(dir)
    }

    // MARK: - Telex

    private func telexKeySets() -> (lexicon: [String], variants: [String], english: [String], random: [String]) {
        let syllables = Self.text("vietnamese-syllables.txt").split(whereSeparator: \.isNewline).map(String.init)
        var lexicon: [String] = []
        for (i, s) in syllables.enumerated() {
            let k = String(TelexEngine.telexKeys(for: s))
            lexicon.append(k)
            if i % 7 == 0 { lexicon.append(k.prefix(1).uppercased() + k.dropFirst()) }
            if i % 13 == 0 { lexicon.append(k.uppercased()) }
        }
        // gõ dấu thanh ngay sau nguyên âm đầu ("toans" → "tosan"), và dấu mũ/móc gõ sau cùng ("truowngf" → "truongwf")
        var variants: [String] = []
        for s in syllables {
            var k = TelexEngine.telexKeys(for: s)
            if let last = k.last, "sfrxj".contains(last), let v = k.firstIndex(where: { "aeiouy".contains($0) }), v + 1 < k.count - 1 {
                k.removeLast()
                k.insert(last, at: v + 1)
                variants.append(String(k))
            }
            if let w = k.firstIndex(of: "w"), w + 1 < k.count {
                var m = k
                m.remove(at: w)
                m.append("w")
                variants.append(String(m))
            }
        }
        let english = Self.text("autoswitch-en.tsv").split(whereSeparator: \.isNewline)
            .compactMap { $0.split(separator: "\t").first.map(String.init) }
            .filter { $0.allSatisfy { $0.isASCII && $0.isLetter } }
        var rng = Rng()
        let alphabet = Array("aaeeiioouuyddwwssffrrxxjjzqnghtcmpklbv")
        var random: [String] = []
        for _ in 0..<20000 {
            var k = ""
            for _ in 0..<(1 + rng.below(9)) {
                let c = alphabet[rng.below(alphabet.count)]
                k.append(rng.below(12) == 0 ? Character(c.uppercased()) : c)
            }
            random.append(k)
        }
        return (lexicon, variants, english, random)
    }

    private func writeTelex(_ dir: URL) throws {
        let lexicon = VietnameseLexicon(text: Self.text("vietnamese-syllables.txt"))
        let macros = MacroTable([("vn", "Việt Nam"), ("đc", "được"), ("ko", "không"), ("hn", "Hà Nội"), ("tp", "thành phố")])
        let sets = telexKeySets()
        let configs: [(name: String, modern: Bool, spell: Bool, keys: [String])] = [
            ("c1", false, true, sets.lexicon + sets.variants + Array(sets.english.prefix(20000)) + Array(sets.random.prefix(10000))),
            ("m1", true, true, sets.lexicon + sets.variants + Array(sets.random.prefix(5000))),
            ("c0", false, false, Array(sets.english.prefix(5000)) + Array(sets.random.prefix(10000))),
            ("m0", true, false, Array(sets.lexicon.prefix(3000)) + Array(sets.random.prefix(5000))),
        ]
        var lines: [String] = []
        for cfg in configs {
            func engine() -> TelexEngine {
                let e = TelexEngine()
                e.modernToneStyle = cfg.modern
                e.spellCheck = cfg.spell
                e.lexicon = cfg.spell ? lexicon : nil
                return e
            }
            for keys in cfg.keys {
                let a = engine()
                let edits = keys.map { Self.enc(a.type($0)) }.joined(separator: "|")
                let output = a.output
                let finish = Self.enc(a.finishWord())
                let b = engine()
                for k in keys { _ = b.type(k) }
                b.backspace()
                let back1 = "\(b.output)/\(String(b.keys))"
                let after = Self.enc(b.type("s"))
                let afterOut = b.output
                let c = engine()
                for k in keys { _ = c.type(k) }
                let macro = Self.enc(c.expandMacro(macros))
                lines.append([cfg.name, keys, edits, output, finish, back1, after, afterOut, macro].joined(separator: "\t"))
            }
        }
        // ngược: chữ → phím Telex
        for w in ["người", "được", "Nguyễn", "ĐẠI", "khuỷu", "Ư", "100đ", "a-b"] {
            lines.append(["keys", w, String(TelexEngine.telexKeys(for: w))].joined(separator: "\t"))
        }
        try write(dir, "telex.txt", lines)
    }

    // MARK: - Tự đổi Anh/Việt

    private func writeAutoSwitch(_ dir: URL) throws {
        let auto = try AutoSwitch(directory: Self.resources)
        let sets = telexKeySets()
        let vi = Self.text("autoswitch-vi.tsv").split(whereSeparator: \.isNewline)
            .compactMap { $0.split(separator: "\t").first.map(String.init) }
        var words = sets.english + vi + sets.lexicon
        words += sets.english.enumerated().filter { $0.offset % 9 == 0 }.map { $0.element.prefix(1).uppercased() + $0.element.dropFirst() }
        words += ["NAS", "HDD", "VĐV", "USA", "IRS", "obj", "a1", "x"]
        var lines: [String] = []
        for (i, w) in words.enumerated() {
            let keys = Array(w)
            for prev in i % 5 == 0 ? ["-", "video", "tooi", "the"] : ["-"] {
                auto.remember(prev == "-" ? nil : Array(prev))
                let shown = TelexEngine.render(keys, modern: false)
                let pe = auto.prefersEnglish(keys: keys, shown: shown)
                let fo = auto.isForeign(keys: keys, shown: shown)
                let vn = auto.vietnamese(for: keys, modern: false) ?? "-"
                let vnm = auto.vietnamese(for: keys, modern: true) ?? "-"
                lines.append([prev, w, shown, pe ? "1" : "0", fo ? "1" : "0", vn, vnm].joined(separator: "\t"))
            }
        }
        try write(dir, "autoswitch.txt", lines)
    }

    // MARK: - Pinyin

    private func writePinyin(_ dir: URL) throws {
        let dict = try PinyinDictionary(directory: Self.resources)
        let bigram = try BigramModel(contentsOf: Self.resources.appendingPathComponent("bigram.bin"))
        let traditional = try ChineseConverter(contentsOf: Self.resources.appendingPathComponent("s2t.bin"))
        let words = try SortedTable(contentsOf: Self.resources.appendingPathComponent("pinyin-words.bin"))

        // đầu vào: khoá từ điển (bỏ dấu cách), khoá cắt dở, viết tắt, câu ghép, và vài ca cố định
        var rng = Rng(state: 0xD1B5_4A32_D192_ED03)
        var keys: [String] = []
        for i in stride(from: 0, to: words.count, by: max(1, words.count / 240)) {
            keys.append(String(decoding: words.key(at: i), as: UTF8.self))
        }
        var inputs = ["nihao", "nh", "nih", "xi'an", "xian", "wozaixuexi", "woshizhongguoren", "wolaiziyuenan",
                      "zongguo", "zhongguo", "nihaoma", "jintiantianqihenhao", "lvxing", "nv", "a", "ang", "'a",
                      "zhuangzhuang", "shishi", "xiexie", "zh", "zhs", "bbbbb", "qwrt", "wo'ai'ni", "xianzai'"]
        for k in keys {
            let s = k.replacingOccurrences(of: " ", with: "")
            inputs.append(s)
            if s.count > 3 { inputs.append(String(s.dropLast(1 + rng.below(2)))) }
            let parts = k.split(separator: " ")
            if parts.count >= 2 { inputs.append(String(parts.map { $0.first! })) }
        }
        for _ in 0..<120 {
            var s = ""
            for _ in 0..<(2 + rng.below(3)) { s += keys[rng.below(keys.count)].replacingOccurrences(of: " ", with: "") }
            inputs.append(String(s.prefix(48)))
        }

        let allFuzzy = Set(FuzzyRule.all.map(\.id))
        let configs: [(name: String, bigram: Bool, fuzzy: Bool, trad: Bool)] = [
            ("u", false, false, false), ("b", true, false, false), ("bf", true, true, false), ("bt", true, false, true),
        ]
        func engine(_ cfg: (name: String, bigram: Bool, fuzzy: Bool, trad: Bool)) -> PinyinEngine {
            let e = PinyinEngine(dictionary: dict)
            if cfg.bigram { e.bigram = bigram }
            if cfg.fuzzy { e.fuzzyRules = allFuzzy }
            if cfg.trad { e.converter = traditional }
            return e
        }
        func cands(_ e: PinyinEngine, _ n: Int = .max) -> String {
            e.candidates.prefix(n).map { "\($0.text)\u{1f}\($0.length)" }.joined(separator: "\u{1e}")
        }
        var lines: [String] = []
        for cfg in configs {
            let e = engine(cfg)
            for input in inputs {
                e.reset()
                for c in input { e.type(c) }
                lines.append([cfg.name, input, e.preedit, cands(e)].joined(separator: "\t"))
            }
        }
        try write(dir, "pinyin.txt", lines)

        // chọn từng phần, Backspace, Enter, và học từ (từ điển người dùng trong bộ nhớ)
        var steps: [String] = []
        for cfg in configs {
            let e = engine(cfg)
            e.userDictionary = PinyinUserDictionary(fileURL: nil)
            for (n, input) in inputs.enumerated() where n % 3 == 0 {
                e.reset()
                for c in input { e.type(c) }
                var log: [String] = []
                var step = 0
                while e.isComposing, step < 12 {
                    if step == 2 && n % 2 == 0 { e.backspace(); log.append("B>\(e.input)@\(e.preedit)") }
                    let i = e.candidates.isEmpty ? -1 : (step * 2 + n) % min(e.candidates.count, 4)
                    if i < 0 { log.append("R>\(e.commitRaw())"); break }
                    let out = e.select(i) ?? "-"
                    log.append("\(i)>\(out)@\(e.input)@\(e.preedit)")
                    step += 1
                }
                if e.isComposing { log.append("R>\(e.commitRaw())") }
                // gõ lại: từ vừa học lên đầu
                for c in input { e.type(c) }
                log.append("again>" + cands(e, 5))
                e.reset()
                steps.append([cfg.name, input, log.joined(separator: "\u{1d}")].joined(separator: "\t"))
            }
        }
        try write(dir, "pinyin-select.txt", steps)

        // phồn thể: khoá trong bảng và cụm ghép từ nhiều khoá (khớp dài nhất)
        let s2t = Self.text("s2t.tsv").split(whereSeparator: \.isNewline).compactMap { $0.split(separator: "\t").first.map(String.init) }
        var phrases = stride(from: 0, to: s2t.count, by: 7).map { s2t[$0] }
        for _ in 0..<2000 {
            var s = ""
            for _ in 0..<(2 + rng.below(3)) { s += s2t[rng.below(s2t.count)] }
            phrases.append(s)
        }
        phrases += ["头发", "后天", "发", "我们的头发很长", "abc头发xyz", ""]
        try write(dir, "convert.txt", phrases.map { "\($0)\t\(traditional.convert($0))" })

        // mô hình bigram: log P(w2 | w1)
        var pairs: [String] = []
        let common = ["我", "是", "在", "再", "中国", "人", "的", "了", "学习", "你好", "时", "事", "不", "有", "他们"]
        for a in common { for b in common { pairs.append("\(a)\t\(b)\t\(bigram.logProb(a, b, unigram: 1e-5).bitPattern)") } }
        try write(dir, "bigram.txt", pairs)
    }
}
