import Foundation

enum EreignisArt: String, Sendable { case automation, meldung, system, fehler, nachricht }

struct ZugEreignis: Equatable, Sendable {
    var id: String
    var art: EreignisArt
    var titel: String
    var text: String?
    var von: String?
    var jobId: String?
    var warnung = false
    var leise = false
    var systemhinweis = false
    var ts: Double?
    var quelle: Einspeisung?
}

struct ZugAntwort: Equatable, Sendable {
    var id: String
    var text: String
    var ts: Double?
    var modell: String?
    var vorlauf: [String]?
    var jobId: String?
    var fertig = false
}

struct ZugBild: Equatable, Sendable { var id: String; var alt: String; var ts: Double? }
struct ZugAnsicht: Equatable, Sendable { var id: String; var viewId: String; var titel: String; var ts: Double? }

enum VerlaufItem: Equatable, Sendable {
    case user(id: String, text: String, ts: Double?, pending: Bool)
    case assistant(ZugAntwort)
    case tools(id: String, steps: [Schritt], ts: Double?)
    case gedanke(id: String, text: String, ts: Double?)
    case ereignis(ZugEreignis)
    case image(ZugBild)
    case widget(ZugAnsicht)
    case reset(id: String, ts: Double?)

    var id: String {
        switch self {
        case .user(let id, _, _, _), .tools(let id, _, _), .gedanke(let id, _, _), .reset(let id, _): return id
        case .assistant(let a): return a.id
        case .ereignis(let e): return e.id
        case .image(let b): return b.id
        case .widget(let w): return w.id
        }
    }

    var ts: Double? {
        switch self {
        case .user(_, _, let ts, _), .tools(_, _, let ts), .gedanke(_, _, let ts), .reset(_, let ts): return ts
        case .assistant(let a): return a.ts
        case .ereignis(let e): return e.ts
        case .image(let b): return b.ts
        case .widget(let w): return w.ts
        }
    }
}

struct Zug: Equatable, Identifiable, Sendable {
    var id: String
    var start: VerlaufItem?
    var schritte: [Schritt] = []
    var antwort: ZugAntwort?
    var hinweise: [ZugEreignis] = []
    var bilder: [ZugBild] = []
    var widgets: [ZugAnsicht] = []
    var von: Double?
    var bis: Double?
    var laeuft = false
    var kandidat: (a: ZugAntwort, i: Int)?

    static func == (l: Zug, r: Zug) -> Bool {
        l.id == r.id && l.start == r.start && l.schritte == r.schritte && l.antwort == r.antwort && l.hinweise == r.hinweise
            && l.bilder == r.bilder && l.widgets == r.widgets && l.von == r.von && l.bis == r.bis && l.laeuft == r.laeuft
            && l.kandidat?.a == r.kandidat?.a && l.kandidat?.i == r.kandidat?.i
    }
}

enum ZugBlock: Equatable, Identifiable, Sendable {
    case zug(Zug)
    case reset(id: String, ts: Double?)
    case zwischen(Zwischendurch)

    var id: String {
        switch self { case .zug(let z): return z.id; case .reset(let id, _): return id; case .zwischen(let g): return g.id }
    }
}

enum Zuege {

    private static func bloecke(_ content: Any?) -> [Any] {
        if let s = content as? String { return [["type": "text", "text": s] as [String: Any]] }
        if let a = content as? [Any] { return a }
        return []
    }

    static func textVon(_ content: Any?) -> String {
        bloecke(content).compactMap { b -> String? in
            guard let d = b as? [String: Any], let t = d["type"] as? String, t == "text" || t == "output_text", let s = d["text"] as? String else { return nil }
            return s
        }.joined(separator: "\n\n").jsTrim
    }

