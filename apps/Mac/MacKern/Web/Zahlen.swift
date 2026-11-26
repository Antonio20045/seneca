import Foundation

enum Zahlen {
    static let geschuetzt: Set<String> = ["telcoradar", "sundartha-engineering", "pruefer"]
    static let markerMaxMs: Double = 2 * 3_600_000
    static let laufAltMs: Double = 12 * 3_600_000
    static let fertigMaxMs: Double = 6 * 3_600_000

    static func brauchtDichZahl(_ ents: [OvEntscheidung]) -> Int { ents.filter { !$0.ruhend }.count }

    struct LaufAuftrag: Equatable {
        enum Zustand: Equatable { case laeuft, fertig, fehler }
        var key: String
        var agentId: String
        var wer: String
        var was: String
        var seit: Double
        var ende: Double?
        var zustand: Zustand
        var karte: OvKarte?
    }

    struct ArbeitetGerade: Equatable {
        var agenten: Set<String> = []
        var auftraege: [LaufAuftrag] = []
        var zuletzt: LaufAuftrag?
        var karten = 0
        var n: Int { auftraege.count }
    }

    private static func agentVon(_ key: String?) -> String {
        guard let key, let m = key.range(of: #"^agent:([^:]+):"#, options: .regularExpression) else { return "" }
        return String(key[m].dropFirst(6).dropLast())
    }

    static func zeigbarerAuftrag(_ r: OvSitzung) -> Bool {
        let von = r.spawnedBy ?? ""
        if von.isEmpty { return false }
        if von.contains(":cron:") { return false }
        if geschuetzt.contains(agentVon(von)) { return false }
        return true
    }

    private static func laeuft(_ r: OvSitzung) -> Bool { r.live || r.status == "running" }
    private static func beginn(_ r: OvSitzung) -> Double {
        for v in [r.startedAt ?? r.sessionStartedAt, r.createdAt, r.updatedAt] { if let v, v != 0 { return v } }
        return 0
    }
    private static func titelVon(_ r: OvSitzung) -> String {
        let roh = [r.label, r.derivedTitle, r.displayName].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        return roh.replacingOccurrences(of: #"^[^—]{0,40}—\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func auftragsKarte(_ cards: [OvKarte], key: String, label: String?) -> OvKarte? {
        let mit = cards.filter { $0.labels.contains("auftrag") && !$0.archiviert }
        let t = (label ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return mit.first { $0.sessionKey == key } ?? (t.isEmpty ? nil : mit.first { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == t })
    }

    static func arbeitetGerade(_ ov: OvDaten, jetzt: Double) -> ArbeitetGerade {
        var res = ArbeitetGerade()
        for z in ov.liste?.laufendeKarten ?? [] {
            res.karten += 1
            if !z.agent.isEmpty, z.agent != "paket.sh" { res.agenten.insert(z.agent) }
        }
        for j in ov.jobs {
            if let s = j.runningAtMs, s != 0, jetzt - s <= markerMaxMs, !j.agent.isEmpty { res.agenten.insert(j.agent) }
        }
        for r in ov.rows {
            let b = beginn(r)
            let aktiv = laeuft(r) && !(b != 0 && jetzt - b > laufAltMs && !r.live)
            if aktiv, let a = r.agentId, !a.isEmpty { res.agenten.insert(a) }
            guard zeigbarerAuftrag(r), let agent = r.agentId, !agent.isEmpty else { continue }
            var basis = LaufAuftrag(key: r.key, agentId: agent, wer: ov.label(agent).isEmpty ? agent : ov.label(agent),
                                    was: titelVon(r).isEmpty ? "Auftrag" : titelVon(r), seit: b, ende: nil, zustand: .laeuft,
                                    karte: auftragsKarte(ov.cards, key: r.key, label: r.label))
            if aktiv {
                res.auftraege.append(basis)
            } else if let ende = r.endedAt, ende != 0, jetzt - ende <= fertigMaxMs, ["done", "failed", "killed", "timeout"].contains(r.status ?? "") {
                basis.ende = ende
                basis.zustand = r.status == "done" ? .fertig : .fehler
                if res.zuletzt == nil || ende > (res.zuletzt?.ende ?? 0) { res.zuletzt = basis }
            }
        }
        res.auftraege.sort { $0.seit < $1.seit }
        for a in res.auftraege { res.agenten.insert(a.agentId) }
        return res
    }
}
