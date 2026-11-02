import Foundation
import XCTest
@testable import ViPiCore

/// Ca thử lấy từ Tools/autoswitch/rules/rules.tsv của Vikey (GPL-3.0), giữ những luật bản thử nghiệm đã có.
final class AutoSwitchTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources")
    private static func text(_ name: String) -> String {
        (try? String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }
    private static let lexicon = VietnameseLexicon(text: text("vietnamese-syllables.txt"))

    /// Gõ cả chuỗi như InputController: Telex khi đang ở tiếng Việt, ghi phím khi ở tiếng Anh; ký tự không phải
    /// chữ cái kết thúc từ. Trả về chữ trên màn hình và chế độ cuối (true = tiếng Việt).
    private func type(_ keys: String, vietnamese start: Bool) -> (String, Bool) {
        let auto = try! AutoSwitch(directory: Self.resources)
        let telex = TelexEngine()
        telex.modernToneStyle = true
        telex.lexicon = Self.lexicon
        var text: [Character] = [], vi = start, english: [Character] = [], atWordStart = true
        func apply(_ edit: TextEdit) { text.removeLast(edit.backspaces); text.append(contentsOf: edit.insert) }
        for ch in keys {
            if ch.isASCII, ch.isLetter {
                if vi { apply(telex.type(ch)) } else { english.append(ch); text.append(ch) }
                continue
            }
            let word = vi ? telex.keys : english
            if vi {
                let shown = telex.output
                if atWordStart, auto.prefersEnglish(keys: word, shown: shown) {
                    apply(TextEdit(backspaces: shown.count, insert: String(word)))
                    telex.reset()
                    vi = false
                } else if let edit = telex.finishWord() {
                    apply(edit)
                    if atWordStart, auto.isForeign(keys: word, shown: shown) { vi = false }
                }
            } else {
                if atWordStart, let v = auto.vietnamese(for: english, modern: true) {
                    apply(TextEdit(backspaces: english.count, insert: v))
                    vi = true
                }
                english = []
            }
            auto.remember(ch == " " && !word.isEmpty ? word : nil)
            atWordStart = ch == " "
            text.append(ch)
        }
        return (String(text), vi)
    }

    private func check(_ cases: [(String, String, Bool)], vietnamese: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for (keys, want, wantVi) in cases {
            let (got, vi) = type(keys, vietnamese: vietnamese)
            XCTAssertEqual(got, want, "keys: \(keys)", file: file, line: line)
            XCTAssertEqual(vi, wantVi, "final mode, keys: \(keys)", file: file, line: line)
        }
    }

    func testVietnameseMode() {
        check([
            ("as ", "á ", true),
            ("boss ", "boss ", false),
            ("more ", "more ", false),
            ("server ", "server ", false),
            ("car ", "cả ", true),
            ("too ", "tô ", true),
            ("this ", "thí ", true),
            ("the best test must pass ", "the best test must pass ", false),
            ("tooi ddi hocj owr truwowngf ddaij hocj ", "tôi đi học ở trường đại học ", true),
            ("khoer khoong ", "khoẻ không ", true),
            ("var x ", "vả x ", true),
            ("tooi nghix gif ddos ", "tôi nghĩ gì đó ", true),
            ("cais testflight build ", "cái testflight build ", false),
            ("analytics dashboard ", "analytics dashboard ", false),
            ("tooi thicsh lanwm ", "tôi thích lanwm ", true),
            ("video call this ", "video call this ", false),
            ("deploy leen server nhes ", "deploy lên server nhé ", true),
        ], vietnamese: true)
    }

    func testEnglishMode() {
        check([
            ("treen ", "trên ", true),
            ("truowfng ", "trường ", true),
            ("truongwf ", "trường ", true),
            ("Truowfng Sa ", "Trường Sa ", true),
            ("con ban an ", "con ban an ", false),
            ("the theme of rust and axis ", "the theme of rust and axis ", false),
            ("i must trust the rest of the list ", "i must trust the rest of the list ", false),
            ("car been ", "car been ", false),
            ("USA EST IRS ", "USA EST IRS ", false),
            ("var x ", "var x ", false),
            ("const deps refs uri ", "const deps refs uri ", false),
            ("git push origin main ", "git push origin main ", false),
            ("obj.dir my_dir ", "obj.dir my_dir ", false),
            ("deploy leen server nhes ", "deploy lên server nhé ", true),
            ("Hey guys, cos ai ddi khoong ", "Hey guys, có ai đi không ", true),
            ("video call cos ", "video call cos ", false),
            ("ok vaayj thi mai gaawpj nhes ", "ok vậy thi mai gặp nhé ", true),
        ], vietnamese: false)
    }
}
