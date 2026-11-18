import Foundation

/// Những từ tự sửa lỗi gõ không bao giờ đụng tới: viết tắt, tiếng lóng, tên thương hiệu người ta gõ thật (ntn, cta,
/// xog…), theo phím đã gõ. Danh sách `keep-words.txt` là KeepWords.inc của Vikey (github.com/tonyminibot/Vikey,
/// GPL-3.0, D26), mỗi dòng một từ, sắp theo byte để tìm nhị phân ngay trên file (đọc bằng mmap).
final class KeepWords {
    static let shared = KeepWords()
    /// `keep-words-chat.txt`: thêm của ViPi, các viết tắt và tiếng lóng tiếng Việt không dấu đo được là chưa có ở trên
    /// (afk, inb, nhma, mlem…), cùng định dạng.
    private let files: [Data]

    private init() {
        files = ["keep-words", "keep-words-chat"].compactMap {
            Bundle.main.url(forResource: $0, withExtension: "txt").flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }
        }
    }

    func contains(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let key = Array(word.lowercased().utf8)
        return files.contains { Self.find(key, in: $0) }
    }

    private static func find(_ key: [UInt8], in data: Data) -> Bool {
        data.withUnsafeBytes { (b: UnsafeRawBufferPointer) -> Bool in
            var lo = 0, hi = b.count   // khoảng byte còn phải xét, luôn bắt đầu ở đầu một dòng
            while lo < hi {
                var start = (lo + hi) / 2
                while start > lo, b[start - 1] != 10 { start -= 1 }
                var end = start
                while end < hi, b[end] != 10 { end += 1 }
                let line = b[start..<end]
                if line.elementsEqual(key) { return true }
                if line.lexicographicallyPrecedes(key) { lo = min(end + 1, hi) } else { hi = start }
            }
            return false
        }
    }
}
