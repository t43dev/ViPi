import SwiftUI
import UIKit

/// Cài đặt, cùng nội dung với bản Android (SettingsActivity.kt). Giá trị ghi vào App Group để bàn phím đọc.
struct SettingsView: View {
    @AppStorage(Prefs.spellCheck, store: Prefs.shared) private var spellCheck = true
    @AppStorage(Prefs.restore, store: Prefs.shared) private var restore = true
    @AppStorage(Prefs.modernTone, store: Prefs.shared) private var modernTone = false
    @AppStorage(Prefs.traditional, store: Prefs.shared) private var traditional = false
    @AppStorage(Prefs.learn, store: Prefs.shared) private var learn = true
    @AppStorage(Prefs.fullWidth, store: Prefs.shared) private var fullWidth = true
    @AppStorage(Prefs.theme, store: Prefs.shared) private var theme = "system"
    @AppStorage(Prefs.keyPopup, store: Prefs.shared) private var keyPopup = true
    @AppStorage(Prefs.suggestions, store: Prefs.shared) private var suggestions = true
    @AppStorage(Prefs.autoCorrect, store: Prefs.shared) private var autoCorrect = true
    @AppStorage(Prefs.vietnameseBar, store: Prefs.shared) private var vietnameseBar = true
    @AppStorage(Prefs.largeLayout, store: Prefs.shared) private var largeLayout = "wide"
    @AppStorage(Prefs.haptics, store: Prefs.shared) private var haptics = true
    @AppStorage(Prefs.autoCap, store: Prefs.shared) private var autoCap = true
    @AppStorage(Prefs.doubleSpace, store: Prefs.shared) private var doubleSpace = true

    @State private var fuzzy = Set(Prefs.fuzzyRules)
    @State private var trial = ""
    @State private var clearRequested = false
    @Environment(\.openURL) private var openURL

    private let fuzzyChoices = fuzzyOptions()
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        Form {
            Section {
                Text("Vietnamese Telex and Chinese Pinyin on one keyboard.")
                    .foregroundStyle(.secondary)
            }

            Section("Set up") {
                Text("1. Open Settings, tap Keyboards and turn on ViPi.\n2. In any app, hold the globe key below the keyboard and choose ViPi.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                // chỉ cho UI test (-clearButton): xoá ô bằng code như nút gửi của app chat
                if ProcessInfo.processInfo.arguments.contains("-clearButton") { Button("Clear") { trial = "" } }
                // chỉ cho UI test (-searchField): ô một dòng với nút Search, như ô tìm kiếm / thanh địa chỉ
                TextField("Try it here", text: $trial, axis: ProcessInfo.processInfo.arguments.contains("-searchField") ? .horizontal : .vertical)
                    .submitLabel(ProcessInfo.processInfo.arguments.contains("-searchField") ? .search : .return)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("trial")
            }

            Section {
                Text("Vietnamese and English are one keyboard: ViPi tells them apart as you type, so treen becomes trên and server stays server. Tap the language key to switch to Chinese and back. Hold a key on the top row for its number. Word lists from Vikey.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                option("Check spelling", "Only add marks where they make a real Vietnamese syllable, so words like \"class\" stay as typed.", $spellCheck)
                option("Restore non-Vietnamese words", "When a word ends and is not Vietnamese, put back the keys you typed: user, data, more.", $restore)
                option("Modern tone placement", "hoà, khoẻ, thuý instead of hòa, khỏe, thúy.", $modernTone)
                option("Suggestion bar", "Show the bar above the keys with the keys you typed and the word with marks. Off: the keyboard is shorter, and the bar only shows for Chinese.", $vietnameseBar)
                option("Word suggestions", "Show ways to finish the word and likely next words on the bar. Needs the suggestion bar.", $suggestions)
                option("Auto-correct typos", "Fix an English word typed with a slip onto a neighbouring key when you press space, and let the keys follow the sentence: a touch between two keys types the likelier letter. Backspace right after a fix puts your word back.", $autoCorrect)
            } header: {
                Text("Vietnamese")
            }

            Section {
                option("Traditional characters", "头发 becomes 頭髮.", $traditional)
                option("Learn the words I pick", "Words you pick come first next time. Stored only in the keyboard on this device.", $learn)
                Button("Clear learned words", role: .destructive) {
                    Prefs.shared.set(Date().timeIntervalSince1970, forKey: Prefs.clearLearnedAt)
                    clearRequested = true
                }
                option("Full-width punctuation", "，。？！ while typing Chinese.", $fullWidth)
            } header: {
                Text("Chinese")
            } footer: {
                if clearRequested { Text("Learned words will be cleared the next time the keyboard opens.") }
            }

            Section("Fuzzy pinyin") {
                ForEach(fuzzyChoices, id: \.id) { choice in
                    Toggle(choice.label, isOn: Binding(
                        get: { fuzzy.contains(choice.id) },
                        set: { on in
                            if on { fuzzy.insert(choice.id) } else { fuzzy.remove(choice.id) }
                            Prefs.fuzzyRules = fuzzy.sorted()
                        }
                    ))
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                option("Show key popup", "Show a larger letter above the key you press.", $keyPopup)
            }

            Section {
                if isPad {
                    Picker("On iPad", selection: $largeLayout) {
                        Text("Full: like the iPad keyboard").tag("wide")
                        Text("Split: one half on each side").tag("split")
                    }
                }
                option("Vibrate on key press", "Needs Full Access: Settings → Apps → ViPi → Keyboards → Allow Full Access.", $haptics)
                option("Auto-capitalize", "Start sentences with a capital letter.", $autoCap)
                option("\".\" shortcut", "Double-tap the space bar for a period and a space.", $doubleSpace)
            } header: {
                Text("Keyboard")
            }

            Section("About") {
                Text("ViPi is free software under GPL-3.0. Typing stays on this device: ViPi works fully without Full Access and has no code that goes online, so it cannot send anything anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Privacy policy") { openURL(Prefs.privacyURL) }
                Button("Source code on GitHub") { openURL(Prefs.sourceURL) }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
        }
        .navigationTitle("ViPi")
    }

    private func option(_ title: String, _ detail: String?, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

