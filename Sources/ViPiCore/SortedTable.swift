import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Bảng khoá → giá trị trong file nhị phân (docs/data-format.md, dựng bằng scripts/build-tables.py), ánh xạ
/// thẳng vào bộ nhớ (mmap): khoá UTF-8 sắp xếp theo byte, tra bằng tìm kiếm nhị phân. Không chép dữ liệu ra
/// RAM riêng (hệ điều hành đọc trang nào cần và bỏ được khi thiếu bộ nhớ); bản Windows/Android đọc cùng file.
public final class SortedTable {
    public enum Error: Swift.Error { case cannotOpen, badFormat }

    private let base: UnsafeRawPointer
    private let size: Int
    public let count: Int
    /// Số riêng của từng bảng (pinyin-words.bin: tổng weight).
    public let meta: Double
    private let keyOffsets: Int, valueOffsets: Int, keys: Int, values: Int

    public init(contentsOf url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw Error.cannotOpen }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size >= 24 else { throw Error.badFormat }
        let size = Int(st.st_size)
        guard let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0), p != MAP_FAILED else { throw Error.cannotOpen }
        let b = UnsafeRawPointer(p)
        let count = Self.u32(b, 8)
        let keys = 24 + 2 * (count + 1) * 4
        guard memcmp(b, "VPST", 4) == 0, Self.u32(b, 4) == 1, keys <= size,
              keys + Self.u32(b, 24 + count * 4) + Self.u32(b, keys - 4) == size else {
            munmap(p, size)
            throw Error.badFormat
        }
        base = b
        self.size = size
        self.count = count
        meta = Double(bitPattern: b.loadUnaligned(fromByteOffset: 16, as: UInt64.self).littleEndian)
        keyOffsets = 24
        valueOffsets = 24 + (count + 1) * 4
        self.keys = keys
        values = keys + Self.u32(b, 24 + count * 4)
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), size) }

    private static func u32(_ p: UnsafeRawPointer, _ at: Int) -> Int {
        Int(p.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian)
    }

    /// Byte UTF-8 của khoá thứ `i`.
    public func key(at i: Int) -> UnsafeRawBufferPointer {
        let start = Self.u32(base, keyOffsets + i * 4), end = Self.u32(base, keyOffsets + i * 4 + 4)
        return UnsafeRawBufferPointer(start: base + keys + start, count: end - start)
    }

    /// Giá trị của khoá thứ `i`; trỏ thẳng vào file, dùng được tới khi bảng bị giải phóng.
    public func value(at i: Int) -> UnsafeRawBufferPointer {
        let start = Self.u32(base, valueOffsets + i * 4), end = Self.u32(base, valueOffsets + i * 4 + 4)
        return UnsafeRawBufferPointer(start: base + values + start, count: end - start)
    }

    /// `count` byte bắt đầu tại vị trí `offset` của khối giá trị (cho bảng trỏ sang mục của bảng khác).
    public func values(offset: Int, count n: Int) -> UnsafeRawBufferPointer {
        UnsafeRawBufferPointer(start: base + values + offset, count: n)
    }

    /// Chỉ số khoá đầu tiên ≥ `key` (so theo byte).
    public func lowerBound(_ key: [UInt8]) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if Self.compare(self.key(at: mid), key) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    public func index(of key: String) -> Int? {
        let k = Array(key.utf8)
        let i = lowerBound(k)
        return i < count && Self.compare(self.key(at: i), k) == 0 ? i : nil
    }

    public func value(for key: String) -> UnsafeRawBufferPointer? { index(of: key).map(value(at:)) }

    /// Có khoá nào bắt đầu bằng `prefix` không.
    public func hasKey(withPrefix prefix: String) -> Bool {
        let p = Array(prefix.utf8)
        let i = lowerBound(p)
        return i < count && key(at: i).starts(with: p)
    }

    private static func compare(_ a: UnsafeRawBufferPointer, _ b: [UInt8]) -> Int {
        let n = min(a.count, b.count)
        let c = b.withUnsafeBytes { n == 0 ? 0 : Int(memcmp(a.baseAddress!, $0.baseAddress!, n)) }
        return c != 0 ? c : a.count - b.count
    }
}
