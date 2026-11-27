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

    private func farbe(_ art: String) -> Color { art == "lesen" ? TafelFarbe.akzent : art == "gewicht" ? TafelFarbe.zweit : TafelFarbe.gruen }

    var body: some View {
        let w = daten.woche
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    Text("Diese Woche").font(Schrift.serif(40)).foregroundStyle(Color.white)
                    Text(StatistikLogik.zeitraum(w.kopf, stand: stand)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(["Woche", "Monat", "Jahr"], id: \.self) { r in
                            Text(r).font(Schrift.grotesk(13, .medium)).foregroundStyle(r == "Woche" ? Color.white : TafelFarbe.zweit)
                                .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(r == "Woche" ? 0.14 : 0)))
                        }
                    }
                    .padding(3).background(Capsule().fill(Color.white.opacity(0.06)))
                }
                (Text(w.satz.first ?? "") + Text(w.satz.dropFirst().map { " " + $0 }.joined()).italic().foregroundColor(TafelFarbe.akzent))
                    .font(Schrift.serif(28)).foregroundStyle(Color.white).padding(.top, 22)
                HStack(alignment: .top, spacing: 16) { ForEach(w.karten) { karte($0) } }.padding(.top, 26)
                GeometryReader { g in
                    HStack(alignment: .top, spacing: 16) {
                        if let u = daten.uebung { uebung(u).frame(width: (g.size.width - 16) * 1.15 / 2.15) }
                        if let j = daten.jahr { bewegung(j).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
                    }
                }
                .frame(height: 290).padding(.top, 56)
                if let h = w.hinweis {
                    HStack(spacing: 14) { SnKugel(groesse: 10, atmet: false); Text(h).font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.zweit) }.padding(.top, 52)
                }
            }
            .padding(.horizontal, 96).padding(.top, 90).padding(.bottom, 40)
        }
        .scrollIndicators(.never)
    }

    private func flaeche<V: View>(@ViewBuilder _ inhalt: () -> V) -> some View {
        inhalt().padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .topLeading).snFlaeche(18, deckkraft: 0.05)
    }

    private func karte(_ k: SenecaStatistik.Karte) -> some View {
        flaeche {
            VStack(alignment: .leading, spacing: 0) {
                (Text(k.titel) + Text(k.buch == nil ? "" : " · ") + Text(k.buch ?? "").font(Schrift.serif(16, kursiv: true))).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(k.wert).font(Schrift.grotesk(40, .medium)).kerning(-0.8).foregroundStyle(Color.white)
                    Text(k.einheit).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                }
                .padding(.top, 8)
                HStack(spacing: 10) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(k.art == "gewicht" ? TafelFarbe.zweit : farbe(k.art)).frame(width: g.size.width * min(1, k.anteil ?? (k.art == "gewicht" ? 0.6 : 0)))
                        }
                    }
                    .frame(height: 3)
                    Text(k.rechts).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).fixedSize()
                }
                .padding(.top, 12).padding(.bottom, 14)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(k.tage.enumerated()), id: \.offset) { i, t in
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            if k.art == "gewicht" {
                                Text(t.wert.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? (t.zustand == "leer" ? "–" : " "))
                                    .font(Schrift.grotesk(11)).foregroundStyle(TafelFarbe.zweit).fixedSize()
                                Circle().fill(t.zustand == "da" ? Color.white.opacity(0.85) : Color.clear).overlay(Circle().strokeBorder(Color.white.opacity(t.zustand == "kommt" ? 0.12 : 0.6), lineWidth: 1.5)).frame(width: 9, height: 9)
                            } else if t.zustand == "da" {
                                RoundedRectangle(cornerRadius: 3).fill(farbe(k.art)).frame(height: max(6, 54 * (t.hoehe ?? 0.6)))
                            } else {
                                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(t.zustand == "kommt" ? 0.05 : 0.14)).frame(height: 3)
                            }
                            Text(["MO", "DI", "MI", "DO", "FR", "SA", "SO"][i]).font(Schrift.mono(10)).foregroundStyle(t.heute ? Color.white : TafelFarbe.aus)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 80)
                    }
                }
                .frame(height: 80)
            }
        }
    }

    private func uebung(_ u: SenecaStatistik.Uebung) -> some View {
        let p = StatistikLogik.achtWochen(u)
        let kg = p.compactMap(\.kg), lo = (kg.min() ?? 0) - 2.5, hi = (kg.max() ?? 1) + 2.5
        return flaeche {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    (Text(u.titel.trimmingCharacters(in: CharacterSet(charactersIn: "."))).foregroundColor(.white) + Text(" · bester Satz je Woche").foregroundColor(TafelFarbe.leise)).font(Schrift.grotesk(15))
                    Spacer()
                    Text("\(p.count) WOCHEN").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                }
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
                    }
                }
                .frame(height: 190)
                if let s = StatistikLogik.heuteSatz(u.zeilen.first) ?? (u.satz.isEmpty ? nil : u.satz) { Text(s).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text) }
            }
        }
    }

    private func bewegung(_ j: SenecaStatistik.Raster) -> some View {
        flaeche {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    (Text("Bewegung").foregroundColor(.white) + Text(" · Laufen und Kraft").foregroundColor(TafelFarbe.leise)).font(Schrift.grotesk(15))
                    Spacer()
                    Text(String(Calendar.current.component(.year, from: Date(timeIntervalSince1970: stand / 1000)))).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(j.raster.enumerated()), id: \.offset) { m, tage in
                        HStack(spacing: 3) {
                            Text(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"][m]).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).frame(width: 16, alignment: .leading)
                            ForEach(Array(tage.enumerated()), id: \.offset) { _, t in
                                RoundedRectangle(cornerRadius: 2).fill(t.hasSuffix("2") ? TafelFarbe.gruen : t.hasSuffix("1") ? TafelFarbe.gruen.opacity(0.45) : Color.white.opacity(t == " " ? 0.04 : 0.07))
                                    .overlay { if t.hasPrefix("h") { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white, lineWidth: 1.5) } }
                                    .frame(width: 11, height: 11)
                            }
                        }
                    }
                }
            }
        }
    }
}
