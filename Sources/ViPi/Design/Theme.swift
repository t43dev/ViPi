import AppKit
import SwiftUI

/// Màu của giao diện Liquid Glass. Mỗi token tự đổi theo Appearance vì app đặt `NSApp.appearance` toàn cục.
enum Theme {
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    private static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(value >> 16 & 255) / 255, green: CGFloat(value >> 8 & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: alpha)
    }
    private static func color(_ light: NSColor, _ dark: NSColor) -> Color { Color(nsColor: dynamic(light, dark)) }
    private static func white(_ alpha: CGFloat) -> NSColor { hex(0xFFFFFF, alpha) }
    private static func ink(_ alpha: CGFloat) -> Color { color(hex(0x241A1B, alpha), hex(0xF3E9E0, alpha)) }

    /// Nền đỏ (nút chính, pill ứng viên, toggle).
    static let brandRed = Color(nsColor: hex(0xC8102E))
    /// Chữ và link màu đỏ: nền tối dùng đỏ sáng hơn để đọc được.
    static let brandRedNS = dynamic(hex(0xC8102E), hex(0xFF6B7A))
    static let brandRedText = Color(nsColor: brandRedNS)
    static let brandGold = Color(nsColor: hex(0xF5B82E))
    static let alertGoldNS = dynamic(hex(0xB8860B), hex(0xF5B82E))
    static let paper = color(hex(0xFBFAF8), hex(0x1C1011))
    static let ink = ink(1)
    static let inkSecondary = ink(0.64)
    static let inkTertiary = ink(0.44)
    static let card = color(white(0.62), white(0.06))
    static let cardStroke = color(white(0.9), white(0.10))
    static let cardHighlight = color(white(1), white(0.18))
    static let divider = color(hex(0x241A1B, 0.08), white(0.09))
    static let control = color(white(0.78), white(0.10))
    static let controlStroke = color(hex(0x241A1B, 0.10), white(0.14))
    static let segmentSelected = color(white(0.96), white(0.18))
    static let rowAlternate = ink(0.03)
    static let stepIdle = ink(0.12)
    static let okGreen = color(hex(0x1E7A3C), hex(0x6FD68F))
}
