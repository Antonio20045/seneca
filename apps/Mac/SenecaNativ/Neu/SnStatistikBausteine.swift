import SwiftUI

struct SnStatSatz: View {
    var teile: [String]
    var groesse: CGFloat

    var body: some View {
        (Text(teile.first ?? "") + Text(teile.dropFirst().map { " " + $0 }.joined()).font(Schrift.serif(groesse, kursiv: true)).foregroundColor(TafelFarbe.akzent))
            .font(Schrift.serif(groesse)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
    }
}

struct SnStatFlaeche<Inhalt: View>: View {
    @ViewBuilder var inhalt: Inhalt

    var body: some View {
        inhalt.padding(.horizontal, 22).padding(.vertical, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).snFlaeche(18, deckkraft: 0.05)
    }
}

struct SnStatTitel: View {
    var titel: String
    var buch: String?

    var body: some View {
        (Text(titel) + Text(buch == nil ? "" : " · ") + Text(buch ?? "").font(Schrift.serif(16, kursiv: true))).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit)
    }
}

struct SnStatKopf: View {
    var titel: String
    var zusatz: String
    var rechts: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text(titel).foregroundColor(.white) + Text(zusatz.isEmpty ? "" : " · " + zusatz).foregroundColor(TafelFarbe.leise)).font(Schrift.grotesk(15))
            Spacer()
            Text(rechts).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
        }
    }
}

struct SnStatZahl: View {
    var wert: String
    var einheit: String
    var unter: String?
    var groesse: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(wert).font(Schrift.grotesk(groesse, .medium)).kerning(-groesse / 50).foregroundStyle(Color.white)
                Text(einheit).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
            }
            if let unter { Text(unter).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise) }
        }
    }
}

struct SnStatFortschritt: View {
    var anteil: Double
    var rechts: String
    var farbe = TafelFarbe.gruen

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(farbe).frame(width: g.size.width * min(1, max(0, anteil)))
                }
            }
            .frame(height: 3)
            Text(rechts).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).fixedSize()
        }
    }
}

struct SnStatWertZeile: View {
    var name: String
    var wert: String?
    var einheit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
            Spacer()
            Text(wert ?? "–").font(Schrift.grotesk(22, .medium)).foregroundStyle(wert == nil ? TafelFarbe.aus : Color.white)
            Text(einheit).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise).frame(width: 26, alignment: .leading)
        }
    }
}

struct SnStatListenZeile: View {
    var links: String
    var mitte: String
    var rechts: String
    var unter: String?
    var hervor: String?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(links).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(mitte).font(Schrift.grotesk(15)).foregroundStyle(Color.white)
                    if let unter { Text(unter).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise) }
                }
                Text(hervor ?? rechts).font(Schrift.mono(11)).foregroundStyle(hervor == nil ? TafelFarbe.leise : TafelFarbe.gruen).frame(width: 84, alignment: .trailing)
            }
            .padding(.vertical, 13)
        }
    }
}

struct SnStatBalken: View {
    var werte: [Double]
    var farbe: Color
    var beschriftung: [String]?
    var ziel: Double?

    var body: some View {
        let hoch = max(werte.max() ?? 0, ziel ?? 0, 0.0001), leer = !werte.contains { $0 > 0 }
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .bottomLeading) {
                    if leer { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
                    HStack(alignment: .bottom, spacing: werte.count > 20 ? 2 : 6) {
                        ForEach(Array(werte.enumerated()), id: \.offset) { _, v in
                            RoundedRectangle(cornerRadius: werte.count > 20 ? 1 : 3).fill(v > 0 ? farbe : Color.white.opacity(leer ? 0 : 0.12))
                                .frame(height: v > 0 ? max(4, g.size.height * v / hoch) : 2).frame(maxWidth: .infinity)
                        }
                    }
                    if let ziel {
                        Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1).offset(y: -g.size.height * ziel / hoch)
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .bottomLeading)
            }
            if let beschriftung {
                HStack(spacing: 6) { ForEach(beschriftung, id: \.self) { Text($0).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).frame(maxWidth: .infinity) } }
            }
        }
    }
}

