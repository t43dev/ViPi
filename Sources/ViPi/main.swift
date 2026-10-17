import AppKit

let app = NSApplication.shared
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--selftest") {
    let delegate = SelfTest(args: Array(args[(i + 1)...]))
    app.delegate = delegate
    app.run()
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
