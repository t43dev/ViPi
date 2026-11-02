import Foundation

/// Chuyển giản thể → phồn thể bằng bảng OpenCC (s2t.bin dựng từ s2t.tsv: `giản<TAB>phồn`, cụm từ trước, từng chữ sau).
/// Khớp dài nhất trước, nên 头发 → 頭髮 còn 发 một mình → 發.
public final class ChineseConverter {
    private let table: SortedTable

    public init(contentsOf url: URL) throws {
        table = try SortedTable(contentsOf: url)
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
                guard table.hasKey(withPrefix: key) else { break }
                if let v = table.value(for: key) { best = (j - i + 1, String(decoding: v, as: UTF8.self)) }
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
