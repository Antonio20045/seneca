import Foundation

struct AreaRow: Equatable, Identifiable, Sendable {
    var id: String
    var due: String
    var title: String
    var note: String
}

struct AreaSection: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var summary: String
    var rows: [AreaRow]
    var more: Int
    var leaderLine: String = ""
    var needs: String? = nil
}

struct AreasState: Equatable, Sendable {
    var stand: String
    var sections: [AreaSection]
}

enum AreasLogic {
    static let boardContext: [String: String] = ["hermes": "Sundartha", "powerbi": "Vodafone", "telco-radar": "Vodafone", "vodafone": "Vodafone"]
    static let order = ["running": 0, "review": 1, "blocked": 2, "ready": 3, "todo": 4, "scheduled": 5, "triage": 6, "backlog": 7]

    static func area(of card: WorkCard, in areas: [Area], projects: [String: String] = [:]) -> String? {
        let board = card.boardId
        if board == "privat" { return nil }
        if let assigned = projects[board], areas.contains(where: { $0.id == assigned }) { return assigned }
        if areas.contains(where: { $0.id == board }) { return board }
        if let context = boardContext[board],
           let area = areas.first(where: { $0.name.caseInsensitiveCompare(context) == .orderedSame || $0.id == context.lowercased() }) { return area.id }
        if let agent = card.agentId, !agent.isEmpty,
           let area = areas.first(where: { $0.leader == agent || $0.specialists.contains(agent) }) { return area.id }
        return nil
    }

    private static let dueRegex = try! NSRegularExpression(
        pattern: #"[\s,;(–-]*\b(?:bis|fällig|frist)(?:\s*:)?(?:\s+(?:zum|am|bis))?\s+(\d{1,2})\.(\d{1,2})\.(?:\d{2,4})?\)?"#,
        options: [.caseInsensitive])

    static func due(_ card: WorkCard) -> (day: Int, month: Int)? {
        for text in [card.title, card.notes ?? ""] {
            let ns = text as NSString
            if let m = dueRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               let d = Int(ns.substring(with: m.range(at: 1))), let mo = Int(ns.substring(with: m.range(at: 2))),
               (1...31).contains(d), (1...12).contains(mo) { return (d, mo) }
        }
        return nil
    }

    static func dueLabel(_ due: (day: Int, month: Int)?) -> String {
        guard let due else { return "–" }
        return String(format: "%02d.%02d.", due.day, due.month)
    }

