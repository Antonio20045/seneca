import SwiftUI

enum KartenFarbe {
    case weiss, tinte

    var text: Color { Stil.tinte.voll }
    var leise: Color { Stil.tinte.zweit }
    var linie: Color { Stil.tinte.linie }
    var link: Color { Stil.farbe.himmel }

    func ton(_ t: SenecaKarte.Ton?) -> Color {
        guard let t else { return text }
        switch t {
        case .ok: return Stil.farbe.gruen
        case .mittel: return Stil.tinte.zweit
        case .hoch, .warn: return Stil.farbe.bernstein
        case .danger: return Stil.farbe.koralle
        }
    }
}

struct SenecaKarteView: View {
    var karte: SenecaKarte
    var farbe: KartenFarbe
    var k: CGFloat = 1
    @Environment(\.appActions) private var actions
    @State private var dateiFehler: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.l) {
            if karte.marke != nil || karte.titel != nil {
                VStack(alignment: .leading, spacing: Stil.abstand.s) {
                    if let m = karte.marke {
                        HStack(spacing: Stil.abstand.s) {
                            Circle().fill(farbe.ton(m.ton)).frame(width: 7, height: 7)
                            Text(m.text).schrift(.etikett).foregroundStyle(farbe.ton(m.ton))
                        }
                    }
                    if let t = karte.titel {
                        Text(t).schrift(.sache).foregroundStyle(farbe.text)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    }
                }
            }
            if !karte.zahlen.isEmpty { zahlen }
            if let f = karte.fortschritt { fortschritt(f) }
            if let d = karte.diagramm { diagramm(d) }
            if !karte.punkte.isEmpty { punkte }
            if !karte.aufgaben.isEmpty { aufgaben }
            if let t = karte.tabelle { tabelle(t) }
            if let t = karte.text {
                Text(t).schrift(.text).foregroundStyle(farbe.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pfad = karte.bericht { bericht(pfad) }
            if !karte.aktionen.isEmpty { aktionen }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Stil.abstand.s)
    }

    private var zahlen: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Stil.abstand.m, alignment: .topLeading)], alignment: .leading, spacing: Stil.abstand.l) {
            ForEach(Array(karte.zahlen.enumerated()), id: \.offset) { _, z in
                VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                    Text(z.wert).schrift(.sache).foregroundStyle(farbe.ton(z.ton))
                    if let l = z.label { Text(l).schrift(.etikett).foregroundStyle(farbe.leise) }
                    if let d = z.detail { Text(d).schrift(.klein).foregroundStyle(farbe.leise) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func fortschritt(_ f: SenecaKarte.Fortschritt) -> some View {
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            HStack(alignment: .firstTextBaseline) {
                if let t = f.text { Text(t).schrift(.zeile).foregroundStyle(farbe.text) }
                Spacer(minLength: Stil.abstand.s)
                Text(f.wert).schrift(.etikett).foregroundStyle(farbe.leise)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(farbe.linie)
                    Capsule().fill(farbe.text).frame(width: max(4, g.size.width * f.anteil))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func diagramm(_ d: SenecaKarte.Diagramm) -> some View {
        let werte = d.punkte.map(\.wert)
        let hoechster = max(werte.max() ?? 1, 0.0001), kleinster = min(werte.min() ?? 0, 0)
        let hoehe: CGFloat = 88
        func wertText(_ v: Double) -> String { SenecaKarte.zahlText(v) + (d.einheit.map { " " + $0 } ?? "") }
        return VStack(alignment: .leading, spacing: Stil.abstand.s) {
            if d.art == .balken {
                HStack(alignment: .bottom, spacing: Stil.abstand.s) {
                    ForEach(Array(d.punkte.enumerated()), id: \.offset) { i, p in
                        VStack(spacing: Stil.abstand.xs) {
                            if d.punkte.count <= 8 { Text(SenecaKarte.zahlText(p.wert)).schrift(.klein).foregroundStyle(farbe.leise).lineLimit(1).minimumScaleFactor(0.7) }
                            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3)
                                .fill(i == d.punkte.count - 1 ? farbe.text : Stil.tinte.leise)
                                .frame(height: max(3, (hoehe - 16) * CGFloat(max(p.wert - kleinster, 0) / (hoechster - kleinster))))
                            Text(p.label).schrift(.klein).foregroundStyle(farbe.leise).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: hoehe + 22, alignment: .bottom)
            } else {
                Canvas { ctx, size in
                    guard werte.count >= 2 else { return }
                    let lo = werte.min()!, hi = werte.max()!
                    func pt(_ i: Int) -> CGPoint {
                        CGPoint(x: 4 + (size.width - 8) * CGFloat(i) / CGFloat(werte.count - 1),
                                y: size.height - 16 - CGFloat(hi == lo ? 0.5 : (werte[i] - lo) / (hi - lo)) * (size.height - 32))
                    }
                    var pfad = Path()
                    for i in werte.indices { i == 0 ? pfad.move(to: pt(i)) : pfad.addLine(to: pt(i)) }
                    ctx.stroke(pfad, with: .color(farbe.text), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    for i in werte.indices { let c = pt(i); ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(farbe.text)) }
                    let e = pt(werte.count - 1), font = Stil.Schrift.klein.font
                    ctx.draw(Text(wertText(werte.last!)).font(font).foregroundColor(farbe.text), at: CGPoint(x: e.x, y: e.y - 11), anchor: .trailing)
                }
                .frame(height: hoehe + 14)
                HStack {
                    Text(d.punkte.first?.label ?? "").schrift(.klein).foregroundStyle(farbe.leise)
                    Spacer()
                    Text(d.punkte.last?.label ?? "").schrift(.klein).foregroundStyle(farbe.leise)
                }
            }
            if d.art == .balken, let e = d.einheit { Text(e).schrift(.klein).foregroundStyle(farbe.leise) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diagramm: " + d.punkte.map { "\($0.label) \(wertText($0.wert))" }.joined(separator: ", "))
    }

    private var punkte: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.m) {
            ForEach(Array(karte.punkte.enumerated()), id: \.offset) { _, p in
                HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.m) {
                    Circle().fill(p.ton.map { farbe.ton($0) } ?? farbe.leise).frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 1.5 }
                    VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                        Text(p.text).schrift(.text).foregroundStyle(farbe.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let m = p.meta { Text(m).schrift(.klein).foregroundStyle(p.ton.map { farbe.ton($0) } ?? farbe.leise) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var aufgaben: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.m) {
            ForEach(Array(karte.aufgaben.enumerated()), id: \.offset) { _, a in
                HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.m) {
                    ZStack {
                        Circle().stroke(farbe.leise, lineWidth: 1.2)
                        if a.fertig { Circle().fill(farbe.text).padding(Stil.abstand.xs) }
                    }
                    .frame(width: 16, height: 16)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                    VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                        Text(a.text).schrift(.text).foregroundStyle(a.fertig ? farbe.leise : farbe.text)
                            .strikethrough(a.fertig, color: farbe.leise).fixedSize(horizontal: false, vertical: true)
                        let nebenzeile = [a.wer, a.bis.map { "bis \($0)" }].compactMap { $0 }.joined(separator: " · ")
                        if !nebenzeile.isEmpty { Text(nebenzeile).schrift(.klein).foregroundStyle(farbe.leise) }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(a.fertig ? "erledigt" : "offen")
            }
        }
    }

    private func tabelle(_ t: SenecaKarte.Tabelle) -> some View {
        let spalten = max(t.spalten.count, t.zeilen.map(\.count).max() ?? 0)
        func zelle(_ z: [String], _ i: Int) -> String { i < z.count ? z[i] : "" }
        return Grid(alignment: .topLeading, horizontalSpacing: Stil.abstand.m, verticalSpacing: 0) {
            if !t.spalten.isEmpty {
                GridRow {
                    ForEach(0..<spalten, id: \.self) { i in
                        Text(zelle(t.spalten, i)).schrift(.etikett).foregroundStyle(farbe.leise)
                    }
                }
                .padding(.bottom, Stil.abstand.s)
            }
            ForEach(Array(t.zeilen.enumerated()), id: \.offset) { _, z in
                Divider().overlay(farbe.linie).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<spalten, id: \.self) { i in
                        Text(zelle(z, i)).schrift(.zeile).foregroundStyle(farbe.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Stil.abstand.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bericht(_ pfad: String) -> some View {
        let name = (pfad as NSString).lastPathComponent
        return VStack(alignment: .leading, spacing: Stil.abstand.xs) {
            Button {
                dateiFehler = nil
                Task { dateiFehler = await actions.dateiOeffnen(pfad); if dateiFehler != nil { try? await Task.sleep(for: .seconds(3)); dateiFehler = nil } }
            } label: {
                Text("Bericht öffnen: \(name)").schrift(.zeileWichtig).foregroundStyle(farbe.link).underline()
                    .multilineTextAlignment(.leading).frame(minHeight: Stil.tippFlaeche, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let f = dateiFehler { Text(f).schrift(.klein).foregroundStyle(farbe.leise) }
        }
    }

    private var aktionen: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(karte.aktionen.enumerated()), id: \.offset) { _, a in
                Button { actions.frage(a.prompt) } label: {
                    HStack(spacing: Stil.abstand.s) {
                        Text(a.label).schrift(.zeileWichtig).foregroundStyle(farbe.link)
                        Text("›").schrift(.zeile).foregroundStyle(farbe.link)
                    }
                    .frame(minHeight: Stil.tippFlaeche, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(farbe.linie).frame(height: 1) }
            }
        }
    }
}
