import Foundation

struct StatLaufZeile: Equatable, Identifiable {
    var id: String
    var tag: String
    var km: String
    var zeit: String
    var pace: String
}

struct StatLaufenSeite: Equatable {
    var untertitel: String
    var werte: [StatWert]
    var wochenKm: [Double]
    var wochenNamen: [String]
    var wochenPace: StatLinie?
    var bestwerte: [String]
    var liste: [StatLaufZeile]
    var leer: String?
}

struct StatAktuellesBuch: Equatable {
    var id: String
    var titel: String
    var autor: String?
    var seit: String
    var fortschritt: StatFortschritt?
    var schnitt: String?
    var tage: [StatBalken]
    var tageLinks: String
}

struct StatBuchZeile: Equatable, Identifiable {
    var id: String
    var titel: String
    var zeile: String
}

struct StatBuecherSeite: Equatable {
    var aktuell: StatAktuellesBuch?
    var listeLabel: String?
    var liste: [StatBuchZeile]
}

enum StatSeitenLogik {
    static func laufen(_ q: StatQuellen) -> StatLaufenSeite {
        let h = q.heute
        let alle = q.laeufe.sorted { $0.start > $1.start }
        let quellen = Array(Set(q.laeufe.map(\.quelle).filter { !$0.isEmpty })).sorted()
        let untertitel = "Aus \(quellen.isEmpty ? "" : StatAbschnitte.aufzaehlung(quellen) + " über ")Apple Health"
        guard !alle.isEmpty else {
            return StatLaufenSeite(untertitel: untertitel, werte: [], wochenKm: [], wochenNamen: [], wochenPace: nil, bestwerte: [], liste: [], leer: StatAbschnitte.leerLaufen)
        }
        let n = Double(alle.count)
        let km = alle.reduce(0) { $0 + $1.km }, zeit = alle.reduce(0) { $0 + $1.dauer }
        let werte = [StatWert(wert: "\(StatFormat.zahl(km / n, 1)) km", name: "Ø pro Lauf"),
                     StatWert(wert: StatFormat.dauerLang(zeit / n), name: "Ø Dauer"),
                     StatWert(wert: StatFormat.pace(zeit / km), name: "Ø pro km")]

        let t = StatTage(q)
        let wochen = (0..<12).map { StatKalender.plus(StatKalender.wochenstart(h), tage: -7 * (11 - $0)) }
        let wochenKm = wochen.map { t.summeKm(von: $0, bis: StatKalender.plus($0, tage: 6)) }
        let namen = wochen.map { String(StatKalender.kalenderwoche($0)) }
        var paceWerte: [Double] = [], paceXs: [Double] = []
        for (i, w) in wochen.enumerated() {
            let ls = t.laeufeIm(von: w, bis: StatKalender.plus(w, tage: 6))
            let k = ls.reduce(0) { $0 + $1.km }
            if k > 0 { paceWerte.append(ls.reduce(0) { $0 + $1.dauer } / k); paceXs.append(Double(i) / 11) }
        }
        let pace: StatLinie? = paceWerte.count >= 2
            ? StatLinie(werte: paceWerte, xs: paceXs, links: StatFormat.pace(paceWerte.first!), rechts: StatFormat.pace(paceWerte.last!), kleinerIstBesser: true) : nil

        var best: [String] = []
        if let weit = alle.max(by: { $0.km < $1.km }) { best.append("Längster Lauf \(StatFormat.zahl(weit.km, 1)) km am \(StatFormat.datumLang(weit.datum))") }
        if let f = StatLaufRechnen.schnellste5km(alle) { best.append("Schnellste 5 km \(StatFormat.dauer(f.sekunden)) am \(StatFormat.datumLang(f.lauf.datum))") }
        if let s = StatLaufRechnen.schnellsterKm(alle) { best.append("Schnellster Kilometer \(StatFormat.pace(s))") }

        let liste = alle.map { StatLaufZeile(id: $0.id, tag: StatFormat.datumMitTag($0.datum), km: "\(StatFormat.zahl($0.km, 1)) km", zeit: StatFormat.dauer($0.dauer), pace: StatFormat.pace($0.pace)) }
        return StatLaufenSeite(untertitel: untertitel, werte: werte, wochenKm: wochenKm, wochenNamen: namen, wochenPace: pace, bestwerte: best, liste: liste, leer: nil)
    }

