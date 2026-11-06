import AppKit
import SwiftUI
import ViPiCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = InputController()
    private let secureInput = SecureInputMonitor()
    private lazy var secureWindow = SecureInputWindowController(monitor: secureInput, prefs: prefs)
    private let updater = Updater()
    private let prefs = Preferences()
    private lazy var aboutWindow = AboutWindowController(updater: updater, prefs: prefs) { [weak self] in self?.settingsWindow.show(tab: 0) }
    private lazy var firstRunWindow = FirstRunWindowController { [weak self] close in
        FirstRunView(prefs: self?.prefs ?? Preferences(),
                     currentInput: { self?.mode ?? .vietnamese },
                     inputs: { self?.menuInputs ?? InputMode.allCases },
                     selectInput: { self?.setMode($0) },
                     openAccessibility: { self?.openAccessibility() },
                     onRecording: { self?.controller.isRecordingShortcut = $0 },
                     close: close)
    }
    private lazy var settingsWindow = SettingsWindowController(
        prefs: prefs, updater: updater, userDictionary: userDictionary,
        onRecording: { [weak self] in self?.controller.isRecordingShortcut = $0 },
        showSecureInput: { [weak self] in self?.secureWindow.show() })
    /// Từ/cụm tiếng Trung người dùng đã chọn, lưu trong Application Support/ViPi/learned.json.
    private let userDictionary = PinyinUserDictionary(
        fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ViPi/learned.json"))
    private var traditional: ChineseConverter?
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
    /// Các bộ gõ người dùng chọn được, gần nhất trước: tự đổi Anh/Việt đang bật thì hai bộ đó gộp làm một (VE).
    private var inputs: [InputMode] {
        guard prefs.autoSwitch else { return recent }
        let mixed = recent.first { $0 != .chinese }!
        return recent.filter { $0 == mixed || $0 == .chinese }
    }
    /// Các bộ gõ theo thứ tự cố định (menu, màn chào): VE luôn đứng đầu.
    private var menuInputs: [InputMode] {
        prefs.autoSwitch ? [recent.first { $0 != .chinese }!, .chinese] : InputMode.allCases
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
        var run = switchRun.flatMap { now.timeIntervalSince($0.at) < 0.8 ? $0 : nil } ?? (order: inputs, step: 0, at: now)
        run.step += 1
        run.at = now
        switchRun = run
        let target = run.order[run.step % run.order.count]
        recent = [target] + run.order.filter { $0 != target }
        mode = target
        hud.show(target, autoSwitch: prefs.autoSwitch)
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
        controller.onAutoSwitch = { [weak self] in self?.setMode($0) }

        secureInput.onChange = { [weak self] in self?.updateIcon() }
        secureInput.start()

        loadDictionary()
        setUpLoginItemOnFirstLaunch()
        updater.start()
        startTap(prompt: false)
        if !AXIsProcessTrusted() || !prefs.didFinishFirstRun {
            prefs.didFinishFirstRun = true
            firstRunWindow.show()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.controller.cancelComposition() }

        updateIcon()
    }

    // MARK: - Setup

    private func loadDictionary() {
        guard let dir = Bundle.main.resourceURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dict = try PinyinDictionary(directory: dir)
                let s2t = try? ChineseConverter(contentsOf: dir.appendingPathComponent("s2t.bin"))
                let bigram = try? BigramModel(contentsOf: dir.appendingPathComponent("bigram.bin"))
                DispatchQueue.main.async {
                    self.traditional = s2t
                    let engine = PinyinEngine(dictionary: dict)
                    engine.bigram = bigram
                    self.controller.pinyin = engine
                    self.applyPreferences()   // engine mới sinh: áp âm mờ, phồn thể, học từ
                }
            } catch {
                NSLog("ViPi: cannot load pinyin dictionary: \(error)")
            }
        }
    }

    /// `prompt`: hỏi bằng hộp thoại hệ thống (cũng thêm ViPi vào danh sách Accessibility); lúc mở app đã có màn chào.
    private func startTap(prompt: Bool) {
        let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([option: prompt] as CFDictionary), controller.start() {
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
        button.image = StatusIcon.image(mode: mode, autoSwitch: prefs.autoSwitch, blocked: blocked, inactive: !controller.isRunning)
        var tip = "ViPi — \(mode.title(autoSwitch: prefs.autoSwitch))\n" + tr("%@: previous · twice: next", prefs.shortcut.label)
        if blocked { tip += "\n" + tr("Secure Input held by %@ — typing blocked", secureInput.holder?.name ?? tr("unknown")) }
        if !controller.isRunning { tip += "\n" + tr("Waiting for Accessibility permission") }
        button.toolTip = tip
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(withTitle: "ViPi \(version)", action: nil, keyEquivalent: "")

        if !controller.isRunning {
            let i = item(tr("Grant Accessibility Permission…"), #selector(showFirstRun))
            i.image = symbol("exclamationmark.triangle.fill", Theme.alertGoldNS)
            menu.addItem(i)
        }
        switch updater.state {
        case .available(let v):
            let i = item(tr("Update to ViPi %@…", v), #selector(showAbout))
            i.image = symbol("arrow.down.circle.fill", Theme.brandRedNS)
            menu.addItem(i)
        case .ready(let v):
            let i = item(tr("Relaunch to Finish Updating to %@", v), #selector(relaunchForUpdate))
            i.image = symbol("arrow.down.circle.fill", Theme.brandRedNS)
            menu.addItem(i)
        default: break
        }
        if secureInput.isEnabled {
            let who = secureInput.holder.map { "\($0.name) (PID \($0.pid))" } ?? tr("unknown app")
            let i = NSMenuItem(title: tr("Secure Input held by %@", who), action: nil, keyEquivalent: "")
            i.image = symbol("lock.fill", .secondaryLabelColor)
            i.isEnabled = false
            menu.addItem(i)
        }
        menu.addItem(.separator())

        for m in menuInputs {
            let i = item(m.title(autoSwitch: prefs.autoSwitch), #selector(selectMode(_:)))
            i.representedObject = m.rawValue
            i.state = m == mode ? .on : .off
            i.indentationLevel = 1
            menu.addItem(i)
        }
        let hint = NSMenuItem(title: tr("%@: previous · twice: next", prefs.shortcut.label), action: nil, keyEquivalent: "")
        hint.attributedTitle = NSAttributedString(string: hint.title, attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.disabledControlTextColor])
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

    private func symbol(_ name: String, _ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
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
        // VE là một bộ gõ: từ tắt theo một trong hai công tắc, dù lúc đó đang ở tiếng Việt hay tiếng Anh
        let macrosEverywhere = prefs.autoSwitch && (prefs.macrosEnabled || prefs.macrosInEnglish)
        controller.macros = macrosEverywhere || prefs.macrosEnabled ? prefs.macroTable : nil
        controller.englishMacros = macrosEverywhere || prefs.macrosInEnglish ? prefs.macroTable : nil
        controller.fullWidthPunctuation = prefs.fullWidthPunctuation
        if !prefs.autoSwitch {
            controller.autoSwitch = nil
        } else if controller.autoSwitch == nil, let auto = loadAutoSwitch() {
            controller.autoSwitch = auto
            if mode == .vietnamese { setMode(.english) }   // vừa bật (hoặc mở app): VE bắt đầu ở tiếng Anh; đang gõ Trung thì để yên
        }
        if let py = controller.pinyin {
            if py.fuzzyRules != prefs.fuzzyRules { py.fuzzyRules = prefs.fuzzyRules }
            let converter = prefs.traditionalChinese ? traditional : nil
            if py.converter !== converter { py.converter = converter }
            py.userDictionary = prefs.learnWords ? userDictionary : nil
        }
        controller.shortcut = prefs.shortcut
        NSApp.appearance = prefs.appearance.nsAppearance
        settingsWindow.relocalize()
        aboutWindow.relocalize()
        secureWindow.relocalize()
        updateIcon()
    }

    private func loadAutoSwitch() -> AutoSwitch? {
        Bundle.main.resourceURL.flatMap { try? AutoSwitch(directory: $0) }
    }

    @objc private func showSecureInput() { secureWindow.show() }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startTap(prompt: true)
    }

    @objc private func showFirstRun() { firstRunWindow.show() }

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
    /// Khung viền bo góc, chữ căn giữa (VI / 拼 / EN / VE), ảnh template nên tự theo màu thanh menu.
    /// Secure Input: ổ khoá trong khung. Chưa có quyền Accessibility: khung nét đứt + "!".
    static func image(mode: InputMode, autoSwitch: Bool, blocked: Bool, inactive: Bool) -> NSImage {
        let label = mode.badge(autoSwitch: autoSwitch)
        let img = NSImage(size: NSSize(width: 24, height: 16), flipped: true) { rect in
            NSColor.black.set()
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
            frame.lineWidth = 1.5
            if inactive, !blocked { frame.setLineDash([2.2, 1.4], count: 2, phase: 0) }
            frame.stroke()
            if blocked {
                NSBezierPath(roundedRect: NSRect(x: 8.5, y: 7, width: 7, height: 5.5), xRadius: 1, yRadius: 1).fill()
                let shackle = NSBezierPath()
                shackle.lineWidth = 1.4
                shackle.move(to: NSPoint(x: 9.75, y: 7))
                shackle.line(to: NSPoint(x: 9.75, y: 5.5))
                shackle.appendArc(withCenter: NSPoint(x: 12, y: 5.5), radius: 2.25, startAngle: 180, endAngle: 0, clockwise: false)
                shackle.line(to: NSPoint(x: 14.25, y: 7))
                shackle.stroke()
            } else if inactive {
                draw("!", size: 11, in: rect)
            } else {
                draw(label, size: mode == .chinese ? 10 : 9.5, in: rect)
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func draw(_ text: String, size: CGFloat, in rect: NSRect) {
        let s = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.black])
        let ts = s.size()
        s.draw(at: NSPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2))
    }
}

// MARK: - HUD khi đổi bộ gõ

struct ModeHUDView: View {
    let badge: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Text(badge)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 28)
                .background(Theme.brandRed, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.ink)
                .lineLimit(1)
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .frame(minWidth: 220, minHeight: 64)
        .glass(radius: 14, prominent: true, shadow: false)   // SwiftUI không được vẽ bóng ra ngoài panel
        .fixedSize()
    }
}

final class ModeHUD {
    private let panel: NSPanel
    private let host = NSHostingView(rootView: ModeHUDView(badge: "", title: ""))
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
    }

    func show(_ mode: InputMode, autoSwitch: Bool) {
        host.rootView = ModeHUDView(badge: mode.badge(autoSwitch: autoSwitch), title: mode.title(autoSwitch: autoSwitch))
        let size = host.fittingSize
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.18, width: size.width, height: size.height), display: true)
        }
        hideWork?.cancel()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        fade(to: 1, duration: 0.12)
        let work = DispatchWorkItem { [weak self] in
            self?.fade(to: 0, duration: 0.18) {
                if self?.hideWork?.isCancelled == false { self?.panel.orderOut(nil) }   // đổi tiếp trong lúc mờ dần: để yên
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, done: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        }, completionHandler: done)
    }
}
