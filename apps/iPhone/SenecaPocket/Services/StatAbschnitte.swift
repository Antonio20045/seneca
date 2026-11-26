import Foundation

enum StatAbschnitte {
    static func inhalt(_ z: StatZeitraum, _ q: StatQuellen, monatZurueck: Int = 0) -> StatInhalt {
        switch z {
        case .heute: return heute(q)
        case .woche: return woche(q)
        case .monat: return monat(q, zurueck: monatZurueck)
        case .jahr: return jahr(q)
        }
    }

    static func aufzaehlung(_ teile: [String]) -> String {
        switch teile.count {
        case 0: return ""
        case 1: return teile[0]
        default: return teile.dropLast().joined(separator: ", ") + " und " + teile.last!
        }
    }
    static func zeitText(_ minuten: Int) -> String { StatFormat.lesezeit(minuten) }

    static func lesezeitImBuch(_ d: StatDaten, _ b: StatBuch) -> Int {
        d.eintraege.filter { $0.istLesezeit && $0.buch == b.id }.reduce(0) { $0 + Int($1.wert.rounded()) }
    }

    static func leseZielBalken(_ ziel: StatLeseZiel?, zeitraum: String, gelesen: Int) -> StatFortschritt? {
        guard let z = ziel, z.zeitraum == zeitraum else { return nil }
        let name = zeitraum == "tag" ? "Tagesziel" : zeitraum == "woche" ? "Wochenziel" : "Monatsziel"
        let rest = z.minuten - gelesen
        return StatFortschritt(anteil: min(1, Double(gelesen) / Double(z.minuten)), links: zeitText(gelesen),
                               rechts: rest > 0 ? "\(name) \(zeitText(z.minuten)), noch \(zeitText(rest))" : "\(name) \(zeitText(z.minuten)) erreicht")
    }

    static func tagesZielText(_ ziel: StatLeseZiel?, t: StatTage, tage: [String]) -> String? {
        guard let z = ziel, z.zeitraum == "tag", !tage.isEmpty else { return nil }
        let erreicht = tage.filter { (t.lesezeit[$0] ?? 0) >= z.minuten }.count
        return "Tagesziel \(zeitText(z.minuten)) an \(erreicht) von \(tage.count) \(tage.count == 1 ? "Tag" : "Tagen") erreicht"
    }

    static let leerLaufen = "Noch kein Lauf in Apple Health. Sobald Nike Run Club einen Lauf dorthin schreibt, erscheint er hier."
    static let leerLesen = "Noch kein Buch. Tippe auf das Plus, trag deine erste Lesesitzung ein und nenne den Titel."
    static let leerTraining = "Noch kein Training. Tippe auf Training starten und trag den ersten Satz ein."
    static let leerGewicht = "Noch kein Gewicht. Trag es in Apple Health ein, dann erscheint es hier."

    static func tempoText(_ tempo: Double) -> String {
        let v = (abs(tempo) * 100).rounded() / 100
        return (tempo > 0.004 ? "+" : "") + StatFormat.kg(v)
    }

    static func intensitaetKm(_ km: Double) -> Int { km <= 0 ? 0 : km < 3.5 ? 1 : km < 5.5 ? 2 : km < 8 ? 3 : 4 }
    static func intensitaetLesen(_ minuten: Int) -> Int { minuten <= 0 ? 0 : minuten < 15 ? 1 : minuten < 30 ? 2 : minuten < 60 ? 3 : 4 }

    static func hauptuebung(_ saetze: [StatSatz], _ d: StatDaten) -> String? {
        var anzahl: [String: Int] = [:], zuletzt: [String: String] = [:]
        for s in saetze {
            let n = d.name(s)
            anzahl[n, default: 0] += 1
            zuletzt[n] = max(zuletzt[n] ?? "", s.datum)
        }
        return anzahl.max { ($0.value, zuletzt[$0.key] ?? "", $0.key) < ($1.value, zuletzt[$1.key] ?? "", $1.key) }?.key
    }

