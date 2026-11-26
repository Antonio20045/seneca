import Foundation

enum Frische {
    enum Quelle: String { case messwerte, kurzstand, plan, geld, vertrauen, befunde }

    static let messwerteMaxTage = 2
    static let kurzstandToleranzMs: Double = 12 * 3_600_000
    static let planMaxTage = 14

    static func rhythmus(_ q: Quelle) -> String {
        switch q {
        case .messwerte, .geld, .vertrauen, .befunde: return "täglich"
        case .kurzstand: return "bei jeder Kartenänderung"
        case .plan: return "alle zwei Wochen"
        }
    }

    struct Stand: Equatable {
        var text: String
        var veraltet: Bool
        var keine: Bool
        var wann: Double?
        var rhythmus: String
    }

    static func ausStempel(_ s: Any?, _ cal: Calendar = .current) -> Double? {
        if let n = s as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue.isFinite ? n.doubleValue : nil }
        guard let str = s as? String else { return nil }
        let t = str.trimmingCharacters(in: .whitespaces)
        guard let re = try? NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?"#),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func g(_ i: Int) -> Int? {
            guard let r = Range(m.range(at: i), in: t) else { return nil }
            return Int(t[r])
        }
        let c = DateComponents(year: g(1), month: g(2), day: g(3), hour: g(4) ?? 0, minute: g(5) ?? 0, second: g(6) ?? 0)
        return cal.date(from: c).map { $0.timeIntervalSince1970 * 1000 }
    }

    static func kurzDatum(_ ms: Double, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.day, .month], from: Date(timeIntervalSince1970: ms / 1000))
        return "\(c.day ?? 1).\(c.month ?? 1)."
    }

    private static func keine(_ q: Quelle) -> Stand { Stand(text: "noch keine Daten", veraltet: false, keine: true, wann: nil, rhythmus: rhythmus(q)) }

    private static func stand(_ wann: Double, _ jetzt: Double, veraltet: Bool, mitUhr: Bool, _ q: Quelle) -> Stand {
        let t = Menschlich.tageZwischen(wann, jetzt)
        let tag = t <= 0 ? (mitUhr ? "heute \(Menschlich.hhmm(wann))" : "heute") : t == 1 ? (mitUhr ? "gestern \(Menschlich.hhmm(wann))" : "gestern") : kurzDatum(wann)
        return Stand(text: veraltet ? "Stand \(kurzDatum(wann)) · veraltet" : "Stand \(tag)", veraltet: veraltet, keine: false, wann: wann, rhythmus: rhythmus(q))
    }

    static func messwert(datentag: Any?, dateiStand: Any?, jetzt: Double, hatWert: Bool = false) -> Stand {
        guard let tag = ausStempel(datentag) else {
            return hatWert && ausStempel(dateiStand) != nil ? datei(dateiStand, jetzt: jetzt, quelle: .messwerte) : keine(.messwerte)
        }
        let d = ausStempel(dateiStand)
        let veraltet = Menschlich.tageZwischen(tag, jetzt) > messwerteMaxTage || (d.map { Menschlich.tageZwischen($0, jetzt) > messwerteMaxTage } ?? false)
        if !veraltet, let d, Menschlich.tageZwischen(tag, jetzt) <= 0 { return stand(d, jetzt, veraltet: false, mitUhr: true, .messwerte) }
        return stand(tag, jetzt, veraltet: veraltet, mitUhr: false, .messwerte)
    }

    static func datei(_ stempel: Any?, jetzt: Double, quelle: Quelle, maxTage: Int = messwerteMaxTage, nurWennOffen: Bool = true) -> Stand {
        guard let wann = ausStempel(stempel) else { return keine(quelle) }
        return stand(wann, jetzt, veraltet: nurWennOffen && Menschlich.tageZwischen(wann, jetzt) > maxTage, mitUhr: true, quelle)
    }

    static func plan(geaendertAm: Double?, offen: Int, jetzt: Double) -> Stand {
        datei(geaendertAm, jetzt: jetzt, quelle: .plan, maxTage: planMaxTage, nurWennOffen: offen > 0)
    }

    static func kurzstand(geaendertAm: Double?, letzteKartenaenderung: Double, jetzt: Double) -> Stand {
        guard let g = geaendertAm, g.isFinite, g > 0 else { return keine(.kurzstand) }
        return stand(g, jetzt, veraltet: letzteKartenaenderung - g > kurzstandToleranzMs, mitUhr: true, .kurzstand)
    }
}
