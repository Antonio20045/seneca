import Foundation

struct TodaySnapshot: Codable, Sendable {
    var calendar: [CalendarEntry]
    var tasks: [SenecaTask]
    var briefings: [Briefing]
    var updatedAt: Date
    var jobs: [AgentJob]? = nil
    var leaders: [String: String]? = nil
    var cards: [WorkCard]? = nil
    var sessions: [SessionRow]? = nil
    var seen: [String: Double]? = nil
    var agentNames: [String: String]? = nil
    var areas: AreaRegistry? = nil
    var projects: [String: String]? = nil
    var calendarStatus: CalendarStatus? = nil
    var projectDue: [String: String]? = nil
    var boardNames: [String: String]? = nil
}

struct WorkCard: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var status: String
    var agentId: String? = nil
    var sessionKey: String? = nil
    var boardId: String = "default"
    var updatedAt: Double? = nil
    var priority: String? = nil
    var notes: String? = nil
    var labels: [String]? = nil
#if os(iOS)
    var startedAt: Double? = nil
    var lebenszeichen: Double? = nil
    var stand: String? = nil
#endif
}

struct SessionRow: Codable, Sendable, Equatable {
    var key: String
    var agentId: String? = nil
    var status: String? = nil
    var lastRunError: String? = nil
}

struct CalendarStatus: Codable, Sendable, Equatable {
    var ok: Bool
    var checkedAt: String? = nil
    var hint: String? = nil
    var checkedDate: Date? { checkedAt.flatMap { SenecaPayloadParser.date($0) } }
}

enum CalendarFreshness {
    static let staleAfter: TimeInterval = 10 * 60
    static func isStale(checkedAt: Date?, now: Date) -> Bool {
        guard let checkedAt else { return false }
        return now.timeIntervalSince(checkedAt) > staleAfter
    }
    static func standText(checkedAt: Date?, now: Date, _ cal: Calendar = .current) -> String? {
        guard let checkedAt, isStale(checkedAt: checkedAt, now: now) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "H:mm"
        let time = f.string(from: checkedAt)
        if cal.isDate(checkedAt, inSameDayAs: now) { return "Stand \(time)" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(checkedAt, inSameDayAs: y) { return "Stand gestern, \(time)" }
        f.dateFormat = "d.M., H:mm"
        return "Stand \(f.string(from: checkedAt))"
    }
}

struct AreaRegistry: Codable, Sendable, Equatable {
    var state: String = "ok"
    var areas: [Area] = []
    var shared: [String] = []
    var hint: String? = nil
}

#if os(iOS)
struct Area: Codable, Identifiable, Sendable, Equatable {
    struct Summary: Codable, Sendable, Equatable {
        var exists: Bool = false
        var lines: [String] = []
        var changedAt: Double? = nil
        var hint: String? = nil
    }
    let id: String
    var name: String
    var leader: String
    var leaderName: String
    var emoji: String = ""
    var specialists: [String] = []
    var summary: Summary = Summary()
    var mitarbeiter: [Mitarbeiter]? = nil
}

struct Mitarbeiter: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var zustaendig: String = ""
    var sitzung: String = ""
}
#else
struct Area: Codable, Identifiable, Sendable, Equatable {
    struct Summary: Codable, Sendable, Equatable {
        var exists: Bool = false
        var lines: [String] = []
        var changedAt: Double? = nil
        var hint: String? = nil
    }
    let id: String
    var name: String
    var leader: String
    var leaderName: String
    var emoji: String = ""
    var specialists: [String] = []
    var summary: Summary = Summary()
    var mitarbeiter: [Mitarbeiter] = []

    struct Mitarbeiter: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var name: String
        var zustaendig: String = ""
        var sitzung: String = ""
    }
}
#endif

struct SenecaTask: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var isDone: Bool
    var status: String = "todo"
    var updatedAt: Double? = nil
    var notes: String? = nil
    var isParked: Bool = false
    var completedAt: Double? = nil
    var priority: String? = nil
    var rawTitle: String? = nil
    var fullTitle: String { rawTitle ?? title }
    var projektId: String? = nil
    var projektName: String? = nil
    var bereichId: String? = nil
    var bereichName: String? = nil
    var plan: String? = nil
    var frist: String? = nil
    var projektFaellig: String? = nil
}

