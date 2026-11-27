import SwiftUI

struct SnStatDetail: View {
    var bereich: StatBereich
    var daten: SenecaStatistik
    var stand: Double
    var zurueck: () -> Void

    private typealias L = StatistikLogik
    private var k: SenecaStatistik.Kennzahlen? { daten.kennzahlen }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: zurueck) { Text("‹ Statistik").font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.zweit).contentShape(Rectangle()) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Zurück zur Statistik")
                Text(kopf).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).padding(.top, 26)
                SnStatSatz(teile: satz, groesse: 40).padding(.top, 10)
                inhalt.padding(.top, 34)
            }
            .padding(.horizontal, 96).padding(.top, 90).padding(.bottom, 140)
        }
        .scrollIndicators(.never)
    }

    private var kopf: String {
        switch bereich {
        case .laufen: "LAUFEN · ZIEL 100 KM AM STÜCK, CA. JUNI"
        case .kraft: "KRAFTTRAINING · DIE LETZTEN ACHT WOCHEN"
        case .lesen: daten.buch?.kopf ?? "LESEN"
        case .koerper: "KÖRPER · SCHLAF, ERHOLUNG, GEWICHT"
        }
    }

    private var satz: [String] {
        switch bereich {
        case .laufen:
            let km = k?.lauf.km.last ?? 0, seit = k.flatMap { L.letzterLauf($0, daten.lauf) }
            let erst = km > 0 ? "\(L.zahl(km)) km diese Woche." : seit.map { "Seit dem \(L.datum($0, lang: true)) kein Lauf." } ?? "Noch kein Lauf."
            let l = k?.lauf.laengster
            guard let w = l?.first?.alsZahl, let d = l?.last?.alsText else { return [erst] }
            return [erst, "Am weitesten bisher \(L.zahl(w)) km, am \(L.datum(d, lang: true))."]
        case .kraft:
            let n = (k?.kraft.tage.suffix(8) ?? []).reduce(0, +), b = k.map(L.bestwerte)?.first
            return [n == 0 ? "Acht Wochen ohne Training." : n == 1 ? "Ein Training in acht Wochen." : "\(n) Trainings in acht Wochen."]
                + (b.map { ["Zuletzt am \(L.datum($0.iso, lang: true)): \($0.name) \(L.zahl($0.kg)) kg × \($0.wdh)."] } ?? [])
        case .lesen:
            let b = daten.buch
            return [b?.titel ?? "Noch kein Buch.", b.map { $0.satz.isEmpty ? $0.zuletzt.first.map { "Zuletzt am \($0.links.capitalized) gelesen." } ?? "" : $0.satz } ?? ""].filter { !$0.isEmpty }
        case .koerper:
            guard let n = k?.koerper.nacht.last, let h = n[1].alsZahl else { return ["Noch keine Nacht gemessen.", "Die Uhr trägt sie von selbst ein."] }
            let puls = k?.koerper.tag.last?[2].alsZahl
            return ["Letzte Nacht \(L.stunden(h)) Std.", ([n[7].alsZahl.map { "HRV \(L.zahl($0, 0))" }, puls.map { "Ruhepuls \(L.zahl($0, 0))" }].compactMap { $0 }.joined(separator: ", ") + ".")]
        }
    }

    @ViewBuilder private var inhalt: some View {
        switch bereich {
        case .laufen: laufen
        case .kraft: kraft
        case .lesen: lesen
        case .koerper: koerper
        }
    }

    @ViewBuilder private var laufen: some View {
        if let k {
            let ziel = L.wochenZiel(k), l = k.lauf
            VStack(alignment: .leading, spacing: 16) {
                SnStatFlaeche {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            SnStatKopf(titel: "Der Weg zu 100 km", zusatz: "Woche für Woche, bis zum Lauf im Juni", rechts: "")
                            SnStatLegende(eintraege: [("WOCHE", TafelFarbe.gruen.opacity(0.4)), ("LÄNGSTER LAUF", TafelFarbe.gruen), ("AUFBAU", TafelFarbe.himmel.opacity(0.55))])
                        }
                        SnWegZu100(weg: L.weg(k)).frame(height: 300)
                        if let ziel {
                            Text("Diese Woche sieht der Aufbau \(L.zahl(ziel.km)) km vor, davon \(L.zahl(ziel.lang)) am Stück. Der lange Lauf wächst um 2 km je Woche, jede vierte Woche ist leichter.")
                                .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    zahl(l.laengster?.first?.alsZahl.map { L.zahl($0) }, "KM", "Längster Lauf" + (l.laengster?.last?.alsText.map { " · \(L.datum($0))" } ?? ""))
                    zahl(l.serie?["beste"].map(String.init), "TAGE", "Beste Serie, jetzt \(l.serie?["jetzt"] ?? 0)")
                    zahl(l.schnellsterKm?.first?.alsZahl.map { L.stunden($0 / 60) }, "/KM", "Schnellster Kilometer" + (l.schnellsterKm?.last?.alsText.map { " · \(L.datum($0))" } ?? ""))
                    zahl(l.trendKm.map { ($0 >= 0 ? "+" : "−") + L.zahl(abs($0)) }, "KM", "Trend je Woche")
                }
                HStack(alignment: .top, spacing: 16) {
                    letzterLauf
                    SnStatFlaeche {
                        VStack(alignment: .leading, spacing: 0) {
                            SnStatKopf(titel: "Die Läufe", zusatz: "Woche für Woche", rechts: "").padding(.bottom, 12)
                            ForEach(L.laufWochen(k, 8), id: \.iso) { w in
                                SnStatListenZeile(links: "\(L.woche(w.iso)) · ab \(L.datum(w.iso))", mitte: "\(L.zahl(w.km)) km", rechts: "",
                                                  unter: "\(w.tage == 1 ? "1 Lauf" : "\(w.tage) Läufe"), längster \(L.zahl(w.lang)) km")
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var letzterLauf: some View {
        SnStatFlaeche {
            VStack(alignment: .leading, spacing: 0) {
                if let l = daten.lauf {
                    SnStatKopf(titel: "Letzter Lauf", zusatz: k.flatMap { L.letzterLauf($0, l) }.map { L.datum($0, lang: true) } ?? "", rechts: l.kopf.components(separatedBy: ", ").last ?? "")
                    HStack(alignment: .top, spacing: 28) {
                        ForEach(l.werte, id: \.self) { w in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.first ?? "").font(Schrift.grotesk(22, .medium)).foregroundStyle(Color.white)
                                Text(w.last ?? "").font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise)
                            }
                        }
                    }
                    .padding(.top, 16)
                    VStack(spacing: 7) {
                        ForEach(l.km, id: \.nr) { s in
                            HStack(spacing: 12) {
                                Text("KM \(s.nr)").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).frame(width: 40, alignment: .leading)
                                GeometryReader { g in Capsule().fill(s.schnellste ? TafelFarbe.gruen : TafelFarbe.gruen.opacity(0.4)).frame(width: g.size.width * s.anteil) }.frame(height: 6)
                                Text(s.zeit).font(Schrift.mono(11)).foregroundStyle(s.schnellste ? TafelFarbe.gruen : TafelFarbe.text).frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 18)
                    if let b = l.bestwert { Text(b).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.gruen).padding(.top, 14) }
                } else {
                    SnStatKopf(titel: "Letzter Lauf", zusatz: "", rechts: "")
                    Text("Noch kein Lauf eingetragen.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise).padding(.top, 14)
                }
            }
        }
    }

    @ViewBuilder private var kraft: some View {
        if let k {
            let best = L.bestwerte(k), vol = k.kraft.volumen, hoch = max(vol.values.max() ?? 1, 1)
            let ohne = L.muskeln.filter { (vol[$0] ?? 0) == 0 }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    if let u = daten.uebung { SnUebungKurve(u: u).frame(maxWidth: .infinity) }
                    SnStatFlaeche {
                        VStack(alignment: .leading, spacing: 16) {
                            SnStatKopf(titel: "Einheiten", zusatz: "je Woche, Ziel 3", rechts: "12 WOCHEN")
                            SnStatBalken(werte: k.kraft.tage.suffix(12).map(Double.init), farbe: TafelFarbe.gruen, beschriftung: k.wochen.suffix(12).map { L.woche($0) }, ziel: 3).frame(height: 190)
                        }
                    }
                    .frame(width: 420)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 16) {
                    SnStatFlaeche {
                        VStack(alignment: .leading, spacing: 0) {
                            SnStatKopf(titel: "Bestwerte", zusatz: "bester Satz je Übung", rechts: "").padding(.bottom, 12)
                            ForEach(best, id: \.name) { b in
                                SnStatListenZeile(links: b.name, mitte: "\(L.zahl(b.kg)) kg × \(b.wdh)", rechts: L.datum(b.iso).uppercased(), unter: "≈ \(L.zahl(b.rm, 0)) kg Maximum")
                            }
                            if best.isEmpty { Text("Noch keine Sätze eingetragen.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise) }
                        }
                    }
                    SnStatFlaeche {
                        VStack(alignment: .leading, spacing: 14) {
                            SnStatKopf(titel: "Muskelgruppen", zusatz: "bewegtes Gewicht, vier Wochen", rechts: "")
                            ForEach(L.muskeln, id: \.self) { m in
                                HStack(spacing: 12) {
                                    Text(m).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.text).frame(width: 84, alignment: .leading)
                                    GeometryReader { g in Capsule().fill((vol[m] ?? 0) > 0 ? TafelFarbe.gruen.opacity(0.7) : Color.white.opacity(0.1)).frame(width: max(3, g.size.width * (vol[m] ?? 0) / hoch)) }.frame(height: 6)
                                    Text((vol[m] ?? 0) > 0 ? "\(L.zahl(vol[m] ?? 0, 0)) kg" : "–").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).frame(width: 70, alignment: .trailing)
                                }
                            }
                            if !ohne.isEmpty {
                                Text("\(ohne.joined(separator: ", ")): nichts in vier Wochen.").font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var lesen: some View {
        if let b = daten.buch {
            VStack(alignment: .leading, spacing: 0) {
                if let a = b.anteil {
                    HStack {
                        Text(b.seite ?? "").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                        Spacer()
                        Text(b.prozent ?? "").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                    }
                    SnStatFortschritt(anteil: a, rechts: "", farbe: TafelFarbe.akzent).padding(.top, 10)
                }
                if let p = b.prognose { Text(p).font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.text).padding(.top, 14) }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(b.zahlen, id: \.self) { z in SnStatZahl(wert: z.first ?? "", einheit: z.count > 1 ? z[1] : "", unter: z.last, groesse: 34).frame(maxWidth: .infinity, alignment: .leading) }
                }
                .padding(.top, 28)
                HStack(alignment: .top, spacing: 16) {
                    SnStatFlaeche {
                        VStack(alignment: .leading, spacing: 0) {
                            SnStatKopf(titel: "Zuletzt", zusatz: "", rechts: "").padding(.bottom, 12)
                            ForEach(Array(b.zuletzt.enumerated()), id: \.offset) { _, z in
                                SnStatListenZeile(links: z.links.capitalized, mitte: z.wert, rechts: "", unter: z.unter.isEmpty ? nil : z.unter, hervor: z.bestwert ? "BESTWERT" : nil)
                            }
                        }
                    }
                    if let n = b.notiz {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(n.kopf).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                            Text(n.text).font(Schrift.serif(22, kursiv: true)).foregroundStyle(Color.white)
                        }
                        .padding(22).frame(maxWidth: .infinity, alignment: .leading).snFlaeche(18, deckkraft: 0.08)
                    }
                }
                .fixedSize(horizontal: false, vertical: true).padding(.top, 28)
            }
        }
    }

    @ViewBuilder private var koerper: some View {
        if let k {
            let n = k.koerper.nacht.last, t = k.koerper.tag.last, tage = L.letzteTage(stand, 14)
            let erste = k.koerper.nacht.first?.first?.alsText
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    zahl(n?[1].alsZahl.map(L.stunden), "STD", "Schlaf" + (n?[2].alsZahl.map { ", davon \(L.stunden($0)) tief" } ?? ""))
                    zahl(n?[6].alsZahl.map { L.zahl($0, 0) }, "", "Schlafwert")
                    zahl(n?[7].alsZahl.map { L.zahl($0, 0) }, "MS", "HRV")
                    zahl(t?[2].alsZahl.map { L.zahl($0, 0) }, "", "Ruhepuls")
                    zahl(n?[8].alsZahl.map { L.zahl($0, 0) }, "", "Body Battery am Morgen")
                    zahl(t?[1].alsZahl.map { $0.formatted(.number.grouping(.automatic).locale(Locale(identifier: "de_DE"))) }, "", "Schritte" + (t?.first?.alsText.map { " am \(L.datum($0))" } ?? ""))
                }
                HStack(alignment: .top, spacing: 16) {
                    SnStatFlaeche {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { SnStatKopf(titel: "Schlaf", zusatz: "die letzten zwei Wochen", rechts: ""); SnStatLegende(eintraege: [("SCHLAF", TafelFarbe.zweit.opacity(0.8)), ("DAVON TIEF", TafelFarbe.himmel)]) }
                            HStack(alignment: .bottom, spacing: 8) {
                                ForEach(tage, id: \.self) { d in
                                    let nacht = L.nacht(k, d)
                                    VStack(spacing: 6) {
                                        Spacer(minLength: 0)
                                        if let h = nacht?[1].alsZahl {
                                            VStack(spacing: 0) {
                                                Rectangle().fill(TafelFarbe.zweit.opacity(0.8))
                                                Rectangle().fill(TafelFarbe.himmel).frame(height: 150 * (nacht?[2].alsZahl ?? 0) / 9)
                                            }
                                            .frame(height: 150 * h / 9).clipShape(RoundedRectangle(cornerRadius: 3))
                                        } else {
                                            Text("–").font(Schrift.grotesk(11)).foregroundStyle(TafelFarbe.aus)
                                        }
                                        Text(L.tag(d).map { ["SO", "MO", "DI", "MI", "DO", "FR", "SA"][Calendar(identifier: .gregorian).component(.weekday, from: $0) - 1] } ?? "")
                                            .font(Schrift.mono(10)).foregroundStyle(d == tage.last ? Color.white : TafelFarbe.aus)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 180)
                            if let erste { Text("Die Uhr misst den Schlaf seit dem \(L.datum(erste, lang: true)). Die Lücken füllen sich von selbst.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text) }
                        }
                    }
                    SnStatFlaeche {
                        VStack(alignment: .leading, spacing: 16) {
                            SnStatKopf(titel: "Gewicht", zusatz: "ein Jahr", rechts: "")
                            SnGewichtKurve(punkte: k.koerper.gewicht.compactMap { r in r.first?.alsText.flatMap(L.tag).flatMap { d in r.last?.alsZahl.map { (d, $0) } } }).frame(height: 180)
                            if let g = k.koerper.gewicht.last, let kg = g.last?.alsZahl, let d = g.first?.alsText {
                                Text("Zuletzt \(L.zahl(kg)) kg am \(L.datum(d, lang: true)), aus Apple Health.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zahl(_ wert: String?, _ einheit: String, _ unter: String) -> some View {
        SnStatZahl(wert: wert ?? "–", einheit: wert == nil ? "" : einheit, unter: unter, groesse: 32).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SnGewichtKurve: View {
    var punkte: [(Date, Double)]

    var body: some View {
        GeometryReader { g in
            let kg = punkte.map(\.1), lo = (kg.min() ?? 0) - 1, hi = (kg.max() ?? 1) + 1
            let t0 = punkte.first?.0.timeIntervalSince1970 ?? 0, t1 = max(t0 + 1, punkte.last?.0.timeIntervalSince1970 ?? 1)
            let x = { (d: Date) in CGFloat((d.timeIntervalSince1970 - t0) / (t1 - t0)) * (g.size.width - 60) + 8 }
            let y = { (v: Double) in (1 - CGFloat((v - lo) / (hi - lo))) * (g.size.height - 26) + 4 }
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: lo.rounded(.up), through: hi, by: max(1, ((hi - lo) / 3).rounded()))), id: \.self) { v in
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: g.size.width, height: 1).offset(y: y(v))
                    Text("\(Int(v))").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).position(x: g.size.width - 14, y: y(v) - 8)
                }
                Path { p in for (i, q) in punkte.enumerated() { i == 0 ? p.move(to: CGPoint(x: x(q.0), y: y(q.1))) : p.addLine(to: CGPoint(x: x(q.0), y: y(q.1))) } }
                    .stroke(TafelFarbe.zweit.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                ForEach(Array(punkte.enumerated()), id: \.offset) { i, q in
                    Circle().fill(i == punkte.count - 1 ? Color.white : TafelFarbe.zweit.opacity(0.8)).frame(width: i == punkte.count - 1 ? 8 : 4).position(x: x(q.0), y: y(q.1))
                }
                if let a = punkte.first, let e = punkte.last {
                    Text(StatistikLogik.monatKurz(StatistikLogik.iso(a.0))).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).position(x: x(a.0) + 10, y: g.size.height - 6)
                    Text(StatistikLogik.monatKurz(StatistikLogik.iso(e.0))).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).position(x: x(e.0), y: g.size.height - 6)
                }
            }
        }
    }
}

struct SnUebungKurve: View {
    var u: SenecaStatistik.Uebung

    var body: some View {
        let p = StatistikLogik.achtWochen(u)
        let kg = p.compactMap(\.kg), lo = (kg.min() ?? 0) - 2.5, hi = (kg.max() ?? 1) + 2.5
        SnStatFlaeche {
            VStack(alignment: .leading, spacing: 14) {
                SnStatKopf(titel: u.titel.trimmingCharacters(in: CharacterSet(charactersIn: ".")), zusatz: "bester Satz je Woche", rechts: "\(p.count) WOCHEN")
                GeometryReader { g in
                    let x = { (i: Int) in CGFloat(i) / CGFloat(max(1, p.count - 1)) * (g.size.width - 16) + 8 }
                    let y = { (v: Double) in (1 - CGFloat((v - lo) / max(0.1, hi - lo))) * (g.size.height - 30) + 18 }
                    let pts = p.enumerated().compactMap { i, q in q.kg.map { CGPoint(x: x(i), y: y($0)) } }
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(stride(from: (lo / 5).rounded(.up) * 5, through: hi, by: 5)), id: \.self) { v in
                            Rectangle().fill(Color.white.opacity(0.07)).frame(width: g.size.width, height: 1).offset(y: y(v))
                            Text("\(Int(v)) kg").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).offset(y: y(v) - 14)
                        }
                        Path { a in guard let f = pts.first, let l = pts.last else { return }; a.move(to: CGPoint(x: f.x, y: g.size.height - 12)); pts.forEach { a.addLine(to: $0) }; a.addLine(to: CGPoint(x: l.x, y: g.size.height - 12)) }
                            .fill(LinearGradient(colors: [TafelFarbe.gruen.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                        Path { a in guard let f = pts.first else { return }; a.move(to: f); pts.dropFirst().forEach { a.addLine(to: $0) } }.stroke(TafelFarbe.gruen, lineWidth: 2)
                        ForEach(Array(p.enumerated()), id: \.offset) { i, q in
                            if let v = q.kg {
                                let last = i == p.count - 1
                                Circle().fill(last ? TafelFarbe.gruen : TafelFarbe.aufHimmel).overlay(Circle().strokeBorder(TafelFarbe.gruen, lineWidth: 1.5)).frame(width: last ? 10 : 7, height: last ? 10 : 7).position(x: x(i), y: y(v))
                                Text("×\(q.wdh ?? 0)").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.text).position(x: x(i), y: y(v) - 14)
                            }
                            Text(q.w).font(Schrift.mono(10)).foregroundStyle(i == p.count - 1 ? Color.white : TafelFarbe.aus).position(x: x(i), y: g.size.height)
                        }
                        if kg.isEmpty {
                            Text("Keine Sätze in diesen acht Wochen.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise).position(x: g.size.width / 2, y: g.size.height / 2)
                        }
                    }
                }
                .frame(height: 190)
                if let s = StatistikLogik.heuteSatz(u.zeilen.first) ?? (u.satz.isEmpty ? nil : u.satz) { Text(s).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text) }
            }
        }
    }
}
