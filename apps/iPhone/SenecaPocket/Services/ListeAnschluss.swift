import Foundation

extension HeuteLogik {
    static let zahlwort = ["", "Eine", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht", "Neun", "Zehn", "Elf", "Zwölf"]
}

extension TageslaufZeit {
    static func lies(_ wert: Any?, heute: Date, kalender: Calendar) -> Date? {
        if let n = wert as? NSNumber, !(wert is String) {
            let z = n.doubleValue
            return z <= 0 ? nil : Date(timeIntervalSince1970: z > 100_000_000_000 ? z / 1000 : z)
        }
        guard let roh = wert as? String else { return nil }
        let s = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let d = IsoZeit.datum(s) { return d }
        func gruppen(_ muster: String) -> [String?]? {
            guard let re = try? NSRegularExpression(pattern: muster),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
        }
        if let g = gruppen(#"^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?"#) {
            var c = DateComponents(year: g[1].flatMap(Int.init), month: g[2].flatMap(Int.init), day: g[3].flatMap(Int.init))
            c.hour = g[4].flatMap(Int.init) ?? 0; c.minute = g[5].flatMap(Int.init) ?? 0; c.second = g[6].flatMap(Int.init) ?? 0
            return kalender.date(from: c)
        }
        if let g = gruppen(#"^(\d{1,2}):(\d{2})$"#), let h = g[1].flatMap(Int.init), let m = g[2].flatMap(Int.init) {
            return kalender.date(bySettingHour: h, minute: m, second: 0, of: heute)
        }
        return nil
    }
}
