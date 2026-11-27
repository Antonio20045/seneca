import CoreLocation
import Foundation

enum JW: Decodable, Equatable {
    case s(String), d(Double), n

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .d(d) } else if let s = try? c.decode(String.self) { self = .s(s) } else { self = .n }
    }

    var d: Double? { if case .d(let v) = self { return v }; return nil }
    var s: String? { if case .s(let v) = self { return v }; return nil }
}

struct LaufDaten: Decodable, Equatable {
    var kennzahlen: Kennzahlen?
    var lauf: Einzel?

    struct Kennzahlen: Decodable, Equatable { var wochen: [String]; var lauf: Lauf }
    struct Lauf: Decodable, Equatable {
        var km: [Double]
        var lang: [Double]
        var laengster: [JW]?
        var aufbau: [[JW]]
        var pace_monat: [[JW]]?
        var liste: [Zeile]?
        var puls_max: Double?
        var naechster: Naechster?
    }
    struct Zeile: Decodable, Equatable, Identifiable {
        var id: String
        var zeit: Double
        var km: Double
        var s: Double?
        var puls: Double?
        var hm: Double?
        var titel: String?
        var form: [[Double]]?
        var datum: Date { Date(timeIntervalSince1970: zeit / 1000) }
        var pace: Double? { s.map { $0 / km } }
    }
    struct Naechster: Decodable, Equatable { var datum: String?; var name: String?; var beschreibung: String? }
    struct Einzel: Decodable, Equatable { var id: String; var spur: Spur? }
    struct Spur: Decodable, Equatable { var p: [[Double]]?; var r: [[Double?]]?; var trainer: String?; var quelle: String? }
}

struct LaufPunkt: Equatable {
    var m: Double
    var pace: Double?
    var puls: Double?
    var hoehe: Double?
}

enum LaufRechnen {
    static let de = Locale(identifier: "de_DE")

    static func pace(_ s: Double?) -> String {
        guard let s, s.isFinite, s > 0 else { return "–" }
        let r = Int(s.rounded())
        return "\(r / 60):" + String(format: "%02d", r % 60)
    }

    static func dauer(_ s: Double?) -> String {
        guard let s else { return "–" }
        let r = Int(s.rounded())
        return r >= 3600 ? "\(r / 3600):" + String(format: "%02d:%02d", r / 60 % 60, r % 60) : "\(r / 60):" + String(format: "%02d", r % 60)
    }

    static func zahl(_ v: Double, _ stellen: Int = 1) -> String { v.formatted(.number.precision(.fractionLength(stellen)).locale(de)) }

    static func datum(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = de
        f.dateFormat = format
        return f.string(from: d)
    }

    static func kurz(_ d: Date, tag: Bool = true) -> String {
        ((tag ? datum(d, "EEEEEE").replacingOccurrences(of: ".", with: "") + " " : "") + datum(d, "d. ") + datum(d, "LLL").replacingOccurrences(of: ".", with: "")).uppercased()
    }

    static func wochenBeginn(_ jetzt: Date) -> Date {
        var k = Calendar(identifier: .iso8601)
        k.locale = de
        return k.dateInterval(of: .weekOfYear, for: jetzt.addingTimeInterval(-4 * 3600))?.start ?? jetzt
    }

    static func woche(_ liste: [LaufDaten.Zeile], jetzt: Date) -> (km: Double, laeufe: Int, s: Double) {
        let ab = wochenBeginn(jetzt).addingTimeInterval(4 * 3600)
        let w = liste.filter { $0.datum >= ab }
        return (w.reduce(0) { $0 + $1.km }, w.count, w.reduce(0) { $0 + ($1.s ?? 0) })
    }

    static func punkte(_ r: [[Double?]]) -> [LaufPunkt] {
        guard r.count > 1 else { return [] }
        return r.indices.map { i in
            let a = r[max(0, i - 2)], b = r[min(r.count - 1, i + 2)]
            let dm = (b[1] ?? 0) - (a[1] ?? 0), ds = (b[0] ?? 0) - (a[0] ?? 0)
            return LaufPunkt(m: r[i][1] ?? 0, pace: dm > 5 ? ds * 1000 / dm : nil, puls: r[i].count > 2 ? r[i][2] : nil, hoehe: r[i].count > 3 ? r[i][3] : nil)
        }
    }

