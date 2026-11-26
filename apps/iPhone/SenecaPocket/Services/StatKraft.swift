import Foundation

struct StatKraftTraining: Equatable, Identifiable {
    var tag: String
    var saetze: [StatSatz]
    var id: String { tag }
}

struct StatKraftZeile: Equatable, Identifiable {
    var id: String
    var name: String
    var werte: [Double]
    var text: String
}

struct StatKraftSeite: Equatable {
    var werte: [StatWert]
    var wochenKg: [Double]
    var wochenNamen: [String]
    var uebungen: [StatKraftZeile]
    var leer: String?
}

struct StatKraftLinie: Equatable {
    var schwer: [StatXY]
    var schaetzung: [StatXY]
    var schwerName: String
    var einheit: String
    var links: String
    var rechts: String
}

struct StatKraftListenZeile: Equatable, Identifiable {
    var id: String
    var tag: String
    var text: String
}

struct StatUebungSeite: Equatable {
    var name: String
    var satz: String
    var linie: StatKraftLinie?
    var hinweis: String?
    var bestwerte: [String]
    var liste: [StatKraftListenZeile]
}

struct StatKraftBest: Equatable {
    var schwerster: StatSatz?
    var meisteWdh: StatSatz?
    var schaetzung: StatSatz?
    var schaetzungWert: Double?
}

enum StatKraft {
    static func schluessel(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }

    static func epley(kg: Double, wdh: Int) -> Double? {
        guard kg > 0, wdh >= 1, wdh <= 12 else { return nil }
        return kg * (1 + Double(wdh) / 30)
    }

