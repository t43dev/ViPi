import AppKit
import Carbon.HIToolbox
import ViPiCore

enum InputMode: String, CaseIterable {
    case vietnamese, chinese, english

    var title: String {
        switch self {
        case .vietnamese: return tr("Vietnamese (Telex)")
        case .chinese: return tr("Chinese (Pinyin)")
        case .english: return tr("English")
        }
    }

    var badge: String {
        switch self {
        case .vietnamese: return "VI"
        case .chinese: return "拼"
        case .english: return "EN"
        }
    }

    /// Tự đổi Anh/Việt đang bật: tiếng Việt và tiếng Anh là một bộ gõ, người dùng thấy "VE".
    func badge(autoSwitch: Bool) -> String { autoSwitch && self != .chinese ? "VE" : badge }
    func title(autoSwitch: Bool) -> String { autoSwitch && self != .chinese ? tr("Vietnamese + English") : title }
}

/// Bắt phím toàn hệ thống bằng CGEventTap và chuyển cho bộ gõ Telex / Pinyin.
final class InputController {
    var mode: InputMode = .vietnamese {
        didSet { cancelComposition() }
    }
    var onCycleMode: (() -> Void)?
    var fullWidthPunctuation = true
    var shortcut = SwitchShortcut.default { didSet { chordArmed = false } }
    var macros: MacroTable?            // gõ tắt khi gõ tiếng Việt, nil: tắt
    var englishMacros: MacroTable?     // gõ tắt khi gõ tiếng Anh, nil: tắt
    var autoSwitch: AutoSwitch?        // tự đổi Anh/Việt khi kết thúc từ (thử nghiệm), nil: tắt
    var onAutoSwitch: ((InputMode) -> Void)?
    /// Ngay sau một lần tự đổi: Backspace xoá chữ đã sửa cùng phím kết thúc từ, trả lại đúng chữ trước đó và
    /// chế độ cũ (như Vikey). Phím nào khác thì quên.
    private var undo: (remove: Int, text: String, keys: [Character], mode: InputMode)?
    private var undoneKeys: [Character]?   // từ vừa được trả lại bằng Backspace: kết thúc lại nó thì không tự đổi nữa
    private var englishWord = ""       // chữ cái của từ đang gõ ở chế độ tiếng Anh
    private var atWordStart = true      // từ đang gõ đứng sau dấu cách/đầu dòng (không dính sau số, @, ...)
    var isRecordingShortcut = false     // đang ghi phím tắt trong Settings: để mọi phím đi qua

    let telex = TelexEngine()
    var pinyin: PinyinEngine?          // nil khi từ điển còn đang nạp
    private let panel = CandidatePanel()
    private var page = 0
    private var highlight = 0
    private let pageSize = 9

    private var tap: CFMachPort?
    private var proxy: CGEventTapProxy?
    private var chordArmed = false
    private var keyCode: CGKeyCode = 0   // phím đang xử lý; phím giả mang lại mã này

    var isRunning: Bool { tap != nil }

    // MARK: - Event tap

