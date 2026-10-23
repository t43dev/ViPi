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

    // MARK: - 0.2.2: học từ, âm mờ, phồn thể

    static let s2t: ChineseConverter = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/s2t.tsv")
        return try! ChineseConverter(contentsOf: url)
    }()

    private func engine(fuzzy: Set<String> = [], traditional: Bool = false,
                        userDict: PinyinUserDictionary? = nil) -> PinyinEngine {
        let e = PinyinEngine(dictionary: Self.dict)
        e.fuzzyRules = fuzzy
        e.converter = traditional ? Self.s2t : nil
        e.userDictionary = userDict
        return e
    }

    private func typed(_ e: PinyinEngine, _ input: String) -> [String] {
        e.reset()
        for c in input { e.type(c) }
        return e.candidates.map(\.text)
    }

    func testLearnedWordMovesToFront() {
        let ud = PinyinUserDictionary(fileURL: nil)
        let e = engine(userDict: ud)
        let before = typed(e, "nihao")
        XCTAssertEqual(before.first, "你好")
        let other = before.firstIndex { $0 != "你好" && $0.count == 2 }!
        let picked = before[other]
        XCTAssertEqual(e.select(other), picked)
        let after = typed(e, "nihao")
        XCTAssertEqual(after.first, picked)
        XCTAssertEqual(after.filter { $0 == picked }.count, 1, "không trùng ứng viên")
        XCTAssertEqual(ud.words(for: "nihao"), [picked])
    }

    func testLearnedPhraseFromTwoSelections() {
        let ud = PinyinUserDictionary(fileURL: nil)
        let e = engine(userDict: ud)
        XCTAssertFalse(typed(e, "longxiao").contains("笼笑"), "chưa có trong từ điển")
        let long = e.candidates.firstIndex { $0.text == "笼" }!
        XCTAssertNil(e.select(long))
        let xiao = e.candidates.firstIndex { $0.text == "笑" }!
        XCTAssertEqual(e.select(xiao), "笼笑")
        XCTAssertEqual(typed(e, "longxiao").first, "笼笑")
        XCTAssertEqual(ud.words(for: "longxiao"), ["笼笑"])
    }

    func testLearnedCandidateLengthCountsApostrophe() {
        let ud = PinyinUserDictionary(fileURL: nil)
        ud.record("xian", "西安")
        let e = engine(userDict: ud)
        _ = typed(e, "xi'an")
        XCTAssertEqual(e.candidates.first, PinyinCandidate(text: "西安", length: 5))
        XCTAssertEqual(e.select(0), "西安")
        XCTAssertFalse(e.isComposing)
    }

    func testUserDictionaryPersistsAndClears() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vipi-test-\(UUID().uuidString)/learned.json")
        let a = PinyinUserDictionary(fileURL: url)
        a.record("nihao", "泥嚎")
        a.record("nihao", "泥嚎")
        a.record("nihao", "你好")
        // ghi ở hàng đợi nền: đợi một chút
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let b = PinyinUserDictionary(fileURL: url)
        XCTAssertEqual(b.words(for: "nihao"), ["泥嚎", "你好"])
        b.clear()
        XCTAssertEqual(b.count, 0)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testFuzzyInitial() {
        XCTAssertFalse(typed(engine(), "zongguo").prefix(5).contains("中国"))
        let e = engine(fuzzy: ["z=zh"])
        XCTAssertTrue(typed(e, "zongguo").prefix(5).contains("中国"))
        XCTAssertEqual(typed(e, "zhongguo").first, "中国", "âm đúng vẫn thắng")
        XCTAssertEqual(e.preedit, "zhong guo")
        _ = typed(e, "zongguo")
        XCTAssertEqual(e.preedit, "zong guo")
    }

    func testFuzzyFinal() {
        XCTAssertFalse(typed(engine(), "xingqin").prefix(5).contains("心情"))
        let e = engine(fuzzy: ["in=ing"])
        XCTAssertTrue(typed(e, "xingqin").prefix(5).contains("心情"))
        XCTAssertTrue(typed(engine(fuzzy: ["an=ang"]), "zhuan").prefix(10).contains("装"))
    }

    func testFuzzyAliases() {
        let a = FuzzyRule.aliases(rules: ["z=zh", "in=ing"], syllables: ["zhi", "zi", "xin", "xing", "ma"])
        XCTAssertEqual(a["zi"], ["zhi"])
        XCTAssertEqual(a["zhi"], ["zi"])
        XCTAssertEqual(Set(a["xin"]!), ["xing"])
        XCTAssertNil(a["ma"])
    }

    func testTraditionalOutput() {
        XCTAssertEqual(Self.s2t.convert("头发"), "頭髮")
        XCTAssertEqual(Self.s2t.convert("后天"), "後天")
        XCTAssertEqual(Self.s2t.convert("皇后"), "皇后")
        XCTAssertEqual(Self.s2t.convert("发"), "發")
        XCTAssertEqual(Self.s2t.convert("hello 中国"), "hello 中國")
        let e = engine(traditional: true)
        XCTAssertEqual(typed(e, "zhongguo").first, "中國")
        XCTAssertEqual(e.select(0), "中國")
        _ = typed(e, "nihaoma")
        _ = e.select(e.candidates.firstIndex { $0.text == "你好" }!)
        XCTAssertEqual(e.preedit, "你好ma")
        XCTAssertEqual(e.commitRaw(), "你好ma")
    }

    func testTraditionalLearnsSimplified() {
        let ud = PinyinUserDictionary(fileURL: nil)
        let e = engine(traditional: true, userDict: ud)
        _ = typed(e, "zhongguo")
        _ = e.select(0)
        XCTAssertEqual(ud.words(for: "zhongguo"), ["中国"])
        e.converter = nil
        XCTAssertEqual(typed(e, "zhongguo").first, "中国")
    }

    // MARK: - 0.3.0: bigram

    static let bigram: BigramModel = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/bigram.bin")
        return try! BigramModel(contentsOf: url)
    }()

    func testBigramModel() {
        XCTAssertEqual(BigramModel.fnv1a("a"), 0xaf63dc4c8601ec8c)          // vector chuẩn FNV-1a 64, khớp make-bigram.py
        XCTAssertGreaterThan(Self.bigram.pairCount, 500_000)
        XCTAssertThrowsError(try BigramModel(data: Data("nope".utf8)))
        let p = 1e-6
        XCTAssertGreaterThan(Self.bigram.logProb("我", "是", unigram: p), Self.bigram.logProb("我", "时", unigram: p))
        // từ chưa có trong corpus đứng trước: chỉ unigram, có phạt (1-λ)
        XCTAssertEqual(Self.bigram.logProb("㑇", "是", unigram: p), log(0.3 * p), accuracy: 1e-9)
    }

    func testBigramPicksWordByContext() {
        let e = PinyinEngine(dictionary: Self.dict)
        e.bigram = Self.bigram
        func first(_ s: String) -> String? { e.reset(); for c in s { e.type(c) }; return e.candidates.first?.text }
        XCTAssertEqual(first("wozaixuexizhongwen"), "我在学习中文")      // unigram: 我再学习中文
        XCTAssertEqual(first("qingnizaishuoyibian"), "请你再说一遍")    // unigram: 请你再说一边
        XCTAssertEqual(first("tadezhongwenshuodehenhao"), "他的中文说得很好")
        XCTAssertEqual(first("woshizhongguoren"), "我是中国人")
        XCTAssertEqual(first("jintiantianqihenhao"), "今天天气很好")
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
