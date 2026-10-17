import AppKit
import Carbon.HIToolbox
import ViPiCore

/// Kiểm thử đầu-cuối trên máy thật: `open -n ViPi.app --args --selftest <words> <out> [gapMs] [holdMs] [variant]`.
/// Tiến trình này gõ phím giả ở mức HID (như bàn phím thật, có đè phím khi gõ nhanh) vào cửa sổ của nó;
/// bản ViPi đang chạy xử lý các phím đó; cuối cùng so chữ trong cửa sổ với kết quả của TelexEngine.
/// Dùng chung chữ ký với ViPi nên dùng luôn quyền Accessibility đã cấp.
final class SelfTest: NSObject, NSApplicationDelegate {
    private let wordsPath: String, outPath: String
    private let gap: Double, hold: Double
    private let variant: Bool
    private let chrome: String?          // "ta" | "ce" | "lx": gõ vào Chrome (textarea / contenteditable / Lexical)
    private let appTarget: String?       // bundle id: gõ vào ô đang focus của app đó (vd com.t3tools.t3code)
    private var window: NSWindow!
    private var textView: NSTextView!
    private let source = CGEventSource(stateID: .hidSystemState)

    init(args: [String]) {
        wordsPath = args[0]
        outPath = args[1]
        gap = args.count > 2 ? Double(args[2])! / 1000 : 0.012
        hold = args.count > 3 ? Double(args[3])! / 1000 : 0.035
        variant = args.dropFirst(4).contains("variant")
        chrome = args.dropFirst(4).first { $0.hasPrefix("chrome-") }.map { String($0.dropFirst(7)) }
        appTarget = args.dropFirst(4).first { $0.hasPrefix("app-") }.map { String($0.dropFirst(4)) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 900, height: 500),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = "ViPi self-test"
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as? NSTextView
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        window.contentView = scroll
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { self.run() }
    }

    private func onMain<T>(_ f: () -> T) -> T { DispatchQueue.main.sync(execute: f) }

