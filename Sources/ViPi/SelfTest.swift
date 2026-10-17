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
    private var window: NSWindow!
    private var textView: NSTextView!
    private let source = CGEventSource(stateID: .hidSystemState)

    init(args: [String]) {
        wordsPath = args[0]
        outPath = args[1]
        gap = args.count > 2 ? Double(args[2])! / 1000 : 0.012
        hold = args.count > 3 ? Double(args[3])! / 1000 : 0.035
        variant = args.count > 4 && args[4] == "variant"
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
        func finish() {
            try? out.write(toFile: outPath, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        guard AXIsProcessTrusted() else { out = "NO_ACCESSIBILITY\n"; finish(); return }

        // Chỉ lấy từ mà engine dựng đúng (bỏ từ mượn kiểu "abc"); kết quả mong đợi = engine
        let words = ((try? String(contentsOfFile: wordsPath, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        var cases: [(keys: [Character], want: String)] = []
        for w in words {
            let keys = variant ? Self.marksAtEnd(w) : TelexEngine.telexKeys(for: w)
            let e = TelexEngine()
            for k in keys { _ = e.type(k) }
            let canonical = TelexEngine()
            for k in TelexEngine.telexKeys(for: w) { _ = canonical.type(k) }
            if canonical.output == w { cases.append((keys, e.output)) }
        }

        var fails = 0
        let batch = 40
        for start in stride(from: 0, to: cases.count, by: batch) {
            let chunk = Array(cases[start..<min(start + batch, cases.count)])
            onMain { textView.string = ""; window.makeFirstResponder(textView) }
            if !onMain({ NSApp.isActive }) { onMain { NSApp.activate(ignoringOtherApps: true) }; usleep(300_000) }
            var keys: [Character] = []
            for c in chunk { keys += c.keys; keys.append(" ") }
            type(keys)
            usleep(400_000)
            let got = onMain { textView.string }.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
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
        out += "TOTAL \(cases.count) FAIL \(fails) gap=\(Int(gap * 1000))ms hold=\(Int(hold * 1000))ms variant=\(variant)\n"
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
            if ev.shift { e.flags = .maskShift }
            e.post(tap: .cghidEventTap)
        }
    }

    /// Nhấn-nhả Control+Shift `times` lần ở mức HID.
    static func pressChord(times: Int, gapMs: Double) {
        let source = CGEventSource(stateID: .hidSystemState)
        let steps: [(CGKeyCode, CGEventFlags)] = [
            (CGKeyCode(kVK_Control), .maskControl), (CGKeyCode(kVK_Shift), [.maskControl, .maskShift]),
            (CGKeyCode(kVK_Shift), .maskControl), (CGKeyCode(kVK_Control), []),
        ]
        for n in 0..<times {
            if n > 0 { usleep(useconds_t(gapMs * 1000)) }
            for (code, flags) in steps {
                guard let e = CGEvent(source: source) else { continue }
                e.type = .flagsChanged
                e.setIntegerValueField(.keyboardEventKeycode, value: Int64(code))
                e.flags = flags
                e.post(tap: .cghidEventTap)
                usleep(30_000)
            }
        }
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
        "k": 40, "n": 45, "m": 46, " ": 49,
    ]
}
