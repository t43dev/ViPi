// Từ Vikey (github.com/tonyminibot/Vikey, GPL-3.0), commit 5f2bfb0, iOS/Keyboard/SuggestLM.swift. Giữ nguyên để dễ so khi Vikey
// đổi; khác bản gốc: kiểu toạ độ phím (KeyRect thay VKKeyRect của bộ máy C++), tên hàng đợi.
import Foundation

/// The English words for the suggestion bar: ways to finish the word being typed, and next words, ranked by the
/// words before the cursor. Katz back-off over word triples, pairs and single words counted in FineWeb and Reddit
/// (Tools/suggest: pack_lm.py builds SuggestEN.bin, README.md has the benchmark against the system keyboard).
/// Memory-mapped: opening the keyboard reads nothing, a lookup touches a few pages.
final class SuggestLM {
    static let shared = SuggestLM(name: "SuggestEN", network: "SuggestNN", networkShare: 0.5)
    /// The same for Vietnamese (syllables; SuggestVI.bin and its network SuggestVINN.bin).
    static let vietnamese = SuggestLM(name: "SuggestVI", network: "SuggestVINN", networkShare: 0.5)   // 0.25-0.75 all within noise
    private let networkName: String
    private let bundle: Bundle   // where the files are: the network comes from the same one
    private static let discount = 0.75
    /// The share of a word's probability that comes from the next-word network (SuggestNN), which reads further
    /// back than two words; the rest is the counts'. Tuned on the benchmarks' dev sets.
    private let networkShare: Double
    private(set) lazy var nn: SuggestNN? = { let n = SuggestNN(name: networkName, words: self, bundle: bundle); return n.isEmpty ? nil : n }()
    private lazy var wordOfNetworkId: [Int] = {   // the network's ids back to word ids
        guard let nn else { return [] }
        var m = [Int](repeating: -1, count: nn.V)
        for w in 0..<wordCount { let k = nn.networkId(w); if k > 0 { m[k] = w } }
        return m
    }()

    private var data: NSData?
    private var base: UnsafeRawPointer?
    private(set) var wordCount: Int
    private var triCount = 0, total = 1.0
    private var keyOffs = 0, blob = 0, uni = 0, biStart = 0, biTotal = 0, biBeta = 0, biIds = 0, biCounts = 0
    private var triKeys = 0, triStart = 0, triTotal = 0, triBeta = 0, triIds = 0, triCounts = 0
    private var top = 0   // the 64 most common words: next-word candidates in any context

    init(name: String, network: String, networkShare: Double, bundle: Bundle = .main) {
        networkName = network; self.networkShare = networkShare; self.bundle = bundle
        let url = bundle.url(forResource: name, withExtension: "bin") ?? Bundle(for: SuggestLM.self).url(forResource: name, withExtension: "bin")
        let d = url.flatMap { try? NSData(contentsOf: $0, options: .alwaysMapped) }
        guard let d, d.length > 32, String(decoding: Data(bytes: d.bytes, count: 8), as: UTF8.self) == "VKLM0002" else {
            data = nil; base = nil; wordCount = 0; return
        }
        data = d; base = d.bytes
        let h = { (i: Int) in Int(d.bytes.load(fromByteOffset: 8 + 4 * i, as: UInt32.self)) }
        let n = h(0), nTri = h(1), nBi = h(2), nTriE = h(3), blobBytes = h(4)
        wordCount = n; triCount = nTri; total = Double(h(5))
        let nCtx = n + 2
        func align(_ x: Int) -> Int { (x + 3) & ~3 }
        var o = 8 + 24
        keyOffs = o; o += 4 * (n + 1)
        blob = o; o = align(o + blobBytes)
        uni = o; o += 4 * n
        biStart = o; o += 4 * (nCtx + 1)
        biTotal = o; o += 4 * nCtx
        biBeta = o; o += 4 * nCtx
        biIds = o; o += 2 * nBi
        biCounts = o; o = align(o + 2 * nBi)
        triKeys = o; o += 4 * nTri
        triStart = o; o += 4 * (nTri + 1)
        triTotal = o; o += 4 * nTri
        triBeta = o; o += 4 * nTri
        triIds = o; o += 2 * nTriE
        triCounts = o; o = align(o + 2 * nTriE)
        top = o; o += 2 * 64
        if o != d.length { data = nil; base = nil; wordCount = 0 }   // not the layout this code reads
    }

