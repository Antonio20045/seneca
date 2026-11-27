import Foundation

enum Muster {
    private static let sperre = NSLock()
    nonisolated(unsafe) private static var gemerkt: [String: NSRegularExpression] = [:]
    private static func hole(_ muster: String, _ gross: Bool) -> NSRegularExpression? {
        let k = (gross ? "i" : "-") + muster
        sperre.lock(); defer { sperre.unlock() }
        if let re = gemerkt[k] { return re }
        guard let re = try? NSRegularExpression(pattern: muster, options: gross ? [.caseInsensitive] : []) else { return nil }
        if gemerkt.count > 400 { gemerkt.removeAll() }
        gemerkt[k] = re
        return re
    }
    static func erster(_ s: String, _ muster: String, gross: Bool = false) -> [String?]? {
        guard let re = hole(muster, gross) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }
    static func passt(_ s: String, _ muster: String, gross: Bool = false) -> Bool { erster(s, muster, gross: gross) != nil }
}

extension Menschlich {
    static func seitText(_ ms: Double, jetzt: Double) -> String {
        let t = tageZwischen(ms, jetzt)
        if t <= 0 { return "seit heute" }
        if t == 1 { return "seit gestern" }
        if t < 14 { return "seit \(t) Tagen" }
        if t < 60 { return "seit \(Int((Double(t) / 7).rounded())) Wochen" }
        return "seit \(Int((Double(t) / 30).rounded())) Monaten"
    }
}

enum HeuteLogik {
    static let zahlwort = ["", "Eine", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht", "Neun", "Zehn", "Elf", "Zwölf"]

    static func jobName(_ j: OvAuftrag) -> String {
        var n = Menschlich.cleanName(j.displayName ?? j.name)
        n = n.replacingOccurrences(of: #"^Skill collection review.*$"#, with: "Skill-Review", options: [.regularExpression, .caseInsensitive])
        n = n.replacingOccurrences(of: "Telco-Radar · ", with: "", options: .anchored)
        n = n.replacingOccurrences(of: #"\s+—\s+täglicher Check$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return n.trimmingCharacters(in: .whitespaces)
    }

    static func istHauptschluessel(_ k: String) -> Bool { Muster.passt(k, #"^agent:[^:]+:main$"#) }
}
