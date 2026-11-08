// Tự đổi tiếng Anh / tiếng Việt khi kết thúc một từ, theo độ phổ biến của hai cách đọc cùng một chuỗi phím.
// Cách làm và bảng tần suất lấy từ Vikey (GPL-3.0, github.com/tonyminibot/Vikey, Engine/Engine.cpp
// "Auto switch language from typing behavior"); tần suất gốc: FrequencyWords (Hermit Dave), OpenSubtitles 2018,
// CC BY-SA 4.0. Cặp từ (Vikey D30, D34): từ đọc được cả hai cách (bus/bú, been/bên) theo từ đứng trước trong văn bản
// thật (FineWeb-2 / FineWeb, ODC-By; HPLT 2, CC0; MADLAD-400, ODC-By; Reddit). Dạng từ tiếng Anh (D60): SCOWL en_US,
// © Kevin Atkinson. Sửa ngược từ ngay trước khi đã chắc là tiếng Anh (D8, D13). Chưa có: bộ ba từ.

import Foundation

public final class AutoSwitch {
    /// Điểm = 10·log10(số lần trên một triệu từ). Khoá tiếng Việt là phím Telex chuẩn hoá ("trên" → "treen").
    private let vietnameseTable: SortedTable
    private let englishTable: SortedTable
    private let pairsTable: SortedTable?   // "từ trước<TAB>từ sau" → 8·log2(số lần)
    /// Từ ngay trước (cách đúng một dấu cách): phím đã gõ, có gõ ở chế độ tiếng Việt không,
    /// và chữ đang hiện nếu bộ gõ không đụng tới lúc kết thúc từ.
    private var previous: (keys: [Character], vietnamese: Bool, shown: String?)?

    static let prefer = 10           // cách đọc kia phải phổ biến hơn ≥ 10 lần
    static let vietnameseFloor = 10  // từ Việt dùng ≥ ~10 lần/triệu từ thì không bao giờ bỏ
    static let tieAfterEnglish = 5   // ngay sau một từ rõ là tiếng Anh, nghiêng về tiếng Anh ≥ 3 lần là đủ
    static let acronymFloor = 5      // NAS, HDD: chỉ giữ tiếng Việt nếu âm tiết đủ phổ biến
    static let pairOverridesTie = 10 // cặp từ nghiêng tiếng Việt ≥ 10 lần thắng luật "ngay sau từ tiếng Anh" (D34)
    static let pairWeight = 2.0, pairMinCount = 3
    static let lookBackLean = 10     // từ trước chỉ được sửa khi tiếng Anh phổ biến hơn ≥ 10 lần: "bên server", "cả server" giữ nguyên
    static let plainMargin = 15      // "thí create": từ trước phải nghiêng tiếng Anh ~30 lần mới đủ làm từ sau sang tiếng Anh
    static let capsFloor = 15        // cả từ viết hoa chỉ đổi sang âm tiết phổ biến (IRS giữ nguyên, không thành Í)

    /// `directory` chứa autoswitch-vi.bin, autoswitch-en.bin và autoswitch-pairs.bin (scripts/build-tables.py).
    public init(directory: URL) throws {
        vietnameseTable = try SortedTable(contentsOf: directory.appendingPathComponent("autoswitch-vi.bin"))
        englishTable = try SortedTable(contentsOf: directory.appendingPathComponent("autoswitch-en.bin"))
        pairsTable = try? SortedTable(contentsOf: directory.appendingPathComponent("autoswitch-pairs.bin"))
    }

    private func vietnamese(_ key: String) -> Int? { vietnameseTable.value(for: key).map { Int(Int8(bitPattern: $0[0])) } }
    private func english(_ word: String) -> Int? { englishTable.value(for: word).map { Int(Int8(bitPattern: $0[0])) } }

    /// Điểm của `shown` nếu đó đúng là một chữ có thật: "rêts" cùng khoá với "rết" nhưng không phải chữ nào (D60).
    private func wordScore(_ shown: String) -> Int? {
        let k = Self.key(shown), keys = Array(k), low = shown.lowercased()
        guard TelexEngine.render(keys, modern: false) == low || TelexEngine.render(keys, modern: true) == low else { return nil }
        return vietnamese(k)
    }

