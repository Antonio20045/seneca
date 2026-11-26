import Foundation

enum VerstaendlicherText {
    static let titelMax = 70

    private static let abkuerzungen: Set<String> = [
        "z", "b", "d", "h", "u", "a", "o", "v", "ca", "bzw", "usw", "vgl", "nr", "std", "min", "sek", "ggf", "evtl", "inkl", "etc", "dr", "abb", "tel", "str", "bspw", "ev", "zb",
    ]

    private static func regex(_ muster: String, _ optionen: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: muster, options: optionen)
    }

    private static let bereinigung: [(NSRegularExpression, String)] = [
        (regex(#"`[^`]*`"#), " "),
        (regex(#"\([^)]*\)"#), " "),
        (regex(#"\[[^\]]*\]"#), " "),
        (regex(#"\{[^}]*\}"#), " "),
        (regex(#"(?:~|/)[\w.\-]*(?:/[\w.\-]+)+/?"#), " "),
        (regex(#"\b[\w\-]+\.(?:md|swift|mjs|cjs|js|ts|tsx|json|yaml|yml|sh|py|sqlite|log|txt|html|css|plist|pdf|png|csv|xcodeproj)\b"#, .caseInsensitive), " "),
        (regex(#"\b[A-Z]{1,3}-[A-Z0-9]{3,8}\b"#), " "),
        (regex(#"\b(?:PR|Pull[- ]Request|Issue|Formular|Ticket|Nr\.?)\s*#?\d+\b"#, .caseInsensitive), " "),
        (regex(#"#\d+\b"#), " "),
        (regex(#"\b[0-9a-f]{7,40}\b"#), " "),
        (regex(#"[`{}\[\]<>|\\]"#), " "),
        (regex(#"\s+"#), " "),
    ]

    private static let warumStart = regex(#"(?:^|\s)Warum\s*:"#, .caseInsensitive)
    private static let artikelEnde = regex(#"(?:\s+(?:in|im|von|vom|der|die|das|den|dem|des|zu|zum|zur|auf|an|bei|mit|aus|für|und|oder|nach|vor|um|als|ein|eine|einen|einem))+[\s,;:\-–—]*$"#, .caseInsensitive)
    private static let schreibeWie = regex(#"^[\s,;:.\-–—•*]+"#)
    private static let auftragsPraefix = regex(#"^(?:Auftrag|Aufgabe)\s*:\s*"#, .caseInsensitive)

    private static let leerraum = regex(#"\s+"#)
    private static let cacheSperre = NSLock()
    nonisolated(unsafe) private static var titelCache: [String: String] = [:]

    private static func ersetze(_ s: String, _ re: NSRegularExpression, _ durch: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: durch)
    }

    static func kurztitel(_ worum: String?) -> String {
        let roh = worum ?? ""
        cacheSperre.lock(); let treffer = titelCache[roh]; cacheSperre.unlock()
        if let treffer { return treffer }
        let t = berechneTitel(roh)
        cacheSperre.lock()
        if titelCache.count > 2000 { titelCache.removeAll() }
        titelCache[roh] = t
        cacheSperre.unlock()
        return t
    }

    private static func berechneTitel(_ roh: String) -> String {
        var s = Menschlich.klartext(roh)
        if let z = s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first { s = String(z) }
        if let m = warumStart.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
            s = (s as NSString).substring(to: m.range.location)
        }
        for (re, durch) in bereinigung { s = ersetze(s, re, durch) }
        s = ersetze(s.trimmingCharacters(in: .whitespacesAndNewlines), schreibeWie, "")
        s = ersetze(s, auftragsPraefix, "")
        var erster = saetze(s).first ?? s
        erster = erster.trimmingCharacters(in: CharacterSet(charactersIn: " .:;,–—-"))
        if erster.count > titelMax { erster = kuerzeAnGrenze(erster, titelMax) }
        erster = ersetze(erster, artikelEnde, "").trimmingCharacters(in: CharacterSet(charactersIn: " .:;,–—-"))
        guard erster.count >= 3, let ersterBuchstabe = erster.first else { return "Auftrag ohne Beschreibung" }
        return String(ersterBuchstabe).uppercased() + erster.dropFirst()
    }

    static func ohneCode(_ text: String) -> String {
        var s = text
        for (re, durch) in bereinigung { s = ersetze(s, re, durch) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func kuerzeAnGrenze(_ s: String, _ max: Int) -> String {
        if s.count <= max { return s }
        let kopf = String(s.prefix(max))
        let grenzen = [", ", "; ", ": ", " – ", " — ", " - "]
        var beste: String.Index?
        for g in grenzen {
            if let r = kopf.range(of: g, options: .backwards), kopf.distance(from: kopf.startIndex, to: r.lowerBound) >= 20 {
                if beste == nil || r.lowerBound > beste! { beste = r.lowerBound }
            }
        }
        if let b = beste { return String(kopf[..<b]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:–—-")) }
        let naechstes = s[s.index(s.startIndex, offsetBy: max)]
        var wort = kopf
        if !naechstes.isWhitespace, let sp = kopf.lastIndex(of: " ") { wort = String(kopf[..<sp]) }
        wort = wort.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:–—-"))
        return wort + " …"
    }

    static func saetze(_ text: String) -> [String] {
        let s = ersetze(text, leerraum, " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        let zeichen = Array(s)
        var teile: [String] = [], start = 0
        var i = 0
        while i < zeichen.count {
            let c = zeichen[i]
            if c == "." || c == "!" || c == "?", i + 1 < zeichen.count, zeichen[i + 1] == " ", i + 2 < zeichen.count {
                var j = i - 1
                while j >= 0, zeichen[j].isLetter || zeichen[j].isNumber { j -= 1 }
                let wort = String(zeichen[(j + 1)..<i]).lowercased()
                let ziffern = !wort.isEmpty && wort.allSatisfy(\.isNumber)
                let naechster = zeichen[i + 2]
                let neuerSatz = naechster.isUppercase || naechster.isNumber || naechster == "„" || naechster == "\""
                let abkuerzung = c == "." && (abkuerzungen.contains(wort) || wort.count == 1 || ziffern)
                if neuerSatz && !abkuerzung {
                    teile.append(String(zeichen[start...i]))
                    start = i + 2
                    i += 2
                    continue
                }
            }
            i += 1
        }
        if start < zeichen.count { teile.append(String(zeichen[start...])) }
        return teile.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func ersterSatz(_ text: String?, max: Int = 170) -> String {
        var t = Menschlich.ohnePfade(Menschlich.klartext(text))
        if ["<null>", "null", "(null)", "undefined"].contains(t.lowercased()) { t = "" }
        guard let s = saetze(t).first else { return "" }
        return s.count <= max ? s : kuerzeAnGrenze(s, max)
    }
}
