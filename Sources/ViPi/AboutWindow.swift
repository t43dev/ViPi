import AppKit
import SwiftUI

final class AboutWindowController {
    private var window: NSWindow?
    private let updater: Updater
    private let prefs: Preferences
    private let showSettings: () -> Void

    init(updater: Updater, prefs: Preferences, showSettings: @escaping () -> Void) {
        self.updater = updater
        self.prefs = prefs
        self.showSettings = showSettings
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView(updater: updater, prefs: prefs, showSettings: showSettings)))
            w.styleMask = [.titled, .closable]
            w.applyGlassChrome()
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        relocalize()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func relocalize() { window?.title = tr("About ViPi") }
}

struct AboutView: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    let showSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("ViPi").font(.system(size: 26, weight: .bold)).padding(.top, 12)
            Text(tr("Version %@ (%@)", Updater.currentVersion, Updater.currentBuild))
                .font(.system(size: 12))
                .foregroundColor(Theme.inkSecondary)
                .textSelection(.enabled)
            Text(tr("Vietnamese Telex + Chinese Pinyin in one input tool.\nMade because macOS had no sensible way to type both."))
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
                .padding(.top, 12)

            HStack(spacing: 8) {
                chip("GitHub", "chevron.left.forwardslash.chevron.right", Updater.pageURL)
                chip(tr("Releases"), "shippingbox", Updater.releasesURL)
                chip(tr("Report an Issue"), "bubble.left", Updater.issuesURL)
            }
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 6) {
                shortcut(prefs.shortcut.label, tr("previous input"))
                shortcut("\(prefs.shortcut.label) ×2", tr("next input"))
                shortcut("Telex", tr("aa â · aw ă · ee ê · oo ô · ow ơ · uw ư · dd đ · s f r x j tones · z clears"))
                shortcut("Pinyin", tr("1–9 pick · Space highlighted · −/= page · Enter raw · Esc cancel"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard()
            .padding(.top, 18)

            UpdateBox(updater: updater, showSettings: showSettings)
                .padding(.top, 12)

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(tr("Telex rules:")).foregroundColor(Theme.inkSecondary)
                    credit("UniKey", "https://www.unikey.org")
                    Text(tr("· Pinyin dictionary:")).foregroundColor(Theme.inkSecondary)
                    credit("rime-ice", "https://github.com/iDvel/rime-ice")
                }
                HStack(spacing: 4) {
                    Text(tr("© 2026 ViPi contributors · Free software under the")).foregroundColor(Theme.inkSecondary)
                    credit("GPL-3.0", "https://github.com/\(Updater.repo)/blob/main/LICENSE")
                }
            }
            .font(.system(size: 11))
            .padding(.top, 14)
        }
        .padding([.horizontal, .bottom], 28)
        .padding(.top, 10)
        .frame(width: 460)
        .foregroundColor(Theme.ink)
        .tint(Theme.brandRed)
        .background(WindowBackground())
    }

    private func credit(_ title: String, _ url: String) -> some View {
        Link(title, destination: URL(string: url)!).foregroundColor(Theme.brandRedText)
    }

    private func chip(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(GlassButtonStyle(height: 28, fontSize: 12))
    }

    private func shortcut(_ key: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 130, alignment: .leading)
            Text(action)
                .font(.system(size: 12))
                .foregroundColor(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Trạng thái cập nhật (trái) và nút (phải). Tự cài hay không đổi trong Settings › General.
struct UpdateBox: View {
    @ObservedObject var updater: Updater
    let showSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                status.font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                detail.font(.system(size: 12)).foregroundColor(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            button
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle: Text(tr("Updates come from GitHub Releases."))
        case .checking: spinner(tr("Checking for updates…"))
        case .upToDate: Label(tr("ViPi is up to date."), systemImage: "checkmark.circle.fill").foregroundColor(Theme.okGreen)
        case .available(let v): Label(tr("ViPi %@ is available.", v), systemImage: "arrow.down.circle.fill").foregroundColor(Theme.brandRedText)
        case .installing(let v): spinner(tr("Installing ViPi %@…", v))
        case .ready(let v): Label(tr("ViPi %@ is installed.", v), systemImage: "checkmark.seal.fill").foregroundColor(Theme.okGreen)
        case .failed(let message): Label(message, systemImage: "exclamationmark.circle").foregroundColor(Theme.brandRedText)
        }
    }

    private func spinner(_ text: String) -> some View {
        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(text) }
    }

    @ViewBuilder private var detail: some View {
        if updater.isReleaseBuild {
            Button(updater.autoInstall ? tr("Updates install automatically · change in Settings › General")
                                       : tr("Automatic updates are off · change in Settings › General"),
                   action: showSettings)
                .buttonStyle(.plain)
        } else {
            Text(tr("Development build: automatic updates are off."))
        }
    }

    @ViewBuilder private var button: some View {
        switch updater.state {
        case .available:
            Button(tr("Install and Relaunch")) { updater.install(relaunchWhenDone: true) }
                .buttonStyle(GlassButtonStyle(role: .primary, height: 28, fontSize: 12))
        case .ready:
            Button(tr("Relaunch Now")) { updater.relaunch() }
                .buttonStyle(GlassButtonStyle(role: .primary, height: 28, fontSize: 12))
        case .checking, .installing:
            EmptyView()
        default:
            Button(tr("Check for Updates")) { updater.check(userInitiated: true) }
                .buttonStyle(GlassButtonStyle(height: 28, fontSize: 12))
        }
    }
}
