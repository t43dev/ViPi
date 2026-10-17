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
    @Published var macrosEnabled: Bool { didSet { save(macrosEnabled, "macrosEnabled") } }
    @Published var macros: [Macro] { didSet { saveJSON(macros, "macros") } }
    @Published var fullWidthPunctuation: Bool { didSet { save(fullWidthPunctuation, "fullWidthPunctuation") } }

    init() {
        defaults.register(defaults: [
            "modernToneStyle": false, "spellCheck": true, "restoreNonVietnamese": true,
            "macrosEnabled": true, "fullWidthPunctuation": true,
        ])
        shortcut = Self.loadJSON(defaults, "switchShortcut") ?? .default
        modernToneStyle = defaults.bool(forKey: "modernToneStyle")
        spellCheck = defaults.bool(forKey: "spellCheck")
        restoreNonVietnamese = defaults.bool(forKey: "restoreNonVietnamese")
        macrosEnabled = defaults.bool(forKey: "macrosEnabled")
        macros = Self.loadJSON(defaults, "macros") ?? [
            Macro(key: "vn", text: "Việt Nam"), Macro(key: "ko", text: "không"), Macro(key: "đc", text: "được"),
        ]
        fullWidthPunctuation = defaults.bool(forKey: "fullWidthPunctuation")
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
