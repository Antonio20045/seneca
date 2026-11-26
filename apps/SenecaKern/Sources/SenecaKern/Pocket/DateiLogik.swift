import Foundation

enum DateiLogik {

    static func bereinige(_ roh: String) -> String {
        func ohneSpitz(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 2, t.hasPrefix("<"), t.hasSuffix(">") { t = String(t.dropFirst().dropLast()) }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var p = ohneSpitz(roh)
        if p.lowercased().hasPrefix("sandbox:") { p = String(p.dropFirst("sandbox:".count)) }
        if p.lowercased().hasPrefix("file://") { p = String(p.dropFirst("file://".count)) }
        p = ohneSpitz(p)
        p = p.replacingOccurrences(of: #"#L\d+(C\d+)?(-L?\d+(C\d+)?)?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        p = p.replacingOccurrences(of: #":\d+(:\d+)?$"#, with: "", options: .regularExpression)
        return p
    }

    struct Antwort: Equatable {
        var name: String
        var pfad: String
        var art: String
        var inhalt: String?
        var data: String?
        var hinweis: String?
    }

    static func antwort(aus json: [String: Any]) -> Antwort? {
        guard let name = json["name"] as? String, !name.isEmpty else { return nil }
        return Antwort(name: name, pfad: json["pfad"] as? String ?? name, art: json["art"] as? String ?? "andere",
                       inhalt: json["inhalt"] as? String, data: json["data"] as? String, hinweis: json["hinweis"] as? String)
    }

    enum Format: Equatable {
        case markdown
        case text
    }

    enum Ziel: Equatable {
        case lesen(titel: String, text: String, format: Format)
        case quickLook(name: String, daten: Data)
        case hinweis(String)
    }

    static let maxZeichen = 200_000

    static func ziel(fuer a: Antwort) -> Ziel {
        switch a.art {
        case "md":
            guard let t = a.inhalt else { return .hinweis(a.hinweis ?? zuGross) }
            return .lesen(titel: anzeigeTitel(a.name), text: kuerze(t), format: .markdown)
        case "text":
            guard let t = a.inhalt else { return .hinweis(a.hinweis ?? zuGross) }
            return .lesen(titel: anzeigeTitel(a.name), text: kuerze(t), format: .text)
        case "html":
            guard let t = a.inhalt else { return .hinweis(a.hinweis ?? zuGross) }
            return .quickLook(name: dateiname(a.name, ersatzEndung: "html"), daten: Data(t.utf8))
        default:
            if let d = a.data, let bytes = daten(ausDataURL: d), !bytes.isEmpty {
                return .quickLook(name: dateiname(a.name, ersatzEndung: nil), daten: bytes)
            }
            if let t = a.inhalt { return .lesen(titel: anzeigeTitel(a.name), text: kuerze(t), format: .text) }
            return .hinweis(a.hinweis ?? "Für diese Datei gibt es keine Vorschau.")
        }
    }

    static let zuGross = "Die Datei ist zu groß für die Vorschau."

    static func anzeigeTitel(_ name: String) -> String {
        var t = name.replacingOccurrences(of: "*", with: "")
        let ext = (t as NSString).pathExtension.lowercased()
        if ["md", "markdown", "txt"].contains(ext) { t = (t as NSString).deletingPathExtension }
        if !t.contains(" ") { t = t.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ") }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? name : t
    }

    static func kuerze(_ text: String) -> String {
        guard text.count > maxZeichen else { return text }
        return String(text.prefix(maxZeichen)) + "\n\n… (Die Datei ist länger; hier steht nur der Anfang.)"
    }

    static func daten(ausDataURL s: String) -> Data? {
        guard s.hasPrefix("data:"), let komma = s.firstIndex(of: ","), s[..<komma].contains(";base64") else { return nil }
        return Data(base64Encoded: String(s[s.index(after: komma)...]), options: .ignoreUnknownCharacters)
    }

    static func dateiname(_ name: String, ersatzEndung: String?) -> String {
        var n = (name as NSString).lastPathComponent
        n = String(n.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != ":" })
        n = n.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        if n.isEmpty { n = "Datei" }
        if n.count > 120 { n = String(n.suffix(120)) }
        if (n as NSString).pathExtension.isEmpty, let e = ersatzEndung { n += "." + e }
        return n
    }

    static func fehlertext(_ meldung: String) -> String {
        let m = meldung.lowercased()
        if m.contains("gibt es nicht") || m.contains("ungültiger pfad") || m.contains("keine datei") { return "Datei nicht gefunden" }
        if m.contains("außerhalb") || m.contains("geheim") || m.contains("nicht freigegeben") { return "Datei nicht freigegeben" }
        if m.contains("nicht erreichbar") || m.contains("timeout") || m.contains("offline") { return "Dein Mac ist gerade nicht erreichbar" }
        return "Datei nicht lesbar"
    }

    static func demoAntwort(pfad: String) -> [String: Any]? {
        let name = (pfad as NSString).lastPathComponent
        if pfad.lowercased().contains("fehlt") { return nil }
        return ["name": name, "pfad": pfad, "art": "md", "groesse": 120,
                "inhalt": "# Beispieldatei\n\nDas ist eine **Demo-Datei** aus dem Chat.\n\n- erster Punkt\n- zweiter Punkt\n\nWeiter unten steht noch ein Satz."]
    }
}
