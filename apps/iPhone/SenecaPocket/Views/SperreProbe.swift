#if DEBUG
import SwiftUI

struct SperreProbe: View {
    @ViewBuilder
    static func aus(_ s: SenecaStand?) -> some View {
        if let welche = ProcessInfo.processInfo.environment["SENECA_DEMO_SPERRE"], let s {
            let z = zustaende(s)
            SperreProbe(zustaende: welche == "alle" ? z : Array(z.prefix(1)), uhrzeit: welche == "alle" ? "" : "10:08", fokus: welche == "alle" ? nil : "Fokus bis 11:00")
        }
    }

    static func zustaende(_ s: SenecaStand) -> [SenecaLive.ContentState] {
        let tag = HeuteTafelLogik.datum(s.jetzt)
        let um = { (h: Int, m: Int) in Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: tag)! }
        let arbeitet = LiveAnzeige.zustand(s, jetzt: um(10, 8))
        var frei = s; frei.ruhe = nil; frei.team = frei.team?.map { var m = $0; m.zustand = "frei"; return m }
        var trail = frei; trail.ruhe = .init(grund: "trail", bis: nil, durchbruch: false); trail.braucht_dich = []; trail.termine = []
        let f = s.braucht_dich?.first
        let quittung = SenecaLive.ContentState(art: "quittung", titel: "Freigegeben", unter: f?.optionen?.first?.folge?.components(separatedBy: ". ").first ?? "", insel: "3 s",
                                               frage: f?.id, knopf: "Rückgängig", bis: Date().addingTimeInterval(3))
        let alle = [arbeitet, .init(art: "fertig", titel: "Erste Fassung ist fertig", unter: "Kein Ton, du bist im Fokus.", insel: "fertig"),
                    LiveAnzeige.zustand(frei, jetzt: um(11, 0)), quittung, LiveAnzeige.zustand(frei, jetzt: um(12, 20)), LiveAnzeige.zustand(trail, jetzt: um(19, 20))].compactMap { $0 }
        return alle
    }

    var zustaende: [SenecaLive.ContentState]
    var uhrzeit: String
    var fokus: String?

    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(stops: [.init(color: TafelFarbe.hex(0x1B3F78), location: 0), .init(color: TafelFarbe.hex(0x0B2148), location: 0.42), .init(color: TafelFarbe.hex(0x040D1E), location: 1)],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 700)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Donnerstag, 26. November").font(Sundartha.grotesk(17, .medium)).foregroundStyle(.white.opacity(0.86)).padding(.top, 92)
                Text(uhrzeit).font(Sundartha.grotesk(96, .medium)).tracking(-3).monospacedDigit().foregroundStyle(.white)
                if let fokus {
                    HStack(spacing: 8) {
                        Circle().fill(LinearGradient(stops: [.init(color: TafelFarbe.akzent, location: 0.5), .init(color: .clear, location: 0.5)], startPoint: .leading, endPoint: .trailing))
                            .overlay(Circle().stroke(TafelFarbe.akzent, lineWidth: 1.5)).frame(width: 10, height: 10)
                        Text(fokus).font(Sundartha.grotesk(13)).foregroundStyle(.white.opacity(0.86))
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12).background(Capsule().fill(.white.opacity(0.1))).padding(.top, 6)
                }
                Spacer()
                VStack(spacing: 10) {
                    ForEach(Array(zustaende.enumerated()), id: \.offset) { _, z in
                        LiveKarte(s: z).background(RoundedRectangle(cornerRadius: 26).fill(LiveFarbe.grund))
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, zustaende.count > 1 ? 30 : 132)
            }
        }
        .ignoresSafeArea()
    }
}
#endif
