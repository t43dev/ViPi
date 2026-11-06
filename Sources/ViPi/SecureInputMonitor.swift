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

    /// Chỉ dùng khi chụp ảnh giao diện (--render).
    func preview(holder: SecureInputHolder?, since: Date?, history: [SecureInputEvent]) {
        isEnabled = holder != nil
        self.holder = holder
        self.since = since
        self.history = history
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
            w.applyGlassChrome()
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

    private static let time = formatter("HH:mm:ss")
    private static let full = formatter("HH:mm:ss  dd/MM")
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            status
            Text(tr("While any app holds Secure Input, macOS hides keystrokes from every input tool, so ViPi cannot type. Usual holders: a focused password field, Terminal/iTerm “Secure Keyboard Entry”, password managers, or loginwindow after the screen was locked. Quitting or switching away from the holder releases it."))
                .font(.system(size: 12))
                .foregroundColor(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
            history.frame(maxHeight: .infinity).glassCard()
        }
        .padding([.horizontal, .bottom], 20)
        .padding(.top, 4)
        .frame(minWidth: 560, minHeight: 360)
        .foregroundColor(Theme.ink)
        .tint(Theme.brandRed)
        .background(WindowBackground())
    }

    @ViewBuilder private var status: some View {
        let on = monitor.isEnabled
        let color = on ? Theme.brandRedText : Theme.okGreen
        // đủ chỗ thì nút nằm một hàng bên phải, chữ xuống dòng; hẹp (hoặc chữ dài) thì xếp dọc
        ViewThatFits(in: .horizontal) {
            statusRow(color) {
                if on, let h = monitor.holder { HStack(spacing: 6) { actions(h) }.fixedSize() }
            }
            statusRow(color) {
                if on, let h = monitor.holder { VStack(alignment: .trailing, spacing: 6) { actions(h) }.fixedSize() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassCard()
    }

    private func statusRow<Actions: View>(_ color: Color, @ViewBuilder actions: () -> Actions) -> some View {
        let on = monitor.isEnabled
        return HStack(spacing: 14) {
            Image(systemName: on ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(on ? tr("Secure Input is ON — typing is blocked") : tr("Secure Input is off — ViPi can type"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)
                if on { holderLine.font(.system(size: 12)).foregroundColor(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(idealWidth: 180, maxWidth: .infinity, alignment: .leading)
            actions()
        }
    }

    /// "Held by **Terminal** · PID 4821 · since 09:38:12"
    private var holderLine: Text {
        guard let h = monitor.holder else { return Text(tr("Holder unknown")) }
        var line = tr("Held by %@ · PID %@", h.name, String(h.pid))
        if let since = monitor.since { line += " · " + tr("since %@", Self.time.string(from: since)) }
        var text = AttributedString(line)
        if let name = text.range(of: h.name) { text[name].font = .system(size: 12, weight: .semibold); text[name].foregroundColor = Theme.ink }
        return Text(text)
    }

    @ViewBuilder private func actions(_ h: SecureInputHolder) -> some View {
        Button(tr("Show App")) { NSRunningApplication(processIdentifier: h.pid)?.activate(options: []) }
            .buttonStyle(GlassButtonStyle(fontSize: 12))
        Button(tr("Reveal in Finder")) {
            if let p = h.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
        }
        .buttonStyle(GlassButtonStyle(fontSize: 12))
        .disabled(h.path == nil)
        Button(tr("Quit %@", h.name)) { NSRunningApplication(processIdentifier: h.pid)?.terminate() }
            .buttonStyle(GlassButtonStyle(role: .danger, fontSize: 12))
            .disabled(NSRunningApplication(processIdentifier: h.pid) == nil)
    }

    private var history: some View {
        VStack(spacing: 0) {
            columns(Text(tr("Time")), Text(tr("Event")), Text(tr("App")), Text("PID"), Text(tr("Path")))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.inkSecondary)
                .padding(.vertical, 8)
            CardDivider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(monitor.history.enumerated()), id: \.element.id) { i, e in
                        row(e)
                            .frame(height: 28)
                            .background(i % 2 == 1 ? Theme.rowAlternate : .clear)
                    }
                }
            }
        }
    }

    private func row(_ e: SecureInputEvent) -> some View {
        columns(
            Text(Self.time.string(from: e.date)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.inkSecondary),
            HStack(spacing: 6) {
                Circle().fill(e.started ? Theme.brandRedText : Theme.okGreen).frame(width: 7, height: 7)
                Text(e.started ? tr("Enabled") : tr("Released")).lineLimit(1)
            },
            Text(e.holder?.name ?? tr("unknown")).lineLimit(1),
            Text(e.holder.map { String($0.pid) } ?? "–").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.inkSecondary),
            Text(e.holder?.path ?? "").foregroundColor(Theme.inkSecondary).lineLimit(1).truncationMode(.middle).help(e.holder?.path ?? "")
        )
        .font(.system(size: 12))
        .help(Self.full.string(from: e.date))
    }

    private func columns<A: View, B: View, C: View, D: View, E: View>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> some View {
        HStack(spacing: 10) {
            a.frame(width: 76, alignment: .leading)
            b.frame(width: 130, alignment: .leading)
            c.frame(width: 110, alignment: .leading)
            d.frame(width: 60, alignment: .leading)
            e.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
    }
}
