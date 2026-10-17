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
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, word in
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(i + 1)").font(.system(size: 11)).opacity(0.6)
                        Text(word).font(.system(size: 18))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .foregroundColor(i == highlight ? .white : .primary)
                    .background(i == highlight ? Color(red: 0.80, green: 0.13, blue: 0.13) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                if hasPrev || hasNext {
                    Text("\(hasPrev ? "◀" : "◁")\(hasNext ? "▶" : "▷")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
              let focusedRef else { return nil }
        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                          rangeRef, &boundsRef) == .success,
               let boundsRef {
                var rect = CGRect.zero
                if AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.height > 0 {
                    return flip(rect)
                }
            }
        }
        // không lấy được caret: dùng góc dưới-trái của ô đang focus
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.height > 0, size.height < 200 else { return nil }   // vùng soạn thảo lớn: caret không rõ
        return flip(CGRect(origin: pos, size: size))
    }

    /// AX dùng gốc trên-trái của màn hình chính; Cocoa dùng gốc dưới-trái.
    private static func flip(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
}
