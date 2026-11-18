import Foundation

/// Cài đặt người dùng, dùng chung giữa app và bàn phím qua App Group.
/// App ghi; bàn phím chỉ đọc (không có Full Access thì iOS không cho bàn phím ghi vào App Group).
/// Tên khoá giống bản Android (Prefs.kt).
enum Prefs {
    static let appGroup = "group.dev.t43.vipi"
    static let shared = UserDefaults(suiteName: appGroup) ?? .standard

    static let modernTone = "modernTone"
    static let spellCheck = "spellCheck"
    static let restore = "restoreNonVietnamese"
    static let traditional = "traditional"
    static let learn = "learnWords"
    static let fullWidth = "fullWidthPunctuation"
    static let haptics = "haptics"
    static let autoCap = "autoCapitalize"
    static let doubleSpace = "doubleSpacePeriod"
    static let keyPopup = "keyPopup"
    /// Thanh gợi ý khi gõ Việt · Anh (tiếng Trung luôn có thanh ứng viên)
    static let vietnameseBar = "vietnameseBar"
    /// Gợi ý từ trên thanh (hoàn thành từ đang gõ, từ tiếp theo) khi gõ Việt · Anh
    static let suggestions = "suggestions"
    /// Tự sửa lỗi chạm lệch phím lúc kết thúc từ tiếng Anh, và vùng chạm phím theo câu đang gõ
    static let autoCorrect = "autoCorrect"
    static let fuzzy = "fuzzy"
    /// "system" | "light" | "dark"
    static let theme = "theme"
    /// iPad: "split" | "wide"
    static let largeLayout = "largeLayout"
    /// App bấm "Clear learned words": thời điểm yêu cầu; bàn phím xoá ở lần mở sau rồi ghi nhớ đã xử lý.
    static let clearLearnedAt = "clearLearnedAt"

    private static let defaults: [String: Any] = [
        modernTone: false, spellCheck: true, restore: true, traditional: false, learn: true, fullWidth: true,
        haptics: true, autoCap: true, doubleSpace: true, keyPopup: true, vietnameseBar: true, suggestions: true, autoCorrect: true,
        theme: "system", largeLayout: "wide",
    ]

    static func bool(_ key: String) -> Bool {
        shared.object(forKey: key) as? Bool ?? (defaults[key] as? Bool ?? false)
    }

    static func string(_ key: String) -> String {
        shared.string(forKey: key) ?? (defaults[key] as? String ?? "")
    }

    static var fuzzyRules: [String] {
        get { shared.stringArray(forKey: fuzzy) ?? [] }
        set { shared.set(newValue, forKey: fuzzy) }
    }

    static let privacyURL = URL(string: "https://vipi.t43.app/privacy")!
    static let sourceURL = URL(string: "https://github.com/t43dev/ViPi")!
}
