import CoreGraphics
import Foundation

// Đáp án mẫu của bộ gợi ý từ Swift (SuggestLM, SuggestNN, TapModel, Suggester, KeepWords) cho lõi Rust so khớp
// (core/tests/suggest.rs). In ra từng lời gọi theo đúng thứ tự cùng kết quả của nó; bản Rust gọi lại y như thế (mạng
// giữ trạng thái giữa các lần gọi, nên thứ tự là một phần của đáp án). Dựng và chạy bằng scripts/make-suggest-golden.sh
// trên Mac (cần 4 file mô hình và Resources/keep-words*.txt cạnh file chạy).
//
// Dòng: tên lệnh, các đối số, "=", các kết quả; cách nhau bằng tab, \ tab và xuống dòng trong chữ viết là \\ \t \n.

var out = ""
func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\t", with: "\\t").replacingOccurrences(of: "\n", with: "\\n")
}
func emit(_ fields: [String], _ results: [String]) { out += (fields.map(esc) + ["="] + results.map(esc)).joined(separator: "\t") + "\n" }
func num(_ d: Double) -> String { "\(d)" }
func opt(_ i: Int?) -> String { i.map { String($0) } ?? "-" }

SuggestLM.warmUpNow()
let langs: [(name: String, lm: SuggestLM)] = [("en", SuggestLM.shared), ("vi", SuggestLM.vietnamese)]
precondition(!SuggestLM.shared.isEmpty && !SuggestLM.vietnamese.isEmpty, "no model files next to the binary")

// MARK: bàn phím 402 pt (iPhone dọc): phím chữ i của một hàng có tâm x = 3,7 + 39,46·(i + 0,5) (hàng 2 lùi nửa phím,
// hàng 3 một phím rưỡi), ô vẽ rộng 33,46, cao 43, các hàng cách 54 (tâm y 615, 669, 723), phím cách 102,4…299,7 ở hàng
// dưới (tâm y 777).
let unit = 39.46, side = 3.7, drawnW = 33.46, drawnH = 43.0
let rowY = [615.0, 669.0, 723.0, 777.0]
var tapKeys: [(index: Int, kind: TapModel.Kind, frame: CGRect)] = []
var rects: [KeyRect] = []
var centre: [Character: CGPoint] = [:]
var index = 0
func addKey(_ kind: TapModel.Kind, _ frame: CGRect, _ row: Int, _ name: String) {
    tapKeys.append((index, kind, frame))
    emit(["key", String(index), name, String(row), num(Double(frame.minX)), num(Double(frame.minY)), num(Double(frame.width)), num(Double(frame.height))], [])
    index += 1
}
for (r, (letters, off)) in [("qwertyuiop", 0.0), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)].enumerated() {
    if r == 2 { addKey(.shift, CGRect(x: side + 3, y: rowY[2] - drawnH / 2, width: 1.5 * unit - 12, height: drawnH), 2, "shift") }
    for (i, ch) in letters.enumerated() {
        let cx = side + unit * (off + Double(i) + 0.5)
        let f = CGRect(x: cx - drawnW / 2, y: rowY[r] - drawnH / 2, width: drawnW, height: drawnH)
        let a = Int(ch.asciiValue!)
        addKey(.letter(a - 97), f, r, String(ch))
        rects.append(KeyRect(x: Float(f.minX), y: Float(f.minY), w: Float(f.width), h: Float(f.height), letter: CChar(a)))
        centre[ch] = CGPoint(x: cx, y: rowY[r])
    }
    if r == 2 { addKey(.backspace, CGRect(x: 402 - side - 3 - (1.5 * unit - 12), y: rowY[2] - drawnH / 2, width: 1.5 * unit - 12, height: drawnH), 2, "back") }
}
index += 1   // phím 123: không tham gia
addKey(.space, CGRect(x: 102.4, y: rowY[3] - drawnH / 2, width: 299.7 - 102.4, height: drawnH), 3, "space")

