// Tự đổi tiếng Anh / tiếng Việt khi kết thúc một từ, theo độ phổ biến của hai cách đọc cùng một chuỗi phím.
// Cách làm và bảng tần suất lấy từ Vikey (GPL-3.0, github.com/tonyminibot/Vikey, Engine/Engine.cpp
// "Auto switch language from typing behavior"); tần suất gốc: FrequencyWords (Hermit Dave), OpenSubtitles 2018,
// CC BY-SA 4.0. Cặp từ (Vikey D30, D34): từ đọc được cả hai cách (bus/bú, been/bên) theo từ đứng trước trong văn bản
// thật (FineWeb-2 / FineWeb, ODC-By; HPLT 2, CC0; MADLAD-400, ODC-By; Reddit). Chưa có: sửa ngược từ trước, bộ ba từ.

import Foundation

public final class AutoSwitch {
    /// Điểm = 10·log10(số lần trên một triệu từ). Khoá tiếng Việt là phím Telex chuẩn hoá ("trên" → "treen").
    private let vietnameseTable: SortedTable
    private let englishTable: SortedTable
    private let pairsTable: SortedTable?   // "từ trước<TAB>từ sau" → 8·log2(số lần)
    /// Từ ngay trước (cách đúng một dấu cách): phím đã gõ, và có gõ ở chế độ tiếng Việt không.
    private var previous: (keys: [Character], vietnamese: Bool)?

    static let prefer = 10           // cách đọc kia phải phổ biến hơn ≥ 10 lần
    static let vietnameseFloor = 10  // từ Việt dùng ≥ ~10 lần/triệu từ thì không bao giờ bỏ
    static let tieAfterEnglish = 5   // ngay sau một từ rõ là tiếng Anh, nghiêng về tiếng Anh ≥ 3 lần là đủ
    static let acronymFloor = 5      // NAS, HDD: chỉ giữ tiếng Việt nếu âm tiết đủ phổ biến
    static let pairOverridesTie = 10 // cặp từ nghiêng tiếng Việt ≥ 10 lần thắng luật "ngay sau từ tiếng Anh" (D34)
    static let pairWeight = 2.0, pairMinCount = 3

    /// `directory` chứa autoswitch-vi.bin, autoswitch-en.bin và autoswitch-pairs.bin (scripts/build-tables.py).
    public init(directory: URL) throws {
        vietnameseTable = try SortedTable(contentsOf: directory.appendingPathComponent("autoswitch-vi.bin"))
        englishTable = try SortedTable(contentsOf: directory.appendingPathComponent("autoswitch-en.bin"))
        pairsTable = try? SortedTable(contentsOf: directory.appendingPathComponent("autoswitch-pairs.bin"))
    }

    private func vietnamese(_ key: String) -> Int? { vietnameseTable.value(for: key).map { Int(Int8(bitPattern: $0[0])) } }
    private func english(_ word: String) -> Int? { englishTable.value(for: word).map { Int(Int8(bitPattern: $0[0])) } }

    /// Từ vừa kết thúc bằng một dấu cách: nhớ làm ngữ cảnh cho từ sau (`vietnamese`: gõ ở chế độ tiếng Việt).
    /// Ranh giới khác (Enter, dấu câu, click): quên.
    public func remember(_ keys: [Character]?, vietnamese: Bool = false) {
        previous = keys.map { ($0, vietnamese) }
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
    func pairVote(previous p: (keys: [Character], vietnamese: Bool)?, _ letters: String) -> Int {
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
            // Telex đã nuốt một phím ("less" → "les"): trả lại từ tiếng Anh
            if shown != String(keys) { return en != nil }
            // kiểm tra chính tả đã giữ nguyên phím ngay khi gõ ("server", "testflight"): Telex lẽ ra đã thêm dấu,
            // nên đây là từ nước ngoài → sang tiếng Anh. Từ viết giống nhau ở hai chế độ ("deploy", "ban"): ở lại.
            // Từ tiếng Anh có trong danh sách ("work" → ưởk) thì sang luôn, như Vikey.
            let marked = TelexEngine.render(keys, modern: false, spellCheck: false)
            guard marked != shown, vietnamese(raw) == nil else { return false }
            return en != nil || isForeign(keys: keys, shown: marked)
        }
        let vn = vietnamese(Self.key(shown))
        // 2 chữ hoa trở lên (NAS, HDD) mà Telex biến thành âm tiết hiếm hoặc không có: viết tắt
        if keys.filter(\.isUppercase).count >= 2, (vn ?? Int.min) < Self.acronymFloor,
           shown.contains(where: { !$0.isASCII && Self.isVowel($0) }) {   // VĐV, HĐND chỉ có đ: giữ
            return true
        }
        guard let en else { return false }   // không phải từ tiếng Anh: để kiểm tra chính tả lo
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
        if keys.filter(\.isUppercase).count >= 2 { return nil }   // viết tắt, tên biến, Caps Lock
        let shown = TelexEngine.render(keys, modern: modern)
        guard shown != String(keys), let vn = vietnamese(Self.key(shown)) else { return nil }
        if let en = english(raw) {
            // cặp từ: "cho con bus" → bú; từ trước gõ ở chế độ tiếng Anh nên đọc như chữ đã gõ
            let vote = pairVote(previous: previous.map { ($0.keys, false) }, raw)
            guard vn - en + vote >= Self.prefer else { return nil }
            // "the theme", "video call cos": ngay sau một từ rõ là tiếng Anh thì giữ tiếng Anh,
            // trừ khi cặp từ nói rõ là tiếng Việt ("test có work", D34)
            if vote < Self.pairOverridesTie, let p = previous?.keys, let praw = Self.letters(p), let pen = english(praw) {
                let pshown = TelexEngine.render(p, modern: modern)
                let pvn = pshown == String(p) ? nil : vietnamese(Self.key(pshown))
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

    static func key(_ word: String) -> String { String(TelexEngine.telexKeys(for: word.lowercased())) }

    private static func isVowel(_ c: Character) -> Bool {
        guard let (letter, _) = Vietnamese.decompose(c) else { return false }
        return "aăâeêioôơuưy".contains(letter)
    }
}
