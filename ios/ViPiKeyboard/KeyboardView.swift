import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func keyboardWillPress()
    func keyboardDidType(_ key: KeyInput)
    func keyboardToggleMode()
    func keyboardMoveCursor(_ delta: Int)
    func keyboardPickCandidate(_ index: Int)
    func keyboardPickSuggestion(_ index: Int)
    func keyboardTypePunctuation(_ text: String)
}

/// Bàn phím vẽ tay bằng Core Graphics (như Canvas của bản Android): ít view, ít bộ nhớ, hợp giới hạn của keyboard extension.
/// Bố cục theo spec Android (mục 4.1, tách đôi 4.2); hình dáng phím theo bàn phím iOS 26 (Liquid Glass): phím bo tròn,
/// không bóng, nền trong để hệ thống vẽ lớp kính phía sau.
final class KeyboardView: UIView {
    enum Layout { case letters, numbers, symbols }
    enum Shift { case off, once, lock }

    enum ReturnKey: Equatable {
        case plain
        case action(String)

        init(_ type: UIReturnKeyType) {
            switch type {
            case .go: self = .action("go")
            case .google, .yahoo, .search: self = .action("search")
            case .join: self = .action("join")
            case .next: self = .action("next")
            case .route: self = .action("route")
            case .send: self = .action("send")
            case .done: self = .action("done")
            case .emergencyCall: self = .action("call")
            case .continue: self = .action("continue")
            default: self = .plain
            }
        }
    }

    private enum Kind { case char, shift, backspace, numbers, letters, symbols, mode, nextKeyboard, space, ret, spacer, gap }

    private struct Key {
        var kind: Kind
        var label = ""
        var units: CGFloat = 1
        var hint: String? = nil
        var punct = false
        var frame = CGRect.zero
        var row = 0
    }

    private struct Metrics {
        var bar: CGFloat, row: CGFloat, gapX: CGFloat, gapY: CGFloat, side: CGFloat, bottom: CGFloat
        var radius: CGFloat, font: CGFloat
    }

    weak var delegate: KeyboardViewDelegate?
    let bar = CandidateBar()
    /// Nút chuyển bàn phím của hệ thống (khi needsInputModeSwitchKey): trong suốt, đặt đè lên phím quả địa cầu.
    let nextKeyboardButton = UIButton(type: .custom)
    private let popup = PopupView()

    var layout: Layout = .letters { didSet { if layout != oldValue { rebuild() } } }
    var shift: Shift = .off { didSet { if shift != oldValue { setNeedsDisplay() } } }
    var mode: InputMode = .english { didSet { if mode != oldValue { setNeedsDisplay() } } }
    var modeLocked = false { didSet { if modeLocked != oldValue { setNeedsDisplay() } } }
    var returnKey: ReturnKey = .plain { didSet { if returnKey != oldValue { setNeedsDisplay() } } }
    var showsNextKeyboard = false { didSet { if showsNextKeyboard != oldValue { rebuild() } } }
    var splitOnPad = true { didSet { if splitOnPad != oldValue { rebuild() } } }
    var keyPopup = true
    var fullWidth = true { didSet { setNeedsDisplay() } }
    /// Thanh gợi ý trên các phím; tắt thì bàn phím thấp hơn (controller đổi chiều cao theo preferredHeight).
    var showsBar = true { didSet { if showsBar != oldValue { bar.isHidden = !showsBar; setNeedsLayout(); setNeedsDisplay() } } }

