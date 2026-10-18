import AppKit
import SwiftUI

let app = NSApplication.shared
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--verify-update"), i + 1 < args.count {
    // kiểm tra một ViPi.app có qua được bước kiểm chữ ký của bộ cập nhật không
    do { try Updater.verify(URL(fileURLWithPath: args[i + 1])); print("VERIFY OK") } catch { print("VERIFY FAIL: \(error.localizedDescription)") }
} else if let i = args.firstIndex(of: "--install-update"), i + 2 < args.count {
    // thử luồng cài: --install-update <file.dmg> <ViPi.app cần thay>
    let done = DispatchSemaphore(value: 0)
    Task {
        do { try await Updater.download(URL(fileURLWithPath: args[i + 1]), replacing: URL(fileURLWithPath: args[i + 2])); print("INSTALL OK") }
        catch { print("INSTALL FAIL: \(error.localizedDescription)") }
        done.signal()
    }
    done.wait()
} else if let i = args.firstIndex(of: "--render-about"), i + 1 < args.count {
    // chụp cửa sổ About ra PNG (kiểm tra giao diện không cần màn hình)
    let view = NSHostingView(rootView: AboutView(updater: Updater(), prefs: Preferences()))
    view.frame = NSRect(origin: .zero, size: view.fittingSize)
    view.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
} else if let i = args.firstIndex(of: "--snapshot-settings"), i + 1 < args.count {
    // mở từng tab Settings thành cửa sổ thật rồi tự chụp: <prefix>-0.png …
    app.setActivationPolicy(.regular)
    let windows = (0..<4).map { tab -> NSWindow in
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(
            prefs: Preferences(), updater: Updater(), onRecording: { _ in }, showSecureInput: {}, initialTab: tab)))
        w.styleMask = [.titled, .closable]
        w.title = tr("ViPi Settings")
        w.setFrameOrigin(NSPoint(x: 80 + tab * 40, y: 120 + tab * 40))
        w.orderFrontRegardless()
        return w
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        for (tab, w) in windows.enumerated() {
            guard let v = w.contentView?.superview, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(args[i + 1])-\(tab).png"))
        }
        exit(0)
    }
    app.run()
} else if let i = args.firstIndex(of: "--chord") {
    // kiểm thử Ctrl+Shift: --chord <số lần> [khoảng cách ms]
    let rest = Array(args[(i + 1)...])
    SelfTest.pressChord(times: Int(rest.first ?? "") ?? 1, gapMs: rest.count > 1 ? Double(rest[1])! : 250,
                        withSpace: rest.contains("space"))
} else if let i = args.firstIndex(of: "--selftest") {
    let delegate = SelfTest(args: Array(args[(i + 1)...]))
    app.delegate = delegate
    app.run()
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
