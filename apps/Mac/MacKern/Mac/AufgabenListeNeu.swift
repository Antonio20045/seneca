import Foundation

enum AufgabenZustand: String, CaseIterable {
    case wartet
    case laeuft
    case brauchtDich = "braucht_dich"
    case haengt
    case fertig
    case abgebrochen

    var wort: String {
        switch self {
        case .wartet: "wartet"
        case .laeuft: "läuft"
        case .brauchtDich: "braucht dich"
        case .haengt: "hängt"
        case .fertig: "fertig"
        case .abgebrochen: "abgebrochen"
        }
    }

    var erledigt: Bool { self == .fertig || self == .abgebrochen }
}

struct Aufgabe: Equatable, Identifiable {
    struct Quelle: Equatable {
        var karte: String?
        var formular: String?
        var sitzung: String?
        var kette: String?
    }

    var id: String
    var titel: String
    var zustand: AufgabenZustand
    var wer: String?
    var agent: String?
    var bereichName: String?
    var projektName: String?
    var herkunft: String?
    var seit: Date?
    var blockiertGemeldet: Date?
    var begonnen: Date?
    var zuletzt: Date?
    var stand: String?
    var grund: String?
    var ergebnis: String?
    var hinweis: String?
    var abnahmeOffen = false
    var neu = false
    var modell: String?
    var teile: [Aufgabe] = []
    var quelle = Quelle()

    var vonAntonio: Bool { herkunft == "antonio" }

    var abschluss: Date? { seit ?? zuletzt ?? begonnen }
}

struct AufgabenZahlen: Equatable {
    var brauchtDich = 0, laeuft = 0, haengt = 0, wartet = 0, neuFertig = 0, neuAbgebrochen = 0, fertig48h = 0

    static func lies(_ q: [String: Any]) -> AufgabenZahlen {
        func n(_ k: String) -> Int { (q[k] as? NSNumber)?.intValue ?? 0 }
        return AufgabenZahlen(brauchtDich: n("braucht_dich"), laeuft: n("laeuft"), haengt: n("haengt"), wartet: n("wartet"),
                              neuFertig: n("neu_fertig"), neuAbgebrochen: n("neu_abgebrochen"), fertig48h: n("fertig_48h"))
    }
}

struct AufgabenZahlenJeHerkunft: Equatable {
    var antonio = AufgabenZahlen()
    var agent = AufgabenZahlen()
    var laeuft: Int { antonio.laeuft + agent.laeuft }
}

struct AufgabenAbschnitte: Equatable {
    var brauchtDich: [Aufgabe] = []
    var laeuft: [Aufgabe] = []
    var wartet: [Aufgabe] = []
    var neu: [Aufgabe] = []
    var zuletzt: [Aufgabe] = []

    static let zuletztStunden = 48

    init() {}

    init(_ aufgaben: [Aufgabe], jetzt: Date, zahlen: AufgabenZahlen? = nil) {
        self.zahlen = zahlen
        func vor(_ a: Date?, _ b: Date?) -> Bool { (a ?? .distantFuture) < (b ?? .distantFuture) }
        func nach(_ a: Date?, _ b: Date?) -> Bool { (a ?? .distantPast) > (b ?? .distantPast) }
        brauchtDich = aufgaben.filter { $0.zustand == .brauchtDich }.sorted { $0.seit == $1.seit ? $0.id < $1.id : vor($0.seit, $1.seit) }
        let haengend = aufgaben.filter { $0.zustand == .haengt }.sorted { Self.stehtSeit($0) == Self.stehtSeit($1) ? $0.id < $1.id : vor(Self.stehtSeit($0), Self.stehtSeit($1)) }
        let laufend = aufgaben.filter { $0.zustand == .laeuft }.sorted {
            let a = $0.begonnen ?? $0.seit, b = $1.begonnen ?? $1.seit
            return a == b ? $0.id < $1.id : nach(a, b)
        }
        laeuft = haengend + laufend
        wartet = aufgaben.filter { $0.zustand == .wartet }.sorted { $0.seit == $1.seit ? $0.id < $1.id : vor($0.seit, $1.seit) }
        let erledigt = aufgaben.filter { $0.zustand.erledigt }.sorted { $0.abschluss == $1.abschluss ? $0.id < $1.id : nach($0.abschluss, $1.abschluss) }
        neu = erledigt.filter(\.neu)
        let grenze = jetzt.addingTimeInterval(-Double(Self.zuletztStunden) * 3600)
        zuletzt = erledigt.filter { !$0.neu && ($0.abschluss.map { $0 >= grenze } ?? true) }
    }

