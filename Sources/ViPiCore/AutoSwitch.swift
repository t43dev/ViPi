// Tự đổi tiếng Anh / tiếng Việt khi kết thúc một từ, theo độ phổ biến của hai cách đọc cùng một chuỗi phím.
// Cách làm và bảng tần suất lấy từ Vikey (GPL-3.0, github.com/tonyminibot/Vikey, Engine/Engine.cpp
// "Auto switch language from typing behavior"); tần suất gốc: FrequencyWords (Hermit Dave), OpenSubtitles 2018,
// CC BY-SA 4.0. Bản thử nghiệm: chưa có sửa ngược từ trước, cặp từ, hoàn tác bằng Backspace.

public final class AutoSwitch {
    /// Điểm = 10·log10(số lần trên một triệu từ). Khoá tiếng Việt là phím Telex chuẩn hoá ("trên" → "treen").
    private let vietnamese: [String: Int]
    private let english: [String: Int]
    private var previous: [Character]?   // từ ngay trước, cách đúng một dấu cách

    static let prefer = 10           // cách đọc kia phải phổ biến hơn ≥ 10 lần
    static let vietnameseFloor = 10  // từ Việt dùng ≥ ~10 lần/triệu từ thì không bao giờ bỏ
    static let tieAfterEnglish = 5   // ngay sau một từ rõ là tiếng Anh, nghiêng về tiếng Anh ≥ 3 lần là đủ
    static let acronymFloor = 5      // NAS, HDD: chỉ giữ tiếng Việt nếu âm tiết đủ phổ biến

    public init(vietnamese: String, english: String) {
        self.vietnamese = Self.table(vietnamese)
        self.english = Self.table(english)
    }

    private static func table(_ text: String) -> [String: Int] {
        var t: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 2, let score = Int(parts[1]) { t[String(parts[0])] = score }
        }
        return t
    }

    /// Từ vừa kết thúc bằng một dấu cách: nhớ làm ngữ cảnh cho từ sau. Ranh giới khác (Enter, dấu câu, click): quên.
    public func remember(_ keys: [Character]?) { previous = keys }

    /// Đang gõ tiếng Việt, từ `keys` hiện thành `shown`: true = trả lại các phím đã gõ và sang tiếng Anh.
    public func prefersEnglish(keys: [Character], shown: String) -> Bool {
        guard keys.count >= 2, let raw = Self.letters(keys) else { return false }
        let en = english[raw]
        if !shown.unicodeScalars.contains(where: { !$0.isASCII }) {
            // Telex đã nuốt một phím ("less" → "les"): trả lại từ tiếng Anh
            if shown != String(keys) { return en != nil }
            // kiểm tra chính tả đã giữ nguyên phím ngay khi gõ ("server", "testflight"): Telex lẽ ra đã thêm dấu,
            // nên đây là từ nước ngoài → sang tiếng Anh. Từ viết giống nhau ở hai chế độ ("deploy", "ban"): ở lại.
            let marked = TelexEngine.render(keys, modern: false, spellCheck: false)
            return marked != shown && vietnamese[raw] == nil && isForeign(keys: keys, shown: marked)
        }
        let vn = vietnamese[Self.key(shown)]
        // 2 chữ hoa trở lên (NAS, HDD) mà Telex biến thành âm tiết hiếm hoặc không có: viết tắt
        if keys.filter(\.isUppercase).count >= 2, (vn ?? Int.min) < Self.acronymFloor,
           shown.contains(where: { !$0.isASCII && Self.isVowel($0) }) {   // VĐV, HĐND chỉ có đ: giữ
            return true
        }
        guard let en else { return false }   // không phải từ tiếng Anh: để kiểm tra chính tả lo
        guard let vn else { return true }
        // "video call thí": ngay sau một từ tiếng Anh viết giống nhau ở hai chế độ
        if en - vn >= Self.tieAfterEnglish, let p = previous, let praw = Self.letters(p), english[praw] != nil,
           TelexEngine.render(p, modern: false) == String(p), vietnamese[praw] == nil {
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
        guard shown != String(keys), let vn = vietnamese[Self.key(shown)] else { return nil }
        if let en = english[raw] {
            guard vn - en >= Self.prefer else { return nil }
            // "the theme", "video call cos": ngay sau một từ rõ là tiếng Anh thì giữ tiếng Anh
            if let p = previous, let praw = Self.letters(p), let pen = english[praw] {
                let pshown = TelexEngine.render(p, modern: modern)
                let pvn = pshown == String(p) ? nil : vietnamese[Self.key(pshown)]
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
