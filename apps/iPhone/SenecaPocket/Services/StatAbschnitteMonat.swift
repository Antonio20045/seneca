import Foundation

extension StatAbschnitte {
    static func monatsName(_ s: String) -> String { StatKalender.monate[max(0, min(11, StatKalender.teile(s).m - 1))] }

    static func fruehesterTag(_ q: StatQuellen) -> String? {
        let tage = q.laeufe.map(\.datum) + q.daten.eintraege.map(\.datum) + q.daten.saetze.map(\.datum) + q.daten.buecher.map(\.begonnen) + q.gewichtHealth.keys
        return tage.min()
    }

    static func staerke(_ saetze: [StatSatz]) -> (wert: Double, koerper: Bool)? {
        guard !saetze.isEmpty else { return nil }
        if saetze.contains(where: { $0.kg != 0 }) { return (saetze.map(\.kg).max() ?? 0, false) }
        return (Double(saetze.map(\.wdh).max() ?? 0), true)
    }
    static func staerkeText(_ v: Double, koerper: Bool) -> String { koerper ? "\(Int(v)) Wdh." : "\(StatFormat.kg(v)) kg" }

    static func monat(_ q: StatQuellen, zurueck: Int) -> StatInhalt {
        let t = StatTage(q)
        let h = q.heute
        let d = q.daten
        let ms = StatKalender.monatsStart(h, versatz: -zurueck)
        let p = StatKalender.teile(ms)
        let n = StatKalender.tageImMonat(jahr: p.j, monat: p.m)
        let me = StatKalender.schluessel(jahr: p.j, monat: p.m, tag: n)
        let laufend = zurueck == 0
        let bis = laufend ? h : me
        let vergangen = StatKalender.abstand(ms, bis) + 1
        let name = monatsName(ms)
        let vorMonat = StatKalender.monatsStart(ms, versatz: -1)
        let vorEnde = StatKalender.plus(ms, tage: -1)
        let versatz = StatKalender.wochentag(ms)
        var abschnitte: [StatAbschnitt] = []

        func raster(_ stufe: (String) -> Int) -> [StatZelle] {
            var z = [StatZelle](repeating: StatZelle(tag: nil, stufe: 0, zukunft: false), count: versatz)
            for i in 0..<n {
                let tag = StatKalender.plus(ms, tage: i)
                z.append(StatZelle(tag: i + 1, stufe: tag > h ? 0 : stufe(tag), zukunft: tag > h))
            }
            while z.count % 7 != 0 { z.append(StatZelle(tag: nil, stufe: 0, zukunft: false)) }
            return z
        }

        let ml = t.laeufeIm(von: ms, bis: me)
        if !ml.isEmpty {
            let km = ml.reduce(0) { $0 + $1.km }
            let kmText = km >= 100 ? StatFormat.zahl(km) : StatFormat.zahl(km, 1)
            var a = StatAbschnitt(id: "laufen", label: "Laufen",
                                  titel: "*\(ml.count) \(ml.count == 1 ? "Lauf" : "Läufe")* in \(vergangen) Tagen, \(kmText) km.", ziel: .laufen)
            a.visuals = [.monatsRaster(beschriftung: "Kalender \(name): an \(Set(ml.map(\.datum)).count) Tagen gelaufen", raster { intensitaetKm(t.km[$0] ?? 0) })]
            if let pause = laengstePause(von: ms, bis: bis, hat: { (t.km[$0] ?? 0) > 0 }) {
                a.details.append(StatDetail(text: pause))
            }
            if ml.count >= 2 {
                let zeit = ml.reduce(0) { $0 + $1.dauer }
                let schnitt = zeit / km
                var zeile = "Ø \(StatFormat.pace(schnitt)) pro km"
                let vm = t.laeufeIm(von: vorMonat, bis: vorEnde)
                if !vm.isEmpty {
                    let diff = vm.reduce(0) { $0 + $1.dauer } / vm.reduce(0) { $0 + $1.km } - schnitt
                    if abs(diff) >= 1 { zeile += ", \(Int(abs(diff).rounded())) Sekunden \(diff > 0 ? "schneller" : "langsamer") als im \(monatsName(vorMonat))" }
                }
                a.visuals.append(.linie(beschriftung: "Pace pro Lauf", StatLinie(werte: ml.map(\.pace), links: StatFormat.pace(ml.first!.pace), rechts: StatFormat.pace(ml.last!.pace), kleinerIstBesser: true)))
                a.details.append(StatDetail(text: zeile))
            }
            abschnitte.append(a)
        } else if q.laeufe.isEmpty {
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen", details: [StatDetail(text: leerLaufen)], ziel: .laufen))
        } else {
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen", titel: laufend ? "Diesen Monat noch *kein Lauf*." : "Im \(name) *kein Lauf*.", ziel: .laufen))
        }

        let gelesen = t.summeLesezeit(von: ms, bis: me)
        let beendet = d.buecher.filter { ($0.beendet ?? "") >= ms && ($0.beendet ?? "") <= me }.sorted { ($0.beendet ?? "") < ($1.beendet ?? "") }
        if gelesen > 0 {
            var titel = "*\(zeitText(gelesen))*"
            if !beendet.isEmpty { titel += ", \(beendet.count == 1 ? "ein Buch" : "\(StatFormat.zahlwort(beendet.count, gross: false)) Bücher") beendet" }
            var a = StatAbschnitt(id: "lesen", label: "Lesen", titel: titel + ".", ziel: .buecher)
            a.visuals = [.monatsRaster(beschriftung: "Kalender \(name): gelesen", raster { intensitaetLesen(t.lesezeit[$0] ?? 0) })]
            if let balken = leseZielBalken(d.leseZiel, zeitraum: "monat", gelesen: gelesen) { a.visuals.insert(.fortschritt(balken), at: 0) }
            let tageGelesen = (0..<vergangen).filter { (t.lesezeit[StatKalender.plus(ms, tage: $0)] ?? 0) > 0 }.count
            var teile = ["An \(tageGelesen) von \(vergangen) Tagen gelesen", "Ø \(zeitText(Int((Double(gelesen) / Double(vergangen)).rounded()))) am Tag"]
            for b in beendet { teile.append("*\(b.titel)* am \(StatKalender.teile(b.beendet ?? "").t). beendet") }
            a.details = [StatDetail(text: teile.joined(separator: " · "))]
            if let z = tagesZielText(d.leseZiel, t: t, tage: (0..<vergangen).map { StatKalender.plus(ms, tage: $0) }) { a.details.append(StatDetail(text: z, leise: true)) }
            abschnitte.append(a)
        } else if d.buecher.isEmpty && !d.eintraege.contains(where: { $0.thema == "lesen" }) {
            abschnitte.append(StatAbschnitt(id: "lesen", label: "Lesen", details: [StatDetail(text: leerLesen)], ziel: .buecher))
        } else {
            abschnitte.append(StatAbschnitt(id: "lesen", label: "Lesen", titel: laufend ? "Diesen Monat noch *nicht gelesen*." : "Im \(name) *nicht gelesen*.", ziel: .buecher))
        }

        let tage = t.trainingsTage(von: ms, bis: me)
        if !tage.isEmpty {
            let sat = t.saetzeIm(von: ms, bis: me)
            var zeilen: [(sitzungen: Int, zeile: StatUebungZeile, besser: Bool)] = []
            for uebung in Set(sat.map { d.name($0) }).sorted() {
                let proTag = Dictionary(grouping: sat.filter { d.name($0) == uebung }, by: \.datum).sorted { $0.key < $1.key }
                let werte = proTag.compactMap { staerke($0.value) }
                guard werte.count >= 2, let erster = werte.first, let letzter = werte.last else { continue }
                let koerper = letzter.koerper
                let text = erster.wert == letzter.wert ? staerkeText(letzter.wert, koerper: koerper)
                    : (koerper ? "\(Int(erster.wert)) → \(Int(letzter.wert)) Wdh." : "\(StatFormat.kg(erster.wert)) → \(StatFormat.kg(letzter.wert)) kg")
                zeilen.append((werte.count, StatUebungZeile(name: uebung, werte: werte.map(\.wert), text: text), letzter.wert > erster.wert))
            }
            zeilen.sort { ($0.sitzungen, $1.zeile.name) > ($1.sitzungen, $0.zeile.name) }
            let besser = zeilen.filter(\.besser).count
            var titel = "*\(tage.count) \(tage.count == 1 ? "Training" : "Trainings")*"
            if besser > 0 { titel += ", in \(StatFormat.zahlwort(besser, gross: false)) \(besser == 1 ? "Übung" : "Übungen") stärker" }
            var a = StatAbschnitt(id: "kraft", label: "Krafttraining", titel: titel + ".", ziel: .kraft)
            if !zeilen.isEmpty { a.visuals = [.uebungen(zeilen.prefix(4).map(\.zeile))] }
            abschnitte.append(a)
        } else if t.training.isEmpty {
            abschnitte.append(StatAbschnitt(id: "kraft", label: "Krafttraining", details: [StatDetail(text: leerTraining)], ziel: .kraft))
        } else {
            abschnitte.append(StatAbschnitt(id: "kraft", label: "Krafttraining", titel: laufend ? "Diesen Monat noch *kein Training*." : "Im \(name) *kein Training*.", ziel: .kraft))
        }

        var gew = StatAbschnitt(id: "gewicht", label: "Gewicht")
        let imMonat = t.trend.filter { $0.tag >= ms && $0.tag <= bis }
        if let ende = imMonat.last {
            let anfang = t.trendBis(vorEnde) ?? imMonat.first!.trend
            if imMonat.count >= 2 || anfang != ende.trend {
                gew.titel = "Trend von \(StatFormat.zahl(anfang, 1)) auf *\(StatFormat.zahl(ende.trend, 1)) kg*."
            } else {
                gew.titel = "Trend *\(StatFormat.zahl(ende.trend, 1)) kg*."
            }
            let punkte = (0..<vergangen).compactMap { i -> StatXY? in
                t.gewicht[StatKalender.plus(ms, tage: i)].map { StatXY(x: Double(i) / Double(max(1, n - 1)), y: $0) }
            }
            let linie = imMonat.map { StatXY(x: Double(StatKalender.abstand(ms, $0.tag)) / Double(max(1, n - 1)), y: $0.trend) }
            gew.visuals = [.gewicht(StatGewichtDiagramm(punkte: punkte, trend: linie))]
            var zeile: [String] = []
            let diff = ende.trend - anfang
            zeile.append(abs(diff) < 0.05 ? "Im \(name) unverändert" : "\(diff > 0 ? "+" : "−")\(StatFormat.zahl(abs(diff), 1)) kg im \(name)")
            if let tempo = t.tempoBis(bis) { zeile.append("\(tempoText(tempo)) kg pro Woche") }
            gew.details = [StatDetail(text: zeile.joined(separator: " · "))]
        } else if t.trend.isEmpty {
            gew.details = [StatDetail(text: leerGewicht)]
        } else {
            gew.titel = "Im \(name) *nicht gewogen*."
        }
        abschnitte.append(gew)

        var inhalt = StatInhalt(kopf: "\(name) \(p.j)", titel: nil, abschnitte: abschnitte)
        inhalt.kannVor = zurueck > 0
        if let frueh = fruehesterTag(q) { inhalt.kannZurueck = StatKalender.monatsStart(frueh, versatz: 0) < ms }
        return inhalt
    }

