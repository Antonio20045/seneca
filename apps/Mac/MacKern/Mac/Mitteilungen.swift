import Foundation

struct Mitteilung: Equatable {
    enum Art: String, CaseIterable { case entscheidung, stoerung }
    var id: String
    var art: Art
    var titel: String
    var text: String
    var pfad: String
}

@MainActor
protocol Mitteilungszentrale: AnyObject {
    func zeige(_ m: Mitteilung)
}

@MainActor
final class MitteilungsWaechter {
    var zentrale: Mitteilungszentrale?
    var aktiv: (Mitteilung.Art) -> Bool = { _ in false }
    static var sammelAb: Int { Int(AppRegel.wert("mitteilung_sammeln_ab", 2)) }

    private(set) var bekannt: Set<String> = []
    private var grundLegt: Set<Mitteilung.Art> = []

    static func kandidaten(daten: OvDaten, stand: SenecaStand?, jetzt: Double) -> [Mitteilung.Art: [Mitteilung]] {
        var out: [Mitteilung.Art: [Mitteilung]] = [:]
        if let s = stand {
            out[.entscheidung] = s.alleFragen.map {
                Mitteilung(id: "entscheidung:\($0.id)", art: .entscheidung, titel: $0.mitteilung?.titel ?? "Braucht dich",
                           text: Menschlich.kuerzen($0.mitteilung?.text ?? $0.text, 140), pfad: Route(.entscheidungen).pfad)
            }
        }
        if daten.geladen {
            let zwei = 2 * Menschlich.tag
            out[.stoerung] = daten.jobs.compactMap { j -> Mitteilung? in
                guard j.aktiv, j.lastRunStatus == "error", let last = j.lastRunAtMs, last > jetzt - zwei else { return nil }
                let k = "fehler:\(j.id):\(Int64(last))"
                return Mitteilung(id: k, art: .stoerung, titel: "Störung", text: "„\(HeuteLogik.jobName(j))“ ist fehlgeschlagen.", pfad: Route(.heute).pfad)
            }
        }
        return out
    }

    @discardableResult
    func pruefe(daten: OvDaten, stand: SenecaStand?, jetzt: Double) -> [Mitteilung] {
        var gemeldet: [Mitteilung] = []
        let k = Self.kandidaten(daten: daten, stand: stand, jetzt: jetzt)
        for art in Mitteilung.Art.allCases {
            guard let liste = k[art] else { continue }
            if !grundLegt.contains(art) {
                grundLegt.insert(art)
                bekannt.formUnion(liste.map(\.id))
                continue
            }
            let neu = liste.filter { !bekannt.contains($0.id) }
            guard !neu.isEmpty else { continue }
            bekannt.formUnion(neu.map(\.id))
            guard aktiv(art) else { continue }
            if neu.count >= Self.sammelAb {
                gemeldet.append(Self.sammel(art, neu))
            } else {
                gemeldet.append(contentsOf: neu)
            }
        }
        for m in gemeldet { zentrale?.zeige(m) }
        return gemeldet
    }

    @discardableResult
    func pruefe(_ s: OverviewStore, stand: SenecaStand?) -> [Mitteilung] {
        pruefe(daten: s.daten, stand: stand, jetzt: s.jetzt)
    }

    static func sammel(_ art: Mitteilung.Art, _ liste: [Mitteilung]) -> Mitteilung {
        let n = liste.count
        switch art {
        case .entscheidung: return Mitteilung(id: "sammel:" + (liste.first?.id ?? ""), art: art, titel: "Braucht dich", text: "\(n) neue Entscheidungen warten.", pfad: Route(.entscheidungen).pfad)
        case .stoerung: return Mitteilung(id: "sammel:" + (liste.first?.id ?? ""), art: art, titel: "Störungen", text: "\(n) Aufträge sind fehlgeschlagen.", pfad: Route(.heute).pfad)
        }
    }
}