struct SnBewegungRaster: View {
    var raster: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(raster.enumerated()), id: \.offset) { m, tage in
                HStack(spacing: 3) {
                    Text(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"][m % 12]).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).frame(width: 16, alignment: .leading)
                    ForEach(Array(tage.enumerated()), id: \.offset) { _, t in
                        RoundedRectangle(cornerRadius: 2).fill(t.hasSuffix("2") ? TafelFarbe.gruen : t.hasSuffix("1") ? TafelFarbe.gruen.opacity(0.45) : Color.white.opacity(t == " " ? 0.04 : 0.07))
                            .overlay { if t.hasPrefix("h") { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white, lineWidth: 1.5) } }
                            .frame(width: 11, height: 11)
                    }
                }
            }
            HStack(spacing: 16) {
                ForEach([("LAUFEN ODER KRAFT", 0.45), ("BEIDES ODER LANG", 1.0)], id: \.0) { t, o in
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(TafelFarbe.gruen.opacity(o)).frame(width: 9, height: 9); Text(t).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise) }
                }
            }
            .padding(.top, 10)
        }
    }
}

struct SnWegZu100: View {
    var weg: [StatWegWoche]

    var body: some View {
        GeometryReader { g in
            let breite = g.size.width - 44, hoehe = g.size.height - 30, schritt = breite / CGFloat(max(1, weg.count))
            let y = { (v: Double) in (1 - CGFloat(v / 100)) * hoehe }
            let heute = weg.lastIndex { !$0.plan } ?? 0
            let bester = weg.indices.filter { !weg[$0].plan }.max { weg[$0].lang < weg[$1].lang }
            ZStack(alignment: .topLeading) {
                ForEach([30.0, 60.0], id: \.self) { v in
                    Rectangle().fill(Color.white.opacity(0.07)).frame(width: breite + 44, height: 1).offset(y: y(v))
                    Text("\(Int(v)) km").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).offset(y: y(v) - 15)
                }
                Path { p in p.move(to: CGPoint(x: 0, y: y(100))); p.addLine(to: CGPoint(x: breite + 30, y: y(100))) }.stroke(TafelFarbe.gruen.opacity(0.4), lineWidth: 1)
                Text("100 km am Stück").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.gruen).offset(y: y(100) - 16)
                Text("ca. Juni").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.gruen).position(x: breite + 4, y: y(100) - 12)
                Circle().fill(TafelFarbe.gruen).frame(width: 9, height: 9).position(x: breite + 30, y: y(100))
                ForEach(Array(weg.enumerated()), id: \.offset) { i, w in
                    let mitte = CGFloat(i) * schritt + schritt / 2 + 22
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5).fill(w.km > 0 ? (w.plan ? TafelFarbe.himmel.opacity(0.22) : TafelFarbe.gruen.opacity(0.4)) : Color.white.opacity(0.1)).frame(height: max(2, hoehe * w.km / 100))
                        RoundedRectangle(cornerRadius: 1.5).fill(w.plan ? TafelFarbe.himmel.opacity(0.55) : TafelFarbe.gruen).frame(height: w.lang > 0 ? hoehe * w.lang / 100 : 0)
                    }
                    .frame(width: schritt * 0.62, height: hoehe, alignment: .bottom).position(x: mitte, y: hoehe / 2)
                    if i == 0 || StatistikLogik.monatKurz(w.iso) != StatistikLogik.monatKurz(weg[i - 1].iso) {
                        Text(StatistikLogik.monatKurz(w.iso)).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.aus).position(x: mitte + 8, y: hoehe + 18)
                    }
                    if i == bester, w.lang > 0 {
                        Text(StatistikLogik.zahl(w.lang)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.gruen).position(x: mitte, y: y(w.lang) - 10)
                    }
                    if i == heute {
                        Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: hoehe - y(70)).position(x: mitte, y: (hoehe + y(70)) / 2)
                        Text("HEUTE").font(Schrift.mono(10)).foregroundStyle(Color.white).position(x: mitte, y: y(70) - 10)
                    }
                }
            }
        }
    }
}

struct SnStatLegende: View {
    var eintraege: [(String, Color)]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(eintraege, id: \.0) { t, f in
                HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(f).frame(width: 9, height: 9); Text(t).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise) }
            }
        }
    }
}