    static func buecher(_ q: StatQuellen) -> StatBuecherSeite {
        let h = q.heute
        let d = q.daten
        let t = StatTage(q)
        var aktuell: StatAktuellesBuch?
        if let b = d.aktuellesBuch {
            let gesamt = StatAbschnitte.lesezeitImBuch(d, b)
            let tageSeit = max(1, StatKalender.abstand(b.begonnen, h) + 1)
            let proTag = Int((Double(gesamt) / Double(tageSeit)).rounded())
            let fortschritt: StatFortschritt? = nil
            let schnitt: String? = gesamt > 0
                ? "Insgesamt \(StatAbschnitte.zeitText(gesamt)) in diesem Buch" + (proTag > 0 ? ", im Schnitt \(StatAbschnitte.zeitText(proTag)) am Tag." : ".")
                : nil
            let fenster = min(tageSeit, 14)
            let ersterTag = StatKalender.plus(h, tage: -(fenster - 1))
            let tagWerte = (0..<fenster).map { i -> (String, Int) in
                let tag = StatKalender.plus(ersterTag, tage: i)
                let n = d.eintraege.filter { $0.istLesezeit && $0.datum == tag && $0.buch == b.id }.reduce(0) { $0 + Int($1.wert.rounded()) }
                return (tag, n)
            }
            let hoechster = max(1, tagWerte.map(\.1).max() ?? 1)
            let balken = tagWerte.map { StatBalken(tag: "", text: nil, anteil: Double($0.1) / Double(hoechster), da: $0.1 > 0, heute: $0.0 == h) }
            aktuell = StatAktuellesBuch(id: b.id, titel: b.titel, autor: b.autor,
                                        seit: "Seit \(StatFormat.datumLang(b.begonnen)), heute Tag \(tageSeit)",
                                        fortschritt: fortschritt, schnitt: schnitt, tage: balken, tageLinks: StatFormat.datumKurz(ersterTag))
        }
        _ = t
        let jahr = StatKalender.teile(h).j
        let fertig = d.buecher.filter { ($0.beendet ?? "").hasPrefix(String(jahr)) }.sorted { ($0.beendet ?? "") > ($1.beendet ?? "") }
        let liste = fertig.map { b -> StatBuchZeile in
            let tage = StatKalender.abstand(b.begonnen, b.beendet ?? h) + 1
            let gelesen = StatAbschnitte.lesezeitImBuch(d, b)
            var teile = ["\(StatFormat.datumKurz(b.begonnen)) bis \(StatFormat.datumKurz(b.beendet ?? h))", "\(tage) \(tage == 1 ? "Tag" : "Tage")"]
            if gelesen > 0 {
                teile.append(StatAbschnitte.zeitText(gelesen))
                teile.append("\(StatAbschnitte.zeitText(Int((Double(gelesen) / Double(tage)).rounded()))) pro Tag")
            }
            return StatBuchZeile(id: b.id, titel: b.titel, zeile: teile.joined(separator: " · "))
        }
        return StatBuecherSeite(aktuell: aktuell, listeLabel: liste.isEmpty ? nil : "Gelesen in \(jahr)", liste: liste)
    }
}

enum StatGym {
    static func uebungen(_ d: StatDaten, extra: [String] = []) -> [String] {
        var zuletzt: [String: (String, Date)] = [:]
        for s in d.saetze {
            let n = d.name(s)
            let stand = (s.datum, s.erfasst ?? .distantPast)
            if let alt = zuletzt[n], (alt.0, alt.1) >= stand { continue }
            zuletzt[n] = stand
        }
        var namen = zuletzt.keys.sorted { (zuletzt[$0]!.0, zuletzt[$0]!.1, $1) > (zuletzt[$1]!.0, zuletzt[$1]!.1, $0) }
        for u in d.uebungen where !namen.contains(u.name) { namen.append(u.name) }
        for e in extra where !namen.contains(where: { $0.lowercased() == e.lowercased() }) { namen.insert(e, at: 0) }
        return namen
    }

