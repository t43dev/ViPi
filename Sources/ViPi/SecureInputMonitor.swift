import AppKit
import Carbon
import IOKit
import SwiftUI

/// Theo dõi Secure Event Input: khi bật, macOS giấu mọi phím khỏi event tap nên ViPi không gõ được.
/// PID đang giữ lấy từ IORegistry (IOConsoleUsers → kCGSSessionSecureInputPID), giống `ioreg -l -w0 | grep SecureInput`.
struct SecureInputHolder: Equatable {
    let pid: pid_t
    let name: String
    let bundleID: String?
    let path: String?
}

struct SecureInputEvent: Identifiable {
    let id = UUID()
    let date: Date
    let started: Bool
    let holder: SecureInputHolder?
}

final class SecureInputMonitor: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var holder: SecureInputHolder?
    @Published private(set) var since: Date?
    @Published private(set) var history: [SecureInputEvent] = []
    var onChange: (() -> Void)?
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        let enabled = IsSecureEventInputEnabled()
        let current = enabled ? Self.holderPID().map(Self.describe) : nil
        guard enabled != isEnabled || current != holder else { return }
        let now = Date()
        if isEnabled { history.insert(SecureInputEvent(date: now, started: false, holder: holder), at: 0) }
        if enabled { history.insert(SecureInputEvent(date: now, started: true, holder: current), at: 0) }
        if history.count > 200 { history.removeLast(history.count - 200) }
        isEnabled = enabled
        holder = current
        since = enabled ? now : nil
        onChange?()
    }

    static func holderPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        let pids = users.compactMap { u -> (pid: pid_t, onConsole: Bool)? in
            guard let n = u["kCGSSessionSecureInputPID"] as? NSNumber else { return nil }
            return (pid_t(n.int32Value), (u["kCGSSessionOnConsoleKey"] as? Bool) ?? false)
        }
        return (pids.first { $0.onConsole } ?? pids.first)?.pid
    }

    static func describe(_ pid: pid_t) -> SecureInputHolder {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return SecureInputHolder(pid: pid, name: app.localizedName ?? "pid \(pid)",
                                     bundleID: app.bundleIdentifier, path: app.bundleURL?.path ?? app.executableURL?.path)
        }
        var buf = [CChar](repeating: 0, count: 4096)
        let path = proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "pid \(pid)"
        return SecureInputHolder(pid: pid, name: name, bundleID: nil, path: path)
    }
}

// MARK: - Window

final class SecureInputWindowController {
    private var window: NSWindow?
    private let monitor: SecureInputMonitor
    private let prefs: Preferences

    init(monitor: SecureInputMonitor, prefs: Preferences) {
        self.monitor = monitor
        self.prefs = prefs
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SecureInputView(monitor: monitor, prefs: prefs)))
            w.setContentSize(NSSize(width: 640, height: 420))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        relocalize()
        monitor.poll()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func relocalize() { window?.title = tr("Secure Input Monitor") }
}

struct SecureInputView: View {
    @ObservedObject var monitor: SecureInputMonitor
    @ObservedObject var prefs: Preferences   // vẽ lại khi đổi ngôn ngữ

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss  dd/MM"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            status
            Text(tr("While any app holds Secure Input, macOS hides keystrokes from every input tool, so ViPi cannot type. Usual holders: a focused password field, Terminal/iTerm “Secure Keyboard Entry”, password managers, or loginwindow after the screen was locked. Quitting or switching away from the holder releases it."))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tr("History")).font(.headline)
            Table(monitor.history) {
                TableColumn(tr("Time")) { e in Text(Self.time.string(from: e.date)).monospacedDigit() }
                    .width(110)
                TableColumn(tr("Event")) { e in Text(e.started ? tr("Enabled") : tr("Released")).foregroundColor(e.started ? .red : .green) }
                    .width(70)
                TableColumn(tr("App")) { e in Text(e.holder?.name ?? tr("unknown")) }
                TableColumn("PID") { e in Text(e.holder.map { String($0.pid) } ?? "–").monospacedDigit() }
                    .width(60)
                TableColumn(tr("Path")) { e in Text(e.holder?.path ?? "").lineLimit(1).truncationMode(.middle).help(e.holder?.path ?? "") }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 360)
    }

    @ViewBuilder private var status: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: monitor.isEnabled ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 28))
                .foregroundColor(monitor.isEnabled ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                if monitor.isEnabled {
                    Text(tr("Secure Input is ON — typing is blocked")).font(.title3.bold())
                    if let h = monitor.holder {
                        Text(tr("Held by %@ (PID %@)", h.name, String(h.pid)) + (h.bundleID.map { " · \($0)" } ?? ""))
                    } else {
                        Text(tr("Holder unknown"))
                    }
                    if let since = monitor.since {
                        Text(tr("Since %@", Self.time.string(from: since))).font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text(tr("Secure Input is off — ViPi can type")).font(.title3.bold())
                }
            }
            Spacer()
            if monitor.isEnabled, let h = monitor.holder {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack {
                        Button(tr("Show App")) { NSRunningApplication(processIdentifier: h.pid)?.activate(options: []) }
                        Button(tr("Reveal in Finder")) {
                            if let p = h.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                        }.disabled(h.path == nil)
                    }
                    Button(tr("Quit %@", h.name)) { NSRunningApplication(processIdentifier: h.pid)?.terminate() }
                        .disabled(NSRunningApplication(processIdentifier: h.pid) == nil)
                }
            }
        }
    }
}
