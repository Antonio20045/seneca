import Foundation

enum Laufzeile {
    struct Teile: Equatable { var haupt: String; var neben = ""; var haengt = false; var anhalten = true }
    static var haengtNach: TimeInterval { AppRegel.wert("gespraech_haengt_hinweis_min", 2) * 60 }
    static var anhaltenNach: TimeInterval { AppRegel.wert("gespraech_haengt_stopp_min", 10) * 60 }
    static let satzTakt: TimeInterval = 1.2

    static func teile(name: String, phase: ChatLive.Phase, taetigkeit: String?, schritte: Int, seit: TimeInterval, ruhig: TimeInterval, letzterSchritt: Double?) -> Teile {
        if phase == .queued { return Teile(haupt: "\(name) schreibt noch eine andere Antwort", anhalten: false) }
        if ruhig >= haengtNach {
            return Teile(haupt: "\(name) antwortet seit \(Int(ruhig / 60)) Min nicht", neben: letzterSchritt.map { " · letzter Schritt " + Formate.hhmm($0) } ?? "", haengt: true, anhalten: false)
        }
        let t = taetigkeit?.trimmingCharacters(in: CharacterSet(charactersIn: " ….")) ?? ""
        let n = schritte == 0 ? "" : " · \(schritte) \(schritte == 1 ? "Schritt" : "Schritte")"
        return Teile(haupt: t.isEmpty ? "\(name) arbeitet" : t, neben: n + " · " + VerlaufLogik.uhrDauer(seit))
    }

    static func kurz(name: String, phase: ChatLive.Phase, taetigkeit: String?, verbunden: Bool) -> String {
        if !verbunden { return "Keine Verbindung. Deine Frage geht raus, sobald Seneca erreichbar ist." }
        switch phase {
        case .sending: return "Deine Frage geht an \(name)."
        case .queued: return "\(name) schreibt noch eine andere Antwort."
        case .working, .writing:
            let t = taetigkeit?.trimmingCharacters(in: CharacterSet(charactersIn: " ….")) ?? ""
            return (t.isEmpty ? "\(name) arbeitet" : t) + "."
        }
    }
}
