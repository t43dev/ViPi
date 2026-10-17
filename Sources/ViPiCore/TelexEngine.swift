// Bộ gõ Telex: mỗi phím gõ được xử lý lại từ đầu trên chuỗi phím thô của từ hiện tại,
// rồi so với chuỗi đang hiển thị để ra số backspace + chuỗi cần chèn.
// Bảng nguyên âm hợp lệ lấy theo VSeqList của Unikey (ukengine.cpp, GPL).

public enum Tone: Int, CaseIterable {
    case none = 0, acute, grave, hook, tilde, dot   // không dấu, sắc, huyền, hỏi, ngã, nặng

    init?(telexKey k: Character) {
        switch k {
        case "s": self = .acute
        case "f": self = .grave
        case "r": self = .hook
        case "x": self = .tilde
        case "j": self = .dot
        default: return nil
        }
    }
}

enum Mark { case none, circumflex, breve, horn, stroke }

struct VChar: Equatable {
    var base: Character        // a-z, chữ thường
    var mark: Mark = .none
    var upper = false
    var fromW = false          // ư sinh ra từ phím w đứng riêng

    var isVowel: Bool { "aeiouy".contains(base) }

    /// Chữ không dấu thanh, vd "ơ", "đ".
    var letter: Character {
        switch (base, mark) {
        case ("a", .circumflex): return "â"
        case ("a", .breve): return "ă"
        case ("e", .circumflex): return "ê"
        case ("o", .circumflex): return "ô"
        case ("o", .horn): return "ơ"
        case ("u", .horn): return "ư"
        case ("d", .stroke): return "đ"
        default: return base
        }
    }
}

/// Kết quả của một phím: xoá `backspaces` ký tự trước con trỏ rồi chèn `insert`.
public struct TextEdit: Equatable {
    public let backspaces: Int
    public let insert: String
    public init(backspaces: Int, insert: String) {
        self.backspaces = backspaces
        self.insert = insert
    }
}

public final class TelexEngine {
    /// true: đặt dấu kiểu mới (hoà, khoẻ, thuý); false: kiểu cũ (hòa, khỏe, thúy) — mặc định như Unikey.
    public var modernToneStyle = false

    /// false: bỏ kiểm tra chính tả — mọi phím dấu đều được áp dụng, không trả lại chữ tiếng Anh.
    public var spellCheck = true

    /// Có danh sách âm tiết thì khi kết thúc từ, chữ không phải tiếng Việt được trả lại như đã gõ.
    public var lexicon: VietnameseLexicon?

    public private(set) var keys: [Character] = []   // phím thô của từ hiện tại (giữ hoa/thường)
    public private(set) var output = ""               // chuỗi đang hiển thị cho từ hiện tại

    public init() {}

    public var isEmpty: Bool { keys.isEmpty }

    public func reset() {
        keys = []
        output = ""
    }

    /// Xử lý một chữ cái a-z/A-Z. Ký tự khác: caller phải reset() vì là ranh giới từ.
    public func type(_ key: Character) -> TextEdit {
        keys.append(key)
        return update(to: Self.render(keys, modern: modernToneStyle, spellCheck: spellCheck))
    }

    /// Kết thúc từ (Space, dấu câu, Enter…) rồi reset. Trả về sửa đổi để gõ lại đúng các phím đã gõ khi
    /// chữ trên màn hình không phải tiếng Việt: có dấu mà không phải âm tiết có thật ("ủe" → "user"),
    /// hoặc phím đôi bỏ dấu nằm giữa từ ("isue" → "issue"). Giữ nguyên: bỏ dấu ở cuối từ ("ass" → "as")
    /// và chữ không có nguyên âm ("100đ").
    public func finishWord() -> TextEdit? {
        defer { reset() }
        let raw = String(keys)
        guard spellCheck, let lexicon, output != raw else { return nil }
        if output.unicodeScalars.allSatisfy(\.isASCII) {
            guard !raw.hasPrefix(output) else { return nil }
        } else {
            let hasVowel = output.contains { Vietnamese.decompose($0).map { "aăâeêioôơuưy".contains($0.0) } ?? false }
            guard hasVowel, !lexicon.contains(output) else { return nil }
        }
        return TextEdit(backspaces: output.count, insert: raw)
    }

