import Foundation

enum Werkzeugtext {
    struct Ergebnis: Equatable, Sendable {
        var rest: String
        var schritte: [Schritt]
        var bereinigt: Bool
    }

    private static let paramNamen: Set<String> = ["command", "cmd", "file_path", "path", "pattern", "description", "query", "url", "input", "content", "old_string", "new_string"]

    private static func re(_ muster: String) -> NSRegularExpression { try! NSRegularExpression(pattern: muster, options: []) }

    private static let markdownAufruf = re(#"\*\*Tool(?: Use)?:[ \t]*([^*\n]*?)\*\*[ \t]*(?:\n+```[A-Za-z]*[ \t]*\n([\s\S]*?)(?:\n```[ \t]*(?:\n|$)|$))?"#)
    private static let markdownErgebnis = re(#"\*\*Tool Result:?\*\*[ \t]*(?:\n+```[A-Za-z]*[ \t]*\n[\s\S]*?(?:\n```[ \t]*(?:\n|$)|$))?"#)
    private static let ergebnisse = re(#"<(?:antml:)?function_results>[\s\S]*?(?:</(?:antml:)?function_results>|</output>(?:\s*</(?:result|function_results|invoke)>)*|$)"#)
    private static let toolUse = re(#"<invoke_tool_use>[\s\S]*?(?:</invoke_tool_use>|$)"#)
    private static let aufrufe = re(#"<(?:antml:)?function_calls>[\s\S]*?(?:</(?:antml:)?function_calls>|$)"#)
    private static let einzel = re(#"<(?:antml:)?invoke\b[\s\S]*?(?:</(?:antml:)?invoke>|$)"#)
    private static let param = re(#"<(?:antml:)?parameter\s+name="([^"]*)"[^>]*>([\s\S]*?)(?:</(?:antml:)?parameter>|$)"#)
    private static let verschachtelt = re(#"<(?:antml:)?invoke\s+name="([^"]*)"[^>]*>([\s\S]*?)(?:</(?:antml:)?parameter>|</(?:antml:)?invoke>|$)"#)
    private static let nameAttr = re(#"<(?:antml:)?invoke\s+name="([^"]*)""#)
    private static let systemReminder = re(#"<system-reminder>[\s\S]*?(?:</system-reminder>|$)"#)
    private static let streuTags = re(#"</?(?:antml:)?(?:function_calls|function_results|invoke|invoke_name|invoke_tool_use|parameter|result|output)\b[^>]*>|</?system-reminder>"#)
    private static let anfang: NSRegularExpression = {
        let teile = ["invoke_tool_use", "invoke", "function_calls", "function_results", "parameter", "system-reminder"].flatMap { w in (1...w.count).map { String(w.prefix($0)) } }
        return re(#"(?:<(?:/?(?:antml:)?(?:"# + Set(teile).sorted().joined(separator: "|") + #")?)?|\*\*Tool(?: Use| Result)?:?[^*\n]*|\*\*(?:T|To|Too|Tool|Tool |Tool U|Tool Us|Tool R|Tool Re|Tool Res|Tool Resu|Tool Resul)\*?)$"#)
    }()

    private static func gruppe(_ m: NSTextCheckingResult, _ i: Int, _ s: NSString) -> String? {
        m.range(at: i).location == NSNotFound ? nil : s.substring(with: m.range(at: i))
    }

    private static func entferne(_ r: NSRegularExpression, _ text: String, _ fuer: ((NSTextCheckingResult, NSString) -> Void)? = nil) -> String {
        let ns = text as NSString
        let treffer = r.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if treffer.isEmpty { return text }
        var aus = ""
        var pos = 0
        for m in treffer {
            if m.range.location < pos { continue }
            aus += ns.substring(with: NSRange(location: pos, length: m.range.location - pos))
            fuer?(m, ns)
            pos = m.range.location + m.range.length
        }
        aus += ns.substring(from: pos)
        return aus
    }

    private static func json(_ s: String?) -> Any? {
        guard let s, !s.jsTrim.isEmpty else { return nil }
        return s.jsTrim
    }

    private static func schritte(ausInvoke s: String, ts: Double?) -> [Schritt] {
        let ns = s as NSString
        var namen = nameAttr.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { gruppe($0, 1, ns) }
        guard let erster = namen.first else { return [] }
        namen = [erster]
        var args: [String: Any] = [:]
        for m in param.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if let k = gruppe(m, 1, ns), let v = gruppe(m, 2, ns) { args[k] = v.jsTrim }
        }
        for m in verschachtelt.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if let k = gruppe(m, 1, ns), paramNamen.contains(k.lowercased()), let v = gruppe(m, 2, ns) { args[k] = v.jsTrim }
        }
        if paramNamen.contains(erster.lowercased()) { return [Arbeitsspur.schritt("Bash", args, ts: ts)] }
        return [Arbeitsspur.schritt(erster, args, ts: ts)]
    }

    static func bereinige(_ text: String, ts: Double? = nil) -> Ergebnis {
        var davor: (UInt8, UInt8) = (0, 0)
        let hinweis = text.utf8.contains { b in
            defer { davor = (davor.1, b) }
            return b == 60 || (b == 84 && davor.0 == 42 && davor.1 == 42)
        }
        if !hinweis { return Ergebnis(rest: text, schritte: [], bereinigt: false) }
        var t = text
        var spur: [Schritt] = []

        t = entferne(systemReminder, t)
        t = entferne(ergebnisse, t)
        t = entferne(markdownErgebnis, t)
        t = entferne(markdownAufruf, t) { m, ns in
            let name = gruppe(m, 1, ns)?.jsTrim
            spur.append(Arbeitsspur.schritt((name ?? "").isEmpty ? nil : name, json(gruppe(m, 2, ns)), ts: ts))
        }
        t = entferne(toolUse, t) { m, ns in
            let s = ns.substring(with: m.range)
            let sn = s as NSString
            var name: String?
            var eingabe: String?
            for p in param.matches(in: s, range: NSRange(location: 0, length: sn.length)) {
                switch gruppe(p, 1, sn) {
                case "tool_name": name = gruppe(p, 2, sn)?.jsTrim
                case "input": eingabe = gruppe(p, 2, sn)
                default: break
                }
            }
            spur.append(Arbeitsspur.schritt(name, json(eingabe), ts: ts))
        }
        t = entferne(aufrufe, t) { m, ns in
            let s = ns.substring(with: m.range)
            let sn = s as NSString
            for e in einzel.matches(in: s, range: NSRange(location: 0, length: sn.length)) { spur += schritte(ausInvoke: sn.substring(with: e.range), ts: ts) }
        }
        t = entferne(einzel, t) { m, ns in spur += schritte(ausInvoke: ns.substring(with: m.range), ts: ts) }
        t = entferne(streuTags, t)
        t = entferne(anfang, t)

        let bereinigt = t != text
        if !bereinigt { return Ergebnis(rest: text, schritte: [], bereinigt: false) }
        let rest = t.ersetzeAlle(#"[ \t]+\n"#, "\n").ersetzeAlle(#"\n{3,}"#, "\n\n").jsTrim
        return Ergebnis(rest: rest, schritte: spur, bereinigt: true)
    }

    static let systemhinweisTitel = "Systemhinweis"

    private static let systemAnfaenge = [
        #"^\[Claude CLI history record omitted"#,
        #"^This session is being continued from a previous conversation"#,
        #"^Summary:\s*\n\s*1\. Primary Request"#,
        #"^OpenClaw resumed this CLI session"#,
        #"^\[Subagent Context\]"#,
        #"^\[Inter-session message\]"#,
        #"^<system-reminder>"#,
    ].map { re($0) }

    static func istSystemtext(_ text: String) -> Bool {
        let t = text.jsTrim
        let r = NSRange(location: 0, length: (t as NSString).length)
        return systemAnfaenge.contains { $0.firstMatch(in: t, range: r) != nil }
    }

    static func istReinerSystemtext(_ text: String) -> Bool {
        istSystemtext(text) && !text.jsTrim.hasPrefix("[Subagent Context]") && !text.jsTrim.hasPrefix("[Inter-session message]")
    }

    static func sichtbar(_ text: String) -> String { bereinige(text).rest }
}
