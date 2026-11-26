import Foundation

enum Entscheiden {
    struct Wahl: Equatable {
        var wahl: String?
        var text: String?
        var notiz: String?
        init(wahl: String?, text: String? = nil, notiz: String? = nil) { self.wahl = wahl; self.text = text; self.notiz = notiz }
    }

    struct Gruppe: Equatable {
        enum Art: String { case faellig, woche, ohne, spaeter }
        var art: Art
        var titel: String
        var liste: [OvEntscheidung]
    }

    struct Tag: Equatable {
        var id: String
        var label: String
        var bis: Double
    }

    static func gruppiere(_ liste: [OvEntscheidung], jetzt: Double) -> [Gruppe] {
        let heute = Menschlich.tagStart(jetzt)
        let woche = heute + 7 * Menschlich.tag
        var g = [Gruppe(art: .faellig, titel: "Überfällig und heute", liste: []), Gruppe(art: .woche, titel: "Diese Woche", liste: []),
                 Gruppe(art: .ohne, titel: "Ohne Termin", liste: []), Gruppe(art: .spaeter, titel: "Später", liste: [])]
        for e in liste {
            let termin = e.frist ?? e.plan
            if e.ruhend { g[3].liste.append(e) }
            else if let t = termin, t <= heute { g[0].liste.append(e) }
            else if let t = termin, t < woche { g[1].liste.append(e) }
            else if termin == nil && jetzt - e.gestelltAm > 3 * Menschlich.tag { g[0].liste.append(e) }
            else { g[2].liste.append(e) }
        }
        for i in g.indices {
            g[i].liste = g[i].liste.enumerated().sorted { a, b in
                let x = a.element.frist ?? a.element.plan ?? .infinity, y = b.element.frist ?? b.element.plan ?? .infinity
                if x != y { return x < y }
                if a.element.gestelltAm != b.element.gestelltAm { return a.element.gestelltAm < b.element.gestelltAm }
                return a.offset < b.offset
            }.map(\.element)
        }
        return g.filter { !$0.liste.isEmpty }
    }

    static func ueberfaellig(_ e: OvEntscheidung, jetzt: Double) -> Bool {
        guard let f = e.frist else { return false }
        return f < Menschlich.tagStart(jetzt)
    }

    static func offene(_ liste: [OvEntscheidung]) -> [OvEntscheidung] { liste.filter { !$0.ruhend } }

    static func vorwahl(_ e: OvEntscheidung) -> String? {
        guard let k = e.empfehlung?.key, e.optionen.contains(where: { $0.key == k }) else { return nil }
        return k
    }

    static func wahlText(_ e: OvEntscheidung, _ w: Wahl) -> String {
        if let k = w.wahl {
            if let o = e.optionen.first(where: { $0.key == k }) { return "\(o.key) — \(o.titel)" }
            return k
        }
        if let t = w.text, !t.isEmpty { return "Anders: \(t)" }
        return "Ohne Auswahl"
    }

    static func nachrichtAnLeiter(_ e: OvEntscheidung, _ w: Wahl) -> String {
        let notiz = [w.wahl != nil ? (w.text ?? "") : "", w.notiz ?? ""].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let ohnePunkt = notiz.replacingOccurrences(of: #"[.\s]*$"#, with: "", options: .regularExpression)
        return "Antonio hat entschieden: \(e.frage) → \(wahlText(e, w)).\(notiz.isEmpty ? "" : " " + ohnePunkt + ".") Bitte umsetzen, abhängige Karten entsperren und die Karte aktuell halten."
    }

    static func naechsteTage(jetzt: Double) -> [Tag] {
        let heute = Menschlich.tagStart(jetzt)
        let wd = Calendar.current.component(.weekday, from: Date(timeIntervalSince1970: heute / 1000)) - 1
        let morgen = Menschlich.addTage(heute, 1)
        var tage = (8 - wd) % 7
        if tage == 0 { tage = 7 }
        let montag = Menschlich.addTage(heute, tage)
        let woche = Menschlich.addTage(heute, 7)
        var out = [Tag(id: "morgen", label: "Morgen", bis: morgen)]
        if montag > morgen && montag < woche { out.append(Tag(id: "montag", label: "Montag", bis: montag)) }
        out.append(Tag(id: "woche", label: "Nächste Woche", bis: woche))
        return out
    }

    static func vor(_ ms: Double, jetzt: Double) -> String {
        Menschlich.seitText(ms, jetzt: jetzt).replacingOccurrences(of: "seit ", with: "vor ")
            .replacingOccurrences(of: "vor heute", with: "heute").replacingOccurrences(of: "vor gestern", with: "gestern")
    }

    static func ganzerSatz(_ t: String) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let l = s.last else { return s }
        return ".!?…".contains(l) ? s : s + "."
    }

    static func kurzText(_ e: OvEntscheidung) -> (kurz: String, rest: String) {
        if let k = e.kurz, !k.isEmpty { return (k, e.kontext) }
        let s = Menschlich.saetze(e.kontext)
        return (s.prefix(2).joined(separator: " "), s.dropFirst(2).joined(separator: " "))
    }

    static func alle(_ roh: [OvEntscheidung], lokalSpaeter: [String: Double], weg: Set<String>, jetzt: Double) -> [OvEntscheidung] {
        roh.map { e in
            if let l = lokalSpaeter[e.id], l > jetzt { var x = e; x.ruhend = true; x.bis = max(l, e.bis ?? 0); return x }
            return e
        }.filter { !weg.contains($0.id) }
    }
}
