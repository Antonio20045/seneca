import Foundation

enum StatZeitraum: String, CaseIterable { case woche = "Woche", monat = "Monat", jahr = "Jahr" }

enum StatBereich: String, CaseIterable, Identifiable {
    case laufen = "Laufen", kraft = "Krafttraining", lesen = "Lesen", koerper = "Körper"
    var id: String { rawValue }
}

struct StatWegWoche: Equatable { var iso: String; var km: Double; var lang: Double; var plan: Bool }
struct StatBestwert: Equatable { var name: String; var kg: Double; var wdh: Int; var rm: Double; var iso: String }
struct StatLaufWoche: Equatable { var iso: String; var km: Double; var tage: Int; var lang: Double }

enum StatistikLogik {
    static let monate = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    static let muskeln = ["Beine", "Rücken", "Brust", "Schultern", "Arme", "Rumpf"]
    private static let wochentage = ["MONTAG", "DIENSTAG", "MITTWOCH", "DONNERSTAG", "FREITAG", "SAMSTAG", "SONNTAG"]
    private static let kalender = Calendar(identifier: .gregorian)

    static func tag(_ iso: String) -> Date? {
        let t = iso.split(separator: "-").compactMap { Int($0) }
        return t.count == 3 ? kalender.date(from: DateComponents(year: t[0], month: t[1], day: t[2], hour: 12)) : nil
    }

