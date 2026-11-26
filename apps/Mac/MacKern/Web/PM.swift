import Foundation

enum PM {
    typealias Info = HeuteLogik.ProjektInfo

    static let tag: Double = 86_400_000

    static let gesundText: [HeuteLogik.Gesundheit: String] = [.gruen: "Läuft", .gelb: "Braucht Aufmerksamkeit", .rot: "Stockt", .grau: "Ruhig"]
    static func prioZahl(_ c: OvKarte) -> Int { HeuteLogik.prio(c) }
    static func istEntscheidung(_ c: OvKarte) -> Bool { HeuteLogik.istEntscheidung(c) }

    struct Wartet: Equatable {
        enum Wer: String { case dich, leiter, extern, niemand }
        var wer: Wer
        var text: String
    }

    static func wartetAuf(ents: [OvEntscheidung], pruefung: [OvKarte], blockiert: [OvKarte], naechster: OvKarte?, leiterName: String?) -> Wartet {
        if ents.contains(where: { !$0.ruhend }) { return Wartet(wer: .dich, text: "wartet auf dich") }
        if !pruefung.isEmpty { return Wartet(wer: .dich, text: "wartet auf deine Prüfung") }
        guard let n = naechster else { return Wartet(wer: .niemand, text: "") }
        if n.status == "blocked" {
            let wartetE = n.labels.contains { $0.hasPrefix("wartet-auf-") }
            return wartetE ? Wartet(wer: .dich, text: "wartet auf deine Entscheidung") : Wartet(wer: .extern, text: "wartet auf Dritte")
        }
        if n.agentId == nil { return Wartet(wer: .dich, text: "liegt bei dir") }
        let name = (leiterName ?? "").isEmpty ? "Mitarbeiter" : leiterName!
        return Wartet(wer: .leiter, text: "\(name) arbeitet daran")
    }

    struct FokusKandidat: Equatable {
        var card: OvKarte
        var grund: String
        var punkte: Int
    }

