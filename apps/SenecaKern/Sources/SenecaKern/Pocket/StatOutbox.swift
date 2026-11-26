import Foundation

struct StatOp: Codable, Equatable, Identifiable {
    var id: String
    var methode: String
    var paramsJSON: Data
    var erfasst: Date? = nil

    init(id: String, methode: String, params: [String: Any]) {
        self.id = id
        self.methode = methode
        var p = params
        if p["id"] == nil { p["id"] = id }
        self.paramsJSON = (try? JSONSerialization.data(withJSONObject: p, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    var params: [String: Any] { (try? JSONSerialization.jsonObject(with: paramsJSON)) as? [String: Any] ?? [:] }

    static func eintragen(id: String = UUID().uuidString, thema: String, wert: Double, datum: String, notiz: String? = nil, buch: String? = nil) -> StatOp {
        var p: [String: Any] = ["id": id, "thema": thema, "wert": wert, "datum": datum]
        if let n = notiz?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { p["notiz"] = n }
        if let buch { p["buch"] = buch }
        return StatOp(id: id, methode: "seneca.statistik.eintragen", params: p)
    }
    static func entfernen(eintrag: String) -> StatOp {
        StatOp(id: UUID().uuidString, methode: "seneca.statistik.entfernen", params: ["id": eintrag])
    }
    static func buchBeginnen(id: String = UUID().uuidString, titel: String, autor: String? = nil, datum: String? = nil, beendeAktuelles: Bool = false) -> StatOp {
        var p: [String: Any] = ["aktion": "beginnen", "id": id, "titel": titel, "beendeAktuelles": beendeAktuelles]
        if let a = autor?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { p["autor"] = a }
        if let datum { p["datum"] = datum }
        return StatOp(id: id, methode: "seneca.statistik.buch", params: p)
    }
    static func buchBeenden(id buch: String, datum: String) -> StatOp {
        StatOp(id: UUID().uuidString, methode: "seneca.statistik.buch", params: ["aktion": "beenden", "id": buch, "datum": datum])
    }
    static func buchAendern(id buch: String, titel: String, autor: String, begonnen: String) -> StatOp {
        let p: [String: Any] = ["aktion": "aendern", "id": buch, "titel": titel, "autor": autor, "begonnen": begonnen]
        return StatOp(id: UUID().uuidString, methode: "seneca.statistik.buch", params: p)
    }
    static func buchEntfernen(id buch: String) -> StatOp {
        StatOp(id: UUID().uuidString, methode: "seneca.statistik.buch", params: ["aktion": "entfernen", "id": buch])
    }
    static func satz(id: String = UUID().uuidString, uebung: String, kg: Double, wdh: Int, datum: String, zeit: Date = Date()) -> StatOp {
        var op = StatOp(id: id, methode: "seneca.statistik.satz", params: ["id": id, "uebung": uebung, "kg": kg, "wdh": wdh, "datum": datum])
        op.erfasst = zeit
        return op
    }
    static func satzEntfernen(satz: String) -> StatOp {
        StatOp(id: UUID().uuidString, methode: "seneca.statistik.satz.entfernen", params: ["id": satz])
    }
}

struct StatFlush {
    var gesendet: [StatOp] = []
    var abgelehnt: [(op: StatOp, meldung: String)] = []
    var offen = false
}

final class StatOutbox {
    private(set) var ops: [StatOp]
    private let defaults: UserDefaults?
    private let key: String
    private var laeuft = false
    private(set) var letzterFehler: String?

    init(defaults: UserDefaults? = .standard, key: String = "seneca-pocket.stat-outbox") {
        self.defaults = defaults
        self.key = key
        if let data = defaults?.data(forKey: key), let saved = try? JSONDecoder().decode([StatOp].self, from: data) { ops = saved } else { ops = [] }
    }

    var istLeer: Bool { ops.isEmpty }
    func enthaelt(_ id: String) -> Bool { ops.contains { $0.id == id } }

    func hinzufuegen(_ op: StatOp) {
        guard !enthaelt(op.id) else { return }
        ops.append(op)
        sichern()
    }

    func entfernen(_ id: String) {
        ops.removeAll { $0.id == id }
        sichern()
    }

    func abarbeiten(_ senden: (StatOp) async throws -> [String: Any]) async -> StatFlush {
        var ergebnis = StatFlush()
        guard !laeuft else { ergebnis.offen = !ops.isEmpty; return ergebnis }
        laeuft = true
        defer { laeuft = false }
        while let op = ops.first {
            do {
                _ = try await senden(op)
                ops.removeAll { $0.id == op.id }
                sichern()
                ergebnis.gesendet.append(op)
                letzterFehler = nil
            } catch SenecaError.offline {
                ergebnis.offen = true
                return ergebnis
            } catch SenecaError.nichtGesendet {
                ergebnis.offen = true
                return ergebnis
            } catch SenecaError.refused(let r) {
                if r.code.uppercased() == "INVALID_REQUEST" {
                    ops.removeAll { $0.id == op.id }
                    sichern()
                    ergebnis.abgelehnt.append((op, r.message))
                } else {
                    letzterFehler = r.message
                    ergebnis.offen = true
                    return ergebnis
                }
            } catch {
                letzterFehler = error.localizedDescription
                ergebnis.offen = true
                return ergebnis
            }
        }
        return ergebnis
    }

    private func sichern() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(ops) { defaults.set(data, forKey: key) }
    }
}
