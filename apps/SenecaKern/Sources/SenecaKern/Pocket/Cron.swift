import Foundation

struct CronExpression: Equatable {
    let minutes: Set<Int>
    let hours: Set<Int>
    let daysOfMonth: Set<Int>
    let months: Set<Int>
    let daysOfWeek: Set<Int>
    let domRestricted: Bool
    let dowRestricted: Bool

    init?(_ text: String) {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count == 5,
              let mi = CronExpression.field(parts[0], 0, 59),
              let h = CronExpression.field(parts[1], 0, 23),
              let dom = CronExpression.field(parts[2], 1, 31),
              let mo = CronExpression.field(parts[3], 1, 12),
              var dow = CronExpression.field(parts[4], 0, 7) else { return nil }
        if dow.contains(7) { dow.remove(7); dow.insert(0) }
        minutes = mi; hours = h; daysOfMonth = dom; months = mo; daysOfWeek = dow
        domRestricted = parts[2] != "*"
        dowRestricted = parts[4] != "*"
    }

    private static func field(_ text: String, _ lo: Int, _ hi: Int) -> Set<Int>? {
        var out = Set<Int>()
        for item in text.split(separator: ",") {
            let stepParts = item.split(separator: "/", maxSplits: 1).map(String.init)
            let step = stepParts.count == 2 ? Int(stepParts[1]) : 1
            guard let step, step > 0 else { return nil }
            let range = stepParts[0]
            var from = lo, to = hi
            if range != "*" {
                let bounds = range.split(separator: "-").map { Int($0) }
                guard !bounds.isEmpty, bounds.allSatisfy({ $0 != nil }) else { return nil }
                from = bounds[0]!
                to = bounds.count > 1 ? bounds[1]! : (stepParts.count == 2 ? hi : from)
            }
            guard from >= lo, to <= hi, from <= to else { return nil }
            out.formUnion(stride(from: from, through: to, by: step))
        }
        return out.isEmpty ? nil : out
    }

    private func matchesDay(day: Int, month: Int, weekday: Int) -> Bool {
        guard months.contains(month) else { return false }
        let domOK = daysOfMonth.contains(day), dowOK = daysOfWeek.contains(weekday)
        if domRestricted && dowRestricted { return domOK || dowOK }
        return domOK && dowOK
    }

    func occurrences(from start: Date, to end: Date, timeZone: TimeZone) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var out: [Date] = []
        var day = cal.startOfDay(for: start)
        while day < end {
            let c = cal.dateComponents([.year, .month, .day, .weekday], from: day)
            if matchesDay(day: c.day!, month: c.month!, weekday: c.weekday! - 1) {
                for h in hours.sorted() {
                    for m in minutes.sorted() {
                        var dc = DateComponents()
                        dc.year = c.year; dc.month = c.month; dc.day = c.day; dc.hour = h; dc.minute = m
                        if let t = cal.date(from: dc), t >= start, t < end { out.append(t) }
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }
}