    private var keys: [Key] = []
    private var unit: CGFloat = 0
    private var pressed: Set<Int> = []
    private var lastShiftTap: TimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw
        bar.onPick = { [weak self] in self?.delegate?.keyboardPickCandidate($0) }
        bar.onSuggestion = { [weak self] in self?.delegate?.keyboardPickSuggestion($0) }
        bar.onPunctuation = { [weak self] in self?.delegate?.keyboardTypePunctuation($0) }
        addSubview(bar)
        nextKeyboardButton.isHidden = true
        addSubview(nextKeyboardButton)
        popup.isUserInteractionEnabled = false
        addSubview(popup)
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance + [UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) { (view: KeyboardView, _: UITraitCollection) in
            view.setNeedsLayout()
            view.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Kích thước

    private func metrics(_ traits: UITraitCollection) -> Metrics {
        if traits.userInterfaceIdiom == .pad && traits.horizontalSizeClass == .regular {
            return Metrics(bar: 44, row: 66, gapX: 8, gapY: 10, side: 6, bottom: 8, radius: 11, font: 24)
        }
        // Số đo bàn phím Apple (iOS 27, đo trên simulator iPhone 15 đến 18 Pro Max, khớp ảnh chụp máy thật):
        // - nằm ngang: phím cao 32, hàng cách 40, khe ngang 6,5, phím ngoài cách mép 4,8, đáy phím cách đáy vùng bàn phím 2
        // - dọc: phím cao 43 (máy rộng dưới 410 pt) hoặc 45, khe 6 / 11, phím ngoài cách mép 6,7, đáy phím sát đáy vùng bàn phím
        //   trên máy hẹp; máy rộng thì đáy phím cách đáy vùng bàn phím 7 pt (máy hẹp Apple còn lấn xuống thêm ~4 pt vào vùng
        //   iOS dành cho thanh dưới, bàn phím ngoài không làm được)
        if traits.verticalSizeClass == .compact {
            return Metrics(bar: 32, row: 40, gapX: 6.5, gapY: 8, side: 1.55, bottom: -2, radius: 8, font: 20)
        }
        let wide = (bounds.width > 0 ? bounds.width : 402) >= 410
        return Metrics(bar: 36, row: wide ? 56 : 54, gapX: 6, gapY: 11, side: 3.7, bottom: wide ? 1.5 : -5.5, radius: 9, font: 23)
    }

    func preferredHeight(traits: UITraitCollection) -> CGFloat {
        let m = metrics(traits)
        return barHeight(m) + 4 * m.row + m.bottom
    }

    private func barHeight(_ m: Metrics) -> CGFloat { showsBar ? m.bar : 0 }

    private var isSplit: Bool {
        splitOnPad && traitCollection.userInterfaceIdiom == .pad && traitCollection.horizontalSizeClass == .regular && bounds.width >= 700
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = metrics(traitCollection)
        bar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight(m))
        popup.frame = bounds
        rebuild()
    }

    func reset() {
        cancelTimers()
        pressed.removeAll()
        touchStates.removeAll()
        popup.hide()
        layout = .letters
        shift = .off
        setNeedsDisplay()
    }

    // MARK: - Bố cục phím (spec Android mục 4.1)

    private func chars(_ s: String, _ units: CGFloat = 1) -> [Key] { s.map { Key(kind: .char, label: String($0), units: units) } }

    private func rows() -> [[Key]] {
        isSplit ? splitRows() : fullRows()
    }

    private func fullRows() -> [[Key]] {
        // hàng dưới như Apple: 123 (2,5 phím, ở đây chia cho 123 và phím ngôn ngữ), cách 5, Return 2,5; dấu , . ở trang 123
        var bottom = [layout == .letters ? Key(kind: .numbers, label: "123", units: 1.5) : Key(kind: .letters, label: "ABC", units: 1.5)]
        if showsNextKeyboard { bottom.append(Key(kind: .nextKeyboard)) }
        bottom += [Key(kind: .mode), Key(kind: .space, units: showsNextKeyboard ? 4 : 5), Key(kind: .ret, units: 2.5)]
        let third = { (left: Key) in [left] + self.chars(".,?!'", 1.4) + [Key(kind: .backspace, units: 1.5)] }
        switch layout {
        case .letters:
            return [
                "qwertyuiop".enumerated().map { Key(kind: .char, label: String($1), hint: String(($0 + 1) % 10)) },
                [Key(kind: .spacer, units: 0.5)] + chars("asdfghjkl") + [Key(kind: .spacer, units: 0.5)],
                [Key(kind: .shift, units: 1.5)] + chars("zxcvbnm") + [Key(kind: .backspace, units: 1.5)],
                bottom,
            ]
        case .numbers:
            return [chars("1234567890"), chars("-/:;()$&@\""), third(Key(kind: .symbols, label: "#+=", units: 1.5)), bottom]
        case .symbols:
            return [chars("[]{}#%^*+="), chars("_\\|~<>€£¥•"), third(Key(kind: .numbers, label: "123", units: 1.5)), bottom]
        }
    }

