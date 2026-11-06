import SwiftUI

/// Thanh tab capsule phía trên nội dung Settings.
struct GlassTabBar: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { i in
                Button(titles[i]) { selection = i }
                    .buttonStyle(Segment(selected: i == selection))
                    .accessibilityAddTraits(i == selection ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.control, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.controlStroke, lineWidth: 1))
    }

    private struct Segment: ButtonStyle {
        let selected: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? Theme.ink : Theme.inkSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(selected ? Theme.segmentSelected : .clear, in: Capsule())
                .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1.5, y: 1)
                .contentShape(Capsule())
        }
    }
}

/// Hàng cài đặt: nhãn trái, control phải, cao 44 và giãn khi nhãn xuống dòng.
struct SettingRow<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: Trailing
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
            .foregroundColor(enabled ? Theme.ink : Theme.inkTertiary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }
}

struct ToggleRow<Badge: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var badge: Badge

    var body: some View {
        SettingRow(title: title) {
            badge
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

extension ToggleRow where Badge == EmptyView {
    init(title: String, isOn: Binding<Bool>) {
        self.init(title: title, isOn: isOn) { EmptyView() }
    }
}

/// Chữ giải thích ngay dưới hàng của nó.
struct HelpText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
    }
}

struct CardDivider: View {
    var body: some View { Theme.divider.frame(height: 1).padding(.horizontal, 14) }
}

/// Picker dạng capsule. Picker thật nằm trong suốt phía trên để giữ menu, dấu chọn và phím của hệ thống.
struct CapsulePicker<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            Text(options.first { $0.value == selection }?.label ?? "").lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 13))
        .foregroundColor(Theme.ink)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(Theme.control, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.controlStroke, lineWidth: 1))
        .overlay {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .opacity(0.011)
        }
    }
}

/// Ô tick 16×16 bo 5, màu thương hiệu.
struct BrandCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isOn ? Theme.brandRed : Theme.control)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(configuration.isOn ? .clear : Theme.controlStroke, lineWidth: 1))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
                        }
                    }
                    .frame(width: 16, height: 16)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }
}

/// Nhãn nhỏ trên nền vàng nhạt, vd EXPERIMENTAL.
struct GoldBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Theme.brandGold.opacity(0.25), in: Capsule())
    }
}
