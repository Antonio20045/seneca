import Foundation

struct TageslaufEreignis: Codable, Equatable {
    var zeit: Date
    var ende: Date?
    var quelle: String
    var art: String
    var titel: String
    var detailJSON: Data
    var schluessel: String

    init(zeit: Date, ende: Date? = nil, quelle: String = "iphone", art: String, titel: String, detail: [String: Any] = [:], schluessel: String) {
        self.zeit = zeit
        self.ende = ende
        self.quelle = quelle
        self.art = art
        self.titel = titel
        self.detailJSON = (try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys])) ?? Data("{}".utf8)
        self.schluessel = schluessel
    }

    var detail: [String: Any] { (try? JSONSerialization.jsonObject(with: detailJSON)) as? [String: Any] ?? [:] }

    func json(_ zone: TimeZone) -> [String: Any] {
        var j: [String: Any] = ["zeit": TageslaufZeit.iso(zeit, zone), "quelle": quelle, "art": art, "titel": titel,
                                "detail": detail, "schluessel": schluessel]
        if let ende { j["ende"] = TageslaufZeit.iso(ende, zone) }
        return j
    }
}

enum TageslaufZeit {
    static func iso(_ d: Date, _ zone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = zone
        return f.string(from: d)
    }

    static func lesen(_ roh: Any?) -> Date? {
        if let n = roh as? NSNumber, !(roh is String) {
            let v = n.doubleValue
            return v > 0 ? Date(timeIntervalSince1970: v > 100_000_000_000 ? v / 1000 : v) : nil
        }
        guard let s = roh as? String, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    static func uhr(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func tag(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

final class TageslaufSchlange {
    private(set) var ereignisse: [TageslaufEreignis]
    private let defaults: UserDefaults?
    private let key: String
    private var laeuft = false
    static let hoechstens = 500
    static let paket = 40
    static let haltbar: TimeInterval = 7 * 86_400

    init(defaults: UserDefaults? = .standard, key: String = "seneca-pocket.tageslauf-schlange") {
        self.defaults = defaults
        self.key = key
        if let data = defaults?.data(forKey: key), let alt = try? JSONDecoder().decode([TageslaufEreignis].self, from: data) { ereignisse = alt } else { ereignisse = [] }
    }

    var istLeer: Bool { ereignisse.isEmpty }

    func hinzufuegen(_ neu: [TageslaufEreignis], jetzt: Date = Date()) {
        guard !neu.isEmpty else { return }
        for e in neu {
            if let i = ereignisse.firstIndex(where: { $0.schluessel == e.schluessel }) { ereignisse[i] = e } else { ereignisse.append(e) }
        }
        ereignisse.removeAll { jetzt.timeIntervalSince($0.zeit) > Self.haltbar }
        if ereignisse.count > Self.hoechstens { ereignisse.removeFirst(ereignisse.count - Self.hoechstens) }
        sichern()
    }

    @discardableResult
    func abarbeiten(isolation: isolated (any Actor)? = #isolation, _ senden: ([TageslaufEreignis]) async throws -> Void) async -> Bool {
        guard !laeuft else { return ereignisse.isEmpty }
        laeuft = true
        defer { laeuft = false }
        while !ereignisse.isEmpty {
            let teil = Array(ereignisse.prefix(Self.paket))
            do { try await senden(teil) } catch { return false }
            ereignisse.removeAll { teil.contains($0) }
            sichern()
        }
        return true
    }

    private func sichern() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(ereignisse) { defaults.set(data, forKey: key) }
    }
}

struct SinnOrt: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var adresse: String
    var breite: Double
    var laenge: Double
    var radius: Double = 150

    static let zuhause = "zuhause"
    static let standard: [SinnOrt] = [
        SinnOrt(id: zuhause, name: "Zuhause", adresse: "Poststraße 3, 40667 Meerbusch", breite: 51.2485136, laenge: 6.6936636),
        SinnOrt(id: "campus", name: "Vodafone Campus", adresse: "Ferdinand-Braun-Platz 1, 40549 Düsseldorf", breite: 51.2356894, laenge: 6.7325717),
        SinnOrt(id: "koeln", name: "Köln", adresse: "Zülpicher Straße, 50937 Köln", breite: 50.9274835, laenge: 6.9341408),
    ]

    static let speicher = "seneca-pocket.sinne.orte"
    static func laden(_ defaults: UserDefaults) -> [SinnOrt] {
        guard let data = defaults.data(forKey: speicher), let orte = try? JSONDecoder().decode([SinnOrt].self, from: data), !orte.isEmpty else { return standard }
        return orte
    }
    static func speichern(_ orte: [SinnOrt], _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(orte) { defaults.set(data, forKey: speicher) }
    }
}

enum OrtsLogik {
    static func istNeu(ort: String, dort: Bool, stand: [String: Bool]) -> Bool { stand[ort] != dort }

    static func ereignis(_ ort: SinnOrt, ankunft: Bool, zeit: Date) -> TageslaufEreignis {
        TageslaufEreignis(zeit: zeit, art: ankunft ? "ort_ankunft" : "ort_abfahrt", titel: ort.name,
                          detail: ["ort": ort.id, "adresse": ort.adresse, "breite": ort.breite, "laenge": ort.laenge, "radius": ort.radius],
                          schluessel: "ort:\(ort.id):\(ankunft ? "an" : "ab"):\(Int(zeit.timeIntervalSince1970 / 60))")
    }
}

struct GeraetTermin: Equatable {
    var id: String
    var titel: String
    var start: Date
    var ende: Date
    var ganztags: Bool = false
    var ort: String? = nil
    var kalender: String? = nil
}

enum TerminLogik {
    static func fenster(jetzt: Date, _ cal: Calendar) -> (von: Date, bis: Date) {
        let von = cal.startOfDay(for: jetzt)
        return (von, cal.date(byAdding: .day, value: 2, to: von) ?? von.addingTimeInterval(2 * 86_400))
    }

    static func schluessel(_ t: GeraetTermin) -> String { "termin:\(t.id):\(Int(t.start.timeIntervalSince1970))" }

    private static func abdruck(_ t: GeraetTermin) -> String {
        "\(t.titel)|\(Int(t.ende.timeIntervalSince1970))|\(t.ganztags)|\(t.ort ?? "")|\(t.kalender ?? "")"
    }

    static func ereignis(_ t: GeraetTermin) -> TageslaufEreignis {
        var d: [String: Any] = ["ganztags": t.ganztags]
        if let o = t.ort, !o.isEmpty { d["ort"] = o }
        if let k = t.kalender, !k.isEmpty { d["kalender"] = k }
        return TageslaufEreignis(zeit: t.start, ende: t.ende, art: "termin", titel: t.titel, detail: d, schluessel: schluessel(t))
    }

    static func neu(_ termine: [GeraetTermin], gemeldet: [String: String]) -> (ereignisse: [TageslaufEreignis], gemeldet: [String: String]) {
        var merk: [String: String] = [:]
        var raus: [TageslaufEreignis] = []
        for t in termine where !t.titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let s = schluessel(t), a = abdruck(t)
            if merk[s] != nil { continue }
            merk[s] = a
            if gemeldet[s] != a { raus.append(ereignis(t)) }
        }
        return (raus, merk)
    }
}

struct GeraetTraining: Equatable {
    var id: String
    var start: Date
    var ende: Date
    var artNr: UInt
    var quelle: String = ""
    var kcal: Double? = nil
    var meter: Double? = nil
}

enum TrainingLogik {
    static func name(_ nr: UInt) -> String {
        switch nr {
        case 37: return "Laufen"
        case 52: return "Gehen"
        case 24: return "Wandern"
        case 13: return "Radfahren"
        case 46: return "Schwimmen"
        case 50, 20: return "Krafttraining"
        case 63: return "Intervalltraining"
        case 11: return "Crosstraining"
        case 73: return "Ausdauertraining"
        case 59: return "Rumpftraining"
        case 57: return "Yoga"
        case 66: return "Pilates"
        case 62: return "Dehnen"
        case 80: return "Abwärmen"
        case 35: return "Rudern"
        case 16: return "Crosstrainer"
        case 44, 74: return "Treppensteigen"
        case 41: return "Fußball"
        case 48: return "Tennis"
        case 6: return "Basketball"
        case 8: return "Boxen"
        case 9: return "Klettern"
        default: return "Training"
        }
    }

