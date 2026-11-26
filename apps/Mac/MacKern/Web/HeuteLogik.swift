import Foundation

enum Muster {
    private static let sperre = NSLock()
    nonisolated(unsafe) private static var gemerkt: [String: NSRegularExpression] = [:]
    private static func hole(_ muster: String, _ gross: Bool) -> NSRegularExpression? {
        let k = (gross ? "i" : "-") + muster
        sperre.lock(); defer { sperre.unlock() }
        if let re = gemerkt[k] { return re }
        guard let re = try? NSRegularExpression(pattern: muster, options: gross ? [.caseInsensitive] : []) else { return nil }
        if gemerkt.count > 400 { gemerkt.removeAll() }
        gemerkt[k] = re
        return re
    }
    static func erster(_ s: String, _ muster: String, gross: Bool = false) -> [String?]? {
        guard let re = hole(muster, gross) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }
    static func passt(_ s: String, _ muster: String, gross: Bool = false) -> Bool { erster(s, muster, gross: gross) != nil }
}

extension Menschlich {
    static func seitText(_ ms: Double, jetzt: Double) -> String {
        let t = tageZwischen(ms, jetzt)
        if t <= 0 { return "seit heute" }
        if t == 1 { return "seit gestern" }
        if t < 14 { return "seit \(t) Tagen" }
        if t < 60 { return "seit \(Int((Double(t) / 7).rounded())) Wochen" }
        return "seit \(Int((Double(t) / 30).rounded())) Monaten"
    }
}

enum HeuteLogik {

