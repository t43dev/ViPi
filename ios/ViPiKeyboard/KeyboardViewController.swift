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
    private var fieldType: UIKeyboardType?
    /// Enter của ô này mở địa chỉ hoặc tìm kiếm (nút Go / Search, ô URL): xem keyboardDidType
    private var enterSubmitsSearch = false
    private var passthrough = false
    private var lastSpaceAt: TimeInterval = 0
    private var lastOwnEdit: TimeInterval = 0
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // gợi ý từ, tự sửa lỗi gõ, vùng chạm theo câu (Suggest/Suggester.swift)
    private let suggester = Suggester()
    private var suggestions: [Suggestion] = []
    private var suggestionsDirty = false
    /// Ô nhập này có nhận gợi ý và tự sửa không (như bàn phím hệ thống: không ở ô địa chỉ, email, số, ô tắt tự sửa).
    private var suggestsHere = false

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
        keyboard.setNeedsDisplay()   // vùng ảnh đã bỏ lúc ẩn (viewDidDisappear)
        applyPrefs()
        startInput()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboard.showsNextKeyboard = needsInputModeSwitchKey
        heightConstraint?.constant = keyboard.preferredHeight(traits: traitCollection)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // mô hình gợi ý (65 MB, đọc bằng mmap) chỉ được nạp sau khi bàn phím đã hiện, ở hàng đợi nền (Vikey D64):
        // đọc lúc mở làm bàn phím lên chậm, iOS có lúc bỏ cuộc và hiện bàn phím của nó. Chưa sẵn thì thanh để trống.
        guard suggester.suggestionsOn || suggester.autoCorrectOn else { return }
        SuggestLM.warmUp(vietnameseFirst: composer?.mode() == .vietnamese) { [weak self] in self?.scheduleSuggestions() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        endComposition()
        keyboard.reset()
        fieldType = nil
        SuggestLM.coolDown()
        suggester.reset()
        suggestions = []
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        keyboard.releaseSurfaces()
    }

    /// iOS tạo một controller mới cho mỗi lần bàn phím hiện lên, trong cùng tiến trình. Nó bỏ controller cũ nhưng
    /// còn giữ view gốc của controller đó: gỡ các view con ra thì bàn phím, thanh gợi ý và các nút ứng viên của lần
    /// mở trước mới được giải phóng (Vikey D67 đo: mỗi lần mở giữ lại ~0,5 MB, tới giới hạn bộ nhớ thì iOS tắt bàn phím).
    deinit {
        MainActor.assumeIsolated {
            viewIfLoaded?.subviews.forEach { $0.removeFromSuperview() }
        }
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
        // không có chữ đang soạn trong ô (đang gõ tiếng Anh, hoặc vừa tự đổi xong) thì lõi vẫn nhớ từ tiếng Anh đang
        // gõ và lần hoàn tác bằng Backspace: con trỏ đã dời thì bỏ, không sẽ sửa nhầm chữ ở chỗ mới
        if shown.isEmpty ? composer?.isComposingChinese() == false : !before.hasSuffix(shown) {
            shown = ""
            composer?.cancel()
            suggester.endWord()
            refreshUI()
        }
        updateShift()
        scheduleSuggestions()
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
        // hàm này chạy sau mỗi lần ô nhập đổi chữ (kể cả do chính bàn phím gõ): chỉ mở sẵn bàn số một lần cho
        // mỗi ô, không thì người dùng vừa về bàn chữ gõ một phím là bị đẩy lại bàn số
        if type != fieldType {
            fieldType = type
            let numbers = numeric.contains(type) || type == .numbersAndPunctuation
            // rời ô số sang ô chữ (bàn phím không đóng giữa hai ô): về trang chữ, không kẹt ở trang 123
            let leftNumbers = !numbers && keyboard.baseLayout == .numbers
            keyboard.baseLayout = numbers ? .numbers : .letters
            if numbers, keyboard.layout == .letters { keyboard.layout = .numbers }
            if leftNumbers { keyboard.layout = .letters }
        }
        keyboard.returnKey = KeyboardView.ReturnKey(proxy.returnKeyType ?? .default)
        enterSubmitsSearch = [.go, .search, .google, .yahoo].contains(proxy.returnKeyType ?? .default)
            || type == .URL || type == .webSearch
        suggestsHere = !passthrough && proxy.autocorrectionType != .no && proxy.spellCheckingType != .no
            && ![.URL, .emailAddress, .webSearch].contains(type)
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
        suggester.suggestionsOn = vietnameseBar && Prefs.bool(Prefs.suggestions)
        suggester.autoCorrectOn = Prefs.bool(Prefs.autoCorrect)
        suggester.knows = { [weak self] in self?.composer?.knowsWord(letters: $0) ?? true }
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
        suggester.endWord()
        refreshUI()
        updateShift()
        scheduleSuggestions()
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
        scheduleSuggestions()
    }

    /// App xoá ô nhập (nút gửi của Telegram) mà thông báo tới lúc bàn phím còn bỏ qua (0,3 s sau phím vừa gõ, xem
    /// cursorMaybeMoved): ô đã trống thì bỏ chữ đang soạn, không thì phím sau tính lại cả chữ cũ và chèn nó vào ô
    /// trống ("dúngddunf"). Chỉ xét ô trống: so nội dung ô có thể nhầm khi gõ nhanh.
    private func syncWithField() {
        // pinyin đang soạn nằm trên thanh gợi ý, không nằm trong ô: ô trống lúc đó là bình thường
        guard !textDocumentProxy.hasText, composer?.isComposingChinese() != true else { return }
        shown = ""
        composer?.cancel()
        dropSuggestions()
        refreshUI()
    }

    func keyboardDidType(_ key: KeyInput) {
        syncWithField()
        markOwnEdit()
        guard let c = composer, !passthrough else {
            deliver(key)
            updateShift()
            return
        }
        // Backspace ngay sau một lần tự sửa lỗi gõ: trả lại từ đã gõ và giữ nó (trước cả lõi: lõi không biết lần sửa này)
        if case .backspace = key {
            if let undo = suggester.undoCorrection(context: textDocumentProxy.documentContextBeforeInput ?? "") {
                deleteBefore(undo.delete)
                textDocumentProxy.insertText(undo.insert)
                c.cancel()
                refreshUI()
                updateShift()
                scheduleSuggestions()
                return
            }
        } else {
            suggester.forgetCorrection()
        }
        let before = c.mode()
        // Enter mở địa chỉ / tìm kiếm gửi đúng chữ đang thấy (Vikey D62): chữ trên màn hình còn y như phím đã gõ thì
        // không đổi nó nữa. Đổi lúc này làm mất phần trình duyệt đang gợi ý ("ver" + Enter mở vercel.com, không
        // phải đi tìm "vẻ"). Chữ đã thành tiếng Việt trên màn hình thì vẫn xử lý như mọi lần kết thúc từ.
        if case .enter = key, enterSubmitsSearch, !c.isComposingChinese(),
           before == .english || c.currentWord() == c.currentKeys() {
            endComposition()
            deliver(key)
            updateShift()
            return
        }
        // tiếng Anh, phím kết thúc từ: chữ sẽ thay cho từ gõ lệch phím, quyết định trên cả từ (thanh gợi ý tính sau
        // mỗi phím, gõ nhanh hơn thế thì tính ngay bây giờ)
        var correction: (typed: String, word: String, end: String)?
        if before == .english, suggestsHere, let end = Self.breakText(key) {
            // tính lại nếu chữ trước con trỏ không còn là chữ bộ gợi ý đã thấy (gõ nhanh, con trỏ vừa dời)
            if suggestionsDirty || !suggester.isCurrent(textDocumentProxy.documentContextBeforeInput ?? "") { updateSuggestions() }
            if let word = suggester.correction() { correction = (suggester.shownWord, word, end) }
        }
        let wordLength = c.currentWord().count
        let hadWord = wordLength > 0
        let r = c.handleKey(key: key)
        trackWord(key)
        if case .backspace = key, let undo = r.edit {
            // Backspace ngay sau một lần tự đổi: trả lại chữ trước đó (lõi đã về chế độ cũ)
            finishComposing()
            deleteBefore(Int(undo.backspaces))
            commit(undo.insert)
        } else {
            switch before {
            case .vietnamese: applyVietnamese(key, r, hadWord: hadWord, wordLength: wordLength)
            case .english:
                // lõi có sửa gì (tự đổi sang tiếng Việt, gõ tắt) thì lõi thắng; không thì mới tới lượt sửa lỗi gõ
                if let fix = correction, r.edit == nil {
                    deleteBefore(fix.typed.count)
                    textDocumentProxy.insertText(fix.word)
                    deliver(key)
                    suggester.didCorrect(typed: fix.typed, inserted: fix.word + fix.end)
                } else {
                    applyEnglish(key, r)
                }
            case .chinese: applyChinese(key, r)
            }
        }
        if let m = r.switchedTo { saveMode(m) }
        refreshUI()
        updateShift()
        scheduleSuggestions()
    }

    /// Chữ của một phím kết thúc từ mà tự sửa lỗi gõ nhận (dấu cách và dấu câu), nil nếu không phải.
    private static func breakText(_ key: KeyInput) -> String? {
        switch key {
        case .space: return " "
        case .text(let t) where [".", ",", "?", "!", ";", ":"].contains(t): return t
        default: return nil
        }
    }

    /// Báo cho bộ gợi ý phím vừa gõ: chữ cái (kèm chỗ chạm) vào từ đang gõ, Backspace bỏ chữ cuối, phím khác kết thúc từ.
    private func trackWord(_ key: KeyInput) {
        switch key {
        case .text(let t) where t.count == 1 && t.first!.isASCII && t.first!.isLetter: suggester.letter(t.first!, at: keyboard.lastTap)
        case .backspace: suggester.backspace()
        default: suggester.endWord()
        }
    }

    // MARK: - Gợi ý từ

    /// Thanh gợi ý được tính sau khi chữ của phím đã vào ô nhập, nên không làm chậm phím; gõ nhanh hơn thế thì bỏ
    /// qua các bước ở giữa.
    private func scheduleSuggestions() {
        guard !suggestionsDirty else { return }
        suggestionsDirty = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.suggestionsDirty else { return }
            self.updateSuggestions()
            self.refreshUI()
        }
    }

    private func updateSuggestions() {
        suggestionsDirty = false
        guard let c = composer, suggestsHere, c.mode() != .chinese, suggester.suggestionsOn || suggester.autoCorrectOn,
              textDocumentProxy.selectedText == nil else {
            suggestions = []
            suggester.endWord()
            return
        }
        let english = c.mode() == .english
        suggestions = suggester.update(context: textDocumentProxy.documentContextBeforeInput ?? "", english: english,
                                       telexKeys: english ? "" : c.currentKeys(), keys: keyboard.letterRects,
                                       capitalize: keyboard.shift != .off)
    }

    func keyboardTouchOdds() -> (odds: [Double], vietnamese: Bool)? {
        suggestionsDirty || !suggestsHere ? nil : suggester.touchOdds()
    }

    func keyboardWordEnds(before letter: String) -> Bool {
        !suggestionsDirty && suggestsHere && suggester.wordEnds(before: letter)
    }

    /// Chạm một ô trên thanh gợi ý Việt · Anh.
    func keyboardPickWord(_ index: Int) {
        guard let c = composer, index < suggestions.count else { return }
        // các ô đang hiện phải đúng với chữ trước con trỏ lúc này; không thì tính lại và bỏ lần chạm (ô đã đổi)
        guard !suggestionsDirty, suggester.isCurrent(textDocumentProxy.documentContextBeforeInput ?? "") else {
            updateSuggestions()
            refreshUI()
            return
        }
        let cell = suggestions[index]
        keyboardWillPress()
        markOwnEdit()
        suggester.forgetCorrection()
        if cell.quoted {
            // giữ đúng từ đã gõ: một dấu cách, và không sửa nó
            suggester.keepShown()
            keyboardDidType(.space)
            return
        }
        finishComposing()
        if !cell.next { deleteBefore(suggester.shownWord.count) }
        textDocumentProxy.insertText(cell.text + " ")
        lastSpaceAt = ProcessInfo.processInfo.systemUptime
        c.cancel()
        suggester.endWord()
        suggestions = []
        refreshUI()
        updateShift()
        scheduleSuggestions()
    }

    func keyboardPickCandidate(_ index: Int) {
        guard let c = composer else { return }
        markOwnEdit()
        applyChinese(nil, c.selectCandidate(index: UInt32(index)))
        refreshUI()
    }

    func keyboardDismiss() {
        endComposition()
        dismissKeyboard()
    }

    /// Dấu câu trên thanh khi gõ tiếng Trung mà chưa có chữ đang soạn.
    func keyboardTypePunctuation(_ text: String) {
        keyboardWillPress()
        markOwnEdit()
        endComposition()
        textDocumentProxy.insertText(text)
        updateShift()
    }

    /// Thanh gợi ý tiếng Việt: giữ đúng các phím đã gõ (0) hoặc chữ đang hiện (1), rồi một dấu cách.
    func keyboardPickSuggestion(_ index: Int) {
        syncWithField()
        guard let c = composer, !c.currentWord().isEmpty else { return }
        markOwnEdit()
        setComposing(index == 0 ? c.currentKeys() : c.currentWord())
        finishComposing()
        commit(" ")
        c.cancel()
        dropSuggestions()
        refreshUI()
        updateShift()
        scheduleSuggestions()
    }

    // MARK: - Áp kết quả của lõi (giống Android)

    private func applyVietnamese(_ key: KeyInput, _ r: KeyOutcome, hadWord: Bool, wordLength: Int) {
        guard let c = composer else { return }
        if case .text(let t) = key, t.count == 1, let ch = t.first, ch.isASCII, ch.isLetter {
            let word = c.currentWord()
            // chữ dính sau số ("abc1def", "65w") lõi cho đi thẳng, không vào từ đang soạn: gửi nguyên phím
            if word.isEmpty { finishComposing(); deliver(key) } else {
                // gõ tiếp vào chữ vừa tự sửa ("vây" ⌫ "j"): chữ đó đã nằm trong ô, bỏ đi để soạn lại cả từ
                if r.reopened > 0 { deleteBefore(Int(r.reopened)) }
                setComposing(word)
            }
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
        dropSuggestions()
        refreshUI()
    }

    /// Từ đang theo dõi không còn đúng nữa (con trỏ dời, ô bị xoá, đổi chế độ): bỏ các ô gợi ý, chữ định sửa và xác
    /// suất phím kế tiếp; lần tính sau đọc lại ô nhập.
    private func dropSuggestions() {
        suggester.endWord()
        suggestions = []
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
        } else if let c, !passthrough, c.mode() == .chinese {
            kb.bar.content = .punctuation(keyboard.fullWidth ? ["，", "。", "？", "！", "、", "……"] : [",", ".", "?", "!"])
        } else if !passthrough, !suggestions.isEmpty {
            kb.bar.content = .suggestions(suggestions)
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
