import SwiftUI

private let statTon: [Double] = [0, 0.4, 0.6, 0.8, 1]

func statSatz(_ s: String, _ stufe: Stil.Schrift, farbe: Color = Stil.tinte.voll) -> Text {
    var t = Text("")
    for (i, teil) in s.components(separatedBy: "*").enumerated() where !teil.isEmpty {
        let kursiv = i % 2 == 1
        let basis = Text(teil).foregroundStyle(farbe)
        switch stufe {
        case .gross, .titel, .sache, .zahl: t = t + basis.font(kursiv ? stufe.kursiv : stufe.font)
        default: t = t + (kursiv ? basis.font(stufe.font).italic() : basis.font(stufe.font))
        }
    }
    return t
}

func statWort(_ s: String) -> String {
    s.replacingOccurrences(of: "Pace", with: "Tempo").replacingOccurrences(of: "Trainings", with: "Einheiten")
}

struct StatDetailText: View {
    var text: String
    var leise = false
    var body: some View {
        statSatz(statWort(text), .text, farbe: leise ? Stil.tinte.leise : Stil.tinte.zweit)
            .lineSpacing(Stil.Schrift.text.zeilenAbstand)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatKlein: View {
    var text: String
    var betont = false
    var body: some View {
        Text(text).schrift(.klein).foregroundStyle(betont ? Stil.tinte.voll : Stil.tinte.zweit)
    }
}

struct StatWerteView: View {
    var werte: [StatWert]
    var spalten = 3
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Stil.abstand.m, alignment: .topLeading), count: spalten),
                  alignment: .leading, spacing: Stil.abstand.l) {
            ForEach(Array(werte.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                    Text(w.wert).schrift(.sache).foregroundStyle(Stil.tinte.voll).lineLimit(1).minimumScaleFactor(0.7)
                    Text(statWort(w.name)).schrift(.klein).foregroundStyle(Stil.tinte.zweit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct StatEnden: View {
    var links: String
    var rechts: String
    var body: some View {
        HStack {
            StatKlein(text: links)
            Spacer(minLength: Stil.abstand.m)
            StatKlein(text: rechts, betont: true)
        }
    }
}

struct StatVisualView: View {
    var v: StatVisual
    var breite: CGFloat

    var body: some View {
        switch v {
        case .laufKarte(let k): StatLaufKarteView(k: k, breite: breite)
        case .tagesbalken(let t): StatTagesbalkenView(t: t)
        case .trainingPunkte(let p): StatPunkteView(punkte: p)
        case .fortschritt(let f): StatFortschrittView(f: f, hoehe: 6)
        case .monatsRaster(let b, let z): StatMonatsRasterView(zellen: z).accessibilityElement().accessibilityLabel(b)
        case .jahresRaster(let r): StatJahresRasterView(r: r)
        case .linie(let b, let l):
            VStack(alignment: .leading, spacing: Stil.abstand.s) {
                if let b { StatKlein(text: statWort(b)) }
                StatLinieView(l: l, hoehe: 64)
            }
        case .uebungen(let z): StatUebungenView(zeilen: z)
        case .gewicht(let g): StatGewichtView(g: g)
        case .monatsBalken(let b): StatMonatsBalkenView(b: b)
        case .buecher(let b): StatBuecherZeitView(buecher: b)
        case .zeitZeilen(let z):
            VStack(alignment: .leading, spacing: Stil.abstand.s) {
                ForEach(Array(z.enumerated()), id: \.offset) { _, zeile in
                    HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.m) {
                        StatKlein(text: zeile.zeit).frame(width: 48, alignment: .leading)
                        StatDetailText(text: zeile.text)
                    }
                }
            }
        case .jahresAchse:
            HStack { ForEach(["Jan", "Apr", "Jul", "Okt", "Dez"], id: \.self) { m in StatKlein(text: m); if m != "Dez" { Spacer() } } }
        }
    }
}

struct StatLaufKarteView: View {
    var k: StatLaufKarte
    var breite: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.l) {
            StatWerteView(werte: k.werte)
            if !k.kmZeilen.isEmpty {
                let maxB = max(60, breite - 36 - 44 - 3 * Stil.abstand.m)
                VStack(alignment: .leading, spacing: Stil.abstand.s) {
                    ForEach(Array(k.kmZeilen.enumerated()), id: \.offset) { _, z in
                        HStack(spacing: Stil.abstand.m) {
                            StatKlein(text: z.label).lineLimit(1).frame(width: 36, alignment: .leading)
                            Capsule()
                                .fill(z.rang == 0 ? Stil.tinte.voll : z.rang == 1 ? Stil.farbe.himmel : Stil.farbe.himmel.opacity(z.ton))
                                .frame(width: maxB * z.laenge, height: 6)
                            Spacer(minLength: 0)
                            StatKlein(text: z.zeit).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zeit pro Kilometer: " + k.kmZeilen.map { "\($0.label) \($0.zeit)" }.joined(separator: ", "))
            }
            if let s = k.satz { StatDetailText(text: s) }
        }
    }
}

struct StatTagesbalkenView: View {
    var t: StatTagesbalken
    var body: some View {
        HStack(alignment: .bottom, spacing: Stil.abstand.s) {
            ForEach(Array(t.balken.enumerated()), id: \.offset) { _, b in
                VStack(spacing: Stil.abstand.xs) {
                    if b.da {
                        StatKlein(text: b.text ?? "", betont: b.heute)
                        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 4)
                            .fill(b.heute ? Stil.tinte.voll : Stil.farbe.himmel)
                            .frame(width: 20, height: max(3, 72 * b.anteil))
                    } else if t.leerKreis {
                        Circle().stroke(Stil.tinte.leise, lineWidth: 1).frame(width: 8, height: 8)
                    } else {
                        StatKlein(text: "–")
                    }
                    StatKlein(text: b.tag, betont: b.heute)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 112, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.balken.map { ($0.text ?? "nichts") }.joined(separator: ", "))
    }
}

struct StatPunkteView: View {
    var punkte: [StatPunkt]
    var body: some View {
        HStack(alignment: .top, spacing: Stil.abstand.s) {
            ForEach(Array(punkte.enumerated()), id: \.offset) { _, p in
                VStack(spacing: Stil.abstand.xs) {
                    Circle().fill(p.an ? Stil.farbe.himmel : Color.clear)
                        .overlay(Circle().strokeBorder(p.an ? Stil.farbe.himmel : Stil.tinte.leise, lineWidth: 1))
                        .frame(width: 14, height: 14)
                    StatKlein(text: p.tag, betont: p.heute)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(punkte.map { "\($0.tag) \($0.an ? "trainiert" : "nichts")" }.joined(separator: ", "))
    }
}

struct StatFortschrittView: View {
    var f: StatFortschritt
    var hoehe: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            if f.anteil > 0 || f.rechts != nil {
                Capsule().fill(Stil.tinte.flaecheStark)
                    .frame(height: hoehe)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(f.anteil >= 1 ? Stil.farbe.gruen : Stil.farbe.himmel)
                                .frame(width: max(hoehe, g.size.width * min(1, f.anteil)))
                        }
                    }
            }
            HStack(alignment: .firstTextBaseline) {
                StatDetailText(text: f.links)
                Spacer(minLength: Stil.abstand.m)
                if let r = f.rechts { StatKlein(text: r) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([f.links, f.rechts].compactMap { $0 }.joined(separator: ", "))
    }
}

struct StatMonatsRasterView: View {
    var zellen: [StatZelle]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Stil.abstand.xs), count: 7), spacing: Stil.abstand.xs) {
            ForEach(Array(zellen.enumerated()), id: \.offset) { _, z in
                ZStack(alignment: .topLeading) {
                    if let tag = z.tag {
                        if z.stufe > 0 {
                            RoundedRectangle(cornerRadius: Stil.radius.klein, style: .continuous).fill(Stil.farbe.himmel.opacity(statTon[min(4, z.stufe)]))
                        } else if !z.zukunft {
                            RoundedRectangle(cornerRadius: Stil.radius.klein, style: .continuous).strokeBorder(Stil.tinte.linie, lineWidth: 1)
                        }
                        Text("\(tag)").schrift(.klein)
                            .foregroundStyle(z.stufe >= 3 ? Stil.farbe.aufHell : z.zukunft ? Stil.tinte.leise : Stil.tinte.zweit)
                            .padding(.horizontal, Stil.abstand.s).padding(.vertical, Stil.abstand.xs)
                    }
                }
                .frame(height: 36)
            }
        }
    }
}

struct StatJahresRasterView: View {
    var r: StatJahresRaster
    var body: some View {
        Canvas { ctx, size in
            let w = (size.width - CGFloat(r.spalten - 1)) / CGFloat(r.spalten)
            for (s, spalte) in r.felder.enumerated() {
                for (z, wert) in spalte.enumerated() where wert != -1 {
                    let farbe: Color = wert == -2 ? Stil.tinte.linie : wert == 0 ? Stil.tinte.flaeche : Stil.farbe.himmel.opacity(statTon[min(4, wert)])
                    ctx.fill(Path(roundedRect: CGRect(x: CGFloat(s) * (w + 1), y: CGFloat(z) * 6, width: w, height: 5), cornerRadius: 1), with: .color(farbe))
                }
            }
        }
        .frame(height: 47)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jahreskalender: jeder gelaufene Tag als Feld")
    }
}

struct StatLinieView: View {
    var l: StatLinie
    var hoehe: CGFloat
    var body: some View {
        VStack(spacing: Stil.abstand.s) {
            Canvas { ctx, size in
                guard l.werte.count >= 2, let lo = l.werte.min(), let hi = l.werte.max() else { return }
                let spanne = max(hi - lo, 0.0001)
                let oben: CGFloat = 6, unten = size.height - 6
                func punkt(_ i: Int) -> CGPoint {
                    let x = (l.xs.count == l.werte.count ? l.xs[i] : Double(i) / Double(l.werte.count - 1)) * size.width
                    var n = (l.werte[i] - lo) / spanne
                    if l.kleinerIstBesser { n = 1 - n }
                    return CGPoint(x: min(size.width - 4, max(4, x)), y: unten - CGFloat(n) * (unten - oben))
                }
                var pfad = Path()
                for i in l.werte.indices { i == 0 ? pfad.move(to: punkt(i)) : pfad.addLine(to: punkt(i)) }
                ctx.stroke(pfad, with: .color(Stil.farbe.himmel), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                let e = punkt(l.werte.count - 1)
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - 4, y: e.y - 4, width: 8, height: 8)), with: .color(Stil.tinte.voll))
            }
            .frame(height: hoehe)
            StatEnden(links: l.links, rechts: l.rechts)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verlauf von \(l.links) auf \(l.rechts)")
    }
}

struct StatMiniLinie: View {
    var werte: [Double]
    var body: some View {
        Canvas { ctx, size in
            guard werte.count >= 2, let lo = werte.min(), let hi = werte.max() else { return }
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: 4 + (size.width - 8) * CGFloat(i) / CGFloat(werte.count - 1),
                        y: size.height - 5 - CGFloat(hi == lo ? 0.5 : (werte[i] - lo) / (hi - lo)) * (size.height - 10))
            }
            var p = Path()
            for i in werte.indices { i == 0 ? p.move(to: pt(i)) : p.addLine(to: pt(i)) }
            ctx.stroke(p, with: .color(Stil.farbe.himmel), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let e = pt(werte.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3, y: e.y - 3, width: 6, height: 6)), with: .color(Stil.tinte.voll))
        }
        .frame(width: 64, height: 28)
        .accessibilityHidden(true)
    }
}

