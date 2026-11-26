import Foundation

struct FuerDichZeile: Equatable, Identifiable {
    enum Art: String, CaseIterable { case antwort, rueckfrage, entscheidung, abnahme, aufgabe }
    var id: String
    var art: Art
    var satz: String
    var wortlaut: String
    var von = ""
    var bereich = ""
    var seit: Date? = nil
    var beleg: [String] = []
    var geprueft = false
    var ergebnis = ""
    var worum = ""
    var empfehlung = ""
    var frist = ""
    var ueberfaellig = false
}

struct LaeuftZeile: Equatable, Identifiable {
    enum Art: String, CaseIterable { case auftrag, arbeit, pruefung }
    var id: String
    var art: Art
    var satz: String
    var wortlaut: String
    var von = ""
    var bereich = ""
    var seit: Date? = nil
    var stand = ""
    var runde = 0
    var zuletzt: Date? = nil
}

enum FuerDich {
    struct Zeile: Equatable, Identifiable {
        var id: String
        var ziel: String
        var titel: String
        var wortlaut: String
        var von: String
        var nebenzeile: String
        var mahnung = ""
        var stand = ""
        var laeuft = false
    }

    struct Gruppe: Equatable, Identifiable {
        var art: FuerDichZeile.Art
        var satz: String
        var zeilen: [Zeile]
        var id: String { art.rawValue }
    }

    static let keinStand = ("Gerade liegt ", "kein Stand vor.")
    static let keinStandSatz = "Dazu liegt gerade kein Stand vor."

