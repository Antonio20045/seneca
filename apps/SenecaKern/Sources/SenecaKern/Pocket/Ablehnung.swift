import Foundation

enum SenecaError: LocalizedError {
    case message(String)
    case rejected(String)
    case refused(GatewayRefusal)
    case stopped
    case offline
    case nichtGesendet
    var errorDescription: String? {
        switch self {
        case .message(let value), .rejected(let value): return value
        case .refused(let r): return r.message
        case .stopped: return "Die Antwort wurde gestoppt."
        case .offline: return "Dein Mac ist gerade nicht erreichbar."
        case .nichtGesendet: return "Deine Frage ist nicht beim Mac angekommen."
        }
    }
}

struct GatewayRefusal: Equatable, Sendable {
    var code: String
    var reason: String?
    var requestId: String?
    var message: String
    var cardStatus: String?
    var cardUpdatedAt: Double?

    func isConflictAlreadyAt(_ status: String) -> Bool {
        code.lowercased() == "workboard_conflict" && cardStatus == status
    }
}
