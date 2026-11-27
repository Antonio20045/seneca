import SwiftUI

struct SnStatistikEcht: View {
    @ObservedObject var store: SenecaStore
    @State private var daten: SenecaStatistik?
    @State private var stand: Double = 0

    var body: some View {
        Group {
            if let daten { SnStatistikTafel(daten: daten, stand: stand) } else { SnHeuteSkelett() }
        }
        .task(id: store.stand?.revision) {
            guard let j = try? await store.rufe("seneca.stand", params: ["geraet": "mac", "sicht": "statistik"]),
                  let roh = try? JSONSerialization.data(withJSONObject: j) else { return }
            daten = try? JSONDecoder().decode(SenecaStatistik.self, from: roh)
            stand = Date().timeIntervalSince1970 * 1000
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
                SnStatSatz(teile: StatistikLogik.satz(daten, zeitraum), groesse: 28).padding(.top, 22)
                laufen.padding(.top, 34)
                HStack(alignment: .top, spacing: 16) { kraft; lesen; koerper }.fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                if zeitraum == .jahr, let j = daten.jahr { jahr(j).padding(.top, 16) }
                mitarbeiter.padding(.top, 56)
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
        return SnStatKachel(bereich: .laufen, oeffne: wechsle) {
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 0) {
                    SnStatTitel(titel: "Laufen")
                    SnStatZahl(wert: summe?[0] ?? StatistikLogik.zahl(km), einheit: summe?[1] ?? "KM").padding(.top, 8)
                    if zeitraum == .woche, let ziel {
                        SnStatFortschritt(anteil: km / max(1, ziel.km), rechts: "VON \(StatistikLogik.zahl(ziel.km)) KM").padding(.top, 12)
                    }
                    Text(leer ? seit.map { "Seit \(StatistikLogik.datum($0, lang: true)) kein Lauf." } ?? "Noch kein Lauf." : summe.map { String($0[2].dropFirst("Laufen, ".count)) } ?? "Längster Lauf \(StatistikLogik.zahl(k?.lauf.lang.last ?? 0)) km.")
                        .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).padding(.top, 16)
                    if let t = k?.lauf.trendKm {
                        Text("TREND \(t >= 0 ? "+" : "−")\(StatistikLogik.zahl(abs(t))) KM JE WOCHE").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).padding(.top, 6)
                    }
                }
                .frame(width: 300, alignment: .leading)
                if let k {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Der Weg zu 100 km").font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
                            Spacer()
                            Text("LÄNGSTER LAUF JE WOCHE").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus)
                        }
                        SnWegLinie(weg: StatistikLogik.weg(k)).frame(height: 104)
                    }
                }
            }
        }
    }

    private var kraft: some View {
        let karte = StatistikLogik.karte(daten, "kraft"), summe = StatistikLogik.summe(daten, zeitraum, "Kraft"), best = k.flatMap { StatistikLogik.bestwerte($0).first }
        let reihe = zeitraum == .woche ? (karte?.tage ?? []).map { $0.zustand == "da" ? 1 : 0 } : (k?.kraft.tage ?? []).suffix(zeitraum == .monat ? 5 : 52).map(Double.init)
        return SnStatKachel(bereich: .kraft, oeffne: wechsle) {
            VStack(alignment: .leading, spacing: 0) {
                SnStatTitel(titel: "Krafttraining")
                SnStatZahl(wert: summe?[0] ?? karte?.wert ?? "0", einheit: summe?[1] ?? karte?.einheit ?? "MAL").padding(.top, 8)
                Text("LETZTER BESTWERT").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).padding(.top, 16)
                Text(best.map { "\($0.name) \(StatistikLogik.zahl($0.kg)) kg × \($0.wdh) · \(StatistikLogik.datum($0.iso))" } ?? "Noch keiner.")
                    .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).lineLimit(1).padding(.top, 4)
                Spacer(minLength: 18)
                SnStatBalken(werte: reihe, farbe: TafelFarbe.gruen, beschriftung: zeitraum == .woche ? ["MO", "DI", "MI", "DO", "FR", "SA", "SO"] : nil).frame(height: 46)
            }
        }
    }

    private var lesen: some View {
        let karte = StatistikLogik.karte(daten, "lesen"), summe = StatistikLogik.summe(daten, zeitraum, "Lesen"), b = daten.buch
        return SnStatKachel(bereich: .lesen, oeffne: wechsle) {
            VStack(alignment: .leading, spacing: 0) {
                SnStatTitel(titel: "Lesen", buch: b?.titel.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                SnStatZahl(wert: summe?[0] ?? karte?.wert ?? "0:00", einheit: summe?[1] ?? karte?.einheit ?? "STD").padding(.top, 8)
                if let a = b?.anteil {
                    SnStatFortschritt(anteil: a, rechts: b?.prozent ?? "", farbe: TafelFarbe.akzent).padding(.top, 12)
                }
                Text("ZULETZT").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).padding(.top, 16)
                Text(b?.zuletzt.first.map { "\($0.links.capitalized) · \($0.wert)" } ?? "Noch nichts gelesen.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).padding(.top, 4)
                Spacer(minLength: 18)
                if zeitraum == .woche {
                    SnStatBalken(werte: (karte?.tage ?? []).map { $0.zustand == "da" ? $0.hoehe ?? 0.6 : 0 }, farbe: TafelFarbe.akzent, beschriftung: ["MO", "DI", "MI", "DO", "FR", "SA", "SO"]).frame(height: 46)
                }
            }
        }
    }

    private var koerper: some View {
        let heute = StatistikLogik.letzteTage(stand, 1).first ?? "", n = k?.koerper.nacht.last, g = k?.koerper.gewicht.last, summe = StatistikLogik.summe(daten, zeitraum, "Gewicht")
        return SnStatKachel(bereich: .koerper, oeffne: wechsle) {
            VStack(alignment: .leading, spacing: 0) {
                SnStatTitel(titel: "Körper")
                VStack(alignment: .leading, spacing: 12) {
                    SnStatWertZeile(name: n?.first?.alsText == heute ? "Schlaf heute Nacht" : "Schlaf", wert: n?[1].alsZahl.map(StatistikLogik.stunden), einheit: "STD")
                    SnStatWertZeile(name: "HRV", wert: n?[7].alsZahl.map { StatistikLogik.zahl($0, 0) }, einheit: "MS")
                    SnStatWertZeile(name: g?.first?.alsText.map { "Gewicht · \(StatistikLogik.datum($0))" } ?? "Gewicht", wert: g?[1].alsZahl.map { StatistikLogik.zahl($0) }, einheit: "KG")
                }
                .padding(.top, 14)
                if let summe {
                    Text("\(summe[0]) KG · \(summe[2].dropFirst("Gewicht ".count))".uppercased()).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).padding(.top, 14)
                }
            }
        }
    }

    private func jahr(_ j: SenecaStatistik.Raster) -> some View {
        HStack(alignment: .top, spacing: 16) {
            SnStatFlaeche {
                VStack(alignment: .leading, spacing: 14) {
                    SnStatKopf(titel: "Bewegung", zusatz: "Laufen und Kraft", rechts: j.kopf.uppercased())
                    SnBewegungRaster(raster: j.raster)
                }
            }
            SnStatFlaeche {
                VStack(alignment: .leading, spacing: 0) {
                    SnStatKopf(titel: "Bestwerte", zusatz: "dieses Jahr", rechts: "")
                    ForEach(Array(StatistikLogik.bestwerteJahr(j).enumerated()), id: \.offset) { _, b in
                        SnStatListenZeile(links: b[0], mitte: b[1], rechts: b[2])
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var mitarbeiter: some View {
        VStack(alignment: .leading, spacing: 16) {
            SnStatKopf(titel: "Von deinen Mitarbeitern", zusatz: "im Gespräch angelegt", rechts: "")
            if let eigene = k?.statistiken, !eigene.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(eigene) { SnStatEigene(s: $0) }
                }
            } else {
                Text("Noch keine. Sag dem Trainer „Zeig mir … als Grafik“, dann steht sie hier.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise)
            }
        }
    }
}

struct SnStatKachel<Inhalt: View>: View {
    var bereich: StatBereich
    var oeffne: (StatBereich) -> Void
    @ViewBuilder var inhalt: Inhalt
    @State private var ueber = false

    var body: some View {
        Button { oeffne(bereich) } label: {
            inhalt.padding(.horizontal, 22).padding(.vertical, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .snFlaeche(18, deckkraft: ueber ? 0.085 : 0.05)
                .overlay(alignment: .topTrailing) {
                    Text("DETAILS ›").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.zweit).padding(.top, 20).padding(.trailing, 22).opacity(ueber ? 1 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { ueber = h } }
        .accessibilityElement(children: .ignore).accessibilityLabel(bereich.rawValue).accessibilityAddTraits(.isButton)
    }
}

struct SnStatEigene: View {
    var s: SenecaStatistik.Kennzahlen.Eigene

    var body: some View {
        SnStatFlaeche {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.titel).font(Schrift.grotesk(15)).foregroundStyle(Color.white)
                    Spacer()
                    Text((s.von ?? "").uppercased()).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise)
                }
                if let g = s.grund { Text(g).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 4) }
                if s.fehler != nil {
                    Text("Diese Statistik ließ sich nicht rechnen. Der Mitarbeiter sieht den Fehler und baut sie neu.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit).padding(.top, 14)
                } else {
                    SnStatZahl(wert: s.wert.map { StatistikLogik.zahl($0) } ?? "–", einheit: (s.einheit ?? "").uppercased(), groesse: 32).padding(.top, 12)
                    if s.diagramm != "zahl", let p = s.punkte, p.count > 1 {
                        SnStatBalken(werte: p.compactMap { $0.last?.alsZahl }, farbe: TafelFarbe.gruen, ziel: s.ziel).frame(height: 60).padding(.top, 14)
                    }
                }
            }
        }
    }
}