    func start() -> Bool {
        if tap != nil { return true }
        var types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if DebugLog.enabled { types.append(.keyUp) }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            let me = Unmanaged<InputController>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(proxy: proxy, type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let result = route(proxy: proxy, type: type, event: event)
        if DebugLog.enabled, type == .keyDown || type == .keyUp || type == .flagsChanged {
            DebugLog.event(type, event, swallowed: result == nil, telex: telex)
        }
        return result
    }

    private func route(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            chordArmed = false
            cancelComposition()
            return pass
        case .flagsChanged:
            if !isRecordingShortcut { handleChord(event.flags) }
            return pass
        case .keyDown:
            if event.getIntegerValueField(.eventSourceUserData) == KeySender.marker || isRecordingShortcut { return pass }
            chordArmed = false
            self.proxy = proxy
            // phím đổi bộ gõ dạng phím bổ trợ + phím (vd Control+Space): nuốt, kể cả khi giữ lặp
            if let code = shortcut.keyCode, code == event.getIntegerValueField(.keyboardEventKeycode),
               event.flags.intersection(SwitchShortcut.relevant) == shortcut.flags {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { self.onCycleMode?() }
                }
                return nil
            }
            return handleKey(event) ? nil : pass
        default:
            return pass
        }
    }

    /// Phím đổi bộ gõ chỉ gồm phím bổ trợ (mặc định Ctrl+Shift): nhấn đủ rồi nhả hết mà không gõ
    /// phím nào khác → đổi bộ gõ.
    private func handleChord(_ flags: CGEventFlags) {
        guard shortcut.keyCode == nil else { return }
        let f = flags.intersection(SwitchShortcut.relevant)
        if f == shortcut.flags {
            chordArmed = true
        } else if f.isEmpty {
            if chordArmed {
                chordArmed = false
                DispatchQueue.main.async { self.onCycleMode?() }
            }
        } else if !f.isSubset(of: shortcut.flags) {
            chordArmed = false
        }
    }

    // MARK: - Keys

    private func handleKey(_ event: CGEvent) -> Bool {
        if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            cancelComposition()   // phím tắt: không đụng vào
            return false
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let typed = Self.typedString(event)
        // Enter/Space/phím điều khiển: không mượn mã của chúng (app có thể hiểu là Enter thật)
        let printable = typed.count == 1 && typed.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
        self.keyCode = printable ? CGKeyCode(keyCode) : 0
        if keyCode == kVK_Delete, let u = undo {
            undoAutoSwitch(u)
            return true
        }
        undo = nil
        switch mode {
        case .english: return handleEnglish(keyCode, typed, event)
        case .vietnamese: return handleVietnamese(keyCode, typed, event)
        case .chinese: return handleChinese(keyCode, typed)
        }
    }

    private func handleVietnamese(_ keyCode: Int, _ typed: String, _ event: CGEvent) -> Bool {
        if keyCode == kVK_Delete {
            telex.backspace()
            return false
        }
        guard typed.count == 1, let ch = typed.first, ch.isASCII, ch.isLetter else {
            // Space/Enter/Tab/dấu câu/số kết thúc từ: gõ tắt ("vn" → "Việt Nam"), hoặc chữ không phải
            // tiếng Việt thì gõ lại như đã gõ ("ủe" → "user"), rồi mới cho phím kết thúc từ đi qua
            let ascii = typed.count == 1 ? typed.first?.asciiValue : nil
            let isSpace = ascii == 0x20 || ascii == 0x0D || ascii == 0x09
            let word = telex.keys, shown = telex.output
            // gõ tắt chỉ khi từ đứng riêng và kết thúc bằng Space/Enter/Tab: "call2vn@" giữ nguyên
            let macro = isSpace && atWordStart ? macros.flatMap(telex.expandMacro) : nil
            let auto = atWordStart ? activeAutoSwitch(typed) : nil
            atWordStart = isSpace
            if let ascii, (0x20...0x7E).contains(ascii) || isSpace {
                var edit = macro, switchTo: InputMode?
                // tự đổi: từ tiếng Anh gõ ở chế độ tiếng Việt ("server", "more") → trả lại phím đã gõ, sang tiếng Anh
                if edit == nil, let auto, auto.prefersEnglish(keys: word, shown: shown) {
                    edit = TextEdit(backspaces: shown.count, insert: String(word))
                    switchTo = .english
                } else if edit == nil, let restored = telex.finishWord() {
                    edit = restored
                    if auto?.isForeign(keys: word, shown: shown) == true { switchTo = .english }
                }
                autoSwitch?.remember(ascii == 0x20 && !word.isEmpty ? word : nil, vietnamese: true)
                if let edit {
                    // gõ nhanh thì phím chữ cuối có thể còn đang giữ: mượn mã của chính phím Space (app chưa thấy nó)
                    KeySender.send(edit, wholeWord: true, keyCode: ascii == 0x20 ? CGKeyCode(kVK_Space) : self.keyCode, proxy: proxy)
                    KeySender.repost(event, proxy: proxy)
                    telex.reset()
                    if let switchTo {
                        onAutoSwitch?(switchTo)
                        if ascii != 0x0D { undo = (edit.insert.count + 1, shown, word, .vietnamese) }
                    }
                    return true
                }
            }
            telex.reset()
            return false
        }
        let shown = telex.output.count
        let edit = telex.type(ch)
        if edit.backspaces == 0, edit.insert == typed { return false }   // để phím gốc đi qua
        KeySender.send(edit, wholeWord: edit.backspaces == shown, keyCode: self.keyCode, proxy: proxy)
        return true
    }

    /// Tiếng Anh: mọi phím đi qua, chỉ nhớ từ đang gõ để thay gõ tắt khi kết thúc bằng Space/Enter/Tab.
    private func handleEnglish(_ keyCode: Int, _ typed: String, _ event: CGEvent) -> Bool {
        guard englishMacros != nil || autoSwitch != nil else { return false }
        if keyCode == kVK_Delete {
            englishWord = String(englishWord.dropLast())
            return false
        }
        if typed.count == 1, let ch = typed.first, ch.isASCII, ch.isLetter {
            englishWord.append(ch)
            return false
        }
        // cùng quy tắc với tiếng Việt: từ đứng riêng, kết thúc bằng Space/Enter/Tab
        let ascii = typed.count == 1 ? typed.first?.asciiValue : nil
        let isSpace = ascii == 0x20 || ascii == 0x0D || ascii == 0x09
        let word = englishWord
        let started = atWordStart
        englishWord = ""
        atWordStart = isSpace
        var text = isSpace && started ? englishMacros?.expansion(for: word) : nil
        var switchTo: InputMode?
        // tự đổi: chữ Telex gõ ở chế độ tiếng Anh ("treen") → chữ tiếng Việt, sang tiếng Việt
        // từ vừa được trả lại bằng Backspace thì giữ như đã gõ
        let undone = undoneKeys == Array(word)
        undoneKeys = nil
        if text == nil, started, !undone, let auto = activeAutoSwitch(typed),
           let vietnamese = auto.vietnamese(for: Array(word), modern: telex.modernToneStyle) {
            text = vietnamese
            switchTo = .vietnamese
        }
        autoSwitch?.remember(ascii == 0x20 && !word.isEmpty ? Array(word) : nil, vietnamese: false)
        guard let text else { return false }
        KeySender.send(TextEdit(backspaces: word.count, insert: text), wholeWord: true,
                       keyCode: ascii == 0x20 ? CGKeyCode(kVK_Space) : self.keyCode, proxy: proxy)
        KeySender.repost(event, proxy: proxy)
        if let switchTo {
            onAutoSwitch?(switchTo)
            if ascii != 0x0D { undo = (text.count + 1, word, Array(word), .english) }
        }
        return true
    }

    /// Backspace ngay sau một lần tự đổi: bỏ chữ đã sửa và phím kết thúc từ, gõ lại chữ trước đó, về chế độ cũ.
    /// Về tiếng Anh thì các phím đó lại là từ đang gõ ("vaay" ⌫ rồi "j" → "vậy"); kết thúc lại y nguyên thì giữ.
    private func undoAutoSwitch(_ u: (remove: Int, text: String, keys: [Character], mode: InputMode)) {
        undo = nil
        KeySender.send(TextEdit(backspaces: u.remove, insert: u.text), wholeWord: false, keyCode: keyCode, proxy: proxy)
        onAutoSwitch?(u.mode)
        if u.mode == .english {
            englishWord = String(u.keys)
            atWordStart = true
            undoneKeys = u.keys
        }
    }

    /// Tự đổi đang bật và phím kết thúc từ là Space/Enter/Tab
    /// hoặc dấu câu sau một từ ("nhes." → "nhé.").
    private func activeAutoSwitch(_ typed: String) -> AutoSwitch? {
        guard let autoSwitch, typed.count == 1,
              let c = typed.first, " \r\t,.;!?)'\"".contains(c) else { return nil }
        return autoSwitch
    }

    private func handleChinese(_ keyCode: Int, _ typed: String) -> Bool {
        guard let py = pinyin else { return false }
        let ch = typed.count == 1 ? typed.first : nil

        if py.isComposing {
            switch keyCode {
            case kVK_Delete: py.backspace(); refreshPanel(); return true
            case kVK_Escape: cancelComposition(); return true
            case kVK_Return, kVK_ANSI_KeypadEnter: commit(py.commitRaw()); return true
            case kVK_Space:
                let i = page * pageSize + highlight
                if py.candidates.indices.contains(i) { choose(i) } else { commitBest() }
                return true
            case kVK_LeftArrow: moveHighlight(-1); return true
            case kVK_RightArrow, kVK_Tab: moveHighlight(1); return true
            case kVK_UpArrow, kVK_PageUp: turnPage(-1); return true
            case kVK_DownArrow, kVK_PageDown: turnPage(1); return true
            default: break
            }
            if let ch {
                if ("a"..."z").contains(ch) || ch == "'" { py.type(ch); page = 0; highlight = 0; refreshPanel(); return true }
                if let d = ch.wholeNumberValue, (1...9).contains(d) { choose(page * pageSize + d - 1); return true }
                if ch == "-" || ch == "[" { turnPage(-1); return true }
                if ch == "=" || ch == "]" { turnPage(1); return true }
            }
            // phím khác (dấu câu, chữ hoa...): chọn ứng viên đầu cho hết rồi xử lý tiếp như bình thường
            commitBest()
        }

        guard let ch else { return false }
        if ("a"..."z").contains(ch) {
            py.type(ch)
            page = 0; highlight = 0
            refreshPanel()
            DispatchQueue.main.async { self.panel.anchor(to: CaretLocator.caretRect()) }
            return true
        }
        if fullWidthPunctuation, let p = Self.punctuation[ch] {
            KeySender.insert(p, keyCode: self.keyCode, proxy: proxy)
            return true
        }
        return false
    }

    private func choose(_ index: Int) {
        guard let py = pinyin, py.candidates.indices.contains(index) else { return }
        if let text = py.select(index) { commit(text) } else { page = 0; highlight = 0; refreshPanel() }
    }

    private func commitBest() {
        guard let py = pinyin else { return }
        while py.isComposing {
            if py.candidates.isEmpty { commit(py.commitRaw()); return }
            if let text = py.select(0) { commit(text); return }
        }
    }

    private func commit(_ text: String) {
        panel.hide()
        if !text.isEmpty { KeySender.insert(text, keyCode: keyCode, proxy: proxy) }
    }

    private func moveHighlight(_ delta: Int) {
        guard let py = pinyin else { return }
        let count = min(pageSize, py.candidates.count - page * pageSize)
        let h = highlight + delta
        if h < 0 { if page > 0 { page -= 1; highlight = pageSize - 1 } }
        else if h >= count { turnPage(1); return }
        else { highlight = h }
        refreshPanel()
    }

    private func turnPage(_ delta: Int) {
        guard let py = pinyin else { return }
        let pages = max(1, (py.candidates.count + pageSize - 1) / pageSize)
        let p = page + delta
        if p >= 0, p < pages { page = p; highlight = 0 }
        refreshPanel()
    }

    private func refreshPanel() {
        guard let py = pinyin, py.isComposing else { panel.hide(); return }
        let start = page * pageSize
        let items = Array(py.candidates.dropFirst(start).prefix(pageSize)).map(\.text)
        panel.update(preedit: py.preedit, items: items, highlight: highlight,
                     hasPrev: page > 0, hasNext: start + pageSize < py.candidates.count)
    }

    func cancelComposition() {
        undo = nil
        undoneKeys = nil
        atWordStart = true
        autoSwitch?.remember(nil)
        englishWord = ""
        telex.reset()
        pinyin?.reset()
        page = 0
        highlight = 0
        panel.hide()
    }

    // MARK: - Helpers

    static func typedString(_ event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }

    static let punctuation: [Character: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！", ";": "；", ":": "：",
        "(": "（", ")": "）", "[": "【", "]": "】", "<": "《", ">": "》",
        "\\": "、", "~": "～", "^": "……", "$": "￥",
    ]
}