    static func schwersterSatz(_ s: [StatSatz]) -> StatSatz? {
        s.max { ($0.kg, $0.wdh) < ($1.kg, $1.wdh) }
    }
    static func satzText(_ s: StatSatz) -> String {
        s.kg != 0 ? "\(StatFormat.kg(s.kg)) kg × \(s.wdh)" : "\(s.wdh) Wiederholungen"
    }

    static func tageDerUebung(_ name: String, _ q: StatQuellen) -> [(tag: String, saetze: [StatSatz])] {
        let alle = q.daten.saetze.filter { q.daten.name($0) == name }
        return Dictionary(grouping: alle, by: \.datum).map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    static func heute(_ q: StatQuellen) -> StatInhalt {
        let t = StatTage(q)
        let h = q.heute
        let d = q.daten
        let monatsStart = StatKalender.monatsStart(h, versatz: 0)
        var abschnitte: [StatAbschnitt] = []

        let laeufeHeute = (t.laeufe[h] ?? []).sorted { $0.start < $1.start }
        let kmHeute = laeufeHeute.reduce(0) { $0 + $1.km }
        let lesenHeute = t.lesezeit[h] ?? 0
        let saetzeHeute = t.saetze[h] ?? []

        var teile: [String] = []
        if kmHeute > 0 { teile.append("*\(StatFormat.zahl(kmHeute, 1)) km* gelaufen") }
        if lesenHeute > 0 { teile.append("\(zeitText(lesenHeute)) gelesen") }
        if !saetzeHeute.isEmpty { teile.append("\(saetzeHeute.count) \(saetzeHeute.count == 1 ? "Satz" : "Sätze") trainiert") }
        let titel = teile.isEmpty ? "Heute noch nichts eingetragen." : "Heute " + aufzaehlung(teile) + "."

        if let lauf = laeufeHeute.last {
            let monat = t.laeufeIm(von: monatsStart, bis: StatKalender.plus(StatKalender.monatsStart(h, versatz: 1), tage: -1))
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen · \(StatFormat.uhr(lauf.start)) Uhr",
                                            visuals: [.laufKarte(laufKarte(lauf, imMonat: monat))], ziel: .laufen))
        } else if q.laeufe.isEmpty {
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen", titel: nil, details: [StatDetail(text: leerLaufen)], ziel: .laufen))
        }

        var lesen = StatAbschnitt(id: "lesen", label: "Lesen", plus: .lesen)
        if let b = d.aktuellesBuch {
            let gesamt = lesezeitImBuch(d, b)
            if lesenHeute > 0 {
                lesen.titel = "\(zeitText(lesenHeute)) in *\(b.titel)*."
                if gesamt > lesenHeute { lesen.details = [StatDetail(text: "Insgesamt \(zeitText(gesamt)) in diesem Buch")] }
            } else {
                lesen.titel = "Heute noch nicht gelesen."
                lesen.details = [StatDetail(text: gesamt > 0 ? "Du liest *\(b.titel)*, bisher \(zeitText(gesamt))." : "Du liest *\(b.titel)*.")]
            }
            lesen.ziel = .buecher
        } else if lesenHeute > 0 {
            lesen.titel = "\(zeitText(lesenHeute)) gelesen."
            lesen.ziel = .buecher
        } else {
            lesen.details = [StatDetail(text: leerLesen)]
            lesen.ziel = .buecher
        }
        if let balken = leseZielBalken(d.leseZiel, zeitraum: "tag", gelesen: lesenHeute) { lesen.visuals = [.fortschritt(balken)] }
        abschnitte.append(lesen)

