import Foundation

final class VerlaufsZaehler {
    static let dateiname = "chat-history-je-stunde.json"
    static let behalteStunden = 14 * 24

    struct Stunde: Codable, Equatable {
        var gesamt = 0
        var sitzungen: [String: Int] = [:]
    }

    struct Stand: Codable, Equatable {
        var seit: String
        var stunden: [String: Stunde] = [:]
    }

    private let url: URL?
    private let kalender: Calendar
    private let sperre = NSLock()
    private(set) var stand: Stand

    init(url: URL?, kalender: Calendar = .current, jetzt: Date = Date()) {
        self.url = url; self.kalender = kalender
        if let url, let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stand.self, from: d) { stand = s }
        else { stand = Stand(seit: Self.stundenKennung(jetzt, kalender)) }
    }

    static func stundenKennung(_ d: Date, _ kalender: Calendar = .current) -> String {
        let c = kalender.dateComponents([.year, .month, .day, .hour], from: d)
        return String(format: "%04d-%02d-%02d %02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0)
    }

    func zaehle(sitzung: String, um zeit: Date = Date()) {
        sperre.lock(); defer { sperre.unlock() }
        let k = Self.stundenKennung(zeit, kalender)
        stand.stunden[k, default: Stunde()].gesamt += 1
        stand.stunden[k, default: Stunde()].sitzungen[sitzung, default: 0] += 1
        if stand.stunden.count > Self.behalteStunden {
            for alt in stand.stunden.keys.sorted().dropLast(Self.behalteStunden) { stand.stunden[alt] = nil }
        }
        guard let url, let d = try? JSONEncoder().encode(stand) else { return }
        try? d.write(to: url, options: .atomic)
    }

    var spitze: Int { stand.stunden.values.map(\.gesamt).max() ?? 0 }
}