    var isEmpty: Bool { wordCount == 0 }

    // MARK: opening the keyboard

    /// Whether a language's files (counts and network) are in memory, so using them can't stall a key. The keyboard
    /// doesn't touch them until then: reading ~70 MB while it opened made it slow to come up, and iOS sometimes gave
    /// up and showed its own keyboard instead (Tony, builds 57-59). Main thread only.
    private(set) static var readyEN = false, readyVI = false
    private static let warmQueue = DispatchQueue(label: "vipi.suggest.warm", qos: .utility)
    private static var warming = false
    private static var generation = 0          // a pass started before the keyboard last went away counts for nothing
    private static var waiting: [() -> Void] = []   // told each time a language becomes ready

    /// Pages the files in on a background queue (the keyboard's language first), then marks each language ready on
    /// the main thread and calls `done` (also when it joins a pass already under way). Cheap when they're still in
    /// memory from the last time. Main thread only.
    static func warmUp(vietnameseFirst: Bool, done: @escaping () -> Void) {
        guard !(readyEN && readyVI) else { return }
        waiting.append(done)
        guard !warming else { return }
        warming = true
        let pass = generation
        let sumsNeeded = Set([shared, vietnamese].filter { !$0.isEmpty && $0.cumulative == nil }.map { ObjectIdentifier($0) })   // read here, on main
        let groups = [(vietnamese: false, names: ["SuggestEN", "SuggestNN"]), (vietnamese: true, names: ["SuggestVI", "SuggestVINN"])]
        let order = vietnameseFirst ? groups.reversed() : groups
        warmQueue.async {
            for (n, g) in order.enumerated() {
                var sum = 0
                for name in g.names { sum &+= touchPages(name) }
                let lm = g.vietnamese ? vietnamese : shared
                let sums = sumsNeeded.contains(ObjectIdentifier(lm)) ? lm.runningSums() : nil   // reads only the mapped file
                let telex = g.vietnamese && sums != nil ? lm.buildTelex() : nil
                DispatchQueue.main.async {
                    pagesSeen &+= sum
                    if let sums, lm.cumulative == nil { lm.cumulative = sums }
                    if let telex, lm.telex == nil { lm.telex = telex }
                    guard pass == generation else { return }
                    if g.vietnamese { readyVI = true } else { readyEN = true }
                    let callers = waiting
                    if n == order.count - 1 { warming = false; waiting = [] }
                    callers.forEach { $0() }
                }
            }
        }
    }
    private static var pagesSeen = 0   // keeps the loads below

    /// One load per memory page of a model file, through a mapping of its own: the pages come into the OS's file
    /// cache, which the keyboard's own mappings share.
    private static func touchPages(_ name: String) -> Int {
        let url = Bundle.main.url(forResource: name, withExtension: "bin") ?? Bundle(for: SuggestLM.self).url(forResource: name, withExtension: "bin")
        guard let d = url.flatMap({ try? NSData(contentsOf: $0, options: .alwaysMapped) }) else { return 0 }
        let p = d.bytes.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        for i in stride(from: 0, to: d.length, by: 16384) { sum &+= Int(p[i]) }
        return sum
    }

    /// The keyboard went away: iOS may drop the pages before it's back, so the next opening pages them in again
    /// (a pass still under way no longer counts).
    static func coolDown() { readyEN = false; readyVI = false; generation += 1; warming = false; waiting = [] }

    /// Tests: use the files at once.
    static func warmUpNow() {
        readyEN = true; readyVI = true
        for lm in [shared, vietnamese] where !lm.isEmpty && lm.cumulative == nil { lm.cumulative = lm.runningSums() }
        if !vietnamese.isEmpty, vietnamese.telex == nil { vietnamese.telex = vietnamese.buildTelex() }
    }

    // MARK: the file

    private func u32(_ section: Int, _ i: Int) -> Int { Int(base!.load(fromByteOffset: section + 4 * i, as: UInt32.self)) }
    private func u16(_ section: Int, _ i: Int) -> Int { Int(base!.load(fromByteOffset: section + 2 * i, as: UInt16.self)) }
    /// A pair's or triple's count, kept as round(ln(count) * 2000).
    private func count(_ section: Int, _ i: Int) -> Double { exp(Double(u16(section, i)) / 2000) }
    private func f32(_ section: Int, _ i: Int) -> Double { Double(base!.load(fromByteOffset: section + 4 * i, as: Float32.self)) }

