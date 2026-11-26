import Foundation

enum TagesSatz {
    static func satz(wartet: Int, aufDich: Int, naechster: (titel: String, minute: Int)?) -> String {
        func wort(_ n: Int) -> String { n > 0 && n < HeuteLogik.zahlwort.count ? HeuteLogik.zahlwort[n] : String(n) }
        let kopf: String
        if wartet <= 0 {
            kopf = "Nichts wartet"
        } else if aufDich <= 0 {
            kopf = wartet == 1 ? "Eine Sache wartet" : "\(wort(wartet)) Dinge warten"
        } else if aufDich >= wartet {
            kopf = wartet == 1 ? "Eine Sache wartet auf dich" : "\(wort(wartet)) Dinge warten auf dich"
        } else {
            kopf = "\(wort(wartet)) Dinge warten, \(aufDich == 1 ? "eines" : wort(aufDich).lowercased()) davon auf dich"
        }
        guard let n = naechster else { return kopf + "." }
        var titel = n.titel
        if titel.count > 26 { titel = String(titel.prefix(25)).trimmingCharacters(in: .whitespaces) + "…" }
        return kopf + String(format: " – um %02d:%02d %@.", n.minute / 60, n.minute % 60, titel)
    }
}

enum Tagesfortschritt {
    static func anteil(erledigt: Int, offen: Int) -> Double {
        let gesamt = erledigt + offen
        guard gesamt > 0 else { return 0 }
        return min(1, max(0, Double(erledigt) / Double(gesamt)))
    }
}

extension OverviewStore {
    var tagesFortschritt: Double { Tagesfortschritt.anteil(erledigt: todos.heuteErledigt.count, offen: heuteTodos.count) }
}
