import UIKit

/// Lõi bộ gõ, nạp một lần cho tiến trình bàn phím. Dữ liệu nằm trong bundle của bàn phím, lõi Rust đọc bằng mmap.
final class Engine {
    static let shared = Engine()
    let composer: ViPiComposer?

    private init() {
        composer = try? ViPiComposer(resourceDir: Bundle.main.resourcePath ?? "")
    }

    /// Từ đã học: trong vùng riêng của bàn phím (không cần Full Access).
    static var learnedFile: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pinyin-user.json").path
    }
}

extension InputMode {
    var name: String {
        switch self {
        case .vietnamese: return "vietnamese"
        case .chinese: return "chinese"
        case .english: return "english"
        }
    }

    init?(name: String?) {
        switch name {
        case "vietnamese": self = .vietnamese
        case "chinese": self = .chinese
        case "english": self = .english
        default: return nil
        }
    }
}

/// Bàn phím ViPi. Cùng cách xử lý phím với bản Android (ViPiInputMethod.kt): lõi trả về số ký tự cần xoá và chữ cần chèn.
/// iOS không có "vùng đang soạn" như Android, nên `shown` nhớ phần chữ đang gõ đã nằm trong ô nhập;
/// các hàm setComposing/finishComposing/commit dưới đây làm đúng việc của InputConnection tương ứng.
/// Pinyin chưa chọn không chèn vào ô nhập mà hiện trên thanh gợi ý (setMarkedText của iOS lỗi ở nhiều app).
final class KeyboardViewController: UIInputViewController, KeyboardViewDelegate {
    private var keyboard: KeyboardView!
    private var heightConstraint: NSLayoutConstraint?
    private var vietnameseBar = true
    private var composer: ViPiComposer? { Engine.shared.composer }
    /// Trạng thái riêng của bàn phím (chế độ đang dùng…), bàn phím tự ghi được.
    private let local = UserDefaults.standard

    private var shown = ""
    private var passthrough = false
    private var lastSpaceAt: TimeInterval = 0
    private var lastOwnEdit: TimeInterval = 0
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Vòng đời