    /// Tách đôi (spec 4.2): mỗi nửa 5 đơn vị, nửa trái sát mép trái, nửa phải sát mép phải.
    private func splitRows() -> [[Key]] {
        let gap = Key(kind: .gap, units: 0)
        let left = layout == .letters ? Key(kind: .numbers, label: "123", units: 1.5) : Key(kind: .letters, label: "ABC", units: 1.5)
        let bottom: [Key] = showsNextKeyboard
            ? [left, Key(kind: .nextKeyboard), Key(kind: .mode), Key(kind: .space, units: 1.5), gap,
               Key(kind: .space, units: 1.5), Key(kind: .char, label: ",", punct: true), Key(kind: .char, label: ".", punct: true), Key(kind: .ret, units: 1.5)]
            : [left, Key(kind: .mode), Key(kind: .char, label: ",", punct: true), Key(kind: .space, units: 1.5), gap,
               Key(kind: .space, units: 2), Key(kind: .char, label: ".", punct: true), Key(kind: .ret, units: 2)]
        let third = { (l: Key) in [l] + self.chars(".,?", 1.2) + [gap] + self.chars("!'", 1.2) + [Key(kind: .spacer, units: 0.6), Key(kind: .backspace, units: 2)] }
        switch layout {
        case .letters:
            return [
                "qwert".enumerated().map { Key(kind: .char, label: String($1), hint: String($0 + 1)) } + [gap]
                    + "yuiop".enumerated().map { Key(kind: .char, label: String($1), hint: String(($0 + 6) % 10)) },
                chars("asdfg") + [gap, Key(kind: .spacer, units: 0.5)] + chars("hjkl") + [Key(kind: .spacer, units: 0.5)],
                [Key(kind: .shift)] + chars("zxcv") + [gap] + chars("bnm") + [Key(kind: .backspace, units: 2)],
                bottom,
            ]
        case .numbers:
            return [chars("12345") + [gap] + chars("67890"), chars("-/:;(") + [gap] + chars(")$&@\""),
                    third(Key(kind: .symbols, label: "#+=", units: 1.4)), bottom]
        case .symbols:
            return [chars("[]{}#") + [gap] + chars("%^*+="), chars("_\\|~<") + [gap] + chars(">€£¥•"),
                    third(Key(kind: .numbers, label: "123", units: 1.4)), bottom]
        }
    }

    private func rebuild() {
        guard bounds.width > 0 else { return }
        let m = metrics(traitCollection)
        let split = isSplit
        // iPad (không tách): một bàn phím ở giữa, rộng tối đa 760 pt
        let available = bounds.width - 2 * m.side
        let width = traitCollection.userInterfaceIdiom == .pad && !split ? min(available, 760) : available
        let originX = (bounds.width - width) / 2
        let unit = split ? min(width * 0.36, 5 * 64) / 5 : width / 10
        self.unit = unit
        var out: [Key] = []
        for (r, row) in rows().enumerated() {
            let y = barHeight(m) + CGFloat(r) * m.row
            let gapIndex = row.firstIndex { $0.kind == .gap }
            let leftPart = gapIndex.map { Array(row[..<$0]) } ?? row
            let rightPart = gapIndex.map { Array(row[($0 + 1)...]) } ?? []
            let leftUnits = leftPart.reduce(0) { $0 + $1.units }
            var x = split ? originX : originX + (width - leftUnits * unit) / 2
            for var k in leftPart {
                k.frame = CGRect(x: x, y: y, width: k.units * unit, height: m.row)
                k.row = r
                out.append(k)
                x += k.units * unit
            }
            if !rightPart.isEmpty {
                var rx = originX + width - rightPart.reduce(0) { $0 + $1.units } * unit
                for var k in rightPart {
                    k.frame = CGRect(x: rx, y: y, width: k.units * unit, height: m.row)
                    k.row = r
                    out.append(k)
                    rx += k.units * unit
                }
            }
        }
        keys = out
        if let i = keys.firstIndex(where: { $0.kind == .nextKeyboard }) {
            nextKeyboardButton.frame = keys[i].frame
            nextKeyboardButton.isHidden = false
        } else {
            nextKeyboardButton.isHidden = true
        }
        setNeedsDisplay()
    }

    // MARK: - Vẽ

