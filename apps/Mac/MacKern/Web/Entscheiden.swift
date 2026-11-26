import Foundation

enum Entscheiden {
    struct Wahl: Equatable {
        var wahl: String?
        var text: String?
        var notiz: String?
        init(wahl: String?, text: String? = nil, notiz: String? = nil) { self.wahl = wahl; self.text = text; self.notiz = notiz }
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

    static func alle(_ roh: [OvEntscheidung], lokalSpaeter: [String: Double], weg: Set<String>, jetzt: Double) -> [OvEntscheidung] {
        roh.map { e in
            if let l = lokalSpaeter[e.id], l > jetzt { var x = e; x.ruhend = true; x.bis = max(l, e.bis ?? 0); return x }
            return e
        }.filter { !weg.contains($0.id) }
    }
}