    /// Backspace đã được gửi cho ứng dụng (không chặn): xoá ký tự cuối và dựng lại phím thô.
    public func backspace() {
        guard !output.isEmpty else { keys = []; return }
        output.removeLast()
        keys = Self.telexKeys(for: output)
        // Chuỗi dựng lại phải hiển thị y hệt; nếu không (hiếm) thì coi như nhập lại từ đầu.
        if Self.render(keys, modern: modernToneStyle, spellCheck: spellCheck) != output { keys = Array(output) }
    }

    private func update(to newOutput: String) -> TextEdit {
        let old = Array(output), new = Array(newOutput)
        var common = 0
        while common < old.count, common < new.count, old[common] == new[common] { common += 1 }
        output = newOutput
        return TextEdit(backspaces: old.count - common, insert: String(new[common...]))
    }

    // MARK: - Render

    /// Dựng chuỗi hiển thị từ chuỗi phím thô.
    static func render(_ keys: [Character], modern: Bool, spellCheck: Bool = true) -> String {
        var s = State(spellCheck: spellCheck)
        for k in keys { s.apply(k) }
        if s.literal { return s.text(modern: modern) }
        return s.acceptable ? s.text(modern: modern) : String(keys)
    }

    struct State {
        var spellCheck = true
        var chars: [VChar] = []
        var tone: Tone = .none
        var literal = false   // sau khi gõ huỷ (aaa, ss, ww...) thì các phím sau là chữ thường

        /// Tắt kiểm tra chính tả thì chữ nào cũng được biến đổi.
        var acceptable: Bool { !spellCheck || isValid }

        mutating func append(_ k: Character) {
            chars.append(VChar(base: Character(k.lowercased()), upper: k.isUppercase))
        }

        mutating func apply(_ key: Character) {
            let k = Character(key.lowercased())
            // từ đã sai chính tả (đang hiện phím thô) thì không biến đổi nữa
            if literal || !k.isASCII || !k.isLetter || !acceptable { append(key); return }
            // chỉ nhận biến đổi nếu kết quả còn hợp lệ (vd "ngoeo": o thứ hai là chữ, không phải ô)
            var t = self
            if t.transform(key, k), t.literal || t.acceptable { self = t } else { append(key) }
        }

        /// false: phím không phải phím biến đổi.
        mutating func transform(_ key: Character, _ k: Character) -> Bool {
            let parts = Syllable(chars)

            if let t = Tone(telexKey: k), !parts.vowels.isEmpty {
                if tone == t { tone = .none; append(key); literal = true } else { tone = t }
                return true
            }
            if k == "z", tone != .none, !parts.vowels.isEmpty { tone = .none; return true }

            if k == "d", chars.first?.base == "d" {
                if chars[0].mark == .stroke { chars[0].mark = .none; append(key); literal = true }
                else { chars[0].mark = .stroke }
                return true
            }

            if "aeo".contains(k), let i = parts.vowels.last(where: { chars[$0].base == k }) {
                if chars[i].mark == .circumflex { chars[i].mark = .none; append(key); literal = true }
                else { chars[i].mark = .circumflex }
                return true
            }

            if k == "w" { return applyW(key, parts) }
            return false
        }

        mutating func applyW(_ key: Character, _ parts: Syllable) -> Bool {
            let v = parts.vowels
            // ư sinh từ w đứng riêng: gõ w lần nữa thì trả lại chữ w
            if let i = v.first(where: { chars[$0].fromW }) {
                chars[i] = VChar(base: "w", upper: chars[i].upper)
                literal = true
                return true
            }
            if v.isEmpty {
                guard parts.final.isEmpty, parts.initial != "q", parts.initial != "qu" else { return false }
                chars.append(VChar(base: "u", mark: .horn, upper: key.isUppercase, fromW: true))
                return true
            }
            let cluster = String(v.map { chars[$0].base })
            guard let marks = Self.hornTable[cluster] else { return false }
            let current = v.map { chars[$0].mark }
            if zip(current, marks).allSatisfy({ $1 == .none || $0 == $1 }) {
                // đã có đủ dấu móc/trăng → huỷ
                for (i, m) in zip(v, marks) where m != .none { chars[i].mark = .none }
                append(key)
                literal = true
            } else {
                for (i, m) in zip(v, marks) where m != .none { chars[i].mark = m }
            }
            return true
        }

        static let hornTable: [String: [Mark]] = [
            "a": [.breve], "o": [.horn], "u": [.horn],
            "oa": [.none, .breve], "oi": [.horn, .none], "ua": [.horn, .none], "ui": [.horn, .none],
            // uo + w → uơ (thuở, huơ); có âm theo sau thì text() đổi thành ươ (người, được)
            "uo": [.none, .horn], "uu": [.horn, .none],
            "uoi": [.none, .horn, .none], "uou": [.none, .horn, .none],
        ]

