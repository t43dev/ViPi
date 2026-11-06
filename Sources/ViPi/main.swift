import AppKit
import ViPiCore

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
} else if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
    // mở từng màn thành cửa sổ thật rồi chụp: <prefix>-<màn>.png (-appearance dark, -uiLanguage vi để đổi kiểu)
    Snapshots.run(prefix: args[i + 1])
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