    static func saetze(_ name: String, _ d: StatDaten, am tag: String) -> [StatSatz] {
        d.saetze.filter { $0.datum == tag && d.name($0).lowercased() == name.lowercased() }
            .sorted { ($0.erfasst ?? .distantPast) < ($1.erfasst ?? .distantPast) }
    }

    static func vorbelegung(_ name: String, _ d: StatDaten, heute: String) -> (kg: Double, wdh: Int) {
        let alle = d.saetze.filter { d.name($0).lowercased() == name.lowercased() }
            .sorted { ($0.datum, $0.erfasst ?? .distantPast) < ($1.datum, $1.erfasst ?? .distantPast) }
        if let s = alle.last { return (s.kg, s.wdh) }
        return (20, 8)
    }

    static func letztesMal(_ name: String, _ d: StatDaten, heute: String) -> String? {
        let frueher = d.saetze.filter { d.name($0).lowercased() == name.lowercased() && $0.datum < heute }
        guard let tag = frueher.map(\.datum).max() else { return nil }
        let s = frueher.filter { $0.datum == tag }.sorted { ($0.erfasst ?? .distantPast) < ($1.erfasst ?? .distantPast) }
        var gruppen: [(kg: Double, wdh: [Int])] = []
        for x in s {
            if let l = gruppen.last, l.kg == x.kg { gruppen[gruppen.count - 1].wdh.append(x.wdh) } else { gruppen.append((x.kg, [x.wdh])) }
        }
        let text = gruppen.map { g in
            g.kg != 0 ? "\(StatFormat.kg(g.kg)) kg × " + g.wdh.map(String.init).joined(separator: " · ")
                     : g.wdh.map(String.init).joined(separator: " · ") + " Wiederholungen"
        }.joined(separator: ", ")
        return "Letztes Mal \(StatFormat.tagWort(tag, heute: heute)) \(text)"
    }

    static func seit(_ d: StatDaten, heute: String) -> Date? {
        d.saetze.filter { $0.datum == heute }.compactMap(\.erfasst).min()
    }

    static func sortiert(_ d: StatDaten, extra: [String] = [], heute: String) -> [String] {
        var tage: [String: Set<String>] = [:], anzeige: [String: String] = [:]
        for s in d.saetze {
            let n = d.name(s), k = StatKraft.schluessel(n)
            tage[k, default: []].insert(s.datum)
            if anzeige[k] == nil { anzeige[k] = n }
        }
        func punkte(_ k: String) -> Double {
            (tage[k] ?? []).reduce(0) { $0 + 1 / (1 + Double(max(0, StatKalender.abstand($1, heute))) / 14) }
        }
        var namen = tage.keys.sorted {
            let a = punkte($0), b = punkte($1)
            if abs(a - b) > 1e-9 { return a > b }
            let la = tage[$0]!.max()!, lb = tage[$1]!.max()!
            return la != lb ? la > lb : $0 < $1
        }.map { anzeige[$0]! }
        var vorhanden = Set(namen.map(StatKraft.schluessel))
        for u in d.uebungen where !vorhanden.contains(StatKraft.schluessel(u.name)) { namen.append(u.name); vorhanden.insert(StatKraft.schluessel(u.name)) }
        var vorn: [String] = []
        for e in extra where !vorhanden.contains(StatKraft.schluessel(e)) { vorn.append(e); vorhanden.insert(StatKraft.schluessel(e)) }
        return vorn + namen
    }

    static func haeufig(_ d: StatDaten, extra: [String] = [], heute: String, limit: Int = 6) -> [String] {
        Array(sortiert(d, extra: extra, heute: heute).prefix(limit))
    }