enum TerminKennung {
    static func vergeben(_ termine: [(start: Date, title: String)]) -> [String] {
        var gesehen: [String: Int] = [:]
        return termine.map { t in
            let basis = "\(Int(t.start.timeIntervalSince1970.rounded(.down)))-\(t.title)"
            let n = (gesehen[basis] ?? 0) + 1
            gesehen[basis] = n
            return n == 1 ? basis : "\(basis)-\(n)"
        }
    }
}

struct CalendarEntry: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date? = nil
    var calendar: String? = nil
    var isAllDay: Bool = false
}

struct AgentJob: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var agentId: String
    var enabled: Bool
    var kind: String
    var expr: String? = nil
    var tz: String? = nil
    var everyMs: Double? = nil
    var anchorMs: Double? = nil
    var lastRunAtMs: Double? = nil
    var nextRunAtMs: Double? = nil
    var displayName: String? = nil
    var lastRunStatus: String? = nil
    var lastError: String? = nil
    var lastDiagnosticsSummary: String? = nil
    var lastDeliveryStatus: String? = nil
    var lastDurationMs: Double? = nil
    var deliveryMode: String? = nil
}

struct Briefing: Codable, Identifiable, Sendable {
    let id: String
    var title: String
    var body: String
    var date: Date
}

struct DayRecord: Codable, Sendable, Equatable {
    var routine: Bool
    var erledigt: Int
    var aktualisiert: Double
}

