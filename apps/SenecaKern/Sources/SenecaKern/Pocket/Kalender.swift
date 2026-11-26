import Foundation

struct KalenderTermin: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendar: String? = nil
    var isAllDay = false
    var place: String? = nil
    var note: String? = nil
}

enum KalenderParser {
    static func termine(_ result: [String: Any]) -> [KalenderTermin] {
        func text(_ v: Any?) -> String? {
            guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        return kennungen((result["termine"] as? [[String: Any]] ?? []).compactMap { e in
            guard let title = text(e["titel"]), let start = SenecaPayloadParser.date(e["start"]) else { return nil }
            let allDay = e["ganztags"] as? Bool ?? false
            let end = SenecaPayloadParser.date(e["ende"]).map { max($0, start) } ?? start.addingTimeInterval(allDay ? 86_400 : 3600)
            return KalenderTermin(id: "", title: title, start: start, end: end,
                                  calendar: text(e["kalender"]), isAllDay: allDay, place: text(e["ort"]), note: text(e["notiz"]))
        })
    }

    static func from(_ entries: [CalendarEntry]) -> [KalenderTermin] {
        kennungen(entries.map {
            KalenderTermin(id: $0.id, title: $0.title, start: $0.start, end: max($0.end ?? $0.start.addingTimeInterval(3600), $0.start),
                           calendar: $0.calendar, isAllDay: $0.isAllDay)
        })
    }

    static func eintraege(_ termine: [KalenderTermin]) -> [CalendarEntry] {
        termine.map { CalendarEntry(id: $0.id, title: $0.title, start: $0.start, end: $0.end, calendar: $0.calendar, isAllDay: $0.isAllDay) }
    }

    static func kennungen(_ termine: [KalenderTermin]) -> [KalenderTermin] {
        let sorted = termine.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return zip(sorted, TerminKennung.vergeben(sorted.map { ($0.start, $0.title) })).map { t, id in
            var t = t
            t.id = id
            return t
        }
    }
}

struct KalenderItem: Equatable, Identifiable {
    enum Kind: Equatable { case termin, routine, ganztags, lauf }
    var id: String
    var title: String
    var start: Date
    var end: Date
    var kind: Kind
    var calendar: String? = nil
    var place: String? = nil
    var note: String? = nil
    var agentId: String? = nil
    var jobId: String? = nil
    var steps: [KalenderItem] = []
    var isTimed: Bool { kind != .ganztags }
}

enum KalenderStufe: String, CaseIterable {
    case tag, woche, monat
}

enum KalenderLogic {
    static let horizon = 42

