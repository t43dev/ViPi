import UIKit

/// Một ô trên thanh gợi ý khi gõ Việt · Anh.
struct Suggestion: Equatable {
    var text: String
    /// từ đúng như đã gõ, trong ngoặc kép: chạm vào thì giữ nguyên nó
    var quoted = false
    /// chữ mà dấu cách sẽ đưa vào thay cho từ đã gõ
    var highlighted = false
    /// từ tiếp theo (chưa gõ chữ nào của nó)
    var next = false
}

/// Gợi ý từ, tự sửa lỗi chạm lệch phím và xác suất phím kế tiếp cho bàn phím Việt · Anh, theo Vikey
/// (github.com/tonyminibot/Vikey, GPL-3.0: D26 phần thanh gợi ý, D63 đến D66). Lớp này giữ từ đang gõ và chỗ chạm của
/// từng chữ; `KeyboardViewController` báo từng phím và hỏi lại kết quả.
///
/// Khác Vikey: ViPi không có bộ máy C++ của Vikey, nên
/// - "từ đã biết" hỏi lõi Rust (`knows`), danh sách giữ nguyên (`KeepWords`) và từ vựng của hai mô hình;
/// - hoàn thành từ và tự sửa chỉ có ở trạng thái Anh (chữ trong ô là đúng các phím đã gõ); ở trạng thái Việt thanh vẫn
///   là hai lựa chọn "phím đã gõ" / "chữ có dấu" như trước, cộng với từ tiếp theo và vùng chạm theo câu.
final class Suggester {
    var suggestionsOn = true
    var autoCorrectOn = true
    /// Lõi có coi chuỗi chữ cái này là từ đã biết không (tiếng Anh, phím Telex của từ tiếng Việt, chữ chat).
    var knows: (String) -> Bool = { _ in false }

    // MARK: từ đang gõ

    /// Các chữ cái của từ đang gõ (như đã gõ) và chỗ chạm của từng chữ.
    private var typed = ""
    private var xs: [Float] = [], ys: [Float] = []
    /// Từ vừa được trả lại bằng Backspace hoặc được chọn giữ nguyên: không sửa nó nữa.
    private var keepWord: String?
    /// Lần tự sửa gần nhất: Backspace ngay sau đó trả lại từ đã gõ.
    private(set) var lastCorrection: (typed: String, inserted: String)?

    func letter(_ ch: Character, at p: CGPoint?) {
        typed.append(ch)
        xs.append(p.map { Float($0.x) } ?? .nan)
        ys.append(p.map { Float($0.y) } ?? .nan)
    }

    func backspace() {
        guard !typed.isEmpty else { return }
        typed.removeLast(); xs.removeLast(); ys.removeLast()
    }

    /// Từ kết thúc, con trỏ dời đi, đổi ô nhập: bỏ từ đang theo dõi.
    func endWord() {
        typed = ""; xs = []; ys = []
        fix = nil
        odds = nil
    }

    /// Phím khác Backspace vừa được gõ: hết cơ hội hoàn tác lần sửa trước.
    func forgetCorrection() { lastCorrection = nil }

    func reset() {
        endWord()
        keepWord = nil
        lastCorrection = nil
        state = State()
    }

    // MARK: kết quả sau mỗi phím

    private struct State {
        var context = ""        // chữ trước con trỏ
        var shown = ""          // từ đang gõ như hiện trong ô (các chữ cái cuối của context)
        var english = false     // lõi đang ở trạng thái Anh
        var telexKeys = ""      // trạng thái Việt: các phím Telex của từ đang gõ
    }
    private var state = State()
    private var fix: (word: String, for: String)?
    private var odds: (values: [Double], vietnamese: Bool)?

    private var before: String { String(state.context.dropLast(state.shown.count)) }

    /// Từ đang gõ như hiện trong ô (lúc tính gần nhất).
    var shownWord: String { state.shown }

    /// Kết quả đang giữ có được tính cho đúng chữ trước con trỏ này không. Phải hỏi trước khi xoá hay thay chữ trong ô:
    /// con trỏ có thể đã dời (kéo trên phím cách, app sửa ô) mà bộ gợi ý chưa kịp tính lại.
    func isCurrent(_ context: String) -> Bool { state.context == context }