    static func title(_ card: WorkCard) -> String {
        var t = card.title.replacingOccurrences(of: #"^\[[^\]]*\]\s*"#, with: "", options: .regularExpression)
        let ns = t as NSString
        if let m = dueRegex.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)), m.range.location + m.range.length == ns.length, m.range.location > 0 {
            t = ns.substring(to: m.range.location)
        }
        t = duForm(t.trimmingCharacters(in: .whitespaces))
        return t.isEmpty ? card.title : t
    }

    static func duForm(_ text: String) -> String {
        guard text.contains("Antonio") else { return text }
        let regeln: [(String, String)] = [
            (#"\b([Bb])ei Antonio\b"#, "$1ei dir"),
            (#"\b(von|mit|zu|nach|aus|Von|Mit|Zu|Nach|Aus) Antonio\b"#, "$1 dir"),
            (#"\b(durch|für|an|ohne|um|Durch|Für|An|Ohne|Um) Antonio\b"#, "$1 dich"),
            (#"\bAntonios (Anweisung|Entscheidung|Freigabe|Rückmeldung|Antwort|Zustimmung|Prüfung|Anmeldung|Wahl|Bitte)\b"#, "deine $1"),
            (#"\bAntonios (Auftrag|Wunsch|Okay|OK|Go|Hinweis)\b"#, "dein $1"),
        ]
        var t = text
        for (muster, ersatz) in regeln {
            t = t.replacingOccurrences(of: muster, with: ersatz, options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"(^|[.!?]\s+)(dein)"#, with: "$1D$2", options: .regularExpression)
            .replacingOccurrences(of: "Ddein", with: "Dein")
        return t
    }

    static func daysUntil(_ due: (day: Int, month: Int), now: Date, _ cal: Calendar) -> Int {
        let year = cal.component(.year, from: now)
        let today = cal.startOfDay(for: now)
        guard var date = cal.date(from: DateComponents(year: year, month: due.month, day: due.day)) else { return Int.max }
        if cal.dateComponents([.day], from: today, to: date).day! < -180 { date = cal.date(byAdding: .year, value: 1, to: date)! }
        return cal.dateComponents([.day], from: today, to: date).day!
    }

    private static let abbreviations: Set<String> = ["z.b.", "bzw.", "ca.", "nr.", "u.a.", "d.h.", "vgl.", "inkl.", "ggf.", "etc.", "evtl.", "max.", "min.", "usw.", "z.t.", "s."]

    static func sentences(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if ".!?…".contains(c), i + 1 < chars.count, chars[i + 1] == " " {
                let next = chars[(i + 2)...].first { $0 != " " }
                let word = current.split(separator: " ").last.map(String.init)?.lowercased() ?? ""
                let isDate = word.range(of: #"^\(?\d{1,2}\.(\d{1,2}\.)?(\d{2,4})?$"#, options: .regularExpression) != nil
                let isInitial = word.count == 2 && word.first!.isLetter && c == "."
                if let next, next.isUppercase || next == "„" || next == "\"", !isDate, !isInitial, !abbreviations.contains(word) {
                    out.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            }
            i += 1
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    static func clean(_ line: String) -> String {
        var t = line.replacingOccurrences(of: #"^Stand(?:\s+(?:vom\s+)?\d{1,2}\.\d{1,2}\.(?:\d{2,4})?(?:,?\s*\d{1,2}[:.]\d{2}(?:\s*Uhr)?)?)?\s*:\s*"#,
                                         with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s*\([^()]{13,}\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,.;:])"#, with: "$1", options: .regularExpression)
        t = duForm(t.trimmingCharacters(in: .whitespaces))
        if let first = t.first, first.isLowercase { t = first.uppercased() + t.dropFirst() }
        return t
    }

    static func summary(_ lines: [String], limit: Int = 200) -> String {
        var all: [String] = []
        for raw in lines {
            let line = clean(raw)
            guard !line.isEmpty else { continue }
            var parts = sentences(line)
            if raw.hasSuffix("…"), parts.count > 1 || !all.isEmpty { parts.removeLast() }
            all += parts.map { s in ".!?…:".contains(s.last!) ? s : s + "." }
        }
        guard let first = all.first else { return "" }
        if all.count > 1, first.count + 1 + all[1].count <= limit { return first + " " + all[1] }
        return first
    }

    static func stamp(_ area: Area, _ cal: Calendar) -> (date: Date, hasTime: Bool)? {
        let file = area.summary.changedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        if let line = area.summary.lines.first {
            let ns = line as NSString
            let re = try! NSRegularExpression(pattern: #"^Stand\s+(\d{1,2})\.(\d{1,2})\.(\d{4})?(?:,?\s*(\d{1,2})[:.](\d{2}))?"#, options: [.caseInsensitive])
            if let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                func int(_ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
                let year = int(3) ?? file.map { cal.component(.year, from: $0) } ?? cal.component(.year, from: Date())
                var c = DateComponents(year: year, month: int(2), day: int(1))
                if let h = int(4), let mi = int(5) {
                    c.hour = h; c.minute = mi
                    if let d = cal.date(from: c) { return (d, true) }
                } else if let d = cal.date(from: c) {
                    if let file, cal.isDate(file, inSameDayAs: d) { return (file, true) }
                    return (d, false)
                }
            }
        }
        return file.map { ($0, true) }
    }

    static func standSentence(_ stamp: (date: Date, hasTime: Bool), now: Date, _ cal: Calendar) -> String {
        let time = stamp.hasTime ? ", \(DayLogic.uhr(stamp.date, cal))" : ""
        if cal.isDate(stamp.date, inSameDayAs: now) { return "Stand von heute\(time)." }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(stamp.date, inSameDayAs: y) { return "Stand von gestern\(time)." }
        let f = germanFormatter("d. MMMM", cal)
        return "Stand vom \(f.string(from: stamp.date))\(time)."
    }

    static func state(registry: AreaRegistry?, cards: [WorkCard], projects: [String: String] = [:], updatedAt: Date?,
                      now: Date, _ cal: Calendar, maxCards: Int = 3, summaryLimit: Int = 200, separateNeeds: Bool = false) -> AreasState {
        let areas = registry?.areas ?? []
        guard !areas.isEmpty else {
            let stand: String
            switch registry?.state {
            case nil: stand = "Seneca holt den Stand, sobald dein Mac erreichbar ist."
            case "fehlerhaft": stand = "Die Liste der Bereiche auf deinem Mac ist gerade nicht lesbar."
            default: stand = "Es sind noch keine Bereiche angelegt."
            }
            return AreasState(stand: stand, sections: [])
        }
        let stamps = areas.compactMap { stamp($0, cal) }
        let newest = stamps.max { $0.date < $1.date } ?? updatedAt.map { ($0, true) }
        let stand = newest.map { standSentence($0, now: now, cal) } ?? "Seneca hat noch keinen Stand."
        var sections: [AreaSection] = []
        for area in areas {
            let open = cards.filter { $0.status != "done" && $0.status != "completed" && self.area(of: $0, in: areas, projects: projects) == area.id }
            let sorted = open.sorted { a, b in
                let wa = a.status == "review" || a.status == "blocked", wb = b.status == "review" || b.status == "blocked"
                if wa != wb { return wa }
                let da = due(a).map { daysUntil($0, now: now, cal) } ?? Int.max
                let db = due(b).map { daysUntil($0, now: now, cal) } ?? Int.max
                if da != db { return da < db }
                let oa = order[a.status] ?? 9, ob = order[b.status] ?? 9
                if oa != ob { return oa < ob }
                let pa = DayLogic.priorityRank[a.priority ?? "normal"] ?? 2, pb = DayLogic.priorityRank[b.priority ?? "normal"] ?? 2
                if pa != pb { return pa < pb }
                return (a.updatedAt ?? 0) > (b.updatedAt ?? 0)
            }
            let listed = separateNeeds ? sorted.filter { !needsYou($0) } : sorted
            let rows = listed.prefix(max(0, maxCards)).map { c in
                AreaRow(id: c.id, due: dueLabel(due(c)), title: title(c),
                        note: c.status == "review" ? ", wartet auf dich" : c.status == "blocked" ? ", hängt fest" : "")
            }
            var text = summary(area.summary.lines, limit: summaryLimit)
            if text.isEmpty {
                text = area.summary.exists ? "Im Kurzstand steht gerade nichts." : "\(area.leaderName) hat noch keinen Kurzstand geschrieben."
            }
            sections.append(AreaSection(id: area.id, name: area.name, summary: text, rows: Array(rows), more: listed.count - rows.count,
                                        leaderLine: leaderLine(area), needs: needsSentence(sorted)))
        }
        return AreasState(stand: stand, sections: sections)
    }
}

extension SenecaPayloadParser {
    static func projects(_ result: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (board, value) in result["projekte"] as? [String: Any] ?? [:] {
            if let area = (value as? [String: Any])?["bereichId"] as? String, !area.isEmpty { out[board] = area }
        }
        return out
    }
}

private let formatterLock = NSLock()
nonisolated(unsafe) private var formatters: [String: DateFormatter] = [:]
func germanFormatter(_ format: String, _ cal: Calendar) -> DateFormatter {
    formatterLock.lock(); defer { formatterLock.unlock() }
    let key = format + "|" + cal.timeZone.identifier + "|\(cal.identifier)"
    if let f = formatters[key] { return f }
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE"); f.calendar = cal; f.timeZone = cal.timeZone
    f.dateFormat = format
    formatters[key] = f
    return f
}

extension AreasLogic {
    static func needsYou(_ card: WorkCard) -> Bool { card.status == "review" || card.status == "blocked" }
    static func isDone(_ card: WorkCard) -> Bool { card.status == "done" || card.status == "completed" }

    static func sessionKey(leader: String) -> String {
        let id = leader.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? Hauptagent.sitzung : "agent:\(id):main"
    }

    static func chatSession(_ target: String?, main: String) -> String {
        let t = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? main : t
    }

    static func agentID(of sessionKey: String) -> String {
        let parts = sessionKey.split(separator: ":")
        return parts.count >= 2 && parts[0] == "agent" ? String(parts[1]) : Hauptagent.id
    }

#if os(iOS)
    private static func takesArticle(_ name: String) -> Bool { name.lowercased().hasSuffix("agent") || name.lowercased().hasSuffix("agentin") }
#else
    private static func takesArticle(_ name: String) -> Bool { name.lowercased().hasSuffix("leiter") || name.lowercased().hasSuffix("leiterin") }
#endif

    static func talkLine(_ leaderName: String) -> String {
        guard takesArticle(leaderName) else { return "Mit \(leaderName) sprechen" }
#if os(iOS)
        return "Mit \(leaderName.lowercased().hasSuffix("in") ? "der" : "dem") \(NeedsYou.dativ(leaderName)) sprechen"
#else
        return "Mit \(leaderName.lowercased().hasSuffix("in") ? "der" : "dem") \(leaderName) sprechen"
#endif
    }

    static func leaderLine(_ area: Area) -> String {
        let name = area.leaderName
#if os(iOS)
        let led = takesArticle(name) ? (name.lowercased().hasSuffix("in") ? "Geleitet von der \(name)" : "Geleitet vom \(NeedsYou.dativ(name))") : "Geleitet von \(name)"
#else
        let led = takesArticle(name) ? (name.lowercased().hasSuffix("in") ? "Geleitet von der \(name)" : "Geleitet vom \(name)") : "Geleitet von \(name)"
#endif
        switch area.specialists.count {
        case 0: return led + "."
        case 1: return led + ", mit einem Spezialisten."
        case let n: return led + ", mit \(DayLogic.word(n)) Spezialisten."
        }
    }

    static func needsSentence(_ cards: [WorkCard]) -> String? {
        let waiting = cards.filter(needsYou)
        guard let first = waiting.first else { return nil }
        if waiting.count == 1 {
            return first.status == "review" ? "„\(title(first))“ wartet auf deine Prüfung." : "„\(title(first))“ hängt fest und braucht dich."
        }
        let n = DayLogic.word(waiting.count)
        return "\(n.prefix(1).uppercased() + n.dropFirst()) Karten brauchen dich, zuerst „\(title(first))“."
    }


    static func dueShort(_ due: (day: Int, month: Int)?, now: Date, _ cal: Calendar) -> String {
        guard let due else { return "" }
        return daysUntil(due, now: now, cal) == 0 ? "heute" : dueLabel(due)
    }

    static func dueSentence(_ due: (day: Int, month: Int)?, now: Date, _ cal: Calendar) -> String? {
        guard let due else { return nil }
        let d = daysUntil(due, now: now, cal)
        switch d {
        case ..<(-1): return "Seit \(DayLogic.word(-d)) Tagen überfällig."
        case -1: return "Seit gestern überfällig."
        case 0: return "Heute fällig."
        case 1: return "Morgen fällig."
        default:
            let year = cal.component(.year, from: now)
            var date = cal.date(from: DateComponents(year: year, month: due.month, day: due.day)) ?? now
            if cal.dateComponents([.day], from: cal.startOfDay(for: now), to: date).day! < -180 { date = cal.date(byAdding: .year, value: 1, to: date)! }
            let f = germanFormatter(d < 7 ? "EEEE, d. MMMM" : "d. MMMM", cal)
            return "Fällig am \(f.string(from: date))."
        }
    }

    static func changedSentence(_ ms: Double?, now: Date, _ cal: Calendar) -> String? {
        guard let ms, ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        if cal.isDate(date, inSameDayAs: now) { return "Zuletzt geändert heute um \(DayLogic.uhr(date, cal))." }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "Zuletzt geändert gestern um \(DayLogic.uhr(date, cal))." }
        let f = germanFormatter("d. MMMM", cal)
        return "Zuletzt geändert am \(f.string(from: date))."
    }

    static let statusSentences = [
        "running": "Läuft gerade.", "review": "Wartet auf deine Prüfung.", "blocked": "Hängt fest und braucht dich.",
        "ready": "Ist bereit für den nächsten Schritt.", "todo": "Steht als Nächstes an.", "scheduled": "Ist eingeplant.",
        "triage": "Ist neu eingegangen und noch nicht eingeordnet.", "backlog": "Liegt im Vorrat.",
        "done": "Ist erledigt.", "completed": "Ist erledigt.",
    ]

    static let groups: [(id: String, title: String, statuses: Set<String>)] = [
        ("running", "Läuft gerade", ["running"]),
        ("next", "Als Nächstes", ["ready", "todo"]),
        ("scheduled", "Eingeplant", ["scheduled"]),
        ("inbox", "Im Vorrat", ["triage", "backlog"]),
        ("done", "Zuletzt erledigt", ["done", "completed"]),
    ]

    static func cardInfo(_ c: WorkCard, area: Area, agentNames: [String: String], now: Date, _ cal: Calendar) -> AreaCardInfo {
        let d = due(c)
        var agent: String?
        if let id = c.agentId, !id.isEmpty {
            if id == area.leader {
                agent = takesArticle(area.leaderName) ? "Zuständig ist der \(area.leaderName)." : "Zuständig ist \(area.leaderName)."
            } else {
                agent = "Zuständig ist \(agentNames[id] ?? id)."
            }
        }
        let notes = c.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AreaCardInfo(id: c.id, title: title(c), due: dueShort(d, now: now, cal), dueSentence: dueSentence(d, now: now, cal),
                            status: c.status, statusSentence: statusSentences[c.status] ?? "Steht als Nächstes an.",
                            notes: notes?.isEmpty == false ? notes : nil, changed: changedSentence(c.updatedAt, now: now, cal), agent: agent)
    }

    static func detail(_ area: Area, cards: [WorkCard], areas: [Area], projects: [String: String] = [:], agentNames: [String: String] = [:],
                       stand: String? = nil, now: Date, _ cal: Calendar) -> AreaDetail {
        let mine = cards.filter { self.area(of: $0, in: areas, projects: projects) == area.id }
        func rank(_ a: WorkCard, _ b: WorkCard) -> Bool {
            let da = due(a).map { daysUntil($0, now: now, cal) } ?? Int.max
            let db = due(b).map { daysUntil($0, now: now, cal) } ?? Int.max
            if da != db { return da < db }
            let oa = order[a.status] ?? 9, ob = order[b.status] ?? 9
            if oa != ob { return oa < ob }
            let pa = DayLogic.priorityRank[a.priority ?? "normal"] ?? 2, pb = DayLogic.priorityRank[b.priority ?? "normal"] ?? 2
            if pa != pb { return pa < pb }
            return (a.updatedAt ?? 0) > (b.updatedAt ?? 0)
        }
        let info = { (c: WorkCard) in cardInfo(c, area: area, agentNames: agentNames, now: now, cal) }
        let needs = mine.filter(needsYou).sorted { a, b in a.status != b.status ? a.status == "review" : rank(a, b) }.map(info)
        let weekAgo = now.timeIntervalSince1970 * 1000 - 7 * 86_400_000
        var groups: [AreaCardGroup] = []
        for g in Self.groups {
            var list = mine.filter { c in
                if needsYou(c) { return false }
                if g.id == "next", !Self.groups.contains(where: { $0.statuses.contains(c.status) }) { return true }
                return g.statuses.contains(c.status)
            }
            if g.id == "done" {
                list = list.filter { ($0.updatedAt ?? 0) >= weekAgo }.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                list = Array(list.prefix(3))
            } else {
                list.sort(by: rank)
            }
            if !list.isEmpty { groups.append(AreaCardGroup(id: g.id, title: g.title, cards: list.map(info))) }
        }
        let lines = area.summary.lines.map(clean).filter { !$0.isEmpty }
        var standLine: String?
        if let s = stamp(area, cal) { standLine = "Kurzstand " + standSentence(s, now: now, cal).dropFirst("Stand ".count) }
        return AreaDetail(id: area.id, name: area.name, leaderName: area.leaderName, sessionKey: sessionKey(leader: area.leader),
                          leaderLine: leaderLine(area), talkLine: talkLine(area.leaderName),
                          standLine: standLine, summary: lines.isEmpty ? [area.summary.exists ? "Im Kurzstand steht gerade nichts." : "\(area.leaderName) hat noch keinen Kurzstand geschrieben."] : lines,
                          needs: needs, needsFromStand: stand.map(StandText.atAntonio) ?? [],
                          groups: groups, open: mine.filter { !isDone($0) }.count,
                          standBlocks: stand.map { StandText.blocks($0) })
    }
}

struct AreaCardInfo: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var due: String
    var dueSentence: String?
    var status: String
    var statusSentence: String
    var notes: String?
    var changed: String?
    var agent: String?
}

struct AreaCardGroup: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var cards: [AreaCardInfo]
}

struct AreaDetail: Equatable, Sendable {
    var id: String
    var name: String
    var leaderName: String
    var sessionKey: String
    var leaderLine: String
    var talkLine: String
    var standLine: String?
    var summary: [String]
    var needs: [AreaCardInfo]
    var needsFromStand: [String]
    var groups: [AreaCardGroup]
    var open: Int
    var standBlocks: [StandText.Block]?
}

enum StandText {
    enum Kind: Equatable, Sendable { case heading(Int), paragraph, bullet, numbered(String) }
    struct Block: Equatable, Identifiable, Sendable {
        var id: Int
        var kind: Kind
        var text: String
    }

    static func inline(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: #"__(.+?)__"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }


    static func blocks(_ markdown: String, skipKurzstand: Bool = true) -> [Block] {
        var out: [Block] = []
        var current: (kind: Kind, text: String)?
        var skipping = false
        func flush() {
            if let c = current, !c.text.isEmpty {
                var kind = c.kind
                var text = inline(c.text)
                if kind == .paragraph, text.hasPrefix("**"), text.hasSuffix("**"), text.count > 4, !text.dropFirst(2).dropLast(2).contains("**") {
                    kind = .heading(4); text = String(text.dropFirst(2).dropLast(2))
                }
                out.append(Block(id: out.count, kind: kind, text: text))
            }
            current = nil
        }
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush()
                let level = line[m].filter { $0 == "#" }.count
                let title = String(line[m.upperBound...]).trimmingCharacters(in: .whitespaces)
                if level <= 2 { skipping = skipKurzstand && title.lowercased().hasPrefix("kurzstand") }
                if !skipping { out.append(Block(id: out.count, kind: .heading(level), text: inline(title))) }
                continue
            }
            if skipping { continue }
            if line.isEmpty || line.range(of: #"^(-{3,}|\*{3,}|<!--.*-->)$"#, options: .regularExpression) != nil { flush(); continue }
            if let m = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flush(); current = (.bullet, String(line[m.upperBound...])); continue
            }
            if let m = line.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
                flush()
                let number = line[m].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ")", with: ".")
                current = (.numbered(number), String(line[m.upperBound...])); continue
            }
            if current != nil { current!.text += " " + line } else { current = (.paragraph, line) }
        }
        flush()
        return out
    }

    static func atAntonio(_ markdown: String) -> [String] {
        var out: [String] = []
        var inside = false
        for b in blocks(markdown, skipKurzstand: false) {
            if case .heading = b.kind {
                inside = b.text.lowercased().hasPrefix("bei antonio")
                continue
            }
            if inside { out.append(AreasLogic.duForm(b.text.replacingOccurrences(of: "**", with: ""))) }
        }
        return out
    }
}