    static func fokusKandidaten(_ ov: OvDaten, jetzt: Double) -> [FokusKandidat] {
        let heute = Menschlich.tagStart(jetzt)
        var res: [FokusKandidat] = []
        for c in ov.cards {
            if c.status == "done" || c.archiviert || istEntscheidung(c) { continue }
            if !(c.agentId == nil || c.boardId == "privat") { continue }
            let plan = Menschlich.planVon(c.labels)
            let frist = Menschlich.fristVon(c.labels)
            var punkte = 0
            var grund = ""
            if let f = frist, f < heute { punkte += 100; grund = "überfällig seit \(Menschlich.datumKurz(f))" }
            else if let f = frist, f <= heute + 2 * tag { punkte += 70; grund = f == heute ? "Frist heute" : "Frist \(Menschlich.datumKurz(f))" }
            if let p = plan, p <= heute { punkte += 60; if grund.isEmpty { grund = "für heute geplant" } }
            if c.status == "running" || c.status == "review" { punkte += 30 }
            punkte += (3 - prioZahl(c)) * 8
            if c.status == "backlog" { punkte -= 40 }
            if Muster.passt(c.title, #"^\[PARKIERT"#, gross: true) { punkte -= 80 }
            res.append(FokusKandidat(card: c, grund: grund, punkte: punkte))
        }
        return res.enumerated().sorted { ($1.element.punkte, $0.offset) < ($0.element.punkte, $1.offset) }.map(\.element)
    }

    static func sortiereKarten(_ karten: [OvKarte]) -> [OvKarte] {
        karten.enumerated().sorted { a, b in
            let x = (HeuteLogik.kartenOrdnung[a.element.status] ?? 9, prioZahl(a.element), a.element.position, a.offset)
            let y = (HeuteLogik.kartenOrdnung[b.element.status] ?? 9, prioZahl(b.element), b.element.position, b.offset)
            return x < y
        }.map(\.element)
    }

    static func fortschritt(_ p: Info) -> (fertig: Int, alle: Int) { (p.fertigA.count, p.aufgaben.count) }

    static func werDran(_ p: Info, label: (String) -> String) -> String {
        var agenten: [String] = []
        for c in p.aufgaben where c.status == "running" {
            guard let a = c.agentId else { continue }
            let n = label(a).isEmpty ? a : label(a)
            if !agenten.contains(n) { agenten.append(n) }
        }
        if !agenten.isEmpty { return agenten.joined(separator: ", ") }
        if p.wartet.wer == .dich { return "Antonio" }
        if let n = p.naechster, n.agentId == nil { return "Antonio" }
        if let a = p.naechster?.agentId { return label(a).isEmpty ? a : label(a) }
        return "niemand zugeteilt"
    }

    struct WartetAufDich: Equatable {
        enum Art: String { case entscheidung, pruefung, karte }
        var id: String
        var projektId: String
        var projektName: String
        var titel: String
        var seit: Double?
        var art: Art
    }

    static func statusSeit(_ c: OvKarte, _ status: String) -> Double? {
        c.events.last { $0.nachStatus == status }?.at
    }

    static func wartetAufDich(_ ps: [Info]) -> [WartetAufDich] {
        var out: [WartetAufDich] = []
        for p in ps {
            for e in p.ents where !e.ruhend {
                out.append(WartetAufDich(id: "e:" + e.id, projektId: p.id, projektName: p.name, titel: e.frage, seit: e.gestelltAm, art: .entscheidung))
            }
            for c in p.pruefung {
                out.append(WartetAufDich(id: "p:" + c.id, projektId: p.id, projektName: p.name, titel: Menschlich.klartext(c.title), seit: statusSeit(c, "review"), art: .pruefung))
            }
            for c in p.blockiert where c.labels.contains(where: { $0.hasPrefix("wartet-auf-") }) {
                out.append(WartetAufDich(id: "b:" + c.id, projektId: p.id, projektName: p.name, titel: Menschlich.klartext(c.title), seit: statusSeit(c, "blocked"), art: .karte))
            }
            for c in p.offenA where c.status != "review" && c.status != "blocked" && c.labels.contains("wartet-auf-antonio") {
                out.append(WartetAufDich(id: "k:" + c.id, projektId: p.id, projektName: p.name, titel: Menschlich.klartext(c.title), seit: nil, art: .karte))
            }
        }
        return out.enumerated().sorted { ($0.element.seit ?? .infinity, $0.offset) < ($1.element.seit ?? .infinity, $1.offset) }.map(\.element)
    }

    struct Statistik: Equatable {
        var erledigtWoche: Int
        var offenGesamt: Int
        var aeltesteOffenTage: Int?
        var ohneVerantwortlichen: Int
    }

    static func projektStatistik(_ ps: [Info], jetzt: Double, label: (String) -> String) -> Statistik {
        let woche = 7 * tag
        var erledigt = 0, offen = 0, ohne = 0
        var aeltest: Double?
        for p in ps {
            for c in p.fertigA { if let z = c.completedAt, jetzt - z <= woche { erledigt += 1 } }
            offen += p.offenA.count
            for c in p.offenA { if let z = c.createdAt, aeltest == nil || z < aeltest! { aeltest = z } }
            if werDran(p, label: label) == "niemand zugeteilt" { ohne += 1 }
        }
        return Statistik(erledigtWoche: erledigt, offenGesamt: offen, aeltesteOffenTage: aeltest.map { Menschlich.tageZwischen($0, jetzt) }, ohneVerantwortlichen: ohne)
    }

    static func istVorrat(id: String, name: String, bereichId: String) -> Bool {
        id == "default" || Muster.passt(name.trimmingCharacters(in: .whitespaces), #"^(sonstiges|ohne projekt)$"#, gross: true) || (!bereichId.isEmpty && id == bereichId)
    }
    static func istVorrat(_ p: Info) -> Bool { istVorrat(id: p.id, name: p.name, bereichId: p.bereichId) }

    struct Risikoeintrag: Equatable {
        enum Stufe: String { case hoch, mittel }
        var stufe: Stufe
        var text: String
    }

    static let risikoTage = 3
    static let stillstandTage = 7
    static let arbeitStatus: Set<String> = ["todo", "ready", "scheduled", "running", "review", "blocked"]

    static func letzteBewegung(_ c: OvKarte) -> Double {
        let e = c.events.filter { $0.art != "diagnostic" }.map(\.at)
        let k = c.kommentare.map(\.createdAt)
        let alle = (e + k).filter { $0.isFinite }
        return alle.max() ?? c.createdAt ?? 0
    }

    private static func agentAus(_ key: String?) -> String {
        Muster.erster(key ?? "", #"^agent:([^:]+):"#)?[1] ?? ""
    }

    static func projektRisiken(_ p: Info, rows: [OvSitzung], jobs: [OvAuftrag], jetzt: Double, prognose pr: Prognose.Ergebnis? = nil) -> [Risikoeintrag] {
        var out: [Risikoeintrag] = []
        let grenze = jetzt - Double(risikoTage) * tag
        var agenten = Set<String>()
        if let a = p.projekt.agent { agenten.insert(a) }
        for c in p.aufgaben { if let a = c.agentId { agenten.insert(a) } }
        let kaputt = rows.filter { r in
            ["failed", "killed", "timeout"].contains(r.status ?? "") && (r.endedAt ?? 0) >= grenze && r.spawnedBy != nil
                && (agenten.contains(agentAus(r.spawnedBy)) || agenten.contains(r.agentId ?? ""))
        }
        if !kaputt.isEmpty {
            var namen: [String] = []
            for r in kaputt {
                var n = r.label ?? r.derivedTitle ?? r.displayName ?? ""
                n = n.replacingOccurrences(of: #"^[^—]{0,40}—\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if !n.isEmpty && !namen.contains(n) { namen.append(n) }
            }
            namen = Array(namen.prefix(2))
            let wann = Menschlich.tageZwischen(kaputt.compactMap(\.endedAt).max() ?? jetzt, jetzt)
            let wo = wann <= 0 ? "Heute" : wann == 1 ? "Gestern" : "In den letzten \(risikoTage) Tagen"
            let was = kaputt.count == 1 ? "ist ein Teilauftrag" : "sind \(kaputt.count) Teilaufträge"
            out.append(Risikoeintrag(stufe: .hoch, text: "\(wo) \(was) fehlgeschlagen\(namen.isEmpty ? "" : ", darunter " + namen.joined(separator: " und "))."))
        }
        for j in jobs {
            guard let a = p.projekt.agent, j.agent == a, j.aktiv else { continue }
            if j.lastRunStatus == "error", (j.lastRunAtMs ?? 0) >= grenze {
                out.append(Risikoeintrag(stufe: .hoch, text: "Der Lauf „\(HeuteLogik.jobName(j))“ ist zuletzt fehlgeschlagen."))
            }
        }
        if pr?.urteil == .passtNicht, let n = pr?.tageNachFrist {
            out.append(Risikoeintrag(stufe: .hoch, text: "Die Frist passt nicht: Beim bisherigen Tempo wäre alles erst \(n) \(n == 1 ? "Tag" : "Tage") danach fertig."))
        } else if pr?.urteil == .knapp {
            out.append(Risikoeintrag(stufe: .mittel, text: "Die Frist ist knapp: Nur mit dem schnelleren Tempo der letzten Tage wird es rechtzeitig."))
        } else if let f = p.frist, f < Menschlich.tagStart(jetzt), !p.offenA.isEmpty {
            out.append(Risikoeintrag(stufe: .hoch, text: "Die Frist vom \(Menschlich.datumKurz(f)) ist überschritten, \(p.offenA.count) \(p.offenA.count == 1 ? "Aufgabe ist" : "Aufgaben sind") noch offen."))
        }
        if !p.blockiert.isEmpty {
            out.append(Risikoeintrag(stufe: .hoch, text: p.blockiert.count == 1 ? "Eine Aufgabe ist blockiert: \(Menschlich.klartext(p.blockiert[0].title))." : "\(p.blockiert.count) Aufgaben sind blockiert."))
        }
        let still = p.offenA.filter { arbeitStatus.contains($0.status) && $0.status != "blocked" && jetzt - letzteBewegung($0) > Double(stillstandTage) * tag && letzteBewegung($0) > 0 }
            .sorted { letzteBewegung($0) < letzteBewegung($1) }
        if let erste = still.first {
            let wer = still.count == 1 ? "Eine Aufgabe liegt" : "\(still.count) Aufgaben liegen"
            out.append(Risikoeintrag(stufe: .mittel, text: "\(wer) seit mehr als \(stillstandTage) Tagen ohne Bewegung, die längste seit \(Menschlich.tageZwischen(letzteBewegung(erste), jetzt)) Tagen: „\(String(Menschlich.klartext(erste.title).prefix(60)))“."))
        }
        return out.enumerated().sorted { a, b in
            let x = (a.element.stufe == .hoch ? 0 : 1, a.offset), y = (b.element.stufe == .hoch ? 0 : 1, b.offset)
            return x < y
        }.map(\.element)
    }

    static let zahlWorte = ["kein", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"]

    static func zahlWort(_ n: Int, gross: Bool = false) -> String {
        let w = n >= 0 && n <= 12 ? (n == 1 && !gross ? "eins" : zahlWorte[n]) : String(n)
        return gross ? String(w.prefix(1)).uppercased() + w.dropFirst() : w
    }
    static func zahlWortVor(_ n: Int, gross: Bool = false) -> String { n == 1 ? (gross ? "Ein" : "ein") : zahlWort(n, gross: gross) }

    static func kopfsatzTeile(rot: Int, wartet: Int) -> (probleme: String, wartetText: String) {
        let probleme = rot > 0 ? "\(zahlWort(rot, gross: true)) \(rot == 1 ? "Projekt hat" : "Projekte haben") Probleme" : ""
        let wartetText = wartet > 0 ? "\(zahlWortVor(wartet, gross: probleme.isEmpty)) \(wartet == 1 ? "Ding wartet" : "Dinge warten") auf dich" : ""
        return (probleme, wartetText)
    }

    static func kopfsatz(rot: Int, wartet: Int, projekte: Int) -> String {
        if projekte == 0 { return "Hier beginnt dein nächstes Vorhaben." }
        let t = kopfsatzTeile(rot: rot, wartet: wartet)
        if !t.probleme.isEmpty || !t.wartetText.isEmpty {
            return t.probleme + (!t.probleme.isEmpty && !t.wartetText.isEmpty ? ", " : "") + t.wartetText + "."
        }
        return projekte == 1 ? "Ein Projekt läuft." : "\(zahlWort(projekte, gross: true)) Projekte laufen."
    }

    static func fristMs(_ p: Info, plan: Plan.Kurz?) -> Double? {
        if let f = p.frist { return f }
        if let s = plan?.frist, Muster.passt(s, #"^\d{4}-\d{2}-\d{2}"#) {
            let ms = Menschlich.ausIso(String(s.prefix(10)))
            return ms.isNaN ? nil : ms
        }
        return nil
    }

    static func risikoVon(_ p: Info, plan: Plan.Kurz?, jetzt: Double) -> (r: Plan.Risiko?, grund: String) {
        if let r = plan?.risiko { return (r, "laut Plan") }
        guard let frist = fristMs(p, plan: plan) else { return (nil, "ohne Frist") }
        let offen = p.offenA.count
        let tage = Int(((frist - Menschlich.tagStart(jetzt)) / tag).rounded(.up))
        if offen == 0 { return (.bequem, "nichts mehr offen") }
        if tage < 0 { return (.passtNicht, "Frist überschritten") }
        let proTag = Double(offen) / Double(max(tage, 1))
        let wie: Plan.Risiko = proTag > 2 ? .passtNicht : proTag > 1 ? .knapp : .bequem
        return (wie, "\(offen) offene \(offen == 1 ? "Karte" : "Karten"), \(tage == 0 ? "Frist heute" : "\(tage) \(tage == 1 ? "Tag" : "Tage") Zeit")")
    }
}
