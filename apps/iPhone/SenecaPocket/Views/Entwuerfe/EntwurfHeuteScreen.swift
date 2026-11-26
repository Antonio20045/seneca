import SwiftUI

struct EntwurfHeuteScreen: View {
    var richtung: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var uhr = EHUhr(EHZustand.aktuell)
    @State private var erschienen = false

    static func richtung(_ seite: String?) -> String? {
        guard let seite, seite.hasPrefix("entwurf-heute") else { return nil }
        return String(seite.split(separator: "-").last ?? "a")
    }

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size, safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
            ZStack(alignment: .topLeading) {
                switch richtung {
                case "b": EntwurfHeuteB(m: m, uhr: uhr, erschienen: erschienen, reduceMotion: reduceMotion)
                case "c": EntwurfHeuteC(m: m, uhr: uhr, erschienen: erschienen, reduceMotion: reduceMotion)
                default: EntwurfHeuteA(m: m, uhr: uhr, erschienen: erschienen, reduceMotion: reduceMotion)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background { EHHintergrund(m: m, reduceMotion: reduceMotion, licht: richtung == "c" ? 0.5 : 0.62) }
        }
        .ignoresSafeArea()
        .background(Sundartha.base.ignoresSafeArea())
        .task {
            let start = Double(ProcessInfo.processInfo.environment["SENECA_ENTWURF_START"] ?? "") ?? 0.5
            try? await Task.sleep(for: .seconds(start))
            erschienen = true
            await uhr.laufen()
        }
    }
}