    private static func text(_ v: Any?) -> String { (v as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    static func zeilen(_ roh: Any?, zeit: (Any?) -> Date?) -> [FuerDichZeile]? {
        guard let liste = roh as? [Any] else { return nil }
        return liste.compactMap { $0 as? [String: Any] }.compactMap { z in
            let id = text(z["id"]), wortlaut = text(z["wortlaut"])
            let satz = text(z["satz"]).isEmpty ? wortlaut : text(z["satz"])
            guard !id.isEmpty, let art = FuerDichZeile.Art(rawValue: text(z["art"])), !satz.isEmpty || art == .antwort else { return nil }
            var f = FuerDichZeile(id: id, art: art, satz: satz, wortlaut: wortlaut.isEmpty ? satz : wortlaut, von: text(z["von"]), bereich: text(z["bereich"]), seit: zeit(z["seit"]))
            f.beleg = ((z["beleg"] as? [Any]) ?? []).map { text($0) }.filter { !$0.isEmpty }
            f.geprueft = (z["geprueft"] as? Bool) ?? false
            f.ergebnis = text(z["ergebnis"])
            f.worum = text(z["worum"])
            f.empfehlung = (z["empfehlung"] as? [String: Any]).map { text($0["text"]) } ?? text(z["empfehlung"])
            f.frist = text(z["frist"])
            f.ueberfaellig = (z["ueberfaellig"] as? Bool) ?? false
            return f
        }
    }

    static func laeuft(_ roh: Any?, zeit: (Any?) -> Date?) -> [LaeuftZeile]? {
        guard let liste = roh as? [Any] else { return nil }
        return liste.compactMap { $0 as? [String: Any] }.compactMap { z in
            let id = text(z["id"]), wortlaut = text(z["wortlaut"])
            let satz = text(z["satz"]).isEmpty ? wortlaut : text(z["satz"])
            guard !id.isEmpty, let art = LaeuftZeile.Art(rawValue: text(z["art"])), !satz.isEmpty else { return nil }
            return LaeuftZeile(id: id, art: art, satz: satz, wortlaut: wortlaut.isEmpty ? satz : wortlaut, von: text(z["von"]), bereich: text(z["bereich"]),
                               seit: zeit(z["seit"]), stand: text(z["stand"]), runde: (z["runde"] as? NSNumber)?.intValue ?? 0, zuletzt: zeit(z["zuletzt"]))
        }
    }

    static func anzahl(_ zeilen: [FuerDichZeile]) -> [FuerDichZeile.Art: Int] { Dictionary(grouping: zeilen, by: \.art).mapValues(\.count) }

    private static let ab13 = ["Dreizehn", "Vierzehn", "Fünfzehn", "Sechzehn", "Siebzehn", "Achtzehn", "Neunzehn", "Zwanzig"]

    private static func zahl(_ n: Int, gross: Bool) -> String {
        let w = n > 1 && n < HeuteLogik.zahlwort.count ? HeuteLogik.zahlwort[n] : (n >= 13 && n <= 20 ? ab13[n - 13] : String(n))
        return gross ? w : w.lowercased()
    }

    static func satz(_ alle: [FuerDichZeile], laeuft: Int, ohne: Set<String> = []) -> (String, String) {
        let f = alle.filter { !($0.art == .aufgabe && ohne.contains($0.id)) }
        let rest = laeuft == 1 ? "eine Arbeit läuft." : "\(zahl(laeuft, gross: false)) Arbeiten laufen."
        if f.isEmpty { return laeuft > 0 ? ("Nichts wartet auf dich, ", rest) : ("Gerade ist ", "nichts offen.") }
        let worte: [(FuerDichZeile.Art, String, String)] = [(.antwort, "ein Mensch", "Menschen"), (.rueckfrage, "eine Rückfrage", "Rückfragen"),
            (.entscheidung, "eine Entscheidung", "Entscheidungen"), (.abnahme, "eine Abnahme", "Abnahmen"), (.aufgabe, "eine Aufgabe", "Aufgaben")]
        let teile: [String] = worte.compactMap { art, eine, viele in
            let n = f.filter { $0.art == art }.count
            return n == 0 ? nil : (n == 1 ? eine : zahl(n, gross: false) + " " + viele)
        }
        var kopf = teile.count > 1 ? teile.dropLast().joined(separator: ", ") + " und " + teile[teile.count - 1] : teile[0]
        kopf = kopf.prefix(1).uppercased() + kopf.dropFirst() + (f.count == 1 ? " wartet " : " warten ")
        return laeuft > 0 ? (kopf + "auf dich, ", rest) : (kopf, "auf dich.")
    }

    static func standKurz(_ s: String, max: Int = 90) -> String {
        let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard t.count > max else { return t }
        let ganz = Arbeitsplan.ganzeSaetze(t, max: max)
        if ganz.count <= max, ganz.count >= 30, let ende = ganz.last, ".!?".contains(ende) { return ganz }
        var tiefe = 0, schnitt: String.Index?
        for i in t.prefix(max).indices {
            switch t[i] {
            case "(": tiefe += 1
            case ")": tiefe = Swift.max(0, tiefe - 1)
            case ",", ";": if tiefe == 0, t.distance(from: t.startIndex, to: i) >= 20 { schnitt = i }
            default: break
            }
        }
        if let schnitt { return String(t[..<schnitt]) + "." }
        return TageslaufSicht.gekuerzt(t, auf: max)
    }

    static func lageSatz(_ n: Int) -> String {
        if n <= 0 { return "Nichts wartet auf dich." }
        return n == 1 ? "Eine Sache wartet auf dich." : "\(zahl(n, gross: true)) Dinge warten auf dich."
    }

    static func gruppenSatz(_ art: FuerDichZeile.Art, _ n: Int) -> String {
        let z = zahl(n, gross: true)
        switch art {
        case .entscheidung: return n == 1 ? "Eine Frage braucht deine Entscheidung." : "\(z) Fragen brauchen deine Entscheidung."
        case .abnahme: return n == 1 ? "Ein Ergebnis wartet auf deine Abnahme." : "\(z) Ergebnisse warten auf deine Abnahme."
        case .aufgabe: return n == 1 ? "Eine Aufgabe liegt bei dir." : "\(z) Aufgaben liegen bei dir."
        case .antwort: return n == 1 ? "Ein Mensch wartet auf deine Antwort." : "\(z) Menschen warten auf deine Antwort."
        case .rueckfrage: return n == 1 ? "Ein Mitarbeiter kommt ohne dich nicht weiter." : "\(z) Mitarbeiter kommen ohne dich nicht weiter."
        }
    }

    static func wartende(_ f: [FuerDichZeile], jetzt: Date, kalender: Calendar = .current) -> [TageslaufSicht.Wartet] {
        func eine(_ z: FuerDichZeile) -> TageslaufSicht.Wartet {
            let w = TageslaufWartet(wer: z.von, seit: z.seit, seitRoh: "", chat: z.bereich, worum: z.satz)
            if z.art == .antwort {
                return .init(id: "antwort|" + z.id, name: z.von.isEmpty ? "Jemand" : z.von, rest: TageslaufSicht.wartetRest(w, jetzt: jetzt, kalender: kalender))
            }
            return .init(id: "rueckfrage|" + z.id, name: z.von.isEmpty ? "Ein Mitarbeiter" : z.von, rest: TageslaufSicht.fragtRest(w, klar: z.satz, jetzt: jetzt, kalender: kalender),
                         mensch: false, wortlaut: !z.worum.isEmpty && z.worum != z.satz ? z.worum : (z.wortlaut == z.satz ? "" : z.wortlaut))
        }
        return f.filter { $0.art == .antwort }.map(eine) + f.filter { $0.art == .rueckfrage }.map(eine)
    }

    static func titel(_ z: FuerDichZeile) -> String {
        guard z.art == .abnahme else { return z.satz }
        var s = z.satz
        for schluss in [" ist fertig und wartet auf deine Prüfung.", " sind fertig und warten auf deine Prüfung.", " ist fertig und wartet auf deine Abnahme.", " sind fertig und warten auf deine Abnahme."] where s.hasSuffix(schluss) {
            s = String(s.dropLast(schluss.count))
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        return s.isEmpty ? z.satz : s
    }

    static func gruppen(_ f: [FuerDichZeile], ohne: Set<String> = [], jetzt: Date, kalender: Calendar = .current) -> [Gruppe] {
        [FuerDichZeile.Art.entscheidung, .abnahme, .aufgabe].compactMap { art in
            let teil = f.filter { $0.art == art && !(art == .aufgabe && ohne.contains($0.id)) }
            guard !teil.isEmpty else { return nil }
            return Gruppe(art: art, satz: gruppenSatz(art, teil.count), zeilen: teil.map { z in
                let seit = z.seit.map { TageslaufZeit.seit($0, jetzt: jetzt, kalender: kalender) } ?? ""
                let neben = [z.von.isEmpty ? z.bereich : z.von, art == .abnahme && z.geprueft ? "vom Prüfer geprüft" : "", seit].filter { !$0.isEmpty }.joined(separator: " · ")
                return Zeile(id: z.id, ziel: (art == .entscheidung ? "e:" : "k:") + z.id, titel: titel(z), wortlaut: z.wortlaut, von: z.von, nebenzeile: neben,
                             mahnung: z.ueberfaellig ? "überfällig" : "")
            })
        }
    }

    static func laufend(_ l: [LaeuftZeile], jetzt: Date, kalender: Calendar = .current) -> [Zeile] {
        l.map { z in
            let zusatz: String
            switch z.art {
            case .auftrag: zusatz = z.runde > 0 ? "Runde \(z.runde)" : ""
            case .arbeit: zusatz = z.seit.map { TageslaufZeit.seit($0, jetzt: jetzt, kalender: kalender) } ?? ""
            case .pruefung: zusatz = "liegt beim Prüfer"
            }
            return Zeile(id: z.id, ziel: "k:" + z.id, titel: z.satz, wortlaut: z.wortlaut, von: z.von,
                         nebenzeile: [z.von.isEmpty ? z.bereich : z.von, zusatz].filter { !$0.isEmpty }.joined(separator: " · "),
                         stand: z.art == .auftrag ? standKurz(z.stand) : "", laeuft: true)
        }
    }
}
