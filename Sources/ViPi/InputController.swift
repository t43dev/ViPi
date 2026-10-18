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
}

/// Bắt phím toàn hệ thống bằng CGEventTap và chuyển cho bộ gõ Telex / Pinyin.
final class InputController {
    var mode: InputMode = .vietnamese {
        didSet { cancelComposition() }
    }
    var onCycleMode: (() -> Void)?
    var fullWidthPunctuation = true
    var shortcut = SwitchShortcut.default { didSet { chordArmed = false } }
    var macros: MacroTable?            // nil: tắt gõ tắt
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
        switch mode {
        case .english: return false
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
            // gõ tắt chỉ khi từ đứng riêng và kết thúc bằng Space/Enter/Tab: "call2vn@" giữ nguyên
            let macro = isSpace && atWordStart ? macros.flatMap(telex.expandMacro) : nil
            atWordStart = isSpace
            if let ascii, (0x20...0x7E).contains(ascii) || isSpace,
               let edit = macro ?? telex.finishWord() {
                // gõ nhanh thì phím chữ cuối có thể còn đang giữ: mượn mã của chính phím Space (app chưa thấy nó)
                KeySender.send(edit, keyCode: ascii == 0x20 ? CGKeyCode(kVK_Space) : self.keyCode, proxy: proxy)
                KeySender.repost(event, proxy: proxy)
                return true
            }
            telex.reset()
            return false
        }
        let edit = telex.type(ch)
        if edit.backspaces == 0, edit.insert == typed { return false }   // để phím gốc đi qua
        KeySender.send(edit, keyCode: self.keyCode, proxy: proxy)
        return true
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
        atWordStart = true
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

/// Nhật ký chẩn đoán (chỉ khi `defaults write io.github.kulinh.vipi debugLog -bool true`):
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

    static func send(_ edit: TextEdit, keyCode: CGKeyCode, proxy: CGEventTapProxy?) {
        DebugLog.line("  SEND bs=\(edit.backspaces) insert=\"\(edit.insert)\" keyCode=\(keyCode)")
        for _ in 0..<edit.backspaces { post(key: CGKeyCode(kVK_Delete), text: nil, proxy: proxy) }
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

    private static func post(key: CGKeyCode, text: String?, proxy: CGEventTapProxy?) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = []
            if let text {
                let units = Array(text.utf16)
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            if let proxy { e.tapPostEvent(proxy) } else { e.post(tap: .cgSessionEventTap) }
        }
    }
}
