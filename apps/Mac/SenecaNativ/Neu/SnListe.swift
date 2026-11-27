import SwiftUI

@MainActor
final class ListenModell: ObservableObject {
    static let gemeinsam = ListenModell()

    @Published private(set) var liste: ArbeitsListe?
    @Published private(set) var einmalGelesen = false
    @Published private(set) var gelesen = Set<String>()
    private var laedt = false

    private static var datei: URL? { MacPfade.datenOrdner?.appendingPathComponent("liste.json") }

    private var letzteAntwort: Data?

    init() {
        guard TageslaufModell.erlaubt || (Hintergrund.aktiv && Messung.aktiv && MacPfade.pruefinstanz), let url = Self.datei else { return }
        Task {
            let l = await Task.detached(priority: .userInitiated) { (try? Data(contentsOf: url)).flatMap { ArbeitsListe.lies($0) } }.value
            if liste == nil, let l { liste = l }
        }
    }

    private var schleifeLaeuft = false

    func beobachte() async {
        guard TageslaufModell.erlaubt, !schleifeLaeuft else { return }
        schleifeLaeuft = true
        defer { schleifeLaeuft = false }
        while !Task.isCancelled {
            await lade()
            try? await Task.sleep(for: .seconds(20))
        }
    }

    func lade() async {
        guard TageslaufModell.erlaubt, !laedt else { return }
        laedt = true
        defer { laedt = false }
        let daten = await Kindprozess.laufe(TageslaufModell.befehl, ["liste", "--json"], limit: 15)
        if let daten, daten != letzteAntwort {
            let alt = liste, url = Self.datei
            let ergebnis = await Task.detached(priority: .utility) { () -> (ArbeitsListe, Bool, Set<String>)? in
                guard let n = ArbeitsListe.lies(daten) else { return nil }
                if let url { try? daten.write(to: url, options: .atomic) }
                return (n, n != alt, Set(n.fertig.map(\.gelesenKennung)))
            }.value
            if let (neu, geaendert, noch) = ergebnis {
                letzteAntwort = daten
                if geaendert { liste = neu }
                if !gelesen.isSubset(of: noch) { gelesen.formIntersection(noch) }
            }
        }
        if !einmalGelesen { einmalGelesen = true }
    }

    func markiereGelesen(_ kennung: String, store: OverviewStore) {
        guard !kennung.isEmpty else { return }
        gelesen.insert(kennung)
        Task {
            await store.markiere([kennung])
            await lade()
        }
    }
}

