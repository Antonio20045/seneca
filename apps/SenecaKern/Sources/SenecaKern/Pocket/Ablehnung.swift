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

    mutating func readCard(fromError e: [String: Any]) {
        let details = e["details"] as? [String: Any] ?? [:]
        guard let card = details["card"] as? [String: Any] else { return }
        cardStatus = card["status"] as? String
        cardUpdatedAt = (card["updatedAt"] as? NSNumber)?.doubleValue
    }

    func isConflictAlreadyAt(_ status: String) -> Bool {
        code.lowercased() == "workboard_conflict" && cardStatus == status
    }
}

enum ConnectFallback: Equatable {
    case retrySharedToken
    case retryWithoutAdmin(awaiting: Bool)
    case giveUp
    case repair

    static func backoff(versuch: Int) -> Double { min(30, pow(2, Double(max(0, versuch - 1)))) }

    static func decide(_ r: GatewayRefusal, askedAdmin: Bool, triedShared: Bool) -> ConnectFallback {
        let code = r.code.uppercased()
        if !askedAdmin {
            if !triedShared && (code.contains("DEVICE_TOKEN_MISMATCH") || code.contains("TOKEN_MISMATCH")) { return .repair }
            return .giveUp
        }
        if (code.contains("SCOPE_MISMATCH") || code.contains("DEVICE_TOKEN_MISMATCH")) && !triedShared { return .retrySharedToken }
        if triedShared && code.contains("DEVICE_TOKEN_MISMATCH") { return .repair }
        if code.contains("PAIRING") {
            if r.reason == "not-paired" { return .giveUp }
            return .retryWithoutAdmin(awaiting: r.reason == "scope-upgrade" || r.reason == "role-upgrade")
        }
        if code.contains("SCOPE") || code.contains("FORBIDDEN") || code.contains("UNAUTHORIZED") || code.contains("TOKEN_MISMATCH") {
            return .retryWithoutAdmin(awaiting: false)
        }
        return .giveUp
    }
}
