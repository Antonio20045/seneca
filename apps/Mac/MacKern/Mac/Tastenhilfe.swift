import Foundation

enum Tastenhilfe {
    struct Zeile: Equatable { let tasten: [String]; let text: String }

    static let zeilen: [Zeile] = [
        Zeile(tasten: ["g", "h"], text: "Heute"), Zeile(tasten: ["g", "k"], text: "Kalender"),
        Zeile(tasten: ["g", "e"], text: "Entscheiden"), Zeile(tasten: ["g", "r"], text: "Bereiche"),
        Zeile(tasten: ["g", "p"], text: "Projekte"),
        Zeile(tasten: ["g", "b"], text: "Berichte"), Zeile(tasten: ["g", "w"], text: "Projekte · Wartet auf dich"),
        Zeile(tasten: ["c"], text: "Gespräch einblenden und schreiben"), Zeile(tasten: ["n"], text: "Neues To-do (auf Heute)"),
        Zeile(tasten: ["\\"], text: "Gespräch ein- oder ausblenden"), Zeile(tasten: ["⌘K"], text: "Suchen"),
        Zeile(tasten: ["j", "k"], text: "Entscheidung wählen"), Zeile(tasten: ["1 – 4"], text: "Option wählen"),
        Zeile(tasten: ["⏎"], text: "Empfehlung bestätigen"), Zeile(tasten: ["h"], text: "Später"),
        Zeile(tasten: ["r"], text: "Rückfrage"), Zeile(tasten: ["o"], text: "Ganze Notiz"),
        Zeile(tasten: ["←", "→"], text: "Kalender: zurück und vor blättern"), Zeile(tasten: ["t"], text: "Kalender: heute"),
        Zeile(tasten: ["d", "w", "m"], text: "Kalender: Tag, Woche, Monat"),
        Zeile(tasten: ["Esc"], text: "Geöffnetes schließen"), Zeile(tasten: ["?"], text: "Diese Hilfe"),
    ]

    enum Befehl: Equatable {
        case gehe(Route)
        case gespraechZeigen, gespraechSchalten, neuesTodo, hilfeSchalten
    }

    static func befehl(_ zeichen: String, gAktiv: Bool) -> Befehl? {
        let z = zeichen.lowercased()
        if gAktiv {
            if z == "w" { return .gehe(Route(.projekte, q: ["ansicht": "wartet"])) }
            if let s = Seite.vonGTaste(z) { return .gehe(Route(s)) }
        }
        switch z {
        case "c": return .gespraechZeigen
        case "n": return .neuesTodo
        case "\\": return .gespraechSchalten
        case "?": return .hilfeSchalten
        default: return nil
        }
    }
}
