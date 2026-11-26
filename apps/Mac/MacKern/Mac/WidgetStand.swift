import Foundation

struct WidgetStand: Codable, Equatable {
    struct Termin: Codable, Equatable {
        var titel: String
        var start: Date
        var ende: Date
        var ort: String?
    }

    var satz: String
    var braucht: Int
    var laeuft: Int
    var ungelesen: Int
    var fragen: [String]
    var termin: Termin?
    var geschrieben: Date

    static func beispiel(_ jetzt: Date = Date()) -> WidgetStand {
        let start = jetzt.addingTimeInterval(2 * 3600)
        return WidgetStand(satz: "Drei Fragen warten auf dich.", braucht: 3, laeuft: 1, ungelesen: 2,
                           fragen: ["Soll das Team die Preisliste noch heute verschicken?", "Neues Konto für die Buchhaltung anlegen?", "Lieferant wechseln?"],
                           termin: Termin(titel: "Frühstück mit Jonas", start: start, ende: start.addingTimeInterval(3600), ort: "Café Lorenz"),
                           geschrieben: jetzt)
    }
}

enum WidgetSpeicher {
    static let gruppe = "5K75RX8FHZ.de.antonio.seneca.nativ"
    static let schluessel = "seneca-nativ.widget.stand"
    static let fragenMax = 3
    static let veraltetNach: TimeInterval = 12 * 3600

    static func lies(_ d: UserDefaults? = UserDefaults(suiteName: gruppe)) -> WidgetStand? {
        guard let data = d?.data(forKey: schluessel) else { return nil }
        return try? JSONDecoder().decode(WidgetStand.self, from: data)
    }

    @discardableResult
    static func schreibe(_ s: WidgetStand, _ d: UserDefaults? = UserDefaults(suiteName: gruppe)) -> Bool {
        guard let d, let data = try? JSONEncoder().encode(s) else { return false }
        var alt = lies(d); alt?.geschrieben = s.geschrieben
        d.set(data, forKey: schluessel)
        return alt != s
    }

    static func veraltet(_ s: WidgetStand, _ jetzt: Date = Date()) -> Bool { jetzt.timeIntervalSince(s.geschrieben) > veraltetNach }

    static func zeitpunkte(_ s: WidgetStand?, ab jetzt: Date, _ cal: Calendar = .current) -> [Date] {
        var out: Set<Date> = [jetzt]
        if let t = s?.termin { for d in [t.start, t.ende] where d > jetzt { out.insert(d) } }
        if let s, let ende = Optional(s.geschrieben.addingTimeInterval(veraltetNach)), ende > jetzt { out.insert(ende) }
        if let m = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: jetzt)) { out.insert(m) }
        return out.sorted()
    }
}
