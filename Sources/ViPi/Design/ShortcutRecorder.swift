import AppKit
import SwiftUI

/// Bấm để ghi phím tắt: nhấn tổ hợp phím bổ trợ rồi nhả, hoặc phím bổ trợ + một phím. Esc để huỷ.
struct ShortcutRecorder: View {
    @Binding var shortcut: SwitchShortcut
    let onRecording: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var peak: NSEvent.ModifierFlags = []

    var body: some View {
        Button { recording ? stop() : start() } label: {
            HStack(spacing: 6) {
                if recording {
                    Text(tr("Press the new shortcut…"))
                } else {
                    Text(shortcut.symbols).font(.system(size: 14))
                    Text(shortcut.label)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(recording ? Theme.brandRed.opacity(0.14) : Theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(recording ? Theme.brandRed : Theme.controlStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        peak = []
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.type == .keyDown {
                if event.keyCode == 53, mods.isEmpty { stop(); return nil }   // Esc: huỷ
                // phải có ⌃, ⌥ hoặc ⌘, nếu không sẽ chặn mất chữ đang gõ
                guard !mods.subtracting(.shift).isEmpty else { NSSound.beep(); return nil }
                shortcut = SwitchShortcut(flags: Self.cgFlags(mods), keyCode: Int(event.keyCode), keyName: Self.keyName(event))
                stop()
                return nil
            }
            if mods.isEmpty {
                // nhả hết: nhận tổ hợp vừa nhấn nếu có từ hai phím bổ trợ
                if Self.count(peak) >= 2 {
                    shortcut = SwitchShortcut(flags: Self.cgFlags(peak))
                    stop()
                }
                peak = []
            } else if Self.count(mods) >= Self.count(peak) {
                peak = mods
            }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { onRecording(false) }
        recording = false
    }

    private static func count(_ m: NSEvent.ModifierFlags) -> Int {
        [NSEvent.ModifierFlags.control, .option, .shift, .command].filter { m.contains($0) }.count
    }

    private static func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.command) { f.insert(.maskCommand) }
        return f
    }

    private static func keyName(_ e: NSEvent) -> String {
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 50: "`",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
                                       98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let n = names[e.keyCode] { return n }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
