import Foundation

/// Chuyển giản thể → phồn thể bằng bảng OpenCC (s2t.tsv: `giản<TAB>phồn`, cụm từ trước, từng chữ sau).
/// Khớp dài nhất trước, nên 头发 → 頭髮 còn 发 một mình → 發.
public final class ChineseConverter {
    private var table: [String: String] = [:]
    private var prefixes: Set<String> = []   // mọi tiền tố của khoá, để dừng sớm khi dò

    public convenience init(contentsOf url: URL) throws {
        self.init(tsv: try String(contentsOf: url, encoding: .utf8))
    }

    public init(tsv: String) {
        for line in tsv.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2 else { continue }
            let key = String(cols[0])
            table[key] = String(cols[1])
            var p = ""
            for c in key { p.append(c); prefixes.insert(p) }
        }
    }

    public func convert(_ text: String) -> String {
        let s = Array(text)
        var out = ""
        var i = 0
        while i < s.count {
            var best: (len: Int, value: String)?
            var key = ""
            var j = i
            while j < s.count {
                key.append(s[j])
                guard prefixes.contains(key) else { break }
                if let v = table[key] { best = (j - i + 1, v) }
                j += 1
            }
            if let best {
                out += best.value
                i += best.len
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return out
    }
}
