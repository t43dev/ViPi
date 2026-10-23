import Foundation

// Bộ gõ Pinyin: tách chuỗi pinyin thành âm tiết, tra từ điển rime-ice (pinyin.tsv),
// ghép câu bằng quy hoạch động trên lưới từ, và cho chọn từng phần như các bộ gõ Trung thông thường.
// Bên trong luôn là giản thể; phồn thể (converter) chỉ áp ở đầu ra: candidates, preedit, kết quả commit.

public struct PinyinEntry: Equatable {
    public let word: String
    public let weight: Int
}

public final class PinyinDictionary {
    private(set) var words: [String: [PinyinEntry]] = [:]   // "ni hao" → [你好, 拟好...] theo weight giảm dần
    private(set) var abbrev: [String: [PinyinEntry]] = [:]  // "nh" → từ 2-4 chữ viết tắt bằng phụ âm đầu
    public private(set) var syllables: Set<String> = []
    private var byPrefix: [String: [String]] = [:]          // "zh" → [zha, zhai, ...]
    private(set) var keyPrefixes: Set<String> = []          // "ni", "ni hao" của khoá "ni hao ma": cắt nhánh khi dò
    let maxSyllableLength = 6

    public convenience init(contentsOf url: URL) throws {
        try self.init(tsv: String(contentsOf: url, encoding: .utf8))
    }

    /// Dòng: `word<TAB>pin yin<TAB>weight`.
    public init(tsv: String) {
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 2 else { continue }
            let word = String(cols[0]), key = String(cols[1])
            let entry = PinyinEntry(word: word, weight: cols.count > 2 ? Int(cols[2]) ?? 0 : 0)
            words[key, default: []].append(entry)
            let sylls = key.split(separator: " ")
            if sylls.count == 1 { syllables.insert(key) }
            if (2...4).contains(sylls.count) {
                abbrev[String(sylls.map { $0.first! }), default: []].append(entry)
            }
            var p = ""
            for s in sylls {
                p += p.isEmpty ? String(s) : " " + s
                keyPrefixes.insert(p)
            }
        }
        for k in words.keys { words[k]!.sort { $0.weight > $1.weight } }
        for k in abbrev.keys { abbrev[k] = Array(abbrev[k]!.sorted { $0.weight > $1.weight }.prefix(30)) }
        for s in syllables {
            for n in 1..<s.count { byPrefix[String(s.prefix(n)), default: []].append(s) }
        }
    }

    func lookup(_ key: String) -> [PinyinEntry] { words[key] ?? [] }
    func abbreviation(_ key: String) -> [PinyinEntry] { abbrev[key] ?? [] }
    func completions(of prefix: String) -> [String] { byPrefix[prefix] ?? [] }
}

public struct PinyinCandidate: Equatable {
    public let text: String
    public let length: Int   // số ký tự input (kể cả dấu ') mà ứng viên này dùng hết
}

public final class PinyinEngine {
    public let dict: PinyinDictionary
    public let maxInput = 48

    /// Âm mờ đang bật (id của FuzzyRule, vd "z=zh").
    public var fuzzyRules: Set<String> = [] {
        didSet { aliases = FuzzyRule.aliases(rules: fuzzyRules, syllables: dict.syllables); refresh() }
    }
    /// Có thì đầu ra là phồn thể.
    public var converter: ChineseConverter? { didSet { refresh() } }
    /// Có thì học từ/cụm người dùng chọn và đưa lên đầu lần sau.
    public var userDictionary: PinyinUserDictionary?

    public private(set) var input = ""                                     // phần pinyin chưa chọn
    private var chosen: [(text: String, raw: String)] = []                 // các đoạn đã chọn (giản thể), chưa commit
    public private(set) var candidates: [PinyinCandidate] = []             // đã chuyển phồn thể nếu bật
    private var internalCandidates: [PinyinCandidate] = []                 // giản thể, cùng chỉ số với candidates
    private var aliases: [String: [String]] = [:]

    public init(dictionary: PinyinDictionary) { dict = dictionary }

    public var isComposing: Bool { !input.isEmpty || !chosen.isEmpty }