    static func runden(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    static func rundenHalb(_ v: Double) -> Double { (v * 2).rounded() / 2 }
    static func kgText(_ v: Double) -> String { StatFormat.kg(runden(v)) }

    static func koerperGewicht(am tag: String, _ gewicht: [String: Double]) -> Double? {
        guard let k = gewicht.keys.filter({ $0 <= tag }).max() else { return nil }
        return gewicht[k]
    }

    static func bewegt(_ s: StatSatz, koerper gewicht: [String: Double]) -> Double {
        if s.kg > 0 { return s.kg * Double(s.wdh) }
        guard s.kg < 0, let k = koerperGewicht(am: s.datum, gewicht), k + s.kg > 0 else { return 0 }
        return (k + s.kg) * Double(s.wdh)
    }

    static func nurUnterstuetzung(_ kgs: [Double]) -> Bool { !kgs.isEmpty && kgs.allSatisfy { $0 <= 0 } && kgs.contains { $0 < 0 } }

    static func trainings(_ name: String, _ d: StatDaten) -> [StatKraftTraining] {
        let key = schluessel(name)
        var nachTag: [String: [(Int, StatSatz)]] = [:]
        for (i, s) in d.saetze.enumerated() where schluessel(d.name(s)) == key { nachTag[s.datum, default: []].append((i, s)) }
        return nachTag.keys.sorted().map { tag in
            let s = nachTag[tag]!.sorted { ($0.1.erfasst ?? .distantPast, $0.0) < ($1.1.erfasst ?? .distantPast, $1.0) }
            return StatKraftTraining(tag: tag, saetze: s.map(\.1))
        }
    }

    static func koerpergewicht(_ ts: [StatKraftTraining]) -> Bool {
        let alle = ts.flatMap(\.saetze)
        return !alle.isEmpty && alle.allSatisfy { $0.kg == 0 }
    }

    static func schwerster(_ s: [StatSatz], koerper: Bool) -> StatSatz? {
        var best: StatSatz?
        for x in s {
            guard let b = best else { best = x; continue }
            if koerper ? (x.wdh, x.kg) > (b.wdh, b.kg) : (x.kg, x.wdh) > (b.kg, b.wdh) { best = x }
        }
        return best
    }

    static func bestwerte(_ ts: [StatKraftTraining]) -> StatKraftBest {
        var b = StatKraftBest()
        let hatMinus = ts.contains { $0.saetze.contains { $0.kg < 0 } }
        for t in ts {
            for s in t.saetze {
                if s.kg != 0 || hatMinus, b.schwerster == nil || (s.kg, s.wdh) > (b.schwerster!.kg, b.schwerster!.wdh) { b.schwerster = s }
                if b.meisteWdh == nil || (s.wdh, s.kg) > (b.meisteWdh!.wdh, b.meisteWdh!.kg) { b.meisteWdh = s }
                if let e = epley(kg: s.kg, wdh: s.wdh), e > (b.schaetzungWert ?? 0) { b.schaetzung = s; b.schaetzungWert = e }
            }
        }
        return b
    }

    static func satzText(_ s: [StatSatz]) -> String {
        var gruppen: [(kg: Double, wdh: [Int])] = []
        for x in s {
            if let l = gruppen.last, l.kg == x.kg { gruppen[gruppen.count - 1].wdh.append(x.wdh) } else { gruppen.append((x.kg, [x.wdh])) }
        }
        return gruppen.map { g in
            g.kg != 0 ? "\(StatFormat.kg(g.kg)) kg × " + g.wdh.map(String.init).joined(separator: " · ")
                     : g.wdh.map(String.init).joined(separator: " · ") + " Wiederholungen"
        }.joined(separator: ", ")
    }

    static func veraenderung(_ ts: [StatKraftTraining], koerper: Bool) -> String {
        guard let erst = ts.first.flatMap({ schwerster($0.saetze, koerper: koerper) }),
              let jetzt = ts.last.flatMap({ schwerster($0.saetze, koerper: koerper) }) else { return "" }
        func w(_ s: StatSatz) -> String { koerper ? String(s.wdh) : StatFormat.kg(s.kg) }
        let einheit = koerper ? "Wdh." : "kg"
        let a = koerper ? Double(erst.wdh) : erst.kg, z = koerper ? Double(jetzt.wdh) : jetzt.kg
        return ts.count < 2 || a == z ? "\(w(jetzt)) \(einheit)" : "\(w(erst)) → \(w(jetzt)) \(einheit)"
    }

    static func zeitraum(tage: Int) -> String {
        if tage <= 1 { return "gestern" }
        if tage < 7 { return "vor \(StatFormat.zahlwort(tage, gross: false)) Tagen" }
        if tage < 56 {
            let w = tage / 7
            return w == 1 ? "vor einer Woche" : "vor \(StatFormat.zahlwort(w, gross: false)) Wochen"
        }
        if tage < 350 {
            let m = max(2, Int((Double(tage) / 30.4).rounded()))
            return m >= 12 ? "vor einem Jahr" : "vor \(StatFormat.zahlwort(m, gross: false)) Monaten"
        }
        let j = max(1, Int((Double(tage) / 365.25).rounded()))
        return j == 1 ? "vor einem Jahr" : "vor \(StatFormat.zahlwort(j, gross: false)) Jahren"
    }

    static func satz(name: String, _ ts: [StatKraftTraining], koerper: Bool, heute: String) -> String {
        guard let erst = ts.first.flatMap({ schwerster($0.saetze, koerper: koerper) }),
              let jetzt = ts.last.flatMap({ schwerster($0.saetze, koerper: koerper) }), ts.count >= 2 else {
            guard let s = ts.first.flatMap({ schwerster($0.saetze, koerper: koerper) }) else { return "\(name): noch kein Training." }
            return "\(name): erst *ein Training*, bester Satz \(satzText([s]))."
        }
        let zeit = zeitraum(tage: StatKalender.abstand(ts[0].tag, heute))
        if koerper {
            let d = jetzt.wdh - erst.wdh
            if d == 0 { return "\(name): *gleich viele Wiederholungen* wie \(zeit)." }
            let n = abs(d)
            return "\(name): *\(n) \(n == 1 ? "Wiederholung" : "Wiederholungen") \(d > 0 ? "mehr" : "weniger")* als \(zeit)."
        }
        let d = jetzt.kg - erst.kg
        if abs(d) < 0.005 { return "\(name): *gleiches Gewicht* wie \(zeit)." }
        if erst.kg <= 0, jetzt.kg <= 0 {
            return "\(name): *\(StatFormat.kg(abs(d))) kg \(d > 0 ? "weniger" : "mehr") Unterstützung* als \(zeit)."
        }
        return "\(name): *\(StatFormat.kg(abs(d))) kg \(d > 0 ? "mehr" : "weniger")* als \(zeit)."
    }

    static func uebungsNamen(_ d: StatDaten) -> [(key: String, name: String)] {
        var zuletzt: [String: (stand: (String, Date), name: String)] = [:]
        for s in d.saetze {
            let k = schluessel(d.name(s))
            let stand = (s.datum, s.erfasst ?? .distantPast)
            if let alt = zuletzt[k], alt.stand >= stand { continue }
            zuletzt[k] = (stand, d.name(s))
        }
        return zuletzt.sorted { ($0.value.stand.0, $0.value.stand.1, $1.key) > ($1.value.stand.0, $1.value.stand.1, $0.key) }
            .map { ($0.key, $0.value.name) }
    }

    static func seite(_ q: StatQuellen) -> StatKraftSeite {
        let d = q.daten, h = q.heute
        guard !d.saetze.isEmpty else {
            return StatKraftSeite(werte: [], wochenKg: [], wochenNamen: [], uebungen: [], leer: StatAbschnitte.leerTraining)
        }
        func kg(_ von: String, _ bis: String) -> Double {
            d.saetze.filter { $0.datum >= von && $0.datum <= bis }.reduce(0) { $0 + bewegt($1, koerper: q.gewichtHealth) }
        }
        let tage = Set(d.saetze.map(\.datum))
        let von4 = StatKalender.plus(h, tage: -27)
        let proWoche = Double(tage.filter { $0 >= von4 && $0 <= h }.count) / 4
        let werte = [StatWert(wert: StatFormat.zahl(proWoche, 1), name: "Trainings pro Woche, Ø der letzten 4 Wochen"),
                     StatWert(wert: "\(StatFormat.zahl((kg(von4, h) / 4).rounded())) kg", name: "bewegt pro Woche, Ø der letzten 4 Wochen")]
        let wochen = (0..<12).map { StatKalender.plus(StatKalender.wochenstart(h), tage: -7 * (11 - $0)) }
        let zeilen = uebungsNamen(d).map { u -> StatKraftZeile in
            let ts = trainings(u.name, d)
            let koerper = koerpergewicht(ts)
            let w = ts.compactMap { schwerster($0.saetze, koerper: koerper) }.map { koerper ? Double($0.wdh) : $0.kg }
            return StatKraftZeile(id: u.key, name: u.name, werte: w, text: veraenderung(ts, koerper: koerper))
        }
        return StatKraftSeite(werte: werte, wochenKg: wochen.map { kg($0, StatKalender.plus($0, tage: 6)) },
                              wochenNamen: wochen.map { String(StatKalender.kalenderwoche($0)) }, uebungen: zeilen, leer: nil)
    }

    static func uebung(_ key: String, _ q: StatQuellen) -> StatUebungSeite? {
        let d = q.daten, h = q.heute
        guard let u = uebungsNamen(d).first(where: { $0.key == schluessel(key) }) else { return nil }
        let ts = trainings(u.name, d)
        guard !ts.isEmpty else { return nil }
        let koerper = koerpergewicht(ts)
        let satzTitel = satz(name: u.name, ts, koerper: koerper, heute: h)

        var linie: StatKraftLinie?
        var hinweis: String?
        if ts.count >= 2 {
            let spanne = Double(max(1, StatKalender.abstand(ts[0].tag, ts[ts.count - 1].tag)))
            func x(_ t: StatKraftTraining) -> Double { Double(StatKalender.abstand(ts[0].tag, t.tag)) / spanne }
            let schwer = ts.compactMap { t in schwerster(t.saetze, koerper: koerper).map { StatXY(x: x(t), y: koerper ? Double($0.wdh) : $0.kg) } }
            let schaetz: [StatXY] = koerper ? [] : ts.compactMap { t in
                t.saetze.compactMap { epley(kg: $0.kg, wdh: $0.wdh) }.max().map { StatXY(x: x(t), y: rundenHalb($0)) }
            }
            linie = StatKraftLinie(schwer: schwer, schaetzung: schaetz.count >= 2 ? schaetz : [],
                                   schwerName: koerper ? "Wiederholungen im besten Satz" : "schwerster Satz",
                                   einheit: koerper ? "Wdh." : "kg",
                                   links: StatFormat.datumLang(ts[0].tag), rechts: StatFormat.datumLang(ts[ts.count - 1].tag))
        } else {
            hinweis = "Ab dem zweiten Training zeigt sich hier der Verlauf."
        }

        let b = bestwerte(ts)
        var best: [String] = []
        if !koerper, let s = b.schwerster {
            let titel = s.kg <= 0 ? "Wenigste Unterstützung" : "Schwerster Satz"
            let satz = s.kg == 0 ? "ohne Hilfe × \(s.wdh)" : "\(StatFormat.kg(s.kg)) kg × \(s.wdh)"
            best.append("\(titel) \(satz) am \(StatFormat.datumLang(s.datum))")
        }
        if let s = b.meisteWdh {
            best.append(koerper ? "Meiste Wiederholungen \(s.wdh) am \(StatFormat.datumLang(s.datum))"
                                : "Meiste Wiederholungen \(s.wdh) bei \(StatFormat.kg(s.kg)) kg am \(StatFormat.datumLang(s.datum))")
        }
        if let s = b.schaetzung, let e = b.schaetzungWert {
            best.append("Bestes geschätztes Maximum ca. \(StatFormat.kg(rundenHalb(e))) kg, aus \(StatFormat.kg(s.kg)) kg × \(s.wdh), am \(StatFormat.datumLang(s.datum))")
        }
        let liste = ts.reversed().map { StatKraftListenZeile(id: $0.tag, tag: StatFormat.datumMitTag($0.tag), text: satzText($0.saetze)) }
        return StatUebungSeite(name: u.name, satz: satzTitel, linie: linie, hinweis: hinweis, bestwerte: best, liste: liste)
    }
}