    /// Từ vừa kết thúc bằng một dấu cách: nhớ làm ngữ cảnh cho từ sau (`vietnamese`: gõ ở chế độ tiếng Việt;
    /// `shown`: chữ đang hiện nếu bộ gõ không sửa gì lúc kết thúc từ). Ranh giới khác (Enter, dấu câu, click): quên.
    public func remember(_ keys: [Character]?, vietnamese: Bool = false, shown: String? = nil) {
        previous = keys.map { ($0, vietnamese, shown) }
    }

    /// Từ trước đang hiện chữ Việt mà đọc tiếng Anh phổ biến hơn hẳn ("thí" = this): (điểm Anh, điểm Việt).
    private func ambiguousPrevious() -> (en: Int, vn: Int)? {
        guard let p = previous, p.vietnamese, let shown = p.shown, shown != String(p.keys),
              let praw = Self.letters(p.keys), let en = english(praw), let vn = wordScore(shown),
              en >= vn + Self.lookBackLean else { return nil }
        return (en, vn)
    }

    /// `keys` vừa sang tiếng Anh: từ ngay trước cũng trả lại phím đã gõ ("thí makes" → "this makes", D8).
    /// Trả (chữ đang hiện, các phím). Từ viết tắt không nói gì về từ trước ("bên USA", D42).
    public func lookBack(keys: [Character]) -> (shown: String, keys: String)? {
        guard Self.capitals(keys) < 2, let raw = Self.letters(keys), english(raw) != nil, ambiguousPrevious() != nil,
              let p = previous, let shown = p.shown else { return nil }
        return (shown, String(p.keys))
    }

    /// "ddc" → "đc": viết tắt chỉ có đ và phụ âm mà tin nhắn hay dùng (D27).
    public func shorthand(keys: [Character]) -> String? {
        guard let raw = Self.letters(keys), raw.hasPrefix("dd"), !raw.contains(where: { "aeiouy".contains($0) }),
              english(raw) == nil, vietnamese(raw) != nil else { return nil }
        return TelexEngine.render(keys, modern: false, spellCheck: false)
    }

    /// Chữ hiện ra của các chữ cái: chính nó, hoặc cách đọc tiếng Việt (phải là từ có thật).
    private func surface(_ letters: String, vietnamese: Bool) -> String? {
        guard vietnamese else { return letters }
        let shown = TelexEngine.render(Array(letters), modern: false)
        return shown != letters && self.vietnamese(Self.key(shown)) != nil ? shown : nil
    }

    private func pairCount(_ key: String) -> Int {
        guard let v = pairsTable?.value(for: key) else { return 0 }
        return Int(pow(2, Double(v[0]) / 8).rounded())
    }

    /// Cặp từ (D30): > 0 khi cách đọc tiếng Việt của `letters` đứng sau từ trước nhiều hơn cách đọc tiếng Anh
    /// (10 = gấp 10 lần, nhân trọng số 2), < 0 thì ngược lại, 0 khi không đủ dữ liệu.
    func pairVote(previous p: (keys: [Character], vietnamese: Bool, shown: String?)?, _ letters: String) -> Int {
        guard pairsTable != nil, let p, let praw = Self.letters(p.keys) else { return 0 }
        let prevVietnamese = p.vietnamese && TelexEngine.render(Array(praw), modern: false) != praw
        guard let before = surface(praw, vietnamese: prevVietnamese), let vn = surface(letters, vietnamese: true) else { return 0 }
        let cv = pairCount(before + "\t" + vn), ce = pairCount(before + "\t" + letters)
        guard cv + ce >= Self.pairMinCount else { return 0 }
        let v = min(30, max(-30, 10 * log10((Double(cv) + 0.5) / (Double(ce) + 0.5))))
        return Int((v * Self.pairWeight).rounded())
    }

