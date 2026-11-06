import AppKit
import SwiftUI

/// Màn chào: cấp quyền Accessibility, chọn bộ gõ, phím đổi bộ gõ.
final class FirstRunWindowController {
    private var window: NSWindow?
    private let makeView: (@escaping () -> Void) -> FirstRunView

    init(makeView: @escaping (@escaping () -> Void) -> FirstRunView) { self.makeView = makeView }

    func show() {
        if window == nil {
            let view = makeView { [weak self] in self?.window?.close() }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.styleMask = [.titled, .closable]
            w.applyGlassChrome()
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct FirstRunView: View {
    @ObservedObject var prefs: Preferences
    /// Bộ gõ đang chọn và các bộ gõ chọn được (có VE khi tự đổi Anh/Việt đang bật).
    let currentInput: () -> InputMode
    let inputs: () -> [InputMode]
    let selectInput: (InputMode) -> Void
    let openAccessibility: () -> Void
    let onRecording: (Bool) -> Void
    let close: () -> Void
    @State private var trusted = AXIsProcessTrusted()
    @State private var picked = false
    @State private var current: InputMode?
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var step: Int { !trusted ? 1 : picked ? 3 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Welcome to ViPi")).font(.system(size: 20, weight: .bold))
                    Text(tr("Three steps and you can type Vietnamese and Chinese anywhere."))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                row(1, tr("Allow Accessibility"), tr("ViPi needs it to read keys and type for you. It never records what you write.")) {
                    pill(trusted ? tr("Granted") : tr("Not granted"), color: trusted ? Theme.okGreen : Theme.brandRedText)
                    if !trusted {
                        Button(tr("Open System Settings…"), action: openAccessibility)
                            .buttonStyle(GlassButtonStyle(role: .primary, fontSize: 12))
                    }
                }
                CardDivider()
                row(2, tr("Pick your input"), tr("You can change this any time from the menu bar.")) {
                    HStack(spacing: 6) {
                        ForEach(inputs(), id: \.self) { chip($0) }
                    }
                    .fixedSize()
                }
                CardDivider()
                row(3, tr("Switch input with a shortcut"), tr("Press once for the previous input, twice quickly for the next.")) {
                    ShortcutRecorder(shortcut: $prefs.shortcut, onRecording: onRecording)
                }
            }
            .glassCard()

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Label(tr("Runs in the menu bar · nothing you type leaves this Mac"), systemImage: "shield")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(tr("Later"), action: close).buttonStyle(GlassButtonStyle(height: 28))
                Button(tr("Done"), action: close).buttonStyle(GlassButtonStyle(role: .primary, height: 28))
            }
        }
        .padding([.horizontal, .bottom], 24)
        .frame(width: 520, height: 400)
        .foregroundColor(Theme.ink)
        .tint(Theme.brandRed)
        .background(WindowBackground())
        .onAppear { current = currentInput() }
        .onReceive(poll) { _ in trusted = AXIsProcessTrusted() }
    }

    private func row<Trailing: View>(_ number: Int, _ title: String, _ help: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(number == step ? .white : Theme.ink)
                .frame(width: 24, height: 24)
                .background(number == step ? Theme.brandRed : Theme.stepIdle, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(help)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func chip(_ mode: InputMode) -> some View {
        let on = mode == current
        return Button { current = mode; picked = true; selectInput(mode) } label: {
            Text("\(mode.badge(autoSwitch: prefs.autoSwitch)) · \(chipName(mode))")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(on ? Theme.brandRed.opacity(0.12) : Theme.control, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Theme.brandRed : Theme.controlStroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chipName(_ mode: InputMode) -> String {
        if prefs.autoSwitch, mode != .chinese { return tr("Telex + English") }
        switch mode {
        case .vietnamese: return "Telex"
        case .chinese: return "Pinyin"
        case .english: return tr("English")
        }
    }
}
