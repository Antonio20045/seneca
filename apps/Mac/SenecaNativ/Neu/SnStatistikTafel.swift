import SwiftUI

struct SnStatistikEcht: View {
    @ObservedObject var store: SenecaStore
    @State private var daten: SenecaStatistik?
    @State private var stand: Double = 0
    @State private var gemeldet: Set<String> = []

    var body: some View {
        Group {
            if let daten { SnStatistikTafel(daten: daten, stand: stand) } else { SnHeuteSkelett() }
        }
        .task(id: store.stand?.revision) {
            guard let j = try? await store.rufe("seneca.stand", params: ["geraet": "mac", "sicht": "statistik"]),
                  let roh = try? JSONSerialization.data(withJSONObject: j) else { return }
            daten = try? JSONDecoder().decode(SenecaStatistik.self, from: roh)
            stand = Date().timeIntervalSince1970 * 1000
            for s in daten?.kennzahlen?.statistiken ?? [] where !gemeldet.contains(s.id) {
                gemeldet.insert(s.id)
                store.handle("anzeige.angesehen", ziel: s.id)
            }
        }
    }
}

struct SnStatistikTafel: View {
    var daten: SenecaStatistik
    var stand: Double
    @State var bereich: StatBereich?
    @State var zeitraum: StatZeitraum = .woche

    var body: some View {
        ZStack {
            if let b = bereich {
                SnStatDetail(bereich: b, daten: daten, stand: stand) { wechsle(nil) }.transition(.opacity.combined(with: .offset(x: 24)))
            } else {
                uebersicht.transition(.opacity.combined(with: .offset(x: -24)))
            }
        }
        .onChange(of: "\(bereich?.rawValue ?? "Übersicht") \(zeitraum.rawValue)", initial: true) { _, z in SnStatistikProbe.gesehen = z }
    }

    private func wechsle(_ b: StatBereich?) { withAnimation(.easeOut(duration: 0.22)) { bereich = b } }

    private var k: SenecaStatistik.Kennzahlen? { daten.kennzahlen }
    private var eigene: [SenecaStatistik.Kennzahlen.Eigene] { k?.statistiken ?? [] }
    private func eigene(_ a: StatBereich) -> [SenecaStatistik.Kennzahlen.Eigene] { eigene.filter { StatistikLogik.abschnitt($0) == a } }