    static func zonen(_ r: [[Double?]], pulsMax: Double?) -> [Double]? {
        let mitPuls = r.filter { $0.count > 2 && $0[2] != nil }
        guard mitPuls.count > 3, let hf = pulsMax ?? mitPuls.compactMap({ $0[2] }).max(), hf > 0 else { return nil }
        var z = [Double](repeating: 0, count: 5)
        for i in 1..<r.count {
            guard let p = r[i].count > 2 ? r[i][2] : nil else { continue }
            let anteil = p / hf
            z[anteil < 0.6 ? 0 : anteil < 0.7 ? 1 : anteil < 0.8 ? 2 : anteil < 0.9 ? 3 : 4] += max(0, (r[i][0] ?? 0) - (r[i - 1][0] ?? 0))
        }
        return z
    }

    static func aehnlich(_ liste: [LaufDaten.Zeile], zu id: String) -> [LaufDaten.Zeile] {
        guard let l = liste.first(where: { $0.id == id }) else { return [] }
        let rest = liste.filter { $0.id != id && abs($0.km - l.km) <= max(1, l.km * 0.2) && $0.s != nil }
        return [l] + rest.prefix(4)
    }

    static func koordinaten(_ p: [[Double]]?) -> [CLLocationCoordinate2D] {
        (p ?? []).filter { $0.count == 2 }.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
    }

    static func ort(_ k: [CLLocationCoordinate2D], anteil: Double) -> CLLocationCoordinate2D? {
        guard k.count > 1 else { return k.first }
        let orte = k.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var summe = [0.0]
        for i in 1..<orte.count { summe.append(summe[i - 1] + orte[i].distance(from: orte[i - 1])) }
        let ziel = (summe.last ?? 0) * min(1, max(0, anteil))
        let i = summe.firstIndex { $0 >= ziel } ?? orte.count - 1
        return k[i]
    }

    static func satzStart(_ liste: [LaufDaten.Zeile], planKm: Double?, jetzt: Date) -> (String, String) {
        guard let letzter = liste.first else { return ("Noch kein Lauf da.", "Der erste zählt am meisten.") }
        let tage = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: letzter.datum), to: Calendar.current.startOfDay(for: jetzt)).day ?? 0
        let w = woche(liste, jetzt: jetzt)
        if tage == 0 { return ("Heute gelaufen.", "Das zählt, egal wie schnell.") }
        if tage >= 3 { return ("Seit \(tage) Tagen kein Lauf.", "Fang klein an, aber fang an.") }
        if let p = planKm, p > 0 {
            return w.km >= p ? ("\(zahl(w.km)) km diese Woche.", "Der Plan ist erfüllt.") : ("\(zahl(w.km)) km diese Woche.", "Noch \(zahl(p - w.km)) bis zum Plan.")
        }
        return ("\(zahl(w.km)) km diese Woche.", "Gestern war gestern.")
    }

    static func befund(_ km: [String]) -> String? {
        let s = km.compactMap { t -> Double? in
            let teile = t.split(separator: ":").compactMap { Double($0) }
            return teile.count == 2 ? teile[0] * 60 + teile[1] : nil
        }
        guard s.count > 2, let lo = s.min(), let hi = s.max(), let i = s.firstIndex(of: lo) else { return nil }
        let diff = Int((hi - lo).rounded())
        return diff < 15 ? "Alle Kilometer innerhalb von \(diff) Sekunden. Gleichmäßig gelaufen."
            : "Kilometer \(i + 1) in \(pace(lo)), der langsamste \(diff >= 60 ? "\(diff / 60):" + String(format: "%02d", diff % 60) + " Minuten" : "\(diff) Sekunden") langsamer."
    }
}
