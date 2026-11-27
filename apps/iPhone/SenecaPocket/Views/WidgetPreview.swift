#if DEBUG
import SwiftUI

struct WidgetPreviewScreen: View {
    @EnvironmentObject private var store: SenecaStore

    var body: some View {
        let faelle: [(String, Date, WidgetLage?)] = store.stand.map(WidgetLogik.faelle) ?? []
        let nr = Int(ProcessInfo.processInfo.environment["SENECA_WIDGET_FALL"] ?? "") ?? 0
        VStack {
            HStack(alignment: .top, spacing: 24) {
                ForEach(faelle[nr...nr], id: \.0) { titel, jetzt, l in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(titel).mono(11, .medium, abstand: 1).foregroundStyle(TafelFarbe.leise)
                        feld(WidgetFace(lage: l, jetzt: jetzt, art: .klein), 158, 158)
                        feld(WidgetFace(lage: l, jetzt: jetzt, art: .mittel), 338, 158)
                        VStack(spacing: 8) {
                            WidgetFace(lage: l, jetzt: jetzt, art: .zeile).font(.system(size: 13))
                            Text(WidgetLogik.uhr(jetzt)).font(.system(size: 64, weight: .semibold, design: .rounded))
                            HStack(spacing: 10) {
                                WidgetFace(lage: l, jetzt: jetzt, art: .rechteck).padding(8).frame(width: 150, height: 66).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.15)))
                                WidgetFace(lage: l, jetzt: jetzt, art: .kreis).frame(width: 66, height: 66).background(Circle().fill(.white.opacity(0.15)))
                            }
                        }
                        .foregroundStyle(.white).padding(14).frame(width: 338).background(RoundedRectangle(cornerRadius: 22).fill(TafelFarbe.hex(0x153A6E)))
                    }
                }
            }
            .padding(24)
            Spacer()
        }
        .background(TafelFarbe.hex(0x0A1530).ignoresSafeArea())
        .onAppear { if store.stand == nil { store.zeigeBeispiel("Beispiel-Stand") } }
    }

    private func feld(_ v: some View, _ b: CGFloat, _ h: CGFloat) -> some View {
        v.padding(16).frame(width: b, height: h).background(RoundedRectangle(cornerRadius: 22).fill(WidgetFarbe.grund))
    }
}
#endif

#if DEBUG
struct TeilenDemo: View {
    @StateObject private var modell = TeilenModell()
    private let pfad = ProcessInfo.processInfo.environment["SENECA_DEMO_ANHANG"] ?? ""

    var body: some View {
        GeometryReader { r in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                if let b = UIImage(contentsOfFile: pfad) { Image(uiImage: b).resizable().scaledToFit().frame(maxHeight: .infinity, alignment: .top).padding(.top, 50).brightness(-0.25) }
                TeilenBlatt(modell: modell, senden: {}, abbrechen: {}, fokus: false)
                    .frame(height: r.size.height * 0.73)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            guard let o = TeilenEingang.ordner, let d = FileManager.default.contents(atPath: pfad) else { return }
            try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
            try? d.write(to: o.appendingPathComponent("demo.png"))
            TeilenEingang.teamMerken([["Engineer", "arbeitet"], ["Produkt", "fragt"], ["Prüfer", "arbeitet"]])
            modell.frage = "Warum geht das nicht?"
            modell.eintrag = TeilenEintrag(id: "demo", zeit: Date(), dateien: ["demo.png"], bilder: 1)
        }
    }
}
#endif