    static func ereignis(_ t: GeraetTraining) -> TageslaufEreignis {
        let art = name(t.artNr)
        var d: [String: Any] = ["art": art, "dauer_min": Int((t.ende.timeIntervalSince(t.start) / 60).rounded())]
        if !t.quelle.isEmpty { d["quelle"] = t.quelle }
        if let k = t.kcal, k > 0 { d["kcal"] = Int(k.rounded()) }
        if let m = t.meter, m > 0 { d["km"] = (m / 10).rounded() / 100 }
        return TageslaufEreignis(zeit: t.start, ende: t.ende, art: "training", titel: art, detail: d, schluessel: "training:\(t.id)")
    }
}

enum Heimkehr {
    static let vonStunde = 15
    static let bisStunde = 22

    static func faellig(ort: String, zeit: Date, zuletzt: String?, _ cal: Calendar) -> Bool {
        guard ort == SinnOrt.zuhause else { return false }
        let stunde = cal.component(.hour, from: zeit)
        guard stunde >= vonStunde, stunde < bisStunde else { return false }
        return zuletzt != TageslaufZeit.tag(zeit, cal)
    }

    static func satzAusKalender(_ termine: [GeraetTermin], jetzt: Date, _ cal: Calendar) -> String {
        let offen = termine.filter { cal.isDate($0.start, inSameDayAs: jetzt) && !$0.ganztags && $0.start > jetzt }.sorted { $0.start < $1.start }
        return ansteht(offen.map { ($0.titel, $0.start) }, cal) + "."
    }