enum SenecaPayloadParser {
    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        }
        if let string = value as? String {
#if os(iOS)
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter.date(from: string)
#else
            return IsoZeit.datum(string)
#endif
        }
        return nil
    }

    static func calendar(_ result: [String: Any]) -> [CalendarEntry] {
        let list = (result["termine"] as? [[String: Any]] ?? []).compactMap { entry -> CalendarEntry? in
            guard let title = entry["titel"] as? String, let start = date(entry["start"]) else { return nil }
            return CalendarEntry(id: "", title: title, start: start, end: date(entry["ende"]), calendar: entry["kalender"] as? String, isAllDay: entry["ganztags"] as? Bool ?? false)
        }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        let ids = TerminKennung.vergeben(list.map { ($0.start, $0.title) })
        return zip(list, ids).map { entry, id in CalendarEntry(id: id, title: entry.title, start: entry.start, end: entry.end, calendar: entry.calendar, isAllDay: entry.isAllDay) }
    }

    static func jobs(_ result: [String: Any]) -> [AgentJob] {
        (result["jobs"] as? [[String: Any]] ?? []).compactMap { job in
            guard let id = job["id"] as? String else { return nil }
            let schedule = job["schedule"] as? [String: Any] ?? [:]
            let state = job["state"] as? [String: Any] ?? [:]
            let name = job["displayName"] as? String ?? job["name"] as? String ?? ""
            return AgentJob(
                id: id, name: name, agentId: job["agentId"] as? String ?? "",
                enabled: job["enabled"] as? Bool ?? true,
                kind: schedule["kind"] as? String ?? "",
                expr: schedule["expr"] as? String, tz: schedule["tz"] as? String,
                everyMs: (schedule["everyMs"] as? NSNumber)?.doubleValue,
                anchorMs: (schedule["anchorMs"] as? NSNumber)?.doubleValue,
                lastRunAtMs: (state["lastRunAtMs"] as? NSNumber)?.doubleValue,
                nextRunAtMs: (state["nextRunAtMs"] as? NSNumber)?.doubleValue,
                displayName: job["displayName"] as? String,
                lastRunStatus: state["lastRunStatus"] as? String,
                lastError: state["lastError"] as? String,
                lastDiagnosticsSummary: (state["lastDiagnostics"] as? [String: Any])?["summary"] as? String,
                lastDeliveryStatus: state["lastDeliveryStatus"] as? String,
                lastDurationMs: (state["lastDurationMs"] as? NSNumber)?.doubleValue,
                deliveryMode: (job["delivery"] as? [String: Any])?["mode"] as? String)
        }
    }

    static func cards(_ result: [String: Any]) -> [WorkCard] {
        (result["cards"] as? [[String: Any]] ?? []).compactMap { card in
            let metadata = card["metadata"] as? [String: Any]
#if os(iOS)
            if let archived = metadata?["archivedAt"] ?? card["archivedAt"], !(archived is NSNull) { return nil }
            if card["archived"] as? Bool == true { return nil }
#else
            if let archived = metadata?["archivedAt"], !(archived is NSNull) { return nil }
#endif
            guard let id = card["id"] as? String else { return nil }
            let automation = metadata?["automation"] as? [String: Any]
#if os(iOS)
            let ereignisse = card["events"] as? [[String: Any]] ?? []
            if ereignisse.last?["kind"] as? String == "archived" { return nil }
            let lauf = card["execution"] as? [String: Any]
            let zeichen = ([(lauf?["updatedAt"] as? NSNumber)?.doubleValue] + ereignisse.suffix(3).map { ($0["at"] as? NSNumber)?.doubleValue }).compactMap { $0 }.max()
            return WorkCard(id: id, title: card["title"] as? String ?? "", status: card["status"] as? String ?? "todo",
                            agentId: card["agentId"] as? String, sessionKey: card["sessionKey"] as? String,
                            boardId: automation?["boardId"] as? String ?? "default",
                            updatedAt: (card["updatedAt"] as? NSNumber)?.doubleValue,
                            priority: card["priority"] as? String, notes: card["notes"] as? String,
                            labels: (card["labels"] as? [Any])?.compactMap { $0 as? String },
                            startedAt: ((lauf?["startedAt"] ?? card["startedAt"]) as? NSNumber)?.doubleValue, lebenszeichen: zeichen,
                            stand: automation?["summary"] as? String)
#else
            return WorkCard(id: id, title: card["title"] as? String ?? "", status: card["status"] as? String ?? "todo",
                            agentId: card["agentId"] as? String, sessionKey: card["sessionKey"] as? String,
                            boardId: automation?["boardId"] as? String ?? "default",
                            updatedAt: (card["updatedAt"] as? NSNumber)?.doubleValue,
                            priority: card["priority"] as? String, notes: card["notes"] as? String,
                            labels: (card["labels"] as? [Any])?.compactMap { $0 as? String })
#endif
        }
    }

    static func sessions(_ result: [String: Any]) -> [SessionRow] {
        (result["sessions"] as? [[String: Any]] ?? []).compactMap { row in
            guard let key = row["key"] as? String else { return nil }
            return SessionRow(key: key, agentId: row["agentId"] as? String, status: row["status"] as? String,
                              lastRunError: row["lastRunError"] as? String)
        }
    }

    static func seen(_ result: [String: Any]) -> [String: Double]? {
        guard let raw = result["gesehen"] as? [String: Any] else { return nil }
        var out: [String: Double] = [:]
        for (k, v) in raw { out[k] = (v as? NSNumber)?.doubleValue ?? 0 }
        return out
    }

    static func agentNames(_ result: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for a in result["agents"] as? [[String: Any]] ?? [] {
            guard let id = a["id"] as? String else { continue }
            let identity = (a["identity"] as? [String: Any])?["name"] as? String
#if os(iOS)
            if let name = [identity, a["name"] as? String].compactMap({ $0?.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) { out[id] = name.lowercased().contains("abgeschaltet") ? "Seneca" : name }
#else
            if let name = [identity, a["name"] as? String].compactMap({ $0?.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) { out[id] = name }
#endif
        }
        return out
    }

    static func calendarStatus(_ result: [String: Any]) -> CalendarStatus {
        CalendarStatus(ok: result["ok"] as? Bool != false, checkedAt: result["geprueftAm"] as? String, hint: result["hinweis"] as? String)
    }

    static func areas(_ result: [String: Any]) -> AreaRegistry {
        func text(_ v: Any?, _ max: Int = 120) -> String { (v as? String).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max)) } ?? "" }
        guard let list = result["bereiche"] as? [[String: Any]] else { return AreaRegistry(state: "unbekannt") }
        var ids = Set<String>()
        var areas: [Area] = []
        for b in list {
            let id = text(b["id"], 64), leader = text(b["leiter"], 64)
            guard !id.isEmpty, !leader.isEmpty, !ids.contains(id) else { continue }
            ids.insert(id)
            let name = text(b["name"]).isEmpty ? id : text(b["name"])
            let ks = b["kurzstand"] as? [String: Any] ?? [:]
#if os(iOS)
            areas.append(Area(
                id: id, name: name, leader: leader,
                leaderName: text(b["leiterName"]).isEmpty ? "Seneca" : text(b["leiterName"]),
                emoji: text(b["emoji"], 16),
                specialists: (b["spezialisten"] as? [Any] ?? []).map { text($0, 64) }.filter { !$0.isEmpty },
                summary: .init(exists: ks["vorhanden"] as? Bool ?? false,
                               lines: Array((ks["zeilen"] as? [Any] ?? []).compactMap { $0 as? String }.prefix(3)),
                               changedAt: (ks["geaendertAm"] as? NSNumber)?.doubleValue,
                               hint: ks["hinweis"] as? String),
                mitarbeiter: (b["mitarbeiter"] as? [[String: Any]]).map { liste in
                    liste.compactMap { m in
                        let mid = text(m["id"], 64), mname = text(m["name"])
                        return mid.isEmpty || mname.isEmpty ? nil : Mitarbeiter(id: mid, name: mname, zustaendig: text(m["zustaendig"], 400), sitzung: text(m["sitzung"], 120))
                    }
                }))
#else
            areas.append(Area(
                id: id, name: name, leader: leader,
                leaderName: text(b["leiterName"]).isEmpty ? name : text(b["leiterName"]),
                emoji: text(b["emoji"], 16),
                specialists: (b["spezialisten"] as? [Any] ?? []).map { text($0, 64) }.filter { !$0.isEmpty },
                summary: .init(exists: ks["vorhanden"] as? Bool ?? false,
                               lines: Array((ks["zeilen"] as? [Any] ?? []).compactMap { $0 as? String }.prefix(3)),
                               changedAt: (ks["geaendertAm"] as? NSNumber)?.doubleValue,
                               hint: ks["hinweis"] as? String),
                mitarbeiter: (b["mitarbeiter"] as? [[String: Any]] ?? []).compactMap { m in
                    let mid = text(m["id"], 64)
                    guard !mid.isEmpty else { return nil }
                    return Area.Mitarbeiter(id: mid, name: text(m["name"]).isEmpty ? mid : text(m["name"]), zustaendig: text(m["zustaendig"], 400), sitzung: text(m["sitzung"], 160))
                }))
#endif
        }
        let state = ["ok", "fehlt", "fehlerhaft"].contains(result["registry"] as? String ?? "") ? result["registry"] as! String : "ok"
        let shared = (result["geteilt"] as? [Any] ?? []).map { text($0, 64) }.filter { !$0.isEmpty }
        return AreaRegistry(state: state, areas: areas, shared: shared, hint: result["hinweis"] as? String)
    }

    static func leaders(_ result: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for b in result["bereiche"] as? [[String: Any]] ?? [] {
            if let id = b["leiter"] as? String, let name = b["leiterName"] as? String { out[id] = name }
        }
        return out
    }

    static func days(_ result: [String: Any]) -> [String: DayRecord] {
        var out: [String: DayRecord] = [:]
        for (key, value) in result["tage"] as? [String: Any] ?? [:] {
            guard let v = value as? [String: Any] else { continue }
            out[key] = DayRecord(routine: v["routine"] as? Bool ?? false,
                                 erledigt: (v["erledigt"] as? NSNumber)?.intValue ?? 0,
                                 aktualisiert: (v["aktualisiert"] as? NSNumber)?.doubleValue ?? 0)
        }
        return out
    }
}
