import XCTest
@testable import ViPiCore

final class TelexEngineTests: XCTestCase {
    /// Gõ từng phím, áp TextEdit lên một "ô văn bản" giả, trả về nội dung cuối.
    private func typeWord(_ keys: String, modern: Bool = false) -> String {
        let e = TelexEngine()
        e.modernToneStyle = modern
        var text: [Character] = []
        for k in keys {
            let edit = e.type(k)
            text.removeLast(edit.backspaces)
            text.append(contentsOf: edit.insert)
        }
        XCTAssertEqual(String(text), e.output)
        return String(text)
    }

    private func check(_ cases: [(String, String)], modern: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        for (keys, want) in cases {
            XCTAssertEqual(typeWord(keys, modern: modern), want, "keys: \(keys)", file: file, line: line)
        }
    }

    func testBasicMarks() {
        check([
            ("aa", "â"), ("aw", "ă"), ("ee", "ê"), ("oo", "ô"), ("ow", "ơ"), ("uw", "ư"), ("dd", "đ"),
            ("w", "ư"), ("tw", "tư"), ("nhw", "như"),
        ])
    }

    func testTones() {
        check([
            ("as", "á"), ("af", "à"), ("ar", "ả"), ("ax", "ã"), ("aj", "ạ"),
            ("viet", "viet"), ("vieejt", "việt"), ("vieetj", "việt"), ("tieengs", "tiếng"),
            ("nguwowif", "người"), ("nguoiwf", "người"), ("dduwowcj", "được"), ("dduowcj", "được"),
            ("hoaf", "hòa"), ("hoangf", "hoàng"), ("toans", "toán"), ("quas", "quá"), ("gif", "gì"),
            ("giaf", "già"), ("khuyeens", "khuyến"), ("cuar", "của"), ("muaw", "mưa"), ("mwa", "mưa"),
            ("ngoaif", "ngoài"), ("khuyur", "khuỷu"), ("cuwuf", "cừu"), ("gwir", "gửi"),
            ("xoawns", "xoắn"), ("quawn", "quăn"), ("thuyr", "thủy"), ("hoex", "hõe"),
        ])
    }

    func testModernToneStyle() {
        check([("hoaf", "hoà"), ("khoer", "khoẻ"), ("thuys", "thuý"), ("hoangf", "hoàng")], modern: true)
    }

    func testFreeOrderAndToneChange() {
        check([
            ("tosan", "toán"), ("vieejt", "việt"), ("vietej", "việt"), ("asf", "à"), ("asz", "a"),
            ("dongd", "đong"), ("duongwf", "dường"),
        ])
    }

    func testUndo() {
        check([
            ("aaa", "aa"), ("aww", "aw"), ("ass", "as"), ("dddd", "ddd"), ("ww", "w"), ("www", "ww"),
            ("bosss", "boss"), ("boss", "bos"), ("uww", "uw"),
        ])
    }

    func testUppercase() {
        check([("Vieejt", "Việt"), ("VIEEJT", "VIỆT"), ("DDaf", "Đà"), ("W", "Ư"), ("NGUWOWIF", "NGƯỜI")])
    }

    func testInvalidWordsStayRaw() {
        check([
            ("class", "class"), ("text", "text"), ("street", "street"), ("hello", "hello"),
            ("took", "took"), ("chrome", "chrome"), ("window", "window"), ("google", "google"),
        ])
    }

    func testBackspaceRebuildsState() {
        let e = TelexEngine()
        for k in "vieejt" { _ = e.type(k) }
        XCTAssertEqual(e.output, "việt")
        e.backspace()                                   // "việ"
        XCTAssertEqual(e.output, "việ")
        let edit = e.type("n")                          // "viện"
        XCTAssertEqual(e.output, "viện")
        XCTAssertEqual(edit, TextEdit(backspaces: 0, insert: "n"))
        e.backspace(); e.backspace()                    // "vi"
        XCTAssertEqual(e.output, "vi")
        _ = e.type("s")
        XCTAssertEqual(e.output, "ví")
    }

    func testRoundTripTelexKeys() {
        for w in ["người", "được", "việt", "Nguyễn", "khuỷu", "hòa", "quốc", "giữa", "đường", "ĐẠI", "gì", "xoắn"] {
            XCTAssertEqual(TelexEngine.render(TelexEngine.telexKeys(for: w), modern: false), w, w)
        }
    }

    func testEditIsMinimal() {
        let e = TelexEngine()
        XCTAssertEqual(e.type("v"), TextEdit(backspaces: 0, insert: "v"))
        XCTAssertEqual(e.type("i"), TextEdit(backspaces: 0, insert: "i"))
        XCTAssertEqual(e.type("e"), TextEdit(backspaces: 0, insert: "e"))
        XCTAssertEqual(e.type("e"), TextEdit(backspaces: 1, insert: "ê"))
        XCTAssertEqual(e.type("j"), TextEdit(backspaces: 1, insert: "ệ"))
        XCTAssertEqual(e.type("t"), TextEdit(backspaces: 0, insert: "t"))
    }
}

final class TelexRoundTripTests: XCTestCase {
    func testParagraphRoundTrip() {
        let text = """
        Tiếng Việt là ngôn ngữ của người Việt và là ngôn ngữ chính thức tại Việt Nam. Đây là tiếng mẹ đẻ \
        của khoảng tám mươi lăm phần trăm dân cư Việt Nam cùng với hơn bốn triệu người Việt hải ngoại. \
        Chữ Quốc ngữ dùng bảng chữ cái Latinh, thêm các dấu thanh và dấu phụ để thể hiện nguyên âm. \
        Khuya rồi, gió thổi nhè nhẹ qua khung cửa sổ, ánh trăng soi xuống dòng sông quê hương thuở ấy. \
        Huỳnh Thúc Kháng, Nguyễn Trãi, Hồ Xuân Hương, Trịnh Công Sơn, khuỷu tay, ngoẹo đầu, hoẵng, quyết định, \
        giữa đường, gì cũng được, uống rượu, cưỡi ngựa, chuyện trò, nghiêng ngả, thuyền buồm, khuyên bảo.
        """
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for w in words {
            XCTAssertEqual(TelexEngine.render(TelexEngine.telexKeys(for: w), modern: false), w, w)
        }
    }
}
