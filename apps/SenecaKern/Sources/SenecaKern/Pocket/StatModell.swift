import Foundation

enum StatKalender {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = .current
        return c
    }()
    static let monate = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    static let monateKurz = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    static let wochentage = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    static let wochentageKurz = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let buchstaben = ["M", "D", "M", "D", "F", "S", "S"]

    static func tag(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
    static func schluessel(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func schluessel(jahr: Int, monat: Int, tag: Int) -> String { String(format: "%04d-%02d-%02d", jahr, monat, tag) }
    static func teile(_ s: String) -> (j: Int, m: Int, t: Int) {
        let p = s.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : (0, 0, 0)
    }
    static func plus(_ s: String, tage n: Int) -> String {
        guard let d = tag(s), let r = cal.date(byAdding: .day, value: n, to: d) else { return s }
        return schluessel(r)
    }
    static func abstand(_ von: String, _ bis: String) -> Int {
        guard let a = tag(von), let b = tag(bis) else { return 0 }
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
    static func wochentag(_ s: String) -> Int {
        guard let d = tag(s) else { return 0 }
        return (cal.component(.weekday, from: d) + 5) % 7
    }
    static func wochenstart(_ s: String) -> String { plus(s, tage: -wochentag(s)) }
    static func kalenderwoche(_ s: String) -> Int {
        guard let d = tag(s) else { return 0 }
        return cal.component(.weekOfYear, from: d)
    }
    static func tageImMonat(jahr: Int, monat: Int) -> Int {
        guard let d = cal.date(from: DateComponents(year: jahr, month: monat, day: 1, hour: 12)) else { return 30 }
        return cal.range(of: .day, in: .month, for: d)?.count ?? 30
    }
    static func tageImJahr(_ jahr: Int) -> Int { (1...12).reduce(0) { $0 + tageImMonat(jahr: jahr, monat: $1) } }
    static func monatsStart(_ s: String, versatz n: Int) -> String {
        let p = teile(s)
        let index = p.j * 12 + (p.m - 1) + n
        return schluessel(jahr: index / 12, monat: index % 12 + 1, tag: 1)
    }
    static func tagImJahr(_ s: String) -> Int { abstand(schluessel(jahr: teile(s).j, monat: 1, tag: 1), s) }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain = ISO8601DateFormatter()
    static func zeit(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }
    static func isoText(_ d: Date) -> String { iso.string(from: d) }
}

enum StatFormat {
    static func zahl(_ v: Double, _ stellen: Int = 0) -> String {
        let neg = v < 0 && abs(v) >= 0.5 * pow(10, -Double(stellen))
        let s = String(format: "%.\(stellen)f", abs(v))
        let teile = s.split(separator: ".", omittingEmptySubsequences: false)
        var ganz = ""
        for (i, c) in String(teile[0]).reversed().enumerated() {
            if i > 0 && i % 3 == 0 { ganz.append(".") }
            ganz.append(c)
        }
        ganz = String(ganz.reversed())
        let out = teile.count > 1 ? ganz + "," + teile[1] : ganz
        return neg ? "−" + out : out
    }
    static func kg(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return zahl(v.rounded(), 0) }
        if abs(v * 10 - (v * 10).rounded()) < 0.005 { return zahl(v, 1) }
        return zahl(v, 2)
    }
    static func pace(_ sek: Double) -> String {
        let s = max(0, Int(sek.rounded()))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    static func dauer(_ sek: Double) -> String {
        let s = max(0, Int(sek.rounded()))
        if s >= 3600 { return "\(s / 3600):" + String(format: "%02d:%02d", s % 3600 / 60, s % 60) }
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    static func lesezeit(_ minuten: Int) -> String {
        let m = max(0, minuten)
        if m < 60 { return "\(m) Min" }
        return m % 60 == 0 ? "\(m / 60) Std" : "\(m / 60) Std \(m % 60) Min"
    }
    static func dauerLang(_ sek: Double) -> String {
        let min = Int((sek / 60).rounded())
        return min >= 60 ? "\(min / 60) Std. \(min % 60) Min." : "\(min) Min."
    }
    static func stundenMinuten(_ sek: Double) -> String {
        let min = max(0, Int(sek / 60))
        return "\(min / 60):" + String(format: "%02d", min % 60)
    }
    static func uhr(_ d: Date) -> String {
        let c = StatKalender.cal.dateComponents([.hour, .minute], from: d)
        return "\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
    }
    static func zahlwort(_ n: Int, gross: Bool = true) -> String {
        let w = ["null", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"]
        guard (0...12).contains(n) else { return String(n) }
        return gross ? w[n].prefix(1).uppercased() + w[n].dropFirst() : w[n]
    }
    static func datumKurz(_ s: String) -> String {
        let p = StatKalender.teile(s)
        return "\(p.t). " + StatKalender.monateKurz[max(0, min(11, p.m - 1))]
    }
    static func datumLang(_ s: String) -> String {
        let p = StatKalender.teile(s)
        return "\(p.t). " + StatKalender.monate[max(0, min(11, p.m - 1))]
    }
    static func datumMitTag(_ s: String) -> String { StatKalender.wochentageKurz[StatKalender.wochentag(s)] + " " + datumKurz(s) }
    static func tagWort(_ s: String, heute: String) -> String {
        let d = StatKalender.abstand(s, heute)
        if d == 0 { return "heute" }
        if d == 1 { return "gestern" }
        if d > 1 && d < 7 { return StatKalender.wochentage[StatKalender.wochentag(s)] }
        return datumLang(s)
    }
    static func tagWortGross(_ s: String, heute: String) -> String {
        let w = tagWort(s, heute: heute)
        return w.prefix(1).uppercased() + w.dropFirst()
    }
}

struct StatEintrag: Equatable, Identifiable {
    var id: String
    var thema: String
    var wert: Double
    var datum: String
    var notiz: String? = nil
    var buch: String? = nil
    var erfasst: Date? = nil
    var einheit: String? = nil

    var istLesezeit: Bool { thema == "lesen" && einheit?.lowercased() != "seiten" }
}

struct StatBuch: Equatable, Identifiable {
    var id: String
    var titel: String
    var autor: String? = nil
    var begonnen: String
    var beendet: String? = nil
}

struct StatUebung: Equatable, Identifiable {
    var id: String
    var name: String
}

struct StatSatz: Equatable, Identifiable {
    var id: String
    var uebung: String
    var kg: Double
    var wdh: Int
    var datum: String
    var erfasst: Date? = nil
}

struct StatLeseZiel: Equatable {
    var minuten: Int
    var zeitraum: String
}

struct StatDaten: Equatable {
    var eintraege: [StatEintrag] = []
    var buecher: [StatBuch] = []
    var uebungen: [StatUebung] = []
    var saetze: [StatSatz] = []
    var leseZiel: StatLeseZiel? = nil

    static let leer = StatDaten()

    var aktuellesBuch: StatBuch? {
        buecher.filter { $0.beendet == nil }.max { ($0.begonnen, $0.id) < ($1.begonnen, $1.id) }
    }
    func buch(_ id: String?) -> StatBuch? { id.flatMap { i in buecher.first { $0.id == i } } }
    func name(_ satz: StatSatz) -> String { uebungen.first { $0.id == satz.uebung }?.name ?? satz.uebung }
    func eintraege(_ thema: String) -> [StatEintrag] { eintraege.filter { $0.thema == thema } }

    static func parse(_ json: [String: Any]) -> StatDaten {
        var d = StatDaten()
        for (i, e) in (json["eintraege"] as? [[String: Any]] ?? []).enumerated() {
            guard let thema = e["thema"] as? String, let wert = zahl(e["wert"]), wert.isFinite,
                  let datum = e["datum"] as? String, StatKalender.tag(datum) != nil else { continue }
            let id = (e["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "alt-\(thema)-\(datum)-\(wert)-\(i)"
            d.eintraege.append(StatEintrag(id: id, thema: thema, wert: wert, datum: datum, notiz: e["notiz"] as? String,
                                           buch: e["buch"] as? String, erfasst: StatKalender.zeit(e["erfasst"] as? String),
                                           einheit: e["einheit"] as? String))
        }
        for t in json["themen"] as? [[String: Any]] ?? [] where t["id"] as? String == "lesen" {
            guard (t["einheit"] as? String)?.lowercased() == "min", let m = zahl(t["ziel"]), m >= 1,
                  let zeitraum = t["zielZeitraum"] as? String, ["tag", "woche", "monat"].contains(zeitraum) else { continue }
            d.leseZiel = StatLeseZiel(minuten: Int(m.rounded()), zeitraum: zeitraum)
        }
        for b in json["buecher"] as? [[String: Any]] ?? [] {
            guard let id = b["id"] as? String, let titel = b["titel"] as? String,
                  let begonnen = b["begonnen"] as? String, StatKalender.tag(begonnen) != nil else { continue }
            let beendet = (b["beendet"] as? String).flatMap { StatKalender.tag($0) != nil ? $0 : nil }
            d.buecher.append(StatBuch(id: id, titel: titel, autor: b["autor"] as? String, begonnen: begonnen, beendet: beendet))
        }
        for u in json["uebungen"] as? [[String: Any]] ?? [] {
            guard let id = u["id"] as? String, let name = u["name"] as? String else { continue }
            d.uebungen.append(StatUebung(id: id, name: name))
        }
        for s in json["saetze"] as? [[String: Any]] ?? [] {
            guard let id = s["id"] as? String, let u = s["uebung"] as? String, let wdh = zahl(s["wdh"]),
                  let datum = s["datum"] as? String, StatKalender.tag(datum) != nil else { continue }
            d.saetze.append(StatSatz(id: id, uebung: u, kg: kgGueltig(zahl(s["kg"])), wdh: Int(wdh), datum: datum,
                                     erfasst: StatKalender.zeit(s["erfasst"] as? String)))
        }
        return d
    }

    static func kgGueltig(_ v: Double?) -> Double {
        guard let v, v.isFinite else { return 0 }
        return min(1000, max(-300, v))
    }

    static func zahl(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    func anwenden(_ op: StatOp, jetzt: Date) -> StatDaten {
        var d = self
        let p = op.params
        let heute = StatKalender.schluessel(jetzt)
        switch op.methode {
        case "seneca.statistik.eintragen":
            guard !d.eintraege.contains(where: { $0.id == op.id }), let thema = p["thema"] as? String, let wert = StatDaten.zahl(p["wert"]) else { return d }
            var buch = p["buch"] as? String
            if thema == "lesen", buch == nil { buch = d.aktuellesBuch?.id }
            d.eintraege.append(StatEintrag(id: op.id, thema: thema, wert: wert, datum: p["datum"] as? String ?? heute,
                                           notiz: p["notiz"] as? String, buch: buch, erfasst: jetzt))
        case "seneca.statistik.entfernen":
            d.eintraege.removeAll { $0.id == (p["id"] as? String ?? op.id) }
        case "seneca.statistik.buch":
            let id = p["id"] as? String ?? op.id
            switch p["aktion"] as? String ?? "" {
            case "beginnen":
                guard !d.buecher.contains(where: { $0.id == id }), let titel = p["titel"] as? String else { return d }
                let begonnen = p["datum"] as? String ?? heute
                if p["beendeAktuelles"] as? Bool == true, let aktuell = d.aktuellesBuch, let i = d.buecher.firstIndex(where: { $0.id == aktuell.id }) {
                    d.buecher[i].beendet = begonnen
                }
                d.buecher.append(StatBuch(id: id, titel: titel, autor: p["autor"] as? String, begonnen: begonnen))
            case "beenden":
                if let i = d.buecher.firstIndex(where: { $0.id == id }), d.buecher[i].beendet == nil { d.buecher[i].beendet = p["datum"] as? String ?? heute }
            case "aendern":
                guard let i = d.buecher.firstIndex(where: { $0.id == id }) else { return d }
                if let t = p["titel"] as? String { d.buecher[i].titel = t }
                if let a = p["autor"] as? String { d.buecher[i].autor = a.isEmpty ? nil : a }
                if let b = p["begonnen"] as? String { d.buecher[i].begonnen = b }
                if p["beendet"] is NSNull { d.buecher[i].beendet = nil } else if let b = p["beendet"] as? String { d.buecher[i].beendet = b }
            case "entfernen":
                d.buecher.removeAll { $0.id == id }
                d.eintraege = d.eintraege.map { var e = $0; if e.buch == id { e.buch = nil }; return e }
            default: break
            }
        case "seneca.statistik.satz":
            guard !d.saetze.contains(where: { $0.id == op.id }), let u = p["uebung"] as? String, let wdh = StatDaten.zahl(p["wdh"]) else { return d }
            d.saetze.append(StatSatz(id: op.id, uebung: u, kg: StatDaten.kgGueltig(StatDaten.zahl(p["kg"])), wdh: Int(wdh),
                                     datum: p["datum"] as? String ?? heute, erfasst: op.erfasst ?? jetzt))
        case "seneca.statistik.satz.entfernen":
            d.saetze.removeAll { $0.id == (p["id"] as? String ?? op.id) }
        default: break
        }
        return d
    }

    func anwenden(_ ops: [StatOp], jetzt: Date) -> StatDaten { ops.reduce(self) { $0.anwenden($1, jetzt: jetzt) } }
}