struct Rng { var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func gauss() -> Double { let u = max(unit(), 1e-12), v = unit(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
}
/// Phím chữ gần chỗ chạm nhất trên hàng của nó (như keyIndex của bàn phím, chỉ phím chữ).
func keyAt(_ p: CGPoint) -> Character {
    let r = min(max(Int(((p.y - rowY[0]) / 54 + 0.5).rounded(.down)), 0), 2)
    var best: Character = "a", bd = Double.greatestFiniteMagnitude
    for (ch, c) in centre where abs(c.y - rowY[r]) < 1 {
        let d = abs(c.x - p.x)
        if d < bd || (d == bd && ch < best) { bd = d; best = ch }
    }
    return best
}

// MARK: các đầu vào

let enWords = ["the", "The", "I", "i", "think", "Think", "don't", "don’t", "dont", "YouTube", "youtube", "café", "cafe", "naïve",
               "rhonk", "th", "qz", "a", "zzzz", "x", "inter", "peop", "people", "co-op", "e-mail", "o'clock", "résumé", "İstanbul",
               "you're", "it's", "THINK", "ﬁne", "Ångström", "", "tie\u{301}ng", "😀"]
let viWords = ["người", "Người", "nguoi", "tiếng", "Việt", "việt", "kỳ", "mùa", "đi", "Đi", "anh", "em", "không", "khong", "được",
               "ươ", "tie\u{301}ng", "ok", "thì", "hôm", "nay", "ĐƯỢC", "the", "liềᴜ", "x", ""]
let longEN = "It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness, it was the epoch of belief and "
let longer = String(repeating: "we walked along the river and talked about nothing in particular while the sun went down ", count: 4) + "and then "
let enContexts = ["", "I ", "I want ", "I want to ", "Thank you so much for ", "the ", "The ", "Hello, ", "What do you think? ", "I said \"",
                  "(see ", "He's ", "don’t ", "We met at 3 ", "xyzzyq ", "I can't believe it's ", "New York ", "line one\nline ", "tab\there ",
                  "I love 👍🏽 ", "café au ", longEN, longer, "mid-sentence: ", "Mr. Smith ", "I’m ", "she said “", "[link] ",
                  "The quick brown fox jumps over the lazy ", "on the other ", "I want to th", "can you ", "HELLO ", "e\u{301}e\u{301} ",
                  "I want to ", "I want to go ", "I want to go home "]
let enPrefixes = ["th", "Th", "a", "I", "yo", "peop", "helpi", "spee", "teh", "qz", "don", "don'", "don’", "x", "inter", "Tha", "caf", "w",
                  "beli", "z", "TH", "naï"]
let longVI = "Hôm nay trời đẹp lắm, chúng tôi đi dạo quanh hồ rồi ghé vào một quán cà phê nhỏ bên đường để nghỉ chân và nói chuyện với nhau rất lâu "
let viContexts = ["", "tôi ", "Tôi muốn ", "cảm ơn ", "kỳ ", "mùa ", "Hôm nay trời ", "người ", "Việt Nam ", "đi ", "tie\u{301}ng ", "ok ",
                  "Xin chào, ", "Anh ơi! ", "em yêu ", longVI, "123 ", "Tôi đi học. ", "thế giới ", "con ", "“Tôi ", "tôi muốn "]
let viPrefixes = ["ng", "ngư", "người", "th", "thì", "kh", "đ", "Đi", "tr", "a", "nguoi", "tiế", "vi", "tie\u{301}"]
let telexKeys = ["th", "ng", "nguo", "nguow", "nguowf", "nguowfi", "nguwowi", "nguowif", "vieet", "vieetj", "vieejt", "tieesng", "tieengs",
                 "dd", "ddi", "ddif", "ddiff", "kh", "khoong", "qua", "quas", "a", "aa", "aw", "uw", "uow", "x", "s", "tr", "truwowng",
                 "truowngf", "gi", "gix", "nh", "nhaf", "z", "w", "Th", "TH", "kyf", "muaf"]

// MARK: 1. hàm tĩnh và tra từ

for w in viWords + ["ươn", "uwow", "Đường", "ngoằn", "khuya", "quốc"] {
    emit(["telex", w], SuggestLM.telexSpellings(w).map { "\(String(decoding: $0.0, as: UTF8.self))/\($0.1 == 0 ? "-" : String(UnicodeScalar($0.1)))/\($0.2)" })
}
for (name, lm) in langs {
    for w in enWords + viWords {
        emit(["id", name, w], [opt(lm.id(w))])
        emit(["starts", name, w], [lm.startsWord(w) ? "1" : "0"])
        emit(["count", name, w], [String(lm.count(w))])
    }
    for i in stride(from: 0, to: lm.wordCount, by: 997) { emit(["form", name, String(i)], [lm.form(i)]) }
    for t in (name == "en" ? enContexts : viContexts) + ["", "x", "the the", "I want to th", "Tôi muốn đi", "abc1 ", "”", "' "] {
        let c = lm.context(t)
        emit(["ctx", name, t], [opt(c.before), opt(c.last), opt(c.tri)])
    }
}

// MARK: 2. mô hình, theo một thứ tự cố định (mạng giữ trạng thái)

func letters(_ lm: SuggestLM, _ name: String, _ prefix: String, _ before: String) -> [Double]? {
    let o = lm.nextLetters(prefix, before: before)
    emit(["letters", name, prefix, before], o.map { $0.map(num) } ?? ["-"])
    return o
}
let pickPoints: [CGPoint] = [CGPoint(x: 278.42, y: 615), CGPoint(x: 281.42, y: 615), CGPoint(x: 276.52, y: 615), CGPoint(x: 283.32, y: 615),
                             CGPoint(x: 161.54, y: 616), CGPoint(x: 200.0, y: 668), CGPoint(x: 279.92, y: 748), CGPoint(x: 200.0, y: 748),
                             CGPoint(x: 260.0, y: 642), CGPoint(x: 63.0, y: 723), CGPoint(x: 341.0, y: 723), CGPoint(x: 141.81, y: 615),
                             CGPoint(x: 299.0, y: 760), CGPoint(x: 20.0, y: 700)]
func picks(_ name: String, _ odds: [Double]) {
    for p in pickPoints {
        emit(["pick", name, num(Double(p.x)), num(Double(p.y))], [opt(TapModel.pick(p, keys: tapKeys, odds: odds, name == "vi" ? TapModel.vietnamese : TapModel.english))])
    }
}
for (name, lm) in langs {
    let contexts = name == "en" ? enContexts : viContexts
    let prefixes = name == "en" ? enPrefixes : viPrefixes
    for (ci, before) in contexts.enumerated() {
        let nw = lm.nextWords(before: before, limit: 3)
        emit(["next", name, before, "3"], zip(nw, lm.probabilities(nw, before: before)).flatMap { [$0.0, num($0.1)] })
        let probe = name == "en" ? ["the", "to", "think", "I", "you", "qzx", "don't", "YouTube"] : ["người", "tôi", "đi", "không", "là", "qzx", "ok"]
        emit(["prob", name, before] + probe, lm.probabilities(probe, before: before).map(num))
        for (pi, prefix) in prefixes.enumerated() {
            let c = lm.completions(prefix, before: before, limit: 3)
            emit(["comp", name, prefix, before, "3"], zip(c, lm.probabilities(c, before: before)).flatMap { [$0.0, num($0.1)] })
            if let o = letters(lm, name, prefix, before), ci % 4 == 0, pi < 6 { picks(name, o) }
        }
        for (prefix, word) in [("spee", "see"), ("spee", "speed"), ("helpi", "help"), ("teh", "the"), ("teh", "Tehran"), ("peop", "pep"),
                               ("rhonk", "think"), ("thi", "this"), ("xq", "the"), ("ngu", "người"), ("tho", "thì"), ("th", "zzzzq")] {
            emit(["pf", name, prefix, word, before], [lm.prefersFinishing(prefix, over: word, before: before) ? "1" : "0"])
        }
        if name == "vi" || ci % 6 == 0 {
            for (ki, keys) in telexKeys.enumerated() {
                for toneNow in [0.03, 0.1] {
                    let o = lm.nextKeys(keys, before: before, toneNow: toneNow)
                    emit(["keys", name, keys, before, num(toneNow)], o.map { $0.map(num) } ?? ["-"])
                    if let o, toneNow == 0.03, ci % 5 == 0, ki % 7 == 0 { picks(name, o) }
                }
            }
        }
    }
}

// MARK: 3. đọc lại các lần chạm

func tapsLine(_ lm: SuggestLM, _ name: String, _ taps: [(x: Float, y: Float)], _ before: String) {
    let reads = lm.readTaps(taps, keys: rects, before: before)
    emit(["taps", name, before, taps.map { "\($0.x),\($0.y)" }.joined(separator: ";")],
         reads.flatMap { [$0.word, String($0.id), num($0.closeness), num($0.likelihood)] })
}
var rng = Rng(s: 20261118)
for (name, lm) in langs {
    let words = name == "en" ? ["think", "the", "hello", "people", "teh", "would", "about", "keyboard", "quick", "zz", "a", "rhonk"]
                             : ["anh", "em", "con", "toi", "nguoi", "khong", "nha", "di"]
    let befores = name == "en" ? ["", "I want to ", "Thank you for the "] : ["", "tôi "]
    for before in befores {
        for w in words {
            tapsLine(lm, name, w.map { (x: Float(centre[$0]!.x), y: Float(centre[$0]!.y)) }, before)
            for sigma in [4.0, 8.0, 12.0] {
                tapsLine(lm, name, w.map { ch in
                    let c = centre[ch]!
                    return (x: Float(c.x + rng.gauss() * sigma), y: Float(c.y + rng.gauss() * sigma))
                }, before)
            }
        }
    }
    // "rhonk" lệch về t và i (x 158, 323 ở hàng trên)
    tapsLine(lm, name, [(158, 615), (Float(centre["h"]!.x), 669), (323, 615), (Float(centre["n"]!.x), 723), (Float(centre["k"]!.x), 669)], "I want to ")
}

// MARK: 4. Suggester: các phiên gõ, từng lời gọi như KeyboardViewController

let s = Suggester()
let knownWords: Set<String> = ["ok", "lol", "ntn", "anh"]
s.knows = { knownWords.contains($0) }
var context = ""
func update(english: Bool = true, telex: String = "", capitalize: Bool? = nil) {
    let cap = capitalize ?? (context.isEmpty || context.hasSuffix(". "))
    let cells = s.update(context: context, english: english, telexKeys: telex, keys: rects, capitalize: cap)
    let odds = s.touchOdds()
    emit(["s.update", context, english ? "1" : "0", telex, cap ? "1" : "0"],
         cells.map { "\($0.text)/\($0.quoted ? "q" : "")\($0.highlighted ? "h" : "")\($0.next ? "n" : "")" } + ["|", s.correction() ?? "-", "|"]
         + (odds.map { [$0.vietnamese ? "vi" : "en"] + $0.odds.map(num) } ?? ["-"]))
}
/// Gõ `text` ở trạng thái Anh: mỗi chữ cái chạm ở `tap` (mặc định tâm phím), dấu cách và dấu câu nhận lần tự sửa.
func type(_ text: String, tap: ((Character) -> CGPoint)? = nil, sigma: Double = 0) {
    for ch in text {
        s.forgetCorrection()
        emit(["s.forget"], [])
        if " .,?!;:".contains(ch) {
            if !s.isCurrent(context) { update() }
            if let w = s.correction() {
                emit(["s.correction"], [w])
                let typed = s.shownWord
                context = String(context.dropLast(typed.count)) + w + String(ch)
                s.didCorrect(typed: typed, inserted: w + String(ch))
                emit(["s.did", typed, w + String(ch)], [])
            } else {
                context.append(ch)
                s.endWord()
                emit(["s.end"], [])
            }
        } else if ch.isASCII && ch.isLetter {
            var p = tap?(ch) ?? centre[Character(ch.lowercased())]!
            var typedCh = ch
            if sigma > 0 {
                p = CGPoint(x: p.x + rng.gauss() * sigma, y: p.y + rng.gauss() * sigma)
                p = CGPoint(x: Double(Float(p.x)), y: Double(Float(p.y)))
                let k = keyAt(p)
                typedCh = ch.isUppercase ? Character(k.uppercased()) : k
            }
            context.append(typedCh)
            s.letter(typedCh, at: p)
            emit(["s.letter", String(typedCh), num(Double(p.x)), num(Double(p.y))], [])
        } else {
            context.append(ch)
            s.endWord()
            emit(["s.end"], [])
        }
        update()
    }
}
func backspaceUndo() {
    if let u = s.undoCorrection(context: context) {
        emit(["s.undo", context], [String(u.delete), u.insert])
        context = String(context.dropLast(u.delete)) + u.insert
    } else {
        emit(["s.undo", context], ["-"])
        if !context.isEmpty { context.removeLast() }
        s.backspace()
        emit(["s.back"], [])
    }
    update()
}
func reset() { s.reset(); emit(["s.reset"], []); context = "" }

// A. câu gõ đúng tâm phím
type("I want to think about it. ")
// B. "rhonk" lệch về t và i: sửa thành think; Backspace trả lại, rồi không sửa nữa
reset()
type("I want to ")
let slipped: [Character: CGPoint] = ["r": CGPoint(x: 158, y: 615), "o": CGPoint(x: 323, y: 615)]
type("rhonk", tap: { slipped[$0] ?? centre[$0]! })
type(" ")
backspaceUndo()
backspaceUndo()
type(" ")
// C. chữ hoa, danh sách giữ nguyên, chữ dính số, tên file
reset()
for t in ["Teh ", "ntn ", "xog ", "abc1xyz ", "report.dcox ", "THINK ", "ThInk ", "peop", " ", "helo ", "oiii ", "(teh) ", "lol "] { type(t) }
// D. giữ nguyên từ trong ngoặc kép
reset()
type("I want to ")
type("rhonk", tap: { slipped[$0] ?? centre[$0]! })
s.keepShown()
emit(["s.keep"], [])
update()
type(" ")
// E. khe trên phím cách: từ đã trọn hay chưa
reset()
type("I want to thank")
for l in ["n", "s", "m", "N", "1", "nn"] { emit(["s.ends", l], [s.wordEnds(before: l) ? "1" : "0"]) }
backspaceUndo()
backspaceUndo()
for l in ["n", "s"] { emit(["s.ends", l], [s.wordEnds(before: l) ? "1" : "0"]) }
// F. tiếng Việt: chỉ xác suất phím và từ tiếp theo
reset()
for (c, telex) in [("kỳ th", "th"), ("mùa th", "th"), ("tôi ", ""), ("Tôi ", ""), ("tôi ng", "ng"), ("người", "nguwowif"), ("", ""),
                   ("Tôi đi học. ", ""), ("cảm ơn ", ""), ("kỳ thi", "thi"), ("xin chào", "chaof")] {
    context = c
    update(english: false, telex: telex)
    for l in ["n", "i"] { emit(["s.ends", l], [s.wordEnds(before: l) ? "1" : "0"]) }
}
// G. công tắc
reset()
for (sug, auto) in [(false, true), (true, false), (false, false), (true, true)] {
    s.suggestionsOn = sug; s.autoCorrectOn = auto
    emit(["s.opts", sug ? "1" : "0", auto ? "1" : "0"], [])
    type("I want to ")
    type("rhonk", tap: { slipped[$0] ?? centre[$0]! })
    type(" ")
    reset()
}
// H. gõ lệch ngẫu nhiên (8 pt) các câu tiếng Anh và chữ chat
let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
func lines(_ name: String) -> [String] { ((try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
for line in lines("sentences.txt") {
    reset()
    type(line + ". ", sigma: 8)
}
reset()
for w in lines("chat.txt").prefix(120) { type(w + " ", sigma: 6) }

let path = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "suggest.txt"
try! out.write(toFile: path, atomically: true, encoding: .utf8)
print("golden suggest: \(out.split(separator: "\n").count) lines → \(path)")
