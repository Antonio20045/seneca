import Foundation

struct Mitteilung: Equatable {
    enum Art: String, CaseIterable { case entscheidung, bericht, stoerung }
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

    static func kandidaten(daten: OvDaten, entscheidungen: [OvEntscheidung], berichte: BerichteWeb.Stand, jetzt: Double) -> [Mitteilung.Art: [Mitteilung]] {
        var out: [Mitteilung.Art: [Mitteilung]] = [:]
        if daten.entRoh != nil {
            out[.entscheidung] = entscheidungen.filter { !$0.ruhend }.map {
                Mitteilung(id: "entscheidung:\($0.id)", art: .entscheidung, titel: "Braucht dich",
                           text: Menschlich.kuerzen(Menschlich.klartext($0.frage), 140), pfad: Route(.entscheidungen).pfad)
            }
        }
        if berichte.fertig {
            out[.bericht] = berichte.liste.filter(\.neu).map {
                Mitteilung(id: "bericht:\($0.schluessel)", art: .bericht, titel: $0.name.isEmpty ? "Neuer Bericht" : $0.name,
                           text: Menschlich.kuerzen($0.satz, 140), pfad: Route(.berichte, id: $0.id).pfad)
            }
        }
        if daten.geladen {
            let zwei = 2 * Menschlich.tag
            out[.stoerung] = daten.jobs.compactMap { j -> Mitteilung? in
                guard j.aktiv, j.lastRunStatus == "error", let last = j.lastRunAtMs, last > jetzt - zwei else { return nil }
                let k = "fehler:\(j.id):\(Int64(last))"
                guard daten.gesehen[k] == nil else { return nil }
                return Mitteilung(id: k, art: .stoerung, titel: "Störung", text: "„\(HeuteLogik.jobName(j))“ ist fehlgeschlagen.", pfad: Route(.heute).pfad)
            }
        }
        return out
    }

    @discardableResult
    func pruefe(daten: OvDaten, entscheidungen: [OvEntscheidung], berichte: BerichteWeb.Stand, jetzt: Double) -> [Mitteilung] {
        var gemeldet: [Mitteilung] = []
        let k = Self.kandidaten(daten: daten, entscheidungen: entscheidungen, berichte: berichte, jetzt: jetzt)
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
    func pruefe(_ s: OverviewStore) -> [Mitteilung] {
        pruefe(daten: s.daten, entscheidungen: s.entscheidungen, berichte: s.berichte, jetzt: s.jetzt)
    }

    static func sammel(_ art: Mitteilung.Art, _ liste: [Mitteilung]) -> Mitteilung {
        let n = liste.count
        switch art {
        case .entscheidung: return Mitteilung(id: "sammel:" + (liste.first?.id ?? ""), art: art, titel: "Braucht dich", text: "\(n) neue Entscheidungen warten.", pfad: Route(.entscheidungen).pfad)
        case .bericht: return Mitteilung(id: "sammel:" + (liste.first?.id ?? ""), art: art, titel: "Neue Berichte", text: "\(n) neue Berichte sind da.", pfad: Route(.berichte).pfad)
        case .stoerung: return Mitteilung(id: "sammel:" + (liste.first?.id ?? ""), art: art, titel: "Störungen", text: "\(n) Aufträge sind fehlgeschlagen.", pfad: Route(.heute).pfad)
        }
    }
}