        var isValid: Bool {
            let p = Syllable(chars)
            guard p.ok else { return false }
            if p.vowels.isEmpty { return p.final.isEmpty }
            let cluster = Self.clusterKey(p.vowels.map { chars[$0] })
            guard Vietnamese.vowelClusters.contains(cluster) else { return false }
            if !p.final.isEmpty {
                guard Vietnamese.finals.contains(p.final), Vietnamese.clustersTakingFinal.contains(cluster) else { return false }
                if ["c", "ch", "p", "t"].contains(p.final), ![.none, .acute, .dot].contains(tone) { return false }
            }
            return true
        }

        static func clusterKey(_ cs: [VChar]) -> String { String(cs.map(\.letter)) }

        func text(modern: Bool) -> String {
            var cs = chars
            let p = Syllable(cs)
            // "ưo"/"uơ" + phụ âm cuối / i / u → "ươ" (người, được, rượu)
            let v = p.vowels
            if v.count >= 2, cs[v[0]].base == "u", cs[v[1]].base == "o", v.count == 3 || !p.final.isEmpty,
               cs[v[0]].mark == .horn || cs[v[1]].mark == .horn {
                cs[v[0]].mark = .horn
                cs[v[1]].mark = .horn
            }
            var out = cs.map { c -> String in
                let s = String(c.letter)
                return c.upper ? s.uppercased() : s
            }
            if tone != .none, let i = Self.tonePosition(cs, p, modern: modern) {
                out[i] = String(Vietnamese.toned(cs[i].letter, tone, upper: cs[i].upper))
            }
            return out.joined()
        }

        static func tonePosition(_ cs: [VChar], _ p: Syllable, modern: Bool) -> Int? {
            let v = p.vowels
            guard !v.isEmpty else { return nil }
            if let marked = v.last(where: { cs[$0].mark != .none }) { return marked }
            if v.count == 1 { return v[0] }
            if !p.final.isEmpty { return v.last }
            if v.count >= 3 { return v[1] }
            let pair = String(v.map { cs[$0].base })
            if ["oa", "oe", "uy"].contains(pair) { return modern ? v[1] : v[0] }
            return v[0]
        }
    }

    // MARK: - Ngược: chuỗi tiếng Việt → phím Telex (dùng khi backspace)

    public static func telexKeys(for word: String) -> [Character] {
        var keys: [Character] = []
        var tone: Tone = .none
        for ch in word {
            guard let (letter, t) = Vietnamese.decompose(ch) else { keys.append(ch); continue }
            if t != .none { tone = t }
            let upper = ch.isUppercase
            func put(_ s: String) { for c in s { keys.append(upper ? Character(c.uppercased()) : c) } }
            switch letter {
            case "â": put("aa")
            case "ă": put("aw")
            case "ê": put("ee")
            case "ô": put("oo")
            case "ơ": put("ow")
            case "ư": put("uw")
            case "đ": put("dd")
            default: put(String(letter))
            }
        }
        switch tone {
        case .none: break
        case .acute: keys.append("s")
        case .grave: keys.append("f")
        case .hook: keys.append("r")
        case .tilde: keys.append("x")
        case .dot: keys.append("j")
        }
        return keys
    }
}

/// Các âm tiết tiếng Việt có thật (mỗi dòng một âm tiết). So khớp không phân biệt hoa/thường
/// và vị trí dấu thanh ("hòa" = "hoà").
public struct VietnameseLexicon {
    private let entries: Set<String>

    public init(text: String) {
        entries = Set(text.split(whereSeparator: \.isNewline).map { Self.key(String($0)) })
    }

    public func contains(_ syllable: String) -> Bool { entries.contains(Self.key(syllable)) }

    private static func key(_ s: String) -> String { String(TelexEngine.telexKeys(for: s.lowercased())) }
}

/// Tách âm tiết: phụ âm đầu / cụm nguyên âm / phụ âm cuối.
struct Syllable {
    var initial = ""
    var vowels: [Int] = []
    var final = ""
    var ok = true

