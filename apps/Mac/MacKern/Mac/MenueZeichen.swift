import Foundation

struct MenueZeichen: Equatable {
    enum Bild: Equatable { case blase, blaseVoll, mikrofon, erkennt, aufnahme, arbeitet, fokus }

    var bild: Bild
    var text: String?
    var ansage: String

    var punkt: String? { bild == .aufnahme ? "rot" : bild == .blaseVoll ? "bernstein" : nil }

    var symbol: String {
        switch bild {
        case .blase: return "text.bubble"
        case .blaseVoll: return "text.bubble.fill"
        case .mikrofon: return "mic.fill"
        case .erkennt: return "waveform"
        case .aufnahme: return "record.circle.fill"
        case .arbeitet: return "ellipsis.bubble"
        case .fokus: return "circle.lefthalf.filled"
        }
    }

    static func entscheide(diktat: DiktatWache.Phase, meetingNimmtAuf: Bool, meetingDauer: TimeInterval,
                           meetingArbeitet: Bool, braucht: Int, fokus: Bool = false) -> MenueZeichen {
        let zeit = meetingNimmtAuf ? MeetingTranskript.zeit(meetingDauer) : nil
        var teile = ["Seneca"]
        let bild: Bild
        switch diktat {
        case .hoert:
            bild = .mikrofon
            teile.append("Diktat hört zu")
        case .erkennt:
            bild = .erkennt
            teile.append("Diktat wird erkannt")
        default:
            bild = meetingNimmtAuf ? .aufnahme : meetingArbeitet ? .arbeitet : fokus ? .fokus : braucht > 0 ? .blaseVoll : .blase
        }
        if let zeit { teile.append("Meeting wird aufgenommen, \(zeit)") } else if meetingArbeitet { teile.append("Meeting wird ausgewertet") }
        if braucht > 0 { teile.append("\(braucht) braucht dich") }
        if fokus { teile.append("Fokus") }
        return MenueZeichen(bild: bild, text: zeit ?? (braucht > 0 && !fokus ? "\(braucht)" : nil), ansage: teile.joined(separator: ", "))
    }
}

enum MenueDiktatZiel: Equatable {
    case vorneLassen
    case zurueck
    case seneca

    static let toleranz: TimeInterval = 0.6

    static func entscheide(senecaVorn: Bool, senecaAktivSeit: TimeInterval?, menueOffenSeit: TimeInterval?, hatFremde: Bool,
                           senecaWarVornBeimKlick: Bool? = nil) -> MenueDiktatZiel {
        guard senecaVorn else { return .vorneLassen }
        guard hatFremde else { return .seneca }
        if senecaWarVornBeimKlick == false { return .zurueck }
        if let aktiv = senecaAktivSeit, let offen = menueOffenSeit, aktiv >= offen - toleranz { return .zurueck }
        return .seneca
    }
}

struct DiktatAnzeige: Equatable {
    enum Art: Equatable { case startet, hoert, still, erkennt, fertig, fehler, beendet }

    var art: Art
    var titel: String
    var hinweis: String

    static let beenden = "Rechte ⌘ tippen, wenn du fertig bist · Esc bricht ab"

    private static func kurz(_ t: String, _ n: Int = 80) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count <= n ? s : String(s.prefix(n - 2)) + "…"
    }

    static func zeile(phase: DiktatWache.Phase, startet: Bool, still: Bool, text: String, beendetHinweis: Bool) -> DiktatAnzeige? {
        if beendetHinweis {
            let rest: String
            switch phase {
            case .erkennt: rest = "Erkenne …"
            case .eingefuegt, .fehler: rest = kurz(text)
            default: rest = "Das Mikrofon hat nichts mehr geliefert."
            }
            return DiktatAnzeige(art: .beendet, titel: "Aufnahme beendet", hinweis: rest)
        }
        switch phase {
        case .ruht: return nil
        case .hoert:
            if startet { return DiktatAnzeige(art: .startet, titel: "Starte …", hinweis: "Das Mikrofon wird geöffnet") }
            if still { return DiktatAnzeige(art: .still, titel: "Ich höre nichts", hinweis: beenden) }
            return DiktatAnzeige(art: .hoert, titel: "Hört zu …", hinweis: beenden)
        case .erkennt: return DiktatAnzeige(art: .erkennt, titel: "Erkenne …", hinweis: "")
        case .eingefuegt: return DiktatAnzeige(art: .fertig, titel: kurz(text), hinweis: "eingefügt")
        case .fehler:
            if text.localizedCaseInsensitiveContains("kein Wort zu hören") { return DiktatAnzeige(art: .fehler, titel: "Kein Wort zu hören", hinweis: "") }
            return DiktatAnzeige(art: .fehler, titel: kurz(text, 160), hinweis: "")
        }
    }
}

enum MeetingMeldung {
    static func soll(vorherWertetAus: Bool, jetztFertig: Bool, hatDatei: Bool, fensterVorn: Bool) -> Bool {
        vorherWertetAus && jetztFertig && hatDatei && !fensterVorn
    }

    static func kennung(datei: String, zusammenfassungFehlt: Bool) -> String { datei + (zusammenfassungFehlt ? "|ohne" : "|mit") }

    static func text(titel: String, hatBeitraege: Bool, zusammenfassungFehlt: Bool) -> (titel: String, text: String) {
        let t = titel.trimmingCharacters(in: .whitespacesAndNewlines)
        let kopf = "Meeting-Notiz fertig: " + (t.isEmpty ? "Meeting" : t)
        if !hatBeitraege { return (kopf, "In der Aufnahme war nichts zu verstehen. Klick öffnet die Datei.") }
        if zusammenfassungFehlt { return (kopf, "Die Mitschrift liegt bereit, die Zusammenfassung hat nicht geklappt. Klick öffnet die Datei.") }
        return (kopf, "Mitschrift und Zusammenfassung liegen bereit. Klick öffnet die Datei.")
    }
}
