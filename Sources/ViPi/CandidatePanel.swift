import AppKit
import SwiftUI

/// Ô gợi ý chữ Hán: dòng pinyin đang gõ + danh sách ứng viên đánh số 1-9.
final class CandidatePanel {
    private let panel: NSPanel
    private let host: NSHostingView<CandidateView>
    private var caret: CGRect?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        host = NSHostingView(rootView: CandidateView(preedit: "", items: [], highlight: 0, hasPrev: false, hasNext: false))
        panel.contentView = host
    }

    func update(preedit: String, items: [String], highlight: Int, hasPrev: Bool, hasNext: Bool) {
        host.rootView = CandidateView(preedit: preedit, items: items, highlight: highlight, hasPrev: hasPrev, hasNext: hasNext)
        layout()
        panel.orderFrontRegardless()
    }

    /// Đặt vị trí theo con trỏ văn bản (toạ độ Cocoa); nil → cạnh con trỏ chuột.
    func anchor(to rect: CGRect?) {
        caret = rect ?? CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 18))
        if panel.isVisible { layout() }
    }

    func hide() {
        panel.orderOut(nil)
        caret = nil
    }

    private func layout() {
        let size = host.fittingSize
        let c = caret ?? CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 18))
        let screen = NSScreen.screens.first { $0.frame.intersects(c.insetBy(dx: -1, dy: -1)) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero
        var origin = CGPoint(x: c.minX, y: c.minY - size.height - 4)
        if origin.y < bounds.minY { origin.y = c.maxY + 4 }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

struct CandidateView: View {
    let preedit: String
    let items: [String]
    let highlight: Int
    let hasPrev: Bool
    let hasNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preedit)
                .font(.system(size: 13))
                .foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 4)
            HStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, word in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(i + 1)")
                            .font(.system(size: 11))
                            .foregroundColor(i == highlight ? .white.opacity(0.75) : Theme.inkSecondary)
                        Text(word)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(i == highlight ? .white : Theme.ink)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .frame(height: 30)
                    .background(i == highlight ? Theme.brandRed : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if hasPrev || hasNext {
                    Theme.stepIdle.frame(width: 1, height: 18).padding(.horizontal, 2)
                    Image(systemName: "chevron.left")
                        .opacity(hasPrev ? 1 : 0.3)
                        .frame(width: 22, height: 26)
                    Image(systemName: hasNext ? "arrowtriangle.right.fill" : "chevron.right")
                        .opacity(hasNext ? 1 : 0.3)
                        .frame(width: 22, height: 26)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.inkSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glass(radius: 12, prominent: true, shadow: false)   // vẽ lại mỗi phím: bóng lấy từ NSPanel
        .fixedSize()
    }
}

/// Lấy vị trí con trỏ văn bản qua Accessibility API (trả về toạ độ Cocoa, gốc dưới-trái).
enum CaretLocator {
    static func caretRect() -> CGRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                          rangeRef, &boundsRef) == .success,
               let bounds = axValue(boundsRef) {
                var rect = CGRect.zero
                if AXValueGetValue(bounds, .cgRect, &rect), rect.height > 0 {
                    return flip(rect)
                }
            }
        }
        // không lấy được caret: dùng góc dưới-trái của ô đang focus
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = axValue(posRef), let sizeValue = axValue(sizeRef) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue, .cgSize, &size)
        guard size.height > 0, size.height < 200 else { return nil }   // vùng soạn thảo lớn: caret không rõ
        return flip(CGRect(origin: pos, size: size))
    }

    /// Ép kiểu an toàn: app lạ có thể trả về kiểu khác, không được crash vì đang giữ bàn phím.
    private static func axValue(_ ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }

    /// AX dùng gốc trên-trái của màn hình chính; Cocoa dùng gốc dưới-trái.
    private static func flip(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
}
