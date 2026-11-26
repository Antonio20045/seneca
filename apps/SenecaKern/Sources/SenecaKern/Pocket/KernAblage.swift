import Foundation

struct KernAblage: Schluesselablage {
    func lies(_ konto: String) async -> Data? { await Schluesselbund.liesAbseits(konto) }
    func speichere(_ daten: Data, konto: String) async throws { try await Schluesselbund.speichereAbseits(daten, konto: konto) }
    func loesche(_ konto: String) async { await Schluesselbund.loescheAbseits(konto) }
}

extension VerbindungsFehler {
    var alsSenecaFehler: SenecaError {
        if self == .offline || code == "ZEITLIMIT" || code == "NETZ" || code == "STILLE" { return .offline }
        var r = GatewayRefusal(code: code, reason: details, requestId: anfrage, message: text)
        r.cardStatus = karteStatus
        r.cardUpdatedAt = karteZeit
        return .refused(r)
    }
}
