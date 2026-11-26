import Foundation

struct HauptfadenWache: Sendable {
    private(set) var proben: [Double] = []

    mutating func notiere(_ verzugMs: Double) { proben.append(verzugMs) }

    func haenger(ueber schwelle: Double = 50) -> Int { proben.count { $0 > schwelle } }

    var schlechtester: Double { proben.max() ?? 0 }

    var mittel: Double { proben.isEmpty ? 0 : proben.reduce(0, +) / Double(proben.count) }

    func perzentil(_ p: Double) -> Double {
        guard !proben.isEmpty else { return 0 }
        let s = proben.sorted()
        let i = min(s.count - 1, max(0, Int((Double(s.count - 1) * p).rounded())))
        return s[i]
    }

    func bericht(_ name: String, schwelle: Double = 50) -> String {
        String(format: "%@: %d Proben, Hänger >%.0f ms: %d, schlechtester %.1f ms, Mittel %.2f ms, P99 %.1f ms",
               name, proben.count, schwelle, haenger(ueber: schwelle), schlechtester, mittel, perzentil(0.99))
    }
}
