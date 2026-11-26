import Foundation

enum Zugang {
    static let standardAdresse = SimulatorSperre.standardAdresse
    static let konto = "zugangsschluessel"

    static var adresse: String? {
        get { UserDefaults.standard.string(forKey: MacPfade.adresseSchluessel) }
        set { UserDefaults.standard.set(newValue, forKey: MacPfade.adresseSchluessel) }
    }

    static func schluessel() -> String? {
        Schluesselbund.lies(konto).flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func schluesselAbseits() async -> String? {
        await Schluesselbund.liesAbseits(konto).flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func speichere(adresse: String, schluessel: String) throws {
        try Schluesselbund.speichere(Data(schluessel.utf8), konto: konto)
        Self.adresse = adresse
    }

    static func entferne() {
        if let a = adresse { Schluesselbund.loescheGeraeteToken(adresse: a) }
        Schluesselbund.loesche(konto)
        Self.adresse = nil
    }

    static func pruefe(adresse: String, schluessel: String) -> String? {
        let a = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let teile = URLComponents(string: a), let host = teile.host, !host.isEmpty,
              ["http", "https", "ws", "wss"].contains(teile.scheme?.lowercased() ?? "") else {
            return "Die Adresse sieht nicht richtig aus. Sie beginnt mit http:// oder https://."
        }
        if schluessel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Trage den Zugangsschlüssel ein." }
        return nil
    }
}

enum Verbindungsmeldung: Equatable {
    case freigabe(nummer: String?)
    case nichtErreichbar
    case abgelehnt(String)

    static func aus(fehlertext: String?) -> Verbindungsmeldung {
        let t = (fehlertext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: "Geräteanfrage:") {
            let nummer = t[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return .freigabe(nummer: nummer.isEmpty ? nil : nummer)
        }
        if t.contains("freigegeben werden") { return .freigabe(nummer: nil) }
        let abgelehnt = ["Zugangsschlüssel", "angemeldet", "Signatur", "Token", "Recht", "ungültig"]
        if !t.isEmpty, abgelehnt.contains(where: { t.localizedCaseInsensitiveContains($0) }) { return .abgelehnt(t) }
        return .nichtErreichbar
    }
}
