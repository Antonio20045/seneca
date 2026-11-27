import Foundation

@MainActor
enum TeilenVerarbeiten {
    static var hatFragen: Bool { TeilenEingang.alle().contains { !$0.nurMerken } }

    static func merken() async {
        for e in TeilenEingang.alle() where e.nurMerken {
            let z = TeilenEingang.merkzettel(e, gelesen: await TeilenEingang.lesen(e))
            await Sinne.shared.melden([TageslaufEreignis(zeit: e.zeit, quelle: "iphone-teilen", art: z.art, titel: z.titel, detail: z.detail, schluessel: "teilen:\(e.id)")])
            TeilenEingang.entfernen(e)
        }
    }

    static func fragen(_ senden: (String, String?, [URL]) -> Bool) async {
        for e in TeilenEingang.alle() where !e.nurMerken {
            let text = TeilenEingang.nachricht(e, gelesen: await TeilenEingang.lesen(e))
            guard senden(text, e.an, TeilenEingang.bilder(e)) else { return }
            TeilenEingang.entfernen(e)
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}
