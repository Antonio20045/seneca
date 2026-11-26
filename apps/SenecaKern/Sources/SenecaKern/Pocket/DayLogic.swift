import Foundation
import CoreText

struct DayItem: Equatable, Identifiable, Sendable {
    enum Kind: Sendable { case termin, lauf }
    var id: String
    var title: String
    var start: Date
    var end: Date
    var kind: Kind
    var agentId: String? = nil
    var isRoutine: Bool = false
}

struct SatzStueck: Equatable {
    var text: String
    var akzent: Bool
}

struct HeroText: Equatable, Sendable {
    enum Mode: Sendable { case plain }
    var line1: String
    var line2Prefix: String
    var emphasis: String
    var line2Suffix: String
    var sub: String
    var mode: Mode
    var key: String { line1 + "|" + line2Prefix + emphasis + line2Suffix }
}

struct DayInput {
    var now: Date
    var calendar: Calendar
    var entries: [CalendarEntry]
    var jobs: [AgentJob]
    var leaders: [String: String]
    var tasks: [SenecaTask]
    var days: [String: DayRecord]
    var routineDoneToday: Bool
    var needs: NeedsInput? = nil
}

struct DayState: Equatable {
    var dayKey: String
    var dateLine: String
    var agenda: [DayItem]
    var routineDetail: String
    var routineDone: Bool
    var todos: [SenecaTask]
    var doneCount: Int
    var progress: Double
    var needs: [NeedsItem] = []
    var needsLine: String? = nil
    var needsDetail: String? = nil
    var needsKurz: String? = nil
    var entries: [CalendarEntry] = []
    var jobs: [AgentJob] = []
    var leaders: [String: String] = [:]
}

enum DayLogic {
    static let runLength: TimeInterval = 15 * 60

