import Foundation

enum KalAnsicht: String, CaseIterable {
    case tag, woche, monat
    var name: String { switch self { case .tag: "Tag"; case .woche: "Woche"; case .monat: "Monat" } }
}

struct KalEntwurf: Equatable {
    var titel = ""
    var start: Double
    var ende: Double
    var ort = ""
    var kalender: String
    var weg: KalWeg?
    var uid: String?
}

struct KalWeg: Equatable {
    var m: Double
    var min: Int
    var art: String
    static func wert(_ g: KalWeg) -> [String: JSONWert] { ["entfernung_m": .zahl(g.m), "weg_min": .zahl(Double(g.min)), "art": .text(g.art)] }
}

enum KalenderLogik {
    typealias K = SenecaStand.Wochenplan
    private static let stundeWort = ["zwölf", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf"]
    private static let wegWort = ["fuss": "zu Fuß", "rad": "mit dem Rad", "auto": "mit dem Auto"]
    private static let minute = 60_000.0

    static func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }

    static func format(_ ms: Double, _ muster: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = muster
        return f.string(from: HeuteTafelLogik.datum(ms))
    }

    static func gleicherTag(_ a: Double, _ b: Double) -> Bool { cal().isDate(HeuteTafelLogik.datum(a), inSameDayAs: HeuteTafelLogik.datum(b)) }

    static func wocheVon(_ k: K, jetzt: Double) -> Int {
        k.wochen.lastIndex { $0.von <= jetzt } ?? 0
    }

    static func tage(_ k: K, woche: Int) -> ArraySlice<SenecaStand.KalTag> {
        let von = max(0, min(woche, k.wochen.count - 1)) * 7
        return k.tage[von..<min(k.tage.count, von + 7)]
    }

    static func monat(_ k: K, woche: Int) -> [SenecaStand.KalTag] {
        guard let mitte = tage(k, woche: woche).first else { return [] }
        let m = cal().component(.month, from: HeuteTafelLogik.datum(mitte.tag + 3 * 86_400_000))
        let erste = k.tage.firstIndex { cal().component(.month, from: HeuteTafelLogik.datum($0.tag)) == m } ?? 0
        let ab = erste - erste % 7
        let bis = (k.tage.lastIndex { cal().component(.month, from: HeuteTafelLogik.datum($0.tag)) == m } ?? k.tage.count - 1) / 7 * 7 + 7
        return Array(k.tage[max(0, ab)..<min(k.tage.count, bis)])
    }

    static func kopf(_ k: K, ansicht: KalAnsicht, woche: Int, tag: Double, jetzt: Double) -> (titel: String, unter: String) {
        switch ansicht {
        case .woche:
            let w = k.wochen[max(0, min(woche, k.wochen.count - 1))]
            return (w.titel, w.unter)
        case .tag:
            let titel = gleicherTag(tag, jetzt) ? "Heute" : gleicherTag(tag, jetzt + 86_400_000) ? "Morgen" : format(tag, "EEEE")
            return (titel, format(tag, "d. MMMM"))
        case .monat:
            let mitte = tage(k, woche: woche).first.map { $0.tag + 3 * 86_400_000 } ?? jetzt
            return (format(mitte, "MMMM"), format(mitte, "yyyy"))
        }
    }

    static func y(_ ms: Double, tag: Double, von: Double, stunde: Double) -> Double {
        (ms - tag) / 3_600_000 * stunde - von * stunde
    }

    static func raste(_ ms: Double, tag: Double, minuten: Double) -> Double {
        tag + ((ms - tag) / (minuten * minute)).rounded() * minuten * minute
    }

    static func uhr(_ ms: Double) -> String { HeuteTafelLogik.uhr(ms) }

    static func zeitZeile(_ start: Double, _ ende: Double) -> String {
        let k = cal().dateComponents([.weekday, .day, .month], from: HeuteTafelLogik.datum(start))
        let tag = ["SO", "MO", "DI", "MI", "DO", "FR", "SA"][(k.weekday ?? 1) - 1]
        let monat = ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"][(k.month ?? 1) - 1]
        return "\(tag) \(k.day ?? 1). \(monat) · \(uhr(start)) BIS \(uhr(ende))"
    }

    static func wegZeile(_ w: KalWeg) -> String {
        "\(String(format: "%.1f", w.m / 1000).replacingOccurrences(of: ".", with: ",")) km · \(w.min) Min \(wegWort[w.art] ?? "zu Fuß")"
    }

    static func erinnerung(_ e: KalEntwurf, vorMin: Double) -> (zeile: String, unter: String)? {
        guard let w = e.weg else { return nil }
        let los = e.start - Double(w.min) * minute
        return ("\(uhr(los - vorMin * minute)) an der Uhr", "Los um \(uhr(los)), Seneca rechnet mit")
    }

    static func stunde(_ ms: Double) -> String {
        let k = cal().dateComponents([.hour, .minute], from: HeuteTafelLogik.datum(ms))
        return k.minute == 0 ? stundeWort[(k.hour ?? 0) % 12] : uhr(ms)
    }

    private static func zum(_ wort: String) -> String {
        ["ung", "heit", "keit", "schaft", "e"].contains { wort.hasSuffix($0) } ? "zur" : "zum"
    }

    static func danach(_ e: KalEntwurf, bloecke: [SenecaStand.KalBlock]) -> String {
        let feste = bloecke.filter { ["termin", "zugleich", "seneca", "bewegung"].contains($0.art) && (e.uid == nil || $0.uid != e.uid) }
        if let x = feste.first(where: { $0.start < e.ende && e.start < $0.ende }) { return "Das überschneidet sich mit \(x.teile?.first ?? x.titel)." }
        let naechster = feste.filter { $0.start >= e.ende }.min { $0.start < $1.start }
        let wort = (naechster?.teile?.first ?? naechster?.titel ?? "").split(separator: " ").first.map(String.init) ?? ""
        let satz = naechster.map { "Danach ist bis \(zum(wort)) \(wort) um \(stunde($0.start)) frei." } ?? "Danach ist der Tag frei."
        guard let k = feste.first(where: { $0.art == "zugleich" }) else { return satz }
        let h = cal().dateComponents([.hour, .minute], from: HeuteTafelLogik.datum(k.start))
        return satz + " Am Konflikt um \(h.minute == 0 ? "\(h.hour ?? 0) Uhr" : uhr(k.start)) ändert das nichts."
    }

    static func wegArt(fussMin: Int, bisMin: Double) -> Bool { Double(fussMin) <= bisMin }

    static func handlung(_ e: KalEntwurf) -> [String: JSONWert] {
        var w: [String: JSONWert] = ["titel": .text(e.titel), "start": .zahl(e.start), "ende": .zahl(e.ende), "kalender": .text(e.kalender)]
        if !e.ort.isEmpty { w["ort"] = .text(e.ort) }
        if let g = e.weg { w["weg"] = .objekt(KalWeg.wert(g)) }
        return w
    }
}
