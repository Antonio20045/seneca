import Foundation

struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var title: String
        var start: Date
        var end: Date
        var place: String? = nil
    }
    var items: [Item]
    var writtenAt: Date
    var coversUntil: Date
    var stand: Date? = nil
    var laufend: [Item]? = nil
}

struct WidgetLines: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case next, free, stale }
    var kind: Kind
    var time: String? = nil
    var title: String? = nil
    var headline: String
    var place: String? = nil
    var jetzt: String? = nil
    var jetztBis: String? = nil
    var inline: String
    var spoken: String
}

enum WidgetStore {
    static let group = "group.de.antonio.senecapocket"
    static let key = "seneca-widget.snapshot"

    static func read(_ defaults: UserDefaults? = UserDefaults(suiteName: group)) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    static func write(_ snapshot: WidgetSnapshot, _ defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }
}

enum WidgetLogic {
    static let staleAfter: TimeInterval = 12 * 3600
    static let itemLimit = 12

    static func shortPlace(_ place: String?, title: String) -> String? {
        guard let first = place?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces), !first.isEmpty,
              !title.localizedCaseInsensitiveContains(first) else { return nil }
        return first
    }

    static func snapshot(items: [WidgetSnapshot.Item], now: Date, horizon: Date, stand: Date? = nil) -> WidgetSnapshot {
        let upcoming = items.filter { $0.start > now && $0.start < horizon }.sorted { $0.start < $1.start }
        let kept = Array(upcoming.prefix(itemLimit))
        let covers = upcoming.count > itemLimit ? kept.last!.start : horizon
        return WidgetSnapshot(items: kept, writtenAt: now, coversUntil: covers, stand: stand)
    }

    static func next(_ items: [WidgetSnapshot.Item], after date: Date) -> WidgetSnapshot.Item? {
        items.filter { $0.start > date }.min { $0.start < $1.start }
    }

    static func hm(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour!, c.minute!)
    }
    private static func uhr(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return c.minute! == 0 ? "\(c.hour!) Uhr" : String(format: "%d:%02d Uhr", c.hour!, c.minute!)
    }

    static func isStale(_ snapshot: WidgetSnapshot, at date: Date) -> Bool {
        date >= staleFrom(snapshot)
    }
    static func staleFrom(_ snapshot: WidgetSnapshot) -> Date {
        let basis = min(snapshot.writtenAt, snapshot.stand ?? snapshot.writtenAt)
        return min(basis.addingTimeInterval(staleAfter), snapshot.coversUntil)
    }

    static func lines(_ snapshot: WidgetSnapshot?, at date: Date, _ cal: Calendar = .current) -> WidgetLines {
        guard let snapshot else {
            let hint = "Öffne Seneca einmal, dann steht hier dein Tag."
            return WidgetLines(kind: .stale, headline: hint, inline: "Öffne Seneca.", spoken: hint)
        }
        if isStale(snapshot, at: date) {
            let hint = "Öffne Seneca für den aktuellen Stand."
            return WidgetLines(kind: .stale, headline: hint, inline: "Öffne Seneca.", spoken: hint)
        }
        let laeuft = ((snapshot.laufend ?? []) + snapshot.items).filter { $0.start <= date && date < $0.end }.max { $0.start < $1.start }
        let jetzt = laeuft?.title, bis = laeuft.map { "bis " + hm($0.end, cal) }
        if let next = next(snapshot.items, after: date), cal.isDate(next.start, inSameDayAs: date) {
            let time = hm(next.start, cal)
            let place = shortPlace(next.place, title: next.title)
            let davor = laeuft.map { "Gerade läuft \($0.title) bis \(uhr($0.end, cal)). " } ?? ""
            return WidgetLines(kind: .next, time: time, title: next.title, headline: "\(time) \(next.title)", place: place, jetzt: jetzt, jetztBis: bis,
                               inline: "\(time) \(next.title)", spoken: davor + "Um \(uhr(next.start, cal)): \(next.title)" + (place.map { ", \($0)" } ?? "") + ".")
        }
        if let l = laeuft {
            let satz = "Gerade läuft \(l.title) bis \(uhr(l.end, cal)). Danach steht heute nichts mehr an."
            return WidgetLines(kind: .free, headline: "Danach steht heute nichts mehr an.", jetzt: jetzt, jetztBis: bis, inline: "\(l.title) \(bis ?? "")", spoken: satz)
        }
        let free = "Heute steht nichts mehr an."
        return WidgetLines(kind: .free, headline: free, inline: free, spoken: free)
    }

    static func timelineDates(_ snapshot: WidgetSnapshot?, from now: Date, _ cal: Calendar = .current) -> [Date] {
        guard let snapshot else { return [now] }
        let end = staleFrom(snapshot)
        var dates = snapshot.items.map(\.start).filter { $0 > now && $0 < end }
        dates += ((snapshot.laufend ?? []) + snapshot.items).map(\.end).filter { $0 > now && $0 < end }
        var midnight = cal.startOfDay(for: now)
        while let following = cal.date(byAdding: .day, value: 1, to: midnight), following < end {
            dates.append(following)
            midnight = following
        }
        if end > now { dates.append(end) }
        return [now] + Array(Set(dates)).sorted()
    }
}
