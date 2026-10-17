import AppKit
import ServiceManagement
import ViPiCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = InputController()
    private let secureInput = SecureInputMonitor()
    private lazy var secureWindow = SecureInputWindowController(monitor: secureInput)
    private let hud = ModeHUD()
    private var permissionTimer: Timer?
    private let defaults = UserDefaults.standard

    private var mode: InputMode {
        get { InputMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .vietnamese }
        set {
            defaults.set(newValue.rawValue, forKey: "mode")
            controller.mode = newValue
            updateIcon()
        }
    }

    /// Bộ gõ dùng gần nhất trước, [0] là bộ đang dùng.
    private var recent: [InputMode] {
        get {
            let saved = (defaults.stringArray(forKey: "recentModes") ?? []).compactMap(InputMode.init(rawValue:))
            return ([mode] + saved + InputMode.allCases).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: "recentModes") }
    }
    /// Chuỗi Ctrl+Shift liên tiếp: thứ tự lúc bắt đầu, số lần bấm, thời điểm bấm cuối.
    private var switchRun: (order: [InputMode], step: Int, at: Date)?

    private func setMode(_ m: InputMode) {
        recent = [m] + recent.filter { $0 != m }
        mode = m
    }

    /// Bấm 1 lần: về bộ gõ trước đó. Bấm liên tiếp (< 0.8 s): đi tiếp các bộ còn lại theo thứ tự dùng gần nhất.
    private func switchMode() {
        let now = Date()
        var run = switchRun.flatMap { now.timeIntervalSince($0.at) < 0.8 ? $0 : nil } ?? (order: recent, step: 0, at: now)
        run.step += 1
        run.at = now
        switchRun = run
        let target = run.order[run.step % run.order.count]
        recent = [target] + run.order.filter { $0 != target }
        mode = target
        hud.show(target)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["modernToneStyle": false, "fullWidthPunctuation": true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.mode = mode
        controller.telex.modernToneStyle = defaults.bool(forKey: "modernToneStyle")
        controller.fullWidthPunctuation = defaults.bool(forKey: "fullWidthPunctuation")
        controller.onCycleMode = { [weak self] in self?.switchMode() }

        secureInput.onChange = { [weak self] in self?.updateIcon() }
        secureInput.start()

        loadDictionary()
        setUpLoginItemOnFirstLaunch()
        startTapOrAskPermission()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.controller.cancelComposition() }

        updateIcon()
    }

    // MARK: - Setup

    private func loadDictionary() {
        guard let url = Bundle.main.url(forResource: "pinyin", withExtension: "tsv") else {
            NSLog("ViPi: pinyin.tsv missing from app bundle")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dict = try PinyinDictionary(contentsOf: url)
                DispatchQueue.main.async { self.controller.pinyin = PinyinEngine(dictionary: dict) }
            } catch {
                NSLog("ViPi: cannot load pinyin dictionary: \(error)")
            }
        }
    }

    private func startTapOrAskPermission() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary), controller.start() {
            updateIcon()
            return
        }
        // chờ người dùng cấp quyền Accessibility rồi tự bật
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted(), self.controller.start() else { return }
            t.invalidate()
            self.updateIcon()
        }
    }

    private func setUpLoginItemOnFirstLaunch() {
        // chỉ tự đăng ký khi đã nằm trong /Applications, tránh gắn vào đường dẫn ~/Downloads
        guard !defaults.bool(forKey: "loginItemConfigured"), Bundle.main.bundlePath.hasPrefix("/Applications") else { return }
        defaults.set(true, forKey: "loginItemConfigured")
        setLaunchAtLogin(true)
    }

    private var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ViPi: launch at login \(on): \(error)")
        }
    }

    // MARK: - Status item

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let blocked = secureInput.isEnabled
        button.image = StatusIcon.image(mode: mode, blocked: blocked, inactive: !controller.isRunning)
        var tip = "ViPi — \(mode.title)\nControl+Shift: previous · twice: next"
        if blocked { tip += "\nSecure Input held by \(secureInput.holder?.name ?? "unknown") — typing blocked" }
        if !controller.isRunning { tip += "\nWaiting for Accessibility permission" }
        button.toolTip = tip
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(withTitle: "ViPi \(version)", action: nil, keyEquivalent: "")

        if !controller.isRunning {
            menu.addItem(item("⚠️ Grant Accessibility Permission…", #selector(openAccessibility)))
        }
        if secureInput.isEnabled {
            let who = secureInput.holder.map { "\($0.name) (PID \($0.pid))" } ?? "unknown app"
            menu.addItem(item("🔒 Secure Input held by \(who)", #selector(showSecureInput)))
        }
        menu.addItem(.separator())

        for m in InputMode.allCases {
            let i = item(m.title, #selector(selectMode(_:)))
            i.representedObject = m.rawValue
            i.state = m == mode ? .on : .off
            menu.addItem(i)
        }
        let hint = NSMenuItem(title: "Control+Shift: previous · press twice: next", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let tone = item("Modern Tone Placement (hoà, thuý)", #selector(toggleToneStyle))
        tone.state = controller.telex.modernToneStyle ? .on : .off
        menu.addItem(tone)
        let punct = item("Full-width Chinese Punctuation", #selector(togglePunctuation))
        punct.state = controller.fullWidthPunctuation ? .on : .off
        menu.addItem(punct)
        menu.addItem(.separator())

        menu.addItem(item("Secure Input Monitor…", #selector(showSecureInput)))
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(item("About ViPi", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit ViPi", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: - Actions

    @objc private func selectMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = InputMode(rawValue: raw) { setMode(m) }
    }

    @objc private func toggleToneStyle() {
        controller.telex.modernToneStyle.toggle()
        defaults.set(controller.telex.modernToneStyle, forKey: "modernToneStyle")
    }

    @objc private func togglePunctuation() {
        controller.fullWidthPunctuation.toggle()
        defaults.set(controller.fullWidthPunctuation, forKey: "fullWidthPunctuation")
    }

    @objc private func toggleLaunchAtLogin() { setLaunchAtLogin(!launchAtLogin) }

    @objc private func showSecureInput() { secureWindow.show() }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startTapOrAskPermission()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Vietnamese (Telex) + Chinese (Pinyin) in one input tool.\n"
                + "Control+Shift switches to the previous input; press twice for the next one.\n\n"
                + "Telex rules follow UniKey. Pinyin dictionary: rime-ice (GPL-3.0).\n"
                + "github.com/kulinh/ViPi",
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Icon

enum StatusIcon {
    /// Một kiểu cho mọi chế độ: ô bo góc đặc, chữ đục rỗng (VI / 拼 / EN), ảnh template nên tự theo
    /// màu thanh menu sáng/tối. Ổ khoá khi Secure Input bật, "!" khi chưa có quyền Accessibility.
    static func image(mode: InputMode, blocked: Bool, inactive: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 16)
        let mark: NSImage = blocked
            ? symbol("lock.fill")
            : text(inactive ? "!" : mode.badge, chinese: mode == .chinese && !inactive, in: size)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
            let r = NSRect(x: rect.midX - mark.size.width / 2, y: rect.midY - mark.size.height / 2,
                           width: mark.size.width, height: mark.size.height)
            mark.draw(in: r, from: .zero, operation: .destinationOut, fraction: 1)
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func text(_ label: String, chinese: Bool, in size: NSSize) -> NSImage {
        let font = chinese ? NSFont.systemFont(ofSize: 12, weight: .bold) : NSFont.systemFont(ofSize: 10.5, weight: .heavy)
        let s = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
        let ts = s.size()
        return NSImage(size: ts, flipped: false) { _ in s.draw(at: .zero); return true }
    }

    private static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
    }
}

// MARK: - HUD khi đổi bộ gõ

final class ModeHUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let bg = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
        panel.contentView = bg
    }

    func show(_ mode: InputMode) {
        label.stringValue = "\(mode.badge)  ·  \(mode.title)"
        let width = max(220, label.intrinsicContentSize.width + 48)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.midX - width / 2, y: f.minY + f.height * 0.18, width: width, height: 64), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}