    static func laengstePause(von: String, bis: String, hat: (String) -> Bool) -> String? {
        var beste = (laenge: 0, start: "", ende: ""), aktuell = (laenge: 0, start: "")
        let tage = StatKalender.abstand(von, bis)
        guard tage >= 0 else { return nil }
        for i in 0...tage {
            let tag = StatKalender.plus(von, tage: i)
            if hat(tag) { aktuell = (0, "") } else {
                aktuell = (aktuell.laenge + 1, aktuell.laenge == 0 ? tag : aktuell.start)
                if aktuell.laenge > beste.laenge { beste = (aktuell.laenge, aktuell.start, tag) }
            }
        }
        if beste.laenge == 0 { return "Kein Tag ohne Lauf" }
        let a = StatKalender.teile(beste.start).t, b = StatKalender.teile(beste.ende).t
        if beste.laenge == 1 { return "Längste Pause ein Tag, am \(a)." }
        return "Längste Pause \(StatFormat.zahlwort(beste.laenge, gross: false)) Tage, vom \(a). bis \(b)."
    }

    static func jahr(_ q: StatQuellen) -> StatInhalt {
        let t = StatTage(q)
        let h = q.heute
        let d = q.daten
        let jahr = StatKalender.teile(h).j
        let ys = StatKalender.schluessel(jahr: jahr, monat: 1, tag: 1)
        let ye = StatKalender.schluessel(jahr: jahr, monat: 12, tag: 31)
        let tageImJahr = StatKalender.tageImJahr(jahr)
        var abschnitte: [StatAbschnitt] = []
        let achse = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

        let jl = t.laeufeIm(von: ys, bis: ye)
        if !jl.isEmpty {
            let km = jl.reduce(0) { $0 + $1.km }
            var a = StatAbschnitt(id: "laufen", label: "Laufen", titel: "*\(StatFormat.zahl(km)) km* an \(Set(jl.map(\.datum)).count) Tagen.", ziel: .laufen)
            let start = StatKalender.wochenstart(ys)
            let spalten = StatKalender.abstand(start, ye) / 7 + 1
            var felder: [[Int]] = []
            for s in 0..<spalten {
                felder.append((0..<7).map { r in
                    let tag = StatKalender.plus(start, tage: s * 7 + r)
                    return tag < ys || tag > ye ? -1 : tag > h ? -2 : intensitaetKm(t.km[tag] ?? 0)
                })
            }
            let monatsKm = (1...12).map { m -> Double in
                t.summeKm(von: StatKalender.schluessel(jahr: jahr, monat: m, tag: 1), bis: StatKalender.schluessel(jahr: jahr, monat: m, tag: StatKalender.tageImMonat(jahr: jahr, monat: m)))
            }
            let bester = monatsKm.enumerated().max { $0.element < $1.element }!
            a.visuals = [.jahresRaster(StatJahresRaster(spalten: spalten, felder: felder)), .jahresAchse,
                         .monatsBalken(StatMonatsBalken(werte: monatsKm, namen: achse, hervor: bester.element > 0 ? bester.offset : nil, aktuell: StatKalender.teile(h).m - 1))]
            let zeit = jl.reduce(0) { $0 + $1.dauer }
            var zeile = "Bester Monat \(StatKalender.monate[bester.offset]) mit \(StatFormat.zahl(bester.element)) km · Ø \(StatFormat.pace(zeit / km)) pro km im Jahr"
            if let ersterMonat = (1...12).first(where: { monatsKm[$0 - 1] > 0 }) {
                let ml = jl.filter { StatKalender.teile($0.datum).m == ersterMonat }
                if ml.count >= 2, ersterMonat != bester.offset + 1 {
                    let pace = ml.reduce(0) { $0 + $1.dauer } / ml.reduce(0) { $0 + $1.km }
                    if pace - zeit / km >= 5 { zeile += ", im \(StatKalender.monate[ersterMonat - 1]) noch \(StatFormat.pace(pace))" }
                }
            }
            a.details = [StatDetail(text: zeile)]
            abschnitte.append(a)
        } else if q.laeufe.isEmpty {
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen", details: [StatDetail(text: leerLaufen)], ziel: .laufen))
        } else {
            abschnitte.append(StatAbschnitt(id: "laufen", label: "Laufen", titel: "Dieses Jahr noch *kein Lauf*.", ziel: .laufen))
        }

        let buecher = d.buecher.filter { $0.begonnen <= ye && ($0.beendet ?? ye) >= ys }.sorted { $0.begonnen < $1.begonnen }
        let gelesen = t.summeLesezeit(von: ys, bis: ye)
        if !buecher.isEmpty {
            let n = buecher.count
            var a = StatAbschnitt(id: "lesen", label: "Lesen", titel: "*\(StatFormat.zahlwort(n)) \(n == 1 ? "Buch" : "Bücher")*, \(zeitText(gelesen)).", ziel: .buecher)
            a.visuals = [.buecher(buecher.map { b in
                let von = Double(max(0, StatKalender.abstand(ys, b.begonnen))) / Double(tageImJahr)
                let bisTag = min(b.beendet ?? h, ye)
                let bis = Double(StatKalender.abstand(ys, bisTag)) / Double(tageImJahr)
                let dauer = b.beendet != nil ? "\(StatKalender.abstand(b.begonnen, b.beendet!) + 1) Tage" : "seit \(StatFormat.datumKurz(b.begonnen))"
                return StatBuchBalken(titel: b.titel, dauer: dauer, von: von, bis: max(bis, von), offen: b.beendet == nil)
            })]
            let fertig = buecher.compactMap { b -> (StatBuch, Double)? in
                guard let e = b.beendet else { return nil }
                let tage = StatKalender.abstand(b.begonnen, e) + 1
                let s = lesezeitImBuch(d, b)
                return tage >= 3 && s > 0 ? (b, Double(s) / Double(tage)) : nil
            }
            if fertig.count >= 2, let schnell = fertig.max(by: { $0.1 < $1.1 }) {
                let schnitt = fertig.reduce(0) { $0 + $1.1 } / Double(fertig.count)
                a.details = [StatDetail(text: "Am meisten pro Tag: *\(schnell.0.titel)* mit \(zeitText(Int(schnell.1.rounded()))) am Tag, im Schnitt aller Bücher sind es \(zeitText(Int(schnitt.rounded()))).")]
            }
            abschnitte.append(a)
        } else if gelesen > 0 {
            abschnitte.append(StatAbschnitt(id: "lesen", label: "Lesen", titel: "*\(zeitText(gelesen))* gelesen.", ziel: .buecher))
        } else {
            abschnitte.append(StatAbschnitt(id: "lesen", label: "Lesen", details: [StatDetail(text: leerLesen)], ziel: .buecher))
        }

        let tage = t.trainingsTage(von: ys, bis: ye)
        if !tage.isEmpty {
            let sat = t.saetzeIm(von: ys, bis: ye)
            var titel = "*\(tage.count) \(tage.count == 1 ? "Training" : "Trainings")*"
            var a = StatAbschnitt(id: "kraft", label: "Krafttraining", ziel: .kraft)
            if let name = hauptuebung(sat, d) {
                let proMonat = Dictionary(grouping: sat.filter { d.name($0) == name }, by: { StatKalender.teile($0.datum).m }).sorted { $0.key < $1.key }
                let werte = proMonat.compactMap { m, s in staerke(s).map { (m, $0.wert, $0.koerper) } }
                if werte.count >= 2, let erster = werte.first, let letzter = werte.last {
                    titel += erster.1 == letzter.1 ? ", \(name) bei \(staerkeText(letzter.1, koerper: letzter.2))."
                        : ", \(name) von \(StatFormat.kg(erster.1)) auf \(staerkeText(letzter.1, koerper: letzter.2))."
                    a.visuals = [.linie(beschriftung: nil, StatLinie(werte: werte.map(\.1), xs: werte.map { (Double($0.0) - 0.5) / 12 },
                                                                     links: staerkeText(erster.1, koerper: erster.2), rechts: staerkeText(letzter.1, koerper: letzter.2)))]
                } else { titel += "." }
            } else { titel += "." }
            a.titel = titel
            var zeile: [String] = []
            let wochen = max(1, Double(StatKalender.abstand(ys, h) + 1) / 7)
            if wochen >= 2 { zeile.append("\(StatFormat.zahl(Double(tage.count) / wochen, 1)) Trainings pro Woche") }
            let vol = StatTage.volumen(sat, koerper: t.koerperHealth)
            if vol >= 1000 { zeile.append("\(StatFormat.zahl(vol / 1000)) Tonnen bewegt") } else if vol > 0 { zeile.append("\(StatFormat.zahl(vol)) kg bewegt") }
            if !zeile.isEmpty { a.details = [StatDetail(text: zeile.joined(separator: " · "))] }
            abschnitte.append(a)
        } else if t.training.isEmpty {
            abschnitte.append(StatAbschnitt(id: "kraft", label: "Krafttraining", details: [StatDetail(text: leerTraining)], ziel: .kraft))
        } else {
            abschnitte.append(StatAbschnitt(id: "kraft", label: "Krafttraining", titel: "Dieses Jahr noch *kein Training*.", ziel: .kraft))
        }

        var gew = StatAbschnitt(id: "gewicht", label: "Gewicht")
        let imJahr = t.trend.filter { $0.tag >= ys && $0.tag <= h }
        if let ende = imJahr.last {
            let anfangTag = t.trend.first { $0.tag >= ys }!.tag
            let anfang = t.trendBis(StatKalender.plus(ys, tage: -1)) ?? t.trendNach[anfangTag]!
            let seit = t.trendBis(StatKalender.plus(ys, tage: -1)) != nil ? "Januar" : monatsName(anfangTag)
            let diff = ende.trend - anfang
            gew.titel = abs(diff) < 0.1 ? "Trend *\(StatFormat.zahl(ende.trend, 1)) kg*, seit \(seit) unverändert."
                : "Seit \(seit) *\(StatFormat.zahl(abs(diff), 1)) kg* \(diff < 0 ? "leichter" : "schwerer")."
            if imJahr.count >= 7 {
                let schritt = max(1, imJahr.count / 60)
                var linie = stride(from: 0, to: imJahr.count, by: schritt).map { StatXY(x: Double(StatKalender.tagImJahr(imJahr[$0].tag)) / Double(tageImJahr), y: imJahr[$0].trend) }
                if let l = imJahr.last, linie.last?.y != l.trend { linie.append(StatXY(x: Double(StatKalender.tagImJahr(l.tag)) / Double(tageImJahr), y: l.trend)) }
                gew.visuals = [.gewicht(StatGewichtDiagramm(punkte: [], trend: linie, links: StatFormat.zahl(anfang, 1), rechts: StatFormat.zahl(ende.trend, 1))), .jahresAchse]
            }
            var zeile: [String] = []
            var monatsAenderung: [(Int, Double)] = []
            for m in 1...12 {
                let monatsEnde = StatKalender.schluessel(jahr: jahr, monat: m, tag: StatKalender.tageImMonat(jahr: jahr, monat: m))
                let davor = StatKalender.plus(StatKalender.schluessel(jahr: jahr, monat: m, tag: 1), tage: -1)
                if let b = t.trendBis(min(monatsEnde, h)), let a = t.trendBis(davor), monatsEnde <= h || StatKalender.teile(h).m == m { monatsAenderung.append((m, b - a)) }
            }
            let richtung = diff < 0 ? -1.0 : 1.0
            if monatsAenderung.count >= 2, let best = monatsAenderung.max(by: { $0.1 * richtung < $1.1 * richtung }), best.1 * richtung > 0.05 {
                zeile.append("Schnellster Monat \(StatKalender.monate[best.0 - 1]) mit \(StatFormat.zahl(abs(best.1), 1)) kg")
            }
            if let tempo = t.tempoBis(h) { zeile.append("aktuell \(tempoText(tempo)) kg pro Woche") }
            if !zeile.isEmpty { gew.details = [StatDetail(text: zeile.joined(separator: " · "))] }
        } else {
            gew.details = [StatDetail(text: leerGewicht)]
        }
        abschnitte.append(gew)

        return StatInhalt(kopf: "\(jahr) bis heute", titel: nil, abschnitte: abschnitte)
    }
}