    static func stehtSeit(_ a: Aufgabe) -> Date? { a.zuletzt ?? a.begonnen ?? a.seit }

    var haengt: Int { laeuft.filter { $0.zustand == .haengt }.count }
    var zahlen: AufgabenZahlen?
    var neuFertig: Int { zahlen?.neuFertig ?? neu.filter { $0.zustand == .fertig }.count }
    var neuAbgebrochen: Int { zahlen?.neuAbgebrochen ?? neu.filter { $0.zustand == .abgebrochen }.count }
    var anzahlBrauchtDich: Int { zahlen?.brauchtDich ?? brauchtDich.count }
    var anzahlHaengt: Int { zahlen?.haengt ?? haengt }
    var anzahlLaeuft: Int { zahlen?.laeuft ?? (laeuft.count - haengt) }
    var anzahlWartet: Int { zahlen?.wartet ?? wartet.count }
    var istRuhig: Bool { brauchtDich.isEmpty && laeuft.isEmpty && neu.isEmpty }
    var istLeer: Bool { istRuhig && wartet.isEmpty && zuletzt.isEmpty }

    private static func wort(_ n: Int) -> String {
        n == 1 ? "einer" : (n > 1 && n < HeuteLogik.zahlwort.count ? HeuteLogik.zahlwort[n].lowercased() : String(n))
    }

    var satz: (String, String) {
        var teile: [String] = []
        let b = anzahlBrauchtDich, h = anzahlHaengt, l = anzahlLaeuft, f = neuFertig, a = neuAbgebrochen
        if b > 0 { teile.append(b == 1 ? "einer braucht dich" : Self.wort(b) + " brauchen dich") }
        if l > 0 { teile.append(l == 1 ? "ein Auftrag läuft" : Self.wort(l) + " Aufträge laufen") }
        if h > 0 { teile.append(h == 1 ? "einer hängt" : Self.wort(h) + " hängen") }
        if f > 0 { teile.append(f == 1 ? "einer ist neu fertig" : Self.wort(f) + " sind neu fertig") }
        if a > 0 { teile.append(a == 1 ? "einer wurde abgebrochen" : Self.wort(a) + " wurden abgebrochen") }
        guard !teile.isEmpty else { return ("Gerade läuft ", "nichts für dich.") }
        if l == 0 { teile.insert("gerade läuft nichts", at: b > 0 ? 1 : 0) }
        let vorn = teile.dropLast().joined(separator: ", ")
        let kopf = vorn.isEmpty ? "" : vorn.prefix(1).uppercased() + vorn.dropFirst() + (teile.count > 2 ? ", " : " und ")
        let letzter = teile[teile.count - 1]
        return kopf.isEmpty ? ("", letzter.prefix(1).uppercased() + letzter.dropFirst() + ".") : (kopf, letzter + ".")
    }

    var zaehlzeile: String {
        var t: [String] = []
        let b = anzahlBrauchtDich, l = anzahlLaeuft, h = anzahlHaengt, w = anzahlWartet
        if b > 0 { t.append("\(b) \(b == 1 ? "braucht" : "brauchen") dich") }
        if l > 0 { t.append("\(l) \(l == 1 ? "läuft" : "laufen")") }
        if h > 0 { t.append("\(h) \(h == 1 ? "hängt" : "hängen")") }
        if w > 0 { t.append("\(w) \(w == 1 ? "wartet" : "warten")") }
        if neuFertig > 0 { t.append("\(neuFertig) neu fertig") }
        if neuAbgebrochen > 0 { t.append("\(neuAbgebrochen) abgebrochen") }
        return t.joined(separator: " · ")
    }
}

struct AufgabenListe: Equatable {
    var stand: Date?
    var gesehenBis: Date?
    var zahlen = AufgabenZahlen()
    var zahlenJeHerkunft: AufgabenZahlenJeHerkunft?
    var aufgaben: [Aufgabe] = []
    var antonio = AufgabenAbschnitte()
    var agenten = AufgabenAbschnitte()

