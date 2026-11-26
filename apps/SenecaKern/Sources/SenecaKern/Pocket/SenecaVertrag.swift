import Foundation

enum VertragWeg: String {
    case alt, vertrag
    static let schluessel = "vertragWeg"
    static var gewaehlt: VertragWeg {
        VertragWeg(rawValue: UserDefaults.standard.string(forKey: schluessel) ?? "") ?? .alt
    }
}

struct VertragEreignis: @unchecked Sendable {
    var name: String
    var daten: [String: Any]
    var seq: Int
}

struct KartenStand: Equatable {
    var status: String?
    var aktualisiert: Double?
}

enum VertragFehler: LocalizedError, Equatable {
    case nurLokal
    case antwort(code: String, text: String, anfrageId: String?, karte: KartenStand? = nil)
    case getrennt
    case zeitlimit
    case ungueltig(String)

    var errorDescription: String? {
        switch self {
        case .nurLokal: return "Die Seneca-Brücke nimmt von außen noch keine Verbindungen an."
        case .antwort(let code, let text, let id, _):
            if code == "KOPPLUNG_NOETIG" { return "Dieses iPhone muss einmal auf deinem Mac freigegeben werden." + (id.map { " Geräteanfrage: \($0)" } ?? "") }
            return text.isEmpty ? code : text
        case .getrennt: return "Dein Mac ist gerade nicht erreichbar."
        case .zeitlimit: return "Der Mac antwortet nicht."
        case .ungueltig(let text): return text
        }
    }

    var alsSenecaFehler: SenecaError {
        switch self {
        case .antwort(let code, let text, let id, let karte):
            let roh: String
            switch code {
            case "KOPPLUNG_NOETIG": roh = "PAIRING_REQUIRED"
            case "NICHT_VERFUEGBAR": roh = "UNAVAILABLE"
            case "KONFLIKT": roh = "workboard_conflict"
            case "UNGUELTIG": roh = "INVALID_REQUEST"
            case "KEIN_RECHT": roh = "FORBIDDEN"
            default: roh = code
            }
            var refusal = GatewayRefusal(code: roh, reason: code == "KOPPLUNG_NOETIG" ? "not-paired" : nil, requestId: id, message: errorDescription ?? text)
            refusal.cardStatus = karte?.status
            refusal.cardUpdatedAt = karte?.aktualisiert
            return .refused(refusal)
        case .getrennt, .zeitlimit: return .offline
        case .nurLokal, .ungueltig: return .message(errorDescription ?? "Verbindung fehlgeschlagen.")
        }
    }
}

struct VertragZugang: Equatable {
    enum Admin: Equatable { case unbekannt, gewaehrt, wartet(anfrageId: String?), nein }
    var rechte: [String]?
    var admin: Admin
}

@MainActor
protocol SenecaVertrag: AnyObject {
    func verbinde() async throws
    func trenne()
    func rufe(_ fn: String, _ daten: [String: Any], zeitlimit: Double) async throws -> [String: Any]
    func lebt(frist: Double) async -> Bool
    var aufEreignis: ((VertragEreignis) -> Void)? { get set }
    var aufGetrennt: ((VertragFehler) -> Void)? { get set }
    var aufZugang: ((VertragZugang) -> Void)? { get set }
}

extension VertragNamen {
    static let altZuNeu: [String: String] = Dictionary(uniqueKeysWithValues: neuZuAlt.map { ($0.value, $0.key) })
}
