import SwiftUI

struct AufgabenLayer: View {
    var m: Metrics
    var now: Date
    var back: () -> Void
    var allowTap: () -> Bool = { true }
    var griff = false

    @EnvironmentObject private var store: SenecaStore
    @EnvironmentObject private var berichte: BerichteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TafelReiter(auswahl: $berichte.tab, optionen: [(.aufgaben, "Aufgaben"), (.berichte, "Berichte")]).padding(.horizontal, 24)
            if berichte.tab == .berichte {
                if let b = store.stand?.berichte { BerichteTafel(berichte: b).transition(.wechsel) } else { HeuteSkelett() }
            } else if let stand = store.stand {
                AufgabenTafel(stand: stand, jetzt: store.demo ? stand.jetzt : now.timeIntervalSince1970 * 1000, offline: offline).transition(.wechsel)
            } else {
                HeuteSkelett()
            }
        }
        .padding(.top, 62)
        .foregroundStyle(TafelFarbe.text)
        .background(TafelGrund())
        .scrollDisabled(griff)
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .onAppear(perform: demoStart)
        .onDisappear { berichte.tab = .aufgaben }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { back() }
        .accessibilityAction(named: "Zurück zu heute") { back() }
    }

    private var offline: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SENECA_DEMO_OFFLINE"] == "1" { return true }
        #endif
        return !store.demo && store.isConfigured && !store.isConnected
    }

    private func demoStart() {
        #if DEBUG
        guard store.demo else { return }
        let env = ProcessInfo.processInfo.environment
        if env["SENECA_DEMO_BERICHTE"] != nil { berichte.tab = .berichte }
        #endif
    }
}