    /// Tính lại sau một phím (chữ của phím đã vào ô): xác suất phím kế tiếp cho lần chạm sau, chữ dấu cách sẽ đưa
    /// vào, và các ô của thanh gợi ý. `capitalize`: Shift đang bật cho chữ đầu câu.
    func update(context: String, english: Bool, telexKeys: String, keys: [KeyRect], capitalize: Bool) -> [Suggestion] {
        let shown = String(context.reversed().prefix { $0.isLetter }.reversed())
        state = State(context: context, shown: shown, english: english, telexKeys: telexKeys)
        odds = nextKeyOdds()
        fix = nil
        guard !shown.isEmpty else {
            // chưa gõ chữ nào của từ mới: từ tiếp theo
            guard suggestionsOn, context.isEmpty || context.last == " " else { return [] }
            return nextWords(capitalize: capitalize).map { Suggestion(text: $0, next: true) }
        }
        guard english, shown.allSatisfy({ $0.isASCII }) else { return [] }
        let lm = SuggestLM.readyEN && !SuggestLM.shared.isEmpty ? SuggestLM.shared : nil
        if autoCorrectOn, let lm, let word = slipFix(lm, keys: keys) { fix = (cased(word), shown) }
        guard suggestionsOn || fix != nil else { return [] }
        var cells = [Suggestion(text: shown, quoted: true)]
        var seen: Set<String> = [shown.lowercased()]
        if let fix {
            seen.insert(fix.word.lowercased())
            cells.append(Suggestion(text: fix.word, highlighted: true))
        }
        if suggestionsOn, let lm {
            let low = shown.lowercased()
            var finishes = lm.completions(low, before: before, limit: 3)
            // từ đã trọn mà ít cách gõ tiếp: dạng sở hữu, như bàn phím hệ thống
            if finishes.count < 2, lm.id(low) != nil, !low.hasSuffix("'s") { finishes.append(low + "'s") }
            for f in finishes where cells.count < 3 {
                let t = cased(f)
                if seen.insert(t.lowercased()).inserted { cells.append(Suggestion(text: t)) }
            }
        }
        if cells.count == 1 { cells[0].quoted = false }
        return cells
    }

    /// Chữ mà phím kết thúc từ sẽ đưa vào thay cho từ đang hiện, nếu có (tính cho đúng từ đó).
    func correction() -> String? {
        guard let fix, fix.for == state.shown else { return nil }
        return fix.word
    }

    func didCorrect(typed: String, inserted: String) {
        lastCorrection = (typed, inserted)
        endWord()
    }

    /// Backspace ngay sau một lần tự sửa: trả về (số ký tự phải xoá, chữ gõ lại) nếu chữ đã sửa còn ngay trước con trỏ.
    func undoCorrection(context: String) -> (delete: Int, insert: String)? {
        guard let c = lastCorrection else { return nil }
        lastCorrection = nil
        guard context.hasSuffix(c.inserted) else { return nil }
        keepWord = c.typed.lowercased()
        endWord()
        return (c.inserted.count, c.typed)
    }

    /// Người dùng chạm vào từ trong ngoặc kép: giữ nguyên nó.
    func keepShown() {
        keepWord = state.shown.lowercased()
        fix = nil
    }

    // MARK: vùng chạm (D65, D66)

    /// 27 xác suất cho lần chạm kế tiếp (a…z rồi "từ kết thúc"), đã tính sau phím trước; nil thì bàn phím tự chọn
    /// phím theo chỗ chạm. Không tính gì lúc chạm.
    func touchOdds() -> (odds: [Double], vietnamese: Bool)? {
        guard autoCorrectOn, let odds else { return nil }
        return (odds.values, odds.vietnamese)
    }

    /// Chạm vào khe giữa hàng chữ dưới cùng và phím cách khi chưa có xác suất phím kế tiếp (mô hình chưa nạp xong):
    /// là dấu cách khi từ tiếng Anh đang gõ đã là một từ và không từ nào gõ tiếp bằng `letter` ("thank" rồi chạm dưới
    /// n). Có xác suất thì TapModel tự cân phím cách với các chữ, ở cả hai thứ tiếng.
    func wordEnds(before letter: String) -> Bool {
        guard autoCorrectOn, state.english, let l = letter.lowercased().unicodeScalars.first, (97...122).contains(l.value) else { return false }
        let w = state.shown.lowercased()
        guard w.count >= 2, w.allSatisfy({ $0.isASCII && $0.isLetter }), SuggestLM.readyEN, !SuggestLM.shared.isEmpty else { return false }
        guard knows(w) || SuggestLM.shared.id(w) != nil else { return false }
        return !SuggestLM.shared.startsWord(w + letter.lowercased())
    }

