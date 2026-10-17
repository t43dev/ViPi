/// Gõ tắt: gõ xong từ khoá rồi Space/dấu câu thì từ khoá được thay bằng cụm đầy đủ ("vn" → "Việt Nam").
/// Không phân biệt hoa/thường; gõ từ khoá viết hoa chữ đầu / viết hoa toàn bộ thì cụm thay cũng vậy.
public struct MacroTable {
    private var exact: [String: String] = [:]
    private var folded: [String: String] = [:]

    public init(_ pairs: [(key: String, text: String)]) {
        for (key, text) in pairs where !key.isEmpty && !text.isEmpty {
            exact[key] = text
            folded[key.lowercased()] = folded[key.lowercased()] ?? text
        }
    }

    public var isEmpty: Bool { exact.isEmpty }

    /// Cụm thay thế cho từ vừa gõ, hoặc nil.
    public func expansion(for word: String) -> String? {
        if let text = exact[word] { return text }
        guard let text = folded[word.lowercased()] else { return nil }
        let letters = word.filter(\.isLetter)
        if letters.count > 1, letters.allSatisfy(\.isUppercase) { return text.uppercased() }
        if let first = word.first, first.isUppercase { return text.prefix(1).uppercased() + text.dropFirst() }
        return text
    }
}

extension TelexEngine {
    /// Kết thúc từ bằng gõ tắt: khớp chữ đang hiện, phím thô, hoặc chữ dựng không kiểm tra chính tả
    /// (để "ddc" khớp từ khoá "đc"). Có thì trả về sửa đổi thay cả từ và reset.
    public func expandMacro(_ macros: MacroTable) -> TextEdit? {
        guard !isEmpty else { return nil }
        let raw = String(keys)
        let candidates = [output, raw, Self.render(keys, modern: modernToneStyle, spellCheck: false)]
        guard let text = candidates.lazy.compactMap(macros.expansion(for:)).first else { return nil }
        let edit = TextEdit(backspaces: output.count, insert: text)
        reset()
        return edit
    }
}
