import SwiftUI

struct SnKalMonat: View {
    @ObservedObject var k: SnKalenderSpeicher
    let tage: [Date]

    private static let zeile: CGFloat = 20

    var body: some View {
        let liste = k.anzeige
        let wochen = tage.count / 7
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(KalRaster.wochentageKurz, id: \.self) {
                    Text($0).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 26, alignment: .top)
            .accessibilityHidden(true)
            GeometryReader { g in
                let hoehe = (g.size.height / CGFloat(wochen)).rounded(.down)
                VStack(spacing: 0) {
                    ForEach(0..<wochen, id: \.self) { w in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { d in
                                let tag = tage[w * 7 + d]
                                SnKalMonatsZelle(k: k, tag: tag, termine: KalRaster.amTag(liste, tag: tag, k.cal), hoehe: hoehe,
                                                 platz: Int((hoehe - 40) / Self.zeile))
                            }
                        }
                        .frame(height: hoehe)
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                    }
                }
            }
        }
    }
}

private struct SnKalMonatsZelle: View {
    @ObservedObject var k: SnKalenderSpeicher
    let tag: Date
    let termine: [KalEreignis]
    let hoehe: CGFloat
    let platz: Int
    @State private var hover = false

    var body: some View {
        let cal = k.cal
        let heute = tag == cal.startOfDay(for: k.jetzt)
        let im = cal.isDate(tag, equalTo: k.stand.anker, toGranularity: .month)
        let nummer = cal.component(.day, from: tag)
        let z = KalRaster.monatsZeilen(anzahl: termine.count, platz: platz)
        VStack(alignment: .leading, spacing: 2) {
            Text(nummer == 1 ? "1. \(KalRaster.monate[cal.component(.month, from: tag) - 1].prefix(3))" : "\(nummer)")
                .font(Schrift.grotesk(13, .medium))
                .foregroundStyle(heute ? Farbe.aufWeiss : (im ? Color.white : Farbe.ink4))
                .padding(.horizontal, heute ? 7 : 0).frame(minWidth: heute ? 24 : 0, minHeight: 24)
                .background(Capsule().fill(heute ? Farbe.himmel : .clear))
                .padding(.bottom, 2)
            ForEach(termine.prefix(z.zeigen)) { e in
                SnKalMonatsZeile(e: e, tag: tag, cal: cal, an: k.offenId == e.id, blass: !im) { k.oeffne(e) }
            }
            if z.mehr > 0 {
                Button { k.zeigeTag(tag) } label: {
                    Text(z.zeigen == 0 ? "\(z.mehr) Termine" : "+\(z.mehr) weitere").font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.ink3)
                        .padding(.horizontal, 6).frame(height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Alle Termine dieses Tages zeigen")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Color.white.opacity(0.04) : (heute ? Farbe.himmel.opacity(0.05) : .clear)).padding(.top, 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if k.entwurf != nil || k.sprungOffen { withAnimation(Kurve.sn(0.18)) { k.sprungOffen = false }; k.schliesse() } else { k.zeigeTag(tag) }
        }
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.15), value: hover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(nummer). \(KalRaster.monate[cal.component(.month, from: tag) - 1])" + (termine.isEmpty ? "" : ", \(termine.count) Termine"))
    }
}

private struct SnKalMonatsZeile: View {
    let e: KalEreignis
    let tag: Date
    let cal: Calendar
    var an = false
    var blass = false
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        let farbe = Color.kal(e.farbe)
        let form = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let balken = KalRaster.istBalken(e)
        Button(action: aktion) {
            HStack(spacing: 5) {
                if !balken {
                    Circle().fill(farbe).frame(width: 6, height: 6)
                    if cal.startOfDay(for: e.start) == tag {
                        Text(KalRaster.uhr(e.start, cal)).font(Schrift.mono(10)).foregroundStyle(Farbe.ink3).fixedSize()
                    }
                }
                Text(e.titel).font(Schrift.grotesk(12, balken ? .medium : .regular)).foregroundStyle(balken ? Color.white : Farbe.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
            .background(form.fill(balken ? farbe.opacity(an ? 0.42 : 0.26) : (an ? farbe.opacity(0.22) : (hover ? Color.white.opacity(0.07) : .clear))))
            .contentShape(form)
        }
        .buttonStyle(.plain)
        .opacity(blass ? 0.55 : 1)
        .onHover { hover = $0 }
        .help(balken ? e.titel : "\(KalRaster.uhr(e.start, cal)) – \(KalRaster.uhr(e.ende, cal))  \(e.titel)")
    }
}
