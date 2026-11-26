import Foundation

enum DateiErkennung {
    static func alleinstehend(_ absatz: String) -> String? {
        let t = absatz.jsTrim
        guard !t.isEmpty, !t.contains("\n") else { return nil }
        if let m = t.treffer(#"^\[([^\]]*)\]\(([^)]+)\)$"#), let ziel = m[2] { return pfad(aus: ziel) }
        return pfad(aus: t)
    }

    static func pfad(aus s: String) -> String? {
        var t = s.jsTrim
        var ausRueckwaertsstrichen = false
        if t.hasPrefix("`"), t.hasSuffix("`"), t.count > 2 { t = String(t.dropFirst().dropLast()); ausRueckwaertsstrichen = true }
        guard !t.isEmpty, ausRueckwaertsstrichen || !t.contains(" ") else { return nil }
        if t.lowercased().hasPrefix("file://") {
            guard let url = URL(string: t), !url.path.isEmpty, url.path != "/" else { return nil }
            return url.path
        }
        guard t.hasPrefix("~/") || t.hasPrefix("/") else { return nil }
        guard t != "/", t != "~/" else { return nil }
        return (t as NSString).expandingTildeInPath
    }
}

struct Entwurf: Equatable, Sendable {
    var betreff: String?
    var empfaenger: String?
    var text: String
}

enum EntwurfTeil: Equatable, Sendable {
    case text(String)
    case entwurf(Entwurf)
}

enum EntwurfErkennung {
    private static let anreden = [
        "liebe ", "lieber ", "hallo ", "hi ", "sehr geehrte", "sehr geehrter", "guten tag", "moin", "dear ", "hey ",
    ]
    private static let grussformeln = [
        "viele grüße", "viele gruesse", "beste grüße", "beste gruesse", "mit freundlichen grüßen",
        "mit freundlichen gruessen", "liebe grüße", "liebe gruesse", "herzliche grüße", "herzliche gruesse",
        "beste wünsche", "beste wuensche", "best regards", "kind regards", "\nlg", "\nvg",
    ]

    static func erkenne(_ text: String) -> Entwurf? {
        let zeilen = text.components(separatedBy: "\n")
        var betreff: String?, empfaenger: String?
        var inhalt: [String] = []
        var markiert = false
        for roh in zeilen {
            let z = roh.jsTrim
            if let m = z.treffer(#"^\*{0,2}(Betreff|Subject)\*{0,2}\s*:\s*(.+)$"#, "i"), let w = m[2] { betreff = w.jsTrim; continue }
            if let m = z.treffer(#"^\*{0,2}(An|To)\*{0,2}\s*:\s*(.+)$"#, "i"), let w = m[2] { empfaenger = w.jsTrim; continue }
            if z.count < 40, z.lowercased().ersetzeAlle(#"[^a-zäöü]"#, "", "i") == "entwurf" { markiert = true; continue }
            inhalt.append(roh)
        }
        let koerper = inhalt.joined(separator: "\n").jsTrim
        guard !koerper.isEmpty else { return nil }
        let klein = "\n" + koerper.lowercased()
        let hatAnrede = anreden.contains { klein.contains("\n" + $0) }
        let hatGruss = grussformeln.contains { klein.contains($0) }
        guard betreff != nil || empfaenger != nil || markiert || (hatAnrede && hatGruss) else { return nil }
        return Entwurf(betreff: betreff, empfaenger: empfaenger, text: koerper)
    }

    private static func istStart(_ absatz: String) -> Bool {
        let z = absatz.jsTrim
        if z.treffer(#"^\*{0,2}(Betreff|Subject|An|To)\*{0,2}\s*:"#, "i") != nil { return true }
        if z.count < 40, z.lowercased().ersetzeAlle(#"[^a-zäöü]"#, "", "i") == "entwurf" { return true }
        let klein = z.lowercased()
        return anreden.contains { klein.hasPrefix($0) }
    }

    private static func istGruss(_ absatz: String) -> Bool {
        let klein = "\n" + absatz.lowercased()
        return grussformeln.contains { klein.contains($0) }
    }

    static func teile(_ text: String) -> [EntwurfTeil] {
        let gruppen = text.components(separatedBy: "\n\n")
        var out: [EntwurfTeil] = []
        var puffer: [String] = []
        func flush() { if !puffer.isEmpty { out.append(.text(puffer.joined(separator: "\n\n"))); puffer = [] } }

        var i = 0
        while i < gruppen.count {
            let g = gruppen[i]
            if istStart(g) {
                var fenster = [g]
                var j = i + 1
                var gefunden = istGruss(g)
                while !gefunden, j < gruppen.count, fenster.count < 12 {
                    fenster.append(gruppen[j])
                    if istGruss(gruppen[j]) { gefunden = true }
                    j += 1
                }
                if gefunden, let e = erkenne(fenster.joined(separator: "\n\n")) {
                    flush(); out.append(.entwurf(e)); i = j; continue
                }
            }
            puffer.append(g)
            i += 1
        }
        flush()
        return out
    }
}

enum KopierText {
    static func text(_ antwort: String) -> String { MDParser.klartext(antwort) }
    static func markdown(_ antwort: String) -> String { antwort }
}
