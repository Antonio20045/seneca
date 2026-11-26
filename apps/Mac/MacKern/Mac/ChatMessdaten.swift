import Foundation

enum ChatMessdaten {
    private static let satz = ["Der", "Verlauf", "bleibt", "ruhig", "stehen,", "auch", "wenn", "unten", "weiter", "geschrieben", "wird,",
                               "und", "die", "Ansicht", "folgt", "nur,", "solange", "du", "am", "Ende", "liest."]

    static func langeAntwort(woerter: Int = 5000) -> String {
        var teile: [String] = ["Hier ist die ausführliche Fassung mit allen Schritten."]
        var n = 8
        var abschnitt = 0
        func absatz(_ saetze: Int) -> String {
            n += saetze * satz.count
            return Array(repeating: satz.joined(separator: " "), count: saetze).joined(separator: " ")
        }
        while n < woerter {
            abschnitt += 1
            teile.append("## Abschnitt \(abschnitt)")
            teile.append(absatz(4))
            teile.append((1...5).map { "- Punkt \($0): " + satz.prefix(12).joined(separator: " ") }.joined(separator: "\n"))
            n += 5 * 14
            teile.append(absatz(3))
            if abschnitt % 2 == 1 {
                teile.append("```swift\n" + (1...14).map { "let wert\($0) = berechne(schritt: \($0), abschnitt: \(abschnitt))" }.joined(separator: "\n") + "\n```")
                n += 14 * 6
            } else {
                teile.append((1...4).map { "\($0). Schritt \($0): " + satz.prefix(10).joined(separator: " ") }.joined(separator: "\n\n"))
                n += 4 * 12
            }
            if abschnitt % 5 == 0 {
                teile.append("| Messung | Vorher | Nachher |\n|---|---|---|\n| Öffnen | langsam | schnell |\n| Strom | ruckelt | ruhig |")
                n += 16
            }
            teile.append(absatz(2))
        }
        return teile.joined(separator: "\n\n")
    }

    static func nurMeldungen() -> [[String: Any]] {
        let t = 1_794_000_000_000.0
        func meldung(_ i: Double, _ text: String) -> [String: Any] {
            ["role": "assistant", "timestamp": t + i * 60_000, "senderLabel": "Forwarded from agent:planung:main", "content": text,
             "provenance": ["kind": "inter_session", "sourceTool": "sessions_send", "sourceSessionKey": "agent:planung:main"]]
        }
        func antwort(_ i: Double, _ text: String) -> [String: Any] {
            ["role": "assistant", "timestamp": t + i * 60_000, "stopReason": "stop", "content": [["type": "text", "text": text]]]
        }
        return [meldung(1, "Von der Planung: Die fünf Karten stehen bereit."), antwort(2, "Ich bringe die fünf Karten in Ordnung und melde mich."),
                meldung(3, "Danke, die Karten stehen."), antwort(4, "Die Karte zum Beleg ist abgelegt."),
                ["role": "user", "timestamp": t + 5 * 60_000, "content": "A scheduled reminder has been triggered. The reminder content is: Tageslauf prüfen"],
                antwort(6, "Ich habe den Tageslauf geprüft, alles steht.")]
    }

    static func verlauf(nachrichten: Int = 200) -> [[String: Any]] {
        var t = 1_794_000_000_000.0
        return (0..<nachrichten).map { i in
            t += 30_000
            if i % 2 == 0 {
                return ["role": "user", "timestamp": t, "content": [["type": "text", "text": "Frage \(i / 2 + 1): Wie steht es um Teil \(i / 2 + 1)?"]], "__openclaw": ["senderId": "gateway-owner"]]
            }
            let text = i % 8 == 7 ? langeAntwort(woerter: 400) : "Teil \(i / 2 + 1) liegt im Plan.\n\n" + Array(repeating: satz.joined(separator: " "), count: 3).joined(separator: " ")
            return ["role": "assistant", "timestamp": t, "stopReason": "stop", "content": [["type": "text", "text": text]]]
        }
    }
}
