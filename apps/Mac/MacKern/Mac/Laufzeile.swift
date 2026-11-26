import Foundation

enum Laufzeile {
    static func dauer(_ seit: TimeInterval) -> String {
        seit < 60 ? "seit \(max(1, Int(seit))) Sek." : "seit \(Int(seit / 60)) Min."
    }

    static func text(name: String, phase: ChatLive.Phase, angekommen: Bool, taetigkeit: String?, schritte: Int, schreibt: Bool, seit: TimeInterval,
                     verbunden: Bool = true, mitDauer: Bool = true) -> String {
        guard mitDauer else {
            let mit = text(name: name, phase: phase, angekommen: angekommen, taetigkeit: taetigkeit, schritte: schritte, schreibt: schreibt, seit: max(seit, 2), verbunden: verbunden)
            let ohne = mit.components(separatedBy: " · seit ").first ?? mit
            return ohne.hasSuffix(".") ? ohne : ohne + "."
        }
        if !verbunden {
            return phase == .sending && !angekommen
                ? "Keine Verbindung. Deine Frage geht an \(name), sobald sie wieder steht."
                : "Keine Verbindung. Die Antwort läuft bei \(name) weiter und erscheint, sobald die Verbindung wieder steht."
        }
        let d = dauer(seit)
        switch phase {
        case .sending:
            if angekommen { return "\(name) hat deine Frage · \(d)" }
            return seit < 2 ? "Deine Frage geht an \(name)." : "Deine Frage ist unterwegs zu \(name) · \(d)"
        case .queued:
            return "\(name) ist noch mit etwas anderem beschäftigt und nimmt deine Frage als Nächstes."
        case .working, .writing:
            if schreibt || phase == .writing { return "\(name) schreibt die Antwort · \(d)" }
            if let t = taetigkeit?.trimmingCharacters(in: CharacterSet(charactersIn: " …."))  , !t.isEmpty { return "\(t) · \(d)" }
            if schritte > 0 { return "\(name) arbeitet · \(schritte) \(schritte == 1 ? "Schritt" : "Schritte") · \(d)" }
            return "\(name) hat deine Frage und denkt nach · \(d)"
        }
    }
}