    private struct Palette {
        let key, fn, text, hint, accent, onAccent, keyPressed, fnPressed: UIColor
    }

    private var palette: Palette {
        let dark = traitCollection.userInterfaceStyle == .dark
        let red = dark ? UIColor(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x3D / 255, alpha: 1)
            : UIColor(red: 0xA8 / 255, green: 0x22 / 255, blue: 0x1C / 255, alpha: 1)
        return dark
            // như bàn phím Apple iOS 26: phím chức năng cùng màu phím chữ
            ? Palette(key: UIColor(white: 1, alpha: 0.30), fn: UIColor(white: 1, alpha: 0.30), text: .white,
                      hint: UIColor(white: 1, alpha: 0.55), accent: red, onAccent: .white,
                      keyPressed: UIColor(white: 1, alpha: 0.14), fnPressed: UIColor(white: 1, alpha: 0.14))
            : Palette(key: UIColor(white: 1, alpha: 0.96), fn: UIColor(white: 1, alpha: 0.96), text: .black,
                      hint: UIColor(white: 0, alpha: 0.45), accent: red, onAccent: .white,
                      keyPressed: UIColor(white: 1, alpha: 0.42), fnPressed: UIColor(white: 1, alpha: 0.42))
    }

    private var chinese: Bool { !modeLocked && mode == .chinese }

    private func label(_ k: Key) -> String {
        if k.punct && chinese && fullWidth { return k.label == "," ? "，" : "。" }
        if layout == .letters && shift != .off { return k.label.uppercased() }
        return k.label
    }

    private func hint(_ k: Key) -> String? {
        guard layout == .letters else { return nil }
        if let h = k.hint { return h }
        if k.label == "v" && chinese { return "ü" }
        return nil
    }

    override func draw(_ rect: CGRect) {
        let m = metrics(traitCollection)
        let p = palette
        for (i, k) in keys.enumerated() where k.kind != .spacer && k.kind != .gap {
            var r = k.frame.insetBy(dx: m.gapX / 2, dy: m.gapY / 2)
            if k.row == 2 && !isSplit && [.shift, .backspace, .numbers, .symbols].contains(k.kind) {
                // như Apple: Shift / xoá hẹp hơn ô của chúng (50 pt trên máy 440 pt), sát mép ngoài, chạm vẫn nhận cả ô
                let w = unit * (traitCollection.verticalSizeClass == .compact ? 1.21 : 1.155)
                if k.frame.midX > bounds.midX { r.origin.x = r.maxX - w }
                r.size.width = w
            }
            let isDown = pressed.contains(i)
            let fill: UIColor
            switch k.kind {
            case .char, .space: fill = isDown ? p.keyPressed : p.key
            case .ret: fill = returnKey == .plain ? (isDown ? p.fnPressed : p.fn) : (isDown ? p.accent.withAlphaComponent(0.7) : p.accent)
            case .shift where shift != .off: fill = p.key
            default: fill = isDown ? p.fnPressed : p.fn
            }
            fill.setFill()
            UIBezierPath(roundedRect: r, cornerRadius: min(m.radius, r.height / 2)).fill()
            let c = CGPoint(x: r.midX, y: r.midY)
            switch k.kind {
            case .char:
                let fontSize = layout == .letters && k.label.first?.isLetter == true ? m.font : m.font - 3
                drawText(label(k), at: CGPoint(x: c.x, y: c.y - 1), font: .systemFont(ofSize: fontSize), color: p.text)
                if let h = hint(k) {
                    drawText(h, at: CGPoint(x: r.maxX - 7, y: r.minY + 8), font: .systemFont(ofSize: 10, weight: .medium), color: p.hint)
                }
            case .shift:
                let name = shift == .lock ? "capslock.fill" : shift == .once ? "shift.fill" : "shift"
                drawSymbol(name, at: c, size: 19, color: p.text)
            case .backspace: drawSymbol("delete.left", at: c, size: 19, color: p.text)
            case .numbers, .letters, .symbols: drawText(k.label, at: c, font: .systemFont(ofSize: 16), color: p.text)
            case .nextKeyboard: drawSymbol("globe", at: c, size: 19, color: p.text)
            case .mode:
                drawText(modeLocked ? "ABC" : (chinese ? "拼" : "VI"), at: c, font: .systemFont(ofSize: 17, weight: .semibold), color: p.text)
            case .space:
                drawText(modeLocked ? "space" : (chinese ? "拼音" : "VI · EN"), at: c, font: .systemFont(ofSize: 14, weight: .medium), color: p.hint)
            case .ret:
                switch returnKey {
                case .plain: drawSymbol("return", at: c, size: 19, color: p.text)
                case .action(let title): drawText(title, at: c, font: .systemFont(ofSize: 16, weight: .medium), color: p.onAccent)
                }
            case .spacer, .gap: break
            }
        }
    }

