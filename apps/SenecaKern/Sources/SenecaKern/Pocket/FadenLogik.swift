import Foundation

enum FadenArt: Equatable, Sendable {
    case datum, frage, antwort
    case live, hinweis
}

struct FadenReihe: Identifiable, Equatable, Sendable {
    enum Inhalt: Equatable, Sendable {
        case datum(String)
        case nachricht(ChatMessage)
    }
    var id: String
    var art: FadenArt
    var inhalt: Inhalt
    var abstandOben: CGFloat
}

enum FadenLogik {
    static let pause: TimeInterval = 3 * 3600
    static let endeToleranz: CGFloat = 60

    static func abstand(von vorher: FadenArt?, zu art: FadenArt) -> CGFloat {
        guard let vorher else { return 0 }
        if art == .datum { return 48 }
        switch (vorher, art) {
        case (.datum, _): return 14
        case (.frage, .antwort), (.frage, .live), (.frage, .hinweis): return 12
        case (.frage, .frage): return 16
        case (.antwort, .frage): return 40
        case (.antwort, .antwort): return 28
        case (.antwort, .live), (.antwort, .hinweis): return 12
        case (.live, _), (.hinweis, _): return 12
        default: return 16
        }
    }

    static func zeilen(_ messages: [ChatMessage], now: Date, calendar: Calendar = .current) -> [FadenReihe] {
        var out: [FadenReihe] = []
        var letzteArt: FadenArt?
        var letztesDatum: Date?
        func anhaengen(_ id: String, _ art: FadenArt, _ inhalt: FadenReihe.Inhalt) {
            out.append(FadenReihe(id: id, art: art, inhalt: inhalt, abstandOben: abstand(von: letzteArt, zu: art)))
            letzteArt = art
        }
        for message in messages {
            if let date = message.date {
                let neu: Bool
                if let letztes = letztesDatum {
                    neu = !calendar.isDate(date, inSameDayAs: letztes) || date.timeIntervalSince(letztes) >= pause
                } else {
                    neu = true
                }
                if neu { anhaengen("datum-\(message.id)", .datum, .datum(datumText(date, now: now, calendar: calendar))) }
                letztesDatum = date
            }
            anhaengen(message.id, message.role == .user ? .frage : .antwort, .nachricht(message))
        }
        return out
    }

    static func datumText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let locale = Locale(identifier: "de_DE")
        func format(_ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = locale
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateFormat = pattern
            return f.string(from: date)
        }
        let uhr = format("H:mm")
        let tage = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        if tage == 0 { return "Heute, \(uhr)" }
        if tage == 1 { return "Gestern, \(uhr)" }
        if tage > 1 && tage <= 6 { return "\(format("EEEE")), \(uhr)" }
        let gleichesJahr = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return "\(format(gleichesJahr ? "d. MMMM" : "d. MMMM yyyy")), \(uhr)"
    }

    static func amEnde(markeUnten: CGFloat, sichtUnten: CGFloat) -> Bool {
        markeUnten <= sichtUnten + endeToleranz
    }


    private static func ohneOffenes(_ zeile: String) -> String {
        var s = zeile
        if let teil = s.range(of: "](", options: .backwards), !s[teil.upperBound...].contains(")") {
            if let auf = s[..<teil.lowerBound].lastIndex(of: "[") {
                s = String(s[..<auf]) + String(s[s.index(after: auf)..<teil.lowerBound])
            }
        } else if let auf = s.lastIndex(of: "["), !s[auf...].contains("]") {
            s.remove(at: auf)
        }
        for marke in ["**", "`", "_"] {
            if s.components(separatedBy: marke).count % 2 == 0, let r = s.range(of: marke, options: .backwards) { s.removeSubrange(r) }
        }
        return s
    }

    static func mindesthoehe(sichtHoehe: CGFloat, mitTrenner: Bool, luftUnten: CGFloat = 24) -> CGFloat {
        max(0, sichtHoehe - luftUnten + (mitTrenner ? 1 : 0))
    }

    static func anfangOben(sichtHoehe: CGFloat, frageOben: CGFloat, endeUnten: CGFloat) -> Bool {
        endeUnten - frageOben > sichtHoehe + 1
    }
}

enum FadenZustandsAnzeige: Equatable, Sendable {
    case wirdGesendet
    case angekommen
    case nichtGesendet
    case keineAntwort
}

extension FadenLogik {
    static func zustandsAnzeige(_ zustand: ZustellZustand?, istLetzteEigene: Bool, antwortFehlt: Bool = false) -> FadenZustandsAnzeige? {
        guard let zustand else { return nil }
        switch zustand {
        case .fehlgeschlagen: return antwortFehlt && istLetzteEigene ? .keineAntwort : .nichtGesendet
        case .wirdGesendet: return istLetzteEigene ? .wirdGesendet : nil
        case .angekommen, .arbeitet: return istLetzteEigene ? .angekommen : nil
        case .fertig: return nil
        }
    }

    static func seitText(seit: Date, jetzt: Date) -> String? {
        let s = Int(jetzt.timeIntervalSince(seit))
        if s < 10 { return nil }
        if s < 60 { return "seit \(s) s" }
        return s % 60 == 0 ? "seit \(s / 60) Min." : "seit \(s / 60) Min. \(s % 60) s"
    }
}
