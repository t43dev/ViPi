import AppKit
import Security

/// Tự kiểm tra cập nhật từ GitHub Releases (cả bản pre-release), tải DMG, kiểm chữ ký Developer ID
/// của team rồi thay bundle đang chạy và khởi động lại khi người dùng không gõ phím.
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(String)
        case installing(String)
        case ready(String)          // đã thay bundle, chờ khởi động lại
        case failed(String)
    }

    static let repo = "kulinh/ViPi"
    static let pageURL = URL(string: "https://github.com/\(repo)")!
    static let releasesURL = URL(string: "https://github.com/\(repo)/releases")!
    static let issuesURL = URL(string: "https://github.com/\(repo)/issues")!
    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    static var currentBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    /// Chỉ tin bản ký Developer ID của team ABONY LLC với đúng bundle id.
    private static let requirement = """
        identifier "io.github.kulinh.vipi" and anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "7H93ZLWK98"
        """

    @Published private(set) var state: State = .idle {
        didSet { onChange?() }
    }
    @Published var autoInstall: Bool {
        didSet { defaults.set(autoInstall, forKey: "autoInstallUpdates") }
    }
    var onChange: (() -> Void)?

    /// Bản dev (ký tự tạo) không tự cập nhật: đổi sang chữ ký Developer ID sẽ làm mất quyền Accessibility.
    let isReleaseBuild = (try? Updater.verify(Bundle.main.bundleURL)) != nil
    private let defaults = UserDefaults.standard
    private var latest: (version: String, dmg: URL)?
    private var timer: Timer?

    init() {
        defaults.register(defaults: ["autoInstallUpdates": true])
        autoInstall = defaults.bool(forKey: "autoInstallUpdates")
    }

    func start() {
        guard isReleaseBuild else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private var lastCheck = Date.distantPast

    private func tick() {
        if Date().timeIntervalSince(lastCheck) > 6 * 3600 { check(userInitiated: false) }
        // đã cài xong: khởi động lại khi không có phím/chuột trong 60 s
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if case .ready = state, autoInstall, idle > 60 { relaunch() }
    }

    // MARK: - Check

    func check(userInitiated: Bool) {
        switch state {
        case .checking, .installing, .ready: return
        default: break
        }
        lastCheck = Date()
        state = .checking
        Task { @MainActor in
            do {
                guard let found = try await Self.fetchLatest(), Self.isNewer(found.version, than: Self.currentVersion) else {
                    state = .upToDate
                    return
                }
                latest = found
                if autoInstall && !userInitiated && isReleaseBuild { install() } else { state = .available(found.version) }
            } catch {
                state = userInitiated ? .failed(tr("Could not reach GitHub: %@", error.localizedDescription)) : .idle
            }
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let draft: Bool
        let assets: [Asset]
    }

    /// `/releases/latest` bỏ qua pre-release, nên lấy danh sách và chọn bản mới nhất có DMG.
    private static func fetchLatest() async throws -> (version: String, dmg: URL)? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ViPi/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let candidates = try JSONDecoder().decode([Release].self, from: data).compactMap { r -> (String, URL)? in
            guard !r.draft, let dmg = r.assets.first(where: { $0.name.hasSuffix(".dmg") }) else { return nil }
            return (r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name, dmg.browser_download_url)
        }
        return candidates.max { isNewer($1.0, than: $0.0) }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let parts = { (s: String) in s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let u = i < x.count ? x[i] : 0, v = i < y.count ? y[i] : 0
            if u != v { return u > v }
        }
        return false
    }

    // MARK: - Install

    func install(relaunchWhenDone: Bool = false) {
        guard let latest else { return }
        state = .installing(latest.version)
        Task.detached(priority: .utility) {
            do {
                try await Self.download(latest.dmg)
                await MainActor.run {
                    self.state = .ready(latest.version)
                    if relaunchWhenDone { self.relaunch() }
                }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    static func download(_ dmgURL: URL, replacing dest: URL = Bundle.main.bundleURL) async throws {
        let fm = FileManager.default
        let (file, response) = try await URLSession.shared.download(from: dmgURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError(tr("Download failed (HTTP %@)", String(http.statusCode))) }
        // thư mục tạm cùng ổ đĩa với ViPi.app để thay bằng cách đổi tên, không ghi đè lên file đang chạy
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dest, create: true)
        defer { try? fm.removeItem(at: work) }
        let dmg = work.appendingPathComponent("ViPi.dmg")
        try fm.moveItem(at: file, to: dmg)

        let mount = work.appendingPathComponent("mnt")
        try run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path)
        defer { try? run("/usr/bin/hdiutil", "detach", mount.path, "-force") }
        let mounted = mount.appendingPathComponent("ViPi.app")
        try verify(mounted)
        let staged = work.appendingPathComponent("ViPi.app")
        try run("/usr/bin/ditto", mounted.path, staged.path)
        try verify(staged)
        do {
            _ = try fm.replaceItemAt(dest, withItemAt: staged)
        } catch {
            throw UpdateError(tr("Cannot replace %@. Open the DMG from GitHub and drag ViPi to Applications.", dest.path))
        }
    }

    static func verify(_ app: URL) throws {
        var code: SecStaticCode?
        var req: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req,
              SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
        else { throw UpdateError(tr("The update is not signed by the ViPi developer")) }
    }

    private static func run(_ tool: String, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError(tr("%@ failed", URL(fileURLWithPath: tool).lastPathComponent)) }
    }

    /// Mở lại ViPi sau khi tiến trình hiện tại thoát.
    func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