/// Nhật ký chẩn đoán (chỉ khi `defaults write dev.t43.vipi debugLog -bool true`):
/// ghi từng phím và từng sửa đổi vào ~/Library/Logs/ViPi-debug.log. Tắt mặc định — nó ghi lại phím gõ.
enum DebugLog {
    static let enabled = UserDefaults.standard.bool(forKey: "debugLog")
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ViPi-debug.log")
    private static let start = Date()

    static func line(_ s: String) {
        guard enabled else { return }
        let t = String(format: "%8.3f ", Date().timeIntervalSince(start))
        let data = Data((t + s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }

    static func event(_ type: CGEventType, _ e: CGEvent, swallowed: Bool, telex: TelexEngine) {
        let kind = type == .keyDown ? "DOWN" : type == .keyUp ? "UP  " : "FLAG"
        let own = e.getIntegerValueField(.eventSourceUserData) == KeySender.marker ? " own" : ""
        let rep = e.getIntegerValueField(.keyboardEventAutorepeat) == 1 ? " repeat" : ""
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        line("\(kind) code=\(e.getIntegerValueField(.keyboardEventKeycode)) char=\"\(InputController.typedString(e))\" flags=\(String(e.flags.rawValue, radix: 16))\(own)\(rep) src=\(e.getIntegerValueField(.eventSourceUnixProcessID)) \(swallowed ? "SWALLOWED" : "pass") keys=\"\(String(telex.keys))\" out=\"\(telex.output)\" app=\(app)")
    }
}

/// Gửi phím giả: backspace + chuỗi Unicode, đánh dấu để tap của mình bỏ qua.
/// Chữ được gửi kèm mã của chính phím vừa bị chặn (ứng dụng chưa thấy phím đó). Không dùng mã 0:
/// đó là phím A thật — gõ nhanh khi A còn đang giữ thì ứng dụng bỏ mất chữ thay thế ("sawcs" → "ắc").
enum KeySender {
    static let marker: Int64 = 0x5669_5069   // "ViPi"
    private static let source = CGEventSource(stateID: .privateState)

    /// Thanh địa chỉ trình duyệt tự điền phần gợi ý (bôi chọn) ngay sau chữ đang gõ; Backspace đầu tiên
    /// chỉ xoá phần gợi ý đó chứ không xoá chữ ("noojp" → "noộp"). Ở thanh địa chỉ, gửi trước một ký tự
    /// rỗng để ghi đè phần gợi ý rồi xoá thêm một lần; không có gợi ý thì ký tự đó bị xoá ngay, không để lại gì.
    /// Trong trang web, vài ô soạn thảo (chat.b.ai) tự xoá dấu cách cuối khi Backspace làm chữ kết thúc bằng
    /// khoảng trắng: thay cả từ bằng Backspace ăn mất dấu cách trước từ ("code được" → "codeđược"). Ở đó thay
    /// cả từ bằng cách bôi chọn (Shift+←) rồi gõ đè. Chỉ làm khi thay cả từ: terminal web (xterm.js) không bôi
    /// chọn được bằng Shift+←, còn sửa giữa từ thì Backspace không bao giờ để lại khoảng trắng cuối.
    static let browsers = ["com.google.Chrome", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
                           "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera",
                           "com.apple.Safari", "org.mozilla.firefox", "com.kagi.kagimacOS"]

    enum Focus { case addressBar, webPage, other }
    private static var lastFocus: AXUIElement?
    private static var lastKind = Focus.other

    /// Ô đang focus trong trình duyệt: trong trang web (có tổ tiên AXWebArea), thanh địa chỉ (ô nhập một dòng
    /// ngoài trang), hay không rõ (không phải trình duyệt / Accessibility không trả lời): gõ như app thường.
    static var focus: Focus {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              browsers.contains(where: { id.hasPrefix($0) }) else { return .other }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard let focused = axElement(system, kAXFocusedUIElementAttribute) else { return .other }
        if let lastFocus, CFEqual(lastFocus, focused) { return lastKind }
        let role = axString(focused, kAXRoleAttribute)
        var kind = role == "AXTextField" || role == "AXComboBox" ? Focus.addressBar : .other
        var node = axElement(focused, kAXParentAttribute)
        for _ in 0..<64 {
            guard let n = node else { break }
            if axString(n, kAXRoleAttribute) == "AXWebArea" { kind = .webPage; break }
            node = axElement(n, kAXParentAttribute)
        }
        lastFocus = focused
        lastKind = kind
        DebugLog.line("  focus role=\(role ?? "?") kind=\(kind)")
        return kind
    }

    private static func axElement(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success, let ref,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func axString(_ e: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    /// `wholeWord`: `edit` xoá hết từ đang gõ (xoá lùi tới tận đầu từ).
    static func send(_ edit: TextEdit, wholeWord: Bool, keyCode: CGKeyCode, proxy: CGEventTapProxy?) {
        DebugLog.line("  SEND bs=\(edit.backspaces) insert=\"\(edit.insert)\" keyCode=\(keyCode) whole=\(wholeWord)")
        var backspaces = edit.backspaces
        if backspaces > 0 {
            switch focus {
            case .addressBar:
                insert("\u{200C}", keyCode: keyCode, proxy: proxy)
                backspaces += 1
            case .webPage where wholeWord:
                for _ in 0..<backspaces { post(key: CGKeyCode(kVK_LeftArrow), text: nil, flags: .maskShift, proxy: proxy) }
                backspaces = edit.insert.isEmpty ? 1 : 0   // không còn chữ để gõ đè: xoá phần đã bôi chọn
            default: break
            }
        }
        for _ in 0..<backspaces { post(key: CGKeyCode(kVK_Delete), text: nil, proxy: proxy) }
        insert(edit.insert, keyCode: keyCode, proxy: proxy)
    }

    /// Gửi lại nguyên phím gốc (sau phần chữ vừa gửi), đánh dấu để tap của mình bỏ qua.
    static func repost(_ event: CGEvent, proxy: CGEventTapProxy?) {
        guard let e = event.copy() else { return }
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        if let proxy { e.tapPostEvent(proxy) } else { e.post(tap: .cgSessionEventTap) }
    }

    static func insert(_ text: String, keyCode: CGKeyCode, proxy: CGEventTapProxy?) {
        for ch in text { post(key: keyCode, text: String(ch), proxy: proxy) }
    }

    private static func post(key: CGKeyCode, text: String?, flags: CGEventFlags = [], proxy: CGEventTapProxy?) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            if let text {
                let units = Array(text.utf16)
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            if let proxy { e.tapPostEvent(proxy) } else { e.post(tap: .cgSessionEventTap) }
        }
    }
}