    private func run() {
        var out = ""
        var finish = {
            try? out.write(toFile: self.outPath, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        guard AXIsProcessTrusted() else { out = "NO_ACCESSIBILITY\n"; finish(); return }
        // "tis-<id>": gõ khi đang bật nguồn nhập đó (vd bộ gõ tiếng Việt của Apple), xong trả về ABC
        if let id = CommandLine.arguments.first(where: { $0.hasPrefix("tis-") })?.dropFirst(4) {
            onMain { Self.selectInputSource(String(id)) }
            let original = finish
            finish = { self.onMain { Self.selectInputSource("com.apple.keylayout.ABC") }; original() }
            usleep(500_000)
            let current = onMain { () -> String in
                let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
                guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "?" }
                return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
            }
            out += "INPUT_SOURCE \(current)\n"
        }

        // Chỉ lấy từ mà engine dựng đúng (bỏ từ mượn kiểu "abc"); kết quả mong đợi = engine
        let words = ((try? String(contentsOfFile: wordsPath, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        // giống ViPi đang chạy: có danh sách âm tiết thì chữ không phải tiếng Việt được trả lại khi gõ Space
        let lexicon = Bundle.main.url(forResource: "vietnamese-syllables", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map(VietnameseLexicon.init(text:))
        let prefs = Preferences()
        let macros = prefs.macrosEnabled ? prefs.macroTable : nil
        func typed(_ keys: [Character]) -> String {
            let e = TelexEngine()
            e.lexicon = lexicon
            for k in keys { _ = e.type(k) }
            let shown = e.output
            if let edit = macros.flatMap(e.expandMacro) ?? e.finishWord() {
                return String(shown.dropLast(edit.backspaces)) + edit.insert
            }
            return shown
        }
        var cases: [(keys: [Character], want: String)] = []
        for w in words {
            // dòng "phím<TAB>mong đợi": gõ đúng các phím đó (vd thử gõ tắt "vn\tViệt Nam")
            let parts = w.split(separator: "\t", omittingEmptySubsequences: false)
            if parts.count == 2 { cases.append((Array(parts[0]), String(parts[1]))); continue }
            guard typed(TelexEngine.telexKeys(for: w)) == w else { continue }
            let keys = variant ? Self.marksAtEnd(w) : TelexEngine.telexKeys(for: w)
            cases.append((keys, typed(keys)))
        }

        // nơi gõ: cửa sổ của mình, hoặc một trang trong Chrome (đọc lại bằng Accessibility)
        var clear: () -> Void = { self.onMain { self.textView.string = ""; self.window.makeFirstResponder(self.textView) } }
        var read: () -> String = { self.onMain { self.textView.string } }
        var focus: () -> Void = {
            if !self.onMain({ NSApp.isActive }) { self.onMain { NSApp.activate(ignoringOtherApps: true) }; usleep(300_000) }
        }
        var separator: Character = "\n"   // Enter kết thúc từ (cụm gõ tắt có thể chứa dấu cách)
        if let mode = chrome ?? appTarget {
            let page: (app: NSRunningApplication, ax: AXUIElement)?
            if let id = appTarget, let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                let ax = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                app.activate(options: [])
                sleep(2)
                page = (app, ax)
            } else {
                page = appTarget == nil ? Self.openChromePage(mode) : nil
            }
            guard let page else { out = "NO_TARGET\n"; finish(); return }
            separator = " "   // Enter trong trình soạn thảo web tạo đoạn mới: dùng Space
            focus = { page.app.activate(options: []); usleep(200_000) }
            clear = {
                self.postKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
                self.postKey(CGKeyCode(kVK_Delete), flags: [])
                usleep(300_000)
            }
            read = { Self.axFocusedValue(page.ax).replacingOccurrences(of: "\u{00A0}", with: " ") }
        }

        var fails = 0
        let batch = 40
        for start in stride(from: 0, to: cases.count, by: batch) {
            let chunk = Array(cases[start..<min(start + batch, cases.count)])
            focus()
            clear()
            var keys: [Character] = []
            for c in chunk { keys += c.keys; keys.append(separator) }
            type(keys)
            usleep(chrome == nil && appTarget == nil ? 400_000 : 900_000)
            let got = read().split(separator: separator, omittingEmptySubsequences: false).map(String.init)
            for (i, c) in chunk.enumerated() {
                let g = i < got.count ? got[i] : "<missing>"
                if g != c.want {
                    fails += 1
                    out += "FAIL\t\(String(c.keys))\twant=\(c.want)\tgot=\(g)\n"
                }
            }
            if got.count != chunk.count + 1 {
                out += "BATCH_DESYNC\tstart=\(start)\tgot_words=\(got.count - 1)\n"
            }
        }
        out += "TOTAL \(cases.count) FAIL \(fails) gap=\(Int(gap * 1000))ms hold=\(Int(hold * 1000))ms variant=\(variant) target=\(chrome.map { "chrome-\($0)" } ?? appTarget ?? "native")\n"
        if appTarget != nil { clear() }   // không để lại chữ thử trong app thật
        finish()
    }

    /// Gõ dãy phím với nhịp `gap`, mỗi phím giữ `hold` (hold > gap → các phím đè nhau như gõ nhanh thật).
    private func type(_ keys: [Character]) {
        var timeline: [(t: Double, code: CGKeyCode, down: Bool, shift: Bool)] = []
        for (i, k) in keys.enumerated() {
            guard let code = Self.keyCodes[Character(k.lowercased())] else { continue }
            let t = Double(i) * gap
            timeline.append((t, code, true, k.isUppercase))
            timeline.append((t + hold, code, false, k.isUppercase))
        }
        timeline.sort { $0.t < $1.t }
        let t0 = Date()
        for ev in timeline {
            let wait = ev.t - Date().timeIntervalSince(t0)
            if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: ev.code, keyDown: ev.down) else { continue }
            e.flags = ev.shift ? .maskShift : []
            e.post(tap: .cghidEventTap)
        }
    }

    /// Nhấn-nhả Control+Shift (hoặc Control+Space) `times` lần ở mức HID.
    static func pressChord(times: Int, gapMs: Double, withSpace: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        let second: (CGKeyCode, CGEventFlags) = withSpace ? (CGKeyCode(kVK_Space), .maskControl) : (CGKeyCode(kVK_Shift), [.maskControl, .maskShift])
        let steps: [(code: CGKeyCode, flags: CGEventFlags, type: CGEventType)] = [
            (CGKeyCode(kVK_Control), .maskControl, .flagsChanged),
            (second.0, second.1, withSpace ? .keyDown : .flagsChanged),
            (second.0, .maskControl, withSpace ? .keyUp : .flagsChanged),
            (CGKeyCode(kVK_Control), [], .flagsChanged),
        ]
        for n in 0..<times {
            if n > 0 { usleep(useconds_t(gapMs * 1000)) }
            for step in steps {
                guard let e = CGEvent(source: source) else { continue }
                e.type = step.type
                e.setIntegerValueField(.keyboardEventKeycode, value: Int64(step.code))
                e.flags = step.flags
                e.post(tap: .cghidEventTap)
                usleep(30_000)
            }
        }
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    /// Mở trang thử trong Chrome: textarea, contenteditable, hoặc trình soạn thảo Lexical (như các app Electron).
    static func openChromePage(_ mode: String) -> (app: NSRunningApplication, ax: AXUIElement)? {
        let html = """
            <!doctype html><meta charset=utf-8><title>ViPi Chrome test</title>
            <style>textarea,div{width:95%;height:40vh;font:16px sans-serif;border:1px solid #888;white-space:pre-wrap}</style>
            <textarea id=ta></textarea><div id=ce contenteditable></div><div id=lx contenteditable></div>
            <script type=module>
            const m = location.hash.slice(1) || 'ta';
            if (m === 'lx') {
              const {createEditor} = await import('https://esm.sh/lexical@0.17.1');
              const {registerPlainText} = await import('https://esm.sh/@lexical/plain-text@0.17.1?deps=lexical@0.17.1');
              const ed = createEditor({namespace: 't', onError: console.error});
              ed.setRootElement(document.getElementById('lx'));
              registerPlainText(ed);
            }
            const el = document.getElementById(m);
            el.focus();
            addEventListener('focus', () => el.focus());
            </script>
            """
        let path = "/tmp/vipi-chrome-test.html"
        try? html.write(toFile: path, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Google Chrome", "file://\(path)#\(mode)"]
        try? p.run()
        p.waitUntilExit()
        sleep(4)
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return nil }
        app.activate(options: [])
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        sleep(1)
        return (app, ax)
    }

    static func axFocusedValue(_ app: AXUIElement) -> String {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return "<no focus>" }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value)
        return value as? String ?? "<no value>"
    }

    static func selectInputSource(_ id: String) {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let src = list.first else { return }
        TISEnableInputSource(src)
        TISSelectInputSource(src)
    }

    /// Biến thể: gõ chữ không dấu trước, dấu mũ/móc/đ và thanh ở cuối ("người" → "nguoiwf").
    static func marksAtEnd(_ w: String) -> [Character] {
        var base = "", marks = "", tone = ""
        var horn = false
        let canon = TelexEngine.telexKeys(for: w)
        var i = 0
        while i < canon.count {
            let c = canon[i]
            let next = i + 1 < canon.count ? canon[i + 1] : nil
            if "sfrxj".contains(c), i == canon.count - 1 { tone = String(c); i += 1; continue }
            if let n = next, n == "w", "aou".contains(c) { base.append(c); horn = true; i += 2; continue }
            if let n = next, n == c, "aeod".contains(c) { base.append(c); marks.append(c); i += 2; continue }
            base.append(c)
            i += 1
        }
        return Array(base + marks + (horn ? "w" : "") + tone)
    }

    static let keyCodes: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46, " ": 49, "\n": 36, "1": 18, "2": 19, ".": 47,
    ]
}