    static func iso(_ cal: Calendar) -> Calendar {
        var c = cal
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }
    static func day(_ offset: Int, from now: Date, _ cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }
    static func dayEnd(_ dayStart: Date, _ cal: Calendar) -> Date { cal.date(byAdding: .day, value: 1, to: dayStart)! }
    static func dayOffset(of date: Date, from now: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }
    static func weekStart(_ date: Date, _ cal: Calendar) -> Date {
        let c = iso(cal)
        return c.dateInterval(of: .weekOfYear, for: date)?.start ?? c.startOfDay(for: date)
    }
    static func weekDays(_ weekStart: Date, _ cal: Calendar) -> [Date] {
        (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart)! }
    }
    static func week(_ offset: Int, from now: Date, _ cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: 7 * offset, to: weekStart(now, cal))!
    }
    static func weekOffset(of date: Date, from now: Date, _ cal: Calendar) -> Int {
        let days = cal.dateComponents([.day], from: weekStart(now, cal), to: weekStart(date, cal)).day ?? 0
        return Int((Double(days) / 7).rounded(.down))
    }
    static func weekNumber(_ date: Date, _ cal: Calendar) -> Int { iso(cal).component(.weekOfYear, from: date) }
    static func monthStart(_ date: Date, _ cal: Calendar) -> Date { cal.dateInterval(of: .month, for: date)?.start ?? cal.startOfDay(for: date) }
    static func month(_ offset: Int, from now: Date, _ cal: Calendar) -> Date {
        cal.date(byAdding: .month, value: offset, to: monthStart(now, cal))!
    }
    static func monthOffset(of date: Date, from now: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.month], from: monthStart(now, cal), to: monthStart(date, cal)).month ?? 0
    }
    static func monthWeeks(_ monthStart: Date, _ cal: Calendar) -> [Date] {
        let end = cal.date(byAdding: .month, value: 1, to: monthStart)!
        var out: [Date] = []
        var w = weekStart(monthStart, cal)
        while w < end {
            out.append(w)
            w = cal.date(byAdding: .day, value: 7, to: w)!
        }
        return out
    }
    static func maxIndex(_ stufe: KalenderStufe, now: Date, _ cal: Calendar) -> Int {
        let last = day(horizon - 1, from: now, cal)
        switch stufe {
        case .tag: return horizon - 1
        case .woche: return weekOffset(of: last, from: now, cal)
        case .monat: return monthOffset(of: last, from: now, cal)
        }
    }

    static func isRoutine(_ t: KalenderTermin) -> Bool {
        (t.calendar ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "routine" || t.title.lowercased().contains("#routine")
    }

    static func items(on day: Date, termine: [KalenderTermin], jobs: [AgentJob], _ cal: Calendar) -> [KalenderItem] {
        let start = cal.startOfDay(for: day)
        let end = dayEnd(start, cal)
        var allDay: [KalenderItem] = []
        var seen = Set<String>()
        var timed: [KalenderItem] = []
        var routine: [KalenderItem] = []
        for t in termine {
            if t.isAllDay {
                guard t.start < end, t.end > start else { continue }
                let key = t.title.lowercased().filter { !$0.isWhitespace }
                guard seen.insert(key).inserted else { continue }
                allDay.append(KalenderItem(id: "g-\(t.id)", title: t.title, start: t.start, end: t.end, kind: .ganztags,
                                           calendar: t.calendar, place: t.place, note: t.note))
                continue
            }
            guard t.start >= start, t.start < end else { continue }
            let item = KalenderItem(id: "t-\(t.id)", title: t.title, start: t.start, end: max(t.end, t.start), kind: .termin,
                                    calendar: t.calendar, place: t.place, note: t.note)
            if isRoutine(t) { routine.append(item) } else { timed.append(item) }
        }
        if let first = routine.map(\.start).min(), let last = routine.map(\.end).max() {
            timed.append(KalenderItem(id: "r-\(DayLogic.dayKey(start, cal))", title: "Morgenroutine", start: first, end: last, kind: .routine,
                                      calendar: routine.first?.calendar, steps: routine.sorted { $0.start < $1.start }))
        }
        for job in jobs {
            for t in DayLogic.runTimes(job, from: start, to: end) {
                timed.append(KalenderItem(id: "l-\(job.id)-\(Int(t.timeIntervalSince1970))", title: DayLogic.jobTitle(job.name), start: t,
                                          end: t.addingTimeInterval(DayLogic.runLength), kind: .lauf, agentId: job.agentId, jobId: job.id))
            }
        }
        timed.sort { a, b in
            if a.start != b.start { return a.start < b.start }
            return a.kind != .lauf && b.kind == .lauf
        }
        return allDay + timed
    }

    static func merge(short: [KalenderTermin], long: [KalenderTermin], shortAt: Date? = nil, longAt: Date? = nil,
                      _ cal: Calendar = .current) -> [KalenderTermin] {
        func same(_ a: KalenderTermin, _ b: KalenderTermin) -> Bool { a.title == b.title && abs(a.start.timeIntervalSince(b.start)) < 60 }
        var out = long
        if let shortAt, let longAt {
            guard shortAt > longAt else { return out.sorted { $0.start < $1.start } }
            let from = cal.startOfDay(for: shortAt)
            let to = cal.date(byAdding: .day, value: 2, to: from) ?? from
            out.removeAll { l in !l.isAllDay && l.start >= from && l.start < to && !short.contains { same($0, l) } }
        }
        for s in short where !s.isAllDay {
            if !out.contains(where: { same($0, s) }) { out.append(s) }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func gemeinsam(kurz: [CalendarEntry], lang: [KalenderTermin]?, kurzAm: Date?, langAm: Date?,
                          _ cal: Calendar = .current) -> [KalenderTermin] {
        let short = KalenderParser.from(kurz)
        guard let lang else { return short }
        return KalenderParser.kennungen(merge(short: short, long: lang, shortAt: kurzAm, longAt: langAm, cal))
    }

    static func isRunning(_ item: KalenderItem, now: Date) -> Bool { item.isTimed && item.start <= now && now < item.end }

    static let weekdayShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let weekdayLong = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]

    static func shortDay(_ date: Date, _ cal: Calendar) -> (weekday: String, day: String) {
        let c = cal.dateComponents([.weekday, .day], from: date)
        return (weekdayShort[(c.weekday ?? 1) - 1], "\(c.day ?? 1)")
    }
    static func monthName(_ date: Date, _ cal: Calendar) -> String { months[(cal.component(.month, from: date)) - 1] }

    static func weekRange(_ weekStart: Date, _ cal: Calendar) -> String {
        let last = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let a = cal.dateComponents([.day, .month], from: weekStart), b = cal.dateComponents([.day, .month], from: last)
        if a.month == b.month { return "\(a.day!). bis \(b.day!). \(months[b.month! - 1])" }
        return "\(a.day!). \(months[a.month! - 1]) bis \(b.day!). \(months[b.month! - 1])"
    }
    static func weekSpan(_ weekStart: Date, _ cal: Calendar) -> String {
        let last = cal.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(cal.component(.day, from: weekStart)). – \(cal.component(.day, from: last))."
    }
    static func weekLine(_ weekStart: Date, _ cal: Calendar) -> String { "Woche \(weekNumber(weekStart, cal)) · \(weekRange(weekStart, cal))" }
    static func monthLine(_ monthStart: Date, _ cal: Calendar) -> String { "\(monthName(monthStart, cal)) \(cal.component(.year, from: monthStart))" }

    static func duration(_ start: Date, _ end: Date) -> String {
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return m == 1 ? "eine Minute" : "\(m) Minuten" }
        if m == 0 { return h == 1 ? "eine Stunde" : "\(h) Stunden" }
        if h == 1 && m == 30 { return "anderthalb Stunden" }
        return (h == 1 ? "eine Stunde" : "\(h) Stunden") + " \(m) Minuten"
    }

    static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static let unknownDay = "Sobald dein Mac erreichbar ist, lade ich die nächsten Wochen."

    static func fromAgent(_ id: String?, _ leaders: [String: String]) -> String {
        let who = DayLogic.agentName(id, leaders)
        if who == "ein Mitarbeiter" { return "von einem deiner Agenten" }
#if os(iOS)
        if who.hasPrefix("der ") { return "vom " + NeedsYou.dativ(String(who.dropFirst(4))) }
#else
        if who.hasPrefix("der ") { return "vom " + who.dropFirst(4) }
#endif
        return "von \(who)"
    }

    static func details(_ item: KalenderItem, leaders: [String: String], _ cal: Calendar) -> [String] {
        var out: [String]
        switch item.kind {
        case .ganztags:
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: item.start), to: cal.startOfDay(for: item.end)).day ?? 1
            out = [days > 1 ? "Ganztägig, \(DayLogic.word(days)) Tage lang." : "Ganztägig."]
        case .termin:
            out = ["\(DayLogic.hm(item.start, cal)) bis \(DayLogic.hm(item.end, cal)), \(duration(item.start, item.end))."]
        case .routine:
            return item.steps.map { "\(DayLogic.hm($0.start, cal))  \($0.title)" }
        case .lauf:
            return ["Ein Lauf \(fromAgent(item.agentId, leaders))."]
        }
        if let k = item.calendar, k.lowercased() != "kalender" { out.append("Im Kalender „\(k)“.") }
        if let p = item.place { out.append(p) }
        if let n = item.note { out.append(n) }
        return out
    }
}

