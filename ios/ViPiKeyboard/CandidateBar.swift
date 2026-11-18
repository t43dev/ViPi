import UIKit

/// Thanh phía trên phím: chữ Hán gợi ý khi gõ Pinyin (kèm pinyin đang gõ, vì iOS không gạch chân nó trong ô nhập),
/// hoặc hai lựa chọn khi gõ tiếng Việt: giữ đúng phím đã gõ, hay chữ có dấu.
final class CandidateBar: UIView {
    enum Content: Equatable {
        case empty
        case chinese(preedit: String, candidates: [String])
        case vietnamese(keys: String, word: String)
        /// tiếng Trung khi chưa gõ gì: dấu câu (như bàn phím Trung của Apple)
        case punctuation([String])
        /// gõ Việt · Anh: từ đã gõ (trong ngoặc kép), chữ dấu cách sẽ đưa vào, cách hoàn thành từ, hoặc từ tiếp theo
        case suggestions([Suggestion])
    }

    var onPick: ((Int) -> Void)?
    var onSuggestion: ((Int) -> Void)?
    var onPunctuation: ((String) -> Void)?
    var onWord: ((Int) -> Void)?
    var content: Content = .empty { didSet { if content != oldValue { reload() } } }

    private let preedit = UILabel()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    /// Nút ứng viên chữ Hán, dùng lại qua từng phím gõ (mỗi phím pinyin đổi tới 60 ứng viên: tạo lại nút là việc nặng nhất)
    private var candidateButtons: [UIButton] = []
    private var candidateTitles: [String] = []
    private var showsCandidates = false
    private var shownCandidates = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        preedit.font = .systemFont(ofSize: 13, weight: .medium)
        preedit.textColor = .secondaryLabel
        preedit.lineBreakMode = .byTruncatingHead
        addSubview(preedit)
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        // iOS 26 làm mờ mép cuộn; thanh thấp nên mép trên và dưới phủ kín chữ
        for edge in [scroll.topEdgeEffect, scroll.bottomEdgeEffect, scroll.leftEdgeEffect, scroll.rightEdgeEffect] { edge.isHidden = true }
        addSubview(scroll)
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .fill
        scroll.addSubview(stack)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        if case .chinese(let p, _) = content, !p.isEmpty {
            let w = min(preedit.intrinsicContentSize.width, bounds.width * 0.3)
            preedit.frame = CGRect(x: 10, y: 0, width: w, height: h)
            scroll.frame = CGRect(x: preedit.frame.maxX + 6, y: 0, width: bounds.width - preedit.frame.maxX - 6, height: h)
        } else {
            preedit.frame = .zero
            scroll.frame = bounds
        }
        let size = stack.systemLayoutSizeFitting(CGSize(width: UIView.layoutFittingCompressedSize.width, height: h))
        stack.frame = CGRect(x: 0, y: 0, width: max(size.width, content.fillsBar ? scroll.bounds.width : 0), height: h)
        scroll.contentSize = stack.frame.size
    }

    private func reload() {
        scroll.contentOffset = .zero
        if case .chinese(let p, let candidates) = content {
            preedit.text = p
            if !showsCandidates {
                stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
                stack.distribution = .fill
                shownCandidates = 0
                showsCandidates = true
            }
            for (i, c) in candidates.enumerated() {
                if i == candidateButtons.count {
                    candidateButtons.append(button(c, size: 21, weight: i == 0 ? .semibold : .regular) { [weak self] in self?.onPick?(i) })
                    candidateTitles.append(c)
                } else if candidateTitles[i] != c {
                    candidateTitles[i] = c
                    candidateButtons[i].configuration?.attributedTitle = Self.title(c, size: 21, weight: i == 0 ? .semibold : .regular)
                }
                // nút thừa luôn nằm cuối hàng: thêm vào / gỡ ra ở cuối (ẩn hiện nút trong UIStackView để lại ràng buộc cũ)
                if i >= shownCandidates { stack.addArrangedSubview(candidateButtons[i]) }
            }
            if candidates.count < shownCandidates {
                for b in candidateButtons[candidates.count..<shownCandidates] { b.removeFromSuperview() }
            }
            shownCandidates = candidates.count
            setNeedsLayout()
            return
        }
        showsCandidates = false
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch content {
        case .empty, .chinese:
            preedit.text = nil
        case .vietnamese(let keys, let word):
            preedit.text = nil
            stack.distribution = .fillEqually
            stack.addArrangedSubview(button("\"\(keys)\"", size: 17, weight: .regular) { [weak self] in self?.onSuggestion?(0) })
            stack.addArrangedSubview(button(word, size: 17, weight: .semibold) { [weak self] in self?.onSuggestion?(1) })
        case .suggestions(let cells):
            preedit.text = nil
            stack.distribution = .fillEqually
            for (i, c) in cells.enumerated() {
                let b = button(c.quoted ? "\"\(c.text)\"" : c.text, size: 17, weight: c.highlighted ? .semibold : .regular) { [weak self] in self?.onWord?(i) }
                b.configuration?.titleLineBreakMode = .byTruncatingTail
                if c.quoted { b.configuration?.baseForegroundColor = .secondaryLabel }
                stack.addArrangedSubview(b)
            }
        case .punctuation(let marks):
            preedit.text = nil
            stack.distribution = .fill
            for m in marks {
                let b = button(m, size: 21, weight: .regular) { [weak self] in self?.onPunctuation?(m) }
                b.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
                stack.addArrangedSubview(b)
            }
        }
        setNeedsLayout()
    }

    private func button(_ title: String, size: CGFloat, weight: UIFont.Weight, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = Self.title(title, size: size, weight: weight)
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }
}

private extension CandidateBar {
    static func title(_ text: String, size: CGFloat, weight: UIFont.Weight) -> AttributedString {
        AttributedString(text, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: size, weight: weight)]))
    }
}

private extension CandidateBar.Content {
    /// các ô chia đều cả bề ngang thanh
    var fillsBar: Bool {
        switch self {
        case .vietnamese, .suggestions: return true
        default: return false
        }
    }
}
