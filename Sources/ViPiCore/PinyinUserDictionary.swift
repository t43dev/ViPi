import Foundation

/// Từ và cụm người dùng đã chọn: khoá là đúng các chữ cái đã gõ (bỏ dấu '), giá trị là số lần chọn.
/// Lưu JSON trong file (nếu có), ghi ở hàng đợi nền để không chặn luồng bắt phím.
public final class PinyinUserDictionary {
    public private(set) var entries: [String: [String: Int]] = [:]
    public let fileURL: URL?
    public var maxEntries = 5000
    private let queue = DispatchQueue(label: "ViPi.userdict", qos: .utility)

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            entries = loaded
        }
    }

    public var count: Int { entries.values.reduce(0) { $0 + $1.count } }

    public func record(_ key: String, _ text: String) {
        guard !key.isEmpty, !text.isEmpty else { return }
        entries[key, default: [:]][text, default: 0] += 1
        if count > maxEntries { prune() }
        save()
    }

    /// Từ đã học cho đúng khoá này, chọn nhiều lần nhất trước.
    public func words(for key: String) -> [String] {
        guard let m = entries[key] else { return [] }
        return m.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    public func clear() {
        entries = [:]
        if let fileURL { queue.async { try? FileManager.default.removeItem(at: fileURL) } }
    }

    /// Giữ lại các mục được chọn nhiều nhất.
    private func prune() {
        var flat: [(key: String, text: String, n: Int)] = []
        for (k, m) in entries { for (t, n) in m { flat.append((k, t, n)) } }
        flat.sort { $0.n > $1.n }
        entries = [:]
        for e in flat.prefix(maxEntries * 9 / 10) { entries[e.key, default: [:]][e.text] = e.n }
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = entries
        queue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
