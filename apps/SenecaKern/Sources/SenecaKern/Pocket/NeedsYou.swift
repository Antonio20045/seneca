import Foundation

struct NeedsItem: Equatable, Sendable {
    enum Kind: Sendable { case agent, card, results, failures, calendar }
    enum Tone: Sendable { case error, decision }
    struct Line: Equatable, Sendable {
        enum Kind: Sendable { case result, failure }
        var jobId: String
        var name: String
        var agentId: String
        var reason: String
        var kind: Kind
        var key: String
        var undelivered: Bool
        var lastRunAtMs: Double
        var durationMs: Double
    }
    var id: String
    var kind: Kind
    var tone: Tone
    var title: String
    var text: String
    var lines: [Line] = []
    var keys: [String]
    var agentId: String? = nil
    var cardTitle: String? = nil
    var cardStatus: String? = nil
    var boardId: String? = nil
    var count: Int { max(1, lines.count) }
}

struct NeedsInput {
    var now: Date
    var calendar: Calendar
    var sessions: [SessionRow]
    var cards: [WorkCard]
    var jobs: [AgentJob]
    var seen: [String: Double]
    var areas: AreaRegistry?
    var agentNames: [String: String]
    var calendarStatus: CalendarStatus?

    init(now: Date, calendar: Calendar, snapshot: TodaySnapshot?, localSeen: [String: Double] = [:]) {
        self.now = now
        self.calendar = calendar
        sessions = snapshot?.sessions ?? []
        cards = snapshot?.cards ?? []
        jobs = snapshot?.jobs ?? []
        seen = (snapshot?.seen ?? [:]).merging(localSeen) { max($0, $1) }
        areas = snapshot?.areas
        agentNames = snapshot?.agentNames ?? [:]
        if areas == nil, let leaders = snapshot?.leaders, !leaders.isEmpty {
            areas = AreaRegistry(areas: leaders.map { Area(id: $0.key, name: $0.key, leader: $0.key, leaderName: $0.value) })
        }
        calendarStatus = snapshot?.calendarStatus
    }

    init(now: Date, calendar: Calendar, sessions: [SessionRow] = [], cards: [WorkCard] = [], jobs: [AgentJob] = [],
         seen: [String: Double] = [:], areas: AreaRegistry? = nil, agentNames: [String: String] = [:], calendarStatus: CalendarStatus? = nil) {
        self.now = now; self.calendar = calendar; self.sessions = sessions; self.cards = cards; self.jobs = jobs
        self.seen = seen; self.areas = areas; self.agentNames = agentNames; self.calendarStatus = calendarStatus
    }
}

enum NeedsYou {
    static let day: Double = 86_400_000

