import AppKit
import SwiftUI
import ViPiCore

/// Tab đang mở của Settings; About mở thẳng tab General qua đây.
final class SettingsNavigation: ObservableObject {
    @Published var tab: Int
    init(tab: Int = 0) { self.tab = tab }
}

final class SettingsWindowController {
    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    private let prefs: Preferences
    private let updater: Updater
    private let userDictionary: PinyinUserDictionary
    private let onRecording: (Bool) -> Void
    private let showSecureInput: () -> Void

    init(prefs: Preferences, updater: Updater, userDictionary: PinyinUserDictionary,
         onRecording: @escaping (Bool) -> Void, showSecureInput: @escaping () -> Void) {
        self.prefs = prefs
        self.updater = updater
        self.userDictionary = userDictionary
        self.onRecording = onRecording
        self.showSecureInput = showSecureInput
    }

    func show(tab: Int? = nil) {
        if let tab { navigation.tab = tab }
        if window == nil {
            let view = SettingsView(prefs: prefs, updater: updater, userDictionary: userDictionary,
                                    onRecording: onRecording, showSecureInput: showSecureInput, navigation: navigation)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.styleMask = [.titled, .closable]
            w.applyGlassChrome()
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
    let userDictionary: PinyinUserDictionary
    let onRecording: (Bool) -> Void
    let showSecureInput: () -> Void
    @ObservedObject var navigation: SettingsNavigation
    @State private var learnedCount = 0

    var body: some View {
        VStack(spacing: 14) {
            GlassTabBar(titles: [tr("General"), tr("Vietnamese"), tr("Chinese"), tr("Text Shortcuts")], selection: $navigation.tab)
                .padding(.top, 2)
            switch navigation.tab {
            case 1: page { vietnamese }
            case 2: page { chinese }
            case 3: MacrosView(prefs: prefs).padding([.horizontal, .bottom], 24)
            default: page { general }
            }
        }
        .frame(width: 560, height: 500)
        .foregroundColor(Theme.ink)
        .tint(Theme.brandRed)
        .background(WindowBackground())
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 14) { content() }
                .padding([.horizontal, .bottom], 24)
                .padding(.top, 1)   // viền trên của card đầu không bị cắt
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }.glassCard()
    }

    @ViewBuilder private var general: some View {
        card {
            SettingRow(title: tr("Language")) {
                CapsulePicker(title: tr("Language"), options: UILanguage.allCases.map { ($0, $0.name) }, selection: $prefs.language)
            }
            CardDivider()
            SettingRow(title: tr("Appearance")) {
                CapsulePicker(title: tr("Appearance"), options: Appearance.allCases.map { ($0, $0.title) }, selection: $prefs.appearance)
            }
        }
        card {
            SettingRow(title: tr("Switch input")) {
                ShortcutRecorder(shortcut: $prefs.shortcut, onRecording: onRecording)
            }
            HelpText(tr("Press once to go back to the previous input, twice quickly for the next one. Use two or more modifier keys (pressed together, then released), or modifiers plus a key such as Control+Space."))
            CardDivider()
            SettingRow(title: tr("Reset to Control+Shift")) {
                Button(tr("Reset")) { prefs.shortcut = .default }.buttonStyle(GlassButtonStyle())
            }
            .disabled(prefs.shortcut == .default)
        }
        card {
            ToggleRow(title: tr("Launch at login"), isOn: $prefs.launchAtLogin)
            CardDivider()
            ToggleRow(title: tr("Automatically install updates"), isOn: $updater.autoInstall)
                .disabled(!updater.isReleaseBuild)
            CardDivider()
            SettingRow(title: tr("Secure Input"), systemImage: "lock") {
                Button(tr("Open Monitor…"), action: showSecureInput).buttonStyle(GlassButtonStyle())
            }
        }
    }

    @ViewBuilder private var vietnamese: some View {
        card {
            ToggleRow(title: tr("Check spelling"), isOn: $prefs.spellCheck)
            HelpText(tr("Only add tone and vowel marks where they make a valid Vietnamese syllable, so English words such as “class” or “window” stay as typed. Turn off to apply every Telex key, like UniKey without spell check."))
            CardDivider()
            ToggleRow(title: tr("Restore non-Vietnamese words"), isOn: $prefs.restoreNonVietnamese)
                .disabled(!prefs.spellCheck)
            HelpText(tr("When a word ends and the result is not a real Vietnamese syllable, retype the keys you pressed: user, data, more."))
        }
        card {
            ToggleRow(title: tr("Switch between Vietnamese and English automatically"), isOn: $prefs.autoSwitch) {
                GoldBadge(text: tr("EXPERIMENTAL"))
            }
            HelpText(tr("Type Telex in English and treen becomes trên, then ViPi switches to Vietnamese. English words typed in Vietnamese, such as server or this makes, come back as typed and ViPi switches to English. The menu bar shows VE while this is on. Word lists from Vikey."))
        }
        card {
            SettingRow(title: tr("Tone placement")) {
                CapsulePicker(title: tr("Tone placement"),
                              options: [(false, tr("Classic (hòa, khỏe, thúy)")), (true, tr("Modern (hoà, khoẻ, thuý)"))],
                              selection: $prefs.modernToneStyle)
            }
        }
    }

