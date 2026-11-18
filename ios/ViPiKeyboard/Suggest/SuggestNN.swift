// Từ Vikey (github.com/tonyminibot/Vikey, GPL-3.0), commit 5f2bfb0, iOS/Keyboard/SuggestNN.swift. Giữ nguyên để dễ so khi Vikey
// đổi; khác bản gốc: kiểu toạ độ phím (KeyRect thay VKKeyRect của bộ máy C++), tên hàng đợi.
import Accelerate
import Foundation

/// The next-word network (Tools/suggest/pack_nn.py, trained by vikey-data lm_en/train_nn.py): an LSTM over the words
/// before the cursor. SuggestLM blends its guess with the word counts, which see only two words back. The weights
/// are float32 in a memory-mapped file that vDSP reads in place (clean pages, not the keyboard's footprint). The state
/// is kept between calls, so a new word costs one LSTM step and one pass over the output layer.
final class SuggestNN {
    private unowned let words: SuggestLM   // whose words the network's ids map to

    private var data: NSData?
    private var base: UnsafeRawPointer?
    private(set) var V = 0, E = 0, H = 0
    private var nWords = 0
    private var nnOf = 0, emb = 0, wih = 0, whh = 0, bias = 0, projW = 0, projB = 0, outB = 0

    init(name: String, words: SuggestLM, bundle: Bundle = .main) {
        self.words = words
        let url = bundle.url(forResource: name, withExtension: "bin") ?? Bundle(for: SuggestNN.self).url(forResource: name, withExtension: "bin")
        guard let d = url.flatMap({ try? NSData(contentsOf: $0, options: .alwaysMapped) }), d.length > 24,
              String(decoding: Data(bytes: d.bytes, count: 8), as: UTF8.self) == "VKNN0001" else { return }
        let h = { (i: Int) in Int(d.bytes.load(fromByteOffset: 8 + 4 * i, as: UInt32.self)) }
        let v = h(0), e = h(1), hid = h(2), n = h(3)
        var o = 8 + 16
        let nnOf = o; o = (o + 2 * n + 3) & ~3
        let emb = o; o += 4 * v * e
        let wih = o; o += 4 * 4 * hid * e
        let whh = o; o += 4 * 4 * hid * hid
        let bias = o; o += 4 * 4 * hid
        let projW = o; o += 4 * e * hid
        let projB = o; o += 4 * e
        let outB = o; o += 4 * v
        guard o == d.length else { return }   // not the layout this code reads
        data = d; base = d.bytes; V = v; E = e; H = hid; nWords = n
        (self.nnOf, self.emb, self.wih, self.whh, self.bias, self.projW, self.projB, self.outB) = (nnOf, emb, wih, whh, bias, projW, projB, outB)
        hs = .allocate(capacity: hid); cs = .allocate(capacity: hid)
        gates = .allocate(capacity: 4 * hid); scratch = .allocate(capacity: 4 * hid)
        z = .allocate(capacity: e); probs = .allocate(capacity: v)
    }

    var isEmpty: Bool { V == 0 }

    /// The network's id for a SuggestLM word id (0: not one of its words).
    func networkId(_ word: Int) -> Int { word < nWords ? Int(base!.load(fromByteOffset: nnOf + 2 * word, as: UInt16.self)) : 0 }

    private func f32(_ section: Int) -> UnsafePointer<Float> { (base! + section).assumingMemoryBound(to: Float.self) }

    /// y = W·x + b, W row-major (rows × cols), all float32.
    private func affine(_ w: UnsafePointer<Float>, rows: Int, cols: Int, _ x: UnsafePointer<Float>, _ b: UnsafePointer<Float>, into y: UnsafeMutablePointer<Float>) {
        vDSP_mmul(w, 1, x, 1, y, 1, vDSP_Length(rows), 1, vDSP_Length(cols))
        vDSP_vadd(y, 1, b, 1, y, 1, vDSP_Length(rows))
    }

    // MARK: running it