    private func drawText(_ s: String, at c: CGPoint, font: UIFont, color: UIColor) {
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let size = a.size()
        a.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2))
    }

    private func drawSymbol(_ name: String, at c: CGPoint, size: CGFloat, color: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let image = UIImage(systemName: name, withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        image.draw(at: CGPoint(x: c.x - image.size.width / 2, y: c.y - image.size.height / 2))
    }

    // MARK: - Chạm

    private final class TouchState {
        var key: Int
        let start: CGPoint
        var lastX: CGFloat
        let order: Int
        var trackpad = false
        var longFired = false
        /// đã gửi phím trước khi nhấc (ngón khác chạm xuống)
        var done = false
        var timer: Timer?
        init(key: Int, at p: CGPoint, order: Int) { self.key = key; start = p; lastX = p.x; self.order = order }
        var startX: CGFloat { start.x }
    }

    private var touchCount = 0

    private var touchStates: [ObjectIdentifier: TouchState] = [:]
    private var repeatTimer: Timer?

    private func keyIndex(at p: CGPoint) -> Int? {
        let m = metrics(traitCollection)
        guard p.y >= barHeight(m) - 4 else { return nil }
        let row = max(0, min(3, Int((p.y - barHeight(m)) / m.row)))
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, k) in keys.enumerated() where k.row == row && k.kind != .spacer && k.kind != .gap {
            if k.frame.contains(CGPoint(x: p.x, y: k.frame.midY)) { return i }
            let d = abs(k.frame.midX - p.x)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // gõ nhanh hai ngón: ngón sau chạm xuống thì gửi ngay phím của ngón trước, đúng thứ tự chạm
        // (đợi nhấc mới gửi thì ngón sau nhấc trước sẽ làm đảo chữ)
        for s in touchStates.values.sorted(by: { $0.order < $1.order })
        where !s.done && !s.longFired && !s.trackpad && (keys[s.key].kind == .char || keys[s.key].kind == .space) {
            s.timer?.invalidate()
            s.done = true
            pressed.remove(s.key)
            fire(keys[s.key])
        }
        for t in touches {
            guard let i = keyIndex(at: t.location(in: self)) else { continue }
            touchCount += 1
            let state = TouchState(key: i, at: t.location(in: self), order: touchCount)
            touchStates[ObjectIdentifier(t)] = state
            delegate?.keyboardWillPress()
            press(i, state)
        }
    }

    private func press(_ i: Int, _ state: TouchState) {
        pressed.insert(i)
        let k = keys[i]
        switch k.kind {
        case .backspace:
            delegate?.keyboardDidType(.backspace)
            repeatTimer?.invalidate()
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    self?.delegate?.keyboardDidType(.backspace)
                }
            }
        case .shift:
            let now = ProcessInfo.processInfo.systemUptime
            // như Android: đang Shift một lần mà chạm lại nhanh thì khoá chữ hoa
            switch shift {
            case .lock: shift = .off
            case .off: shift = .once
            case .once: shift = now - lastShiftTap < 0.35 ? .lock : .off
            }
            lastShiftTap = now
        case .char:
            if keyPopup { popup.show(label(k), over: k.frame.insetBy(dx: metrics(traitCollection).gapX / 2, dy: metrics(traitCollection).gapY / 2), palette: popupPalette) }
            if let h = k.hint, layout == .letters {
                state.timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak state] _ in
                    guard let self, let state else { return }
                    state.longFired = true
                    self.popup.show(h, over: self.keys[state.key].frame.insetBy(dx: 3, dy: 5), palette: self.popupPalette)
                }
            }
        default: break
        }
        setNeedsDisplay()
    }

    private var popupPalette: PopupView.Palette {
        let dark = traitCollection.userInterfaceStyle == .dark
        return PopupView.Palette(fill: dark ? UIColor(white: 0.32, alpha: 1) : .white, text: dark ? .white : .black)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let s = touchStates[ObjectIdentifier(t)], !s.done else { continue }
            let p = t.location(in: self)
            let k = keys[s.key]
            if k.kind == .space {
                if !s.trackpad && abs(p.x - s.startX) > 14 { s.trackpad = true; s.lastX = p.x }
                if s.trackpad {
                    let step: CGFloat = 9
                    while p.x - s.lastX > step { delegate?.keyboardMoveCursor(1); s.lastX += step }
                    while s.lastX - p.x > step { delegate?.keyboardMoveCursor(-1); s.lastX -= step }
                }
            } else if k.kind == .char && !s.longFired, hypot(p.x - s.start.x, p.y - s.start.y) > k.frame.width * 0.5,
                      let i = keyIndex(at: p), i != s.key, keys[i].kind == .char {
                // trượt hẳn sang phím khác trước khi nhấc: lấy phím mới (như bàn phím iOS);
                // lệch vài điểm khi gõ nhanh thì vẫn là phím đã chạm
                s.timer?.invalidate()
                pressed.remove(s.key)
                s.key = i
                press(i, s)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let s = touchStates.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            s.timer?.invalidate()
            let k = keys[s.key]
            pressed.remove(s.key)
            if s.done { continue }
            if k.kind == .backspace { repeatTimer?.invalidate(); repeatTimer = nil }
            if s.longFired, let h = k.hint { delegate?.keyboardDidType(.text(text: h)) }
            else if !s.trackpad { fire(k) }
        }
        if touchStates.isEmpty { popup.hide() }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let s = touchStates.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            s.timer?.invalidate()
            pressed.remove(s.key)
        }
        repeatTimer?.invalidate()
        repeatTimer = nil
        popup.hide()
        setNeedsDisplay()
    }

    private func cancelTimers() {
        for s in touchStates.values { s.timer?.invalidate() }
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func fire(_ k: Key) {
        switch k.kind {
        case .char:
            let text = layout == .letters && shift != .off ? k.label.uppercased() : k.label
            if shift == .once { shift = .off }
            delegate?.keyboardDidType(.text(text: text))
        case .space: delegate?.keyboardDidType(.space)
        case .ret: delegate?.keyboardDidType(.enter)
        case .numbers: layout = .numbers
        case .letters: layout = .letters
        case .symbols: layout = .symbols
        case .mode: delegate?.keyboardToggleMode()
        case .shift, .backspace, .nextKeyboard, .spacer, .gap: break
        }
    }
}