    override func viewDidLoad() {
        super.viewDidLoad()
        let kb = KeyboardView(frame: view.bounds)
        kb.delegate = self
        kb.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kb)
        NSLayoutConstraint.activate([
            kb.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kb.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kb.topAnchor.constraint(equalTo: view.topAnchor),
            kb.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        kb.nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        keyboard = kb
        let h = view.heightAnchor.constraint(equalToConstant: kb.preferredHeight(traits: traitCollection))
        h.priority = UILayoutPriority(999)
        h.isActive = true
        heightConstraint = h
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyPrefs()
        startInput()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboard.showsNextKeyboard = needsInputModeSwitchKey
        heightConstraint?.constant = keyboard.preferredHeight(traits: traitCollection)
    }

    override func viewWillDisappear(_ animated: Bool) {
        endComposition()
        keyboard.reset()
        super.viewWillDisappear(animated)
    }

    // MARK: - Ô nhập

    override func textWillChange(_ textInput: UITextInput?) {}

    override func textDidChange(_ textInput: UITextInput?) {
        cursorMaybeMoved()
        startInput()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        cursorMaybeMoved()
    }

    /// Con trỏ bị di chuyển ngoài bàn phím (chạm chỗ khác trong ô nhập): bỏ phần đang gõ.
    private func cursorMaybeMoved() {
        guard ProcessInfo.processInfo.systemUptime - lastOwnEdit > 0.3 else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if !shown.isEmpty && !before.hasSuffix(shown) {
            shown = ""
            composer?.cancel()
            refreshUI()
        }
        updateShift()
    }

    /// Đọc loại ô nhập: ô số đi thẳng không qua lõi, phím Return theo hành động của ô.
    private func startInput() {
        let proxy = textDocumentProxy
        let type = proxy.keyboardType ?? .default
        let numeric: [UIKeyboardType] = [.numberPad, .decimalPad, .phonePad, .namePhonePad, .asciiCapableNumberPad]
        let wasPassthrough = passthrough
        passthrough = composer == nil || proxy.isSecureTextEntry == true || numeric.contains(type)
        if passthrough && !wasPassthrough { endComposition() }
        keyboard.modeLocked = passthrough
        if numeric.contains(type) || type == .numbersAndPunctuation {
            if keyboard.layout == .letters { keyboard.layout = .numbers }
        }
        keyboard.returnKey = KeyboardView.ReturnKey(proxy.returnKeyType ?? .default)
        let appearance: UIUserInterfaceStyle
        switch Prefs.string(Prefs.theme) {
        case "light": appearance = .light
        case "dark": appearance = .dark
        default: appearance = proxy.keyboardAppearance == .dark ? .dark : .unspecified
        }
        keyboard.overrideUserInterfaceStyle = appearance
        refreshUI()
        updateShift()
    }

    private func applyPrefs() {
        keyboard.keyPopup = Prefs.bool(Prefs.keyPopup)
        vietnameseBar = Prefs.bool(Prefs.vietnameseBar)
        keyboard.fullWidth = Prefs.bool(Prefs.fullWidth)
        keyboard.splitOnPad = Prefs.string(Prefs.largeLayout) != "wide"
        guard let c = composer else { return }
        c.setVietnameseOptions(modernToneStyle: Prefs.bool(Prefs.modernTone), spellCheck: Prefs.bool(Prefs.spellCheck),
                               restoreNonVietnamese: Prefs.bool(Prefs.restore))
        c.setFullWidthPunctuation(on: Prefs.bool(Prefs.fullWidth))
        c.setFuzzyRules(ids: Prefs.fuzzyRules)
        c.setTraditional(on: Prefs.bool(Prefs.traditional))
        // app không ghi được vào vùng của bàn phím: nó để lại yêu cầu xoá trong App Group
        let request = Prefs.shared.double(forKey: Prefs.clearLearnedAt)
        if request > local.double(forKey: "clearedLearnedAt") {
            c.clearLearned()
            try? FileManager.default.removeItem(atPath: Engine.learnedFile)
            local.set(request, forKey: "clearedLearnedAt")
        }
        c.setLearning(on: Prefs.bool(Prefs.learn), file: Engine.learnedFile)
        // Việt và Anh là một bộ gõ, luôn tự nhận diện; phím ngôn ngữ chỉ đổi giữa Việt·Anh và Trung
        c.setAutoSwitch(on: true)
        if c.mode() != savedMode { c.setMode(mode: savedMode) }
    }

    // MARK: - Chế độ

    private var savedMode: InputMode { InputMode(name: local.string(forKey: "mode")) ?? .english }
    private var latin: InputMode { InputMode(name: local.string(forKey: "latin")) ?? .english }

    private func saveMode(_ m: InputMode) {
        local.set(m.name, forKey: "mode")
        if m != .chinese { local.set(m.name, forKey: "latin") }
    }

    private func setMode(_ mode: InputMode) {
        guard let c = composer else { return }
        endComposition()
        c.setMode(mode: mode)
        saveMode(mode)
        refreshUI()
        updateShift()
    }

    // MARK: - KeyboardViewDelegate

    func keyboardWillPress() {
        if Prefs.bool(Prefs.haptics) && hasFullAccess { haptic.impactOccurred() }
    }

    func keyboardToggleMode() {
        guard !passthrough, let c = composer else { return }
        setMode(c.mode() == .chinese ? latin : .chinese)
    }

    func keyboardMoveCursor(_ delta: Int) {
        endComposition()
        markOwnEdit()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
    }

    func keyboardDidType(_ key: KeyInput) {
        markOwnEdit()
        guard let c = composer, !passthrough else {
            deliver(key)
            updateShift()
            return
        }
        let before = c.mode()
        let wordLength = c.currentWord().count
        let hadWord = wordLength > 0
        let r = c.handleKey(key: key)
        if case .backspace = key, let undo = r.edit {
            // Backspace ngay sau một lần tự đổi: trả lại chữ trước đó (lõi đã về chế độ cũ)
            finishComposing()
            deleteBefore(Int(undo.backspaces))
            commit(undo.insert)
        } else {
            switch before {
            case .vietnamese: applyVietnamese(key, r, hadWord: hadWord, wordLength: wordLength)
            case .english: applyEnglish(key, r)
            case .chinese: applyChinese(key, r)
            }
        }
        if let m = r.switchedTo { saveMode(m) }
        refreshUI()
        updateShift()
    }

    func keyboardPickCandidate(_ index: Int) {
        guard let c = composer else { return }
        markOwnEdit()
        applyChinese(nil, c.selectCandidate(index: UInt32(index)))
        refreshUI()
    }

    /// Thanh gợi ý tiếng Việt: giữ đúng các phím đã gõ (0) hoặc chữ đang hiện (1), rồi một dấu cách.
    func keyboardPickSuggestion(_ index: Int) {
        guard let c = composer else { return }
        markOwnEdit()
        setComposing(index == 0 ? c.currentKeys() : c.currentWord())
        finishComposing()
        commit(" ")
        c.cancel()
        refreshUI()
        updateShift()
    }

    // MARK: - Áp kết quả của lõi (giống Android)

    private func applyVietnamese(_ key: KeyInput, _ r: KeyOutcome, hadWord: Bool, wordLength: Int) {
        guard let c = composer else { return }
        if case .text(let t) = key, t.count == 1, let ch = t.first, ch.isASCII, ch.isLetter {
            setComposing(c.currentWord())
            return
        }
        if case .backspace = key {
            if hadWord {
                setComposing(c.currentWord())
                if c.currentWord().isEmpty { finishComposing() }
            } else {
                deliver(key)
            }
            return
        }
        if let edit = r.edit {
            if Int(edit.backspaces) > wordLength {
                // tự đổi sửa cả từ trước ("thí makes" → "this makes"): xoá cả phần ngoài chữ đang gõ
                finishComposing()
                deleteBefore(Int(edit.backspaces))
                commit(edit.insert)
            } else {
                setComposing(edit.insert)
                finishComposing()
            }
            if r.repostKey { deliver(key) }
        } else {
            finishComposing()
            deliver(key)
        }
    }

    private func applyEnglish(_ key: KeyInput, _ r: KeyOutcome) {
        guard let edit = r.edit else { deliver(key); return }
        deleteBefore(Int(edit.backspaces))
        commit(edit.insert)
        if r.repostKey { deliver(key) }
    }

    /// Chữ Hán đã chọn được chèn; pinyin còn lại (chọn từng phần) vẫn nằm trên thanh gợi ý.
    private func applyChinese(_ key: KeyInput?, _ r: KeyOutcome) {
        if !r.handled { if let key { deliver(key) }; return }
        if let edit = r.edit { commit(edit.insert) }
        if r.repostKey, let key { deliver(key) }
    }

    /// Bỏ phần đang gõ: chữ Việt đang gõ giữ lại, pinyin chưa chọn thì bỏ.
    private func endComposition() {
        finishComposing()
        composer?.cancel()
        refreshUI()
    }

    // MARK: - Thao tác trên ô nhập

    private func markOwnEdit() { lastOwnEdit = ProcessInfo.processInfo.systemUptime }

    /// Thay chữ đang soạn bằng `text`, chỉ xoá và gõ lại phần khác nhau ở cuối.
    private func setComposing(_ text: String) {
        let old = Array(shown), new = Array(text)
        var same = 0
        while same < old.count && same < new.count && old[same] == new[same] { same += 1 }
        deleteBefore(old.count - same)
        if same < new.count { textDocumentProxy.insertText(String(new[same...])) }
        shown = text
    }

    private func finishComposing() { shown = "" }

    private func commit(_ text: String) {
        setComposing(text)
        shown = ""
    }

    private func deleteBefore(_ n: Int) {
        guard n > 0 else { return }
        for _ in 0..<n { textDocumentProxy.deleteBackward() }
    }

    /// Phím đi thẳng tới ô nhập như một bàn phím thường.
    private func deliver(_ key: KeyInput) {
        let proxy = textDocumentProxy
        switch key {
        case .text(let t): commit(t)
        case .space: space()
        case .enter: proxy.insertText("\n")
        case .backspace: proxy.deleteBackward()
        case .tab: proxy.insertText("\t")
        case .left: proxy.adjustTextPosition(byCharacterOffset: -1)
        case .right: proxy.adjustTextPosition(byCharacterOffset: 1)
        default: break
        }
        if case .space = key {} else { lastSpaceAt = 0 }
    }

    /// Hai lần cách liền nhau sau một chữ: ". ".
    private func space() {
        let now = ProcessInfo.processInfo.systemUptime
        if Prefs.bool(Prefs.doubleSpace) && now - lastSpaceAt < 0.6 {
            let before = Array((textDocumentProxy.documentContextBeforeInput ?? "").suffix(2))
            if before.count == 2, before[1] == " ", before[0].isLetter || before[0].isNumber {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(". ")
                lastSpaceAt = 0
                return
            }
        }
        textDocumentProxy.insertText(" ")
        lastSpaceAt = now
    }

    // MARK: - Giao diện

    private func refreshUI() {
        guard let kb = keyboard else { return }
        let c = composer
        kb.mode = passthrough || c == nil ? .english : c!.mode()
        // thanh gợi ý: luôn có khi gõ tiếng Trung, khi gõ Việt · Anh thì theo cài đặt; ô mật khẩu / số thì không
        let showsBar = !passthrough && (kb.mode == .chinese || vietnameseBar)
        if kb.showsBar != showsBar {
            kb.showsBar = showsBar
            heightConstraint?.constant = kb.preferredHeight(traits: traitCollection)
        }
        if let c, !passthrough, c.isComposingChinese() {
            kb.bar.content = .chinese(preedit: c.preedit(), candidates: c.candidates().prefix(60).map(\.text))
        } else if let c, !passthrough, c.mode() == .vietnamese, !c.currentWord().isEmpty, c.currentKeys() != c.currentWord() {
            kb.bar.content = .vietnamese(keys: c.currentKeys(), word: c.currentWord())
        } else {
            kb.bar.content = .empty
        }
    }

    private func updateShift() {
        guard let kb = keyboard, kb.layout == .letters, kb.shift != .lock else { return }
        // tiếng Trung: không tự viết hoa (chữ hoa không phải pinyin, sẽ đi thẳng vào ô nhập)
        let chinese = !passthrough && composer?.mode() == .chinese
        if !Prefs.bool(Prefs.autoCap) || chinese {
            if chinese && kb.shift == .once { kb.shift = .off }
            return
        }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let caps: Bool
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .allCharacters: caps = true
        case .words: caps = before.isEmpty || before.last?.isWhitespace == true
        case .sentences: caps = Self.atSentenceStart(before)
        default: caps = false
        }
        kb.shift = caps && (composer?.currentWord().isEmpty ?? true) ? .once : .off
    }

    static func atSentenceStart(_ before: String) -> Bool {
        if before.isEmpty || before.last == "\n" { return true }
        guard before.last == " " else { return false }
        guard let last = before.trimmingCharacters(in: .whitespaces).last else { return true }
        return ".!?。！？\n".contains(last)
    }
}
