import SwiftUI

struct WurzelView: View {
    @ObservedObject var modell: AppModell

    var body: some View {
        ZStack {
            TagesGrund(modell: modell)
            switch modell.zustand {
            case .einrichten:
                EinrichtenView(modell: modell)
            case .verbindet:
                MeldungView(titel: "Verbinde mit Seneca …", text: nil, symbol: nil, knopf: nil)
            case .fehler(let meldung):
                FehlerView(modell: modell, meldung: meldung)
            case .bereit:
                RahmenView(modell: modell)
            }
        }
        .animation(Kurve.ease(0.25), value: modell.zustand)
        .fensterSichtAusHauptfenster()
    }
}

struct TagesGrund: View {
    @ObservedObject var modell: AppModell
    @ObservedObject private var notizblock: NotizblockModell

    init(modell: AppModell) {
        self.modell = modell
        _notizblock = ObservedObject(wrappedValue: modell.snNotizblock)
    }

    var body: some View {
        let p = modell.fortschrittTest ?? notizblock.fortschritt
        SnGrund(fortschritt: p)
            .animation(Kurve.sn(1.2), value: p)
            .accessibilityIdentifier("tagesgrund")
    }
}