        var kraft = StatAbschnitt(id: "kraft", label: "Krafttraining", ziel: .kraft)
        kraft.aktion = "Training starten"
        if !saetzeHeute.isEmpty {
            let namen = Array(Set(saetzeHeute.map { d.name($0) })).sorted()
            kraft.titel = "*\(saetzeHeute.count) \(saetzeHeute.count == 1 ? "Satz" : "Sätze")* heute."
            var zeile = namen.joined(separator: ", ")
            if let dauer = trainingsMinuten(saetzeHeute) { zeile += " · \(dauer) Minuten" }
            kraft.details = [StatDetail(text: zeile)]
        } else if t.training.contains(h) {
            kraft.titel = "Heute *trainiert*."
        } else if let letzter = t.training.filter({ $0 < h }).max() {
            kraft.titel = "Heute kein Training."
            let s = t.saetze[letzter] ?? []
            var zeile = StatFormat.tagWortGross(letzter, heute: h)
            if !s.isEmpty {
                zeile += " \(s.count) \(s.count == 1 ? "Satz" : "Sätze")"
                if let m = trainingsMinuten(s) { zeile += " in \(m) Minuten" }
            }
            kraft.details = [StatDetail(text: zeile)]
        } else {
            kraft.details = [StatDetail(text: leerTraining)]
        }
        abschnitte.append(kraft)

        var gew = StatAbschnitt(id: "gewicht", label: "Gewicht")
        if let trend = t.trendBis(h) {
            if let heuteKg = t.gewicht[h] {
                gew.titel = "*\(StatFormat.zahl(heuteKg, 1)) kg* heute gewogen."
                gew.details = [StatDetail(text: "Trend \(StatFormat.zahl(trend, 1)) kg")]
            } else {
                gew.titel = "Trend *\(StatFormat.zahl(trend, 1)) kg*."
                if let letzter = t.gewicht.keys.filter({ $0 <= h }).max(), let kg = t.gewicht[letzter] {
                    gew.details = [StatDetail(text: "Zuletzt \(StatFormat.tagWort(letzter, heute: h)) gewogen, \(StatFormat.zahl(kg, 1)) kg")]
                }
            }
        } else {
            gew.details = [StatDetail(text: leerGewicht)]
        }
        abschnitte.append(gew)

