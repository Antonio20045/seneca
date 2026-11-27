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

enum MeetingMeldung {
    static func soll(vorherWertetAus: Bool, jetztFertig: Bool, hatDatei: Bool, fensterVorn: Bool) -> Bool {
        vorherWertetAus && jetztFertig && hatDatei && !fensterVorn
    }

    static func kennung(datei: String, zusammenfassungFehlt: Bool) -> String { datei + (zusammenfassungFehlt ? "|ohne" : "|mit") }

    static func text(_ e: MeetingErgebnis, vorschlaege n: Int) -> (titel: String, text: String, knoepfe: [String]) {
        let kopf = "Notiz zum " + (e.termin.map { _ in e.titel.components(separatedBy: ": ").first ?? e.titel } ?? "Gespräch")
        if e.segmente.isEmpty { return (kopf, "In der Aufnahme war nichts zu verstehen.", ["Ansehen"]) }
        if case .ohneZusammenfassung = e.stand { return (kopf, "Die Mitschrift liegt bereit, die Zusammenfassung hat nicht geklappt.", ["Ansehen"]) }
        let satz = e.zusammenfassung.components(separatedBy: CharacterSet(charactersIn: ",.")).first ?? ""
        return (kopf, satz + (n > 0 ? " · \(n) \(n == 1 ? "Vorschlag" : "Vorschläge") für dich" : ""), n > 0 ? ["Ansehen", "\(n) übernehmen"] : ["Ansehen"])
    }
}
