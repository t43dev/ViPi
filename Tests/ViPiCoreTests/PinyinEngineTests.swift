import Foundation
import XCTest
@testable import ViPiCore

final class PinyinEngineTests: XCTestCase {
    static let dict: PinyinDictionary = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/pinyin.tsv")
        return try! PinyinDictionary(contentsOf: url)
    }()

    private func top(_ input: String, _ n: Int = 5) -> [String] {
        let e = PinyinEngine(dictionary: Self.dict)
        for c in input { e.type(c) }
        return e.candidates.prefix(n).map(\.text)
    }

    func testDictionaryLoaded() {
        XCTAssertGreaterThan(Self.dict.syllables.count, 400)
        XCTAssertTrue(Self.dict.syllables.contains("zhuang"))
    }

    func testCommonWords() {
        XCTAssertEqual(top("nihao").first, "你好")
        XCTAssertEqual(top("zhongguo").first, "中国")
        XCTAssertTrue(top("xian").contains("先"))
        XCTAssertTrue(top("xi'an").contains("西安"))
        XCTAssertEqual(top("xiexie").first, "谢谢")
    }

    func testSentence() {
        XCTAssertEqual(top("woshizhongguoren").first, "我是中国人")
        XCTAssertEqual(top("wolaizi yuenan".replacingOccurrences(of: " ", with: "")).first, "我来自越南")
    }

    func testIncompleteLastSyllable() {
        XCTAssertTrue(top("nih", 10).contains("你好"))
    }

    func testAbbreviation() {
        XCTAssertTrue(top("nh", 10).contains("你好"))
    }

    func testPartialSelection() {
        let e = PinyinEngine(dictionary: Self.dict)
        for c in "nihaoma" { e.type(c) }
        // chọn một ứng viên chỉ dùng "nihao" → còn "ma"
        let idx = e.candidates.firstIndex { $0.text == "你好" }!
        XCTAssertNil(e.select(idx))
        XCTAssertEqual(e.input, "ma")
        XCTAssertEqual(e.preedit, "你好ma")
        let ma = e.candidates.firstIndex { $0.text == "吗" }!
        XCTAssertEqual(e.select(ma), "你好吗")
        XCTAssertFalse(e.isComposing)
    }

    func testBackspaceUndoesSelection() {
        let e = PinyinEngine(dictionary: Self.dict)
        for c in "nihaoma" { e.type(c) }
        _ = e.select(e.candidates.firstIndex { $0.text == "你好" }!)
        e.backspace(); e.backspace()   // xoá "ma"
        XCTAssertEqual(e.input, "")
        e.backspace()                  // bỏ chọn 你好 → trả lại "nihao"
        XCTAssertEqual(e.input, "nihao")
        XCTAssertEqual(e.commitRaw(), "nihao")
    }

    func testDisplaySegmentation() {
        let e = PinyinEngine(dictionary: Self.dict)
        for c in "zhongguoren" { e.type(c) }
        XCTAssertEqual(e.preedit, "zhong guo ren")
    }

    func testLoadAndLookupSpeed() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/pinyin.tsv")
        let t0 = Date()
        let d = try! PinyinDictionary(contentsOf: url)
        let load = Date().timeIntervalSince(t0)
        let e = PinyinEngine(dictionary: d)
        let t1 = Date()
        for c in "womenyiqiquxuexiaoba" { e.type(c) }
        let typing = Date().timeIntervalSince(t1)
        print("dict load \(load)s, 20 keystrokes \(typing)s, top: \(e.candidates.prefix(3).map(\.text))")
    }
}
