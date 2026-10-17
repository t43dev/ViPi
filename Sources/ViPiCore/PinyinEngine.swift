import Foundation

// Bộ gõ Pinyin: tách chuỗi pinyin thành âm tiết, tra từ điển rime-ice (pinyin.tsv),
// ghép câu bằng quy hoạch động trên lưới từ, và cho chọn từng phần như các bộ gõ Trung thông thường.

public struct PinyinEntry: Equatable {
    public let word: String
    public let weight: Int
}

public final class PinyinDictionary {
    private(set) var words: [String: [PinyinEntry]] = [:]   // "ni hao" → [你好, 拟好...] theo weight giảm dần
    private(set) var abbrev: [String: [PinyinEntry]] = [:]  // "nh" → từ 2-4 chữ viết tắt bằng phụ âm đầu
    public private(set) var syllables: Set<String> = []
    private var byPrefix: [String: [String]] = [:]          // "zh" → [zha, zhai, ...]
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

    public private(set) var input = ""                                     // phần pinyin chưa chọn
    private var chosen: [(text: String, raw: String)] = []                 // các đoạn đã chọn, chưa commit
    public private(set) var candidates: [PinyinCandidate] = []

    public init(dictionary: PinyinDictionary) { dict = dictionary }

    public var isComposing: Bool { !input.isEmpty || !chosen.isEmpty }

    /// Chuỗi hiển thị trong ô gợi ý: phần đã chọn + pinyin còn lại tách âm tiết.
    public var preedit: String {
        chosen.map(\.text).joined() + segmentForDisplay(input)
    }

    public func reset() {
        input = ""
        chosen = []
        candidates = []
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
        guard candidates.indices.contains(index) else { return nil }
        let c = candidates[index]
        let raw = String(input.prefix(c.length))
        chosen.append((c.text, raw))
        input = String(input.dropFirst(c.length))
        while input.first == "'" { input.removeFirst() }
        if input.isEmpty {
            let text = chosen.map(\.text).joined()
            reset()
            return text
        }
        refresh()
        return nil
    }

    /// Enter: commit phần đã chọn + pinyin thô còn lại.
    public func commitRaw() -> String {
        let text = chosen.map(\.text).joined() + input.replacingOccurrences(of: "'", with: "")
        reset()
        return text
    }

    private func refresh() {
        candidates = input.isEmpty ? [] : PinyinEngine.candidates(for: Array(input), dict: dict)
    }

    // MARK: - Candidate generation

    struct WordMatch {
        let end: Int
        let entries: [PinyinEntry]
    }

    /// Mọi từ trong từ điển bắt đầu tại `start` (đi theo lưới âm tiết, tối đa 8 âm tiết).
    static func words(from start: Int, in s: [Character], dict: PinyinDictionary) -> [WordMatch] {
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
                if dict.syllables.contains(syl) {
                    let key = prefix + [syl]
                    let found = dict.lookup(key.joined(separator: " "))
                    if !found.isEmpty { out.append(WordMatch(end: end, entries: found)) }
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

    static func candidates(for s: [Character], dict: PinyinDictionary) -> [PinyinCandidate] {
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
            matchesAt[i] = words(from: i, in: s, dict: dict)
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

    /// "nihao" → "ni hao" (tách tham lam, dài nhất trước).
    func segmentForDisplay(_ text: String) -> String {
        let s = Array(text)
        var out: [String] = []
        var i = 0
        while i < s.count {
            if s[i] == "'" { out.append("'"); i += 1; continue }
            var len = min(dict.maxSyllableLength, s.count - i)
            while len > 1, !dict.syllables.contains(String(s[i..<(i + len)])) { len -= 1 }
            out.append(String(s[i..<(i + len)]))
            i += len
        }
        return out.joined(separator: " ").replacingOccurrences(of: " ' ", with: "'")
    }
}