    static func iso(_ d: Date) -> String {
        let c = kalender.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func datum(_ iso: String, lang: Bool = false) -> String {
        guard let d = tag(iso) else { return "" }
        let c = kalender.dateComponents([.year, .month, .day], from: d), m = monate[(c.month ?? 1) - 1]
        let jahr = c.year == kalender.component(.year, from: Date()) ? "" : " \(c.year ?? 0)"
        return "\(c.day ?? 0). " + (lang ? m : String(m.prefix(3))) + jahr
    }

    static func monatKurz(_ iso: String) -> String { tag(iso).map { String(monate[kalender.component(.month, from: $0) - 1].prefix(3)).uppercased() } ?? "" }

    static func woche(_ iso: String) -> String { tag(iso).map { "W\(Calendar(identifier: .iso8601).component(.weekOfYear, from: $0))" } ?? "" }

    static func zahl(_ d: Double, _ stellen: Int = 1) -> String {
        let r = (d * pow(10, Double(stellen))).rounded() / pow(10, Double(stellen))
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.\(stellen)f", r)).replacingOccurrences(of: ".", with: ",")
    }

    static func tempo(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s.rounded()) % 60) }

    static func abschnitt(_ s: SenecaStatistik.Kennzahlen.Eigene) -> StatBereich? {
        ["lauf": .laufen, "satz": .kraft, "lesen": .lesen, "nacht": .koerper, "tag": .koerper, "gewicht": .koerper][s.metrik?.split(separator: ".").first.map(String.init) ?? ""]
    }

    static func lebensbereich(_ s: SenecaStatistik.Kennzahlen.Eigene) -> String { s.bereich ?? (abschnitt(s) == nil ? "unternehmertum" : "wachstum") }

    static func stunden(_ h: Double) -> String { let m = Int((h * 60).rounded()); return String(format: "%d:%02d", m / 60, m % 60) }

    static func zeitraum(_ kopf: String, stand: Double) -> String {
        let t = kopf.components(separatedBy: " · ")
        let tage = (t.last ?? "").replacingOccurrences(of: ". bis ", with: ".–")
        return ([tage, t.first ?? ""] + ["Stand " + HeuteTafelLogik.uhr(stand)]).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func heuteSatz(_ z: SenecaStatistik.Zeile?) -> String? {
        guard let z, z.links.hasPrefix("HEUTE") else { return nil }
        return "Heute " + z.wert + (z.unter.isEmpty ? "." : ", \(z.unter).")
    }

    static func achtWochen(_ u: SenecaStatistik.Uebung) -> [SenecaStatistik.Punkt] { Array(u.wochen.suffix(8)) }

    static func karte(_ d: SenecaStatistik, _ art: String) -> SenecaStatistik.Karte? { d.woche.karten.first { $0.art == art } }

    static func summe(_ d: SenecaStatistik, _ z: StatZeitraum, _ bereich: String) -> [String]? {
        (z == .monat ? d.monat : z == .jahr ? d.jahr : nil)?.zahlen.first { $0.count == 3 && $0[2].hasPrefix(bereich) }
    }

    static func bestwerteJahr(_ j: SenecaStatistik.Raster) -> [[String]] { (j.bestwerte ?? []).filter { $0.count == 3 && !$0[1].contains("undefined") } }

    static func wochenZiel(_ k: SenecaStatistik.Kennzahlen) -> (lang: Double, km: Double)? {
        guard let r = k.lauf.aufbau.first(where: { $0.first?.alsText == k.wochen.last }), r.count == 3, let l = r[1].alsZahl, let km = r[2].alsZahl else { return nil }
        return (l, km)
    }

    static func letzterLauf(_ k: SenecaStatistik.Kennzahlen, _ l: SenecaStatistik.Lauf?) -> String? {
        guard let i = k.lauf.km.lastIndex(where: { $0 > 0 }), i < k.wochen.count, let montag = tag(k.wochen[i]) else { return nil }
        let versatz = wochentage.firstIndex { l?.kopf.contains($0) == true } ?? 0
        return kalender.date(byAdding: .day, value: versatz, to: montag).map(iso)
    }

    static func weg(_ k: SenecaStatistik.Kennzahlen) -> [StatWegWoche] {
        let vorbei = zip(k.wochen, zip(k.lauf.km, k.lauf.lang)).map { StatWegWoche(iso: $0, km: $1.0, lang: $1.1, plan: false) }
        let plan = k.lauf.aufbau.dropFirst().compactMap { r in r.count == 3 ? r[0].alsText.map { StatWegWoche(iso: $0, km: r[2].alsZahl ?? 0, lang: r[1].alsZahl ?? 0, plan: true) } : nil }
        return vorbei + plan
    }

    static func wegSatz(_ k: SenecaStatistik.Kennzahlen) -> String {
        guard let ziel = wochenZiel(k) else { return "Der Aufbau für die 100 km am Stück läuft Woche für Woche bis zum Lauf im Juni." }
        return "Diese Woche sieht der Aufbau \(zahl(ziel.km)) km vor, davon \(zahl(ziel.lang)) am Stück. Der lange Lauf wächst um 2 km je Woche, jede vierte Woche ist leichter."
    }

    static func laufWochen(_ k: SenecaStatistik.Kennzahlen, _ anzahl: Int) -> [StatLaufWoche] {
        k.wochen.indices.reversed().filter { k.lauf.km[$0] > 0 }.prefix(anzahl).map { StatLaufWoche(iso: k.wochen[$0], km: k.lauf.km[$0], tage: k.lauf.tage[$0], lang: k.lauf.lang[$0]) }
    }

    static func bestwerte(_ k: SenecaStatistik.Kennzahlen) -> [StatBestwert] {
        k.kraft.bestwerte.compactMap { n, r in
            guard r.count == 4, let rm = r[0].alsZahl, let iso = r[1].alsText, let kg = r[2].alsZahl, let w = r[3].alsZahl else { return nil }
            return StatBestwert(name: n, kg: kg, wdh: Int(w), rm: rm, iso: iso)
        }
        .sorted { ($0.iso, $0.rm) > ($1.iso, $1.rm) }
    }

    static func satz(_ d: SenecaStatistik, _ z: StatZeitraum) -> [String] {
        guard z == .woche, let k = d.kennzahlen else { return (z == .monat ? d.monat : d.jahr)?.satz ?? d.woche.satz }
        let km = k.lauf.km.last ?? 0, still = km == 0 && (k.kraft.tage.last ?? 0) == 0 && karte(d, "lesen")?.tage.allSatisfy { $0.zustand != "da" } != false
        let seit = [letzterLauf(k, d.lauf), bestwerte(k).first?.iso].compactMap { $0 }.max()
        let erst = still ? seit.map { "Seit dem \(datum($0, lang: true)) ist es still." } ?? "Eine stille Woche." : d.woche.satz.first ?? ""
        guard let ziel = wochenZiel(k) else { return [erst] }
        let zweit = km == 0 ? "Der Aufbau für die 100 km beginnt diese Woche mit \(zahl(ziel.lang)) km am Stück."
            : km >= ziel.km ? "Das Laufziel der Woche ist geschafft." : "Noch \(zahl(ziel.km - km)) km bis zu den \(zahl(ziel.km)) dieser Woche."
        return [erst, zweit]
    }

    static func nacht(_ k: SenecaStatistik.Kennzahlen, _ iso: String) -> [JSONWert]? { k.koerper.nacht.last { $0.first?.alsText == iso } }

    static func letzteTage(_ stand: Double, _ anzahl: Int) -> [String] {
        let heute = Date(timeIntervalSince1970: stand / 1000)
        return (0..<anzahl).reversed().compactMap { kalender.date(byAdding: .day, value: -$0, to: heute).map(iso) }
    }
}