    /// Chuỗi hiển thị trong ô gợi ý: phần đã chọn + pinyin còn lại tách âm tiết.
    public var preedit: String {
        output(chosen.map(\.text).joined()) + segmentForDisplay(input)
    }

    public func reset() {
        input = ""
        chosen = []
        candidates = []
        internalCandidates = []
    }

    /// a-z hoặc dấu ' (v thay cho ü).
    public func type(_ c: Character) {
        guard input.count < maxInput else { return }
        if c == "'" && (input.isEmpty || input.last == "'") { return }
        input.append(c)
        refresh()
    }

    public func backspace() {
        if !input.isEmpty {
            input.removeLast()
        } else if let last = chosen.popLast() {
            input = last.raw
        }
        refresh()
    }

    /// Chọn ứng viên; trả về chuỗi cần commit khi đã dùng hết input, nil nếu còn phải chọn tiếp.
    public func select(_ index: Int) -> String? {
        guard internalCandidates.indices.contains(index) else { return nil }
        let c = internalCandidates[index]
        let raw = String(input.prefix(c.length))
        userDictionary?.record(Self.letters(raw), c.text)
        chosen.append((c.text, raw))
        input = String(input.dropFirst(c.length))
        while input.first == "'" { input.removeFirst() }
        if input.isEmpty {
            let text = chosen.map(\.text).joined()
            // cụm ghép từ nhiều lần chọn: học cả cụm để lần sau ra một phát
            if chosen.count >= 2, text.count <= 10 {
                userDictionary?.record(Self.letters(chosen.map(\.raw).joined()), text)
            }
            reset()
            return output(text)
        }
        refresh()
        return nil
    }

    /// Enter: commit phần đã chọn + pinyin thô còn lại.
    public func commitRaw() -> String {
        let text = output(chosen.map(\.text).joined()) + Self.letters(input)
        reset()
        return text
    }

    static func letters(_ raw: String) -> String { raw.replacingOccurrences(of: "'", with: "") }

    private func output(_ simplified: String) -> String {
        converter?.convert(simplified) ?? simplified
    }

    private func refresh() {
        guard !input.isEmpty else { candidates = []; internalCandidates = []; return }
        var list = PinyinEngine.candidates(for: Array(input), dict: dict, aliases: aliases)
        if let ud = userDictionary {
            // từ/cụm đã học cho đúng chuỗi đang gõ lên đầu
            let learned = ud.words(for: Self.letters(input)).map { PinyinCandidate(text: $0, length: input.count) }
            if !learned.isEmpty {
                let top = Set(learned.map(\.text))
                list = learned + list.filter { !top.contains($0.text) }
            }
        }
        internalCandidates = []
        candidates = []
        var seen = Set<String>()
        for c in list {
            let shown = output(c.text)
            if seen.insert(shown).inserted {
                internalCandidates.append(c)
                candidates.append(PinyinCandidate(text: shown, length: c.length))
            }
        }
    }

    // MARK: - Candidate generation

    struct WordMatch {
        let end: Int
        let entries: [PinyinEntry]
    }

