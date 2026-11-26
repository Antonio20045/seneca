import Foundation

enum SchrittArt: String, CaseIterable, Sendable {
    case web, lesen, schreiben, befehl, agent, suche, plan, gedanke, warten, nachricht, sonst
}

struct Schritt: Equatable, Sendable {
    var art: SchrittArt
    var text: String
    var detail: String?
    var titel: String?
    var tech: String?
    var ts: Double?
}

struct SpurTeil: Equatable, Sendable {
    var n = 0
    var art: SchrittArt
    var text: String
}

enum Arbeitsspur {
    private static func basename(_ p: String) -> String {
        let t = p.ersetze(#"[/\\]+$"#, "")
        let letzter = t.teileNach(#"[/\\]"#).last ?? ""
        return letzter.isEmpty ? p : letzter
    }

    private static func host(_ u: String) -> String {
        if let h = URL(string: u)?.host, !h.isEmpty { return h.lowercased().ersetze(#"^www\."#, "") }
        return u.jsSlice(0, 40)
    }

    static func kurz(_ s: Any?, _ n: Int = 70) -> String {
        let t = jsText(s).ersetzeAlle(#"\s+"#, " ").jsTrim
        return t.jsLaenge > n ? t.jsSlice(0, n - 1) + "…" : t
    }

    private static func agentAus(_ k: Any?) -> String {
        guard let s = k as? String, !s.isEmpty else { return jsText(k) }
        if s.passt(#"^agent:"#) { let t = s.components(separatedBy: ":"); return t.count > 1 ? t[1] : "" }
        return s
    }

    private static func argumente(_ raw: Any?) -> [String: Any] {
        if let s = raw as? String {
            if let d = s.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) {
                return (j as? [String: Any]) ?? [:]
            }
            return ["text": s]
        }
        return (raw as? [String: Any]) ?? [:]
    }

    private static func befehl(_ a: [String: Any]) -> (text: String, detail: String?) {
        let cmd = jsText(jsErster(a["command"], a["cmd"], a["script"]))
        let d = jsWahr(a["description"]) ? jsText(a["description"]) : ""
        if cmd.passt(#"\bgit\b"#) && cmd.passt(#"\b(log|status|diff|show|branch)\b"#) { return ("Git-Verlauf angesehen", nil) }
        if cmd.passt(#"\bgit\b.*\b(commit|merge|push)\b"#) { return ("Änderungen eingecheckt", nil) }
        if cmd.passt(#"\bcurl\b|\bwget\b"#) {
            let u = cmd.treffer(#"https?://[^\s'"]+"#)?[0]
            return ("Webseite abgerufen", u.map(host))
        }
        if let was = SystemMuster.verwaltungsBefehl(cmd) {
            let de = ["status": "Systemzustand", "doctor": "Systemdiagnose", "automations": "Automatisierungen", "cron": "Automatisierungen",
                      "mcp": "Werkzeugserver", "channels": "Kanäle", "models": "Modelle", "sessions": "Sitzungen", "agents": "Agenten"]
            return ("\(de[was] ?? "System") geprüft", nil)
        }
        if cmd.passt(#"^\s*(cat|head|tail|sed -n|less)\b"#) {
            let f = cmd.treffer(#"(?:~|/)[^\s'";|]+\.\w+"#)?[0]
            return ("Datei gelesen", f.map(basename))
        }
        if cmd.passt(#"^\s*(ls|find|grep|rg)\b"#) { return ("Dateien durchsucht", nil) }
        if cmd.passt(#"\bps\b|\bkill\b|\blsof\b"#) { return ("Laufende Prozesse geprüft", nil) }
        if cmd.passt(#"\bnpm|node|npx|python3?\b"#) { return ("Programm ausgeführt", d.isEmpty ? nil : kurz(d, 50)) }
        return ("Befehl ausgeführt", d.isEmpty ? nil : kurz(d, 50))
    }

    static func schritt(_ name: String?, _ raw: Any?, ts: Double? = nil) -> Schritt {
        let a = argumente(raw)
        let n = (name ?? "").isEmpty ? "Werkzeug" : name!
        let k = n.ersetze(#"^mcp__[^_]+(?:_[^_]+)*?__"#, "").ersetze(#"^functions\."#, "").lowercased()
        let pfad = jsErster(a["file_path"], a["path"], a["filePath"], a["file"], a["notebook_path"])
        func mit(_ art: SchrittArt, _ text: String, _ detail: String? = nil, _ titel: String? = nil) -> Schritt {
            Schritt(art: art, text: text, detail: detail, titel: titel, tech: n, ts: ts)
        }
        let pfadText = pfad.map { jsText($0) }
        let datei = pfadText.map(basename)

        if k.passt(#"show_widget"#) || (k.passt(#"^exec$"#) && jsText(jsErster(a["input"], a["code"])).passt(#"show_widget\s*\("#)) {
            return mit(.plan, "Ansicht gebaut", jsWahr(a["title"]) ? kurz(jsText(a["title"]), 50) : nil)
        }
        if k.passt(#"web_?search|websearch|search_web|exa.*search|brave"#) {
            return mit(.web, "Im Web gesucht", jsWahr(a["query"]) ? "„\(kurz(a["query"], 60))“" : nil)
        }
        if k.passt(#"web_?fetch|webfetch|fetch_url|browser|navigate|get_page"#) {
            let u = jsErster(a["url"], a["href"])
            return mit(.web, "Webseite gelesen", jsWahr(u) ? host(jsText(u)) : nil, jsWahr(u) ? jsText(u) : nil)
        }
        if k.passt(#"^(read|read_file|view|cat|open)$"#) || k.passt(#"read_?(multiple_)?files?"#) {
            return mit(.lesen, "Datei gelesen", jsWahr(pfad) ? datei : nil, jsWahr(pfad) ? pfadText : nil)
        }
        if k.passt(#"^(write|write_file|create_file)$"#) {
            return mit(.schreiben, "Datei geschrieben", jsWahr(pfad) ? datei : nil, jsWahr(pfad) ? pfadText : nil)
        }
        if k.passt(#"^(edit|multiedit|multi_edit|str_replace|apply_patch|edit_block|notebookedit)$"#) {
            return mit(.schreiben, "Datei geändert", jsWahr(pfad) ? datei : nil, jsWahr(pfad) ? pfadText : nil)
        }
        if k.passt(#"^(grep|glob|ls|find|search|list_directory|search_files|start_search)$"#) {
            return mit(.suche, "Dateien durchsucht", jsWahr(a["pattern"]) ? "„\(kurz(a["pattern"], 40))“" : nil)
        }
        if k.passt(#"^(exec|bash|shell|run|terminal|start_process|run_command)$"#) {
            let b = befehl(a)
            return mit(.befehl, b.text, b.detail, jsWahr(a["command"]) ? kurz(a["command"], 400) : nil)
        }
        if k.passt(#"^process$|read_process_output|interact_with_process"#) {
            return mit(.warten, (a["action"] as? String) == "kill" ? "Befehl beendet" : "Auf einen Befehl gewartet")
        }
        if k.passt(#"sessions_spawn|spawn_agent|^task$|^agent$|subagent_spawn"#) {
            let wer = jsText(jsErster(a["agentId"], a["agent"], a["subagent_type"], agentAus(a["sessionKey"])))
            let hatBeschreibung = jsWahr(a["label"]) || jsWahr(a["description"])
            return mit(.agent, wer.isEmpty ? "Helfer beauftragt" : "\(wer) beauftragt", hatBeschreibung ? kurz(jsErster(a["label"], a["description"]), 50) : nil)
        }
        if k.passt(#"sessions_send|send_message_to_session"#) {
            let wer = agentAus(jsErster(a["sessionKey"], a["key"]))
            return mit(.agent, wer.isEmpty ? "Einem Agenten geschrieben" : "\(wer) geschrieben")
        }
        if k.passt(#"sessions_yield|wait_for|await"#) { return mit(.warten, "Auf Agenten gewartet") }
        if k.passt(#"sessions_(list|history)|session_status|subagents|agents_list"#) { return mit(.agent, "Stand der Agenten angesehen") }
        if k.passt(#"^message$|send_message|notify"#) { return mit(.nachricht, "Nachricht verschickt") }
        if k.passt(#"progress_card|todowrite|update_plan|plan"#) { return mit(.plan, "Fortschritt festgehalten") }
        if k.passt(#"memory|remember|recall"#) { return mit(.lesen, k.passt(#"write|save|store|add"#) ? "Im Gedächtnis notiert" : "Im Gedächtnis nachgesehen") }
        if k.passt(#"workboard|card"#) { return mit(.plan, "Aufgabenboard aktualisiert") }
        if k.passt(#"cron|automation|schedule"#) { return mit(.plan, "Automatisierung angesehen") }
        if k.passt(#"calendar|kalender"#) { return mit(.lesen, "Kalender angesehen") }
        if k.passt(#"place_call|call"#) { return mit(.nachricht, "Anruf vorbereitet") }
        if k.passt(#"gmail|mail"#) { return mit(.lesen, "E-Mails angesehen") }
        if k.passt(#"image|generate"#) { return mit(.schreiben, "Bild erstellt") }
        let lesbar = k.ersetzeAlle(#"[_-]+"#, " ").jsTrim
        return mit(.sonst, "Werkzeug benutzt", lesbar.isEmpty ? nil : kurz(lesbar, 40))
    }

    static func gedanke(_ text: String, ts: Double? = nil) -> Schritt {
        Schritt(art: .gedanke, text: kurz(text.replacingOccurrences(of: "**", with: ""), 220), detail: nil,
                titel: text.jsLaenge > 220 ? text : nil, tech: nil, ts: ts)
    }

    static func zusammenfassung(_ steps: [Schritt], dauerMs: Double? = nil) -> (teile: [SpurTeil], dauer: String) {
        func z(_ f: (Schritt) -> Bool) -> Int { steps.filter(f).count }
        let quellen = z { $0.art == .web || $0.art == .lesen || $0.art == .suche }
        let befehle = z { $0.art == .befehl || $0.art == .warten }
        let agenten = z { $0.art == .agent && $0.text.passt("beauftragt") }
        let geschrieben = z { $0.art == .agent && $0.text.passt("geschrieben") } + z { $0.art == .nachricht }
        let geaendert = z { $0.art == .schreiben }
        var teile: [(art: SchrittArt, n: Int, text: String)] = []
        if agenten > 0 { teile.append((.agent, agenten * 3, agenten == 1 ? "1 Agent beauftragt" : "\(agenten) Agenten beauftragt")) }
        if quellen > 0 { teile.append((.lesen, quellen, quellen == 1 ? "1 Quelle gelesen" : "\(quellen) Quellen gelesen")) }
        if geaendert > 0 { teile.append((.schreiben, geaendert * 2, geaendert == 1 ? "1 Datei geändert" : "\(geaendert) Dateien geändert")) }
        if befehle > 0 { teile.append((.befehl, befehle, befehle == 1 ? "1 Prüfung" : "\(befehle) Prüfungen")) }
        if geschrieben > 0 { teile.append((.nachricht, geschrieben, geschrieben == 1 ? "1 Nachricht" : "\(geschrieben) Nachrichten")) }
        let sonst = steps.filter { $0.art != .gedanke }.count - quellen - befehle - agenten - geschrieben - geaendert
        if teile.isEmpty && sonst > 0 { teile.append((.plan, sonst, sonst == 1 ? "1 Schritt" : "\(sonst) Schritte")) }
        if teile.isEmpty && !steps.isEmpty { teile.append((.gedanke, 1, "Gedankengang")) }
        let sortiert = teile.enumerated().sorted { $0.element.n != $1.element.n ? $0.element.n > $1.element.n : $0.offset < $1.offset }.map(\.element)
        return (sortiert.prefix(3).map { SpurTeil(n: $0.n, art: $0.art, text: $0.text) }, dauerText(dauerMs))
    }

    static func dauerText(_ ms: Double?) -> String {
        guard let ms, ms != 0, !ms.isNaN, ms >= 15_000 else { return "" }
        let m = jsRunde(ms / 60_000)
        if m < 1 { return "\(Int(jsRunde(ms / 1000))) Sek." }
        if m < 60 { return "\(Int(m)) Min." }
        let h = Int(m / 60)
        let rest = Int(m) % 60
        return "\(h) Std.\(rest != 0 ? " \(rest) Min." : "")"
    }

    private static func jsRunde(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    static func laufText(_ s: Schritt?) -> String {
        guard let s else { return "" }
        let regeln: [(String, String)] = [
            (#"^Im Web gesucht$"#, "Sucht im Web"),
            (#"^Webseite gelesen$"#, "Liest eine Webseite"),
            (#"^Webseite abgerufen$"#, "Ruft eine Webseite ab"),
            (#"^Datei gelesen$"#, "Liest eine Datei"),
            (#"^Datei geschrieben$"#, "Schreibt eine Datei"),
            (#"^Datei geändert$"#, "Ändert eine Datei"),
            (#"^Dateien durchsucht$"#, "Durchsucht Dateien"),
            (#"^Befehl ausgeführt$"#, "Prüft etwas auf dem Mac"),
            (#"^Programm ausgeführt$"#, "Lässt ein Programm laufen"),
            (#"^Git-Verlauf angesehen$"#, "Sieht den Git-Verlauf an"),
            (#"^(.+) geprüft$"#, "Prüft $1"),
            (#"^Laufende Prozesse geprüft$"#, "Prüft laufende Prozesse"),
            (#"^Auf einen Befehl gewartet$"#, "Wartet auf einen Befehl"),
            (#"^Auf Agenten gewartet$"#, "Wartet auf die Agenten"),
            (#"^(.+) beauftragt$"#, "Beauftragt $1"),
            (#"^(.+) geschrieben$"#, "Schreibt $1"),
            (#"^Stand der Agenten angesehen$"#, "Fragt die Agenten nach dem Stand"),
            (#"^Nachricht verschickt$"#, "Verschickt eine Nachricht"),
            (#"^Fortschritt festgehalten$"#, "Hält den Fortschritt fest"),
            (#"^Im Gedächtnis nachgesehen$"#, "Sieht im Gedächtnis nach"),
            (#"^Im Gedächtnis notiert$"#, "Notiert sich etwas"),
            (#"^Werkzeug benutzt$"#, "Arbeitet"),
        ]
        var t = s.text
        for (muster, neu) in regeln { t = t.ersetze(muster, neu) }
        if let d = s.detail, !d.isEmpty, s.art != .befehl { return "\(t) · \(d)" }
        return t
    }
}