    @ViewBuilder private var chinese: some View {
        card {
            SettingRow(title: tr("Characters")) {
                CapsulePicker(title: tr("Characters"),
                              options: [(false, tr("Simplified (中国)")), (true, tr("Traditional (中國)"))],
                              selection: $prefs.traditionalChinese)
            }
            CardDivider()
            ToggleRow(title: tr("Full-width punctuation (，。？！)"), isOn: $prefs.fullWidthPunctuation)
        }
        card {
            ToggleRow(title: tr("Learn the words I pick"), isOn: $prefs.learnWords)
            HelpText(tr("Words and phrases you choose come first next time. They are stored only on this Mac."))
            CardDivider()
            SettingRow(title: tr("%@ learned words", String(learnedCount))) {
                Button(tr("Clear")) { userDictionary.clear(); learnedCount = 0 }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(learnedCount == 0)
            }
        }
        .onAppear { learnedCount = userDictionary.count }
        card {
            Text(tr("Fuzzy pinyin"))
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            HelpText(tr("Treat these sounds as the same, so zong also finds zhong."))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 8) {
                ForEach(FuzzyRule.all) { rule in
                    Toggle(rule.label, isOn: fuzzy(rule.id))
                        .toggleStyle(BrandCheckboxStyle())
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private func fuzzy(_ id: String) -> Binding<Bool> {
        Binding(get: { prefs.fuzzyRules.contains(id) },
                set: { on in if on { prefs.fuzzyRules.insert(id) } else { prefs.fuzzyRules.remove(id) } })
    }
}

struct MacrosView: View {
    @ObservedObject var prefs: Preferences
    @State private var selection: Macro.ID?
    @FocusState private var focus: Field?

    private struct Field: Hashable {
        let id: Macro.ID
        let isKey: Bool
    }

    /// Một bảng chung, bật riêng cho từng bộ gõ (bộ gõ Trung dùng Space để chọn chữ nên không áp dụng).
    private var enabled: Bool { prefs.macrosEnabled || prefs.macrosInEnglish }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                ToggleRow(title: tr("Use in Vietnamese"), isOn: $prefs.macrosEnabled)
                CardDivider()
                ToggleRow(title: tr("Use in English"), isOn: $prefs.macrosInEnglish)
                HelpText(tr("Type a shortcut as its own word, then Space, Return or Tab, to replace it with the full text (call2vn@ stays as typed). Letter case follows what you type: vn → Việt Nam, VN → VIỆT NAM. Not used in Chinese mode, where Space picks a candidate."))
            }
            .glassCard()
            table
                .frame(maxHeight: .infinity)
                .glassCard()
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(tr("Shortcut")).frame(width: 150, alignment: .leading)
                Text(tr("Replace with")).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.inkSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            CardDivider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(prefs.macros) { row($0) }
                }
            }
            .frame(maxHeight: .infinity)
            CardDivider()
            HStack(spacing: 0) {
                Button { add() } label: { Image(systemName: "plus").frame(width: 28, height: 24).contentShape(Rectangle()) }
                    .accessibilityLabel(tr("Add"))
                Theme.controlStroke.frame(width: 1, height: 14)
                Button { remove() } label: { Image(systemName: "minus").frame(width: 28, height: 24).contentShape(Rectangle()) }
                    .accessibilityLabel(tr("Remove"))
                    .disabled(selection == nil)
                    .opacity(selection == nil ? 0.45 : 1)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Text(tr("%@ shortcuts", String(prefs.macros.count)))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.inkSecondary)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(alignment: .leading) {
                Capsule().fill(Theme.control)
                    .overlay(Capsule().strokeBorder(Theme.controlStroke, lineWidth: 1))
                    .frame(width: 58, height: 24)
                    .padding(.leading, 14)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onChange(of: focus) { if let id = $0?.id { selection = id } }
        .onAppear {
            // macOS tự đặt con trỏ vào ô đầu tiên khi mở tab: đừng coi đó là chọn hàng (nút − sẽ xoá nhầm)
            DispatchQueue.main.async { focus = nil; selection = nil }
        }
    }

    private func row(_ macro: Macro) -> some View {
        HStack(spacing: 10) {
            TextField(tr("e.g. vn"), text: field(macro.id, \.key))
                .focused($focus, equals: Field(id: macro.id, isKey: true))
                .frame(width: 150)
            TextField(tr("e.g. Việt Nam"), text: field(macro.id, \.text))
                .focused($focus, equals: Field(id: macro.id, isKey: false))
        }
        .textFieldStyle(.plain)
        .labelsHidden()
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(selection == macro.id ? Theme.brandRed.opacity(0.14) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = macro.id }
    }

    private func add() {
        let macro = Macro(key: "", text: "")
        prefs.macros.append(macro)
        selection = macro.id
        focus = Field(id: macro.id, isKey: true)
    }

    private func remove() {
        focus = nil
        prefs.macros.removeAll { $0.id == selection }
        selection = nil
    }

    private func field(_ id: Macro.ID, _ path: WritableKeyPath<Macro, String>) -> Binding<String> {
        Binding(
            get: { prefs.macros.first { $0.id == id }?[keyPath: path] ?? "" },
            set: { value in
                if let i = prefs.macros.firstIndex(where: { $0.id == id }) { prefs.macros[i][keyPath: path] = value }
            })
    }
}
