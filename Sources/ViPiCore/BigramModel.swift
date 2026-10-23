import Foundation

/// Mô hình bigram từ (dữ liệu libpinyin, GPL-3; dựng bằng scripts/make-bigram.py): P(w2 | w1) nội suy với unigram
/// của từ điển, để khi ghép câu chọn 在/再, 是/时/事 theo từ đứng trước thay vì chỉ theo tần suất riêng lẻ.
/// bigram.bin được mmap: mảng khoá FNV-1a 64 đã sắp xếp + mảng số đếm, tra bằng tìm kiếm nhị phân,
/// nên nạp tức thì và gần như không tốn bộ nhớ riêng.
public final class BigramModel {
    private let data: Data
    private let uniKeys: Range<Int>, uniCounts: Range<Int>      // offset byte trong data
    private let pairKeys: Range<Int>, pairCounts: Range<Int>
    public let unigramCount: Int, pairCount: Int
    /// Trọng số của bigram so với unigram khi nội suy (0.7 đúng nhất trên bộ 50 câu thử).
    public let lambda: Double

    public enum Error: Swift.Error { case badFormat }

    public convenience init(contentsOf url: URL, lambda: Double = 0.7) throws {
        try self.init(data: try Data(contentsOf: url, options: .alwaysMapped), lambda: lambda)
    }

    public init(data: Data, lambda: Double = 0.7) throws {
        self.data = data
        self.lambda = lambda
        guard data.count >= 16, data.prefix(4) == Data("VPBG".utf8) else { throw Error.badFormat }
        func u32(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24 }
        guard u32(4) == 1 else { throw Error.badFormat }
        unigramCount = u32(8)
        pairCount = u32(12)
        var o = 16
        uniKeys = o..<(o + unigramCount * 8); o = uniKeys.upperBound
        uniCounts = o..<(o + unigramCount * 4); o = uniCounts.upperBound
        pairKeys = o..<(o + pairCount * 8); o = pairKeys.upperBound
        pairCounts = o..<(o + pairCount * 4); o = pairCounts.upperBound
        guard o == data.count else { throw Error.badFormat }
    }

    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return h
    }

    /// Tìm `key` trong mảng u64 sắp xếp tại `keys`; trả về count tương ứng.
    private func count(_ key: UInt64, keys: Range<Int>, counts: Range<Int>) -> UInt32? {
        data.withUnsafeBytes { raw -> UInt32? in
            let n = keys.count / 8
            var lo = 0, hi = n
            while lo < hi {
                let mid = (lo + hi) / 2
                let k = raw.loadUnaligned(fromByteOffset: keys.lowerBound + mid * 8, as: UInt64.self).littleEndian
                if k == key { return raw.loadUnaligned(fromByteOffset: counts.lowerBound + mid * 4, as: UInt32.self).littleEndian }
                if k < key { lo = mid + 1 } else { hi = mid }
            }
            return nil
        }
    }

    /// log P(w2 | w1) = log(λ·c12/c1 + (1-λ)·P(w2)). w1 không có trong corpus coi như c12 = 0,
    /// vẫn chịu hệ số (1-λ) để từ hiếm không được "miễn phạt" khi đứng trước.
    public func logProb(_ w1: String, _ w2: String, unigram p2: Double) -> Double {
        guard let c1 = count(Self.fnv1a(w1), keys: uniKeys, counts: uniCounts), c1 > 0,
              let c12 = count(Self.fnv1a(w1 + "\t" + w2), keys: pairKeys, counts: pairCounts) else {
            return log((1 - lambda) * p2)
        }
        return log(lambda * Double(c12) / Double(c1) + (1 - lambda) * p2)
    }
}
