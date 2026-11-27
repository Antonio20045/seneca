import SwiftUI

@MainActor
final class AufgabenModell: ObservableObject {
    static let gemeinsam = AufgabenModell()

    @Published private(set) var liste: AufgabenListe?
    @Published private(set) var einmalGelesen = false
    @Published private(set) var lesbar = true
    private var laedt = false
    private var schleifeLaeuft = false

    static var befehl: URL { TageslaufHaken.ordner.appendingPathComponent("aufgaben.py") }
    private static var datei: URL? { MacPfade.datenOrdner?.appendingPathComponent("aufgaben.json") }

    init() {
        guard TageslaufModell.erlaubt || (Hintergrund.aktiv && Messung.aktiv && MacPfade.pruefinstanz), let url = Self.datei, let d = try? Data(contentsOf: url) else { return }
        liste = AufgabenListe.lies(d)
    }

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
        let daten = await Kindprozess.laufe(Self.befehl, ["liste"], limit: 15)
        let alt = liste
        var ergebnisGeaendert = false
        let ergebnis = await Task.detached(priority: .utility) { () -> (AufgabenListe, Bool)? in
            guard let daten, let n = AufgabenListe.lies(daten) else { return nil }
            return (n, n != alt)
        }.value
        if let daten, let (neu, geaendert) = ergebnis {
            if geaendert { liste = neu }
            ergebnisGeaendert = geaendert
            if !lesbar { lesbar = true }
            if geaendert, let url = Self.datei { Task.detached(priority: .utility) { try? daten.write(to: url, options: .atomic) } }
        } else if lesbar {
            lesbar = false
        }
        if !einmalGelesen { einmalGelesen = true }
        if let l = liste, lesbar { await AufgabenMelder.gemeinsam.pruefe(l, geaendert: ergebnisGeaendert) }
    }
}

