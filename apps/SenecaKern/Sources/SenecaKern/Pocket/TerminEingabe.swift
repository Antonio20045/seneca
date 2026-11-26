import Foundation

enum TerminEingabeLogik {
    static let kalender = ["Privat", "Arbeit"]
    static let maxLaenge = 200

    static func naechsteVolleStunde(_ jetzt: Date, _ cal: Calendar = .current) -> Date {
        cal.dateInterval(of: .hour, for: jetzt)?.end ?? jetzt.addingTimeInterval(3600)
    }

    static func tagesEnde(_ datum: Date, _ cal: Calendar = .current) -> Date {
        let morgen = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: datum)) ?? datum
        return morgen.addingTimeInterval(-60)
    }

    static func vorgabe(jetzt: Date, _ cal: Calendar = .current) -> (tag: NeueAufgabeLogik.TagWahl, von: Date, bis: Date) {
        let volle = naechsteVolleStunde(jetzt, cal)
        if cal.isDate(volle, inSameDayAs: jetzt) {
            return (.heute, volle, min(volle.addingTimeInterval(3600), tagesEnde(jetzt, cal)))
        }
        let neun = cal.date(bySettingHour: 9, minute: 0, second: 0, of: jetzt) ?? jetzt
        return (.morgen, neun, neun.addingTimeInterval(3600))
    }

    static func bisNachVon(altVon: Date, altBis: Date, neuVon: Date, _ cal: Calendar = .current) -> Date {
        let dauer = altBis.timeIntervalSince(altVon)
        return min(neuVon.addingTimeInterval(dauer > 0 ? dauer : 3600), tagesEnde(neuVon, cal))
    }

    static func zeitraum(tag: NeueAufgabeLogik.TagWahl, datum: Date, von: Date, bis: Date, jetzt: Date,
                         _ cal: Calendar = .current) -> (start: Date, ende: Date) {
        let heute = cal.startOfDay(for: jetzt)
        let tagStart: Date
        switch tag {
        case .heute, .ohne: tagStart = heute
        case .morgen: tagStart = cal.date(byAdding: .day, value: 1, to: heute) ?? heute
        case .datum: tagStart = cal.startOfDay(for: datum)
        }
        func uhrzeit(_ d: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: tagStart) ?? tagStart
        }
        return (uhrzeit(von), uhrzeit(bis))
    }

    static func pruefen(titel: String, ort: String, start: Date, ende: Date, jetzt: Date) -> String? {
        let titel = titel.trimmingCharacters(in: .whitespacesAndNewlines)
        if titel.isEmpty { return "Der Titel fehlt." }
        if titel.count > maxLaenge { return "Der Titel ist zu lang." }
        if ort.trimmingCharacters(in: .whitespacesAndNewlines).count > maxLaenge { return "Der Ort ist zu lang." }
        if ende <= start { return "Das Ende muss nach dem Beginn liegen." }
        if abs(start.timeIntervalSince(jetzt)) > 400 * 86_400 { return "Das Datum liegt zu weit weg." }
        return nil
    }

    static func params(titel: String, start: Date, ende: Date, kalender: String, ort: String) -> [String: Any] {
        var p: [String: Any] = [
            "titel": titel.trimmingCharacters(in: .whitespacesAndNewlines),
            "start": Int64((start.timeIntervalSince1970 * 1000).rounded()),
            "ende": Int64((ende.timeIntervalSince1970 * 1000).rounded()),
            "kalender": kalender,
        ]
        let ort = ort.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ort.isEmpty { p["ort"] = ort }
        return p
    }
}
