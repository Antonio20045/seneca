import Foundation

enum AufgabenLogic {
    static let tageZurueck = 7
    static let tageVor = 35

    static func tag(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespaces), s.count == 10 else { return nil }
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        return back.year == y && back.month == m && back.day == d ? s : nil
    }

    static func datum(_ tag: String?, _ cal: Calendar = .current) -> Date? {
        guard let tag = self.tag(tag) else { return nil }
        let p = tag.split(separator: "-").compactMap { Int($0) }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func labelTag(_ labels: [String]?, _ prefix: String) -> String? {
        for label in labels ?? [] where label.hasPrefix(prefix + ":") {
            if let t = tag(String(label.dropFirst(prefix.count + 1))) { return t }
        }
        return nil
    }

#if os(iOS)
    static func fenster(jetzt: Date, _ cal: Calendar = .current) -> (von: String, bis: String) {
        let start = cal.startOfDay(for: jetzt)
        return (DayLogic.dayKey(cal.date(byAdding: .day, value: -tageZurueck, to: start)!, cal),
                DayLogic.dayKey(cal.date(byAdding: .day, value: tageVor, to: start)!, cal))
    }
#else
    static func fenster(jetzt: Date, _ cal: Calendar = .current) -> (von: String, bis: String) {
        let start = cal.startOfDay(for: jetzt)
        return (DayLogic.dayKey(cal.date(byAdding: .day, value: -tageZurueck, to: start)!, cal),
                DayLogic.dayKey(cal.date(byAdding: .day, value: tageVor, to: start)!, cal))
    }

    static func heutigeKartenTodos(_ cards: [WorkCard], heute: String) -> [WorkCard] {
        cards.filter { c in
            let privat = c.boardId == "privat" || (c.agentId ?? "").isEmpty
            guard privat, c.status != "done", !TodoEdits.isParked(c.title) else { return false }
            guard !(c.labels ?? []).contains(where: { $0.hasPrefix("entscheidung") }) else { return false }
            guard let plan = labelTag(c.labels, "plan") else { return false }
            return plan <= heute
        }.sorted { a, b in
            let pa = labelTag(a.labels, "plan") ?? "", pb = labelTag(b.labels, "plan") ?? ""
            let ueberA = pa < heute, ueberB = pb < heute
            if ueberA != ueberB { return ueberA }
            let prioA = DayLogic.priorityRank[a.priority ?? "normal"] ?? 2, prioB = DayLogic.priorityRank[b.priority ?? "normal"] ?? 2
            if prioA != prioB { return prioA < prioB }
            if pa != pb { return pa < pb }
            return TodoEdits.display(a.title).localizedCaseInsensitiveCompare(TodoEdits.display(b.title)) == .orderedAscending
        }
    }

    static func seitText(plan: String?, heute: String, _ cal: Calendar = .current) -> String? {
        guard let p = datum(plan, cal), let h = datum(heute, cal), p < h else { return nil }
        let tage = cal.dateComponents([.day], from: p, to: h).day ?? 0
        if tage == 1 { return "von gestern" }
        if tage < 7 { return "seit " + ["So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa."][cal.component(.weekday, from: p) - 1] }
        return "seit \(cal.component(.day, from: p)).\(cal.component(.month, from: p))."
    }
#endif

    static func wichtiger(_ a: SenecaTask, _ b: SenecaTask) -> Bool {
        let pa = DayLogic.priorityRank[a.priority ?? "normal"] ?? 2, pb = DayLogic.priorityRank[b.priority ?? "normal"] ?? 2
        if pa != pb { return pa < pb }
        if a.frist != b.frist { return (a.frist ?? "9999") < (b.frist ?? "9999") }
        if a.projektFaellig != b.projektFaellig { return (a.projektFaellig ?? "9999") < (b.projektFaellig ?? "9999") }
        let order = a.title.localizedCaseInsensitiveCompare(b.title)
        return order != .orderedSame ? order == .orderedAscending : a.id < b.id
    }

    static func zurueckgestellt(_ t: SenecaTask) -> Bool { t.isParked || t.status == "backlog" }

    static func privatOhnePlan(_ t: SenecaTask) -> Bool {
        guard t.plan == nil else { return false }
        return t.projektId == nil || t.projektId == "privat" || t.projektId == "default"
    }

    static func gehoertZuHeute(_ t: SenecaTask, heute: String) -> Bool {
        if zurueckgestellt(t) { return false }
        if let plan = t.plan { return plan <= heute }
        return privatOhnePlan(t)
    }

    static func heutigeAufgaben(_ tasks: [SenecaTask], jetzt: Date, _ cal: Calendar = .current) -> [SenecaTask] {
        let start = cal.startOfDay(for: jetzt)
        let t0 = start.timeIntervalSince1970 * 1000
        let heute = DayLogic.dayKey(start, cal)
        return tasks.filter { t in
            guard gehoertZuHeute(t, heute: heute) else { return false }
            return !t.isDone || (t.completedAt ?? t.updatedAt ?? 0) >= t0
        }.sorted(by: wichtiger)
    }

    static func topDrei(_ tasks: [SenecaTask], jetzt: Date, _ cal: Calendar = .current) -> [SenecaTask] {
        Array(heutigeAufgaben(tasks, jetzt: jetzt, cal).prefix(3))
    }

    static func aufgaben(_ tasks: [SenecaTask], fuerTag tag: Date, jetzt: Date, _ cal: Calendar = .current) -> [SenecaTask] {
        let key = DayLogic.dayKey(tag, cal), heute = DayLogic.dayKey(jetzt, cal)
        var out: [SenecaTask] = key == heute ? heutigeAufgaben(tasks, jetzt: jetzt, cal) : []
        let have = Set(out.map(\.id))
        out += tasks.filter { t in
            t.plan == key && !zurueckgestellt(t) && !have.contains(t.id) && (key >= heute || t.isDone)
        }
        return out.sorted(by: wichtiger)
    }

    enum Abschnitt: String, CaseIterable, Sendable {
        case heute, morgen, dieseWoche, spaeter, ohneTag
        var titel: String {
            switch self {
            case .heute: return "Heute"
            case .morgen: return "Morgen"
            case .dieseWoche: return "Diese Woche"
            case .spaeter: return "Später"
            case .ohneTag: return "Ohne Tag"
            }
        }
    }

    struct AbschnittListe: Equatable, Sendable {
        var abschnitt: Abschnitt
        var aufgaben: [SenecaTask]
    }

    static func abschnitte(_ tasks: [SenecaTask], jetzt: Date, behalten: Set<String> = [], _ cal: Calendar = .current) -> [AbschnittListe] {
        let start = cal.startOfDay(for: jetzt)
        let heute = DayLogic.dayKey(start, cal)
        let morgen = DayLogic.dayKey(cal.date(byAdding: .day, value: 1, to: start)!, cal)
        let bisSonntag = (8 - cal.component(.weekday, from: start)) % 7
        let wochenEnde = DayLogic.dayKey(cal.date(byAdding: .day, value: bisSonntag + 1, to: start)!, cal)
        func zeigen(_ t: SenecaTask) -> Bool { !t.isDone || behalten.contains(t.id) }
        func nachTagDann(_ a: SenecaTask, _ b: SenecaTask) -> Bool {
            if a.plan != b.plan { return (a.plan ?? "") < (b.plan ?? "") }
            return wichtiger(a, b)
        }
        let zuHeute = heutigeAufgaben(tasks, jetzt: jetzt, cal).filter(zeigen)
        let dabei = Set(zuHeute.map(\.id))
        let rest = tasks.filter { zeigen($0) && !dabei.contains($0.id) }
        var morgenListe: [SenecaTask] = [], woche: [SenecaTask] = [], spaeter: [SenecaTask] = [], geparkt: [SenecaTask] = [], ohne: [SenecaTask] = []
        for t in rest {
            if t.isParked { geparkt.append(t); continue }
            guard let plan = t.plan, plan > heute else { ohne.append(t); continue }
            if plan == morgen { morgenListe.append(t) } else if plan < wochenEnde { woche.append(t) } else { spaeter.append(t) }
        }
        let alle: [AbschnittListe] = [
            AbschnittListe(abschnitt: .heute, aufgaben: zuHeute),
            AbschnittListe(abschnitt: .morgen, aufgaben: morgenListe.sorted(by: wichtiger)),
            AbschnittListe(abschnitt: .dieseWoche, aufgaben: woche.sorted(by: nachTagDann)),
            AbschnittListe(abschnitt: .spaeter, aufgaben: spaeter.sorted(by: nachTagDann) + geparkt.sorted(by: wichtiger)),
            AbschnittListe(abschnitt: .ohneTag, aufgaben: ohne.sorted(by: wichtiger)),
        ]
        guard alle.contains(where: { !$0.aufgaben.isEmpty }) else { return [] }
        return alle.filter { $0.abschnitt == .heute || !$0.aufgaben.isEmpty }
    }

    static func anzeigeTitel(_ titel: String) -> String {
        let bereinigt = titel.replacingOccurrences(of: #"\s*\([A-Z]{1,2}-\d+[a-z]*\)\s*$"#, with: "", options: .regularExpression)
        return bereinigt.isEmpty ? titel : bereinigt
    }

    static func kurzTag(_ tag: String?, jetzt: Date, mitDatum: Bool = true, _ cal: Calendar = .current) -> String? {
        guard let d = datum(tag, cal) else { return nil }
        let wochentage = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let monate = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]
        let wt = wochentage[cal.component(.weekday, from: d) - 1]
        guard mitDatum else { return wt }
        let tagZahl = cal.component(.day, from: d)
        if cal.component(.month, from: d) == cal.component(.month, from: jetzt) && cal.component(.year, from: d) == cal.component(.year, from: jetzt) {
            return "\(wt) \(tagZahl)."
        }
        return "\(wt) \(tagZahl). \(monate[cal.component(.month, from: d) - 1])"
    }

    static func nebenzeile(_ t: SenecaTask, abschnitt: Abschnitt, jetzt: Date, _ cal: Calendar = .current) -> String? {
        var teile: [String] = []
        if t.priority == "urgent" { teile.append("dringend") }
        if abschnitt == .dieseWoche, let tag = kurzTag(t.plan, jetzt: jetzt, mitDatum: false, cal) { teile.append(tag) }
        if abschnitt == .spaeter, !t.isParked, let tag = kurzTag(t.plan, jetzt: jetzt, cal) { teile.append(tag) }
        teile += ortTeile(bereich: t.bereichName, projekt: t.projektName)
        if let frist = t.frist, frist != t.plan, let tag = kurzTag(frist, jetzt: jetzt, cal) { teile.append("bis \(tag)") }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    static func ortTeile(bereich: String?, projekt: String?) -> [String] {
        let bereich = bereich?.trimmingCharacters(in: .whitespaces).nilWennLeer
        let projekt = projekt?.trimmingCharacters(in: .whitespaces).nilWennLeer
        var teile: [String] = []
        if let bereich {
            teile.append(bereich)
            if let projekt {
                if let rest = projektNachBereich(projekt, bereich) { if !rest.isEmpty { teile.append(rest) } } else { teile.append(projekt) }
            }
        } else if let projekt { teile.append(projekt) }
        return teile
    }

    static func projektNachBereich(_ projekt: String, _ bereich: String) -> String? {
        guard let r = projekt.range(of: bereich, options: [.anchored, .caseInsensitive]) else { return nil }
        let rest = projekt[r.upperBound...]
        if let erstes = rest.first, erstes.isLetter || erstes.isNumber { return nil }
        let trenner = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:-–—·/"))
        return String(rest).trimmingCharacters(in: trenner)
    }

    enum Gewicht { case wichtig, normal, niedrig }
    static func gewicht(_ t: SenecaTask) -> Gewicht {
        switch t.priority {
        case "urgent", "high": return .wichtig
        case "low": return .niedrig
        default: return .normal
        }
    }

    static func angereichert(_ tasks: [SenecaTask], plugin: [SenecaTask]?, projects: [String: String]?, due: [String: String]?,
                             areas: [Area]?) -> [SenecaTask] {
        var out = tasks
        var index: [String: Int] = [:]
        for (i, t) in out.enumerated() where index[t.id] == nil { index[t.id] = i }
        for p in plugin ?? [] {
            guard let i = index[p.id] else { index[p.id] = out.count; out.append(p); continue }
            out[i].projektId = p.projektId ?? out[i].projektId
            out[i].projektName = p.projektName ?? out[i].projektName
            out[i].bereichId = p.bereichId ?? out[i].bereichId
            out[i].bereichName = p.bereichName ?? out[i].bereichName
            out[i].plan = p.plan ?? out[i].plan
            out[i].frist = p.frist ?? out[i].frist
            out[i].projektFaellig = p.projektFaellig ?? out[i].projektFaellig
        }
        let list = areas ?? []
        for i in out.indices {
            guard let board = out[i].projektId else { continue }
            if out[i].bereichId == nil {
                out[i].bereichId = AreasLogic.area(of: WorkCard(id: out[i].id, title: out[i].title, status: out[i].status, boardId: board),
                                                   in: list, projects: projects ?? [:])
            }
            if out[i].bereichName == nil, let id = out[i].bereichId { out[i].bereichName = list.first(where: { $0.id == id })?.name }
            if out[i].projektFaellig == nil { out[i].projektFaellig = due?[board] }
        }
        return out
    }
}

extension SenecaPayloadParser {
    static func aufgaben(_ result: [String: Any]) -> [SenecaTask]? {
        guard result["ok"] as? Bool != false, let list = result["aufgaben"] as? [[String: Any]] else { return nil }
        func text(_ v: Any?) -> String? { (v as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
        func ms(_ v: Any?) -> Double? { v is NSNull ? nil : SenecaPayloadParser.date(v).map { $0.timeIntervalSince1970 * 1000 } }
        var projects: [String: [String: Any]] = [:]
        for p in result["projekte"] as? [[String: Any]] ?? [] { if let id = text(p["id"]) { projects[id] = p } }
        return list.compactMap { a in
            guard let id = text(a["id"]), let raw = text(a["titel"]) ?? text(a["title"]) else { return nil }
            if let wer = text(a["wer"]), wer != "antonio" { return nil }
            let project = text(a["projektId"]).flatMap { projects[$0] }
            let status = text(a["status"]) ?? "todo"
            return SenecaTask(
                id: id, title: TodoEdits.display(raw), isDone: ["done", "completed"].contains(status), status: status,
                updatedAt: ms(a["geaendert"]), notes: text(a["notizen"]), isParked: TodoEdits.isParked(raw),
                completedAt: ms(a["erledigtAm"]), priority: text(a["prioritaet"]), rawTitle: raw,
                projektId: text(a["projektId"]),
                projektName: text(a["projektName"]) ?? text(project?["name"]),
                bereichId: text(a["bereichId"]) ?? text(project?["bereichId"]),
                bereichName: text(a["bereichName"]),
                plan: AufgabenLogic.tag(a["plan"]), frist: AufgabenLogic.tag(a["frist"]),
                projektFaellig: AufgabenLogic.tag(project?["faellig"]))
        }
    }

    static func projectDue(_ result: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (board, value) in result["projekte"] as? [String: Any] ?? [:] {
            if let due = AufgabenLogic.tag((value as? [String: Any])?["faellig"]) { out[board] = due }
        }
        return out
    }
}

#if os(iOS)
extension SenecaStore {
    var aufgaben: [SenecaTask] { today?.tasks ?? [] }

    func heutigeAufgaben(jetzt: Date? = nil, _ cal: Calendar = .current) -> [SenecaTask] {
        AufgabenLogic.heutigeAufgaben(aufgaben, jetzt: jetzt ?? clock(), cal)
    }

    func topDrei(jetzt: Date? = nil, _ cal: Calendar = .current) -> [SenecaTask] {
        AufgabenLogic.topDrei(aufgaben, jetzt: jetzt ?? clock(), cal)
    }

    func aufgaben(fuerTag tag: Date, jetzt: Date? = nil, _ cal: Calendar = .current) -> [SenecaTask] {
        AufgabenLogic.aufgaben(aufgaben, fuerTag: tag, jetzt: jetzt ?? clock(), cal)
    }

    func aendereAufgabe(_ id: String, _ aenderung: AufgabenAenderung) async throws {
        guard var snap = today, let i = snap.tasks.firstIndex(where: { $0.id == id }) else { return }
        var params: [String: Any] = ["id": id]
        switch aenderung {
        case .plan(let tag):
            snap.tasks[i].plan = tag
            params["plan"] = tag ?? NSNull()
        case .frist(let tag):
            snap.tasks[i].frist = tag
            params["frist"] = tag ?? NSNull()
        case .prioritaet(let p):
            snap.tasks[i].priority = p
            params["prioritaet"] = p
        }
        today = snap
        guard !demo, !id.hasPrefix("local-") else { return }
        _ = try await rufe("seneca.aufgaben.planen", params: params, timeout: 15)
        await loadToday()
    }
}

enum AufgabenAenderung: Equatable, Sendable {
    case plan(String?)
    case frist(String?)
    case prioritaet(String)
}
#else
extension SenecaStore {
    var aufgaben: [SenecaTask] { today?.tasks ?? [] }

    func heutigeAufgaben(jetzt: Date? = nil, _ cal: Calendar = .current) -> [SenecaTask] {
        AufgabenLogic.heutigeAufgaben(aufgaben, jetzt: jetzt ?? clock(), cal)
    }

    func topDrei(jetzt: Date? = nil, _ cal: Calendar = .current) -> [SenecaTask] {
        AufgabenLogic.topDrei(aufgaben, jetzt: jetzt ?? clock(), cal)
    }

    func aufgaben(fuerTag tag: Date, jetzt: Date? = nil, _ cal: Calendar = .current) -> [SenecaTask] {
        AufgabenLogic.aufgaben(aufgaben, fuerTag: tag, jetzt: jetzt ?? clock(), cal)
    }
}
#endif

#if DEBUG
extension AufgabenLogic {
    static func demo(now: Date, _ cal: Calendar = .current) -> (tasks: [SenecaTask], projects: [String: String], due: [String: String]) {
        let day = cal.startOfDay(for: now)
        func tag(_ offset: Int) -> String { DayLogic.dayKey(cal.date(byAdding: .day, value: offset, to: day)!, cal) }
        let areas: [String: String] = ["vodafone": "Vodafone", "sundartha": "Sundartha"]
        let boards: [String: (name: String, area: String?, due: Int?)] = [
            "powerbi": ("Power-BI-Reportings für alle Services", "vodafone", 25),
            "telco-radar": ("Telco-Radar", "vodafone", 18),
            "vodafone": ("Vodafone, Sonstiges", "vodafone", nil),
            "hermes": ("Hermes", "sundartha", 19),
            "firma-ug": ("Firma und UG", "sundartha", 49),
            "privat": ("Privat", nil, nil),
        ]
        let stamp = now.timeIntervalSince1970 * 1000
        var n = 0
        func task(_ id: String, _ title: String, _ board: String, _ priority: String, plan: Int? = nil, frist: Int? = nil,
                  done: Bool = false, completed: Date? = nil) -> SenecaTask {
            n += 1
            let b = boards[board]!
            return SenecaTask(id: id, title: title, isDone: done, status: done ? "done" : "todo",
                              updatedAt: stamp - Double(n) * 3_600_000, completedAt: completed.map { $0.timeIntervalSince1970 * 1000 },
                              priority: priority,
                              projektId: board, projektName: b.name, bereichId: b.area, bereichName: b.area.flatMap { areas[$0] },
                              plan: plan.map(tag), frist: frist.map(tag), projektFaellig: b.due.map(tag))
        }
        let yesterdayEvening = cal.date(byAdding: .minute, value: 20 * 60 + 15, to: cal.date(byAdding: .day, value: -1, to: day)!)!
#if os(iOS)
        let tasks: [SenecaTask] = [
            task("a-v5", "Einmal in Power BI anmelden (V-5)", "powerbi", "high", plan: 0),
            task("a-e7", "Instagram: anfangen oder sein lassen? (E-7)", "hermes", "high", plan: 0),
            task("a-m1s", "Kleinunternehmerstatus mit dem Steuerberater klären (M-1s)", "firma-ug", "high", plan: 0),
            task("hook", "Webhook-Kette prüfen", "vodafone", "low", plan: -2),
            task("a-t1", "Geräte-Überarbeitung (TCO, Telekom, Historie) ansehen und freigeben", "telco-radar", "high", plan: 1),
            task("a-e6", "Wie kommen wir an die Discord-Gespräche von CALL-E? (E-6)", "hermes", "normal", plan: 1),
            task("a-p2", "Liste aller Services und ihrer Reportings durchsehen und freigeben", "powerbi", "normal", plan: 2),
            task("a-e8", "Speicherung bei ElevenLabs: Datenminimierung halten oder ändern? (E-8)", "hermes", "normal", plan: 2),
            task("a-mailand", "Mailand 19.–22.10.: Unterkunft buchen", "privat", "normal", plan: 2, frist: 4),
            task("a-t2", "Deine To-dos für den Mitarbeiter einsammeln", "telco-radar", "normal", plan: 3),
            task("a-steuer", "Steuererklärung abgeben", "privat", "normal", plan: 3),
            task("a-p3", "Mit dem Mitarbeiter den ersten Service (STONE) für die OneNumber-Vorlage festlegen", "powerbi", "normal", plan: 4, frist: 8),
            task("a-v1", "Die 13 Bauversuche in „Mein Arbeitsbereich“ löschen (V-1)", "vodafone", "low", plan: 5),
            task("a-t3", "Entscheiden, ob die automatische Marktrecherche-Seite kommt", "telco-radar", "low", plan: 7),
            task("a-abnahmen", "Die vier offenen Abnahmen prüfen (P-32, P-3, P-2b, P-28)", "powerbi", "normal", plan: 10),
            task("a-e10", "Rechtstexte vervollständigen, sobald die UG eingetragen ist (E-10)", "firma-ug", "low"),
            task("a-routine", "Wochenroutine: 2× Krafttraining, 2× Joggen, abends lesen", "privat", "low", plan: -1, done: true, completed: yesterdayEvening),
        ] + vorgaben().filter { $0.id != "hook" }
#else
        let tasks: [SenecaTask] = [
            task("a-v5", "Einmal in Power BI anmelden (V-5)", "powerbi", "high", plan: 0),
            task("a-e7", "Instagram: anfangen oder sein lassen? (E-7)", "hermes", "high", plan: 0),
            task("a-m1s", "Kleinunternehmerstatus mit Jonas klären (M-1s)", "firma-ug", "high", plan: 0),
            task("hook", "Webhook-Kette prüfen", "vodafone", "low", plan: -2),
            task("a-t1", "Geräte-Überarbeitung (TCO, Telekom, Historie) ansehen und freigeben", "telco-radar", "high", plan: 1),
            task("a-e6", "Wie kommen wir an die Discord-Gespräche von CALL-E? (E-6)", "hermes", "normal", plan: 1),
            task("a-p2", "Liste aller Services und ihrer Reportings durchsehen und freigeben", "powerbi", "normal", plan: 2),
            task("a-e8", "Speicherung bei ElevenLabs: Datenminimierung halten oder ändern? (E-8)", "hermes", "normal", plan: 2),
            task("a-mailand", "Mailand 19.–22.10.: Unterkunft buchen", "privat", "normal", plan: 2, frist: 4),
            task("a-t2", "Deine To-dos für Seneca einsammeln", "telco-radar", "normal", plan: 3),
            task("a-steuer", "Steuererklärung abgeben", "privat", "normal", plan: 3),
            task("a-p3", "Mit Seneca den ersten Service (STONE) für die OneNumber-Vorlage festlegen", "powerbi", "normal", plan: 4, frist: 8),
            task("a-v1", "Die 13 Bauversuche in „Mein Arbeitsbereich“ löschen (V-1)", "vodafone", "low", plan: 5),
            task("a-t3", "Entscheiden, ob die automatische Marktrecherche-Seite kommt", "telco-radar", "low", plan: 7),
            task("a-abnahmen", "Die vier offenen Abnahmen prüfen (P-32, P-3, P-2b, P-28)", "powerbi", "normal", plan: 10),
            task("a-e10", "Rechtstexte vervollständigen, sobald die UG eingetragen ist (E-10)", "firma-ug", "low"),
            task("a-routine", "Wochenroutine: 2× Krafttraining, 2× Joggen, abends lesen", "privat", "low", plan: -1, done: true, completed: yesterdayEvening),
        ] + vorgaben().filter { $0.id != "hook" }
#endif
        var projects: [String: String] = [:], due: [String: String] = [:]
        for (board, b) in boards {
            if let area = b.area, board != area { projects[board] = area }
            if let days = b.due { due[board] = tag(days) }
        }
        return (tasks, projects, due)
    }

    static func vorgaben() -> [SenecaTask] {
        [("db", "Datenbankzugang schließen"), ("num", "Rufnummern-Prüfung aktivieren"), ("hook", "Webhook-Kette prüfen")].map {
            SenecaTask(id: $0.0, title: $0.1, isDone: false, projektId: "privat", projektName: "Privat")
        }
    }
}
#endif

private extension String {
    var nilWennLeer: String? { isEmpty ? nil : self }
}

enum NeueAufgabeLogik {
    enum TagWahl: String, CaseIterable, Sendable { case heute, morgen, datum, ohne }

    static func plan(_ wahl: TagWahl, datum: Date, jetzt: Date, _ cal: Calendar = .current) -> String? {
        let start = cal.startOfDay(for: jetzt)
        switch wahl {
        case .heute: return DayLogic.dayKey(start, cal)
        case .morgen: return DayLogic.dayKey(cal.date(byAdding: .day, value: 1, to: start)!, cal)
        case .datum: return DayLogic.dayKey(datum, cal)
        case .ohne: return nil
        }
    }

    static func frist(_ datum: Date?, _ cal: Calendar = .current) -> String? { datum.map { DayLogic.dayKey($0, cal) } }

    struct Projekt: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
    }
    struct Gruppe: Identifiable, Equatable, Sendable {
        var bereichId: String?
        var bereichName: String?
        var projekte: [Projekt]
        var id: String { bereichId ?? "-" }
    }
    struct Ziel: Equatable, Sendable {
        var board: String
        var projektName: String?
        var bereichId: String?
        var bereichName: String?
    }

    static func gruppen(boardNames: [String: String]?, projects: [String: String]?, areas: [Area]?, cards: [WorkCard]?,
                        tasks: [SenecaTask]) -> [Gruppe] {
        var ids = Set(projects?.keys.map { $0 } ?? [])
        ids.formUnion(cards?.map(\.boardId) ?? [])
        ids.formUnion(tasks.compactMap(\.projektId))
        ids.formUnion(boardNames?.keys.map { $0 } ?? [])
        ids.subtract(["privat", "default", ""])
        let list = areas ?? []
        var proArea: [String: [Projekt]] = [:], ohne: [Projekt] = []
        for id in ids {
            let name = boardNames?[id] ?? tasks.first(where: { $0.projektId == id })?.projektName ?? id.prefix(1).uppercased() + id.dropFirst()
            let projekt = Projekt(id: id, name: name)
            if let area = AreasLogic.area(of: WorkCard(id: "", title: "", status: "", boardId: id), in: list, projects: projects ?? [:]) {
                proArea[area, default: []].append(projekt)
            } else { ohne.append(projekt) }
        }
        func sortiert(_ p: [Projekt]) -> [Projekt] { p.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        var out = list.compactMap { a in proArea[a.id].map { Gruppe(bereichId: a.id, bereichName: a.name, projekte: sortiert($0)) } }
        if !ohne.isEmpty { out.append(Gruppe(bereichId: nil, bereichName: nil, projekte: sortiert(ohne))) }
        return out
    }

    static func ziel(board: String?, boardNames: [String: String]?, projects: [String: String]?, areas: [Area]?,
                     tasks: [SenecaTask] = []) -> Ziel? {
        guard let board, !board.isEmpty, board != "privat" else { return nil }
        let list = areas ?? []
        let area = AreasLogic.area(of: WorkCard(id: "", title: "", status: "", boardId: board), in: list, projects: projects ?? [:])
        return Ziel(board: board,
                    projektName: boardNames?[board] ?? tasks.first(where: { $0.projektId == board })?.projektName,
                    bereichId: area, bereichName: area.flatMap { id in list.first(where: { $0.id == id })?.name })
    }

    static func beschriftung(_ ziel: Ziel?) -> String {
        guard let ziel else { return "Ohne Bereich" }
        let teile = AufgabenLogic.ortTeile(bereich: ziel.bereichName, projekt: ziel.projektName ?? ziel.board)
        return teile.isEmpty ? "Ohne Bereich" : teile.joined(separator: " · ")
    }
}

#if os(iOS)
extension AufgabenLogic {
    static func heutigeKartenTodos(_ cards: [WorkCard], heute: String) -> [WorkCard] {
        cards.filter { c in
            let privat = c.boardId == "privat" || (c.agentId ?? "").isEmpty
            guard privat, c.status != "done", !TodoEdits.isParked(c.title) else { return false }
            guard !(c.labels ?? []).contains(where: { $0.hasPrefix("entscheidung") }) else { return false }
            guard let plan = labelTag(c.labels, "plan") else { return false }
            return plan <= heute
        }.sorted { a, b in
            let pa = labelTag(a.labels, "plan") ?? "", pb = labelTag(b.labels, "plan") ?? ""
            let ueberA = pa < heute, ueberB = pb < heute
            if ueberA != ueberB { return ueberA }
            let prioA = DayLogic.priorityRank[a.priority ?? "normal"] ?? 2, prioB = DayLogic.priorityRank[b.priority ?? "normal"] ?? 2
            if prioA != prioB { return prioA < prioB }
            if pa != pb { return pa < pb }
            return TodoEdits.display(a.title).localizedCaseInsensitiveCompare(TodoEdits.display(b.title)) == .orderedAscending
        }
    }
}

#endif