    /// How a word shows: "I", "YouTube", "don't".
    func form(_ id: Int) -> String {
        let s = u32(keyOffs, id), e = u32(keyOffs, id + 1)
        let all = UnsafeRawBufferPointer(start: base! + blob + s, count: e - s)
        if let tab = all.firstIndex(of: 9) { return String(decoding: all[(tab + 1)...], as: UTF8.self) }
        return String(decoding: all, as: UTF8.self)
    }

    /// A word's key against `k`, in byte order (<0, 0, >0). memcmp, not Sequence comparisons: generic code is slow
    /// in debug builds, where the timing tests run.
    private func compare(_ id: Int, _ k: [UInt8]) -> Int {
        let s = u32(keyOffs, id), e = u32(keyOffs, id + 1)
        let p = base! + blob + s
        let len = memchr(p, 9, e - s).map { UnsafeRawPointer($0) - p } ?? e - s
        let c = k.withUnsafeBytes { memcmp(p, $0.baseAddress!, min(len, k.count)) }
        return c != 0 ? Int(c) : len - k.count
    }

    /// The first id whose key is >= `k` (byte order).
    private func lowerBound(_ k: [UInt8]) -> Int {
        var lo = 0, hi = wordCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if compare(mid, k) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private static func bytes(_ s: String) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(s.utf8.count)
        for b in s.utf8 {   // plain ASCII (most English, every Telex key) without Foundation's work
            guard b < 0x80 else { return Array(s.lowercased().replacingOccurrences(of: "’", with: "'").precomposedStringWithCanonicalMapping.utf8) }
            out.append(b >= 65 && b <= 90 ? b + 32 : b)
        }
        return out
    }

    /// The ids of the words that start with `prefix` (a contiguous range: keys are byte-sorted).
    private func range(_ prefix: [UInt8]) -> Range<Int> { lowerBound(prefix)..<lowerBound(prefix + [0xFF]) }

    func id(_ word: String) -> Int? {
        guard !isEmpty else { return nil }
        let k = Self.bytes(word), i = lowerBound(k)
        return i < wordCount && compare(i, k) == 0 ? i : nil
    }

    /// Whether some word starts with `prefix` (the prefix itself counts).
    func startsWord(_ prefix: String) -> Bool { !isEmpty && !range(Self.bytes(prefix)).isEmpty }

    /// How often the word was seen (0 when it isn't a word here).
    func count(_ word: String) -> Int { id(word).map { u32(uni, $0) } ?? 0 }

    /// Whether the typed letters are a word on its way rather than a typo of `word` (a fix that isn't one of the
    /// ways to finish them): after `before`, the words they start are at least 2% as likely as the fix, about how
    /// often a word gets a typo ("spee" → speed after "high", not "see"; "helpi" → helping, not "help"; but
    /// "teh" → the, not Tehran), or the fix isn't English.
    func prefersFinishing(_ prefix: String, over word: String, before: String) -> Bool {
        guard !isEmpty else { return false }
        let k = Self.bytes(prefix), r = range(k)
        guard !r.isEmpty, !Self.bytes(word).starts(with: k) else { return false }
        guard let fix = id(word) else { return true }
        let ctx = context(before)
        var finishing = 0.0, pFix = 0.0
        scan(r, ctx) { _, p in finishing += p }
        scan(fix..<fix + 1, ctx) { _, p in pFix = p }
        return finishing >= 0.02 * pFix
    }

    // MARK: the model

    private func p1(_ w: Int) -> Double { Double(u32(uni, w)) / total }

