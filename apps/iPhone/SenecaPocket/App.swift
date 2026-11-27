import SwiftUI
import BackgroundTasks

@main
@MainActor
struct SenecaPocketApp: App {
    @StateObject private var store: SenecaStore
    @Environment(\.scenePhase) private var phase

    init() {
        if ProcessInfo.processInfo.environment["SENECA_DEMO"] == "1" { GespraechsPartner.setzeDemo() }
        let store = SenecaStore()
        _store = StateObject(wrappedValue: store)
        SenecaStore.aktuell = store
        FadenBruecke.shared.verbinde(store.chat)
        store.chat.speicher.oeffne(store.chat.currentKey)
        Sinne.shared.starten(store: store)
        TagesablaufQuelle.shared.starten(store: store)
        Hintergrund.anmelden()
        UIWindow.appearance().overrideUserInterfaceStyle = .dark
    }
    var body: some Scene {
        WindowGroup {
            content
                .environmentObject(store)
                .environmentObject(store.chat)
                .preferredColorScheme(.dark)
                .tint(Sundartha.himmel)
                .statusBarHidden(false)
                .task { WidgetBridge.shared.attach(store) }
                .task { Eingang.nachtragen(store) }
                .task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if !store.demo { await StatHealthSync.shared.abgleichen(grund: .vordergrund, fragen: false) }
                    try? await Task.sleep(for: .seconds(3))
                    await Sinne.shared.abgleichen()
                }
                .onChange(of: phase) { _, neu in
                    if neu == .background { Hintergrund.planen(); store.chat.speicher.sichere() }
                    if neu == .active, !store.demo {
                        Task {
                            await StatHealthSync.shared.abgleichen(grund: .vordergrund, fragen: false)
                            try? await Task.sleep(for: .seconds(3))
                            await Sinne.shared.abgleichen()
                        }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SENECA_WIDGET_PREVIEW"] == "1" {
            WidgetPreviewScreen()
        } else if let muster = GrundMusterSeite.ausDemo {
            GrundMusterSeite.ansicht(muster)
        } else if ProcessInfo.processInfo.environment["SENECA_DEMO_PAGE"] == "sinne" {
            SinneView(zurueck: nil)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}

@MainActor
enum Hintergrund {
    static let kennung = "de.antonio.senecapocket.auffrischen"

    static func anmelden() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: kennung, using: .main) { aufgabe in
            MainActor.assumeIsolated {
                planen()
                var fertig = false
                let arbeit = Task { @MainActor in
                    await Sinne.shared.abgleichen()
                    await TeilenVerarbeiten.merken()
                    await TagesablaufQuelle.shared.auffrischen(sofort: true)
                    Sinne.shared.hintergrundEnde()
                    if !fertig { fertig = true; aufgabe.setTaskCompleted(success: true) }
                }
                aufgabe.expirationHandler = {
                    arbeit.cancel()
                    DispatchQueue.main.async { if !fertig { fertig = true; aufgabe.setTaskCompleted(success: false) } }
                }
            }
        }
    }

    static func planen() {
        let wunsch = BGAppRefreshTaskRequest(identifier: kennung)
        wunsch.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(wunsch)
    }
}
