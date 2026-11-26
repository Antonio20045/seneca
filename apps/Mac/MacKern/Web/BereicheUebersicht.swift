import Foundation

enum BereicheUebersicht {
    static let keineAngabe = "keine Angabe"
    static let verlaufSeite = 30
    static let ohneBereich = "_ohne"

    struct Namen {
        var jobName: (OvAuftrag) -> String
        var bereichName: (String) -> String
        var boardKurz: (OvKarte) -> String
        init(jobName: @escaping (OvAuftrag) -> String = { HeuteLogik.jobName($0) }, bereichName: @escaping (String) -> String = { _ in "" },
             boardKurz: @escaping (OvKarte) -> String = { _ in "" }) {
            self.jobName = jobName; self.bereichName = bereichName; self.boardKurz = boardKurz
        }
    }

    static func laufSatz(_ j: OvAuftrag, jobName: (OvAuftrag) -> String) -> String {
        let name = Menschlich.anfuehrung(jobName(j), 56)
        let st = j.lastRunStatus ?? ""
        if st.passt(#"^(ok|success|finished|done)"#, "i") { return "Der Lauf \(name) ist fertig." }
        if st.passt(#"^(error|failed|fail|timeout|cancel)"#, "i") { return "Der Lauf \(name) ist fehlgeschlagen." }
        return "Der Lauf \(name) lief zuletzt."
    }

    static func istDauerlaeufer(_ j: OvAuftrag) -> Bool { j.art == "every" && (j.everyMs ?? 0) > 0 && (j.everyMs ?? 0) <= 3_600_000 }

    struct ProjektZahl: Equatable {
        var id: String
        var bereichId: String
        var offen: Int
        var fertig: Int
        init(id: String, bereichId: String, offen: Int, fertig: Int) { self.id = id; self.bereichId = bereichId; self.offen = offen; self.fertig = fertig }
        init(_ p: HeuteLogik.ProjektInfo) { self.init(id: p.id, bereichId: p.bereichId, offen: p.offenA.count, fertig: p.fertigA.count) }
    }

    struct BereichsStand: Equatable {
        var id: String
        var name: String
        var leiter: String
        var lauf: Double
        var laufZeit: String
        var laufSatz: String
        var offen: Int?
        var fertig: Int?
        var offenText: String
        var fertigText: String
        var link: String
    }

    static func bereichsStand(jobs: [OvAuftrag], bereiche: [Area], projekte: [ProjektZahl], jetzt: Double, namen n: Namen = Namen()) -> [BereichsStand] {
        bereiche.map { b in
            let ids = Set([b.leader] + b.specialists)
            var letzter: OvAuftrag?
            for j in jobs {
                let a = j.agent
                guard !a.isEmpty, ids.contains(a), let t = j.lastRunAtMs, t > 0 else { continue }
                if letzter == nil || t > (letzter?.lastRunAtMs ?? 0) { letzter = j }
            }
            let lauf = letzter?.lastRunAtMs ?? 0
            let eigene = projekte.filter { $0.bereichId == b.id }
            let offen: Int? = eigene.isEmpty ? nil : eigene.reduce(0) { $0 + $1.offen }
            let fertig: Int? = eigene.isEmpty ? nil : eigene.reduce(0) { $0 + $1.fertig }
            return BereichsStand(
                id: b.id, name: b.name.isEmpty ? b.id : b.name, leiter: b.leaderName.isEmpty ? keineAngabe : b.leaderName,
                lauf: lauf, laufZeit: lauf > 0 ? Menschlich.vorText(lauf, jetzt: jetzt) : keineAngabe,
                laufSatz: letzter.map { laufSatz($0, jobName: n.jobName) } ?? keineAngabe,
                offen: offen, fertig: fertig,
                offenText: offen.map { "\($0) offen" } ?? keineAngabe, fertigText: fertig.map { "\($0) erledigt" } ?? keineAngabe,
                link: "#/bereich/" + Menschlich.urlTeil(b.id))
        }
    }

    enum Gruppe: String { case heute = "Heute", gestern = "Gestern", aelter = "Älter" }
    enum Art: String { case lauf, karte }

    struct Zeile: Equatable, Identifiable {
        var key: String
        var bereich: String
        var satz: String
        var zeit: Double
        var zeitText: String
        var art: Art
        var gruppe: Gruppe
        var id: String { key }
    }

    static func gruppeVon(_ ms: Double, jetzt: Double) -> Gruppe {
        let t = Menschlich.tageZwischen(ms, jetzt)
        return t <= 0 ? .heute : t == 1 ? .gestern : .aelter
    }

    private static func zeitAnzeige(_ ms: Double, jetzt: Double) -> String {
        gruppeVon(ms, jetzt: jetzt) == .aelter ? "\(Menschlich.datumKurz(ms)), \(Menschlich.hhmm(ms))" : Menschlich.hhmm(ms)
    }

    static func verlauf(cards: [OvKarte], jobs: [OvAuftrag], label: (String) -> String, projekte: [(id: String, bereichId: String)], bereiche: [(id: String, name: String)],
                        jetzt: Double, namen n: Namen) -> [Zeile] {
        var bereichsName: [String: String] = [:]
        for b in bereiche { bereichsName[b.id] = b.name.isEmpty ? b.id : b.name }
        var boardBereich: [String: String] = [:]
        for p in projekte { boardBereich[p.id] = p.bereichId }
        var alle: [Zeile] = []
        for c in cards {
            guard c.status == "done", let agent = c.agentId, !agent.isEmpty, !HeuteLogik.istEntscheidung(c), let zeit = c.completedAt, zeit > 0, !c.archiviert else { continue }
            let bid = boardBereich[c.boardId]
            let bereich = [bid.flatMap { bereichsName[$0] }, n.bereichName(agent), n.boardKurz(c)].compactMap { $0 }.first { !$0.isEmpty } ?? keineAngabe
            alle.append(Zeile(key: "k" + c.id, bereich: bereich, satz: "Karte \(Menschlich.anfuehrung(c.title, 56)) ist abgeschlossen.", zeit: zeit,
                              zeitText: zeitAnzeige(zeit, jetzt: jetzt), art: .karte, gruppe: gruppeVon(zeit, jetzt: jetzt)))
        }
        for j in jobs {
            let a = j.agent
            let zeit = j.lastRunAtMs ?? 0
            guard !a.isEmpty, zeit > 0, !istDauerlaeufer(j) else { continue }
            let bereich = [n.bereichName(a), a == "main" ? label(a) : ""].first { !$0.isEmpty } ?? keineAngabe
            alle.append(Zeile(key: "j" + j.id, bereich: bereich, satz: laufSatz(j, jobName: n.jobName), zeit: zeit,
                              zeitText: zeitAnzeige(zeit, jetzt: jetzt), art: .lauf, gruppe: gruppeVon(zeit, jetzt: jetzt)))
        }
        return alle.enumerated().sorted { ($1.element.zeit, $0.offset) < ($0.element.zeit, $1.offset) }.map(\.element)
    }

    static func verlaufGruppen(_ zeilen: [Zeile], anzahl: Int = verlaufSeite) -> [(gruppe: Gruppe, zeilen: [Zeile])] {
        var out: [(gruppe: Gruppe, zeilen: [Zeile])] = []
        for z in zeilen.prefix(anzahl) {
            if let l = out.last, l.gruppe == z.gruppe { out[out.count - 1].zeilen.append(z) } else { out.append((z.gruppe, [z])) }
        }
        return out
    }

    struct ListenZeile: Equatable, Identifiable {
        var id: String
        var name: String
        var bereich: Area?
    }

    static func listenZeilen(bereiche: [Area], projekte: [HeuteLogik.ProjektInfo]) -> [ListenZeile] {
        var z = bereiche.map { ListenZeile(id: $0.id, name: $0.name.isEmpty ? $0.id : $0.name, bereich: $0) }
        if !projekteOhneBereich(bereiche, projekte).isEmpty { z.append(ListenZeile(id: ohneBereich, name: "Ohne Bereich", bereich: nil)) }
        return z
    }

    static func projekteOhneBereich(_ bereiche: [Area], _ projekte: [HeuteLogik.ProjektInfo]) -> [HeuteLogik.ProjektInfo] {
        projekte.filter { p in p.bereichId.isEmpty || !bereiche.contains { $0.id == p.bereichId } }
    }

    static func projekteVon(_ id: String, bereiche: [Area], projekte: [HeuteLogik.ProjektInfo]) -> [HeuteLogik.ProjektInfo] {
        let liste = id == ohneBereich ? projekteOhneBereich(bereiche, projekte) : projekte.filter { $0.bereichId == id }
        func rang(_ g: HeuteLogik.Gesundheit) -> Int { [.rot: 0, .gelb: 1, .gruen: 2, .grau: 3][g] ?? 3 }
        return liste.enumerated().sorted { a, b in
            (rang(a.element.health), -a.element.offenA.count, a.offset) < (rang(b.element.health), -b.element.offenA.count, b.offset)
        }.map(\.element)
    }

    static func wahl(_ gewuenscht: [String], zeilen: [ListenZeile]) -> String {
        gewuenscht.first { w in !w.isEmpty && zeilen.contains { $0.id == w } } ?? zeilen.first?.id ?? ""
    }

    static func kurzSatz(_ zeilen: [String]) -> String {
        var z = (zeilen.first ?? "")
        z = z.ersetzeAlle(#"\[([^\]]*)\]\([^)]*\)"#, "$1").ersetzeAlle(#"[*_`]"#, "")
        z = z.ersetze(#"^\s*(?:[-•]|\d+[.)])\s*"#, "").ersetzeAlle(#"\s+"#, " ").jsTrim
        if z.isEmpty { return "" }
        let satz = z.jsLaenge > 120 ? (z.treffer(#"^.{40,120}?[.!?](?=\s|$)"#)?[0] ?? Menschlich.kuerzen(z, 120)) : z
        return satz.passt(#"[.!?…]$"#) ? satz : satz + "."
    }

    static func frageText(_ n: Int) -> String { "\(n) \(n == 1 ? "Frage" : "Fragen") an dich" }

    static func kopfzeile(zeilen: Int, geladen: Bool) -> String {
        zeilen > 0 ? (zeilen == 1 ? "1 Bereich" : "\(zeilen) Bereiche") : (geladen ? "Noch keine Bereiche" : "Lade die Bereiche …")
    }
}

extension Menschlich {
    static func anfuehrung(_ t: String, _ max: Int) -> String { "„\(kuerzen(klartext(t), max))“" }

    static func urlTeil(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")) ?? s
    }
}
