import AppKit
import SwiftUI
import ViPiCore

/// `ViPi --render <prefix>`: chụp mọi màn với dữ liệu mẫu, dùng để so với thiết kế và cập nhật assets/readme.
/// Màn hình phải đang bật (caffeinate -u). Nên chạy bằng bundle id riêng để defaults sạch.
enum Snapshots {
    private static var windows: [(name: String, window: NSWindow)] = []

    static func run(prefix: String) {
        app.setActivationPolicy(.regular)
        let prefs = Preferences()
        app.appearance = prefs.appearance.nsAppearance
        let dictionary = PinyinUserDictionary(fileURL: nil)

        for (tab, name) in ["general", "vietnamese", "chinese", "shortcuts"].enumerated() {
            add("settings-\(name)", titled: tr("ViPi Settings"), SettingsView(
                prefs: prefs, updater: Updater(), userDictionary: dictionary, onRecording: { _ in }, showSecureInput: {},
                navigation: SettingsNavigation(tab: tab)))
        }

        let states: [(String, Updater.State)] = [
            ("idle", .idle), ("checking", .checking), ("uptodate", .upToDate), ("available", .available("0.5.0")),
            ("installing", .installing("0.5.0")), ("ready", .ready("0.5.0")), ("failed", .failed(tr("Could not reach GitHub: %@", "timed out"))),
        ]
        for (name, state) in states {
            let updater = Updater()
            updater.preview(state)
            add("about-\(name)", titled: tr("About ViPi"), AboutView(updater: updater, prefs: prefs, showSettings: {}))
        }

        let holder = SecureInputHolder(pid: getpid(), name: "Terminal", bundleID: "com.apple.Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let password = SecureInputHolder(pid: 3310, name: "1Password", bundleID: nil, path: "/Applications/1Password.app")
        let now = Date()
        let history = [
            SecureInputEvent(date: now, started: true, holder: holder),
            SecureInputEvent(date: now.addingTimeInterval(-992), started: false, holder: password),
            SecureInputEvent(date: now.addingTimeInterval(-1030), started: true, holder: password),
        ]
        for (name, on) in [("monitor-on", true), ("monitor-off", false)] {
            let monitor = SecureInputMonitor()
            monitor.preview(holder: on ? holder : nil, since: on ? now : nil, history: history)
            add(name, titled: tr("Secure Input Monitor"), SecureInputView(monitor: monitor, prefs: prefs), size: NSSize(width: 640, height: 420))
        }

        add("firstrun", titled: "", FirstRunView(
            prefs: prefs, currentInput: { .english }, inputs: { prefs.autoSwitch ? [.english, .chinese] : InputMode.allCases },
            selectInput: { _ in }, openAccessibility: {}, onRecording: { _ in }, close: {}))

        addOverlay("candidates", CandidateView(preedit: "ni hao", items: ["你好", "拟好", "你", "尼", "泥"], highlight: 0, hasPrev: false, hasNext: true))
        addOverlay("candidates-last", CandidateView(preedit: "ni", items: ["妮", "倪", "霓"], highlight: 1, hasPrev: true, hasNext: false))
        for (name, mode) in [("hud-ve", InputMode.english), ("hud-zh", InputMode.chinese)] {
            addOverlay(name, ModeHUDView(badge: mode.badge(autoSwitch: true), title: mode.title(autoSwitch: true)))
        }

        writeIcons(to: "\(prefix)-icons.png")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { captureNext(prefix: prefix) }
    }

    private static func add<V: View>(_ name: String, titled title: String, _ view: V, size: NSSize? = nil) {
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.styleMask = [.titled, .closable]
        w.applyGlassChrome()
        if let size { w.setContentSize(size) }
        w.title = title
        w.setFrameOrigin(NSPoint(x: 60 + windows.count * 12, y: 60 + windows.count * 12))
        w.orderFrontRegardless()
        windows.append((name, w))
    }

    private static func addOverlay<V: View>(_ name: String, _ view: V) {
        let host = NSHostingView(rootView: view)
        let w = NSPanel(contentRect: NSRect(origin: NSPoint(x: 700, y: 120 + windows.count * 6), size: host.fittingSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.contentView = host
        w.orderFrontRegardless()
        windows.append((name, w))
    }

    /// Lần lượt đưa từng cửa sổ lên trước làm cửa sổ chính (cửa sổ phụ bị macOS làm xám nút và toggle) rồi chụp.
    private static func captureNext(prefix: String) {
        guard let (name, w) = windows.first else { exit(0) }
        windows.removeFirst()
        w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            capture(w, to: "\(prefix)-\(name).png")
            w.orderOut(nil)
            captureNext(prefix: prefix)
        }
    }

    /// Cửa sổ của chính mình nên không cần quyền Screen Recording.
    private static func capture(_ w: NSWindow, to path: String) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution, .boundsIgnoreFraming]) else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Mọi trạng thái của biểu tượng thanh menu, phóng to 4 lần trên nền trắng.
    private static func writeIcons(to path: String) {
        let icons = [
            StatusIcon.image(mode: .english, autoSwitch: true, blocked: false, inactive: false),
            StatusIcon.image(mode: .vietnamese, autoSwitch: false, blocked: false, inactive: false),
            StatusIcon.image(mode: .chinese, autoSwitch: true, blocked: false, inactive: false),
            StatusIcon.image(mode: .english, autoSwitch: false, blocked: false, inactive: false),
            StatusIcon.image(mode: .english, autoSwitch: true, blocked: true, inactive: false),
            StatusIcon.image(mode: .english, autoSwitch: true, blocked: false, inactive: true),
        ]
        let sheet = NSImage(size: NSSize(width: 110 * icons.count + 10, height: 84), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (i, icon) in icons.enumerated() {
                icon.draw(in: NSRect(x: 10 + 110 * i, y: 10, width: 96, height: 64))
            }
            return true
        }
        guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
