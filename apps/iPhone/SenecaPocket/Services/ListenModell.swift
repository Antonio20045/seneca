import Foundation

@MainActor
final class ListenModell: ObservableObject {
    static let gemeinsam = ListenModell()

    @Published private(set) var liste: ArbeitsListe?
    @Published private(set) var stand: Date?
    @Published private(set) var einmalGelesen = false
    @Published private(set) var gelesen = Set<String>()

    private static var datei: URL? { MacPfade.datenOrdner?.appendingPathComponent("liste.json") }

    init() {
        #if DEBUG
        if let pfad = ProcessInfo.processInfo.environment["SENECA_DEMO_LISTE"], let d = try? Data(contentsOf: URL(fileURLWithPath: pfad)) {
            liste = ArbeitsListe.lies(d)
            stand = (try? FileManager.default.attributesOfItem(atPath: pfad))?[.modificationDate] as? Date
            einmalGelesen = true
            return
        }
        #endif
        guard !MacPfade.demo, let url = Self.datei, let d = try? Data(contentsOf: url) else { return }
        liste = ArbeitsListe.lies(d)
        stand = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func nimm(_ antwort: [String: Any], jetzt: Date = Date()) {
        einmalGelesen = true
        guard let neu = ArbeitsListe.lies(wurzel: antwort, jetzt: jetzt) else { return }
        if neu != liste { liste = neu }
        stand = jetzt
        let noch = Set(neu.fertig.map(\.gelesenKennung))
        if !gelesen.isSubset(of: noch) { gelesen.formIntersection(noch) }
        if !MacPfade.demo, let url = Self.datei, JSONSerialization.isValidJSONObject(antwort),
           let d = try? JSONSerialization.data(withJSONObject: antwort) {
            try? d.write(to: url, options: .atomic)
        }
    }

    func markiereGelesen(_ kennung: String, store: SenecaStore) {
        guard !kennung.isEmpty else { return }
        gelesen.insert(kennung)
        store.markSeen([kennung])
    }
}