    static let zahlwort = ["", "Eine", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht", "Neun", "Zehn", "Elf", "Zwölf"]

    static func lageSatz(_ braucht: Int) -> String {
        if braucht <= 0 { return "Nichts wartet auf dich." }
        if braucht == 1 { return "Eine Frage wartet auf dich." }
        return "\(braucht < zahlwort.count ? zahlwort[braucht] : String(braucht)) Fragen warten auf dich."
    }

    struct Erkannt: Equatable {
        var titel: String
        var min: Int?
        var bereichId: String?
        var hoch = false
    }

    private static func trimmen(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^[\s,;:–—-]+|[\s,;:–—-]+$"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func erkenneUhrzeit(_ text: String) -> (min: Int, rest: String)? {
        let muster = [
            #"(?:\b(?:um|gegen|ab)\s+)?\b([01]?\d|2[0-3]):([0-5]\d)(?:\s*Uhr\b)?"#,
            #"(?:\b(?:um|gegen|ab)\s+)?\b([01]?\d|2[0-3])\.([0-5]\d)\s*Uhr\b"#,
            #"(?:\b(?:um|gegen|ab)\s+)?\b([01]?\d|2[0-3])\s*Uhr\b(?:\s*([0-5]\d)\b)?"#,
        ]
        let ns = text as NSString
        var best: (at: Int, len: Int, min: Int)?
        var belegt: [(Int, Int)] = []
        for p in muster {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let at = m.range.location, ende = at + m.range.length
                if belegt.contains(where: { at < $0.1 && ende > $0.0 }) { continue }
                let davor = ns.substring(with: NSRange(location: max(0, at - 5), length: at - max(0, at - 5)))
                if Muster.passt(davor, #"\bbis\s+$"#, gross: true) { continue }
                belegt.append((at, ende))
                let h = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let mi = m.range(at: 2).location == NSNotFound ? 0 : Int(ns.substring(with: m.range(at: 2))) ?? 0
                if best == nil || at >= best!.at { best = (at, m.range.length, h * 60 + mi) }
            }
        }
        guard let b = best else { return nil }
        let rest = trimmen(ns.substring(to: b.at) + " " + ns.substring(from: b.at + b.len))
        return (b.min, rest.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : rest)
    }

    static func erkenneBereich(_ text: String, _ bereiche: [(id: String, name: String)]) -> (bereichId: String, rest: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for b in bereiche.sorted(by: { $0.name.count > $1.name.count }) {
            let name = b.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            let n = NSRegularExpression.escapedPattern(for: name)
            if let m = Muster.erster(t, "^\(n)\\s*[:,–—-]\\s*(.+)$", gross: true), let r = m[1] { return (b.id, trimmen(r)) }
            if let m = Muster.erster(t, "^(.+?)\\s*[,(:–—-]\\s*\(n)\\s*\\)?$", gross: true), let r = m[1] { return (b.id, trimmen(r)) }
            if Muster.passt(t, "^\(n)\\s+\\S", gross: true) || Muster.passt(t, "\\S\\s+\(n)$", gross: true) { return (b.id, t) }
        }
        return nil
    }

    static func notizAuswerten(_ roh: String, _ bereiche: [(id: String, name: String)]) -> Erkannt {
        var t = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        let hoch = t.hasPrefix("!")
        if hoch { t = t.replacingOccurrences(of: #"^!+\s*"#, with: "", options: .regularExpression) }
        var out = Erkannt(titel: t, hoch: hoch)
        if let b = erkenneBereich(t, bereiche) { t = b.rest; out.bereichId = b.bereichId }
        if let z = erkenneUhrzeit(t) { t = z.rest; out.min = z.min }
        out.titel = t
        return out
    }

    struct PlanInfo: Equatable {
        var tag: Double?
        var min: Int?
        var bis: Int?
        var fertigWenn: String?
    }

    static func planInfo(_ c: OvKarte) -> PlanInfo {
        let l = c.labels.first { $0.hasPrefix("plan:") }
        let v = l.map { String($0.dropFirst(5)) } ?? ""
        func hm(_ h: String?, _ m: String?) -> Int? { (Int(h ?? "")).flatMap { h in Int(m ?? "").map { h * 60 + $0 } } }
        var info = PlanInfo()
        if let m = Muster.erster(v, #"^(\d{4}-\d{2}-\d{2})(?:[T@ ](\d{1,2}):(\d{2})(?:-(\d{1,2}):(\d{2}))?)?"#), let tag = m[1] {
            let ms = Menschlich.ausIso(tag)
            info.tag = ms.isNaN ? nil : ms
            if m[2] != nil { info.min = hm(m[2], m[3]); if m[4] != nil { info.bis = hm(m[4], m[5]) } }
        }
        let notes = c.notes ?? ""
        if info.min == nil, let t = Muster.erster(notes, #"\b([01]?\d|2[0-3]):([0-5]\d)(?:\s*(?:bis|–|-)\s*([01]?\d|2[0-3]):([0-5]\d))?"#) {
            info.min = hm(t[1], t[2])
            if t[3] != nil { info.bis = hm(t[3], t[4]) }
        }
        if let fw = Muster.erster(notes, #"fertig,?\s+wenn\s+([^\n]+)"#, gross: true), let w = fw[1] {
            info.fertigWenn = w.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
        return info
    }

    static func prio(_ c: OvKarte) -> Int { ["urgent": 0, "high": 1, "normal": 2, "low": 3][c.priority ?? "normal"] ?? 2 }

    struct Todo: Equatable {
        var card: OvKarte
        var titel: String
        var board: String
        var geparkt: Bool
        var irgendwann: Bool
    }
    struct Todos: Equatable {
        var offen: [Todo]
        var erledigt: [Todo]
        var heuteErledigt: [Todo]
    }

    static func todos(_ cards: [OvKarte], jetzt: Double) -> Todos {
        let mine = cards.filter { $0.boardId == "privat" || $0.agentId == nil }
        func map(_ c: OvKarte) -> Todo {
            let geparkt = Muster.passt(c.title, #"^\[PARKIERT[^\]]*?(\d{1,2}\.\d{1,2}\.)?\]\s*"#, gross: true)
            return Todo(card: c, titel: c.title.replacingOccurrences(of: #"^\[[^\]]*\]\s*"#, with: "", options: .regularExpression),
                        board: c.boardId, geparkt: geparkt, irgendwann: c.status == "backlog")
        }
        let offen = mine.filter { $0.status != "done" }.map(map).enumerated().sorted { a, b in
            let x = (a.element.geparkt ? 1 : 0, a.element.irgendwann ? 1 : 0, prio(a.element.card), a.offset)
            let y = (b.element.geparkt ? 1 : 0, b.element.irgendwann ? 1 : 0, prio(b.element.card), b.offset)
            return x < y
        }.map(\.element)
        let t0 = Menschlich.tagStart(jetzt)
        let erledigt = mine.filter { $0.status == "done" }.map(map)
        return Todos(offen: offen, erledigt: erledigt, heuteErledigt: erledigt.filter { ($0.card.completedAt ?? $0.card.updatedAt ?? 0) >= t0 })
    }

    struct TodoZeile: Equatable, Identifiable {
        var card: OvKarte
        var titel: String
        var projekt: String
        var tag: Double
        var ueber: Bool
        var min: Int?
        var bis: Int?
        var fertigWenn: String?
        var bereichId: String?
        var id: String { card.id }
    }

    static func tagesTodos(_ cards: [OvKarte], projekte: [(id: String, frist: Double?)], projektName: (OvKarte) -> String, tag0: Double, jetzt: Double) -> [TodoZeile] {
        var fristen: [String: Double?] = [:]
        for p in projekte { fristen[p.id] = p.frist }
        func frist(_ z: TodoZeile) -> Double { (fristen[z.card.boardId] ?? nil) ?? Menschlich.fristVon(z.card.labels) ?? .infinity }
        let zeilen: [TodoZeile] = todos(cards, jetzt: jetzt).offen
            .filter { !$0.geparkt && !$0.card.labels.contains { $0.hasPrefix("entscheidung") } }
            .compactMap { t in
                let p = planInfo(t.card)
                guard let tag = p.tag, tag <= tag0 else { return nil }
                let titel = Menschlich.klartext(t.card.title)
                return TodoZeile(card: t.card, titel: titel.isEmpty ? t.titel : titel, projekt: projektName(t.card), tag: tag, ueber: tag < tag0,
                                 min: p.min, bis: p.bis, fertigWenn: p.fertigWenn,
                                 bereichId: t.card.labels.first { $0.hasPrefix("bereich:") }.map { String($0.dropFirst(8)) })
            }
        return zeilen.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if x.ueber != y.ueber { return x.ueber }
            if prio(x.card) != prio(y.card) { return prio(x.card) < prio(y.card) }
            if frist(x) != frist(y) { return frist(x) < frist(y) }
            if x.tag != y.tag { return x.tag < y.tag }
            if (x.min ?? 1_000_000_000) != (y.min ?? 1_000_000_000) { return (x.min ?? 1_000_000_000) < (y.min ?? 1_000_000_000) }
            return a.offset < b.offset
        }.map(\.element)
    }

    static let kurzNamen: [String: (name: String, kontext: String)] = [
        "hermes": ("Hermes", "Sundartha"), "powerbi": ("Power BI", "Vodafone"), "privat": ("Privat", ""), "sundartha": ("Sundartha", ""),
        "telco-radar": ("Telco-Radar", "Vodafone"), "vodafone": ("Sonstiges", "Vodafone"),
    ]
    static func boardName(_ ov: OvDaten, _ id: String) -> String {
        if let k = kurzNamen[id] { return k.name }
        let n = Menschlich.cleanName(ov.boards.first { $0.id == id }?.name)
        return n.isEmpty ? id : n
    }

    static func jobName(_ j: OvAuftrag) -> String {
        var n = Menschlich.cleanName(j.displayName ?? j.name)
        n = n.replacingOccurrences(of: #"^Skill collection review.*$"#, with: "Skill-Review", options: [.regularExpression, .caseInsensitive])
        n = n.replacingOccurrences(of: "Telco-Radar · ", with: "", options: .anchored)
        n = n.replacingOccurrences(of: #"\s+—\s+täglicher Check$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return n.trimmingCharacters(in: .whitespaces)
    }

    static let kartenOrdnung = ["running": 0, "review": 1, "blocked": 2, "ready": 3, "todo": 4, "scheduled": 5, "triage": 6, "backlog": 7, "done": 8]

    struct Projekt: Equatable {
        enum Art { case ruhig, arbeitet, fehler }
        var id: String
        var name: String
        var kontext: String
        var karten: [OvKarte]
        var agent: String?
        var zustandText: String
        var zustandArt: Art
        var chatKey: String?
        var offen: Int
        var fertig: Int
    }

    static func istHauptschluessel(_ k: String) -> Bool { Muster.passt(k, #"^agent:[^:]+:main$"#) }

    static func projekte(_ ov: OvDaten, nurEchte: Bool = false) -> [Projekt] {
        let archiviert = Set(ov.boards.filter(\.archiviert).map(\.id))
        var ids: [String] = []
        for id in ov.boards.map(\.id) + ov.cards.map(\.boardId) where !archiviert.contains(id) && !ids.contains(id) { ids.append(id) }
        if nurEchte {
            ids = ids.filter { ov.pm.projekte[$0] != nil && ov.pm.projekte[$0]?.status != "archiviert" }
        }
        var liste: [Projekt] = []
        for id in ids {
            var karten = ov.cards.filter { $0.boardId == id }
            if id == "default" && karten.isEmpty { continue }
            let b = ov.boards.first { $0.id == id }
            let gereinigt = Menschlich.cleanName(b?.name)
            let (name, altKontext) = kurzNamen[id] ?? (gereinigt.isEmpty ? (id == "default" ? "Ohne Projekt" : id) : gereinigt, "")
            let kontext: String
            if let z = ov.pm.projekte[id] { kontext = ov.bereiche?.areas.first { $0.id == z.bereichId }?.name ?? "" } else { kontext = altKontext }
            let agent = b?.standardAgent
            let jobs = agent.map { a in ov.jobs.filter { $0.agent == a && $0.aktiv } } ?? []
            let takt = jobs.first { $0.art == "every" && ($0.everyMs ?? 0) > 0 && ($0.everyMs ?? 0) <= 3_600_000 }
            let sitzungen = agent.map { a in ov.rows.filter { $0.agentId == a } } ?? []
            let pausiert = sitzungen.contains { Muster.passt($0.derivedTitle ?? $0.label ?? "", "pausiert", gross: true) }
            let arbeitet = sitzungen.contains { $0.live } || karten.contains { $0.status == "running" }
            let fehl = jobs.contains { $0.lastRunStatus == "error" }
            var text = pausiert ? "pausiert" : "wartet auf Arbeit"
            var art = Projekt.Art.ruhig
            if let t = takt { text = "arbeitet alle \(Int(((t.everyMs ?? 0) / 60_000).rounded())) Min"; art = .arbeitet }
            if arbeitet { text = "arbeitet gerade"; art = .arbeitet }
            if fehl { text = ((takt != nil || arbeitet) ? text + ", " : "") + "zuletzt fehlgeschlagen"; art = .fehler }
            karten = karten.enumerated().sorted { a, c in
                let x = (kartenOrdnung[a.element.status] ?? 9, prio(a.element), a.offset), y = (kartenOrdnung[c.element.status] ?? 9, prio(c.element), c.offset)
                return x < y
            }.map(\.element)
            let benannt = sitzungen.first { istHauptschluessel($0.key) } ?? sitzungen.first
            liste.append(Projekt(id: id, name: name, kontext: kontext, karten: karten, agent: agent, zustandText: text, zustandArt: art,
                                 chatKey: agent.map { benannt?.key ?? "agent:\($0):main" },
                                 offen: karten.filter { $0.status != "done" }.count, fertig: karten.filter { $0.status == "done" }.count))
        }
        return liste.enumerated().sorted { ($1.element.karten.count, $0.offset) < ($0.element.karten.count, $1.offset) }.map(\.element)
    }

    enum Gesundheit: String { case gruen, gelb, rot, grau }

    static func istEntscheidung(_ c: OvKarte) -> Bool { c.labels.contains { $0 == "entscheidung" || $0.hasPrefix("entscheidung:") } }

    static func bereichDesProjekts(_ p: Projekt, _ ov: OvDaten) -> String {
        let bereiche = ov.bereiche?.areas ?? []
        if let saved = ov.pm.projekte[p.id] { return bereiche.contains { $0.id == saved.bereichId } ? saved.bereichId : "" }
        func key(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespaces) }
        return bereiche.first { key($0.id) == key(p.id) || key($0.name) == key(p.kontext) || key($0.id) == key(p.kontext) }?.id ?? ""
    }

    struct ProjektInfo: Equatable {
        var projekt: Projekt
        var bereichId: String
        var frist: Double?
        var health: Gesundheit
        var grund: String
        var naechster: OvKarte?
        var aufgaben: [OvKarte]
        var offenA: [OvKarte]
        var fertigA: [OvKarte]
        var pruefung: [OvKarte]
        var blockiert: [OvKarte]
        var letzteAktivitaet: Double
        var letzteErledigt: Double
        var bereich: Area? = nil
        var abteilung = ""
        var ziel = ""
        var wartet = PM.Wartet(wer: .niemand, text: "")
        var ents: [OvEntscheidung] = []
        var leiter: String? = nil
        var id: String { projekt.id }
        var name: String { projekt.name }
    }

    static func projektInfos(_ ov: OvDaten, _ ents: [OvEntscheidung], jetzt: Double, nurEchte: Bool = false) -> [ProjektInfo] {
        let heute = Menschlich.tagStart(jetzt)
        var out: [ProjektInfo] = []
        for p in projekte(ov, nurEchte: nurEchte) {
            let karten = p.karten.filter { !$0.archiviert }
            let aufgaben = karten.filter { !istEntscheidung($0) }
            let offenA = aufgaben.filter { $0.status != "done" }
            let fertigA = aufgaben.filter { $0.status == "done" }
            let pe = ents.filter { $0.boardId == p.id }
            let pruefung = offenA.filter { $0.status == "review" }
            let blockiert = offenA.filter { $0.status == "blocked" }
            let bereichId = bereichDesProjekts(p, ov)
            let frist: Double? = {
                if let f = ov.pm.projekte[p.id]?.faellig, f.isFinite { return f }
                return offenA.compactMap { Menschlich.fristVon($0.labels) }.min()
            }()
            let letzteAktivitaet = karten.map { $0.updatedAt ?? 0 }.max() ?? 0
            let letzteErledigt = fertigA.map { $0.completedAt ?? $0.updatedAt ?? 0 }.max() ?? 0
            func nachRang(_ liste: [OvKarte], mitStatus: Bool) -> [OvKarte] {
                liste.enumerated().sorted { a, b in
                    let x = (mitStatus ? (kartenOrdnung[a.element.status] ?? 9) : 0, prio(a.element), a.offset)
                    let y = (mitStatus ? (kartenOrdnung[b.element.status] ?? 9) : 0, prio(b.element), b.offset)
                    return x < y
                }.map(\.element)
            }
            let naechster = nachRang(offenA, mitStatus: true).first { $0.status != "backlog" } ?? nachRang(offenA, mitStatus: false).first

            var health = Gesundheit.gruen
            var grund = !offenA.isEmpty ? "Läuft nach Plan." : !fertigA.isEmpty ? "Alles erledigt." : "Noch keine Aufgaben."
            let alteE = pe.filter { !$0.ruhend && jetzt - $0.gestelltAm > 7 * Menschlich.tag }.sorted { $0.gestelltAm < $1.gestelltAm }
            let fristUeber = offenA.filter { (Menschlich.fristVon($0.labels) ?? .infinity) < heute }
            let offeneE = pe.filter { !$0.ruhend }.count
            if !blockiert.isEmpty {
                health = .rot
                grund = blockiert.count == 1 ? "Eine Aufgabe hängt fest: \(Menschlich.klartext(blockiert[0].title))." : "\(blockiert.count) Aufgaben hängen fest."
            } else if !fristUeber.isEmpty || (frist.map { $0 < heute } ?? false) {
                health = .rot
                grund = "Die Frist vom \(Menschlich.datumKurz(frist ?? Menschlich.fristVon(fristUeber[0].labels) ?? heute)) ist überschritten."
            } else if !alteE.isEmpty {
                health = .rot
                grund = alteE.count == 1 ? "Eine Entscheidung wartet \(Menschlich.seitText(alteE[0].gestelltAm, jetzt: jetzt))." : "\(alteE.count) Entscheidungen warten seit über einer Woche."
            } else if offeneE > 0 {
                health = .gelb
                grund = offeneE == 1 ? "Eine Entscheidung wartet auf dich." : "\(offeneE) Entscheidungen warten auf dich."
            } else if pruefung.contains(where: { jetzt - ($0.updatedAt ?? jetzt) > 2 * Menschlich.tag }) {
                health = .gelb
                grund = "Ein Ergebnis wartet seit über zwei Tagen auf deine Prüfung."
            } else if offenA.contains(where: { ["todo", "ready", "running", "review", "scheduled"].contains($0.status) }) && jetzt - letzteErledigt > 7 * Menschlich.tag && letzteErledigt > 0 {
                health = .gelb
                grund = "Seit \(Menschlich.tageZwischen(letzteErledigt, jetzt)) Tagen wurde nichts erledigt."
            } else if !karten.isEmpty && jetzt - letzteAktivitaet > 14 * Menschlich.tag {
                health = .grau
                grund = "Seit \(Int((Double(Menschlich.tageZwischen(letzteAktivitaet, jetzt)) / 7).rounded())) Wochen keine Aktivität."
            } else if karten.isEmpty || (offenA.isEmpty && pe.isEmpty) {
                health = .grau
                grund = karten.isEmpty ? "Noch keine Aufgaben." : "Alles erledigt, nichts mehr offen."
            }
            let bereich = bereichId.isEmpty ? nil : ov.bereiche?.areas.first { $0.id == bereichId }
            let leiter = bereich?.leader ?? p.agent
            let leiterName = bereich?.leaderName ?? leiter.map { ov.label($0) }
            var pp = p
            if !ov.agents.isEmpty, let a = p.agent, ov.agent(a) == nil { pp.agent = bereich?.leader }
            if let b = bereich { pp.kontext = b.name }
            let meta = ov.pm.projekte[p.id]
            out.append(ProjektInfo(projekt: pp, bereichId: bereichId, frist: frist, health: health, grund: grund, naechster: naechster, aufgaben: aufgaben,
                                   offenA: offenA, fertigA: fertigA, pruefung: pruefung, blockiert: blockiert,
                                   letzteAktivitaet: letzteAktivitaet, letzteErledigt: letzteErledigt,
                                   bereich: bereich, abteilung: meta?.abteilung ?? "", ziel: meta?.ziel ?? "",
                                   wartet: PM.wartetAuf(ents: pe, pruefung: pruefung, blockiert: blockiert, naechster: naechster, leiterName: leiterName),
                                   ents: pe, leiter: leiter))
        }
        return out
    }

    struct Lauf: Equatable {
        enum Zustand: Equatable { case ok, fehler, geplant, verpasst }
        var job: OvAuftrag
        var at: Double
        var min: Int
        var zustand: Zustand
    }

    static func laeufeHeute(_ jobs: [OvAuftrag], jetzt: Double) -> (laeufe: [Lauf], takt: [OvAuftrag]) {
        let t0 = Menschlich.tagStart(jetzt), t1 = Menschlich.addTage(t0, 1)
        var laeufe: [Lauf] = []
        var takt: [OvAuftrag] = []
        for j in jobs {
            if !j.aktiv || j.agent.isEmpty { continue }
            if j.art == "every", let e = j.everyMs, e > 0, e <= 3_600_000 { takt.append(j); continue }
            var zeiten: [Double] = []
            func add(_ t: Double) { if !zeiten.contains(t) { zeiten.append(t) } }
            if j.art == "every", let e = j.everyMs, e > 0, var t = j.anchorMs {
                if t < t0 { t += ((t0 - t) / e).rounded(.up) * e }
                while t < t1 { add(t); t += e }
            }
            let last = j.lastRunAtMs, next = j.nextRunAtMs
            if let l = last, l >= t0, l < t1 { add(l) }
            if let n = next, n >= t0, n < t1 { add(n) }
            var minuten: [Int] = []
            var proMinute: [Int: Double] = [:]
            for t in zeiten { let m = Menschlich.minuteDesTages(t); if proMinute[m] == nil { minuten.append(m) }; proMinute[m] = t }
            for m in minuten {
                let at = proMinute[m]!
                let vorbei = at <= jetzt
                let gelaufen = abs((last ?? 0) - at) < 30 * 60_000
                let z: Lauf.Zustand = !vorbei ? .geplant : !gelaufen ? .verpasst : (j.lastRunStatus == "error" ? .fehler : .ok)
                laeufe.append(Lauf(job: j, at: at, min: m, zustand: z))
            }
        }
        laeufe = laeufe.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        return (laeufe, takt)
    }

    struct LaufEin: Equatable {
        var id: String
        var at: Double
        var zustand: Lauf.Zustand
        var name: String
        var wer: String
    }

    static func laeufeFuerTag(_ ov: OvDaten, tag0: Double, jetzt: Double) -> [LaufEin] {
        if Menschlich.addTage(tag0, 1) <= jetzt { return [] }
        let heute = jetzt >= tag0
        return laeufeHeute(ov.jobs, jetzt: heute ? jetzt : tag0 + 12 * 3_600_000).laeufe.map {
            let wer = ov.label($0.job.agent)
            return LaufEin(id: $0.job.id, at: $0.at, zustand: heute ? $0.zustand : .geplant, name: jobName($0.job), wer: wer.isEmpty ? "Team" : wer)
        }
    }

    struct TodoEin: Equatable { var id: String; var titel: String; var min: Int; var bis: Int?; var hinweis: String? }

    struct Zeile: Equatable, Identifiable {
        enum Art: Int { case ganztags = 0, termin, lauf, todo }
        var key: String
        var von: Int
        var bis: Int?
        var titel: String
        var unter: String?
        var art: Art
        var zustand: Lauf.Zustand?
        var vorbei: Bool
        var laeuft: Bool
        var laufIds: [String] = []
        var id: String { key }
    }

    private static func minVon(_ ms: Double, _ tag0: Double) -> Int { Int(((ms - tag0) / 60_000).rounded()) }

    static func istGanztags(_ t: OvTermin) -> Bool {
        if t.ganztags { return true }
        let m = Menschlich.minuteDesTages(t.start)
        let dauer = t.ende - t.start
        if dauer >= Menschlich.tag - 60_000 && m == 0 { return true }
        if dauer <= 0 && (m == 0 || m == 60) { return true }
        return false
    }

    static func tagesZeilen(tag0: Double, jetzt: Double, termine: [OvTermin], laeufe: [LaufEin] = [], todos: [TodoEin] = []) -> [Zeile] {
        let tag1 = Menschlich.addTage(tag0, 1)
        let heute = jetzt >= tag0 && jetzt < tag1
        var out: [Zeile] = []
        var gesehen = Set<String>()
        var ganztags: [(String, OvTermin)] = [], zeitlich: [(String, OvTermin)] = []
        for t in termine {
            let gz = istGanztags(t)
            let ende = gz ? max(t.ende, t.start + Menschlich.tag * 0.5) : t.ende
            if !(ende > tag0 && t.start < tag1) && !(gz && t.start >= tag0 && t.start < tag1) { continue }
            let titel = t.titel.trimmingCharacters(in: .whitespaces)
            let key = "\(titel.lowercased())|\(gz ? "g" : String(Int(t.start)))|\(gz ? "" : String(Int(t.ende)))"
            if !gesehen.insert(key).inserted { continue }
            if gz { ganztags.append((key, t)) } else { zeitlich.append((key, t)) }
        }
        zeitlich = zeitlich.enumerated().sorted { a, b in
            if a.element.1.start != b.element.1.start { return a.element.1.start < b.element.1.start }
            if a.element.1.ende != b.element.1.ende { return a.element.1.ende > b.element.1.ende }
            return a.offset < b.offset
        }.map(\.element)
        func titelVon(_ t: OvTermin) -> String { t.titel.trimmingCharacters(in: .whitespaces).isEmpty ? "Termin" : t.titel.trimmingCharacters(in: .whitespaces) }
        for (key, e) in ganztags { out.append(Zeile(key: "g" + key, von: -1, titel: titelVon(e), unter: e.kalender, art: .ganztags, vorbei: false, laeuft: false)) }
        for (key, e) in zeitlich {
            let von = max(0, minVon(e.start, tag0))
            let bis = minVon(min(max(e.ende, e.start), tag1), tag0)
            let unter = [e.kalender, e.ort].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(Zeile(key: "t" + key, von: von, bis: bis > von ? bis : nil, titel: titelVon(e), unter: unter.isEmpty ? nil : unter, art: .termin,
                             vorbei: heute && max(e.ende, e.start) < jetzt, laeuft: heute && e.start <= jetzt && max(e.ende, e.start) >= jetzt))
        }
        var minuten: [Int] = []
        var gruppen: [Int: [LaufEin]] = [:]
        for l in laeufe { let m = minVon(l.at, tag0); if gruppen[m] == nil { minuten.append(m) }; gruppen[m, default: []].append(l) }
        func einmalig(_ l: [String]) -> [String] {
            var s: [String] = []
            for x in l.map({ $0.trimmingCharacters(in: .whitespaces) }) where !x.isEmpty && !s.contains(x) { s.append(x) }
            return s
        }
        for m in minuten {
            let g = gruppen[m]!
            let wer = einmalig(g.map(\.wer))
            let z: Lauf.Zustand = g.contains { $0.zustand == .fehler } ? .fehler : g.allSatisfy { $0.zustand == .geplant } ? .geplant : g.allSatisfy { $0.zustand == .verpasst } ? .verpasst : .ok
            out.append(Zeile(key: "l\(m)\(g[0].id)", von: m, titel: g.count == 1 ? g[0].name : "\(g.count) Läufe",
                             unter: g.count == 1 ? wer.first : wer.joined(separator: ", "), art: .lauf, zustand: z,
                             vorbei: heute && (g.map(\.at).max() ?? 0) < jetzt, laeuft: false, laufIds: g.map(\.id)))
        }
        for t in todos {
            out.append(Zeile(key: "d" + t.id, von: t.min, bis: t.bis, titel: t.titel, unter: ["To-do", t.hinweis].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                             art: .todo, vorbei: false, laeuft: false))
        }
        return out.enumerated().sorted { a, b in
            if a.element.von != b.element.von { return a.element.von < b.element.von }
            if a.element.art != b.element.art { return a.element.art.rawValue < b.element.art.rawValue }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func zeitText(_ z: Zeile) -> String {
        if z.von < 0 { return "ganztags" }
        func h(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }
        if let b = z.bis, b > z.von { return "\(h(z.von)) – \(h(b))" }
        return h(z.von)
    }

    struct Bisher: Equatable {
        var termine: Int
        var laeufe: Int
        var fehler: Int
        var text: String {
            var teile: [String] = []
            if termine > 0 { teile.append("\(termine) \(termine == 1 ? "Termin" : "Termine")") }
            if laeufe > 0 { teile.append("\(laeufe) \(laeufe == 1 ? "Lauf" : "Läufe")" + (fehler > 0 ? ", davon \(fehler) fehlgeschlagen" : "")) }
            return teile.isEmpty ? "noch nichts" : teile.joined(separator: ", ")
        }
    }

    static func bisherHeute(zeilen: [Zeile], laeufe: [LaufEin], jetzt: Double) -> Bisher {
        let gelaufen = laeufe.filter { $0.at < jetzt && ($0.zustand == .ok || $0.zustand == .fehler) }
        return Bisher(termine: zeilen.filter { $0.art == .termin && $0.vorbei }.count, laeufe: gelaufen.count, fehler: gelaufen.filter { $0.zustand == .fehler }.count)
    }
}