    /// Đang gõ tiếng Việt, từ `keys` hiện thành `shown`: true = trả lại các phím đã gõ và sang tiếng Anh.
    public func prefersEnglish(keys: [Character], shown: String) -> Bool {
        guard keys.count >= 2, let raw = Self.letters(keys) else { return false }
        let en = english(raw)
        if !shown.unicodeScalars.contains(where: { !$0.isASCII }) {
            // Telex đã nuốt một phím ("less" → "les", "currentState" → "curentState"): trả lại từ tiếng Anh, viết tắt
            // ("ASUS") hay từ không thể là một âm tiết, trừ khi chữ còn lại đã là tiếng Anh ("tessting" → "testing")
            if shown != String(keys) {
                return en != nil || Self.capitals(keys) >= 2
                    || (english(shown.lowercased()) == nil && Self.literalShape(keys, zIsTone: false))
            }
            // kiểm tra chính tả đã giữ nguyên phím ngay khi gõ ("server", "testflight"): Telex lẽ ra đã thêm dấu,
            // nên đây là từ nước ngoài → sang tiếng Anh. Từ viết giống nhau ở hai chế độ ("deploy", "ban"): ở lại.
            // Từ tiếng Anh có trong danh sách ("work" → ưởk) thì sang luôn, như Vikey.
            let marked = TelexEngine.render(keys, modern: false, spellCheck: false)
            guard marked != shown, vietnamese(raw) == nil else {
                // "this create": từ chỉ có tiếng Anh ngay sau một từ gần như chắc là tiếng Anh (D13)
                guard en != nil, vietnamese(raw) == nil, let p = ambiguousPrevious() else { return false }
                return p.en >= p.vn + Self.plainMargin
            }
            return en != nil || isForeign(keys: keys, shown: marked)
        }
        let vn = wordScore(shown)
        // 2 chữ hoa trở lên (NAS, HDD) mà Telex biến thành âm tiết hiếm hoặc không có: viết tắt
        if Self.capitals(keys) >= 2, (vn ?? Int.min) < Self.acronymFloor,
           shown.contains(where: { !$0.isASCII && Self.isVowel($0) }) {   // VĐV, HĐND chỉ có đ: giữ
            return true
        }
        // không phải từ tiếng Anh: để kiểm tra chính tả lo, trừ tên riêng không thể là một âm tiết ("Momo" → Môm)
        guard let en else { return vn == nil && Self.literalShape(keys, zIsTone: true) && isForeign(keys: keys, shown: shown) }
        guard let vn else { return true }
        // cặp từ: "cho con bus" → bú, "đi xe bus" → bus
        let vote = pairVote(previous: previous, raw)
        if vote != 0 { return en - vn - vote >= Self.prefer && (vn < Self.vietnameseFloor || vote <= -Self.prefer) }
        // "video call thí": ngay sau một từ tiếng Anh viết giống nhau ở hai chế độ
        if en - vn >= Self.tieAfterEnglish, let p = previous?.keys, let praw = Self.letters(p), english(praw) != nil,
           TelexEngine.render(p, modern: false) == String(p), vietnamese(praw) == nil {
            return true
        }
        return vn < Self.vietnameseFloor && en - vn >= Self.prefer
    }

    /// Đang gõ tiếng Việt, kiểm tra chính tả đã trả lại các phím của một từ không có thật: từ nước ngoài
    /// (TestFlight, analytics) thì sang tiếng Anh; gõ nhầm tiếng Việt (có â ê ô ă ơ ư đ, một cụm nguyên âm) thì ở lại.
    public func isForeign(keys: [Character], shown: String) -> Bool {
        guard keys.count >= 3 else { return false }
        var groups = 0, inVowel = false
        for k in keys {
            let v = "aeiouy".contains(k.lowercased())
            if v, !inVowel { groups += 1 }
            inVowel = v
        }
        return groups > 1 || !shown.contains { Vietnamese.decompose($0).map { "âêôăơưđ".contains($0.0) } ?? false }
    }

