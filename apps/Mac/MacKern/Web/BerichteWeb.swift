import Foundation

enum BerichteWeb {
    static let tage: Double = 30
    private static let tagMs: Double = 86_400_000

    struct Lauf: Equatable {
        var start: Double
        var dauer: Double
        var status: String
        var zustellung: String
        var summary: String
    }

    struct Nachricht: Equatable {
        var rolle: String
        var zeit: Double?
        var text: String
    }

    struct Roh: Equatable {
        var jobId: String
        var sessionKey: String
        var agentId: String
        var laeufe: [Lauf]
        var nachrichten: [Nachricht]
    }

    struct Bericht: Equatable, Identifiable {
        var schluessel: String
        var id: String
        var jobId: String
        var von: String
        var name: String
        var zeit: Double
        var satz: String
        var text: String
        var neu: Bool
        var chatKey: String
        var agentId: String
    }

    struct Stand: Equatable {
        var liste: [Bericht] = []
        var ungelesen = 0
        var fertig = false
    }

    static func berichtAgent(_ j: OvAuftrag, standard: String) -> String { j.agent.isEmpty ? standard : j.agent }

    static func istMelder(_ j: OvAuftrag) -> Bool { j.deliveryMode == "announce" }

    static func schluessel(_ jobId: String, _ start: Double) -> String { "lauf:\(jobId):\(Int64(start))" }

    static func berichtId(_ jobId: String, _ start: Double) -> String { "\(jobId).\(Int64(start))" }

    static func signatur(_ jobs: [OvAuftrag]) -> String {
        jobs.filter(istMelder).map { "\($0.id):\(Int64($0.lastRunAtMs ?? 0))" }.joined(separator: "|")
    }

    static func chatSchluessel(erster: String?, job: OvAuftrag, standard: String) -> String {
        let k = (erster ?? "").ersetze(#":run:[^:]+$"#, "")
        return k.isEmpty ? "agent:\(berichtAgent(job, standard: standard)):cron:\(job.id)" : k
    }

    private static func zeitAus(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        guard let s = v as? String else { return nil }
        return IsoZeit.datum(s).map { $0.timeIntervalSince1970 * 1000 }
    }

    static func laeufeAus(_ antwort: [String: Any]?) -> [Lauf] {
        ((antwort?["entries"] as? [[String: Any]]) ?? []).map { e in
            Lauf(start: KartenLesen.zahl(e["runAtMs"]) ?? 0, dauer: KartenLesen.zahl(e["durationMs"]) ?? 0, status: e["status"] as? String ?? "",
                 zustellung: e["deliveryStatus"] as? String ?? "", summary: (e["summary"] as? String ?? "").jsTrim)
        }
    }

    static func nachrichtenAus(_ antwort: [String: Any]?) -> [Nachricht] {
        ((antwort?["messages"] as? [[String: Any]]) ?? []).map { m in
            Nachricht(rolle: m["role"] as? String ?? "", zeit: zeitAus(m["timestamp"]), text: Zuege.textVon(m["content"]).jsTrim)
        }
    }

    static func rohAus(job: OvAuftrag, laeufe: [String: Any]?, verlauf: [String: Any]?, standard: String) -> Roh? {
        let l = laeufeAus(laeufe)
        guard !l.isEmpty else { return nil }
        let erster = ((laeufe?["entries"] as? [[String: Any]])?.first?["sessionKey"]) as? String
        return Roh(jobId: job.id, sessionKey: chatSchluessel(erster: erster, job: job, standard: standard), agentId: berichtAgent(job, standard: standard),
                   laeufe: l, nachrichten: nachrichtenAus(verlauf))
    }

    static func ersterSatz(_ text: String) -> String {
        let ohne = text.ersetzeAlle(#"```seneca[\s\S]*?(```|$)"#, "\n").jsTrim
        var t = (ohne.teileNach(#"\n\s*\n"#).first ?? "").ersetze(#"^[#>\-*\s]+"#, "").ersetzeAlle(#"[*_`]"#, "").ersetzeAlle(#"\s+"#, " ").jsTrim
        if t.isEmpty { t = text.treffer(#""titel"\s*:\s*"((?:[^"\\]|\\.)*)""#)?[1] ?? "" }
        let m = t.treffer(#"^(.{24,}?[.!?])(\s|$)"#)
        return Menschlich.kuerzen(m?[1] ?? t, 180)
    }

    static func liste(roh: [Roh], ov: OvDaten, jetzt: Double) -> [Bericht] {
        let ab = jetzt - tage * tagMs
        var out: [Bericht] = []
        for r in roh {
            guard let j = ov.jobs.first(where: { $0.id == r.jobId }) else { continue }
            for e in r.laeufe {
                guard e.start != 0, e.start >= ab, e.dauer > 20_000 else { continue }
                let zugestellt = e.zustellung == "not-delivered" && e.dauer > 30_000
                guard e.status == "ok" || zugestellt else { continue }
                let ende = e.start + e.dauer
                var text = ""
                for m in r.nachrichten where m.rolle == "assistant" {
                    guard let ts = m.zeit, ts >= e.start - 1000, ts <= ende + 120_000, !m.text.isEmpty else { continue }
                    text = m.text
                }
                if text.isEmpty { text = e.summary }
                if text.isEmpty { continue }
                let key = schluessel(j.id, e.start)
                let von = ov.label(berichtAgent(j, standard: ov.defaultAgent))
                out.append(Bericht(schluessel: key, id: berichtId(j.id, e.start), jobId: j.id, von: von.isEmpty ? "Seneca" : von, name: HeuteLogik.jobName(j), zeit: ende,
                                   satz: ersterSatz(text), text: text, neu: (ov.gesehen[key] ?? 0) == 0 && e.start > jetzt - 2 * tagMs,
                                   chatKey: r.sessionKey, agentId: r.agentId))
            }
        }
        return out.enumerated().sorted { ($1.element.zeit, $0.offset) < ($0.element.zeit, $1.offset) }.map(\.element)
    }

    static func stand(roh: [Roh], fertig: Bool, ov: OvDaten, jetzt: Double) -> Stand {
        let l = liste(roh: roh, ov: ov, jetzt: jetzt)
        return Stand(liste: l, ungelesen: l.filter(\.neu).count, fertig: fertig)
    }

    static func ueberschrift(_ s: Stand) -> String {
        if !s.fertig { return "Einen Moment." }
        if s.liste.isEmpty { return "Noch keine Berichte." }
        if s.ungelesen == 0 { return "Alles gelesen." }
        return s.ungelesen == 1 ? "Ein Bericht ist neu." : "\(s.ungelesen) Berichte sind neu."
    }

    static func finde(_ id: String, in s: Stand) -> Bericht? { s.liste.first { $0.id == id } }
}
