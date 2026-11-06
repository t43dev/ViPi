import AppKit
import SwiftUI

/// Mọi bề mặt kính đi qua đây. macOS 26 trở lên dùng Liquid Glass thật; macOS 13–15 dùng material + viền sáng.
/// `#if compiler`: SDK cũ (CI macos-15) không có `glassEffect` nên `#available` thôi thì không biên dịch được.
/// Đặt VIPI_NO_GLASS=1 để xem nhánh dự phòng ngay trên máy mới.
enum Glass {
    static let useFallback = ProcessInfo.processInfo.environment["VIPI_NO_GLASS"] != nil
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat = 14
    var prominent = false       // nổi hơn: HUD, khung ứng viên
    var shadow = true           // panel vẽ lại mỗi phím dùng bóng của NSPanel, không dùng bóng SwiftUI
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !Glass.useFallback {
            content.glassEffect(prominent ? .regular : .regular.tint(.clear), in: .rect(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.6), lineWidth: 1).blendMode(.plusLighter))
            .shadow(color: .black.opacity(shadow ? (prominent ? 0.25 : 0.10) : 0), radius: prominent ? 24 : 10, y: prominent ? 12 : 4)
    }
}

extension View {
    func glass(radius: CGFloat = 14, prominent: Bool = false, shadow: Bool = true) -> some View {
        modifier(GlassSurface(radius: radius, prominent: prominent, shadow: shadow))
    }

    /// Một nhóm cài đặt: kính + nền card + viền + đường sáng phía trên.
    func glassCard(radius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.cardStroke, lineWidth: 1))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Theme.cardHighlight, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.06)),
                lineWidth: 1))
            .glass(radius: radius, shadow: false)
    }
}

/// Nền cửa sổ: material phía sau cửa sổ phủ một lớp giấy.
struct WindowBackground: View {
    var body: some View {
        ZStack {
            BehindWindowMaterial()
            Theme.paper.opacity(0.76)
        }
        .ignoresSafeArea()
    }
}

private struct BehindWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension NSWindow {
    /// Thanh tiêu đề trong suốt, nội dung nằm dưới thanh tiêu đề.
    func applyGlassChrome() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        titleVisibility = .visible
        toolbarStyle = .unified
    }
}

/// Nút capsule. macOS 26 trở lên là kính tương tác, cũ hơn là nền `control` (hoặc đỏ với nút chính).
struct GlassButtonStyle: ButtonStyle {
    enum Role { case secondary, primary, danger }
    var role = Role.secondary
    var height: CGFloat = 26
    var fontSize: CGFloat = 13
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(size: fontSize, weight: role == .secondary ? .medium : .semibold))
            .foregroundColor(role == .primary ? .white : role == .danger ? Theme.brandRedText : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: height)
            .contentShape(Capsule())
        return surface(label)
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }

    @ViewBuilder private func surface(_ label: some View) -> some View {
        switch role {
        case .danger:
            label.background(Theme.brandRed.opacity(0.10), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.brandRed.opacity(0.4), lineWidth: 1))
        case .primary:
            #if compiler(>=6.2)
            if #available(macOS 26, *), !Glass.useFallback {
                label.glassEffect(.regular.tint(Theme.brandRed).interactive(), in: .capsule)
            } else {
                label.background(Theme.brandRed, in: Capsule())
            }
            #else
            label.background(Theme.brandRed, in: Capsule())
            #endif
        case .secondary:
            #if compiler(>=6.2)
            if #available(macOS 26, *), !Glass.useFallback {
                label.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                label.background(Theme.control, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.controlStroke, lineWidth: 1))
            }
            #else
            label.background(Theme.control, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.controlStroke, lineWidth: 1))
            #endif
        }
    }
}