    private var uebersicht: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    Text(["Diese Woche", "Dieser Monat", "Dieses Jahr"][StatZeitraum.allCases.firstIndex(of: zeitraum) ?? 0]).font(Schrift.serif(40)).foregroundStyle(Color.white)
                    Text(zeitraum == .woche ? StatistikLogik.zeitraum(daten.woche.kopf, stand: stand) : (zeitraum == .monat ? daten.monat : daten.jahr)?.kopf ?? "")
                        .font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                    Spacer()
                    umschalter
                }
                SnStatGruppe(bereich: "wachstum", unter: "Laufen, Krafttraining, Lesen und Körper").padding(.top, 40)
                VStack(alignment: .leading, spacing: 0) {
                    laufen
                    kraft
                    lesen
                    koerper
                    if zeitraum == .jahr, let j = daten.jahr { jahr(j) }
                    ForEach(eigene.filter { StatistikLogik.abschnitt($0) == nil && StatistikLogik.lebensbereich($0) == "wachstum" }) { SnStatEigene(s: $0, voll: true) }
                }
                ForEach(["unternehmertum", "soziales"], id: \.self) { b in
                    let liste = eigene.filter { StatistikLogik.abschnitt($0) == nil && StatistikLogik.lebensbereich($0) == b }
                    if !liste.isEmpty {
                        SnStatGruppe(bereich: b, unter: "von deinen Mitarbeitern angelegt").padding(.top, 64)
                        ForEach(liste) { SnStatEigene(s: $0, voll: true) }
                    }
                }
                let ohne = ["unternehmertum", "soziales"].filter { b in !eigene.contains { StatistikLogik.lebensbereich($0) == b } }
                if !ohne.isEmpty {
                    Text("\(ohne.map { $0 == "soziales" ? "Soziales" : "Unternehmertum" }.joined(separator: " und ")) \(ohne.count > 1 ? "haben" : "hat") noch keine Statistik. Fragst du zweimal nach einem Stand, legt der zuständige Mitarbeiter eine an.")
                        .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise).padding(.top, 56)
                }
            }
            .padding(.horizontal, 96).padding(.top, 90).padding(.bottom, 140)
        }
        .scrollIndicators(.never)
    }

    private var umschalter: some View {
        HStack(spacing: 2) {
            ForEach(StatZeitraum.allCases, id: \.self) { z in
                Button { withAnimation(.easeOut(duration: 0.2)) { zeitraum = z } } label: {
                    Text(z.rawValue).font(Schrift.grotesk(13, .medium)).foregroundStyle(z == zeitraum ? Color.white : TafelFarbe.zweit)
                        .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(z == zeitraum ? 0.14 : 0))).contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityLabel(z.rawValue)
            }
        }
        .padding(3).background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var laufen: some View {
        let km = k?.lauf.km.last ?? 0, ziel = k.flatMap(StatistikLogik.wochenZiel), summe = StatistikLogik.summe(daten, zeitraum, "Laufen")
        let leer = zeitraum == .woche ? km == 0 : summe?.first == "0"
        let seit = k.flatMap { StatistikLogik.letzterLauf($0, daten.lauf) }
        let tempo = (k?.lauf.paceMonat ?? []).suffix(12).compactMap { p in p.count > 1 ? p[1].alsZahl.map { ("\(StatistikLogik.monatKurz(p[0].alsText ?? "")) \((p[0].alsText ?? "").prefix(4))", $0) } : nil }
        return SnStatAbschnitt(bereich: .laufen, oeffne: wechsle, eigene: eigene(.laufen)) {
            SnStatZahl(wert: summe?[0] ?? StatistikLogik.zahl(km), einheit: zeitraum == .woche && ziel != nil ? "VON \(StatistikLogik.zahl(ziel!.km)) KM" : summe?[1] ?? "KM")
            Text(leer ? seit.map { "Seit \(StatistikLogik.datum($0, lang: true)) kein Lauf." } ?? "Noch kein Lauf." : summe.map { String($0[2].dropFirst("Laufen, ".count)) } ?? "Längster Lauf \(StatistikLogik.zahl(k?.lauf.lang.last ?? 0)) km.")
                .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).padding(.top, 10)
        } grafik: {
            HStack(alignment: .top, spacing: 48) {
                SnStatSpalte(titel: "Kilometer je Woche", rechts: "12 WOCHEN") {
                    SnStatBalken(werte: Array((k?.lauf.km ?? []).suffix(12)), farbe: TafelFarbe.gruen, ziel: ziel?.km).frame(height: 96)
                }
                SnStatSpalte(titel: "Tempo je Monat", rechts: "MIN JE KM") {
                    SnStatLinie(punkte: tempo, text: { StatistikLogik.tempo($0) }, schneller: true).frame(height: 96)
                }
                .frame(width: 300)
            }
        }
    }

    private var kraft: some View {
        let karte = StatistikLogik.karte(daten, "kraft"), summe = StatistikLogik.summe(daten, zeitraum, "Kraft"), best = k.flatMap { StatistikLogik.bestwerte($0).first }
        let volumen = StatistikLogik.muskeln.map { ($0, k?.kraft.volumen[$0] ?? 0) }
        return SnStatAbschnitt(bereich: .kraft, oeffne: wechsle, eigene: eigene(.kraft)) {
            SnStatZahl(wert: summe?[0] ?? karte?.wert ?? "0", einheit: summe?[1] ?? karte?.einheit ?? "MAL")
            Text(best.map { "Bestwert: \($0.name) \(StatistikLogik.zahl($0.kg)) kg × \($0.wdh), \(StatistikLogik.datum($0.iso))" } ?? "Noch kein Bestwert.")
                .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).lineLimit(2).padding(.top, 10)
        } grafik: {
            HStack(alignment: .top, spacing: 48) {
                SnStatSpalte(titel: "Einheiten je Woche", rechts: "12 WOCHEN") {
                    SnStatRhythmus(werte: Array((k?.kraft.tage ?? []).suffix(12))).frame(height: 96)
                }
                SnStatSpalte(titel: "Volumen je Muskel", rechts: "4 WOCHEN") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(volumen, id: \.0) { m, v in SnStatVolumen(name: m, wert: v, hoch: volumen.map(\.1).max() ?? 0) }
                    }
                }
                .frame(width: 300)
            }
        }
    }

    private var lesen: some View {
        let karte = StatistikLogik.karte(daten, "lesen"), summe = StatistikLogik.summe(daten, zeitraum, "Lesen"), b = daten.buch
        let tage = (karte?.tage ?? []).map { $0.zustand == "da" ? $0.wert ?? $0.hoehe ?? 0.6 : 0 }
        return SnStatAbschnitt(bereich: .lesen, oeffne: wechsle, eigene: eigene(.lesen)) {
            SnStatZahl(wert: summe?[0] ?? karte?.wert ?? "0:00", einheit: summe?[1] ?? karte?.einheit ?? "STD")
            Text(b?.zuletzt.first.map { "Zuletzt \($0.links.capitalized), \($0.wert)." } ?? "Noch nichts gelesen.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).padding(.top, 10)
        } grafik: {
            HStack(alignment: .top, spacing: 48) {
                SnStatSpalte(titel: "Lesezeit je Tag", rechts: "DIESE WOCHE") {
                    SnStatBalken(werte: tage.isEmpty ? Array(repeating: 0, count: 7) : tage, farbe: TafelFarbe.akzent, beschriftung: ["MO", "DI", "MI", "DO", "FR", "SA", "SO"]).frame(height: 96)
                }
                SnStatSpalte(titel: b.map { "Buch · \($0.titel.trimmingCharacters(in: CharacterSet(charactersIn: ".")))" } ?? "Buch", rechts: b?.prozent ?? "") {
                    VStack(alignment: .leading, spacing: 14) {
                        SnStatFortschritt(anteil: b?.anteil ?? 0, rechts: b?.seite ?? "", farbe: TafelFarbe.akzent)
                        Text((b?.zahlen ?? []).filter { $0.count == 3 && $0[2] != "diese Woche" }.map { "\($0[2]) \($0[0]) \($0[1])".uppercased() }.joined(separator: " · "))
                            .font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                    }
                }
                .frame(width: 300)
            }
        }
    }

    private var koerper: some View {
        let n = k?.koerper.nacht.last, g = k?.koerper.gewicht ?? [], heute = StatistikLogik.letzteTage(stand, 1).first ?? ""
        let nacht = (k?.koerper.nacht ?? []).suffix(14).map { $0.count > 1 ? $0[1].alsZahl ?? 0 : 0 }, schlaf = Array(repeating: 0.0, count: 14 - nacht.count) + nacht
        let gewicht = g.suffix(26).compactMap { p in p.count > 1 ? p[1].alsZahl.map { (StatistikLogik.monatKurz(p[0].alsText ?? ""), $0) } : nil }
        return SnStatAbschnitt(bereich: .koerper, oeffne: wechsle, eigene: eigene(.koerper)) {
            SnStatZahl(wert: n.flatMap { $0.count > 1 ? $0[1].alsZahl.map(StatistikLogik.stunden) : nil } ?? "–", einheit: "STD SCHLAF")
            Text([n?.first?.alsText == heute ? "Heute Nacht." : nil, n.flatMap { $0.count > 7 ? $0[7].alsZahl.map { "HRV \(StatistikLogik.zahl($0, 0)) ms." } : nil }].compactMap { $0 }.joined(separator: " "))
                .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).padding(.top, 10)
        } grafik: {
            HStack(alignment: .top, spacing: 48) {
                SnStatSpalte(titel: "Schlaf je Nacht", rechts: "14 NÄCHTE") {
                    SnStatBalken(werte: schlaf, farbe: TafelFarbe.himmel, ziel: 8).frame(height: 96)
                }
                SnStatSpalte(titel: "Gewicht", rechts: "KG") {
                    SnStatLinie(punkte: gewicht, text: { StatistikLogik.zahl($0) }, schneller: false).frame(height: 96)
                }
                .frame(width: 300)
            }
        }
    }

    private func jahr(_ j: SenecaStatistik.Raster) -> some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bewegung im Jahr").font(Schrift.grotesk(17)).foregroundStyle(Color.white)
                Text("Laufen und Kraft, jeder Tag ein Feld").font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 4).padding(.bottom, 14)
                ForEach(Array(StatistikLogik.bestwerteJahr(j).enumerated()), id: \.offset) { _, b in SnStatListenZeile(links: b[0], mitte: b[1], rechts: b[2]) }
            }
            .frame(width: 280, alignment: .leading)
            SnBewegungRaster(raster: j.raster)
        }
        .padding(.vertical, 30)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}

