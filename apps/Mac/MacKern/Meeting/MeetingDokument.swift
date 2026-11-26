import Foundation

enum MeetingStand: Equatable {
    case laeuft
    case vollstaendig
    case ohneZusammenfassung(String)
}

struct MeetingErgebnis {
    var titel: String
    var beginn: Date
    var dauer: Double
    var segmente: [MeetingSegment]
    var zusammenfassung: String
    var aufgaben: [String]
    var rollen: [Int: String] = [:]
    var hinweise: [String] = []
    var entscheidungen: [String] = []
    var alleAufgaben: [MeetingAufgabe] = []
    var offeneFragen: [String] = []
    var stand: MeetingStand = .vollstaendig
    var aufnahme: String? = nil
}

enum MeetingDokument {
    static func ordnerStandard() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Bereiche/privat/meetings", isDirectory: true)
    }

    static func slug(_ titel: String) -> String {
        var t = titel.lowercased()
        for (a, b) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] { t = t.replacingOccurrences(of: a, with: b) }
        t = t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
        var aus = ""
        var strich = false
        for z in t.unicodeScalars {
            if (z.value >= 97 && z.value <= 122) || (z.value >= 48 && z.value <= 57) { aus.unicodeScalars.append(z); strich = false }
            else if !strich, !aus.isEmpty { aus += "-"; strich = true }
        }
        while aus.hasSuffix("-") { aus.removeLast() }
        if aus.count > 60 { aus = String(aus.prefix(60)); while aus.hasSuffix("-") { aus.removeLast() } }
        return aus.isEmpty ? "meeting" : aus
    }

    static func tag(_ d: Date, zeitzone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zeitzone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func dateiname(titel: String, beginn: Date, zeitzone: TimeZone = .current) -> String {
        "\(tag(beginn, zeitzone: zeitzone))-\(slug(titel)).md"
    }

    static func dauerText(_ s: Double) -> String {
        let min = Int((s / 60).rounded())
        if s < 60 { return "\(Int(s.rounded())) Sek." }
        if min < 60 { return "\(min) Min." }
        return "\(min / 60) Std. \(min % 60) Min."
    }

    static func markdown(_ e: MeetingErgebnis, zeitzone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE"); f.timeZone = zeitzone; f.dateFormat = "d. MMMM yyyy, HH:mm 'Uhr'"
        let nummern = MeetingTranskript.sprecherAnzahl(e.segmente)
        let sprecher = (nummern.isEmpty ? [1] : nummern).map { n -> String in
            let r = e.rollen[n].map { " (\($0))" } ?? ""
            return "Sprecher \(n)\(r)"
        }.joined(separator: ", ")
        let leer: String
        var z: [String] = []
        z.append("# \(e.titel)")
        z.append("")
        z.append("- **Datum:** \(f.string(from: e.beginn))")
        z.append("- **Dauer:** \(dauerText(e.dauer))")
        z.append("- **Sprecher:** \(sprecher)")
        if let a = e.aufnahme { z.append("- **Aufnahme:** \(a)") }
        switch e.stand {
        case .vollstaendig: leer = "_keine_"
        case .laeuft:
            leer = "_wird noch erstellt_"
            z.append("- **Stand:** Mitschrift fertig, die Zusammenfassung wird noch erstellt.")
        case .ohneZusammenfassung(let grund):
            leer = "_fehlt (siehe Stand oben)_"
            z.append("- **Stand:** Zusammenfassung fehlt (\(grund)). Nachholen in Seneca: Meeting-Fenster, „Erneut zusammenfassen“ oder unter „Frühere Aufnahmen“ „Erneut auswerten“.")
        }
        for h in e.hinweise { z.append("- **Hinweis:** \(h)") }
        z.append("")
        z.append("## Worum es ging")
        z.append("")
        z.append(e.zusammenfassung.isEmpty ? leer : e.zusammenfassung)
        z.append("")
        z.append("## Entscheidungen")
        z.append("")
        if e.entscheidungen.isEmpty { z.append(leer) } else { for t in e.entscheidungen { z.append("- \(t)") } }
        z.append("")
        z.append("## Aufgaben")
        z.append("")
        let alle = e.alleAufgaben.isEmpty ? e.aufgaben.map { MeetingAufgabe(wer: "Antonio", text: $0, termin: nil) } : e.alleAufgaben
        if alle.isEmpty { z.append(leer) } else { for a in alle { z.append(a.fuerAntonio ? "- [ ] \(a.zeile)" : "- \(a.zeile)") } }
        z.append("")
        z.append("## Offene Fragen")
        z.append("")
        if e.offeneFragen.isEmpty { z.append(leer) } else { for t in e.offeneFragen { z.append("- \(t)") } }
        z.append("")
        z.append("## Mitschrift")
        z.append("")
        if e.segmente.isEmpty { z.append("_Nichts erkannt._") }
        for s in e.segmente { z.append("**\(s.sprecherName)** [\(MeetingTranskript.zeit(s.start))] \(s.text)"); z.append("") }
        return z.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func frei(_ name: String, in ordner: URL) -> URL {
        let basis = String(name.dropLast(3))
        var ziel = ordner.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = ordner.appendingPathComponent("\(basis)-\(n).md"); n += 1
        }
        return ziel
    }

    @discardableResult
    static func schreibe(_ e: MeetingErgebnis, in ordner: URL, zeitzone: TimeZone = .current) throws -> URL {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let ziel = frei(dateiname(titel: e.titel, beginn: e.beginn, zeitzone: zeitzone), in: ordner)
        try markdown(e, zeitzone: zeitzone).write(to: ziel, atomically: true, encoding: .utf8)
        return ziel
    }

    @discardableResult
    static func nachtrage(_ e: MeetingErgebnis, datei: URL, zeitzone: TimeZone = .current) throws -> URL {
        let ordner = datei.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try markdown(e, zeitzone: zeitzone).write(to: datei, atomically: true, encoding: .utf8)
        let name = dateiname(titel: e.titel, beginn: e.beginn, zeitzone: zeitzone)
        let muster = "^" + NSRegularExpression.escapedPattern(for: String(name.dropLast(3))) + "(-\\d+)?\\.md$"
        if datei.lastPathComponent.range(of: muster, options: .regularExpression) != nil { return datei }
        let ziel = frei(name, in: ordner)
        try FileManager.default.moveItem(at: datei, to: ziel)
        return ziel
    }
}
