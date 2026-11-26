import Foundation

enum Team {

    static func jobsVonAgent(_ jobs: [OvAuftrag], _ id: String) -> [OvAuftrag] { jobs.filter { $0.agent == id } }
    static func systemJobs(_ jobs: [OvAuftrag]) -> [OvAuftrag] { jobs.filter { $0.agent.isEmpty } }

    enum Zustand: String, Equatable { case arbeitet, wartet, fehler, ruhig }

    struct Status: Equatable {
        var zustand: Zustand
        var text: String
    }

    static func zustandWort(_ z: Zustand) -> String {
        switch z { case .arbeitet: return "arbeitet"; case .wartet: return "braucht dich"; case .fehler: return "Störung"; case .ruhig: return "" }
    }

    static func zustandSatz(_ s: Status, wer: String) -> String {
        switch s.zustand {
        case .arbeitet: return "\(wer) arbeitet gerade."
        case .wartet: return "\(wer) \(s.text)."
        case .fehler: return "Störung: \(s.text)."
        case .ruhig: return ""
        }
    }

    static func status(_ ov: OvDaten, id: String, ents: [OvEntscheidung], arbeitend: Set<String>, jetzt: Double) -> Status {
        let zeilen = ov.rows.filter { $0.agentId == id }
        let haupt = zeilen.first { $0.key.passt(#"^agent:[^:]+:main$"#) }
        let fehlerJob = jobsVonAgent(ov.jobs, id).filter { $0.aktiv }.first { $0.lastRunStatus == "error" && ($0.lastRunAtMs ?? 0) > jetzt - 2 * 86_400_000 }
        let bereich = ov.bereiche?.areas.first { $0.leader == id }
        let wartet = bereich.map { b in ents.filter { $0.bereichId == b.id && !$0.ruhend }.count } ?? 0
        if zeilen.contains(where: { $0.live }) || arbeitend.contains(id) { return Status(zustand: .arbeitet, text: "arbeitet gerade") }
        if haupt?.status == "failed", let f = haupt?.letzterFehler { return Status(zustand: .fehler, text: fehlerUrsache(f).kurz) }
        if let j = fehlerJob { return Status(zustand: .fehler, text: fehlerUrsache(j.letzterFehler ?? "").kurz) }
        if wartet > 0 { return Status(zustand: .wartet, text: wartet == 1 ? "wartet auf eine Entscheidung von dir" : "wartet auf \(wartet) Entscheidungen von dir") }
        return Status(zustand: .ruhig, text: "ruhig")
    }

    struct Gruppe: Equatable, Identifiable {
        var titel: String
        var leute: [Person]
        var id: String { titel.isEmpty ? "stab" : titel }
    }

    static func gruppen(_ ov: OvDaten) -> [Gruppe] {
        let p = Gegenueber.personenVon(ov)
        return ([Gruppe(titel: "", leute: [p.seneca])] + p.bereiche.map { Gruppe(titel: $0.name, leute: $0.leute) }).filter { !$0.leute.isEmpty }
    }

    struct Ursache: Equatable {
        var art: String
        var kurz: String
        var detail: String?
        var zustellung = false
    }

    static func fehlerUrsache(_ roh: String) -> Ursache {
        let r = roh
        var ab: String?
        if let m = r.treffer(#"resets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, "i") {
            var h = Int(m[1] ?? "0") ?? 0
            let ap = m[3]?.lowercased()
            if ap == "pm" && h < 12 { h += 12 }
            if ap == "am" && h == 12 { h = 0 }
            ab = String(format: "ab %02d:%@ wieder frei", h, m[2] ?? "00")
        }
        if r.passt(#"channel is required|no configured channels"#, "i") {
            return Ursache(art: "kanal", kurz: "Fertig, aber nicht als Nachricht zugestellt", detail: "Es ist kein Nachrichtenkanal eingerichtet.", zustellung: true)
        }
        if r.passt(#"weekly limit"#, "i") { return Ursache(art: "wochenlimit", kurz: "Wochenlimit erreicht", detail: ab) }
        if r.passt(#"daily limit"#, "i") { return Ursache(art: "tageslimit", kurz: "Tageslimit erreicht", detail: ab) }
        if r.passt(#"usage limit|rate[_ ]?limit|\b429\b|hit your .*limit"#, "i") { return Ursache(art: "limit", kurz: "Nutzungslimit erreicht", detail: ab) }
        if r.passt(#"billing|credit|guthaben|insufficient|quota"#, "i") { return Ursache(art: "abrechnung", kurz: "Abrechnungsproblem beim Modellanbieter") }
        if r.passt(#"timed? ?out|timeout|zu lange"#, "i") { return Ursache(art: "zeit", kurz: "Hat zu lange gedauert und wurde abgebrochen") }
        if r.passt(#"-600|Programm läuft nicht|is not running"#, "i") { return Ursache(art: "kalender-app", kurz: "Die Kalender-App lief nicht") }
        if r.passt(#"tool authority registration"#, "i") { return Ursache(art: "start", kurz: "Konnte nicht starten", detail: "Interner Fehler bei der Werkzeug-Berechtigung.") }
        if r.passt(#"overloaded|529|503|unavailable"#, "i") { return Ursache(art: "ueberlastet", kurz: "Der Modellanbieter war überlastet") }
        if r.passt(#"unauthorized|401|forbidden|403|invalid.*key"#, "i") { return Ursache(art: "zugang", kurz: "Zugang abgelehnt", detail: "Der Schlüssel oder die Anmeldung stimmt nicht.") }
        if r.passt(#"ECONN|ENOTFOUND|network|fetch failed"#, "i") { return Ursache(art: "netz", kurz: "Keine Verbindung") }
        let erste = (r.components(separatedBy: "\n").first ?? "").ersetze(#"^All models failed \(\d+\):\s*"#, "", "i").ersetze(#"\s*\([a-z_]+\)\s*$"#, "").jsTrim
        return Ursache(art: "sonst", kurz: erste.isEmpty ? "Mit einem Fehler beendet" : Menschlich.kuerzen(erste, 90))
    }

    static func takt(_ j: OvAuftrag, expr: String? = nil) -> String {
        if j.art == "every", let ms = j.everyMs, ms > 0 {
            let m = Int((ms / 60_000).rounded())
            return m < 60 ? "alle \(m) Min." : m % 60 == 0 ? (m == 60 ? "stündlich" : "alle \(m / 60) Std.") : "alle \(m) Min."
        }
        guard let e = expr ?? j.cronAusdruck else { return "" }
        let p = e.jsTrim.teileNach(#"\s+"#)
        if p.count < 5 { return e }
        let mi = p[0], h = p[1], dom = p[2], dow = p[4]
        if !mi.passt(#"^\d+$"#) || !h.passt(#"^\d+$"#) { return e }
        let zeit = String(format: "%02d:%02d", Int(h) ?? 0, Int(mi) ?? 0)
        if dom.hasPrefix("*/") { return "alle \(dom.dropFirst(2)) Tage um \(zeit)" }
        if dow != "*" {
            let tage = dow.components(separatedBy: ",").map { x in Int(x).map { Menschlich.wochentagKurz[$0 % 7] } ?? x }
            return "\(tage.joined(separator: ", ")) um \(zeit)"
        }
        return "täglich um \(zeit)"
    }
}