struct SnStatGruppe: View {
    var bereich: String
    var unter: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(TafelFarbe.bereich(bereich)).frame(width: 28, height: 2)
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(["wachstum": "Wachstum", "soziales": "Soziales"][bereich] ?? "Unternehmertum").font(Schrift.serif(34)).foregroundStyle(Color.white)
                Text(unter).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise)
            }
        }
        .padding(.bottom, 8)
    }
}

struct SnStatAbschnitt<Links: View, Grafik: View>: View {
    var bereich: StatBereich
    var oeffne: (StatBereich) -> Void
    var eigene: [SenecaStatistik.Kennzahlen.Eigene]
    @ViewBuilder var links: Links
    @ViewBuilder var grafik: Grafik
    @State private var ueber = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { oeffne(bereich) } label: {
                HStack(alignment: .top, spacing: 56) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(bereich.rawValue).font(Schrift.grotesk(17)).foregroundStyle(Color.white)
                            Spacer()
                            Text("DETAILS ›").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.zweit).opacity(ueber ? 1 : 0)
                        }
                        links.padding(.top, 10)
                    }
                    .frame(width: 280, alignment: .leading)
                    grafik.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 30).padding(.horizontal, 20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(ueber ? 0.035 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { ueber = h } }
            .accessibilityElement(children: .ignore).accessibilityLabel(bereich.rawValue).accessibilityAddTraits(.isButton)
            ForEach(eigene) { SnStatEigene(s: $0, voll: false).padding(.horizontal, 20) }
        }
        .padding(.horizontal, -20)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}