    /// Mọi từ trong từ điển bắt đầu tại `start` (đi theo lưới âm tiết, tối đa 8 âm tiết).
    /// `aliases`: âm tiết gõ theo âm mờ → âm tiết thật; từ tìm qua âm mờ bị hạ weight để âm đúng thắng.
    static func words(from start: Int, in s: [Character], dict: PinyinDictionary,
                      aliases: [String: [String]] = [:]) -> [WordMatch] {
        var out: [WordMatch] = []
        func walk(_ pos: Int, _ prefix: [String]) {
            guard prefix.count < 8 else { return }
            var p = pos
            while p < s.count, s[p] == "'" { p += 1 }
            guard p < s.count else { return }
            var len = 1
            while len <= dict.maxSyllableLength, p + len <= s.count {
                let piece = s[p..<(p + len)]
                if piece.contains("'") { break }
                let syl = String(piece)
                let end = p + len
                var options: [(syllable: String, fuzzy: Bool)] = []
                if dict.syllables.contains(syl) { options.append((syl, false)) }
                for a in aliases[syl] ?? [] { options.append((a, true)) }
                for o in options {
                    let key = prefix + [o.syllable]
                    let joined = key.joined(separator: " ")
                    guard dict.keyPrefixes.contains(joined) else { continue }
                    let found = dict.lookup(joined)
                    if !found.isEmpty {
                        let entries = o.fuzzy ? found.map { PinyinEntry(word: $0.word, weight: $0.weight / 8) } : found
                        out.append(WordMatch(end: end, entries: entries))
                    }
                    walk(end, key)
                }
                // âm tiết cuối chưa gõ xong: "nih" → ni + (ha, hai, hao, ...)
                if end == s.count {
                    var found: [PinyinEntry] = []
                    for comp in dict.completions(of: syl) {
                        found += dict.lookup((prefix + [comp]).joined(separator: " ")).prefix(20)
                    }
                    if !found.isEmpty {
                        found.sort { $0.weight > $1.weight }
                        out.append(WordMatch(end: end, entries: found))
                    }
                }
                len += 1
            }
        }
        walk(start, [])
        return out
    }

    static func candidates(for s: [Character], dict: PinyinDictionary,
                           aliases: [String: [String]] = [:]) -> [PinyinCandidate] {
        let n = s.count
        var list: [PinyinCandidate] = []
        var seen = Set<String>()
        func add(_ text: String, _ length: Int) {
            if seen.insert(text).inserted { list.append(PinyinCandidate(text: text, length: length)) }
        }

        // Viết tắt toàn phụ âm đầu: "nh" → 你好
        let letters = s.filter { $0 != "'" }
        if (2...4).contains(letters.count), !letters.contains(where: { "aeiouv".contains($0) }) {
            for e in dict.abbreviation(String(letters)).prefix(10) { add(e.word, n) }
        }

        // Ghép câu: best[i] = (điểm, câu) tốt nhất cho s[i...]
        var matchesAt: [[WordMatch]] = Array(repeating: [], count: n + 1)
        for i in 0..<n {
            matchesAt[i] = words(from: i, in: s, dict: dict, aliases: aliases)
        }
        var best: [(score: Double, text: String, words: Int)?] = Array(repeating: nil, count: n + 1)
        best[n] = (0, "", 0)
        for i in stride(from: n - 1, through: 0, by: -1) {
            if s[i] == "'", let next = best[i + 1] { best[i] = next; continue }
            for m in matchesAt[i] {
                guard let rest = best[m.end], let top = m.entries.first else { continue }
                let score = log(Double(max(top.weight, 1))) - 20 + rest.score
                if best[i] == nil || score > best[i]!.score {
                    best[i] = (score, top.word + rest.text, rest.words + 1)
                }
            }
        }
        if let sentence = best[0], sentence.words > 1 { add(sentence.text, n) }

        // Từ bắt đầu ở đầu chuỗi: dài trước, rồi theo weight
        let starts = matchesAt[0].sorted { $0.end > $1.end }
        var byEnd: [Int: [PinyinEntry]] = [:]
        for m in starts { byEnd[m.end, default: []] += m.entries }
        for end in byEnd.keys.sorted(by: >) {
            for e in byEnd[end]!.sorted(by: { $0.weight > $1.weight }).prefix(60) { add(e.word, end) }
        }
        return Array(list.prefix(200))
    }

    /// "nihao" → "ni hao" (tách tham lam, dài nhất trước; âm mờ cũng tính là âm tiết).
    func segmentForDisplay(_ text: String) -> String {
        let s = Array(text)
        var out: [String] = []
        var i = 0
        func isSyllable(_ x: String) -> Bool { dict.syllables.contains(x) || aliases[x] != nil }
        while i < s.count {
            if s[i] == "'" { out.append("'"); i += 1; continue }
            var len = min(dict.maxSyllableLength, s.count - i)
            while len > 1, !isSyllable(String(s[i..<(i + len)])) { len -= 1 }
            out.append(String(s[i..<(i + len)]))
            i += len
        }
        return out.joined(separator: " ").replacingOccurrences(of: " ' ", with: "'")
    }
}
