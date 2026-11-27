import SwiftUI

enum ProjekteLogik {
    static let wegName = "Der Weg zu 100 km"
}

struct ProjekteTafel: View {
    var stand: SenecaStand
    @EnvironmentObject private var store: SenecaStore
    @StateObject private var model = StatistikModel()

    private var liste: [SenecaStand.Projekt] { stand.projekte?.liste ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(liste) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(Sundartha.grotesk(17)).foregroundStyle(.white)
                        (Text(TafelFarbe.bereichWort(p.bereich).map { "\($0) · " } ?? "").foregroundColor(TafelFarbe.bereich(p.bereich)) + Text(p.untertitel ?? "").foregroundColor(TafelFarbe.leise))
                            .font(Sundartha.grotesk(12))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                }
                if !liste.contains(where: { $0.name == ProjekteLogik.wegName }) { weg }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .listeOben()
        .task { await model.laden(store: store) }
    }

    private var weg: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ProjekteLogik.wegName).font(Sundartha.serif(26)).foregroundStyle(.white)
            (Text("Wachstum · ").foregroundColor(TafelFarbe.bereich("wachstum")) + Text("Lauf im Juni").foregroundColor(TafelFarbe.leise)).font(Sundartha.grotesk(12)).padding(.bottom, 10)
            WegZu100(k: model.laufDaten?.kennzahlen?.lauf)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}