    init(_ cs: [VChar]) {
        let b = cs.map { $0.mark == .stroke ? Character("đ") : $0.base }
        var i = 0
        for cons in Vietnamese.initials where b.count >= cons.count && String(b[0..<cons.count]) == cons {
            var n = cons.count
            if cons == "gi", !(b.count > 2 && cs[2].isVowel) { n = 1 }   // "gì": i là nguyên âm
            if cons == "qu", cs[1].mark != .none { n = 1 }
            initial = String(b[0..<n])
            i = n
            break
        }
        while i < cs.count, cs[i].isVowel { vowels.append(i); i += 1 }
        final = String(b[i...])
        if final.contains(where: { "aeiouy".contains($0) }) { ok = false }
    }
}

enum Vietnamese {
    // dài trước ngắn để khớp tham lam
    static let initials = ["ngh", "ng", "nh", "ch", "gh", "gi", "kh", "ph", "th", "tr", "qu",
                           "b", "c", "d", "đ", "g", "h", "k", "l", "m", "n", "p", "q", "r", "s", "t", "v", "x"]

    static let finals: Set<String> = ["c", "ch", "m", "n", "ng", "nh", "p", "t"]

    // VSeqList của Unikey (gồm cả dạng chưa hoàn chỉnh khi đang gõ)
    static let vowelClusters: Set<String> = [
        "a", "â", "ă", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        "ai", "ao", "au", "ay", "âu", "ây", "eo", "eu", "êu", "ia", "ie", "iê", "iu",
        "oa", "oă", "oe", "oi", "ôi", "ơi", "oo", "ua", "uâ", "ue", "uê", "ui", "uo", "uô", "uơ",
        "uu", "uy", "ưa", "ưi", "ưo", "ươ", "ưu", "ye", "yê",
        "ieu", "iêu", "oai", "oay", "oeo", "uay", "uây", "uoi", "uou", "uôi", "uơi", "uơu",
        "uya", "uye", "uyê", "uyu", "ưoi", "ưou", "ươi", "ươu", "yeu", "yêu",
    ]

    static let clustersTakingFinal: Set<String> = [
        "a", "â", "ă", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        "ie", "iê", "oa", "oă", "oe", "oo", "ua", "uâ", "ue", "uê", "uo", "uô", "uơ", "uy",
        "ưo", "ươ", "ye", "yê", "uye", "uyê",
    ]

    // thứ tự: không dấu, sắc, huyền, hỏi, ngã, nặng
    static let lowerTable: [Character: String] = [
        "a": "aáàảãạ", "ă": "ăắằẳẵặ", "â": "âấầẩẫậ", "e": "eéèẻẽẹ", "ê": "êếềểễệ",
        "i": "iíìỉĩị", "o": "oóòỏõọ", "ô": "ôốồổỗộ", "ơ": "ơớờởỡợ", "u": "uúùủũụ",
        "ư": "ưứừửữự", "y": "yýỳỷỹỵ",
    ]
    static let upperTable: [Character: String] = [
        "a": "AÁÀẢÃẠ", "ă": "ĂẮẰẲẴẶ", "â": "ÂẤẦẨẪẬ", "e": "EÉÈẺẼẸ", "ê": "ÊẾỀỂỄỆ",
        "i": "IÍÌỈĨỊ", "o": "OÓÒỎÕỌ", "ô": "ÔỐỒỔỖỘ", "ơ": "ƠỚỜỞỠỢ", "u": "UÚÙỦŨỤ",
        "ư": "ƯỨỪỬỮỰ", "y": "YÝỲỶỸỴ",
    ]

    static func toned(_ letter: Character, _ tone: Tone, upper: Bool) -> Character {
        guard let row = (upper ? upperTable : lowerTable)[letter] else { return letter }
        return Array(row)[tone.rawValue]
    }

    /// Ký tự tiếng Việt → (chữ thường không dấu thanh, dấu thanh). nil nếu không phải chữ cái.
    static let decomposeMap: [Character: (Character, Tone)] = {
        var m: [Character: (Character, Tone)] = [:]
        for (letter, row) in lowerTable {
            for (i, c) in row.enumerated() { m[c] = (letter, Tone(rawValue: i)!) }
        }
        for (letter, row) in upperTable {
            for (i, c) in row.enumerated() { m[c] = (letter, Tone(rawValue: i)!) }
        }
        m["đ"] = ("đ", .none); m["Đ"] = ("đ", .none)
        return m
    }()

    static func decompose(_ ch: Character) -> (Character, Tone)? {
        if let r = decomposeMap[ch] { return r }
        if ch.isASCII, ch.isLetter { return (Character(ch.lowercased()), .none) }
        return nil
    }
}
