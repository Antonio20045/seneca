import Foundation

struct AufgabenSchritt: Equatable, Identifiable {
    var id: Int
    var zeit: Date?
    var text: String
}

struct AufgabenVerlauf: Equatable {
    var id: String
    var titel: String?
    var zustand: AufgabenZustand?
    var auftrag: String?
    var schritte: [AufgabenSchritt] = []
    var schritteGesamt = 0
    var quelleSchritte: String?
    var letzterText: String?
    var ergebnis: String?
    var hinweis: String?
    var teile: [Aufgabe] = []

    var schritteNeuesteZuerst: [AufgabenSchritt] { schritte.reversed() }

    var anzahlSchritte: Int { max(schritteGesamt, schritte.count) }

    enum Antwort: Equatable {
        case da(AufgabenVerlauf)
        case fehler(String)
    }

    static func lies(_ daten: Data, jetzt: Date = Date(), kalender: Calendar = .current) -> Antwort? {
        guard let w = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any] else { return nil }
        func text(_ k: String) -> String? {
            guard let s = w[k] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let f = text("fehler") { return .fehler(f) }
        guard let id = text("id") else { return nil }
        var v = AufgabenVerlauf(id: id)
        v.titel = text("titel")
        v.zustand = text("zustand").flatMap(AufgabenZustand.init(rawValue:))
        v.auftrag = text("auftrag"); v.letzterText = text("letzter_text"); v.ergebnis = text("ergebnis"); v.hinweis = text("hinweis")
        v.quelleSchritte = text("quelle_schritte")
        var n = 0
        for roh in (w["schritte"] as? [Any]) ?? [] {
            defer { n += 1 }
            guard let s = roh as? [String: Any], let t = (s["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
            v.schritte.append(AufgabenSchritt(id: n, zeit: AufgabenZeit.lies(s["zeit"]), text: t))
        }
        v.schritteGesamt = (w["schritte_gesamt"] as? NSNumber)?.intValue ?? v.schritte.count
        v.teile = ((w["teile"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).flatMap { Aufgabe.lies($0, jetzt: jetzt, kalender: kalender, mitTeilen: false) } }
        return .da(v)
    }

    init(id: String) { self.id = id }
}

extension AufgabenSchritt {
    func uhr(jetzt: Date, kalender: Calendar = .current) -> String {
        zeit.map { ListenText.uhr($0, jetzt: jetzt, kalender: kalender) } ?? ""
    }
}

extension Aufgabe {
    func kopfzeile(jetzt: Date, kalender: Calendar = .current) -> String {
        let start = (zustand == .laeuft || zustand == .haengt) ? (begonnen ?? seit) : (zustand.erledigt ? abschluss : seit)
        let ab = start.map { "seit " + ListenText.uhr($0, jetzt: jetzt, kalender: kalender) }
        return [wer, [zustand.wort, ab].compactMap { $0 }.joined(separator: " ")].compactMap { $0 }.joined(separator: " · ")
    }

    var detailSatz: String? {
        switch zustand {
        case .haengt, .abgebrochen, .brauchtDich: return grund ?? hinweis
        default: return hinweis
        }
    }

    var fertigHinweis: String? { zustand == .fertig && vonAntonio ? hinweis : nil }
}
