import AppKit

let app = NSApplication.shared
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--chord") {
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
