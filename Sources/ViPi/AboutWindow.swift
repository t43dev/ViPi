import AppKit
import SwiftUI

final class AboutWindowController {
    private var window: NSWindow?
    private let updater: Updater

    init(updater: Updater) { self.updater = updater }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView(updater: updater)))
            w.title = "About ViPi"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("ViPi").font(.system(size: 26, weight: .bold))
                Text("Version \(Updater.currentVersion) (\(Updater.currentBuild))")
                    .font(.callout).foregroundColor(.secondary).textSelection(.enabled)
            }
            Text("Vietnamese Telex + Chinese Pinyin in one input tool.\nMade because macOS had no sensible way to type both.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link(destination: Updater.pageURL) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: Updater.releasesURL) { Label("Releases", systemImage: "shippingbox") }
                Link(destination: Updater.issuesURL) { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    shortcut("Control+Shift", "previous input")
                    shortcut("Control+Shift ×2", "next input")
                    shortcut("Telex", "aa â · aw ă · ee ê · oo ô · ow ơ · uw ư · dd đ · s f r x j tones · z clears")
                    shortcut("Pinyin", "1–9 pick · Space highlighted · −/= page · Enter raw · Esc cancel")
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
                    Toggle("Automatically install updates", isOn: $updater.autoInstall)
                        .disabled(!updater.isReleaseBuild)
                    if !updater.isReleaseBuild {
                        Text("Development build: automatic updates are off.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(4)
            }

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text("Telex rules:").foregroundColor(.secondary)
                    Link("UniKey", destination: URL(string: "https://www.unikey.org")!)
                    Text("· Pinyin dictionary:").foregroundColor(.secondary)
                    Link("rime-ice", destination: URL(string: "https://github.com/iDvel/rime-ice")!)
                }
                HStack(spacing: 4) {
                    Text("© 2026 ViPi contributors · Free software under the").foregroundColor(.secondary)
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
            Text(action).font(.callout).foregroundColor(.secondary)
        }
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.state {
        case .idle: Text("Updates come from GitHub Releases.").foregroundColor(.secondary)
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking for updates…") }
        case .upToDate: Label("ViPi is up to date.", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .available(let v): Label("ViPi \(v) is available.", systemImage: "arrow.down.circle.fill").foregroundColor(.accentColor)
        case .installing(let v): HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing ViPi \(v)…") }
        case .ready(let v): Label("ViPi \(v) is installed.", systemImage: "checkmark.seal.fill").foregroundColor(.green)
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
        }
    }

    @ViewBuilder private var updateButton: some View {
        switch updater.state {
        case .available: Button("Install and Relaunch") { updater.install(relaunchWhenDone: true) }.buttonStyle(.borderedProminent)
        case .ready: Button("Relaunch Now") { updater.relaunch() }.buttonStyle(.borderedProminent)
        case .checking, .installing: EmptyView()
        default: Button("Check for Updates") { updater.check(userInitiated: true) }
        }
    }
}