    static func suche(_ text: String, in namen: [String]) -> [String] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return namen }
        func f(_ n: String) -> String { n.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let treffer = namen.filter { f($0).contains(q) }
        let anfang = treffer.filter { n in f(n).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(q) } }
        return anfang + treffer.filter { !anfang.contains($0) }
    }

    static func neuAnlegen(_ text: String, in namen: [String]) -> String? {
        let n = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !namen.contains(where: { StatKraft.schluessel($0) == StatKraft.schluessel(n) }) else { return nil }
        return n
    }

    static let kgGrenzen: ClosedRange<Double> = -300...1000

    static func kgParsen(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-").replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        var minus = false
        if t.hasPrefix("-") { minus = true; t.removeFirst() } else if t.hasPrefix("+") { t.removeFirst() }
        guard !t.isEmpty, t.filter({ $0 == "," || $0 == "." }).count <= 1,
              t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }), t.contains(where: \.isNumber) else { return nil }
        guard let v = Double(t.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let r = ((minus ? -v : v) * 100).rounded() / 100
        return kgGrenzen.contains(r) ? (r == 0 ? 0 : r) : nil
    }

    static func kgSchritt(_ kg: Double, _ schritt: Double) -> Double {
        let r = ((kg + schritt) * 100).rounded() / 100
        return min(kgGrenzen.upperBound, max(kgGrenzen.lowerBound, r == 0 ? 0 : r))
    }

    static func kgFeld(_ kg: Double) -> String {
        var s = String(format: "%.2f", abs(kg))
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        s = s.replacingOccurrences(of: ".", with: ",")
        return kg < -0.004 ? "\u{2212}" + s : s
    }

    static func kgVorzeichen(_ kg: Double) -> Double { kg == 0 ? 0 : -kg }
}

struct GymUhr: Codable, Equatable {
    var tag: String
    var start: Date
    var letzter: Date

    static let fortsetzung: TimeInterval = 4 * 3600

    func gilt(jetzt: Date, heute: String) -> Bool {
        tag == heute || (tag < heute && jetzt.timeIntervalSince(letzter) < GymUhr.fortsetzung)
    }

    static func eintragen(_ alt: GymUhr?, jetzt: Date, heute: String) -> GymUhr {
        if let a = alt, a.gilt(jetzt: jetzt, heute: heute) {
            return GymUhr(tag: a.tag, start: min(a.start, jetzt), letzter: jetzt)
        }
        return GymUhr(tag: heute, start: jetzt, letzter: jetzt)
    }

    static func stand(lokal: GymUhr?, daten: StatDaten, jetzt: Date, heute: String) -> (start: Date, letzter: Date, saetze: Int)? {
        let uhr = lokal.flatMap { $0.gilt(jetzt: jetzt, heute: heute) ? $0 : nil }
        let tage = Set([heute] + (uhr.map { [$0.tag] } ?? []))
        let saetze = daten.saetze.filter { tage.contains($0.datum) }
        guard !saetze.isEmpty else { return nil }
        let zeiten = (saetze.compactMap(\.erfasst) + (uhr.map { [$0.start, $0.letzter] } ?? [])).filter { $0 <= jetzt }
        guard let start = zeiten.min(), let letzter = zeiten.max() else { return nil }
        return (start, letzter, saetze.count)
    }

    static func pause(letzter: Date, jetzt: Date) -> TimeInterval { max(0, jetzt.timeIntervalSince(letzter)) }

    static func pauseText(_ sek: TimeInterval) -> String {
        let s = max(0, Int(sek))
        return s >= 3600 ? "\(s / 3600):" + String(format: "%02d:%02d", s % 3600 / 60, s % 60) : "\(s / 60):" + String(format: "%02d", s % 60)
    }

    static func trainingText(_ sek: TimeInterval) -> String {
        sek < 60 ? "Training gerade gestartet" : "Training seit \(StatFormat.stundenMinuten(sek))"
    }

    static let schluessel = "seneca.gymuhr"
    static func laden(_ u: UserDefaults = .standard) -> GymUhr? {
        u.data(forKey: schluessel).flatMap { try? JSONDecoder().decode(GymUhr.self, from: $0) }
    }
    static func speichern(_ uhr: GymUhr?, _ u: UserDefaults = .standard) {
        if let uhr, let d = try? JSONEncoder().encode(uhr) { u.set(d, forKey: schluessel) } else { u.removeObject(forKey: schluessel) }
    }
}
