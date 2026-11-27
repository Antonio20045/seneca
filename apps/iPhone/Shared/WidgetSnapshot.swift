import Foundation

struct WidgetLage: Codable, Equatable, Sendable {
    struct Termin: Codable, Equatable, Sendable { var titel: String; var unter: String?; var von: Date; var bis: Date; var art: String }
    struct Frage: Codable, Equatable, Sendable { var kurz: String; var von: String; var seit: Date?; var frist: Date? }
    var stand: Date
    var termine: [Termin]
    var fokusVon: Date?
    var fokusBis: Date?
    var danach: String?
    var fragen: [Frage]
    var wartend: Int
    var team: String?
    var bodyBattery: Int?
}

enum WidgetZustand: Equatable, Sendable { case ruhig, fokus, frage, alt }

enum WidgetStore {
    static let group = "group.de.antonio.senecapocket"
    static let key = "seneca-widget.lage"

    static func read(_ defaults: UserDefaults? = UserDefaults(suiteName: group)) -> WidgetLage? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetLage.self, from: data)
    }

    static func write(_ lage: WidgetLage, _ defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        guard let data = try? JSONEncoder().encode(lage) else { return }
        defaults?.set(data, forKey: key)
    }
}

enum WidgetLogik {
    static let altNach: TimeInterval = 30 * 60
    private static let stunde = ["zwölf", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf"]
    private static let tage = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    private static let kurzTage = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    static func zustand(_ l: WidgetLage, _ jetzt: Date) -> WidgetZustand {
        if jetzt.timeIntervalSince(l.stand) > altNach { return .alt }
        if let b = l.fokusBis, b > jetzt, (l.fokusVon ?? jetzt) <= jetzt { return .fokus }
        return l.fragen.isEmpty ? .ruhig : .frage
    }

    static func uhr(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func stundeWort(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return c.minute == 0 ? stunde[(c.hour ?? 0) % 12] : uhr(d)
    }

    static func kurzUhr(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return c.minute == 0 ? "\(c.hour ?? 0)" : uhr(d)
    }

    static func tag(_ d: Date) -> String { tage[Calendar.current.component(.weekday, from: d) - 1] }
    static func kurzTag(_ d: Date) -> String { "\(kurzTage[Calendar.current.component(.weekday, from: d) - 1]) \(Calendar.current.component(.day, from: d))" }
    static func minuten(_ von: Date, _ bis: Date) -> Int { max(0, Int((bis.timeIntervalSince(von) / 60).rounded(.up))) }

    static func naechste(_ l: WidgetLage, _ jetzt: Date) -> [WidgetLage.Termin] {
        l.termine.filter { $0.von > jetzt && $0.art != "fokus" && Calendar.current.isDate($0.von, inSameDayAs: jetzt) }
    }

    static func fragen(_ n: Int) -> String { n == 1 ? "1 Frage" : "\(n) Fragen" }

    static func kurzName(_ t: WidgetLage.Termin) -> String {
        let w = t.titel.split(separator: " ")
        return w.count > 1 && ["mit", "bei"].contains(w[w.count - 2].lowercased()) ? String(w.last!) : String(w.last ?? "")
    }

    static func zeile(_ l: WidgetLage, _ jetzt: Date) -> String {
        switch zustand(l, jetzt) {
        case .ruhig: return [kurzTag(jetzt), naechste(l, jetzt).first.map { "\(uhr($0.von)) \($0.titel)" }].compactMap { $0 }.joined(separator: " · ")
        case .fokus: return "Fokus bis \(kurzUhr(l.fokusBis ?? jetzt))" + (l.fragen.isEmpty ? "" : " · danach \(fragen(l.fragen.count))")
        case .frage: return "\(fragen(l.fragen.count)) · zuerst \(l.fragen[0].kurz.replacingOccurrences(of: "?", with: ""))"
        case .alt: return "Stand \(uhr(l.stand)) · Mac antwortet nicht"
        }
    }

    static func ziel(_ l: WidgetLage, _ jetzt: Date) -> URL? {
        switch zustand(l, jetzt) {
        case .frage: return URL(string: "seneca://entscheiden")
        case .fokus: return URL(string: "seneca://heute")
        case .ruhig, .alt: return URL(string: "seneca://kalender")
        }
    }

    static func zeiten(_ l: WidgetLage?, ab jetzt: Date) -> [Date] {
        guard let l else { return [jetzt] }
        let marken = l.termine.flatMap { [$0.von, $0.bis] } + [l.fokusBis, l.stand.addingTimeInterval(altNach + 1)].compactMap { $0 }
        let viertel = (1...24).map { jetzt.addingTimeInterval(Double($0) * 900) }
        return ([jetzt] + (marken + viertel).filter { $0 > jetzt && $0 < jetzt.addingTimeInterval(6 * 3600) }).sorted()
    }
}
