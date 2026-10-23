import Foundation

/// Âm mờ (模糊音): coi hai cách phát âm là một, vd z = zh, in = ing.
public struct FuzzyRule: Identifiable, Hashable {
    public let a: String
    public let b: String
    public let isInitial: Bool     // phụ âm đầu (thay ở đầu âm tiết) hay vần (thay ở cuối)
    public var id: String { "\(a)=\(b)" }
    public var label: String { "\(a) ↔ \(b)" }

    public static let all: [FuzzyRule] = [
        FuzzyRule(a: "z", b: "zh", isInitial: true),
        FuzzyRule(a: "c", b: "ch", isInitial: true),
        FuzzyRule(a: "s", b: "sh", isInitial: true),
        FuzzyRule(a: "n", b: "l", isInitial: true),
        FuzzyRule(a: "f", b: "h", isInitial: true),
        FuzzyRule(a: "l", b: "r", isInitial: true),
        FuzzyRule(a: "an", b: "ang", isInitial: false),
        FuzzyRule(a: "en", b: "eng", isInitial: false),
        FuzzyRule(a: "in", b: "ing", isInitial: false),
    ]

    /// Âm tiết gõ theo luật mờ → các âm tiết thật trong từ điển. `rules` là các id ("z=zh") đang bật.
    public static func aliases(rules: Set<String>, syllables: Set<String>) -> [String: [String]] {
        let active = all.filter { rules.contains($0.id) }
        guard !active.isEmpty else { return [:] }
        var out: [String: [String]] = [:]
        for s in syllables {
            for r in active {
                let v: String?
                if r.isInitial {
                    if s.hasPrefix(r.b) { v = r.a + s.dropFirst(r.b.count) }
                    else if s.hasPrefix(r.a) { v = r.b + s.dropFirst(r.a.count) }
                    else { v = nil }
                } else {
                    if s.hasSuffix(r.b) { v = String(s.dropLast(r.b.count)) + r.a }
                    else if s.hasSuffix(r.a) { v = String(s.dropLast(r.a.count)) + r.b }
                    else { v = nil }
                }
                if let v, v != s, !(out[v]?.contains(s) ?? false) { out[v, default: []].append(s) }
            }
        }
        return out
    }
}
