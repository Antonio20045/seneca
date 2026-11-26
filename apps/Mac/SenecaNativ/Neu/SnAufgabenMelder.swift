import Foundation

@MainActor
final class AufgabenMelder {
    static let gemeinsam = AufgabenMelder()

    var einstellungen: MacEinstellungen?
    var zustellen: ((AufgabenMeldung) async -> Bool)?

    private var merker: AufgabenMeldeMerker?
    private static var datei: URL? { MacPfade.datenOrdner?.appendingPathComponent("aufgaben-meldungen.json") }

    func pruefe(_ liste: AufgabenListe, geaendert: Bool) async {
        guard MacPfade.profil == .echt, !MacPfade.nebenher, let einstellungen, let zustellen else { return }
        if merker == nil {
            let url = Self.datei
            merker = await Task.detached(priority: .utility) { () -> AufgabenMeldeMerker in
                url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(AufgabenMeldeMerker.self, from: $0) } ?? AufgabenMeldeMerker()
            }.value
        }
        guard var m = merker, geaendert || !m.begonnen || !m.offen.isEmpty else { return }
        let vorher = m
        let faellig = AufgabenMeldungen.pruefe(liste, merker: &m, jetzt: Date(), meldenAn: einstellungen.aufgabenMelden)
        merker = m
        var nicht: [AufgabenMeldung] = []
        for f in faellig where !(await zustellen(f)) { nicht.append(f) }
        if !nicht.isEmpty { merker?.offen.append(contentsOf: nicht) }
        if let neu = merker, neu != vorher, let url = Self.datei {
            Task.detached(priority: .utility) { if let d = try? JSONEncoder().encode(neu) { try? d.write(to: url, options: .atomic) } }
        }
    }
}