    /// The first index of a run of ids (sorted) whose id is >= w.
    private func lower(_ ids: Int, _ run: Range<Int>, _ w: Int) -> Int {
        var lo = run.lowerBound, hi = run.upperBound
        while lo < hi {
            let mid = (lo + hi) / 2
            if u16(ids, mid) < w { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func triIndex(_ a: Int, _ b: Int) -> Int? {
        let k = a << 16 | b
        var lo = 0, hi = triCount
        while lo < hi {
            let mid = (lo + hi) / 2, x = u32(triKeys, mid)
            if x == k { return mid }
            if x < k { lo = mid + 1 } else { hi = mid }
        }
        return nil
    }

    /// P(w | the context), from the counts of (last, w) and (before, last, w) when they were kept (nil when not).
    private func p(_ w: Int, _ ctx: Context, pair: Double?, triple: Double?) -> Double {
        guard let b = ctx.last else { return p1(w) }
        let n = u32(biTotal, b)
        let p2 = n == 0 ? p1(w) : pair.map { ($0 - Self.discount) / Double(n) } ?? f32(biBeta, b) * p1(w)
        guard let t = ctx.tri else { return p2 }
        return triple.map { ($0 - Self.discount) / Double(u32(triTotal, t)) } ?? f32(triBeta, t) * p2
    }

    /// Every word id in `r` (a run of the vocabulary) with its P(w | context): one walk along the context's pairs and
    /// triples, which are sorted by id, so no word costs a search.
    private func scan(_ r: Range<Int>, _ ctx: Context, _ body: (Int, Double) -> Void) {
        let bi = ctx.last.map { u32(biStart, $0)..<u32(biStart, $0 + 1) } ?? 0..<0
        let tri = ctx.tri.map { u32(triStart, $0)..<u32(triStart, $0 + 1) } ?? 0..<0
        var i = lower(biIds, bi, r.lowerBound), j = lower(triIds, tri, r.lowerBound)
        for w in r {
            while i < bi.upperBound, u16(biIds, i) < w { i += 1 }
            while j < tri.upperBound, u16(triIds, j) < w { j += 1 }
            let pair = i < bi.upperBound && u16(biIds, i) == w ? count(biCounts, i) : nil
            let triple = j < tri.upperBound && u16(triIds, j) == w ? count(triCounts, j) : nil
            body(w, p(w, ctx, pair: pair, triple: triple))
        }
    }

    /// P(w) blended with the network's guess (nnp: its distribution after the same text).
    private func blend(_ p: Double, _ w: Int, _ nnp: UnsafePointer<Float>?) -> Double {
        guard let nnp, let nn else { return p }
        let k = nn.networkId(w)
        return (1 - networkShare) * p + networkShare * (k > 0 ? Double(nnp[k]) : 0)
    }

    // MARK: the context

    /// The two tokens before the cursor's word as ids: words, <s> after . ! ? or a new line, <,> after , ; :.
    struct Context {
        var before: Int?, last: Int?
        var tri: Int? = nil   // the triple table's row for (before, last), looked up once
    }

    private var lastContext: (text: String, ctx: Context)?   // a word's keystrokes all share the text before it

    func context(_ text: String) -> Context {
        guard !isEmpty else { return Context() }
        if let c = lastContext, c.text == text { return c.ctx }
        let c = readContext(text)
        lastContext = (text, c)
        return c
    }

    private func readContext(_ text: String) -> Context {
        let sentence = wordCount, comma = wordCount + 1
        let tail = text.suffix(120)
        var toks: [Int?] = tail.count == text.count ? [sentence] : []   // a cut tail starts mid-sentence
        var word = String.UnicodeScalarView(), first = tail.count != text.count   // the cut's first word may be partial: dropped
        func endWord() {
            if !word.isEmpty { if !first { toks.append(id(String(word))) }; word = String.UnicodeScalarView() }
            first = false
        }
        // by scalar, not Character: grapheme breaking costs more than the rest (a combining mark is a letter's part)
        for ch in tail.unicodeScalars {
            if ch.properties.isAlphabetic || ch.properties.generalCategory == .nonspacingMark
                || ((ch == "'" || ch == "’") && !word.isEmpty) { word.append(ch); continue }
            endWord()
            switch ch {
            case ".", "!", "?", "\n": toks = [sentence]
            case ",", ";", ":": toks = [comma]
            case " ": break
            default: if !("\"“(['‘".unicodeScalars.contains(ch) && toks == [sentence]) { toks = [nil] }   // a quote or bracket can open a sentence
            }
        }
        endWord()
        // an unknown word ends the context: nothing before it counts
        if let i = toks.lastIndex(where: { $0 == nil }) { toks = Array(toks[(i + 1)...]) }
        var c = Context(before: toks.count >= 2 ? toks[toks.count - 2] : nil, last: toks.last ?? nil)
        if let a = c.before, let b = c.last { c.tri = triIndex(a, b) }
        return c
    }

    // MARK: slips

    /// A word's letters from its taps, read back: every word whose letters each lie near their tap (as many letters as
    /// taps: slips onto a neighbour, not missed or extra keys), with log closeness (a 2D Gaussian per tap, spread in
    /// key widths and heights as the engine's TouchModel) and log P(word | before). Best first by their sum. Words
    /// with more than `maxSlips` letters off their nearest key aren't looked at.
    struct Reading { let word: String; let id: Int; let closeness: Double; let likelihood: Double; var score: Double { closeness + likelihood } }

    func readTaps(_ taps: [(x: Float, y: Float)], keys: [KeyRect], before: String, maxSlips: Int = 2, limit: Int = 4,
                  sigma: Float = 0.35, sigmaY: Float = 0.25) -> [Reading] {
        guard !isEmpty, !taps.isEmpty, taps.count < 24 else { return [] }
        // per tap: the letters close enough to have been meant (within ~3 spreads), closest first
        var near: [[(UInt8, Double)]] = []
        for t in taps {
            var c: [(UInt8, Double)] = []
            for k in keys {
                let dx = (t.x - (k.x + k.w / 2)) / (k.w * sigma), dy = (t.y - (k.y + k.h / 2)) / (k.h * sigmaY)
                let s = -0.5 * Double(dx * dx + dy * dy)
                if s > -4.5 { c.append((UInt8(bitPattern: k.letter), s)) }
            }
            c.sort { $0.1 > $1.1 }
            near.append(c)
        }
        var found: [(Int, Double)] = [], prefix: [UInt8] = []
        func walk(_ i: Int, _ closeness: Double, _ slips: Int) {
            if i == taps.count {
                let w = lowerBound(prefix)
                if w < wordCount, compare(w, prefix) == 0 { found.append((w, closeness)) }
                return
            }
            for (j, (letter, s)) in near[i].enumerated() {
                let sl = slips + (j == 0 ? 0 : 1)
                if sl > maxSlips { continue }
                prefix.append(letter)
                if lowerBound(prefix) < lowerBound(prefix + [0xFF]) { walk(i + 1, closeness + s, sl) }   // some word starts so
                prefix.removeLast()
            }
        }
        walk(0, 0, 0)
        guard !found.isEmpty else { return [] }
        let p = probabilities(found.map { form($0.0) }, before: before)
        return zip(found, p).map { Reading(word: form($0.0.0), id: $0.0.0, closeness: $0.0.1, likelihood: log(max($0.1, 1e-12))) }
            .sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    // MARK: the next letter

    /// The chance of each next letter after `prefix` (the word's letters so far) and `before` (the text before the
    /// word): the share of the words that go on with a…z (26 values), then the chance the word ends here (27th).
    /// Word counts only (the network isn't needed for one letter). nil when no word starts so. One walk along the
    /// context's pairs and triples in the prefix's run; the rest comes from running sums of the single-word counts.
    func nextLetters(_ prefix: String, before: String) -> [Double]? {
        guard !isEmpty else { return nil }
        let k = Self.bytes(prefix), r = range(k)
        guard !r.isEmpty else { return nil }
        guard let cum = cumulative else { return nil }
        let L = k.count
        // the byte after the prefix in a word of r: -1 when the word is the prefix itself; non-decreasing along r
        func next(_ w: Int) -> Int {
            let s = u32(keyOffs, w), e = u32(keyOffs, w + 1)
            guard L < e - s else { return -1 }
            let b = Int((base! + blob + s).load(fromByteOffset: L, as: UInt8.self))
            return b == 9 ? -1 : b
        }
        func bin(_ w: Int) -> Int { let b = next(w); return b < 0 ? 26 : b >= 97 && b <= 122 ? b - 97 : -1 }
        func first(_ from: Int, atLeast b: Int) -> Int {   // the first id in from..<r.upperBound whose next byte >= b
            var lo = from, hi = r.upperBound
            while lo < hi { let m = (lo + hi) / 2; if next(m) < b { lo = m + 1 } else { hi = m } }
            return lo
        }
        var runs = [Range<Int>](repeating: 0..<0, count: 27)   // each letter's run of ids
        var lo = r.lowerBound
        if lo < r.upperBound, next(lo) < 0 { runs[26] = lo..<lo + 1; lo += 1 }
        lo = first(lo, atLeast: 97)
        for c in 0..<26 where lo < r.upperBound {
            let end = first(lo, atLeast: 98 + c)
            runs[c] = lo..<end
            lo = end
        }
        func uni(_ run: Range<Int>) -> Double { Double(cum[run.upperBound] - cum[run.lowerBound]) }
        var mass = runs.map(uni)   // P(w) summed, before the context
        let ctx = context(before)
        if let bRow = ctx.last, u32(biTotal, bRow) > 0 {
            let n = Double(u32(biTotal, bRow)), beta = f32(biBeta, bRow)
            let bi = u32(biStart, bRow)..<u32(biStart, bRow + 1)
            // pairs: p2 = (c - D) / n where (last, w) was kept, beta * p1 elsewhere
            var p2 = mass.map { beta * $0 }
            var i = lower(biIds, bi, r.lowerBound)
            while i < bi.upperBound, u16(biIds, i) < r.upperBound {
                let w = u16(biIds, i), c = bin(w)
                if c >= 0 { p2[c] += (count(biCounts, i) - Self.discount) / n - beta * p1(w) }
                i += 1
            }
            mass = p2
            if let t = ctx.tri {
                let tn = Double(u32(triTotal, t)), tb = f32(triBeta, t)
                let tri = u32(triStart, t)..<u32(triStart, t + 1)
                mass = p2.map { tb * $0 }
                var j = lower(triIds, tri, r.lowerBound)
                while j < tri.upperBound, u16(triIds, j) < r.upperBound {
                    let w = u16(triIds, j), c = bin(w)
                    if c >= 0 {
                        let ip = lower(biIds, bi, w)
                        let pw = ip < bi.upperBound && u16(biIds, ip) == w ? (count(biCounts, ip) - Self.discount) / n : beta * p1(w)
                        mass[c] += (count(triCounts, j) - Self.discount) / tn - tb * pw
                    }
                    j += 1
                }
            }
        }
        let total = mass.reduce(0) { $0 + max($1, 0) }
        return total > 0 ? mass.map { max($0, 0) / total } : nil
    }

    // MARK: Vietnamese: the next Telex key

    /// The commonest Vietnamese words spelled in Telex, sorted by their keys: marks where they sit (aa aw ee oo ow uw
    /// dd), the tone (s f r x j) apart, since people type it at the end or in the middle. "ươ" also as "uow" (one w).
    /// Built by warmUp off the main thread, set on the main thread; nil until then.
    struct TelexIndex {
        var keys: [UInt8] = [], start: [Int32] = [0], word: [Int32] = [], tone: [UInt8] = [], share: [Float] = []
        var count: Int { word.count }
        func key(_ i: Int) -> ArraySlice<UInt8> { keys[Int(start[i])..<Int(start[i + 1])] }
    }
    private(set) var telex: TelexIndex?

    /// A word's Telex spellings (keys, tone key or 0, share of its count): "người" → nguwowi + f, nguowi + f.
    static func telexSpellings(_ word: String) -> [([UInt8], UInt8, Float)] {
        var base: [UInt8] = [], tone: UInt8 = 0
        for u in word.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            switch u.value {
            case 0x61...0x7A: base.append(UInt8(u.value))
            case 0x111: base += [100, 100]                                  // đ
            case 0x302: if let l = base.last { base.append(l) }             // â ê ô
            case 0x306, 0x31B: base.append(119)                             // ă, ơ ư: w
            case 0x301: tone = 115
            case 0x300: tone = 102
            case 0x309: tone = 114
            case 0x303: tone = 120
            case 0x323: tone = 106
            default: return []
            }
        }
        guard !base.isEmpty else { return [] }
        let uwow: [UInt8] = Array("uwow".utf8)
        if let i = (0...max(base.count - 4, 0)).first(where: { base.count >= $0 + 4 && Array(base[$0..<$0 + 4]) == uwow }) {
            var one = base; one.remove(at: i + 1)                           // uow
            return [(base, tone, 0.5), (one, tone, 0.5)]
        }
        return [(base, tone, 1)]
    }

    fileprivate func buildTelex(limit: Int = 25000) -> TelexIndex {
        let common = (0..<wordCount).sorted { u32(uni, $0) > u32(uni, $1) }.prefix(limit)
        var entries: [([UInt8], UInt8, Int32, Float)] = []
        for w in common { for (k, t, s) in Self.telexSpellings(form(w)) { entries.append((k, t, Int32(w), s)) } }
        entries.sort { $0.0.lexicographicallyPrecedes($1.0) }
        var t = TelexIndex()
        for e in entries { t.keys += e.0; t.start.append(Int32(t.keys.count)); t.word.append(e.2); t.tone.append(e.1); t.share.append(e.3) }
        return t
    }

    /// Words that follow the context, as P(w | context) - beta * P(w) (Katz: the rest is beta * P(w)), for the
    /// Vietnamese next key: one slot per word id (~240 KB once), filled for the context's pairs and triples and
    /// cleared again when the text before the word changes.
    private var extra: [Float] = [], extraSet: [Int] = [], extraText: String?, extraBeta = 1.0
    private func contextExtra(_ before: String) -> Double {
        if extraText == before { return extraBeta }
        if extra.isEmpty { extra = [Float](repeating: 0, count: wordCount) }
        for w in extraSet { extra[w] = 0 }
        extraSet.removeAll(keepingCapacity: true)
        extraText = before; extraBeta = 1
        let ctx = context(before)
        guard let bRow = ctx.last, u32(biTotal, bRow) > 0 else { return 1 }
        let n = Double(u32(biTotal, bRow)), bb = f32(biBeta, bRow)
        var tb = 1.0
        if let t = ctx.tri { tb = f32(triBeta, t) }
        extraBeta = tb * bb
        for i in u32(biStart, bRow)..<u32(biStart, bRow + 1) {
            let w = u16(biIds, i)
            extra[w] = Float(tb * ((count(biCounts, i) - Self.discount) / n - bb * p1(w))); extraSet.append(w)
        }
        if let t = ctx.tri {
            let tn = Double(u32(triTotal, t))
            for j in u32(triStart, t)..<u32(triStart, t + 1) {
                let w = u16(triIds, j)
                let p2 = bb * p1(w) + Double(extra[w]) / tb
                extra[w] += Float((count(triCounts, j) - Self.discount) / tn - tb * p2); extraSet.append(w)
            }
        }
        return extraBeta
    }

    /// The chance of each next key while a Vietnamese word is typed in Telex (`typed`: its keys so far) after
    /// `before`: 26 keys, then the word ending (27). A pending tone can come next too (`toneNow` of the time while
    /// letters remain). nil when no word in the index goes on from these keys.
    func nextKeys(_ typed: String, before: String, toneNow: Double = 0.1) -> [Double]? {
        guard let tx = telex, !typed.isEmpty else { return nil }
        var base: [UInt8] = [], typedTone: UInt8 = 0, vowel = false
        for b in typed.lowercased().utf8 {
            if vowel, b == 115 || b == 102 || b == 114 || b == 120 || b == 106 {   // s f r x j
                if typedTone == b { return nil }   // typed twice: the engine undoes the tone and stops reading Telex
                typedTone = b; continue
            }
            if b == 97 || b == 101 || b == 105 || b == 111 || b == 117 || b == 121 { vowel = true }
            base.append(b)
        }
        // the run of entries whose keys start with base
        func lower(_ k: [UInt8], _ upper: Bool) -> Int {
            var lo = 0, hi = tx.count
            while lo < hi {
                let m = (lo + hi) / 2, e = tx.key(m)
                let less = upper ? (e.starts(with: k) || e.lexicographicallyPrecedes(k)) : e.lexicographicallyPrecedes(k)
                if less { lo = m + 1 } else { hi = m }
            }
            return lo
        }
        let a = lower(base, false), b = lower(base, true)
        guard a < b else { return nil }
        let beta = contextExtra(before)
        var out = [Double](repeating: 0, count: 27)
        let L = base.count
        for i in a..<b {
            let w = Int(tx.word[i]), t = tx.tone[i]
            if typedTone != 0 && t != typedTone { continue }
            let p = (beta * p1(w) + Double(extra[w])) * Double(tx.share[i])
            guard p > 0 else { continue }
            let k = tx.key(i), pending = vowel && typedTone == 0 && t != 0   // a tone key acts only after a vowel
            if k.count > L {
                let c = Int(k[k.startIndex + L]) - 97
                guard (0..<26).contains(c) else { continue }
                out[c] += pending ? p * (1 - toneNow) : p
                if pending { out[Int(t) - 97] += p * toneNow }
            } else if pending {
                out[Int(t) - 97] += p
            } else {
                out[26] += p
            }
        }
        let total = out.reduce(0, +)
        return total > 0 ? out.map { $0 / total } : nil
    }

    /// Running sums of P(w) over the ids (~240 KB): any run's share in two reads. Built by warmUp off the main
    /// thread (reads only the mapped file), set on the main thread; nil until then.
    private(set) var cumulative: [Float]?
    fileprivate func runningSums() -> [Float] {
        var out = [Float](repeating: 0, count: wordCount + 1), s = 0.0
        for w in 0..<wordCount { s += p1(w); out[w + 1] = Float(s) }
        return out
    }

    // MARK: suggestions

    /// The best ways to finish `prefix` after `before` (the text before the word), most likely first, as they show
    /// ("I", "don't"). The prefix itself isn't one of them.
    func completions(_ prefix: String, before: String, limit: Int) -> [String] {
        guard !isEmpty, !prefix.isEmpty else { return [] }
        let k = Self.bytes(prefix), r = range(k)
        guard !r.isEmpty else { return [] }
        var best: [(Double, Int)] = []
        let nnp = nn?.next(after: before)
        scan(r, context(before)) { w, p in
            let s = blend(p, w, nnp)
            if best.count == limit, s <= best[limit - 1].0 { return }
            if compare(w, k) == 0 { return }
            let at = best.firstIndex { s > $0.0 } ?? best.count
            best.insert((s, w), at: at)
            if best.count > limit { best.removeLast() }
        }
        return best.map { form($0.1) }
    }

    /// P(word) after `before` for each word, as the bar ranks them (counts and network blended); 0 for a word it
    /// doesn't know.
    func probabilities(_ words: [String], before: String) -> [Double] {
        guard !isEmpty else { return words.map { _ in 0 } }
        let ctx = context(before), nnp = nn?.next(after: before)
        return words.map { word in
            guard let w = id(word) else { return 0 }
            var r = 0.0
            scan(w..<w + 1, ctx) { w, p in r = blend(p, w, nnp) }
            return r
        }
    }

    /// The likeliest next words after `before` (which ends with a space): the context's pairs (a triple kept for a
    /// word is always kept as a pair too), the most common words, and the network's favourites.
    func nextWords(before: String, limit: Int) -> [String] {
        guard !isEmpty else { return [] }
        let ctx = context(before), nnp = nn?.next(after: before)
        var best: [(Double, Int)] = []
        func consider(_ w: Int, _ s: Double) {
            if best.count == limit, s <= best[limit - 1].0 { return }
            if best.contains(where: { $0.1 == w }) { return }
            let at = best.firstIndex { s > $0.0 } ?? best.count
            best.insert((s, w), at: at)
            if best.count > limit { best.removeLast() }
        }
        if let b = ctx.last {
            let bi = u32(biStart, b)..<u32(biStart, b + 1)
            let tri = ctx.tri.map { u32(triStart, $0)..<u32(triStart, $0 + 1) } ?? 0..<0
            var j = tri.lowerBound
            for i in bi {
                let w = u16(biIds, i)
                while j < tri.upperBound, u16(triIds, j) < w { j += 1 }
                let triple = j < tri.upperBound && u16(triIds, j) == w ? count(triCounts, j) : nil
                consider(w, blend(p(w, ctx, pair: count(biCounts, i), triple: triple), w, nnp))
            }
        }
        var extra = (0..<64).map { u16(top, $0) }
        if let nnp, let nn {   // the network's 16 likeliest words
            var picks: [(Float, Int)] = []
            for k in 4..<nn.V where picks.count < 16 || nnp[k] > picks[15].0 {
                picks.append((nnp[k], k)); picks.sort { $0.0 > $1.0 }
                if picks.count > 16 { picks.removeLast() }
            }
            extra += picks.compactMap { wordOfNetworkId[$0.1] >= 0 ? wordOfNetworkId[$0.1] : nil }
        }
        for w in extra {
            scan(w..<w + 1, ctx) { w, p in consider(w, blend(p, w, nnp)) }
        }
        return best.map { form($0.1) }
    }
}
