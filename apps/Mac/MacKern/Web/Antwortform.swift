import Foundation

enum Antwortform {
    static func kernUndRest(_ src: String, folgtMehr: Bool = false) -> (kern: String?, rest: String) {
        let roh = src.ersetzeAlle(#"\r\n"#, "\n").jsTrim
        let text = ohneKopfUeberschrift(roh)
        if text != roh { return (nil, text) }
        let teile = text.teileNach(#"\n{2,}"#)
        let p = (teile.first ?? "").jsTrim
        let rest = Array(teile.dropFirst())
        if p.isEmpty || p.passt(#"\n"#) || p.passt(#"^(#|[-*•]\s|\d+[.)]\s|\||```|>|---)"#) { return (nil, text) }
        if (p.jsLaenge < 12 || p.passt(#":\s*$"#) || p.passt(#"^(guten (morgen|tag|abend)|hallo|hi|hey|moin|servus)\b[^.!?]{0,30}[.!?]?$"#, "i")) && (!rest.isEmpty || folgtMehr) {
            return (nil, text)
        }
        if istKennzeile(p) { return (nil, text) }
        func ohneFett(_ k: String) -> String { k.ersetze(#"^\*\*([^*]+)\*\*:?$"#, "$1") }
        if p.jsLaenge <= 200 { return (ohneFett(p), rest.joined(separator: "\n\n")) }
        guard let m = p.treffer(#"^(.{20,190}?[a-zäöüß)\d“"]{2}[.!?](?:\*\*)?)\s+(?=[A-ZÄÖÜ„"*`(])"#), let gesamt = m[0], var kern = m[1] else { return (nil, text) }
        var weiter = p.jsSlice(gesamt.jsLaenge)
        if kern.trefferAnzahl(#"\*\*"#) % 2 == 1 {
            kern = kern.ersetzeAlle(#"\*\*"#, "")
            weiter = "**" + weiter
        }
        return (ohneFett(kern), ([weiter] + rest).joined(separator: "\n\n"))
    }

    static func istKennzeile(_ absatz: String) -> Bool {
        absatz.passt(#"^[A-ZÄÖÜ][A-ZÄÖÜ0-9]+[-_][A-ZÄÖÜ0-9_-]*[A-ZÄÖÜ0-9](?![a-zäöüß])"#)
    }

    static func ohneKopfUeberschrift(_ text: String) -> String {
        guard let m = text.treffer(#"^#{1,6}[ \t]+([^\n]*?)[ \t#]*(?:\n+|$)"#), let ganz = m[0], let titel = m[1] else { return text }
        let rest = text.jsSlice(ganz.jsLaenge)
        let t = titel.ersetzeAlle(#"\*\*"#, "").jsTrim
        if t.isEmpty { return rest }
        return rest.isEmpty ? "**\(t)**" : "**\(t)**\n\n" + rest
    }

    static func antwortartig(_ seg: String, ruhigMs: Double) -> Bool {
        seg.jsLaenge > 280 || (seg.contains("\n\n") && seg.jsLaenge > 140) || (ruhigMs > 2500 && seg.jsLaenge > 160)
    }

    static func letzterSatz(_ seg: String) -> String {
        let zeile = seg.components(separatedBy: "\n").last { !$0.jsTrim.isEmpty } ?? ""
        let t = zeile.ersetzeAlle(#"[*_`#>]"#, "").jsTrim
        return t.jsLaenge > 96 ? t.jsSlice(0, 95) + "…" : t
    }
}