    static func == (a: AufgabenListe, b: AufgabenListe) -> Bool {
        a.aufgaben == b.aufgaben && a.gesehenBis == b.gesehenBis && a.zahlen == b.zahlen && a.zahlenJeHerkunft == b.zahlenJeHerkunft
    }

    init(stand: Date? = nil, gesehenBis: Date? = nil, zahlen: AufgabenZahlen = AufgabenZahlen(), aufgaben: [Aufgabe] = [],
         zahlenJeHerkunft: AufgabenZahlenJeHerkunft? = nil, jetzt: Date = Date()) {
        self.stand = stand; self.gesehenBis = gesehenBis; self.zahlen = zahlen; self.aufgaben = aufgaben; self.zahlenJeHerkunft = zahlenJeHerkunft
        antonio = AufgabenAbschnitte(aufgaben.filter(\.vonAntonio), jetzt: jetzt, zahlen: zahlenJeHerkunft?.antonio)
        agenten = AufgabenAbschnitte(aufgaben.filter { !$0.vonAntonio }, jetzt: jetzt, zahlen: zahlenJeHerkunft?.agent)
    }

    func aufgabe(_ id: String) -> Aufgabe? {
        aufgaben.first { $0.id == id } ?? aufgaben.lazy.compactMap { $0.teile.first { t in t.id == id } }.first
    }

    func offeneArbeit(fuer agent: String? = nil) -> [Aufgabe] {
        var gesehen = Set<String>()
        var ausgabe: [Aufgabe] = []
        func zeige(_ a: Aufgabe) {
            let kennung = a.quelle.kette.map { "kette-" + $0 } ?? a.id
            if gesehen.insert(kennung).inserted { ausgabe.append(a) }
        }
        for a in aufgaben where !a.zustand.erledigt {
            let teile = a.teile.filter { !$0.zustand.erledigt }
            let auftragPasst = agent == nil || a.agent == agent
            let durchTeilErklaert = [.laeuft, .wartet].contains(a.zustand) && teile.contains { $0.zustand == a.zustand }
            if auftragPasst && !durchTeilErklaert { zeige(a) }
            for teil in teile where auftragPasst || teil.agent == agent {
                if teil.zustand != a.zustand || durchTeilErklaert || !auftragPasst { zeige(teil) }
            }
        }
        return ausgabe
    }

    func laeuftGerade(fuer agent: String) -> [Aufgabe] { offeneArbeit(fuer: agent) }

    var heuteSatz: (String, String) {
        let arbeit = offeneArbeit()
        let aktiv = arbeit.filter { $0.zustand == .laeuft }.count
        let wartet = arbeit.filter { $0.zustand == .wartet }.count
        return (aktiv == 1 ? "1 Arbeitsschritt läuft" : String(aktiv) + " Arbeitsschritte laufen",
                wartet == 1 ? ", 1 wartet." : ", " + String(wartet) + " warten.")
    }

    static func lies(_ daten: Data, jetzt: Date = Date(), kalender: Calendar = .current) -> AufgabenListe? {
        guard let wurzel = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any], let roh = wurzel["aufgaben"] as? [Any] else { return nil }
        let aufgaben = roh.compactMap { ($0 as? [String: Any]).flatMap { Aufgabe.lies($0, jetzt: jetzt, kalender: kalender) } }
        var z = AufgabenZahlen()
        if let q = wurzel["zahlen"] as? [String: Any] { z = AufgabenZahlen.lies(q) }
        var je: AufgabenZahlenJeHerkunft?
        if let q = wurzel["zahlen_je_herkunft"] as? [String: Any], let a = q["antonio"] as? [String: Any], let g = q["agent"] as? [String: Any] {
            je = AufgabenZahlenJeHerkunft(antonio: AufgabenZahlen.lies(a), agent: AufgabenZahlen.lies(g))
        }
        return AufgabenListe(stand: AufgabenZeit.lies(wurzel["stand"]), gesehenBis: AufgabenZeit.lies(wurzel["gesehen_bis"]), zahlen: z, aufgaben: aufgaben, zahlenJeHerkunft: je, jetzt: jetzt)
    }
}

