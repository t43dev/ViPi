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
    let view = NSHostingView(rootView: AboutView(updater: Updater()))
    view.frame = NSRect(origin: .zero, size: view.fittingSize)
    view.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
} else if let i = args.firstIndex(of: "--chord") {
    // kiểm thử Ctrl+Shift: --chord <số lần> [khoảng cách ms]
    let rest = Array(args[(i + 1)...])
    SelfTest.pressChord(times: Int(rest.first ?? "") ?? 1, gapMs: rest.count > 1 ? Double(rest[1])! : 250)
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