    private static func kurz(_ s: String, _ n: Int = 90) -> String {
        let t = s.ersetzeAlle(#"\s+"#, " ").jsTrim
        return t.jsLaenge > n ? t.jsSlice(0, n - 1) + "…" : t
    }

    private static func agentAus(_ s: String?) -> String? { s?.treffer(#"agent:([\w-]+)"#)?[1] }

    private static let toolXml = #"</?(?:antml:)?(?:function_calls|invoke|invoke_name|parameter)\b[^>]*>"#

    static func ohneToolText(_ text: String) -> (rest: String, roh: Bool) {
        if !text.passt(toolXml, "i") { return (text, false) }
        var rest = text.ersetzeAlle(#"<(?:antml:)?function_calls>[\s\S]*?(</(?:antml:)?function_calls>|$)"#, "", "i")
        rest = rest.ersetzeAlle(#"<(?:antml:)?invoke\b[\s\S]*?(</(?:antml:)?invoke>|$)"#, "", "i")
        rest = rest.components(separatedBy: "\n").filter { !$0.passt(toolXml, "i") }.joined(separator: "\n").jsTrim
        return (rest, true)
    }

    private static let ansageStart = #"^(lass mich|ich (schaue|sehe|prüfe|hole|sammle|messe|lese|gehe|starte|frage|checke|kläre|suche|fange|werde|mache)\b|erst(mal)?\s|zuerst\b|kurz(er)? (blick|check|moment)|moment\b|einen moment|i'?ll\b|let me\b|i will\b|i'?m going|now,? (i|let)|checking\b|first,? i|okay,? (i|let)|alright)"#
    private static let ansageEnde = #"(ich (prüfe|schaue|sehe|hole|messe|lese|kläre|sammle)[^.!?]*|lass mich[^.!?]*|statt zu raten)[.:…!]?\s*$"#

    static func abspalten(_ text: String) -> (kern: String, vorlauf: [String]) {
        var paras = text.teileNach(#"\n{2,}"#)
        var vorlauf: [String] = []
        while paras.count > 1 {
            let p = paras[0].jsTrim
            let kurzerAbsatz = p.jsLaenge < 240 && !p.passt(#"^(#|[-*•]|\d+[.)]|\||```)"#)
            let englisch = p.passt(#"^[A-Z][^äöüßÄÖÜ]{25,}$"#)
                && p.trefferAnzahl(#"\b(the|and|I'?ll|I|let|first|now|is|are|with|of|to|it|this)\b"#) >= 2
                && !p.passt(#"\b(und|der|die|das|ist|nicht|ich|wir|mit|auf|eine?|für|noch)\b"#, "i")
                && paras.dropFirst().joined(separator: " ").passt(#"[äöüß]"#)
            if kurzerAbsatz && (p.passt(ansageStart, "i") || p.passt(ansageEnde, "i") || englisch) {
                vorlauf.append(p)
                paras.removeFirst()
                continue
            }
            break
        }
        return (paras.joined(separator: "\n\n").jsTrim, vorlauf)
    }

    private static func ausloeser(_ text: String) -> ZugEreignis? {
        if text.passt(#"^A scheduled reminder has been triggered"#, "i") {
            let teile = text.teileNach(#"The reminder content is:\s*"#, "i")
            let inhalt = teile.count > 1 ? teile[1].jsTrim : ""
            let zeile = inhalt.components(separatedBy: "\n").first { !$0.jsTrim.isEmpty } ?? "Erinnerung"
            let fehl = zeile.treffer(#"Automation\s+["“„]?([^"”“]+?)["”“]?\s+failed\s+(\d+)\s+times?"#, "i")
            let wieder = zeile.treffer(#"Automation\s+["“„]?([^"”“]+?)["”“]?\s+(recovered|succeeded|is healthy again)"#, "i")
            let titel: String
            if let fehl { titel = "„\(fehl[1] ?? "")“ ist \(fehl[2] ?? "")× fehlgeschlagen" }
            else if let wieder { titel = "„\(wieder[1] ?? "")“ läuft wieder" }
            else { titel = kurz(zeile.ersetze(#"[.:]\s*$"#, ""), 70) }
            return ZugEreignis(id: "", art: .automation, titel: titel, text: inhalt, warnung: fehl != nil)
        }
        if text.passt(#"^\[cron:"#, "i") || text.passt(#"^Arbeitslauf\."#) {
            return ZugEreignis(id: "", art: .automation, titel: text.passt(#"^Arbeitslauf"#) ? "Arbeitslauf" : "Automatischer Lauf", text: text)
        }
        if text.passt(#"^\[Inter-session"#, "i") || text.passt(#"^\[Subagent"#, "i") {
            let von = agentAus(text.treffer(#"sourceSession=(\S+)"#)?[1]) ?? agentAus(text)
            let fertig = (text.components(separatedBy: "\n").first ?? "").passt(#"completed|finished|done|abgeschlossen"#, "i")
            var body = text.ersetze(#"^\[[^\]]*\][^\n]*\n?"#, "")
            body = body.ersetze(#"^This content was routed[^\n]*\n?"#, "", "im")
            body = SystemMuster.ohnePraefixZeile(body).jsTrim
            let titel = text.passt(#"^\[Subagent"#, "i") ? (fertig ? "Helfer ist fertig" : "Rückmeldung eines Helfers") : "Rückmeldung"
            return ZugEreignis(id: "", art: .meldung, titel: titel, text: body, von: von)
        }
        if text.passt(#"^System:"#, "i") || text.passt(#"^<system"#, "i") || SystemMuster.beginntMitKlammer(text) {
            let ohne = text.ersetze(#"^System:\s*(\[[^\]]*\]\s*)?"#, "", "i")
            let erste = ohne.components(separatedBy: "\n").first ?? ""
            if let g = erste.treffer(#"^Externe Arbeit \S+ ["“„]([^"”“]+)["”“] \(([\w-]+), PID \d+\) ist (mit Fehler )?beendet"#) {
                let fehler = g[3] != nil
                return ZugEreignis(id: "", art: .system, titel: "Die Arbeit „\(g[1] ?? "")“ ist \(fehler ? "mit einem Fehler " : "")beendet", text: text, von: g[2],
                                   warnung: fehler && !text.contains("Nur zur Kenntnis"), leise: true)
            }
            return ZugEreignis(id: "", art: .system, titel: kurz(erste.isEmpty ? "Systemmeldung" : erste, 70), text: text,
                               warnung: erste.passt(#"error|fail|fehl"#, "i"), leise: text.passt(#"^System:"#, "i"))
        }
        return nil
    }

    private static func ereignis(aus ein: Einspeisung, text: String) -> ZugEreignis {
        let art: EreignisArt
        switch ein.art {
        case .agent, .unteragent: art = .meldung
        case .system, .aufsicht: art = .system
        case .automation: art = .automation
        }
        let erste = text.components(separatedBy: "\n").first { !$0.jsTrim.isEmpty } ?? "Meldung"
        return ZugEreignis(id: "", art: art, titel: kurz(erste, 70), text: text, von: ein.von, leise: art == .system && text.passt(#"^System:"#))
    }

    private static let werkzeugTypen: Set<String> = ["toolcall", "tool_use", "tool_call", "tooluse", "function_call", "functioncall", "server_tool_use", "mcp_tool_use", "tool-call"]

    private static func zeitstempel(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        guard let s = v as? String else { return nil }
        return IsoZeit.datum(s).map { $0.timeIntervalSince1970 * 1000 }
    }

    static func kennung(_ m: [String: Any]) -> String {
        if let a = (m[SpeicherFeld.lokal] as? [String: Any])?[SpeicherFeld.anzeige] as? String, !a.isEmpty { return a }
        return ((m["__openclaw"] as? [String: Any]).flatMap { jsErster($0["id"]) } ?? jsErster(m["id"])).map { jsText($0) } ?? ""
    }

    static func toItems(_ messages: [[String: Any]], ab: Int = 0) -> [VerlaufItem] { eintraege(messages, ab: ab).items }

    static func laeufe(_ m: [String: Any]) -> [String] {
        var out: [String] = []
        if let k = ChatLogic.runKey(m) { out.append(k) }
        if m["role"] as? String == "user" {
            let k = ChatLogic.idempotencyKey(of: m)
            if let kern = k.components(separatedBy: ":").first?.lowercased(), !kern.isEmpty, !out.contains(kern) { out.append(kern) }
        }
        for l in (m[SpeicherFeld.lokal] as? [String: Any])?[SpeicherFeld.laeufe] as? [String] ?? [] where !out.contains(l.lowercased()) { out.append(l.lowercased()) }
        if let f = (m[SpeicherFeld.lokal] as? [String: Any])?[SpeicherFeld.frage] as? String, !out.contains(f.lowercased()) { out.append(f.lowercased()) }
        return out
    }

    static func eintraege(_ messages: [[String: Any]], ab: Int = 0) -> (items: [VerlaufItem], laeufe: [String: [String]]) {
        var laufVon: [String: [String]] = [:]
        var zeilenLaeufe: [String] = []
        var gezaehlt = 0
        var items: [VerlaufItem] = [] {
            didSet {
                if items.count > gezaehlt, !zeilenLaeufe.isEmpty { laufVon[items[items.count - 1].id] = zeilenLaeufe }
                gezaehlt = items.count
            }
        }
        var toolRun: Int?
        var seen: [String] = []

        var kennungen: [String: Int] = [:]

        for (lokal, m) in messages.enumerated() {
            let eigene = kennung(m)
            var id = eigene.isEmpty ? "m\(lokal + ab)" : eigene
            if let n = kennungen[id] { kennungen[id] = n + 1; id += "#\(n)" } else { kennungen[id] = 1 }
            var teil = 0
            func teilId(_ art: String) -> String { teil += 1; return id + ":" + art + "\(teil)" }
            let ts = zeitstempel(m["timestamp"])
            let role = m["role"] as? String
            zeilenLaeufe = laeufe(m)

            if role == "user" {
                toolRun = nil
                var roh = textVon(m["content"]).ersetze(#"\s*\[Vom iPhone[^\]]*\]\s*$"#, "")
                if let rest = SystemMuster.fortgesetztRest(roh) { roh = rest }
                if roh.isEmpty || SystemMuster.istVersteckt(roh) { continue }
                let bereinigt = Werkzeugtext.bereinige(roh).rest
                if !Urheber.istAuftragsWeckruf(roh), !SystemMuster.istProbe(roh), Werkzeugtext.istReinerSystemtext(roh) || (bereinigt.isEmpty && roh != bereinigt) {
                    items.append(.ereignis(ZugEreignis(id: id, art: .system, titel: Werkzeugtext.systemhinweisTitel, text: roh.jsLaenge > 4000 ? roh.jsSlice(0, 4000) + "…" : roh,
                                                       leise: true, systemhinweis: true, ts: ts)))
                    continue
                }
                let text = bereinigt.isEmpty ? roh : bereinigt
                let urheber = Urheber.erkenne(zeile: m, text: text)
                var e: ZugEreignis?
                switch urheber {
                case .antonio:
                    let meta = m["__openclaw"] as? [String: Any]
                    let absender = (meta?["senderId"] as? String).map { !$0.isEmpty } ?? false
                    e = absender || Urheber.kanalAbsender(meta) != nil ? nil : ausloeser(text)
                case .kanal(let a):
                    e = ZugEreignis(id: "", art: .nachricht, titel: a.bezeichnung, text: text, von: a.name)
                case .unbelegt:
                    e = ausloeser(text)
                    if e == nil, items.contains(where: { if case .user(_, let t, _, _) = $0 { return text.jsTrim.jsEndsWith(t.jsTrim) }; return false }) { continue }
                    if e == nil { e = ereignis(aus: Einspeisung(art: .system), text: text); e?.leise = true }
                case .eingespeist(let ein):
                    e = ausloeser(text) ?? ereignis(aus: ein, text: text)
                    e?.quelle = ein
                }
                seen.removeAll()
                if var e { e.id = id; e.ts = ts; items.append(.ereignis(e)) }
                else { items.append(.user(id: id, text: text, ts: ts, pending: SpeicherFeld.wartet(m))) }
                continue
            }

            if role == "assistant" {
                let label = jsText(m["senderLabel"])
                let provenance = m["provenance"] as? [String: Any]
                if (provenance?["kind"] as? String) == "inter_session" || label.passt(#"^Forwarded from"#, "i") {
                    toolRun = nil
                    let text = textVon(m["content"])
                    if text.isEmpty { continue }
                    let von = label.treffer(#"^Forwarded from\s+(\S+)"#, "i")?[1] ?? agentAus(provenance?["sourceSessionKey"] as? String)
                    items.append(.ereignis(ZugEreignis(id: id, art: .meldung, titel: "Meldung", text: text, von: von, ts: ts)))
                    continue
                }
                var jobId: String?
                if let auto = m["openclawAutomation"] as? [String: Any], (auto["kind"] as? String) == "cron" {
                    let j = jsText(auto["jobId"])
                    jobId = j.isEmpty ? "cron" : j
                }
                var letzteAntwort: Int?
                for case let b as [String: Any] in bloecke(m["content"]) {
                    let typ = b["type"] as? String
                    let btext = b["text"] as? String
                    if (typ == "text" || typ == "output_text"), let btext, !btext.jsTrim.isEmpty {
                        toolRun = nil
                        let roh = btext.jsTrim
                        if roh.passt(#"^\s*NO_REPLY\s*$"#, "i") || roh.passt(#"^✅ Session reset"#) || roh.passt(#"^HEARTBEAT_OK"#, "i") { continue }
                        if roh.passt(#"^I couldn't continue this session after a gateway restart"#, "i") {
                            items.append(.ereignis(ZugEreignis(id: teilId("n"), art: .system, titel: "Dieser Chat wurde durch einen Gateway-Neustart beendet",
                                                               text: "Der bisherige Verlauf ist sicher. Mit /new beginnt ein neuer Chat mit diesem Mitarbeiter.", warnung: true, ts: ts)))
                            continue
                        }
                        if seen.contains(roh) { continue }
                        var text = roh
                        if let bekannt = seen.filter({ $0.jsLaenge > 40 && text.jsEndsWith($0) }).max(by: { $0.jsLaenge < $1.jsLaenge }) {
                            text = text.jsSlice(0, text.jsLaenge - bekannt.jsLaenge).jsTrim
                            for s in seen.sorted(by: { $0.jsLaenge > $1.jsLaenge }) where s.jsLaenge > 40 { text = text.replacingOccurrences(of: s, with: "") }
                            text = text.ersetzeAlle(#"\n{3,}"#, "\n\n").jsTrim
                            if text.isEmpty { continue }
                        }
                        var frueher: String?
                        for s in seen where text.jsStartsWith(s + "\n") {
                            if frueher == nil || s.jsLaenge > frueher!.jsLaenge { frueher = s }
                        }
                        if let frueher { text = text.jsSlice(frueher.jsLaenge).jsTrim }
                        seen.append(roh)
                        let w = Werkzeugtext.bereinige(text, ts: ts)
                        let t = ohneToolText(w.rest)
                        if !w.schritte.isEmpty {
                            items.append(.tools(id: teilId("w"), steps: w.schritte, ts: ts))
                        }
                        if (w.bereinigt || t.roh) && t.rest.isEmpty { continue }
                        let (kern, vorlauf) = abspalten(t.rest)
                        let modell: String? = jsWahr(m["model"]) && jsWahr(m["provider"]) && !SystemMuster.istSystemAnbieter(m["provider"]) ? jsText(m["model"]) : nil
                        items.append(.assistant(ZugAntwort(id: teilId(""), text: kern, ts: ts, modell: modell, vorlauf: vorlauf.isEmpty ? nil : vorlauf, jobId: jobId)))
                        letzteAntwort = items.count - 1
                    } else if typ == "thinking", jsWahr(b["thinking"]) || jsWahr(b["text"]) {
                        toolRun = nil
                        items.append(.gedanke(id: teilId("g"), text: jsText(jsErster(b["thinking"], b["text"])), ts: ts))
                    } else if let typ, Self.werkzeugTypen.contains(typ.lowercased()) {
                        if toolRun == nil {
                            items.append(.tools(id: teilId("t"), steps: [], ts: ts))
                            toolRun = items.count - 1
                        }
                        let name = jsText(jsErster(b["name"], b["toolName"]) ?? "Werkzeug")
                        let s = Arbeitsspur.schritt(name, jsErster(b["arguments"], b["input"], b["args"]), ts: ts)
                        if case .tools(let tid, var steps, let tts) = items[toolRun!] {
                            steps.append(s)
                            items[toolRun!] = .tools(id: tid, steps: steps, ts: tts)
                        }
                    } else if typ == "image" {
                        toolRun = nil
                        items.append(.image(ZugBild(id: teilId("i"), alt: jsText(jsErster(b["alt"]) ?? "Bild"), ts: ts)))
                    } else if typ == "canvas", let pv = b["preview"] as? [String: Any], (pv["kind"] as? String) == "canvas",
                              let vid = pv["viewId"] as? String, !vid.jsTrim.isEmpty {
                        let titel = jsText(pv["title"]).jsTrim
                        items.append(.widget(ZugAnsicht(id: teilId("w"), viewId: vid.jsTrim, titel: titel.isEmpty ? "Ansicht" : titel, ts: ts)))
                    }
                }
                if let li = letzteAntwort, jsText(m["stopReason"]).passt(#"^(end_?turn|stop)$"#, "i"), case .assistant(var a) = items[li] {
                    a.fertig = true
                    items[li] = .assistant(a)
                }
                continue
            }

            if role == "custom" {
                if (m["display"] as? Bool) == false { continue }
                let text = textVon(m["content"])
                if text.isEmpty { continue }
                toolRun = nil
                let fehler = text.passt(#"did not run|error|fehl"#, "i")
                items.append(.ereignis(ZugEreignis(id: id, art: fehler ? .fehler : .system,
                                                   titel: text.passt(#"did not run"#, "i") ? "Lauf nicht gestartet" : kurz(text, 70), text: text, ts: ts)))
                continue
            }

            if role == "system", ((m["__openclaw"] as? [String: Any])?["kind"] as? String) == "reset" {
                toolRun = nil
                items.append(.reset(id: id, ts: ts))
                continue
            }
        }
        return (items, laufVon)
    }

    private static let luecke: Double = 8 * 60_000
    private static let stille: Double = 3 * 60_000

    private static func zurueckstufen(_ z: inout Zug) {
        guard let a = z.antwort else { return }
        for v in a.vorlauf ?? [] { z.schritte.append(Arbeitsspur.gedanke(v, ts: a.ts)) }
        var ohne = a
        ohne.vorlauf = nil
        z.kandidat = (ohne, z.schritte.count)
        z.schritte.append(Arbeitsspur.gedanke(a.text, ts: a.ts))
        z.antwort = nil
    }

    private static func abschliessen(_ z: inout Zug) {
        if z.antwort != nil || z.laeuft { return }
        guard let k = z.kandidat else { return }
        z.antwort = k.a
        if k.i < z.schritte.count { z.schritte.remove(at: k.i) }
        z.kandidat = nil
    }

    static let neubeginnNachFrage: Double = 10_000

    static func zuege(_ items: [VerlaufItem], laeufe: [String: [String]] = [:], laufSeit: Double? = nil, laufSchluessel: String? = nil,
                      jetzt: Double = Date().timeIntervalSince1970 * 1000) -> [ZugBlock] {
        var out: [ZugBlock] = []
        var zugVonLauf: [String: Int] = [:]
        var letzterAusloeser: Int?
        var z: Int?
        var letzteTs: Double = 0
        var offen: [Int] = []

        func neu(_ start: VerlaufItem?, _ id: String, _ ts: Double?) -> Int {
            out.append(.zug(Zug(id: id, start: start, von: start?.ts ?? ts)))
            return out.count - 1
        }
        func zug(_ i: Int) -> Zug { if case .zug(let x) = out[i] { return x }; fatalError("kein Zug") }
        func aendere(_ i: Int, _ f: (inout Zug) -> Void) {
            guard case .zug(var x) = out[i] else { return }
            f(&x)
            out[i] = .zug(x)
        }

        for it in items {
            let ts = it.ts ?? 0
            if case .reset(let id, let rts) = it {
                if let zi = z, zi == out.count - 1, case .user(_, _, let fts, _)? = zug(zi).start, zug(zi).antwort == nil, zug(zi).schritte.isEmpty,
                   let fts, let rts, rts >= fts, rts - fts < neubeginnNachFrage {
                    out.insert(.reset(id: id, ts: rts), at: zi)
                    z = zi + 1
                    offen = [zi + 1]
                    letzterAusloeser = zi + 1
                    for (l, i) in zugVonLauf where i >= zi { zugVonLauf[l] = i + 1 }
                    continue
                }
                out.append(.reset(id: id, ts: rts))
                z = nil
                offen = []
                letzterAusloeser = nil
                continue
            }
            if !offen.isEmpty && ts != 0 && letzteTs != 0 && ts - letzteTs > stille { offen = [] }
            if case .ereignis(let e) = it, e.systemhinweis {
                if let zi = z { aendere(zi) { if !$0.hinweise.contains(where: { $0.systemhinweis }) { $0.hinweise.append(e) } } }
                continue
            }
            if case .ereignis(let e) = it, e.leise, !e.warnung, !offen.isEmpty { continue }
            var ausloesend = false
            switch it {
            case .user: ausloesend = true
            case .ereignis(let e): ausloesend = e.art != .fehler || z == nil
            default: break
            }
            if case .user(_, _, _, true) = it {
                let n = neu(it, it.id, nil)
                for l in laeufe[it.id] ?? [] { zugVonLauf[l] = n }
                continue
            }
            if ausloesend {
                let n = neu(it, it.id, nil)
                z = n
                letzterAusloeser = n
                for l in laeufe[it.id] ?? [] { zugVonLauf[l] = n }
                if case .user = it { offen.append(n) }
                if ts != 0 { letzteTs = ts }
                continue
            }

            var auto = false
            var jobId: String?
            if case .assistant(let a) = it, let j = a.jobId, !j.isEmpty {
                var laufendeAutomation = false
                if let zi = z, case .ereignis(let se)? = zug(zi).start, se.art == .automation, zug(zi).antwort == nil { laufendeAutomation = true }
                auto = !laufendeAutomation
                jobId = j
            }
            let pause = z != nil && ts != 0 && letzteTs != 0 && ts - letzteTs > luecke
            if pause { offen = [] }
            var istEreignis = false
            if case .ereignis = it { istEreignis = true }
            let eigeneLaeufe = laeufe[it.id] ?? []
            let gebunden = eigeneLaeufe.lazy.compactMap { zugVonLauf[$0] }.first
            if let gebunden { z = gebunden }
            else if !eigeneLaeufe.isEmpty { if !auto, !istEreignis, let l = letzterAusloeser { z = l } }
            else if !auto && !offen.isEmpty && !istEreignis { z = offen[0] }
            var nachAbschluss = false
            if gebunden == nil, let zi = z, zug(zi).antwort?.fertig == true {
                switch it { case .assistant, .tools, .gedanke: nachAbschluss = true; default: break }
            }
            if z == nil || auto || (pause && gebunden == nil) || nachAbschluss {
                var start: VerlaufItem?
                if auto { start = .ereignis(ZugEreignis(id: it.id + ":auto", art: .automation, titel: "Automatischer Lauf", jobId: jobId, ts: ts)) }
                z = neu(start, it.id + ":z", ts)
            }
            let zi = z!
            if gebunden == nil { for l in eigeneLaeufe { zugVonLauf[l] = zi } }
            if ts != 0 {
                letzteTs = ts
                aendere(zi) { $0.von = $0.von ?? ts; $0.bis = ts }
            }
            switch it {
            case .assistant(let a):
                aendere(zi) { zurueckstufen(&$0); $0.antwort = a }
                if a.fertig { offen.removeAll { $0 == zi } }
            case .tools(_, let steps, _):
                aendere(zi) { zurueckstufen(&$0); $0.schritte.append(contentsOf: steps) }
            case .gedanke(_, let text, let gts):
                aendere(zi) { $0.schritte.append(Arbeitsspur.gedanke(text, ts: gts)) }
            case .ereignis(let e):
                aendere(zi) { if $0.hinweise.last?.titel != e.titel { $0.hinweise.append(e) } }
            case .image(let b):
                aendere(zi) { $0.bilder.append(b) }
            case .widget(let w):
                aendere(zi) { if !$0.widgets.contains(where: { $0.viewId == w.viewId }) { $0.widgets.append(w) } }
            default: break
            }
        }

        if let laufSeit, laufSeit != 0 {
            let zuege = out.indices.filter { if case .zug = out[$0] { return true }; return false }
            func gehoert(_ l: Zug) -> Bool { l.antwort == nil || (l.antwort!.ts ?? jetzt) >= laufSeit - 5000 }
            var ziel: Int?
            if let k = laufSchluessel?.lowercased(), !k.isEmpty { ziel = zugVonLauf[k] }
            if ziel == nil, laufSchluessel == nil, let li = zuege.last, gehoert(zug(li)) { ziel = li }
            if let li = ziel {
                aendere(li) { zurueckstufen(&$0); $0.laeuft = true }
            } else {
                out.append(.zug(Zug(id: "lauf-" + jsText(NSNumber(value: laufSeit)), von: laufSeit, laeuft: true)))
            }
        }
        for i in out.indices { aendere(i) { abschliessen(&$0) } }
        for i in out.indices {
            aendere(i) { z in
                if let a = z.antwort, let v = a.vorlauf { z.schritte.append(contentsOf: v.map { Arbeitsspur.gedanke($0, ts: a.ts) }) }
            }
        }
        return out
    }

    static func agentNameKurz(_ id: String) -> String {
        id == Hauptagent.id ? "Seneca" : id.split(separator: "-", omittingEmptySubsequences: false).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
    }
}

enum CodeFalte {
    static let maxZeilen = 6
    static func zeilen(_ code: String) -> Int {
        let t = code.trimmingCharacters(in: .newlines)
        return t.isEmpty ? 0 : t.components(separatedBy: "\n").count
    }
    static func eingeklappt(_ code: String) -> Bool { zeilen(code) > maxZeilen }
}
