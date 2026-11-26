import Foundation

struct Anzeige: Equatable, Identifiable {
    enum Ton: String, Equatable { case ok, mittel, hoch, warn, danger }
    struct Listenpunkt: Equatable { var text: String; var meta: String?; var ton: Ton? }
    struct Zeitpunkt: Equatable { var datum: Date?; var datumText: String; var text: String; var erledigt: Bool }
    struct Messpunkt: Equatable { var am: String; var wert: Double }
    enum Baustein: Equatable {
        case fortschritt(label: String?, wert: Double?, von: Double?, text: String?, seit: String?)
        case zahl(label: String?, wert: Double?, einheit: String?, ziel: Double?, seit: Double?, verlauf: [Messpunkt])
        case liste(label: String?, punkte: [Listenpunkt])
        case zeitleiste(label: String?, punkte: [Zeitpunkt])
        case countdown(label: String?, bis: Date?)
    }

    var id: String
    var titel: String
    var zweck: String?
    var istWidget: Bool
    var bausteine: [Baustein]
    var endeText: String?
    var bis: Date?
    var stand: Date?
    var fehler: String?
    var erledigt: Bool
    var bestelltAm: Date?

    static let hoechstens = 6

    static func lesen(_ antwort: [String: Any]) -> [Anzeige] {
        let roh = (antwort["pins"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let alle = roh.compactMap { pin($0) }
        return Array(alle.sorted { ($0.bestelltAm ?? .distantFuture) < ($1.bestelltAm ?? .distantFuture) }.prefix(hoechstens))
    }

    static func pin(_ p: [String: Any]) -> Anzeige? {
        guard let a = p["anzeige"] as? [String: Any] else { return nil }
        let karte = p["karte"] as? [String: Any] ?? [:]
        let name = text(p["name"]) ?? text(p["titel"]) ?? UUID().uuidString
        let titel = text(p["titel"]) ?? text(karte["titel"]) ?? "Anzeige"
        let widget = text(p["art"]) == "widget"
        let bausteine = widget ? [] : (karte["bausteine"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { baustein($0) }
        var ende: (String?, Date?) = (nil, nil)
        if let e = a["ende"] as? [String: Any] {
            if text(e["art"]) == "dauerhaft" { ende = ("dauerhaft", nil) }
            else if let b = text(e["bis"]) { ende = (nil, datum(b)) }
        }
        return Anzeige(id: name, titel: titel, zweck: text(a["zweck"]), istWidget: widget, bausteine: bausteine,
                       endeText: ende.0, bis: ende.1, stand: text(a["stand"]).flatMap(datum), fehler: text(a["fehler"]),
                       erledigt: (a["erledigt"] as? Bool) ?? false, bestelltAm: text(a["bestelltAm"]).flatMap(datum))
    }

    static func baustein(_ b: [String: Any]) -> Baustein? {
        let label = text(b["label"])
        switch text(b["typ"]) {
        case "fortschritt":
            var seit: String?
            if let s = b["seitStart"] as? [String: Any] {
                let dw = Int((zahl(s["wert"]) ?? 0).rounded()), dv = Int((zahl(s["von"]) ?? 0).rounded())
                let am = text(s["am"]).flatMap(datum).map(kurz) ?? ""
                var teile: [String] = []
                if dv != 0 { teile.append(String(format: "%+d neue", dv)) }
                if dw != 0 { teile.append(String(format: "%+d erledigt", dw)) }
                if !teile.isEmpty { seit = teile.joined(separator: ", ") + (am.isEmpty ? "" : " seit \(am)") }
            }
            return .fortschritt(label: label, wert: zahl(b["wert"]), von: zahl(b["von"]), text: text(b["text"]), seit: seit)
        case "zahl":
            let verlauf = (b["verlauf"] as? [Any] ?? []).compactMap { e -> Messpunkt? in
                guard let m = e as? [String: Any], let w = zahl(m["wert"]) else { return nil }
                return Messpunkt(am: text(m["am"]) ?? "", wert: w)
            }
            return .zahl(label: label, wert: zahl(b["wert"]), einheit: text(b["einheit"]), ziel: zahl(b["ziel"]),
                         seit: zahl(b["seitStart"]), verlauf: verlauf)
        case "liste":
            let punkte = (b["punkte"] as? [Any] ?? []).prefix(8).compactMap { e -> Listenpunkt? in
                if let s = e as? String, !s.isEmpty { return Listenpunkt(text: s, meta: nil, ton: nil) }
                guard let m = e as? [String: Any], let t = text(m["text"]) else { return nil }
                return Listenpunkt(text: t, meta: text(m["meta"]), ton: text(m["ton"]).flatMap(Ton.init(rawValue:)))
            }
            return .liste(label: label, punkte: Array(punkte))
        case "zeitleiste":
            let punkte = (b["punkte"] as? [Any] ?? []).prefix(8).compactMap { e -> Zeitpunkt? in
                guard let m = e as? [String: Any], let t = text(m["text"]) else { return nil }
                let d = text(m["datum"])
                return Zeitpunkt(datum: d.flatMap(datum), datumText: d.flatMap(datum).map(kurz) ?? "", text: t, erledigt: (m["erledigt"] as? Bool) ?? false)
            }
            return .zeitleiste(label: label, punkte: Array(punkte))
        case "countdown":
            return .countdown(label: label, bis: text(b["bis"]).flatMap(datum))
        default:
            return nil
        }
    }

    static func resttage(bis: Date, jetzt: Date, _ cal: Calendar = Self.berlin) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: jetzt), to: cal.startOfDay(for: bis)).day ?? 0
    }

    static func countdownText(_ tage: Int) -> String {
        switch tage {
        case 0: return "heute"
        case 1: return "noch 1 Tag"
        case 2...: return "noch \(tage) Tage"
        case -1: return "seit 1 Tag vorbei"
        default: return "seit \(-tage) Tagen vorbei"
        }
    }

    static func fortschrittAnteil(wert: Double, von: Double) -> Double { von > 0 ? min(1, max(0, wert / von)) : 0 }

    static func fortschrittText(vorlage: String?, wert: Double, von: Double) -> String {
        let t = vorlage ?? "{wert} von {von}"
        let prozent = von > 0 ? Int((wert / von * 100).rounded()) : 0
        return t.replacingOccurrences(of: "{wert}", with: zahlText(wert)).replacingOccurrences(of: "{von}", with: zahlText(von))
            .replacingOccurrences(of: "{rest}", with: zahlText(max(0, von - wert))).replacingOccurrences(of: "{prozent}", with: "\(prozent) %")
    }

    static func zahlText(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e12 { return String(Int(v)) }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    func fuss(jetzt: Date) -> String {
        var teile: [String] = []
        if let z = zweck { teile.append(z) }
        if erledigt { teile.append("erreicht") }
        else if let b = bis { teile.append("bis \(Self.kurz(b))") }
        if let f = fehler, !f.isEmpty { teile.append(f) }
        else if let s = stand { teile.append("Stand \(Self.uhr(s))") }
        return teile.joined(separator: " · ")
    }

    func standAlt(jetzt: Date) -> Bool { stand.map { jetzt.timeIntervalSince($0) > 3 * 3600 } ?? false }

    static let berlin: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current; c.locale = Locale(identifier: "de_DE"); return c }()

    static func datum(_ s: String) -> Date? {
#if os(iOS)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
#else
        if let d = IsoZeit.datum(s) { return d }
#endif
        let f = DateFormatter()
        f.calendar = berlin; f.timeZone = berlin.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func kurz(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = berlin; f.timeZone = berlin.timeZone; f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM"
        return f.string(from: d)
    }

    static func uhr(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = berlin.timeZone; f.locale = Locale(identifier: "de_DE"); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func wochentag(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = berlin; f.timeZone = berlin.timeZone; f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f.string(from: d)
    }

    private static func text(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func zahl(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}

@MainActor
final class AnzeigenLader: ObservableObject {
    @Published private(set) var anzeigen: [Anzeige] = []
    private var aufgabe: Task<Void, Never>?

    func start(_ store: SenecaStore) {
        aufgabe?.cancel()
        aufgabe = Task { [weak self] in
            while !Task.isCancelled {
                if store.isConnected, let a = try? await store.rufe("seneca.pins") { self?.anzeigen = Anzeige.lesen(a) }
                try? await Task.sleep(for: .seconds(store.isConnected ? 300 : 10))
            }
        }
    }

    func stop() { aufgabe?.cancel(); aufgabe = nil }
}
