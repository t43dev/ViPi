import AppKit
import SwiftUI
import ViPiCore

let app = NSApplication.shared
let args = CommandLine.arguments

/// Chụp một view ra PNG ở độ phân giải 2x (ảnh sắc nét cho README).
func writePNG(_ view: NSView, to path: String) {
    let b = view.bounds
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * 2), pixelsHigh: Int(b.height * 2),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = b.size
    view.cacheDisplay(in: b, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}
/// Chụp một cửa sổ đang hiện trên màn hình đúng như người dùng thấy (cả thanh tiêu đề, bóng, giao diện tối);
/// cửa sổ của chính mình nên không cần quyền Screen Recording. Màn hình phải đang bật (caffeinate -u).
func captureWindow(_ w: NSWindow, to path: String) {
    guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}
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
    writePNG(view, to: args[i + 1])
} else if let i = args.firstIndex(of: "--snapshot-settings"), i + 1 < args.count {
    // mở từng tab Settings thành cửa sổ thật trên màn hình rồi chụp: <prefix>-0.png … (-appearance dark để chụp bản tối)
    app.setActivationPolicy(.regular)
    app.appearance = Preferences().appearance.nsAppearance
    let windows = (0..<4).map { tab -> NSWindow in
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(
            prefs: Preferences(), updater: Updater(), userDictionary: PinyinUserDictionary(fileURL: nil),
            onRecording: { _ in }, showSecureInput: {}, initialTab: tab)))
        w.styleMask = [.titled, .closable]
        w.title = tr("ViPi Settings")
        w.setFrameOrigin(NSPoint(x: 80 + tab * 40, y: 120 + tab * 40))
        w.orderFrontRegardless()
        return w
    }
    // khung chọn chữ Hán mẫu (ảnh cho README): <prefix>-candidates.png
    let candidates = NSWindow(contentViewController: NSHostingController(rootView: CandidateView(
        preedit: "ni hao", items: ["你好", "拟好", "你", "尼", "泥"], highlight: 0, hasPrev: false, hasNext: true)
        .padding(16)))
    candidates.styleMask = [.borderless]
    candidates.isOpaque = false
    candidates.backgroundColor = .clear
    candidates.setFrameOrigin(NSPoint(x: 700, y: 120))
    candidates.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        // bản 1x đúng như trên màn hình, và bản 2x vẽ lại từ view (sắc nét cho README)
        captureWindow(candidates, to: "\(args[i + 1])-candidates.png")
        if let v = candidates.contentView { writePNG(v, to: "\(args[i + 1])-candidates@2x.png") }
        for (tab, w) in windows.enumerated() {
            captureWindow(w, to: "\(args[i + 1])-\(tab).png")
            if let v = w.contentView?.superview { writePNG(v, to: "\(args[i + 1])-\(tab)@2x.png") }
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