    static func isMainKey(_ key: String) -> Bool { key.range(of: #"^agent:[^:]+:main$"#, options: .regularExpression) != nil }
    static func leader(_ id: String?, _ areas: AreaRegistry?) -> Area? {
        guard let id, !id.isEmpty else { return nil }
        return areas?.areas.first { $0.leader == id }
    }
    static let alwaysHelpers: Set<String> = ["claude", "engineer", "researcher", "pruefer"]
    static func isHelper(_ id: String?, _ areas: AreaRegistry?) -> Bool {
        let id = id ?? ""
        if id.isEmpty || leader(id, areas) != nil { return false }
        return alwaysHelpers.contains(id) || id.hasPrefix("sp-") || (areas?.shared.contains(id) ?? false)
            || (areas?.areas.contains { $0.specialists.contains(id) } ?? false)
    }
    static func label(_ id: String?, _ input: NeedsInput) -> String {
        guard let id, !id.isEmpty else { return "" }
        return leader(id, input.areas)?.leaderName ?? input.agentNames[id] ?? id
    }
    static func jobName(_ job: AgentJob) -> String {
        let raw = (job.displayName?.isEmpty == false ? job.displayName! : job.name)
        let short = raw.replacingOccurrences(of: #"^Skill collection review.*$"#, with: "Skill-Review", options: [.regularExpression, .caseInsensitive])
        return DayLogic.jobTitle(short)
    }
    static func num(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == value.rounded(), abs(value) < 9e15 { return String(Int64(value)) }
        return NSNumber(value: value).stringValue
    }
    static func jsPrefix(_ s: String, _ n: Int) -> String { String(decoding: Array(s.utf16.prefix(n)), as: UTF16.self) }
    static func cardKey(_ card: WorkCard) -> String { "karte:\(card.id):\(num(card.updatedAt))" }

    static func reason(_ job: AgentJob) -> (reason: String, undelivered: Bool) {
        let raw = job.lastDiagnosticsSummary ?? job.lastError ?? ""
        func has(_ pattern: String) -> Bool { raw.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if has("channel is required|no configured channels") { return ("Fertig, aber nicht als Nachricht zugestellt.", true) }
        if job.lastDeliveryStatus == "not-delivered" && (job.lastDurationMs ?? 0) > 30_000 { return ("Fertig, aber nicht zugestellt.", true) }
        if has("-600|Programm läuft nicht|is not running") { return ("Die Kalender-App lief nicht, als die Automatisierung startete.", false) }
        if has("429|rate limit|usage limit|Nutzungslimit") { return ("Das Nutzungslimit des Modells war erreicht.", false) }
        if has("billing|credit|guthaben|insufficient") { return ("Das Modell meldet ein Abrechnungsproblem.", false) }
        if has("timed? ?out|timeout") { return ("Der Lauf hat zu lange gedauert und wurde abgebrochen.", false) }
        if raw.isEmpty { return ("Letzter Lauf mit Fehler beendet.", false) }
        return (jsPrefix(raw.components(separatedBy: "\n")[0], 160), false)
    }

    static func items(_ input: NeedsInput) -> [NeedsItem] {
        var out: [NeedsItem] = []
        let nowMs = input.now.timeIntervalSince1970 * 1000
        func isNew(_ k: String) -> Bool { input.seen[k] == nil }
        for s in input.sessions where isMainKey(s.key) && s.status == "failed" && !(s.lastRunError ?? "").isEmpty && !isHelper(s.agentId, input.areas) {
            let error = s.lastRunError!
            let k = "agent:\(s.key):\(jsPrefix(error, 80))"
            guard isNew(k) else { continue }
            out.append(NeedsItem(id: "agent-" + s.key, kind: .agent, tone: .error, title: "\(label(s.agentId, input)) bricht gerade ab",
                                 text: jsPrefix(error, 220), keys: [k], agentId: s.agentId))
        }
        for c in input.cards where (c.status == "review" || c.status == "blocked") && isNew(cardKey(c)) {
            let review = c.status == "review"
            out.append(NeedsItem(id: "card-" + c.id, kind: .card, tone: review ? .decision : .error,
                                 title: review ? "Wartet auf deine Prüfung: \(c.title)" : "Hängt fest: \(c.title)",
                                 text: [label(c.agentId, input), c.boardId].filter { !$0.isEmpty }.joined(separator: ", "),
                                 keys: [cardKey(c)], agentId: c.agentId, cardTitle: c.title, cardStatus: c.status, boardId: c.boardId))
        }
        var results: [NeedsItem.Line] = [], failures: [NeedsItem.Line] = []
        for j in input.jobs where j.enabled && (j.lastRunAtMs ?? 0) > nowMs - 2 * day {
            let last = j.lastRunAtMs!
            let (why, undelivered) = j.lastRunStatus == "error" ? reason(j) : ("", false)
            let isResult = j.deliveryMode == "announce" && (j.lastRunStatus == "ok" || undelivered) && (j.lastDurationMs ?? 0) > 20_000
            if isResult {
                let k = "lauf:\(j.id):\(num(last))"
                if isNew(k) { results.append(.init(jobId: j.id, name: jobName(j), agentId: j.agentId, reason: why, kind: .result, key: k, undelivered: undelivered, lastRunAtMs: last, durationMs: j.lastDurationMs ?? 0)) }
            } else if j.lastRunStatus == "error" {
                let k = "fehler:\(j.id):\(num(last))"
                if isNew(k) { failures.append(.init(jobId: j.id, name: jobName(j), agentId: j.agentId, reason: why, kind: .failure, key: k, undelivered: false, lastRunAtMs: last, durationMs: j.lastDurationMs ?? 0)) }
            }
        }
        results.sort { $0.lastRunAtMs > $1.lastRunAtMs }
        failures.sort { $0.lastRunAtMs > $1.lastRunAtMs }
        if !results.isEmpty {
            var agents: [String] = []
            for r in results where !agents.contains(label(r.agentId, input)) { agents.append(label(r.agentId, input)) }
            let from = agents.count == 1 ? agents[0] : "deinen Mitarbeitern"
            let undelivered = results.contains { $0.undelivered }
            out.append(NeedsItem(id: "ergebnisse", kind: .results, tone: .decision,
                                 title: results.count == 1 ? "Neu von \(from): \(results[0].name)" : "\(results.count) neue Ergebnisse von \(from)",
                                 text: undelivered ? "Fertig, aber nicht bei dir angekommen, weil kein Nachrichtenkanal eingerichtet ist. Hier kannst du sie lesen."
                                                   : "Fertig. Lies sie hier, danach verschwinden sie aus dieser Liste.",
                                 lines: results, keys: results.map(\.key)))
        }
        if !failures.isEmpty {
            out.append(NeedsItem(id: "fehler", kind: .failures, tone: .error,
                                 title: failures.count == 1 ? "\(failures[0].name) ist fehlgeschlagen" : "\(failures.count) Automatisierungen sind fehlgeschlagen",
                                 text: failures.count == 1 ? failures[0].reason : list(failures.map(\.name)) + ".",
                                 lines: failures, keys: failures.map(\.key)))
        }
        if let cal = input.calendarStatus, !cal.ok {
            let k = "kalender:\(cal.checkedAt ?? "")"
            if isNew(k) {
                out.append(NeedsItem(id: "kalender", kind: .calendar, tone: .error, title: "Seneca kommt nicht an deinen Kalender",
                                     text: cal.hint ?? "Die letzte Kalenderabfrage ist fehlgeschlagen.", keys: [k]))
            }
        }
        return out
    }

    static func count(_ items: [NeedsItem]) -> Int { items.reduce(0) { $0 + $1.count } }
    static func keys(_ items: [NeedsItem]) -> [String] { items.flatMap(\.keys) }

    static func list(_ names: [String]) -> String {
        names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " und " + names.last!
    }
    static let countWords = ["Keine", "Eine", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht", "Neun", "Zehn", "Elf", "Zwölf"]
    static func countWord(_ n: Int) -> String { n < countWords.count ? countWords[n] : String(n) }
    static func lowerCount(_ n: Int) -> String { n < countWords.count ? countWords[n].lowercased() : String(n) }

    static func who(_ id: String?, _ input: NeedsInput) -> String {
        guard let id, !id.isEmpty else { return "ein Mitarbeiter" }
        if id == Hauptagent.id { return "Seneca" }
        let name = label(id, input)
#if os(iOS)
        return name.hasSuffix("Agent") ? "der \(name)" : name.prefix(1).uppercased() + name.dropFirst()
#else
        return name.hasSuffix("Leiter") ? "der \(name)" : name.prefix(1).uppercased() + name.dropFirst()
#endif
    }
#if os(iOS)
    static func from(_ who: String) -> String { who.hasPrefix("der ") ? "vom " + dativ(String(who.dropFirst(4))) : "von " + who }
    static func dativ(_ name: String) -> String { name.hasSuffix("Agent") ? name + "en" : name }
#else
    static func from(_ who: String) -> String { who.hasPrefix("der ") ? "vom " + who.dropFirst(4) : "von " + who }
#endif
    static func upper(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func when(_ ms: Double, now: Date, _ cal: Calendar) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        let h = cal.component(.hour, from: date)
        let part = h < 5 ? "Nacht" : h < 10 ? "früh" : h < 12 ? "Vormittag" : h < 14 ? "Mittag" : h < 18 ? "Nachmittag" : h < 22 ? "Abend" : "Nacht"
        switch days {
        case ...0: return part == "früh" ? "heute früh" : "heute \(part)"
        case 1: return part == "früh" ? "gestern früh" : "gestern \(part)"
        default: return "vorgestern"
        }
    }

    static func sentence(_ item: NeedsItem, _ input: NeedsInput) -> (lead: String, also: String) {
        switch item.kind {
        case .agent:
            let w = who(item.agentId, input)
            return ("\(upper(w)) bricht gerade ab.", "Außerdem bricht \(w) gerade ab.")
        case .card:
            let t = "„\(AufgabenLogic.anzeigeTitel(item.cardTitle ?? ""))“"
            return item.cardStatus == "review"
                ? ("\(t) wartet auf deine Prüfung.", "Außerdem wartet \(t) auf deine Prüfung.")
                : ("\(t) hängt fest.", "Außerdem hängt \(t) fest.")
        case .results:
            let agents = Set(item.lines.map(\.agentId))
            let w = agents.count == 1 ? who(item.lines[0].agentId, input) : "deine Mitarbeiter"
            if item.lines.count == 1 {
                return ("\(upper(w)) hat „\(item.lines[0].name)“ fertig.", "Außerdem hat \(w) „\(item.lines[0].name)“ fertig.")
            }
            let von = agents.count == 1 ? from(w) : "von deinen Mitarbeitern"
            let n = lowerCount(item.lines.count)
            return ("\(upper(von)) sind \(n) neue Ergebnisse da.", "Außerdem sind \(von) \(n) neue Ergebnisse da.")
        case .failures:
            if item.lines.count == 1 {
                let l = item.lines[0], at = when(l.lastRunAtMs, now: input.now, input.calendar)
                return ("\(l.name) ist \(at) fehlgeschlagen.", "Außerdem ist \(l.name) \(at) fehlgeschlagen.")
            }
            if item.lines.count == 2 {
                let names = list(item.lines.map(\.name))
                return ("\(names) sind fehlgeschlagen.", "Außerdem sind \(names) fehlgeschlagen.")
            }
            let n = lowerCount(item.lines.count)
            return ("\(upper(n)) Automatisierungen sind fehlgeschlagen.", "Außerdem sind \(n) Automatisierungen fehlgeschlagen.")
        case .calendar:
            return ("Seneca kommt gerade nicht an deinen Kalender.", "Außerdem kommt Seneca gerade nicht an deinen Kalender.")
        }
    }

    static func hero(_ items: [NeedsItem], _ input: NeedsInput) -> HeroText? {
        guard let first = items.first else { return nil }
        let n = count(items)
        var sub = sentence(first, input).lead
        if items.count == 2 {
            sub += " " + sentence(items[1], input).also
        } else if items.count > 2 {
            let rest = n - first.count
            sub += rest == 1 ? " Dazu kommt noch eine weitere Sache." : " Dazu kommen noch \(lowerCount(rest)) weitere."
        }
        return HeroText(line1: n == 1 ? "Eine Sache" : "\(countWord(n)) Sachen", line2Prefix: "",
                        emphasis: n == 1 ? "wartet" : "warten", line2Suffix: " auf dich.", sub: sub, mode: .plain)
    }

    static func mintZeile(_ items: [NeedsItem], _ input: NeedsInput) -> String? {
        guard let first = items.first else { return nil }
        let n = count(items)
        let erstes = nennung(first, input)
        return n == 1 ? "Eine Sache wartet auf dich: \(erstes)." : "\(countWord(n)) Sachen warten auf dich, zuerst \(erstes)."
    }

    struct BerichtText: Equatable {
        var id: String, kicker: String, title: String, body: String, keys: [String]
        var bewertung: BerichtBewertung? = nil
    }

    static func berichtZeilen(_ items: [NeedsItem]) -> [NeedsItem.Line] {
        guard let first = items.first, first.kind == .results else { return [] }
        return Array(first.lines.prefix(3))
    }

    static func laufText(_ result: [String: Any]) -> String? {
        let text = ((result["entries"] as? [[String: Any]])?.first?["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    static func bericht(_ lines: [NeedsItem.Line], texte: [String?], now: Date, calendar cal: Calendar) -> BerichtText? {
        let teile = zip(lines, texte).compactMap { l, t in t.map { (line: l, text: $0) } }
        guard let first = teile.first else { return nil }
        func wann(_ l: NeedsItem.Line) -> String {
            let date = Date(timeIntervalSince1970: l.lastRunAtMs / 1000)
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
            return "\(days <= 0 ? "heute" : days == 1 ? "gestern" : "vorgestern"), \(DayLogic.hm(date, cal)) Uhr"
        }
        let keys = teile.map(\.line.key)
        if teile.count == 1 {
            return BerichtText(id: "ergebnis-\(first.line.key)", kicker: "Bericht · \(wann(first.line))", title: first.line.name, body: first.text, keys: keys,
                           bewertung: BerichtBewertung(agentId: first.line.agentId.isEmpty ? Hauptagent.id : first.line.agentId, kartenId: first.line.key))
        }
        return BerichtText(id: "ergebnisse-\(keys.joined(separator: ","))", kicker: "Bericht · \(wann(first.line))", title: "Neue Ergebnisse",
                           body: teile.map { "## \($0.line.name)\n\n\($0.text)" }.joined(separator: "\n\n"), keys: keys)
    }

    static func nennung(_ item: NeedsItem, _ input: NeedsInput) -> String {
        switch item.kind {
        case .agent: return "\(who(item.agentId, input)), der gerade abbricht"
        case .card: return "„\(AufgabenLogic.anzeigeTitel(item.cardTitle ?? ""))“"
        case .results:
            if item.lines.count == 1 { return "das Ergebnis „\(item.lines[0].name)“" }
            let agents = Set(item.lines.map(\.agentId))
            let von = agents.count == 1 ? from(who(item.lines[0].agentId, input)) : "von deinen Mitarbeitern"
            return "\(lowerCount(item.lines.count)) neue Ergebnisse \(von)"
        case .failures:
            return item.lines.count == 1 ? "der fehlgeschlagene Lauf „\(item.lines[0].name)“" : "\(lowerCount(item.lines.count)) fehlgeschlagene Läufe"
        case .calendar: return "dein Kalender, an den Seneca gerade nicht herankommt"
        }
    }

    static func answer(_ items: [NeedsItem], _ input: NeedsInput) -> AnswerLayout {
        let cal = input.calendar
        var rows: [AnswerLayout.Row] = []
        var reasons: [String] = []
        for item in items {
            switch item.kind {
            case .agent:
                rows.append(.init(time: "–", text: "\(upper(who(item.agentId, input))) bricht gerade ab."))
                let first = jsPrefix(item.text.components(separatedBy: "\n")[0], 160)
                if !first.isEmpty { reasons.append(first.hasSuffix(".") ? first : first + ".") }
            case .card:
                let review = item.cardStatus == "review"
                rows.append(.init(time: "–", text: review ? "„\(AufgabenLogic.anzeigeTitel(item.cardTitle ?? ""))“ wartet auf deine Prüfung." : "„\(AufgabenLogic.anzeigeTitel(item.cardTitle ?? ""))“ hängt fest."))
                if items.count == 1, let agent = item.agentId, !agent.isEmpty {
                    reasons.append("Sie kommt \(from(who(agent, input))).")
                }
            case .results:
                for l in item.lines {
                    rows.append(.init(time: DayLogic.hm(Date(timeIntervalSince1970: (l.lastRunAtMs + l.durationMs) / 1000), cal), text: "\(l.name) ist fertig."))
                }
                if item.lines.contains(where: \.undelivered) { reasons.append("Es ist fertig, kam aber nicht als Nachricht bei dir an.") }
            case .failures:
                for l in item.lines {
                    rows.append(.init(time: DayLogic.hm(Date(timeIntervalSince1970: l.lastRunAtMs / 1000), cal), text: "\(l.name) ist fehlgeschlagen."))
                    if !reasons.contains(l.reason) { reasons.append(l.reason) }
                }
            case .calendar:
                rows.append(.init(time: "–", text: "Seneca kommt nicht an deinen Kalender."))
                reasons.append(item.text)
            }
        }
        let headline: [AnswerLayout.Segment]
        if items.count == 1, let only = items.first {
            headline = singleHeadline(only, input)
        } else {
            let n = count(items)
            headline = [.init(text: "\(countWord(n)) Sachen\n", italic: false), .init(text: "warten", italic: true), .init(text: " auf dich.", italic: false)]
        }
        return AnswerLayout(headline: headline, rows: Array(rows.prefix(6)), rest: reasons.prefix(2).joined(separator: " "))
    }

    private static func singleHeadline(_ item: NeedsItem, _ input: NeedsInput) -> [AnswerLayout.Segment] {
        func h(_ a: String, _ em: String, _ b: String = ".") -> [AnswerLayout.Segment] { [.init(text: a, italic: false), .init(text: em, italic: true), .init(text: b, italic: false)] }
        switch item.kind {
        case .agent: return h("\(upper(who(item.agentId, input))) bricht gerade ", "ab")
        case .card:
            let t = "„\(AufgabenLogic.anzeigeTitel(item.cardTitle ?? ""))“"
            return item.cardStatus == "review" ? h("\(t) wartet auf deine ", "Prüfung") : h("\(t) hängt ", "fest")
        case .results:
            return item.lines.count == 1 ? h("\(item.lines[0].name) ist ", "fertig") : h("\(countWord(item.lines.count)) neue ", "Ergebnisse", " sind da.")
        case .failures:
            return item.lines.count == 1 ? h("\(item.lines[0].name) ist ", "fehlgeschlagen") : h("\(countWord(item.lines.count)) Läufe sind ", "fehlgeschlagen")
        case .calendar: return h("Seneca kommt nicht an deinen ", "Kalender")
        }
    }
}