/// Ô phóng to chữ phía trên phím đang bấm. Hàng trên cùng vẽ lấn vào thanh gợi ý (bàn phím không vẽ được ra ngoài view của nó).
final class PopupView: UIView {
    struct Palette { let fill: UIColor; let text: UIColor }

    private var text = ""
    private var keyFrame = CGRect.zero
    private var colors = Palette(fill: .white, text: .black)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ text: String, over keyFrame: CGRect, palette: Palette) {
        self.text = text
        self.keyFrame = keyFrame
        colors = palette
        isHidden = false
        setNeedsDisplay()
    }

    func hide() { isHidden = true }

    override func draw(_ rect: CGRect) {
        let w = max(keyFrame.width + 14, 46)
        // phía trên hàng đầu không còn chỗ khi ẩn thanh gợi ý (iOS không cho vẽ ra ngoài bàn phím): đè lên chính phím
        let room = keyFrame.minY - 6
        let h = room >= 30 ? min(keyFrame.height * 1.15, room) : keyFrame.height
        let y = room >= 30 ? keyFrame.minY - h - 4 : 2
        let box = CGRect(x: min(max(keyFrame.midX - w / 2, 2), bounds.width - w - 2), y: y, width: w, height: h)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 10, color: UIColor(white: 0, alpha: 0.25).cgColor)
        colors.fill.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 12).fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        let a = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: min(32, h * 0.62)), .foregroundColor: colors.text])
        let s = a.size()
        a.draw(at: CGPoint(x: box.midX - s.width / 2, y: box.midY - s.height / 2))
    }
}
