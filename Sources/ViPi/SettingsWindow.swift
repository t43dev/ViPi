import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?
    private let prefs: Preferences
    private let updater: Updater
    private let onRecording: (Bool) -> Void
    private let showSecureInput: () -> Void

    init(prefs: Preferences, updater: Updater, onRecording: @escaping (Bool) -> Void, showSecureInput: @escaping () -> Void) {
        self.prefs = prefs
        self.updater = updater
        self.onRecording = onRecording
        self.showSecureInput = showSecureInput
    }

    func show() {
        if window == nil {
            let view = SettingsView(prefs: prefs, updater: updater, onRecording: onRecording, showSecureInput: showSecureInput)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        relocalize()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func relocalize() { window?.title = tr("ViPi Settings") }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var updater: Updater
    let onRecording: (Bool) -> Void
    let showSecureInput: () -> Void
    @State var tab: Int

    init(prefs: Preferences, updater: Updater, onRecording: @escaping (Bool) -> Void,
         showSecureInput: @escaping () -> Void, initialTab: Int = 0) {
        self.prefs = prefs
        self.updater = updater
        self.onRecording = onRecording
        self.showSecureInput = showSecureInput
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            general.tabItem { Label(tr("General"), systemImage: "gearshape") }.tag(0)
            vietnamese.tabItem { Label(tr("Vietnamese"), systemImage: "character.book.closed") }.tag(1)
            chinese.tabItem { Label(tr("Chinese"), systemImage: "character") }.tag(2)
            MacrosView(prefs: prefs).tabItem { Label(tr("Text Shortcuts"), systemImage: "text.badge.plus") }.tag(3)
        }
        .padding(20)
        .frame(width: 560, height: 500)
    }

    private var general: some View {
        Form {
            Section {
                Picker(tr("Language"), selection: $prefs.language) {
                    ForEach(UILanguage.allCases) { Text($0.name).tag($0) }
                }
                Picker(tr("Appearance"), selection: $prefs.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                LabeledContent(tr("Switch input")) {
                    ShortcutRecorder(shortcut: $prefs.shortcut, onRecording: onRecording)
                }
                caption(tr("Press once to go back to the previous input, twice quickly for the next one. Use two or more modifier keys (pressed together, then released), or modifiers plus a key such as Control+Space."))
                Button(tr("Reset to Control+Shift")) { prefs.shortcut = .default }
                    .disabled(prefs.shortcut == .default)
            }
            Section {
                Toggle(tr("Launch at login"), isOn: $prefs.launchAtLogin)
                Toggle(tr("Automatically install updates"), isOn: $updater.autoInstall)
                    .disabled(!updater.isReleaseBuild)
                LabeledContent(tr("Secure Input")) {
                    Button(tr("Open Monitor…"), action: showSecureInput)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var vietnamese: some View {
        Form {
            Section {
                Toggle(tr("Check spelling"), isOn: $prefs.spellCheck)
                caption(tr("Only add tone and vowel marks where they make a valid Vietnamese syllable, so English words such as “class” or “window” stay as typed. Turn off to apply every Telex key, like UniKey without spell check."))
                Toggle(tr("Restore non-Vietnamese words"), isOn: $prefs.restoreNonVietnamese)
                    .disabled(!prefs.spellCheck)
                caption(tr("When a word ends and the result is not a real Vietnamese syllable, retype the keys you pressed: user, data, more."))
            }
            Section {
                Picker(tr("Tone placement"), selection: $prefs.modernToneStyle) {
                    Text(tr("Classic (hòa, khỏe, thúy)")).tag(false)
                    Text(tr("Modern (hoà, khoẻ, thuý)")).tag(true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var chinese: some View {
        Form {
            Section {
                Toggle(tr("Full-width punctuation (，。？！)"), isOn: $prefs.fullWidthPunctuation)
            }
        }
        .formStyle(.grouped)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct MacrosView: View {
    @ObservedObject var prefs: Preferences
    @State private var selection: Macro.ID?

    /// Một bảng chung, bật riêng cho từng bộ gõ (bộ gõ Trung dùng Space để chọn chữ nên không áp dụng).
    private var enabled: Bool { prefs.macrosEnabled || prefs.macrosInEnglish }

    var body: some View {
        Form {
            Section {
                Toggle(tr("Use in Vietnamese"), isOn: $prefs.macrosEnabled)
                Toggle(tr("Use in English"), isOn: $prefs.macrosInEnglish)
                Text(tr("Type a shortcut as its own word, then Space, Return or Tab, to replace it with the full text (call2vn@ stays as typed). Letter case follows what you type: vn → Việt Nam, VN → VIỆT NAM. Not used in Chinese mode, where Space picks a candidate."))
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section { table }
        }
        .formStyle(.grouped)
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 8) {
            Table(prefs.macros, selection: $selection) {
                TableColumn(tr("Shortcut")) { m in TextField(tr("e.g. vn"), text: field(m.id, \.key)) }
                    .width(120)
                TableColumn(tr("Replace with")) { m in TextField(tr("e.g. Việt Nam"), text: field(m.id, \.text)) }
            }
            .labelsHidden()   // trong Form, nhãn TextField hiện cạnh ô: chỉ dùng làm gợi ý
            .frame(height: 170)
            .disabled(!enabled)
            HStack(spacing: 4) {
                Button { prefs.macros.append(Macro(key: "", text: "")) } label: { Image(systemName: "plus") }
                Button {
                    prefs.macros.removeAll { $0.id == selection }
                    selection = nil
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
                Text(tr("%@ shortcuts", String(prefs.macros.count))).font(.caption).foregroundColor(.secondary)
            }
            .disabled(!enabled)
        }
    }
}

extension MacrosView {
    private func field(_ id: Macro.ID, _ path: WritableKeyPath<Macro, String>) -> Binding<String> {
        Binding(
            get: { prefs.macros.first { $0.id == id }?[keyPath: path] ?? "" },
            set: { value in
                if let i = prefs.macros.firstIndex(where: { $0.id == id }) { prefs.macros[i][keyPath: path] = value }
            })
    }
}

/// Bấm để ghi phím tắt: nhấn tổ hợp phím bổ trợ rồi nhả, hoặc phím bổ trợ + một phím. Esc để huỷ.
struct ShortcutRecorder: View {
    @Binding var shortcut: SwitchShortcut
    let onRecording: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var peak: NSEvent.ModifierFlags = []

    var body: some View {
        Button(recording ? tr("Press the new shortcut…") : shortcut.label) { recording ? stop() : start() }
            .frame(minWidth: 180)
            .onDisappear { stop() }
    }

    private func start() {
        recording = true
        peak = []
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.type == .keyDown {
                if event.keyCode == 53, mods.isEmpty { stop(); return nil }   // Esc: huỷ
                // phải có ⌃, ⌥ hoặc ⌘, nếu không sẽ chặn mất chữ đang gõ
                guard !mods.subtracting(.shift).isEmpty else { NSSound.beep(); return nil }
                shortcut = SwitchShortcut(flags: Self.cgFlags(mods), keyCode: Int(event.keyCode), keyName: Self.keyName(event))
                stop()
                return nil
            }
            if mods.isEmpty {
                // nhả hết: nhận tổ hợp vừa nhấn nếu có từ hai phím bổ trợ
                if Self.count(peak) >= 2 {
                    shortcut = SwitchShortcut(flags: Self.cgFlags(peak))
                    stop()
                }
                peak = []
            } else if Self.count(mods) >= Self.count(peak) {
                peak = mods
            }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { onRecording(false) }
        recording = false
    }

    private static func count(_ m: NSEvent.ModifierFlags) -> Int {
        [NSEvent.ModifierFlags.control, .option, .shift, .command].filter { m.contains($0) }.count
    }

    private static func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.command) { f.insert(.maskCommand) }
        return f
    }

    private static func keyName(_ e: NSEvent) -> String {
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 50: "`",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
                                       98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let n = names[e.keyCode] { return n }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