    private static let window = 32   // tokens read when starting over
    // the state, and the text it has read (a singleton's buffers: never freed)
    private var hs: UnsafeMutablePointer<Float>!, cs: UnsafeMutablePointer<Float>!
    private var gates: UnsafeMutablePointer<Float>!, scratch: UnsafeMutablePointer<Float>!
    private var z: UnsafeMutablePointer<Float>!, probs: UnsafeMutablePointer<Float>!
    private var fedText: String?, lastToken = 1, probsReady = false

    /// One LSTM step: the state reads token t.
    private func step(_ t: Int) {
        let G = 4 * H
        affine(f32(wih), rows: G, cols: E, f32(emb) + t * E, f32(bias), into: gates)
        vDSP_mmul(f32(whh), 1, hs, 1, scratch, 1, vDSP_Length(G), 1, vDSP_Length(H))
        vDSP_vadd(gates, 1, scratch, 1, gates, 1, vDSP_Length(G))
        for j in 0..<H {
            let i = 1 / (1 + exp(-gates[j])), f = 1 / (1 + exp(-gates[H + j]))
            let c = tanh(gates[2 * H + j]), o = 1 / (1 + exp(-gates[3 * H + j]))
            cs[j] = f * cs[j] + i * c
            hs[j] = o * tanh(cs[j])
        }
        lastToken = t
    }

    /// The tokens of `text` as the network was trained on them (vikey-data lm_en/dump_tokens.py): words, 1 after
    /// . ! ? or a new line, 2 after , ; :, 3 for anything else that breaks a run of words; repeats of 1 and 3 merged,
    /// a quote or bracket opening a sentence skipped. `last` is the token before the text.
    private func tokens(_ text: Substring, after last: Int) -> [Int] {
        var out: [Int] = [], prev = last, word = ""
        func emit(_ t: Int) { if (t == 1 || t == 3) && prev == t { return }; out.append(t); prev = t }
        func endWord() {
            guard !word.isEmpty else { return }
            emit(words.id(word).map(networkId) ?? 0); word = ""
        }
        for ch in text {
            if ch.isLetter || ((ch == "'" || ch == "’") && !word.isEmpty) { word.append(ch); continue }
            endWord()
            switch ch {
            case ".", "!", "?", "\n": emit(1)
            case ",", ";", ":": emit(2)
            case " ": break
            default: if !("\"'()[]-–—*".contains(ch) && prev == 1) { emit(3) }
            }
        }
        endWord()
        return out
    }

    /// The probability of each of the network's words coming next after `before` (its words: networkId), or nil
    /// without the network. Text that goes on from the last call's costs one step per new token.
    func next(after before: String) -> UnsafePointer<Float>? {
        guard !isEmpty else { return nil }
        if let fed = fedText, fed == before, probsReady { return UnsafePointer(probs) }
        if let fed = fedText, !fed.isEmpty, before.hasPrefix(fed), fed.last == " " {
            for t in tokens(before.dropFirst(fed.count), after: lastToken) { step(t) }
        } else {
            for j in 0..<H { hs[j] = 0; cs[j] = 0 }
            let tail = before.suffix(300)
            var toks = tokens(tail, after: tail.count == before.count ? 1 : 3)
            if tail.count != before.count, !toks.isEmpty { toks.removeFirst() }   // the cut's first word may be partial
            lastToken = 1
            for t in [1] + toks.suffix(Self.window) { step(t) }
        }
        fedText = before
        // z = proj(h); p = softmax(emb · z + outB)
        affine(f32(projW), rows: E, cols: H, hs, f32(projB), into: z)
        affine(f32(emb), rows: V, cols: E, z, f32(outB), into: probs)
        var mx: Float = 0
        vDSP_maxv(probs, 1, &mx, vDSP_Length(V))
        var neg = -mx
        vDSP_vsadd(probs, 1, &neg, probs, 1, vDSP_Length(V))
        var n = Int32(V)
        vvexpf(probs, probs, &n)
        var sum: Float = 0
        vDSP_sve(probs, 1, &sum, vDSP_Length(V))
        var inv = 1 / sum
        vDSP_vsmul(probs, 1, &inv, probs, 1, vDSP_Length(V))
        probsReady = true
        return UnsafePointer(probs)
    }
}