#if DEBUG
enum KalenderDemo {
    static func termine(now: Date, _ cal: Calendar) -> [KalenderTermin] {
        let today = cal.startOfDay(for: now)
        func dayStart(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: today)! }
        func at(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(byAdding: .minute, value: h * 60 + m, to: dayStart(d))! }
        var out: [KalenderTermin] = []
        let routine = [("Aufwachen", 300, 315, "Start des Morgens. Ersetzt keinen Wecker."), ("Laufen", 330, 390, ""), ("Lesen", 390, 450, ""),
                       ("Programmieren lernen", 450, 480, ""), ("To-Dos sichten", 480, 495, "Beginn des Arbeitstags.")]
        for d in 0..<KalenderLogic.horizon {
            for (t, s, e, note) in routine {
                out.append(KalenderTermin(id: "demo-\(d)-\(t)", title: t, start: at(d, 0, s), end: at(d, 0, e), calendar: "Routine",
                                          note: note.isEmpty ? nil : note))
            }
        }
        func termin(_ d: Int, _ h: Int, _ m: Int, _ minutes: Int, _ title: String, _ kal: String = "Arbeit", place: String? = nil, note: String? = nil) {
            out.append(KalenderTermin(id: "demo-t-\(d)-\(title)", title: title, start: at(d, h, m), end: at(d, h, m + minutes), calendar: kal, place: place, note: note))
        }
        func ganztags(_ d: Int, _ days: Int, _ title: String, _ kal: String, place: String? = nil, note: String? = nil) {
            out.append(KalenderTermin(id: "demo-g-\(d)-\(title)", title: title, start: dayStart(d), end: dayStart(d + days), calendar: kal, isAllDay: true, place: place, note: note))
        }
        termin(0, 10, 0, 45, "Abstimmung Sundartha", place: "Telefon", note: "Website-Texte und den Termin für den Relaunch klären.")
        termin(0, 15, 30, 60, "Kaffee mit Lena", "Privat", place: "Café Lorenz, Lindenstraße 12")
        termin(2, 9, 30, 90, "Workshop Vodafone", place: "Düsseldorf, Ferdinand-Braun-Platz 1")
        termin(2, 18, 30, 120, "Abendessen mit Lena", "Privat", place: "Trattoria da Enzo")
        termin(3, 11, 0, 30, "Rückruf Steuerberater", "Privat")
        termin(6, 14, 0, 60, "Review Power BI", note: "Dashboards für das Quartal durchgehen.")
        ganztags(8, 5, "Airbnb, Milano", "Kalender", place: "Via Gian Giacomo Mora 9, Mailand", note: "Check-in ab 15 Uhr, Check-out bis 10 Uhr.")
        termin(8, 7, 10, 95, "Flug nach Mailand", "Privat", place: "Flughafen Düsseldorf, Terminal B")
        ganztags(9, 1, "Geburtstag Julia", "Kalender")
        if let okt31 = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 10, day: 31)),
           let ende = cal.date(byAdding: .day, value: -(cal.component(.weekday, from: okt31) - 1), to: okt31),
           let abstand = cal.dateComponents([.day], from: today, to: ende).day, (0..<KalenderLogic.horizon).contains(abstand) {
            ganztags(abstand, 1, "Ende der Sommerzeit", "Feiertage")
        }
        termin(16, 10, 0, 60, "Quartalsgespräch", place: "Büro")
        ganztags(20, 1, "Reformationstag", "Feiertage")
        ganztags(21, 1, "Allerheiligen", "Feiertage")
        termin(23, 16, 0, 45, "Physiotherapie", "Privat")
        termin(27, 9, 0, 240, "Strategietag Sundartha", place: "Köln")
        ganztags(35, 1, "Osman Geburtstag", "Kalender")
        return out.sorted { $0.start < $1.start }
    }

    static func vergangen(now: Date, tage: Int, _ cal: Calendar) -> [KalenderTermin] {
        let today = cal.startOfDay(for: now)
        var out: [KalenderTermin] = []
        let routine = [("Aufwachen", 300, 315), ("Laufen", 330, 390), ("Lesen", 390, 450), ("Programmieren lernen", 450, 480), ("To-Dos sichten", 480, 495)]
        let titel = ["Jour fixe Vodafone", "Abstimmung Sundartha", "Workshop Newsletter", "Friseur", "Review Power BI", "Mittagessen mit Jonas",
                     "Zahnreinigung", "Telefonat Hosting", "Abendessen bei den Eltern"]
        for d in 1...max(1, tage) {
            let day = cal.date(byAdding: .day, value: -d, to: today)!
            func at(_ min: Int) -> Date { cal.date(byAdding: .minute, value: min, to: day)! }
            for (t, s, e) in routine {
                out.append(KalenderTermin(id: "demo-v-\(d)-\(t)", title: t, start: at(s), end: at(e), calendar: "Routine"))
            }
            let wochentag = cal.component(.weekday, from: day)
            guard wochentag != 1, wochentag != 7 else { continue }
            let n = 1 + (d * 7) % 3
            for i in 0..<n {
                let t = titel[(d * 5 + i * 4) % titel.count]
                let start = (9 + i * 3 + d % 2) * 60 + (d % 3) * 15
                out.append(KalenderTermin(id: "demo-v-\(d)-t\(i)", title: t, start: at(start), end: at(start + 45 + (d % 4) * 15), calendar: "Arbeit"))
            }
        }
        if let einheit = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 10, day: 3)), einheit < today {
            out.append(KalenderTermin(id: "demo-v-einheit", title: "Tag der Deutschen Einheit", start: einheit,
                                      end: cal.date(byAdding: .day, value: 1, to: einheit)!, calendar: "Feiertage", isAllDay: true))
        }
        return out.sorted { $0.start < $1.start }
    }

    static func tage(now: Date, _ cal: Calendar) -> [String: DayRecord] {
        let today = cal.startOfDay(for: now)
        var out: [String: DayRecord] = [:]
        for d in 1...62 {
            let day = cal.date(byAdding: .day, value: -d, to: today)!
            out[DayLogic.dayKey(day, cal)] = DayRecord(routine: d % 9 != 4 && d % 13 != 6, erledigt: (d * 7) % 4, aktualisiert: 1)
        }
        return out
    }

    static func voll(now: Date, _ cal: Calendar) -> [KalenderTermin] {
        let today = cal.startOfDay(for: now)
        func at(_ h: Int, _ m: Int) -> Date { cal.date(byAdding: .minute, value: h * 60 + m, to: today)! }
        let liste: [(String, Int, Int, Int, String?)] = [
            ("Telefonat Hosting", 8, 30, 20, nil), ("Standup Website-Team", 9, 0, 15, "Video"), ("Angebot Vodafone durchgehen", 11, 0, 60, nil),
            ("Mittagessen mit Jonas", 12, 15, 60, "Kantine am Hafen"), ("Interview Kandidatin Design", 13, 30, 45, "Büro"),
            ("Design-Review Website", 14, 30, 60, "mit dem Website-Team"), ("Rückruf Steuerberater", 16, 45, 20, nil),
            ("Physiotherapie", 17, 30, 45, "Praxis am Markt"), ("Elternabend", 19, 30, 90, "Grundschule Lindenstraße"),
            ("Konzert in der Tonhalle", 21, 15, 105, nil),
        ]
        return liste.map { t, h, m, minuten, ort in
            KalenderTermin(id: "demo-voll-\(t)", title: t, start: at(h, m), end: at(h, m + minuten), calendar: "Arbeit", place: ort)
        }
    }
}
#endif
