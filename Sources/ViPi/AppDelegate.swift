import AppKit
import ViPiCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = InputController()
    private let secureInput = SecureInputMonitor()
    private lazy var secureWindow = SecureInputWindowController(monitor: secureInput, prefs: prefs)
    private let updater = Updater()
    private let prefs = Preferences()
    private lazy var aboutWindow = AboutWindowController(updater: updater, prefs: prefs)
    private lazy var settingsWindow = SettingsWindowController(
        prefs: prefs, updater: updater,
        onRecording: { [weak self] in self?.controller.isRecordingShortcut = $0 },
        showSecureInput: { [weak self] in self?.secureWindow.show() })
    private let hud = ModeHUD()
    private var permissionTimer: Timer?
    private var lexicon: VietnameseLexicon?
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.mode = mode
        if let url = Bundle.main.url(forResource: "vietnamese-syllables", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            lexicon = VietnameseLexicon(text: text)
        }
        prefs.onChange = { [weak self] in self?.applyPreferences() }
        applyPreferences()
        controller.onCycleMode = { [weak self] in self?.switchMode() }

        secureInput.onChange = { [weak self] in self?.updateIcon() }
        secureInput.start()

        loadDictionary()
        setUpLoginItemOnFirstLaunch()
        updater.start()
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
        prefs.launchAtLogin = true
    }

    // MARK: - Status item

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let blocked = secureInput.isEnabled
        button.image = StatusIcon.image(mode: mode, blocked: blocked, inactive: !controller.isRunning)
        var tip = "ViPi — \(mode.title)\n" + tr("%@: previous · twice: next", prefs.shortcut.label)
        if blocked { tip += "\n" + tr("Secure Input held by %@ — typing blocked", secureInput.holder?.name ?? tr("unknown")) }
        if !controller.isRunning { tip += "\n" + tr("Waiting for Accessibility permission") }
        button.toolTip = tip
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(withTitle: "ViPi \(version)", action: nil, keyEquivalent: "")

        if !controller.isRunning {
            menu.addItem(item(tr("⚠️ Grant Accessibility Permission…"), #selector(openAccessibility)))
        }
        switch updater.state {
        case .available(let v): menu.addItem(item(tr("⬆️ Update to ViPi %@…", v), #selector(showAbout)))
        case .ready(let v): menu.addItem(item(tr("⬆️ Relaunch to Finish Updating to %@", v), #selector(relaunchForUpdate)))
        default: break
        }
        if secureInput.isEnabled {
            let who = secureInput.holder.map { "\($0.name) (PID \($0.pid))" } ?? tr("unknown app")
            menu.addItem(item(tr("🔒 Secure Input held by %@", who), #selector(showSecureInput)))
        }
        menu.addItem(.separator())

        for m in InputMode.allCases {
            let i = item(m.title, #selector(selectMode(_:)))
            i.representedObject = m.rawValue
            i.state = m == mode ? .on : .off
            menu.addItem(i)
        }
        let hint = NSMenuItem(title: tr("%@: previous · twice: next", prefs.shortcut.label), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        menu.addItem(item(tr("Settings…"), #selector(showSettings), key: ","))
        menu.addItem(item(tr("Secure Input Monitor…"), #selector(showSecureInput)))
        menu.addItem(item(tr("Check for Updates…"), #selector(checkForUpdates)))
        menu.addItem(item(tr("About ViPi"), #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item(tr("Quit ViPi"), #selector(quit), key: "q"))
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

    @objc private func showSettings() { settingsWindow.show() }

    private func applyPreferences() {
        controller.telex.modernToneStyle = prefs.modernToneStyle
        controller.telex.spellCheck = prefs.spellCheck
        controller.telex.lexicon = prefs.spellCheck && prefs.restoreNonVietnamese ? lexicon : nil
        controller.macros = prefs.macrosEnabled ? prefs.macroTable : nil
        controller.englishMacros = prefs.macrosInEnglish ? prefs.macroTable : nil
        controller.fullWidthPunctuation = prefs.fullWidthPunctuation
        controller.shortcut = prefs.shortcut
        settingsWindow.relocalize()
        aboutWindow.relocalize()
        secureWindow.relocalize()
        updateIcon()
    }

    @objc private func showSecureInput() { secureWindow.show() }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startTapOrAskPermission()
    }

    @objc private func showAbout() { aboutWindow.show() }

    @objc private func checkForUpdates() {
        aboutWindow.show()
        updater.check(userInitiated: true)
    }

    @objc private func relaunchForUpdate() { updater.relaunch() }

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
