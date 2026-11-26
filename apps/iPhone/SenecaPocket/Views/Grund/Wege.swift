import SwiftUI

enum Ziel: Equatable, Hashable {
    case chat(mitarbeiter: String? = nil)
    case aufgaben
    case berichte
    case arbeit(ArbeitTeil = .fragen)
    case kalender(tag: Date? = nil)
    case statistik
    case einstellungen

    enum ArbeitTeil: Equatable, Hashable {
        case fragen, laeuft, projekte
    }
}

struct Wege {
    var zurueck: () -> Void
    var oeffne: (Ziel) -> Void

    init(zurueck: @escaping () -> Void, oeffne: @escaping (Ziel) -> Void) {
        self.zurueck = zurueck
        self.oeffne = oeffne
    }

    static let leer = Wege(
        zurueck: {
            #if DEBUG
            print("Wege: zurueck() ist noch nicht verbunden (Paket 2).")
            #endif
        },
        oeffne: { ziel in
            #if DEBUG
            print("Wege: oeffne(\(ziel)) ist noch nicht verbunden (Paket 2).")
            #endif
        })
}

private struct WegeSchluessel: EnvironmentKey {
    static let defaultValue = Wege.leer
}

extension EnvironmentValues {
    var wege: Wege {
        get { self[WegeSchluessel.self] }
        set { self[WegeSchluessel.self] = newValue }
    }
}