    static func dayKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func dateLine(_ date: Date, _ cal: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "EEEE, d. MMMM"
        return f.string(from: date)
    }
    static func hm(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour!, c.minute!)
    }

    static func offlineSatz(stand: Date?, now: Date, wartend: Int = 0, _ cal: Calendar) -> String {
        let s = "Dein Mac ist gerade nicht erreichbar"
        if wartend > 0 {
            return s + (wartend == 1 ? "; eine Änderung wartet, bis er wieder da ist."
                        : "; \(word(wartend)) Änderungen warten, bis er wieder da ist.")
        }
        guard let stand, now.timeIntervalSince(stand) >= 5 * 60 else { return s + ", Seneca versucht es weiter." }
        let zeit = uhr(stand, cal)
        if cal.isDate(stand, inSameDayAs: now) { return s + "; das hier ist der Stand von \(zeit)." }
        if let gestern = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(stand, inSameDayAs: gestern) {
            return s + "; das hier ist der Stand von gestern, \(zeit)."
        }
        let c = cal.dateComponents([.day, .month], from: stand)
        return s + "; das hier ist der Stand vom \(c.day!).\(c.month!)., \(zeit)."
    }
    static func uhr(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return c.minute! == 0 ? "\(c.hour!) Uhr" : String(format: "%d:%02d Uhr", c.hour!, c.minute!)
    }
    static let numberWords = ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"]
    static func word(_ n: Int) -> String { n >= 0 && n < numberWords.count ? numberWords[n] : String(n) }

    static func isRoutine(_ e: CalendarEntry) -> Bool {
        (e.calendar ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "routine"
            || e.title.lowercased().contains("#routine")
    }

    static func jobTitle(_ raw: String) -> String {
        var t = raw
        while let first = t.unicodeScalars.first, first.properties.isEmojiPresentation || first.properties.isEmoji && first.value > 0x2000 || first == "\u{FE0F}" || first == " " {
            t.unicodeScalars.removeFirst()
        }
        for pattern in [#"\s+[—–-]\s+täglicher Check$"#, #"\s+mit Anruf$"#, #"^Telco-Radar · "#] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func runTimes(_ job: AgentJob, from start: Date, to end: Date) -> [Date] {
        guard job.enabled, !job.agentId.isEmpty else { return [] }
        if job.kind == "every", let every = job.everyMs, every > 0, every <= 3_600_000 { return [] }
        var times: [Date] = []
        if job.kind == "cron", let expr = job.expr, let cron = CronExpression(expr) {
            let tz = job.tz.flatMap(TimeZone.init(identifier:)) ?? .current
            times = cron.occurrences(from: start, to: end, timeZone: tz)
        } else if job.kind == "every", let every = job.everyMs, every > 0, let anchor = job.anchorMs {
            var t = anchor / 1000
            let s = start.timeIntervalSince1970, e = end.timeIntervalSince1970
            if t < s { t += ceil((s - t) / (every / 1000)) * (every / 1000) }
            while t < e { times.append(Date(timeIntervalSince1970: t)); t += every / 1000 }
        }
        for ms in [job.lastRunAtMs, job.nextRunAtMs].compactMap({ $0 }) {
            let d = Date(timeIntervalSince1970: ms / 1000)
            if d >= start && d < end { times.append(d) }
        }
        var byMinute: [Int: Date] = [:]
        for t in times { byMinute[Int(t.timeIntervalSince1970 / 60)] = byMinute[Int(t.timeIntervalSince1970 / 60)] ?? t }
        return byMinute.values.sorted()
    }

    static func items(on day: Date, _ input: DayInput) -> [DayItem] {
        let cal = input.calendar
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        var out: [DayItem] = []
        for e in input.entries where !e.isAllDay && e.start >= start && e.start < end {
            out.append(DayItem(id: "t-\(e.id)", title: e.title, start: e.start, end: max(e.end ?? e.start.addingTimeInterval(3600), e.start), kind: .termin, isRoutine: isRoutine(e)))
        }
        for job in input.jobs {
            for t in runTimes(job, from: start, to: end) {
                out.append(DayItem(id: "l-\(job.id)-\(Int(t.timeIntervalSince1970))", title: jobTitle(job.name), start: t, end: t.addingTimeInterval(runLength), kind: .lauf, agentId: job.agentId))
            }
        }
        return out.sorted { $0.start != $1.start ? $0.start < $1.start : ($0.kind == .termin && $1.kind == .lauf) }
    }

    static let priorityRank = ["urgent": 0, "high": 1, "normal": 2, "low": 3]
    static func todosToday(_ tasks: [SenecaTask], dayStart: Date, _ cal: Calendar = .current) -> [SenecaTask] {
        AufgabenLogic.heutigeAufgaben(tasks, jetzt: dayStart, cal)
    }

    static func streakBefore(today: Date, days: [String: DayRecord], _ cal: Calendar) -> Int {
        var n = 0
        var d = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: today))!
        while days[dayKey(d, cal)]?.routine == true {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }
    static func routineDetail(window: (Date, Date)?, _ cal: Calendar) -> String {
        guard let window else { return "" }
        return "\(hm(window.0, cal)) bis \(hm(window.1, cal))"
    }

    static func agentName(_ id: String?, _ leaders: [String: String]) -> String {
        guard let id, !id.isEmpty else { return "ein Mitarbeiter" }
        if id == "main" { return "Seneca" }
#if os(iOS)
        if let name = leaders[id] { return name.hasSuffix("Agent") ? "der \(name)" : name }
#else
        if let name = leaders[id] { return name.hasSuffix("Leiter") ? "der \(name)" : name }
#endif
        return id.prefix(1).uppercased() + id.dropFirst()
    }

    static func state(_ input: DayInput) -> DayState {
        let cal = input.calendar, now = input.now
        let dayStart = cal.startOfDay(for: now)
        let today = items(on: now, input)
        let todos = todosToday(input.tasks, dayStart: dayStart, cal)
        let doneTodos = todos.filter(\.isDone).count
        let done = (input.routineDoneToday ? 1 : 0) + doneTodos
        let routine = today.filter(\.isRoutine)
        let window = routine.isEmpty ? nil : (routine.map(\.start).min()!, routine.map(\.end).max()!)
        var needsInput = input.needs
        needsInput?.now = now
        let needs = needsInput.map(NeedsYou.items) ?? []
        let needsHero = needsInput.flatMap { NeedsYou.hero(needs, $0) }
        return DayState(
            dayKey: dayKey(now, cal),
            dateLine: dateLine(now, cal),
            agenda: Array(today.filter { $0.start > now }.prefix(3)),
            routineDetail: routineDetail(window: window, cal),
            routineDone: input.routineDoneToday,
            todos: todos,
            doneCount: done,
            progress: Double(done) / Double(1 + todos.count),
            needs: needs,
            needsLine: needsHero.map { "\($0.line1) \($0.line2Prefix)\($0.emphasis)\($0.line2Suffix)" },
            needsDetail: needsHero?.sub,
            needsKurz: needsInput.flatMap { NeedsYou.mintZeile(needs, $0) },
            entries: input.entries,
            jobs: input.jobs,
            leaders: input.leaders)
    }

    static func settle(startProgress: Double, progress: Double) -> Double {
#if os(iOS)
        PageGesture.wouldOpen(start: startProgress, progress: progress) ? 1 : 0
#else
        startProgress < 0.5 ? (progress > 0.28 ? 1 : 0) : (progress < 0.72 ? 0 : 1)
#endif
    }
    static func dragProgress(start: Double, translation: Double, travel: Double = 380) -> Double {
        min(1, max(0, start - translation / travel))
    }
}