    static let ohneWissen = "Du bist zu Hause. Deinen Kalender darf ich auf dem iPhone nicht lesen."

    private static func ansteht(_ k: [(titel: String, zeit: Date?)], _ cal: Calendar) -> String {
        func eins(_ e: (titel: String, zeit: Date?)) -> String {
            "„\(e.titel)“" + (e.zeit.map { " um \(TageslaufZeit.uhr($0, cal)) Uhr" } ?? "")
        }
        switch k.count {
        case 0: return "Heute steht nichts mehr an"
        case 1: return "Heute steht noch \(eins(k[0])) an"
        case 2: return "Heute stehen noch \(eins(k[0])) und \(eins(k[1])) an"
        default:
            let rest = k.count - 2
            return "Heute stehen noch \(eins(k[0])), \(eins(k[1])) und \(rest == 1 ? "ein weiterer Termin" : "\(rest) weitere Termine") an"
        }
    }
}

struct SinneLage: Equatable {
    enum Standort: Equatable { case immer, nurOffen, aus, ungefragt }
    var standort: Standort
    var kalender: Bool
    var mitteilungen: Bool
    var wartend: Int
    var erfolg: Date? = nil
    var erfolgAnzahl = 0
    var fehler: String? = nil
    var fehlerZeit: Date? = nil
}

enum SinneBericht {
    static let erfolgKey = "seneca-pocket.sinne.letzter-erfolg"
    static let erfolgAnzahlKey = "seneca-pocket.sinne.letzter-erfolg-anzahl"
    static let fehlerKey = "seneca-pocket.sinne.letzter-fehler"
    static let fehlerZeitKey = "seneca-pocket.sinne.letzter-fehler-zeit"

    static func wann(_ d: Date, jetzt: Date, _ cal: Calendar = .current) -> String {
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: jetzt)).day ?? 0
        let c = cal.dateComponents([.day, .month, .hour, .minute], from: d)
        let uhr = String(format: "%d:%02d Uhr", c.hour ?? 0, c.minute ?? 0)
        switch tage {
        case 0: return "heute um \(uhr)"
        case 1: return "gestern um \(uhr)"
        default: return "am \(c.day ?? 0).\(c.month ?? 0). um \(uhr)"
        }
    }

    static func saetze(_ l: SinneLage, jetzt: Date, _ cal: Calendar = .current) -> [String] {
        var aus: [String] = []
        var fehlt: [String] = []
        switch l.standort {
        case .immer: break
        case .nurOffen: fehlt.append("der Standort bei geschlossener App")
        case .aus, .ungefragt: fehlt.append("der Standort")
        }
        if !l.kalender { fehlt.append("der Kalender") }
        if !l.mitteilungen { fehlt.append("Mitteilungen") }
        switch fehlt.count {
        case 0: aus.append("Standort, Kalender und Mitteilungen sind erlaubt.")
        case 1: aus.append("Es fehlt noch eine Erlaubnis: \(fehlt[0]).")
        default: aus.append("Es fehlen noch Erlaubnisse: \(fehlt.dropLast().joined(separator: ", ")) und \(fehlt.last!).")
        }
        if !l.kalender, l.standort == .aus || l.standort == .ungefragt {
            aus.append("Ohne Standort und Kalender hat das iPhone nichts, was es dem Mac melden könnte.")
        } else if l.standort == .nurOffen {
            aus.append("Ankommen und Weggehen bemerkt das iPhone so nur, während die App offen ist.")
        }
        switch l.wartend {
        case 0: aus.append("Gerade wartet kein Ereignis auf den Mac.")
        case 1: aus.append("Ein Ereignis wartet auf den Mac.")
        default: aus.append("\(l.wartend) Ereignisse warten auf den Mac.")
        }
        if let e = l.erfolg {
            let menge = l.erfolgAnzahl == 1 ? "ein Ereignis" : "\(l.erfolgAnzahl) Ereignisse"
            aus.append("Zuletzt kam \(wann(e, jetzt: jetzt, cal)) etwas am Mac an (\(menge)).")
        } else {
            aus.append("Von diesem iPhone ist bisher noch nichts am Mac angekommen.")
        }
        if let f = l.fehler, let z = l.fehlerZeit, l.erfolg.map({ z > $0 }) ?? true {
            aus.append("Der letzte Versuch \(wann(z, jetzt: jetzt, cal)) ist gescheitert: \(f)")
        }
        return aus
    }

    static func grund(_ fehler: Error) -> String {
        switch fehler {
        case SenecaError.offline: return "Der Mac war nicht erreichbar."
        case SenecaError.nichtGesendet: return "Der Mac hat die Ereignisse nicht angenommen."
        case SenecaError.refused: return "Der Mac hat abgelehnt (\(fehler.localizedDescription))."
        case SenecaError.message(let m), SenecaError.rejected(let m): return "Der Mac hat abgelehnt: \(m)"
        default: return "Der Mac hat nicht wie erwartet geantwortet (\(fehler.localizedDescription))."
        }
    }
}