        return StatInhalt(kopf: "\(StatKalender.wochentage[StatKalender.wochentag(h)]), \(StatFormat.datumLang(h))", titel: titel, abschnitte: abschnitte)
    }

    static func trainingsMinuten(_ saetze: [StatSatz]) -> Int? {
        let zeiten = saetze.compactMap(\.erfasst)
        guard let a = zeiten.min(), let b = zeiten.max() else { return nil }
        let m = Int((b.timeIntervalSince(a) / 60).rounded())
        return m >= 1 ? m : nil
    }

    static func laufKarte(_ l: StatLauf, imMonat: [StatLauf]) -> StatLaufKarte {
        var werte = [StatWert(wert: "\(StatFormat.zahl(l.km, 1)) km", name: "Strecke"),
                     StatWert(wert: StatFormat.dauer(l.dauer), name: "Zeit"),
                     StatWert(wert: StatFormat.pace(l.pace), name: "pro km")]
        if let a = l.aufstieg, a > 0 { werte.append(StatWert(wert: "\(StatFormat.zahl(a)) m", name: "bergauf")) }
        if let p = l.pulsMittel { werte.append(StatWert(wert: StatFormat.zahl(p), name: "Ø Puls")) }
        if let p = l.pulsMax { werte.append(StatWert(wert: StatFormat.zahl(p), name: "max Puls")) }

        var zeilen: [StatKmZeile] = []
        var satz: [String] = []
        if let km = l.kmZeiten, km.count >= 2 {
            let paces = km.map(\.pace)
            let lo = paces.min()!, hi = paces.max()!
            let spanne = max(hi - lo, 1)
            let rangfolge = paces.enumerated().sorted { $0.element < $1.element }.map(\.offset)
            for (i, k) in km.enumerated() {
                let rang = rangfolge.firstIndex(of: i) ?? 0
                zeilen.append(StatKmZeile(label: k.label, zeit: StatFormat.pace(k.pace), laenge: 0.55 + 0.45 * (k.pace - lo) / spanne,
                                          rang: rang, ton: 0.45 + 0.27 * (1 - (k.pace - lo) / spanne)))
            }
            let schnell = rangfolge[0]
            if km.count >= 3 {
                if schnell == km.count - 1 { satz.append("Schnellster Kilometer zum Schluss.") }
                else if schnell == 0 { satz.append("Schnellster Kilometer gleich zu Beginn.") }
                else if km[schnell].voll { satz.append("Schnellster Kilometer war der \(km[schnell].label).") }
            }
        }
        if imMonat.count >= 4 {
            let nachPace = imMonat.sorted { $0.pace < $1.pace }
            let nachKm = imMonat.sorted { $0.km > $1.km }
            let rang = (nachPace.firstIndex { $0.id == l.id } ?? 99) + 1
            if rang == 1 { satz.append("Schnellster Lauf in diesem Monat.") }
            else if rang == 2 { satz.append("Zweitschnellster Lauf in diesem Monat.") }
            else if rang == 3 { satz.append("Drittschnellster Lauf in diesem Monat.") }
            else if nachKm.first?.id == l.id { satz.append("Längster Lauf in diesem Monat.") }
        }
        return StatLaufKarte(uhrzeit: StatFormat.uhr(l.start), werte: werte, kmZeilen: zeilen, satz: satz.isEmpty ? nil : satz.joined(separator: " "))
    }

    static func woche(_ q: StatQuellen) -> StatInhalt {
        let t = StatTage(q)
        let h = q.heute
        let d = q.daten
        let start = StatKalender.wochenstart(h)
        let tage = (0..<7).map { StatKalender.plus(start, tage: $0) }
        let ende = tage[6]
        let vergangen = max(1, min(7, StatKalender.abstand(start, h) + 1))
        var abschnitte: [StatAbschnitt] = []

        let wl = t.laeufeIm(von: start, bis: ende)
        if !wl.isEmpty {
            let km = wl.reduce(0) { $0 + $1.km }
            let zeit = wl.reduce(0) { $0 + $1.dauer }
            let weitester = wl.max { $0.km < $1.km }!
            let hoechster = tage.map { t.km[$0] ?? 0 }.max() ?? 1
            let balken = tage.enumerated().map { i, tag in
                StatBalken(tag: StatKalender.buchstaben[i], text: t.km[tag].map { StatFormat.zahl($0, 1) }, anteil: (t.km[tag] ?? 0) / max(hoechster, 0.1),
                           da: (t.km[tag] ?? 0) > 0, heute: tag == h)
            }
            var details = [StatDetail(text: "\(StatFormat.dauerLang(zeit)) · Ø \(StatFormat.pace(zeit / km)) pro km · am weitesten \(StatFormat.zahl(weitester.km, 1)) km am \(StatKalender.wochentage[StatKalender.wochentag(weitester.datum)])")]
            let davor = t.summeKm(von: StatKalender.plus(start, tage: -28), bis: StatKalender.plus(start, tage: -1))
            if davor > 0 {
                let diff = km - davor / 4
                let text = abs(diff) < 0.05 ? "So viel wie im Schnitt der letzten vier Wochen"
                    : "\(StatFormat.zahl(abs(diff), 1)) km \(diff > 0 ? "mehr" : "weniger") als im Schnitt der letzten vier Wochen"
                details.append(StatDetail(text: text, leise: true))
            }
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen",
                                            titel: "\(StatFormat.zahlwort(wl.count)) \(wl.count == 1 ? "Lauf" : "Läufe"), *\(StatFormat.zahl(km, 1)) km*.",
                                            visuals: [.tagesbalken(StatTagesbalken(balken: balken, leerKreis: true))], details: details, ziel: .laufen))
        } else if q.laeufe.isEmpty {
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen", details: [StatDetail(text: leerLaufen)], ziel: .laufen))
        } else {
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen", titel: "Diese Woche noch *kein Lauf*.", ziel: .laufen))
        }

        var lesen = StatAbschnitt(id: "lesen", label: "Lesen", ziel: .buecher, plus: .lesen)
        let wLesen = t.summeLesezeit(von: start, bis: ende)
        let leseTage = tage.filter { (t.lesezeit[$0] ?? 0) > 0 }.count
        let schnitt = Int((Double(wLesen) / Double(vergangen)).rounded())
        if let b = d.aktuellesBuch {
            lesen.titel = "Du liest *\(b.titel)*."
            let gesamt = lesezeitImBuch(d, b)
            if let balken = leseZielBalken(d.leseZiel, zeitraum: "woche", gelesen: wLesen) {
                lesen.visuals = [.fortschritt(balken)]
            }
            lesen.details.append(StatDetail(text: wLesen > 0
                ? "\(zeitText(wLesen)) an \(leseTage) \(leseTage == 1 ? "Tag" : "Tagen") · Ø \(zeitText(schnitt)) am Tag"
                : "Diese Woche noch nicht gelesen"))
            if gesamt > wLesen { lesen.details.append(StatDetail(text: "Insgesamt \(zeitText(gesamt)) in diesem Buch", leise: true)) }
        } else if wLesen > 0 {
            lesen.titel = "*\(zeitText(wLesen))* diese Woche."
            if let balken = leseZielBalken(d.leseZiel, zeitraum: "woche", gelesen: wLesen) { lesen.visuals = [.fortschritt(balken)] }
        } else {
            lesen.details = [StatDetail(text: leerLesen)]
        }
        if let z = tagesZielText(d.leseZiel, t: t, tage: tage.filter { $0 <= h }) { lesen.details.append(StatDetail(text: z, leise: true)) }
        abschnitte.append(lesen)

        var kraft = StatAbschnitt(id: "kraft", label: "Krafttraining", ziel: .kraft)
        kraft.aktion = "Training starten"
        let trainingsTage = t.trainingsTage(von: start, bis: ende)
        let wSaetze = t.saetzeIm(von: start, bis: ende)
        if !trainingsTage.isEmpty {
            let n = trainingsTage.count
            kraft.titel = wSaetze.isEmpty ? "\(StatFormat.zahlwort(n)) \(n == 1 ? "Training" : "Trainings")."
                : "\(StatFormat.zahlwort(n)) \(n == 1 ? "Training" : "Trainings"), *\(wSaetze.count) \(wSaetze.count == 1 ? "Satz" : "Sätze")*."
            kraft.visuals = [.trainingPunkte(tage.enumerated().map { StatPunkt(tag: StatKalender.buchstaben[$0.offset], an: trainingsTage.contains($0.element), heute: $0.element == h) })]
            if let name = hauptuebung(wSaetze, d) {
                let alle = tageDerUebung(name, q)
                if let letzter = alle.last(where: { $0.tag >= start && $0.tag <= ende }), let top = schwersterSatz(letzter.saetze) {
                    var zeile = "\(name) \(satzText(top))"
                    if let davor = alle.last(where: { $0.tag < letzter.tag }), let vorher = schwersterSatz(davor.saetze) {
                        let wann = StatKalender.abstand(davor.tag, h) < 7 ? "am \(StatKalender.wochentage[StatKalender.wochentag(davor.tag)])" : "am \(StatFormat.datumLang(davor.tag))"
                        if top.kg != vorher.kg {
                            if top.kg <= 0, vorher.kg <= 0 {
                                zeile += ", das sind \(StatFormat.kg(abs(top.kg - vorher.kg))) kg \(top.kg > vorher.kg ? "weniger" : "mehr") Unterstützung als \(wann)"
                            } else {
                                zeile += ", das sind \(StatFormat.kg(abs(top.kg - vorher.kg))) kg \(top.kg > vorher.kg ? "mehr" : "weniger") als \(wann)"
                            }
                        } else if top.wdh != vorher.wdh {
                            let diff = abs(top.wdh - vorher.wdh)
                            zeile += ", das \(diff == 1 ? "ist eine Wiederholung" : "sind \(diff) Wiederholungen") \(top.wdh > vorher.wdh ? "mehr" : "weniger") als \(wann)"
                        } else {
                            zeile += ", genauso viel wie \(wann)"
                        }
                    }
                    kraft.details.append(StatDetail(text: zeile))
                }
            }
            let vol = StatTage.volumen(wSaetze, koerper: t.koerperHealth)
            if vol > 0 {
                var zeile = "\(StatFormat.zahl(vol)) kg bewegt"
                let vorWoche = StatTage.volumen(t.saetzeIm(von: StatKalender.plus(start, tage: -7), bis: StatKalender.plus(start, tage: -1)), koerper: t.koerperHealth)
                if vorWoche > 0 {
                    let pct = Int(((vol / vorWoche - 1) * 100).rounded())
                    zeile += pct == 0 ? ", so viel wie letzte Woche" : ", \(abs(pct)) % \(pct > 0 ? "mehr" : "weniger") als letzte Woche"
                }
                kraft.details.append(StatDetail(text: zeile, leise: true))
            }
        } else if t.training.isEmpty {
            kraft.details = [StatDetail(text: leerTraining)]
        } else {
            kraft.titel = "Diese Woche noch *kein Training*."
        }
        abschnitte.append(kraft)

        abschnitte.append(gewichtWoche(t, h: h, start: start, tage: tage))

        let kopf = "Woche \(StatKalender.kalenderwoche(start)) · \(StatFormat.datumLang(start)) bis \(StatFormat.datumLang(ende))"
        return StatInhalt(kopf: kopf, titel: nil, abschnitte: abschnitte)
    }

    static func gewichtWoche(_ t: StatTage, h: String, start: String, tage: [String]) -> StatAbschnitt {
        var gew = StatAbschnitt(id: "gewicht", label: "Gewicht")
        let ende = tage[6]
        guard let trend = t.trendBis(min(h, ende)) else {
            gew.details = [StatDetail(text: leerGewicht)]
            return gew
        }
        var titel = "Trend *\(StatFormat.zahl(trend, 1)) kg*"
        let vor = t.trendBis(StatKalender.plus(min(h, ende), tage: -7))
        if let vor {
            let diff = trend - vor
            titel += abs(diff) < 0.05 ? ", so viel wie vor einer Woche." : ", \(StatFormat.zahl(abs(diff), 1)) kg \(diff < 0 ? "weniger" : "mehr") als vor einer Woche."
        } else {
            titel += "."
        }
        gew.titel = titel
        var punkte: [StatXY] = [], linie: [StatXY] = []
        for (i, tag) in tage.enumerated() {
            let x = Double(i) / 6
            if let kg = t.gewicht[tag] { punkte.append(StatXY(x: x, y: kg)) }
            if let tr = t.trendNach[tag] { linie.append(StatXY(x: x, y: tr)) }
        }
        if !punkte.isEmpty || linie.count > 1 { gew.visuals = [.gewicht(StatGewichtDiagramm(punkte: punkte, trend: linie, hoehe: 96))] }
        var zeile: [String] = []
        if let kg = t.gewicht[h] { zeile.append("Heute gewogen \(StatFormat.zahl(kg, 1)) kg") }
        if let tempo = t.tempoBis(h) { zeile.append("Tempo \(tempoText(tempo)) kg pro Woche") }
        if !zeile.isEmpty { gew.details = [StatDetail(text: zeile.joined(separator: " · "))] }
        return gew
    }
}