struct SnStatSpalte<Inhalt: View>: View {
    var titel: String
    var rechts: String
    @ViewBuilder var inhalt: Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(titel).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit).lineLimit(1)
                Spacer()
                Text(rechts).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus)
            }
            inhalt
        }
    }
}

struct SnStatLinie: View {
    var punkte: [(String, Double)]
    var text: (Double) -> String
    var schneller: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let w = punkte.map(\.1), lo = w.min() ?? 0, hi = max((w.max() ?? 1), lo + 0.0001)
                let x = { (i: Int) in punkte.count > 1 ? g.size.width * CGFloat(i) / CGFloat(punkte.count - 1) : g.size.width / 2 }
                let y = { (v: Double) in 10 + (g.size.height - 20) * CGFloat(schneller ? (v - lo) / (hi - lo) : (hi - v) / (hi - lo)) }
                if punkte.isEmpty {
                    Text("Noch keine Werte.").font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.aus)
                } else {
                    Path { p in for (i, q) in punkte.enumerated() { i == 0 ? p.move(to: CGPoint(x: x(i), y: y(q.1))) : p.addLine(to: CGPoint(x: x(i), y: y(q.1))) } }
                        .stroke(TafelFarbe.zweit, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    Circle().fill(Color.white).frame(width: 6, height: 6).position(x: x(punkte.count - 1), y: y(punkte.last!.1))
                    Text(text(punkte.last!.1)).font(Schrift.mono(11)).foregroundStyle(Color.white).fixedSize()
                        .position(x: x(punkte.count - 1) - 18, y: y(punkte.last!.1) + (y(punkte.last!.1) < 24 ? 14 : -14))
                }
            }
            HStack {
                Text(punkte.first?.0 ?? "").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus)
                Spacer()
                Text(punkte.last?.0 ?? "").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus)
            }
        }
    }
}

struct SnStatRhythmus: View {
    var werte: [Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(werte.enumerated()), id: \.offset) { _, n in
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if n == 0 { RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.12)).frame(height: 2) }
                    ForEach(0..<min(n, 5), id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(TafelFarbe.gruen).frame(height: 14) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct SnStatVolumen: View {
    var name: String
    var wert: Double
    var hoch: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(Schrift.grotesk(12)).foregroundStyle(wert > 0 ? TafelFarbe.text : TafelFarbe.aus).frame(width: 70, alignment: .leading)
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 2).fill(wert > 0 ? TafelFarbe.gruen.opacity(0.75) : Color.white.opacity(0.1))
                    .frame(width: wert > 0 ? max(3, g.size.width * wert / max(hoch, 1)) : g.size.width, height: wert > 0 ? 6 : 1)
                    .frame(maxHeight: .infinity)
            }
            Text(wert > 0 ? "\(Int(wert).formatted(.number.locale(Locale(identifier: "de_DE")))) KG" : "–").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise).frame(width: 64, alignment: .trailing)
        }
        .frame(height: 12)
    }
}

struct SnStatEigene: View {
    var s: SenecaStatistik.Kennzahlen.Eigene
    var voll: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 0) {
                Text(s.titel).font(Schrift.grotesk(voll ? 17 : 14)).foregroundStyle(Color.white)
                Text(["von \(s.von?.capitalized ?? "einem Mitarbeiter")", s.grund].compactMap { $0 }.joined(separator: " · ")).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise).padding(.top, 4)
            }
            .frame(width: 280, alignment: .leading)
            if s.fehler != nil {
                Text("Diese Statistik ließ sich nicht rechnen. Der Mitarbeiter sieht den Fehler und baut sie neu.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit)
            } else {
                HStack(alignment: .bottom, spacing: 48) {
                    SnStatZahl(wert: s.wert.map { StatistikLogik.zahl($0) } ?? "–", einheit: (s.einheit ?? "").uppercased(), groesse: voll ? 32 : 24).frame(width: 200, alignment: .leading)
                    if s.diagramm != "zahl", let p = s.punkte, p.count > 1 {
                        SnStatBalken(werte: p.compactMap { $0.last?.alsZahl }, farbe: TafelFarbe.bereich(StatistikLogik.lebensbereich(s)), ziel: s.ziel).frame(height: voll ? 60 : 36)
                    }
                }
            }
        }
        .padding(.vertical, voll ? 30 : 0).padding(.bottom, voll ? 0 : 26)
        .overlay(alignment: .top) { if voll { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) } }
        .opacity(s.grau == true ? 0.45 : 1)
    }
}