enum AufgabenZeit {
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let isoBruch: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

    static func lies(_ wert: Any?) -> Date? {
        guard let s = wert as? String, !s.isEmpty else { return nil }
        return iso.date(from: s) ?? isoBruch.date(from: s) ?? TageslaufZeit.lies(s, heute: Date(), kalender: .current)
    }
}

extension Aufgabe {
    static func lies(_ d: [String: Any], jetzt: Date, kalender: Calendar, mitTeilen: Bool = true) -> Aufgabe? {
        func text(_ k: String) -> String? {
            let v: String?
            if let s = d[k] as? String { v = s } else if let n = d[k] as? NSNumber, !(d[k] is Bool) { v = n.stringValue } else { v = nil }
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            return t?.isEmpty == false ? t : nil
        }
        guard let id = text("id"), let titel = text("titel"), let z = text("zustand").flatMap(AufgabenZustand.init(rawValue:)) else { return nil }
        var a = Aufgabe(id: id, titel: titel, zustand: z)
        a.wer = text("wer"); a.agent = text("agent"); a.bereichName = text("bereich_name"); a.projektName = text("projekt_name")
        a.herkunft = text("herkunft")
        a.blockiertGemeldet = AufgabenZeit.lies(d["blockiert_gemeldet"])
        a.seit = AufgabenZeit.lies(d["seit"]); a.begonnen = AufgabenZeit.lies(d["begonnen"]); a.zuletzt = AufgabenZeit.lies(d["zuletzt"])
        a.stand = text("stand"); a.grund = text("grund"); a.ergebnis = text("ergebnis"); a.hinweis = text("hinweis"); a.modell = text("modell")
        a.abnahmeOffen = (d["abnahme_offen"] as? Bool) ?? false
        a.neu = (d["neu"] as? Bool) ?? false
        if let q = d["quelle"] as? [String: Any] {
            func s(_ k: String) -> String? { (q[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            a.quelle = Quelle(karte: s("karte"), formular: s("formular"), sitzung: s("sitzung"), kette: s("kette"))
        }
        if mitTeilen, let t = d["teile"] as? [Any] {
            a.teile = t.compactMap { ($0 as? [String: Any]).flatMap { lies($0, jetzt: jetzt, kalender: kalender, mitTeilen: false) } }
        }
        return a
    }

    func wasUndSeit(jetzt: Date, kalender: Calendar = .current) -> String {
        let start = (zustand == .laeuft || zustand == .haengt) ? (begonnen ?? seit) : seit
        return [wer, start.map { "seit " + ListenText.uhr($0, jetzt: jetzt, kalender: kalender) }].compactMap { $0 }.joined(separator: " · ")
    }

    func zusatz(jetzt: Date) -> (text: String, haengt: Bool)? {
        switch zustand {
        case .laeuft: return stand.map { ($0, false) }
        case .haengt:
            var t = "Blockiert"
            if let blockiertGemeldet {
                t += " gemeldet " + ListenText.uhr(blockiertGemeldet, jetzt: jetzt, kalender: .current)
            }
            if let g = grund { t += " · " + g }
            return (t, true)
        case .brauchtDich, .wartet, .abgebrochen: return grund.map { ($0, false) }
        case .fertig: return nil
        }
    }

    var teileZaehlzeile: String {
        guard !teile.isEmpty else { return "" }
        let reihe: [(AufgabenZustand, String, String)] = [(.laeuft, "läuft", "laufen"), (.haengt, "hängt", "hängen"), (.brauchtDich, "braucht dich", "brauchen dich"),
                                                          (.wartet, "wartet", "warten"), (.fertig, "fertig", "fertig"), (.abgebrochen, "abgebrochen", "abgebrochen")]
        var t = [teile.count == 1 ? "1 Teil" : "\(teile.count) Teile"]
        for (z, eins, viele) in reihe {
            let n = teile.filter { $0.zustand == z }.count
            if n > 0 { t.append("\(n) " + (n == 1 ? eins : viele)) }
        }
        return t.joined(separator: " · ")
    }

    func abschlussUhr(jetzt: Date, kalender: Calendar = .current) -> String {
        abschluss.map { ListenText.uhr($0, jetzt: jetzt, kalender: kalender) } ?? ""
    }
}