    private func nextKeyOdds() -> (values: [Double], vietnamese: Bool)? {
        guard autoCorrectOn else { return nil }
        if state.english {
            let w = state.shown
            guard !w.isEmpty, w.allSatisfy({ $0.isASCII }), SuggestLM.readyEN, !SuggestLM.shared.isEmpty,
                  let o = SuggestLM.shared.nextLetters(w.lowercased(), before: before), o.count == 27 else { return nil }
            return (o, false)
        }
        guard !state.telexKeys.isEmpty, SuggestLM.readyVI, !SuggestLM.vietnamese.isEmpty,
              let o = SuggestLM.vietnamese.nextKeys(state.telexKeys, before: before, toneNow: 0.03), o.count == 27 else { return nil }
        return (o, true)
    }

    // MARK: tự sửa lỗi chạm lệch phím (D63, theo các giới hạn của D26)

    private static let slipMargin = 3.0
    /// Từ thay vào phải đủ hợp với câu: log P(từ | các từ trước) trên mức này. Vikey không có ngưỡng này; với nó,
    /// trong mô phỏng chạm lệch (8 pt) chữ chat gõ đúng mà bị đổi giảm từ 4,6% xuống 0,16%, còn từ tiếng Anh gõ lệch
    /// được sửa đúng 61 trên 70 (không ngưỡng: 66).
    private static let slipLikelihoodFloor = -9.0

    /// Dạng chữ không phải lỗi gõ: không có nguyên âm (viết tắt), ba chữ giống nhau liền nhau hoặc nguyên âm cuối gõ
    /// đôi (kéo dài chữ: "oiii", "nhaa").
    private static func looksTyped(_ low: String) -> Bool {
        let c = Array(low)
        guard c.contains(where: { "aeiouy".contains($0) }) else { return false }
        if c.count >= 3, (2..<c.count).contains(where: { c[$0] == c[$0 - 1] && c[$0] == c[$0 - 2] }) { return false }
        if c.count >= 2, c[c.count - 1] == c[c.count - 2], "aeiouy".contains(c[c.count - 1]) { return false }
        return true
    }

    /// Từ mà các lần chạm nhiều khả năng định gõ, khi rõ ràng không phải chính các chữ đã gõ. Không bao giờ sửa: từ
    /// đã biết (cả hai thứ tiếng), chữ gõ ra âm tiết tiếng Việt, từ trong danh sách giữ nguyên, từ dưới 3 chữ, từ có
    /// từ 2 chữ hoa, từ vừa được trả lại, và các chữ đang trên đường tới một từ hay gặp hơn ("peop" → people).
    private func slipFix(_ lm: SuggestLM, keys: [KeyRect]) -> String? {
        let shown = state.shown, low = shown.lowercased()
        // chỉ từ đứng riêng: sau dấu cách, đầu ô hoặc dấu mở ngoặc. Chữ dính sau số, dấu chấm, gạch dưới ("report.docx",
        // "abc1xyz", "user_nmae") là tên file, mã, tên biến
        guard before.last.map({ $0.isWhitespace || "\"'(“‘[".contains($0) }) ?? true else { return nil }
        guard low.count >= 3, typed.lowercased() == low, !xs.contains(where: { $0.isNaN }), !keys.isEmpty,
              shown.filter({ $0.isUppercase }).count < 2, keepWord != low,
              Self.looksTyped(low), lm.id(low) == nil, !knows(low), !KeepWords.shared.contains(low) else { return nil }
        let reads = lm.readTaps(zip(xs, ys).map { (x: $0, y: $1) }, keys: keys, before: before)
        guard let best = reads.first, best.word.lowercased() != low else { return nil }
        // các chữ đã gõ không phải một từ: điểm của chính chúng là độ gần ~0 cộng một xác suất rất nhỏ
        let typedScore = reads.first { $0.word.lowercased() == low }?.score ?? -40
        guard best.score - typedScore > Self.slipMargin, best.likelihood > Self.slipLikelihoodFloor else { return nil }
        return lm.prefersFinishing(low, over: best.word, before: before) ? nil : best.word
    }

    // MARK: từ tiếp theo

    private func nextWords(capitalize: Bool) -> [String] {
        var out: [String] = []
        if state.english {
            if SuggestLM.readyEN, !SuggestLM.shared.isEmpty { out = SuggestLM.shared.nextWords(before: state.context, limit: 3) }
        } else if SuggestLM.readyVI, !SuggestLM.vietnamese.isEmpty {
            out = SuggestLM.vietnamese.nextWords(before: state.context, limit: 3)
        }
        return capitalize ? out.map { $0.prefix(1).uppercased() + $0.dropFirst() } : out
    }

    /// Viết hoa chữ đầu như từ đã gõ ("Teh" → "The").
    private func cased(_ s: String) -> String {
        state.shown.first?.isUppercase == true ? s.prefix(1).uppercased() + s.dropFirst() : s
    }
}
