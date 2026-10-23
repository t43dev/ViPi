import AppKit
import ServiceManagement
import ViPiCore

/// Phím đổi bộ gõ: chỉ phím bổ trợ (nhấn cùng lúc rồi nhả, vd ⌃⇧) hoặc phím bổ trợ + một phím (vd ⌃Space).
struct SwitchShortcut: Codable, Equatable {
    var modifiers: UInt64          // CGEventFlags trong ⌃⌥⇧⌘
    var keyCode: Int?
    var keyName: String?

    static let `default` = SwitchShortcut(flags: [.maskControl, .maskShift])
    static let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    init(flags: CGEventFlags, keyCode: Int? = nil, keyName: String? = nil) {
        modifiers = flags.intersection(Self.relevant).rawValue
        self.keyCode = keyCode
        self.keyName = keyName
    }

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    /// "Control+Shift", "Control+Space"
    var label: String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("Control") }
        if flags.contains(.maskAlternate) { parts.append("Option") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Command") }
        if let keyName { parts.append(keyName) }
        return parts.joined(separator: "+")
    }
}

/// Giao diện sáng/tối của các cửa sổ ViPi (Settings, About, khung chọn chữ Hán…).
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return tr("System")
        case .light: return tr("Light")
        case .dark: return tr("Dark")
        }
    }
    /// nil = theo macOS
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct Macro: Codable, Identifiable, Equatable {
    var id = UUID()
    var key: String
    var text: String
}

/// Cài đặt của ViPi, lưu trong UserDefaults; mỗi thay đổi gọi `onChange` để áp vào bộ gõ.
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?

    @Published var shortcut: SwitchShortcut { didSet { saveJSON(shortcut, "switchShortcut") } }
    @Published var modernToneStyle: Bool { didSet { save(modernToneStyle, "modernToneStyle") } }
    @Published var spellCheck: Bool { didSet { save(spellCheck, "spellCheck") } }
    @Published var restoreNonVietnamese: Bool { didSet { save(restoreNonVietnamese, "restoreNonVietnamese") } }
    @Published var macrosEnabled: Bool { didSet { save(macrosEnabled, "macrosEnabled") } }      // gõ tắt khi gõ tiếng Việt
    @Published var macrosInEnglish: Bool { didSet { save(macrosInEnglish, "macrosInEnglish") } }
    @Published var macros: [Macro] { didSet { saveJSON(macros, "macros") } }
    @Published var fullWidthPunctuation: Bool { didSet { save(fullWidthPunctuation, "fullWidthPunctuation") } }
    @Published var traditionalChinese: Bool { didSet { save(traditionalChinese, "traditionalChinese") } }  // đầu ra phồn thể
    @Published var learnWords: Bool { didSet { save(learnWords, "learnWords") } }                          // học từ đã chọn
    @Published var fuzzyRules: Set<String> { didSet { saveJSON(fuzzyRules, "fuzzyRules") } }               // id FuzzyRule đang bật
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance"); onChange?() }
    }
    @Published var language: UILanguage {
        didSet {
            UILanguage.current = language
            defaults.set(language.rawValue, forKey: "uiLanguage")
            onChange?()
        }
    }

    init() {
        defaults.register(defaults: [
            "modernToneStyle": false, "spellCheck": true, "restoreNonVietnamese": true,
            "macrosEnabled": true, "macrosInEnglish": false, "fullWidthPunctuation": true,
            "traditionalChinese": false, "learnWords": true,
        ])
        shortcut = Self.loadJSON(defaults, "switchShortcut") ?? .default
        modernToneStyle = defaults.bool(forKey: "modernToneStyle")
        spellCheck = defaults.bool(forKey: "spellCheck")
        restoreNonVietnamese = defaults.bool(forKey: "restoreNonVietnamese")
        macrosEnabled = defaults.bool(forKey: "macrosEnabled")
        macrosInEnglish = defaults.bool(forKey: "macrosInEnglish")
        macros = Self.loadJSON(defaults, "macros") ?? [
            Macro(key: "vn", text: "Việt Nam"), Macro(key: "ko", text: "không"), Macro(key: "đc", text: "được"),
        ]
        fullWidthPunctuation = defaults.bool(forKey: "fullWidthPunctuation")
        traditionalChinese = defaults.bool(forKey: "traditionalChinese")
        learnWords = defaults.bool(forKey: "learnWords")
        fuzzyRules = Self.loadJSON(defaults, "fuzzyRules") ?? []
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init(rawValue:)) ?? .system
        language = defaults.string(forKey: "uiLanguage").flatMap(UILanguage.init(rawValue:)) ?? .system
        UILanguage.current = language
    }

    var macroTable: MacroTable { MacroTable(macros.map { ($0.key.trimmingCharacters(in: .whitespaces), $0.text) }) }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("ViPi: launch at login \(newValue): \(error)")
            }
        }
    }

    private func save(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    private func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
        onChange?()
    }

    private static func loadJSON<T: Decodable>(_ defaults: UserDefaults, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
