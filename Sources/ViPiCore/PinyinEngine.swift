import Foundation

// Bộ gõ Pinyin: tách chuỗi pinyin thành âm tiết, tra từ điển rime-ice (pinyin.tsv),
// ghép câu bằng quy hoạch động trên lưới từ, và cho chọn từng phần như các bộ gõ Trung thông thường.
// Bên trong luôn là giản thể; phồn thể (converter) chỉ áp ở đầu ra: candidates, preedit, kết quả commit.

public struct PinyinEntry: Equatable {
    public let word: String
    public let weight: Int
}

public final class PinyinDictionary {
    private let words: SortedTable    // "ni hao" → [你好, 拟好...] theo weight giảm dần (pinyin-words.bin)
    private let abbrev: SortedTable   // "nh" → vị trí các mục trong words: từ 2-4 chữ viết tắt bằng phụ âm đầu
    public let syllables: Set<String>
    private let byPrefix: [String: [String]]          // "zh" → [zha, zhai, ...]
    public let totalWeight: Double                    // tổng weight: P(w) = weight / totalWeight
    let maxSyllableLength = 6

    /// `directory` chứa pinyin-words.bin và pinyin-abbrev.bin (scripts/build-tables.py từ pinyin.tsv).
    public init(directory: URL) throws {
        words = try SortedTable(contentsOf: directory.appendingPathComponent("pinyin-words.bin"))
        abbrev = try SortedTable(contentsOf: directory.appendingPathComponent("pinyin-abbrev.bin"))
        totalWeight = words.meta
        var syllables = Set<String>()
        for i in 0..<words.count where !words.key(at: i).contains(0x20) {
            syllables.insert(String(decoding: words.key(at: i), as: UTF8.self))
        }
        var byPrefix: [String: [String]] = [:]
        for s in syllables {
            for n in 1..<s.count { byPrefix[String(s.prefix(n)), default: []].append(s) }
        }
        self.syllables = syllables
        // thứ tự cố định (không theo thứ tự duyệt Set) để ứng viên cùng weight luôn ra cùng một thứ tự
        self.byPrefix = byPrefix.mapValues { $0.sorted() }
    }

    func lookup(_ key: String) -> [PinyinEntry] {
        guard let v = words.value(for: key) else { return [] }
        var out: [PinyinEntry] = [], o = 0
        while o < v.count { out.append(Self.entry(v, at: &o)) }
        return out
    }

    func abbreviation(_ key: String) -> [PinyinEntry] {
        guard let refs = abbrev.value(for: key) else { return [] }
        return stride(from: 0, to: refs.count, by: 4).map { i in
            let at = Int(refs.loadUnaligned(fromByteOffset: i, as: UInt32.self).littleEndian)
            let n = Int(words.values(offset: at, count: 1)[0])
            var o = 0
            return Self.entry(words.values(offset: at, count: 1 + n + 4), at: &o)
        }
    }

    func completions(of prefix: String) -> [String] { byPrefix[prefix] ?? [] }

    /// "ni", "ni hao" là đầu (theo âm tiết) của khoá "ni hao ma": cắt nhánh khi dò.
    func hasKeyPrefix(_ prefix: String) -> Bool {
        let p = Array(prefix.utf8)
        let i = words.lowerBound(p)
        guard i < words.count else { return false }
        let k = words.key(at: i)
        return k.count == p.count ? k.elementsEqual(p) : k.starts(with: p + [0x20])
    }

    /// Mục: độ dài từ (1 byte), từ UTF-8, weight (u32).
    private static func entry(_ v: UnsafeRawBufferPointer, at o: inout Int) -> PinyinEntry {
        let n = Int(v[o])
        let word = String(decoding: UnsafeRawBufferPointer(rebasing: v[(o + 1)..<(o + 1 + n)]), as: UTF8.self)
        let weight = Int(v.loadUnaligned(fromByteOffset: o + 1 + n, as: UInt32.self).littleEndian)
        o += 1 + n + 4
        return PinyinEntry(word: word, weight: weight)
    }
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
    /// Có thì ghép câu theo ngữ cảnh (từ trước quyết định từ sau), không thì chỉ theo tần suất.
    public var bigram: BigramModel? { didSet { refresh() } }

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
        var list = PinyinEngine.candidates(for: Array(input), dict: dict, aliases: aliases, bigram: bigram)
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
                    guard dict.hasKeyPrefix(joined) else { continue }
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
                           aliases: [String: [String]] = [:], bigram: BigramModel? = nil) -> [PinyinCandidate] {
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

        // Ghép câu: Viterbi trái→phải trên lưới từ, mỗi vị trí giữ `beam` giả thuyết tốt nhất;
        // điểm = Σ log P(w | từ trước) (bigram, hoặc chỉ unigram khi không có mô hình).
        var matchesAt: [[WordMatch]] = Array(repeating: [], count: n + 1)
        for i in 0..<n {
            matchesAt[i] = words(from: i, in: s, dict: dict, aliases: aliases)
        }
        struct Hyp { let score: Double; let word: String; let prev: (pos: Int, idx: Int)?; let words: Int }
        let beam = 8, alternatives = bigram == nil ? 1 : 5   // giả thuyết giữ mỗi vị trí; từ thay thế xét cho mỗi đoạn
        var hyps: [[Hyp]] = Array(repeating: [], count: n + 1)
        hyps[0] = [Hyp(score: 0, word: "", prev: nil, words: 0)]
        func push(_ h: Hyp, at pos: Int) {
            var list = hyps[pos]
            if list.count >= beam, let worst = list.indices.min(by: { list[$0].score < list[$1].score }) {
                guard h.score > list[worst].score else { return }
                list.remove(at: worst)
            }
            list.append(h)
            hyps[pos] = list
        }
        for i in 0..<n {
            if s[i] == "'" { for h in hyps[i] { push(h, at: i + 1) }; continue }
            guard !hyps[i].isEmpty else { continue }
            for m in matchesAt[i] {
                for e in m.entries.prefix(alternatives) {
                    let p = Double(max(e.weight, 1)) / dict.totalWeight
                    for (hi, h) in hyps[i].enumerated() {
                        let lp = h.prev == nil || bigram == nil ? log(p) : bigram!.logProb(h.word, e.word, unigram: p)
                        push(Hyp(score: h.score + lp, word: e.word, prev: (i, hi), words: h.words + 1), at: m.end)
                    }
                }
            }
        }
        if let last = hyps[n].max(by: { $0.score < $1.score }), last.words > 1 {
            var parts: [String] = []
            var cur: Hyp? = last
            var pos = n
            while let h = cur, let prev = h.prev {
                parts.append(h.word)
                pos = prev.pos
                cur = hyps[pos][prev.idx]
            }
            add(parts.reversed().joined(), n)
        }

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
