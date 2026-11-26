import Foundation

struct Quittung: Equatable, Identifiable {
    var id: String
    var titel: String
    var weg: WegSicht
    var nachrichtId: String
    var teile: [BoardSicht.Teil] = []
    var zustandSatz = ""
}

enum Quittungen {
    static let verzug: TimeInterval = 120
    static let vorlauf: TimeInterval = 2

    static func zuordnen(nachrichten: [(id: String, ts: Double)], karten alle: [ListenZeile], agent: String, jetzt: Date = Date(), kalender: Calendar = .current) -> [String: [Quittung]] {
        var gesehen = Set<String>()
        let karten = alle.filter { $0.nachricht != nil && ($0.nachrichtAn.isEmpty ? $0.agent : $0.nachrichtAn) == agent && gesehen.insert($0.id).inserted }
        guard !karten.isEmpty, !nachrichten.isEmpty else { return [:] }
        let gruppen = Dictionary(grouping: karten) { $0.nachricht!.timeIntervalSince1970.rounded() }
        var frei = nachrichten.sorted { $0.ts < $1.ts }
        var aus: [String: [Quittung]] = [:]
        for t in gruppen.keys.sorted() {
            let ms = t * 1000
            guard let i = frei.lastIndex(where: { $0.ts <= ms + vorlauf * 1000 && ms - $0.ts <= verzug * 1000 }) else { continue }
            let n = frei.remove(at: i)
            let gesendet = Date(timeIntervalSince1970: n.ts / 1000)
            aus[n.id] = (gruppen[t] ?? []).sorted { ($0.station("angelegt")?.zeit ?? .distantPast, $0.id) < ($1.station("angelegt")?.zeit ?? .distantPast, $1.id) }.map { z in
                Quittung(id: z.id, titel: z.titel, weg: WegSicht(z, gesendet: gesendet, jetzt: jetzt, kalender: kalender), nachrichtId: n.id,
                         teile: BoardSicht.teile(z.teile, jetzt: jetzt, kalender: kalender), zustandSatz: z.zustandSatz)
            }
        }
        return aus
    }

    static func nachrichten(_ bloecke: [ZugBlock]) -> [(id: String, ts: Double)] {
        bloecke.compactMap { b in
            guard case .zug(let z) = b, case .user(_, _, let ts?, _)? = z.start else { return nil }
            return (z.id, ts)
        }
    }
}