struct AnswerLayout: Equatable {
    struct Segment: Equatable { var text: String; var italic: Bool }
    struct Row: Equatable { var time: String; var text: String; var day: String = "" }
    var headline: [Segment]
    var rows: [Row]
    var rest: String
    var more: String = ""
}

enum AnswerParser {
    static let coreRows = 4
    static let restLimit = 160
    static let headlineLines = 3
    static let headlineWidth: CGFloat = 334
    static let headlineSize: CGFloat = 38

    static func clean(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }
    static func segments(_ s: String) -> [AnswerLayout.Segment] {
        let normalized = s.replacingOccurrences(of: "**", with: "*").replacingOccurrences(of: "__", with: "*")
        var out: [AnswerLayout.Segment] = []
        for (i, part) in normalized.components(separatedBy: "*").enumerated() where !part.isEmpty {
            out.append(.init(text: part, italic: i % 2 == 1))
        }
        return out
    }

    private static let weekdays = "montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag"
    private static let months = "januar|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember"
    static func splitDay(_ text: String) -> (text: String, day: String) {
        let pattern = #"^(.*\S)\s*,\s*((?:heute|morgen|übermorgen)(?:\s+(?:früh|vormittag|nachmittag|abend))?|(?:am\s+|nächsten\s+|kommenden\s+)?(?:"# + weekdays + #")|(?:am\s+)?\d{1,2}\.\s*(?:\d{1,2}\.(?:\d{2,4})?|(?:"# + months + #")))\.?$"#
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return (text, "") }
        var day = ns.substring(with: m.range(at: 2))
        if ["heute", "morgen", "übermorgen"].contains(where: { day.lowercased().hasPrefix($0) }) { day = day.lowercased() }
        return (ns.substring(with: m.range(at: 1)), day)
    }

    static func firstSentence(_ text: String, min: Int = 8) -> (String, String) {
        var searchStart = text.startIndex
        while let range = text.range(of: #"[.!?…](\s|$)"#, options: .regularExpression, range: searchStart..<text.endIndex) {
            if text.distance(from: text.startIndex, to: range.lowerBound) >= min {
                return (String(text[..<range.upperBound]).trimmingCharacters(in: .whitespaces),
                        String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
            searchStart = range.upperBound
        }
        return (text, "")
    }

    static func rowLine(_ row: AnswerLayout.Row) -> String {
        let text = row.day.isEmpty ? row.text : "\(row.text), \(row.day)"
        return row.time == "–" ? "– \(text)" : "\(row.time) \(text)"
    }

    static func lineCount(_ segments: [AnswerLayout.Segment], width: CGFloat = headlineWidth, size: CGFloat = headlineSize) -> Int {
        let regular = CTFontCreateWithName("InstrumentSerif-Regular" as CFString, size, nil)
        guard CTFontCopyPostScriptName(regular) as String == "InstrumentSerif-Regular" else {
            return max(1, Int((Double(segments.map(\.text).joined().count) / 21).rounded(.up)))
        }
        let italic = CTFontCreateWithName("InstrumentSerif-Italic" as CFString, size, nil)
        let attributed = NSMutableAttributedString()
        for s in segments {
            attributed.append(NSAttributedString(string: s.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): s.italic ? italic : regular,
                NSAttributedString.Key(kCTKernAttributeName as String): -0.01 * size]))
        }
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil), nil)
        return (CTFrameGetLines(frame) as? [CTLine])?.count ?? 1
    }

    private static let splitPoints: [(rank: Int, pattern: String)] = [
        (3, #"\s+[—–-]\s+|;\s+"#),
        (2, #":\s+|,\s+(?:und|oder)\s+|,\s+(?=(?:aber|doch|sondern|denn|jedoch)\b)"#),
        (1, #",\s+(?=(?:weil|dass|wenn|falls|solange|sobald|bevor|nachdem|damit|obwohl|während|ob|sodass|indem|seit|seitdem|bis|als|wie|wo)\b)"#),
        (0, #",\s+(?!(?:der|die|das|dem|den|deren|dessen|denen|welche[rsmn]?)\b)"#),
    ]

    static func splitHeadline(_ sentence: String, fits: (String) -> Bool) -> (head: String, tail: String) {
        let s = sentence.replacingOccurrences(of: "**", with: "*").replacingOccurrences(of: "__", with: "*")
        guard !fits(s) else { return (sentence, "") }
        let ns = s as NSString
        var best: (rank: Int, head: String, tail: String)?
        for (rank, pattern) in splitPoints {
            let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let before = ns.substring(to: m.range.location)
                guard before.filter({ $0 == "*" }).count % 2 == 0 else { continue }
                let headText = before.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:")))
                let tailText = ns.substring(from: m.range.location + m.range.length).trimmingCharacters(in: .whitespaces)
                guard headText.replacingOccurrences(of: "*", with: "").count >= 8,
                      tailText.contains(where: \.isLetter) else { continue }
                let head = headText + "."
                guard fits(head) else { continue }
                if best == nil || rank > best!.rank || (rank == best!.rank && head.count > best!.head.count) {
                    best = (rank, head, capitalized(tailText))
                }
            }
        }
        return best.map { ($0.head, $0.tail) } ?? (sentence, "")
    }

    static func capitalized(_ s: String) -> String {
        guard let i = s.firstIndex(where: \.isLetter) else { return s }
        return s.replacingCharacters(in: i...i, with: s[i].uppercased())
    }

    static func dropUnfinishedLine(_ raw: String) -> String {
        var lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        let stub = try! NSRegularExpression(pattern: #"^\s*(?:[-–•*]|\d+[.)])?\s*(?:\*\*)?(?:\d{1,2}(?:[:.]\d{0,2})?(?:\s*Uhr)?)?(?:\*\*)?\s*[-–—:·|]?\s*$"#)
        if let last = lines.last, lines.count > 1,
           stub.firstMatch(in: last, range: NSRange(location: 0, length: (last as NSString).length)) != nil {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ raw: String) -> AnswerLayout {
        let timeRow = try! NSRegularExpression(pattern: #"^(?:[-–•*]\s*)?(?:\*\*)?(\d{1,2})[:.](\d{2})(?:\s*Uhr)?(?:\*\*)?\s*(?:[-–—:·|]\s*)?(.+)$"#)
        let bullet = try! NSRegularExpression(pattern: #"^(?:[-–•*]|\d+[.)])\s+(.+)$"#)
        var rows: [AnswerLayout.Row] = []
        var prose: [String] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            let line = clean(rawLine)
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            let r = NSRange(location: 0, length: ns.length)
            if let m = timeRow.firstMatch(in: line, range: r), let h = Int(ns.substring(with: m.range(at: 1))), h < 24 {
                let text = ns.substring(with: m.range(at: 3)).replacingOccurrences(of: "*", with: "")
                let split = splitDay(text)
                rows.append(.init(time: String(format: "%d:%@", h, ns.substring(with: m.range(at: 2))), text: split.text, day: split.day))
            } else if let m = bullet.firstMatch(in: line, range: r) {
                rows.append(.init(time: "–", text: ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "*", with: "")))
            } else {
                prose.append(line)
            }
        }
        let text = prose.joined(separator: " ")
        let (first, after) = firstSentence(text)
        let (head, tail) = splitHeadline(first) { lineCount(segments($0)) <= headlineLines }
        var headline = head
        let remaining = [tail, after].filter { !$0.isEmpty }.joined(separator: " ")
        var (rest, moreProse) = firstSentence(remaining, min: 1)
        if rest.count > restLimit {
            moreProse = remaining
            rest = ""
        }
        if headline.isEmpty { headline = rows.isEmpty ? "Ich habe gerade keine Antwort." : "Das habe ich gefunden." }
        let extraRows = rows.dropFirst(coreRows).map(rowLine).joined(separator: "\n")
        let more = [extraRows, moreProse].filter { !$0.isEmpty }.joined(separator: "\n\n").replacingOccurrences(of: "*", with: "")
        return AnswerLayout(headline: segments(headline), rows: Array(rows.prefix(coreRows)),
                            rest: rest.replacingOccurrences(of: "*", with: ""), more: more)
    }

    static func spoken(_ answer: AnswerLayout) -> String {
        func sentence(_ s: String) -> String {
            let t = s.replacingOccurrences(of: " …", with: "").trimmingCharacters(in: .whitespaces)
            guard let last = t.last else { return "" }
            return ".!?…:".contains(last) ? t : t + "."
        }
        var parts = [sentence(answer.headline.map(\.text).joined())]
        for row in answer.rows {
            let time = spokenTime(row.time)
            if row.day.isEmpty {
                parts.append(sentence(time.isEmpty ? row.text : "\(time) \(row.text)"))
            } else {
                let day = row.day.prefix(1).uppercased() + row.day.dropFirst()
                parts.append(sentence(time.isEmpty ? "\(day) \(row.text)" : "\(day) um \(time) \(row.text)"))
            }
        }
        parts.append(sentence(answer.rest))
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func spokenTime(_ hm: String) -> String {
        let parts = hm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return "" }
        return parts[1] == 0 ? "\(parts[0]) Uhr" : "\(parts[0]) Uhr \(parts[1])"
    }

    static func todoIntent(_ text: String) -> String? {
        let re = try! NSRegularExpression(pattern: #"^\s*(?:neues?\s+)?(?:to[\s-]?do|aufgabe)\s*[:,\-–]?\s+(.+?)[.!]?\s*$"#, options: [.caseInsensitive])
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let title = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        guard title.count >= 2 else { return nil }
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}

extension DayLogic {
    struct AusblickTag: Equatable {
        var tag: Date
        var titel: [String]
    }

    static func ausblick(zeilenAufHome: Int, kommende: [AusblickTag], maxAnzahl: Int = 3) -> [AusblickTag] {
        guard zeilenAufHome == 0 else { return [] }
        var rest = maxAnzahl
        var aus: [AusblickTag] = []
        for tag in kommende where rest > 0 && !tag.titel.isEmpty {
            let titel = Array(tag.titel.prefix(rest))
            aus.append(AusblickTag(tag: tag.tag, titel: titel))
            rest -= titel.count
        }
        return aus
    }

    static func wann(_ tag: Date, jetzt: Date, _ cal: Calendar = .current) -> String {
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: jetzt), to: cal.startOfDay(for: tag)).day ?? 1
        if tage <= 1 { return "Morgen" }
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.calendar = cal
        f.dateFormat = tage < 7 ? "EEEE" : "d. MMMM"
        return "Am \(f.string(from: tag))"
    }

    static func ausblickSatz(_ tage: [AusblickTag], jetzt: Date, _ cal: Calendar = .current) -> [SatzStueck] {
        let tage = tage.filter { !$0.titel.isEmpty }
        guard !tage.isEmpty else { return [] }
        var stuecke: [SatzStueck] = []
        var text = ""
        for (i, d) in tage.enumerated() {
            let wann = wann(d.tag, jetzt: jetzt, cal)
            if i == 0 {
                text += "\(wann) \(d.titel.count > 1 ? "stehen" : "steht") "
            } else {
                text += ", " + wann.prefix(1).lowercased() + wann.dropFirst() + " "
            }
            for (j, titel) in d.titel.enumerated() {
                text += j == 0 ? "„" : (j == d.titel.count - 1 ? "“ und „" : "“, „")
                stuecke.append(SatzStueck(text: text, akzent: false))
                stuecke.append(SatzStueck(text: AufgabenLogic.anzeigeTitel(titel), akzent: true))
                text = ""
            }
            text += "“" + (i == 0 ? " an" : "")
        }
        stuecke.append(SatzStueck(text: text + ".", akzent: false))
        return stuecke
    }
}
