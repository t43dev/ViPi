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
            w.title = "ViPi Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
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
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            vietnamese.tabItem { Label("Vietnamese", systemImage: "character.book.closed") }.tag(1)
            MacrosView(prefs: prefs).tabItem { Label("Text Shortcuts", systemImage: "text.badge.plus") }.tag(2)
            chinese.tabItem { Label("Chinese", systemImage: "character") }.tag(3)
        }
        .padding(20)
        .frame(width: 560, height: 430)
    }

    private var general: some View {
        Form {
            Section {
                LabeledContent("Switch input") {
                    ShortcutRecorder(shortcut: $prefs.shortcut, onRecording: onRecording)
                }
                Text("Press once to go back to the previous input, twice quickly for the next one. "
                     + "Use two or more modifier keys (pressed together, then released), or modifiers plus a key such as Control+Space.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reset to Control+Shift") { prefs.shortcut = .default }
                    .disabled(prefs.shortcut == .default)
            }
            Section {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                Toggle("Automatically install updates", isOn: $updater.autoInstall)
                    .disabled(!updater.isReleaseBuild)
                LabeledContent("Secure Input") {
                    Button("Open Monitor…", action: showSecureInput)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var vietnamese: some View {
        Form {
            Section {
                Toggle("Check spelling", isOn: $prefs.spellCheck)
                Text("Only add tone and vowel marks where they make a valid Vietnamese syllable, so English words such as “class” or “window” stay as typed. "
                     + "Turn off to apply every Telex key, like UniKey without spell check.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Restore non-Vietnamese words", isOn: $prefs.restoreNonVietnamese)
                    .disabled(!prefs.spellCheck)
                Text("When a word ends and the result is not a real Vietnamese syllable, retype the keys you pressed: user, data, more.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Picker("Tone placement", selection: $prefs.modernToneStyle) {
                    Text("Classic (hòa, khỏe, thúy)").tag(false)
                    Text("Modern (hoà, khoẻ, thuý)").tag(true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var chinese: some View {
        Form {
            Section {
                Toggle("Full-width punctuation (，。？！)", isOn: $prefs.fullWidthPunctuation)
            }
        }
        .formStyle(.grouped)
    }
}

struct MacrosView: View {
    @ObservedObject var prefs: Preferences
    @State private var selection: Macro.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Expand text shortcuts in Vietnamese mode", isOn: $prefs.macrosEnabled)
            Text("Type a shortcut as its own word, then Space, Return or Tab, to replace it with the full text (call2vn@ stays as typed). Letter case follows what you type: vn → Việt Nam, VN → VIỆT NAM.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Table(prefs.macros, selection: $selection) {
                TableColumn("Shortcut") { m in TextField("e.g. vn", text: field(m.id, \.key)) }
                    .width(120)
                TableColumn("Replace with") { m in TextField("e.g. Việt Nam", text: field(m.id, \.text)) }
            }
            .disabled(!prefs.macrosEnabled)
            HStack(spacing: 4) {
                Button { prefs.macros.append(Macro(key: "", text: "")) } label: { Image(systemName: "plus") }
                Button {
                    prefs.macros.removeAll { $0.id == selection }
                    selection = nil
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
                Text("\(prefs.macros.count) shortcuts").font(.caption).foregroundColor(.secondary)
            }
            .disabled(!prefs.macrosEnabled)
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
        Button(recording ? "Press the new shortcut…" : shortcut.label) { recording ? stop() : start() }
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
