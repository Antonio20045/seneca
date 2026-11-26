import SwiftUI

enum TafelFarbe {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255).opacity(a)
    }
    static let text = hex(0xE2E4E9)
    static let leise = hex(0x939EAD)
    static let zweit = hex(0xBAC1CB)
    static let akzent = hex(0xCFE4FA)
    static let aus = hex(0x6B7686)
    static let bernstein = hex(0xE8B84B)
    static let gruen = hex(0x6BD98F)
    static let jetzt = hex(0xF07A5F)
    static let himmel = hex(0x8FB6E3)
    static let aufHimmel = hex(0x0A2245)
}

enum HeuteTafelLogik {
    static let tagVon = 7.0, tagBis = 21.0

    static func datum(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    static func beispiel(_ name: String = "Beispiel-Stand") -> SenecaStand? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let roh = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SenecaStand.self, from: roh)
    }

    static func datumZeile(_ ms: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f.string(from: datum(ms))
    }

    static func wochentag(_ ms: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE"
        return f.string(from: datum(ms))
    }

    static func frist(_ ms: Double, jetzt: Double, _ cal: Calendar = .current) -> String {
        if cal.isDate(datum(ms), inSameDayAs: datum(jetzt)) { return "Frist \(uhr(ms, cal))" }
        if let morgen = cal.date(byAdding: .day, value: 1, to: datum(jetzt)), cal.isDate(datum(ms), inSameDayAs: morgen) { return "Frist morgen" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d.M."
        return "Frist \(f.string(from: datum(ms)))"
    }

    static func uhr(_ ms: Double, _ cal: Calendar = .current) -> String {
        let k = cal.dateComponents([.hour, .minute], from: datum(ms))
        return String(format: "%02d:%02d", k.hour ?? 0, k.minute ?? 0)
    }

    static func kommend(_ s: SenecaStand) -> [SenecaStand.Termin] {
        (s.termine ?? []).filter { $0.ganztag != true && $0.art != "fokus" && $0.art != "bewegung" && $0.start > s.jetzt }.sorted { $0.start < $1.start }
    }

    static func satz(_ s: SenecaStand, folge: Bool = false) -> (vor: String, akzent: String)? {
        guard let t = folge ? s.heute?.satz_folge : s.heute?.satz, t.count == 2 else { return nil }
        return (t[0], t[1])
    }

    static func frage(_ s: SenecaStand) -> SenecaStand.Frage? {
        guard s.ruhe == nil || s.ruhe?.durchbruch == true && s.ruhe?.grund != "fokus" else { return nil }
        return s.braucht_dich?.first { $0.antwort == nil }
    }

    static func wartenZeile(_ s: SenecaStand) -> String? {
        let n = (s.buendel?.fragen?.count ?? 0) + (s.ruhe == nil ? 0 : s.braucht_dich?.count ?? 0)
        guard let r = s.ruhe, n > 0 else { return nil }
        let wort = n == 1 ? "1 Frage wartet" : "\(n) Fragen warten"
        return wort + (r.grund == "fokus" ? ", bis dein Fokus vorbei ist" : ", bis deine Ruhe vorbei ist")
    }

    static func teamZeile(_ s: SenecaStand) -> String? {
        guard let m = s.team?.first(where: { $0.zustand == "arbeitet" && $0.satz != nil }), let satz = m.satz else { return nil }
        let min = m.seit.map { " · \(Int(max(0, s.jetzt - $0) / 60_000)) Min" } ?? ""
        return "\(m.name) \(satz)\(min)"
    }

    static func todoZeile(_ t: SenecaStand.Todo) -> String {
        [t.bereich, t.dauer_min.map { "\(Int($0)) Min" }].compactMap { $0 }.joined(separator: " · ")
    }

    static func anteil(_ ms: Double, _ cal: Calendar = .current) -> Double {
        let k = cal.dateComponents([.hour, .minute], from: datum(ms))
        return min(1, max(0, (Double(k.hour ?? 0) + Double(k.minute ?? 0) / 60 - tagVon) / (tagBis - tagVon)))
    }

    static func marke(_ s: SenecaStand) -> (ort: Double, text: String)? {
        if let r = s.ruhe, r.grund == "fokus", let bis = r.bis, let f = s.termine?.first(where: { $0.art == "fokus" && $0.ende >= bis && $0.start <= s.jetzt }) {
            return (anteil(f.start), "FOKUS BIS \(uhr(bis))")
        }
        guard let a = kommend(s).first(where: { $0.ende - $0.start >= 30 * 60_000 }) else { return nil }
        let name = a.titel.components(separatedBy: " mit ").last ?? a.titel
        return (anteil(a.start), "\(uhr(a.start)) \(name.uppercased())")
    }
}
