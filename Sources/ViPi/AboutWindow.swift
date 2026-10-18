import AppKit
import SwiftUI

final class AboutWindowController {
    private var window: NSWindow?
    private let updater: Updater
    private let prefs: Preferences

    init(updater: Updater, prefs: Preferences) {
        self.updater = updater
        self.prefs = prefs
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView(updater: updater, prefs: prefs)))
            w.styleMask = [.titled, .closable]
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

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("ViPi").font(.system(size: 26, weight: .bold))
                Text(tr("Version %@ (%@)", Updater.currentVersion, Updater.currentBuild))
                    .font(.callout).foregroundColor(.secondary).textSelection(.enabled)
            }
            Text(tr("Vietnamese Telex + Chinese Pinyin in one input tool.\nMade because macOS had no sensible way to type both."))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link(destination: Updater.pageURL) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: Updater.releasesURL) { Label(tr("Releases"), systemImage: "shippingbox") }
                Link(destination: Updater.issuesURL) { Label(tr("Report an Issue"), systemImage: "exclamationmark.bubble") }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    shortcut(prefs.shortcut.label, tr("previous input"))
                    shortcut("\(prefs.shortcut.label) ×2", tr("next input"))
                    shortcut("Telex", tr("aa â · aw ă · ee ê · oo ô · ow ơ · uw ư · dd đ · s f r x j tones · z clears"))
                    shortcut("Pinyin", tr("1–9 pick · Space highlighted · −/= page · Enter raw · Esc cancel"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        updateStatus
                        Spacer()
                        updateButton
                    }
                    Toggle(tr("Automatically install updates"), isOn: $updater.autoInstall)
                        .disabled(!updater.isReleaseBuild)
                    if !updater.isReleaseBuild {
                        Text(tr("Development build: automatic updates are off."))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    LanguagePicker(prefs: prefs).fixedSize()
                }
                .padding(4)
            }

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(tr("Telex rules:")).foregroundColor(.secondary)
                    Link("UniKey", destination: URL(string: "https://www.unikey.org")!)
                    Text(tr("· Pinyin dictionary:")).foregroundColor(.secondary)
                    Link("rime-ice", destination: URL(string: "https://github.com/iDvel/rime-ice")!)
                }
                HStack(spacing: 4) {
                    Text(tr("© 2026 ViPi contributors · Free software under the")).foregroundColor(.secondary)
                    Link("GPL-3.0", destination: URL(string: "https://github.com/\(Updater.repo)/blob/main/LICENSE")!)
                }
            }
            .font(.caption)
        }
        .padding(24)
        .frame(width: 460)
    }

    private func shortcut(_ key: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.system(.callout, design: .monospaced)).frame(width: 130, alignment: .leading)
            Text(action).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.state {
        case .idle: Text(tr("Updates come from GitHub Releases.")).foregroundColor(.secondary)
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("Checking for updates…")) }
        case .upToDate: Label(tr("ViPi is up to date."), systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .available(let v): Label(tr("ViPi %@ is available.", v), systemImage: "arrow.down.circle.fill").foregroundColor(.accentColor)
        case .installing(let v): HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("Installing ViPi %@…", v)) }
        case .ready(let v): Label(tr("ViPi %@ is installed.", v), systemImage: "checkmark.seal.fill").foregroundColor(.green)
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
        }
    }

    @ViewBuilder private var updateButton: some View {
        switch updater.state {
        case .available: Button(tr("Install and Relaunch")) { updater.install(relaunchWhenDone: true) }.buttonStyle(.borderedProminent)
        case .ready: Button(tr("Relaunch Now")) { updater.relaunch() }.buttonStyle(.borderedProminent)
        case .checking, .installing: EmptyView()
        default: Button(tr("Check for Updates")) { updater.check(userInitiated: true) }
        }
    }
}