struct StatUebungenView: View {
    var zeilen: [StatUebungZeile]
    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.m) {
            ForEach(Array(zeilen.enumerated()), id: \.offset) { _, z in
                HStack(spacing: Stil.abstand.m) {
                    Text(z.name).schrift(.zeileWichtig).foregroundStyle(Stil.tinte.voll).lineLimit(1)
                        .frame(width: 112, alignment: .leading)
                    StatMiniLinie(werte: z.werte)
                    StatDetailText(text: z.text).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }
}

struct StatGewichtView: View {
    var g: StatGewichtDiagramm
    var body: some View {
        VStack(spacing: Stil.abstand.s) {
            Canvas { ctx, size in
                let alle = g.punkte.map(\.y) + g.trend.map(\.y)
                guard let lo0 = alle.min(), let hi0 = alle.max() else { return }
                let mitte = (lo0 + hi0) / 2, halb = max((hi0 - lo0) / 2, 0.4)
                let lo = mitte - halb, hi = mitte + halb
                let oben: CGFloat = 8, unten = size.height - 8
                func pt(_ p: StatXY) -> CGPoint {
                    CGPoint(x: 6 + p.x * (size.width - 12), y: oben + CGFloat((hi - p.y) / (hi - lo)) * (unten - oben))
                }
                var linie = Path()
                for (i, p) in g.trend.enumerated() { i == 0 ? linie.move(to: pt(p)) : linie.addLine(to: pt(p)) }
                let r: CGFloat = g.hoehe < 100 ? 4 : 3
                for p in g.punkte {
                    let c = pt(p)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Stil.tinte.zweit))
                }
                ctx.stroke(linie, with: .color(Stil.farbe.himmel), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .frame(height: g.hoehe)
            if let a = g.links, let e = g.rechts { StatEnden(links: a, rechts: e) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gewichtsverlauf mit Trendlinie")
    }
}

struct StatMonatsBalkenView: View {
    var b: StatMonatsBalken
    var body: some View {
        let hoechster = max(b.werte.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: Stil.abstand.xs) {
            ForEach(Array(b.werte.enumerated()), id: \.offset) { i, v in
                VStack(spacing: Stil.abstand.xs) {
                    if v > 0 {
                        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 4)
                            .fill(i == b.aktuell ? Stil.tinte.voll : i == b.hervor ? Stil.farbe.himmel : Stil.farbe.himmel.opacity(statTon[2]))
                            .frame(height: max(3, 76 * v / hoechster))
                    } else {
                        Capsule().fill(Stil.tinte.linie).frame(height: 2)
                    }
                    StatKlein(text: b.namen[i]).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 104, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(b.beschreibung)
    }
}

struct StatBuecherZeitView: View {
    var buecher: [StatBuchBalken]
    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.m) {
            ForEach(Array(buecher.enumerated()), id: \.offset) { _, b in
                VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.m) {
                        Text(b.titel).schrift(.zeile).foregroundStyle(Stil.tinte.voll).lineLimit(1)
                        Spacer(minLength: Stil.abstand.xs)
                        StatKlein(text: b.dauer)
                    }
                    Capsule().fill(Stil.tinte.flaecheStark).frame(height: 6)
                        .overlay {
                            GeometryReader { g in
                                Capsule().fill(b.offen ? Stil.tinte.voll : Stil.farbe.himmel)
                                    .frame(width: max(6, g.size.width * (b.bis - b.von)))
                                    .offset(x: g.size.width * b.von)
                            }
                        }
                }
            }
        }
    }
}