    /// Đang gõ tiếng Anh: chữ tiếng Việt thay cho các phím đã gõ ("treen" → "trên"), nil = giữ tiếng Anh.
    public func vietnamese(for keys: [Character], modern: Bool) -> String? {
        guard keys.count >= 2, let raw = Self.letters(keys) else { return nil }
        if let s = shorthand(keys: keys) { return s }
        let shown = TelexEngine.render(keys, modern: modern)
        guard shown != String(keys), let vn = wordScore(shown) else { return nil }
        let en = english(raw)
        // viết tắt, tên biến; riêng Caps Lock gõ tiếng Việt thì đổi: dấu Telex rõ ràng (THOONG) hoặc ngay sau từ viết hoa (D41)
        if Self.capitals(keys) >= 2 {
            let allCaps = { (k: [Character]) in k.count >= 2 && k.allSatisfy(\.isUppercase) }
            let afterCaps = previous.map { allCaps($0.keys) } ?? false
            guard allCaps(keys), en == nil, vn >= Self.capsFloor, (keys.count >= 4 && Self.telexMarked(raw)) || afterCaps else { return nil }
        }
        if let en {
            // cặp từ: "cho con bus" → bú; từ trước gõ ở chế độ tiếng Anh nên đọc như chữ đã gõ
            let vote = pairVote(previous: previous.map { ($0.keys, false, nil) }, raw)
            guard vn - en + vote >= Self.prefer else { return nil }
            // "the theme", "video call cos": ngay sau một từ rõ là tiếng Anh thì giữ tiếng Anh,
            // trừ khi cặp từ nói rõ là tiếng Việt ("test có work", D34)
            if vote < Self.pairOverridesTie, let p = previous?.keys, let praw = Self.letters(p), let pen = english(praw) {
                let pshown = TelexEngine.render(p, modern: modern)
                let pvn = pshown == String(p) ? nil : wordScore(pshown)
                if pvn == nil || pen - pvn! >= Self.prefer { return nil }
            }
        }
        return shown
    }

    /// Chữ thường a-z của các phím, nil nếu có phím không phải chữ cái.
    static func letters(_ keys: [Character]) -> String? {
        let s = String(keys).lowercased()
        return s.allSatisfy { $0.isASCII && $0.isLetter } ? s : nil
    }

    /// Số chữ hoa; DD tính là một (Đ): "DDaf Nawngx" là Đà Nẵng, còn DDR, DDoS vẫn là hai (D39).
    static func capitals(_ keys: [Character]) -> Int {
        keys.indices.filter { keys[$0].isUppercase && !(keys[$0] == "D" && $0 > 0 && keys[$0 - 1] == "D") }.count
    }

    /// Có dấu Telex rõ ràng: nguyên âm hoặc d gõ đôi, w sau nguyên âm.
    static func telexMarked(_ raw: String) -> Bool {
        let a = Array(raw)
        return zip(a, a.dropFirst()).contains { ($0 == $1 && "aeod".contains($0)) || ($1 == "w" && "aou".contains($0)) }
    }

    /// Dáng không thể là một âm tiết tiếng Việt: chữ hoa giữa từ, hoặc hai cụm nguyên âm cách nhau bởi phụ âm thật
    /// (phím thanh và w không tính; `zIsTone`: z đang là phím bỏ dấu). Có w hay aa/ee/oo/dd thì vẫn là người đang gõ Telex.
    static func literalShape(_ keys: [Character], zIsTone: Bool) -> Bool {
        let low = keys.map { Character($0.lowercased()) }
        let capital = zip(keys, keys.dropFirst()).contains { !$0.isUppercase && $1.isUppercase }
        if capital && !zIsTone { return true }   // Telex đã nuốt phím: currentWindow vẫn là tên biến dù có w
        if zip(low, low.dropFirst()).contains(where: { $1 == "w" || ($0 == $1 && "aeod".contains($0)) }) { return false }
        if capital { return true }
        var sawVowel = false, afterConsonant = false
        for c in low {
            if "aeiouy".contains(c) {
                if afterConsonant { return true }
                sawVowel = true
            } else if sawVowel, !"sfrxjw".contains(c), !(zIsTone && c == "z") {
                afterConsonant = true
            }
        }
        return false
    }

    static func key(_ word: String) -> String { String(TelexEngine.telexKeys(for: word.lowercased())) }

    private static func isVowel(_ c: Character) -> Bool {
        guard let (letter, _) = Vietnamese.decompose(c) else { return false }
        return "aăâeêioôơuưy".contains(letter)
    }
}
