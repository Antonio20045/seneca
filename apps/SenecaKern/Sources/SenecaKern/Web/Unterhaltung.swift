import Foundation

struct Einspeisung: Equatable, Sendable {
    enum Art: String, Sendable { case agent, unteragent, system, automation, aufsicht }
    var art: Art
    var von: String?
    var fertig = false
    var auftrag = false
    var probe = false

    func bezeichnung(namen: [String: String] = [:]) -> String {
        switch art {
        case .agent: return von.map { namen[$0] ?? Zuege.agentNameKurz($0) } ?? "Agent"
        case .unteragent: return fertig ? "Unteragent fertig" : "Unteragent"
        case .system: return "System"
        case .automation: return "Automation"
        case .aufsicht: return "Aufsicht"
        }
    }
}

struct KanalAbsender: Equatable, Sendable {
    var kanal: String?
    var name: String?

    static func kanalName(_ k: String?) -> String? {
        guard let k = k?.jsTrim, !k.isEmpty else { return nil }
        let bekannt = ["whatsapp": "WhatsApp", "imessage": "iMessage", "sms": "SMS", "telegram": "Telegram", "signal": "Signal", "slack": "Slack", "discord": "Discord"]
        return bekannt[k.lowercased()] ?? k.prefix(1).uppercased() + k.dropFirst()
    }

    var bezeichnung: String {
        switch (name, Self.kanalName(kanal)) {
        case (let n?, let k?): return "\(n) (\(k))"
        case (let n?, nil): return n
        case (nil, let k?): return k
        default: return "Fremde Nachricht"
        }
    }

    static func gekuerzt(_ id: String) -> String {
        let t = id.jsTrim
        return t.jsLaenge > 9 ? t.jsSlice(0, 5) + "…" + t.jsSlice(t.jsLaenge - 2) : t
    }
}

enum Urheber: Equatable, Sendable {
    case antonio
    case kanal(KanalAbsender)
    case eingespeist(Einspeisung)
    case unbelegt

    static func erkenne(zeile m: [String: Any], text: String) -> Urheber {
        let u = erkenneOhneProbe(zeile: m, text: text)
        guard SystemMuster.istProbe(text) else { return u }
        switch u {
        case .antonio, .kanal: return u
        case .eingespeist(var e): e.probe = true; return .eingespeist(e)
        case .unbelegt: return .eingespeist(Einspeisung(art: .system, probe: true))
        }
    }

    static func kanalAbsender(_ meta: [String: Any]?) -> (vonAntonio: Bool, absender: KanalAbsender)? {
        guard let meta else { return nil }
        func wort(_ v: Any?) -> String? { (v as? String).map { $0.jsTrim }.flatMap { $0.isEmpty ? nil : $0 } }
        let identitaet = meta["senderIdentity"] as? [String: Any]
        let typ = wort(identitaet?["type"])
        let kanal = wort((meta["transport"] as? [String: Any])?["channel"]) ?? (typ == "profile" ? nil : wort(identitaet?["pluginId"]))
        let id = wort(meta["senderId"])
        let eigentuemer = meta["senderIsOwner"] as? Bool
        let beobachtet = typ == "observation" || typ == "remote"
        guard kanal != nil || beobachtet || (id != nil && eigentuemer == false && typ != "profile") else { return nil }
        let name = wort(meta["senderName"]) ?? wort(meta["senderUsername"]) ?? id.map(KanalAbsender.gekuerzt)
        let absender = KanalAbsender(kanal: kanal, name: name)
        if id != nil { return (eigentuemer == true, absender) }
        return (kanal != nil, absender)
    }

    private static func erkenneOhneProbe(zeile m: [String: Any], text: String) -> Urheber {
        let meta = m["__openclaw"] as? [String: Any]
        if let p = m["provenance"] as? [String: Any] {
            var e = ausProvenance(p, text: text)
            e.auftrag = istAuftragsWeckruf(text)
            return .eingespeist(e)
        }
        if (m["display"] as? Bool) == false { return .eingespeist(einspeisungAusText(text) ?? Einspeisung(art: .system)) }
        if let k = kanalAbsender(meta) { return k.vonAntonio ? .antonio : .kanal(k.absender) }
        if let s = meta?["senderId"] as? String, !s.isEmpty { return .antonio }
        if (m[SpeicherFeld.lokal] as? [String: Any])?[SpeicherFeld.art] as? String == "frage" { return .antonio }
        if let e = einspeisungAusText(text) { return .eingespeist(e) }
        let schluessel = (m["idempotencyKey"] as? String) ?? (meta?["idempotencyKey"] as? String) ?? ""
        if schluessel.hasPrefix("cron-") || m["openclawAutomation"] != nil { return .eingespeist(Einspeisung(art: .automation)) }
        if meta?["importedFrom"] != nil { return .unbelegt }
        return .eingespeist(Einspeisung(art: schluessel.hasPrefix("wache-") ? .aufsicht : .system))
    }

    private static func agentAus(_ s: String?) -> String? { s?.treffer(#"agent:([\w-]+)"#)?[1] }

    private static func ausProvenance(_ p: [String: Any], text: String) -> Einspeisung {
        let kind = p["kind"] as? String ?? ""
        let quelle = p["sourceSessionKey"] as? String
        let werkzeug = p["sourceTool"] as? String ?? ""
        let von = agentAus(quelle)
        if kind == "inter_session" {
            let unter = werkzeug == "subagent_settle" || (quelle ?? "").passt(#":(subagent|acp):"#) || text.passt(#"^\[Subagent"#, "i")
            if unter { return Einspeisung(art: .unteragent, von: von, fertig: unteragentFertig(text)) }
            return Einspeisung(art: .agent, von: von)
        }
        if p["jobId"] != nil { return Einspeisung(art: .automation) }
        return Einspeisung(art: .system)
    }

    static func istAuftragsWeckruf(_ text: String) -> Bool {
        text.passt(#"^System: \[[^\]]*\] Auftrag A-[A-Z0-9]+ [^\n]*\bist fertig\b"#, "m")
    }

    private static func unteragentFertig(_ text: String) -> Bool {
        text.passt(#"settled|completed|finished|abgeschlossen|\bdone\b"#, "i")
    }

    static func einspeisungAusText(_ text: String) -> Einspeisung? {
        let t = text.jsTrim
        if istAuftragsWeckruf(t) { return Einspeisung(art: .system, auftrag: true) }
        if t.passt(#"\[Inter-session message\]"#, "i") {
            let quelle = t.treffer(#"sourceSession=(\S+)"#)?[1]
            let unter = (t.treffer(#"sourceTool=(\S+)"#)?[1] ?? "") == "subagent_settle" || (quelle ?? "").passt(#":(subagent|acp):"#) || t.passt(#"\[Subagent Context\]"#)
            let von = agentAus(quelle)
            return unter ? Einspeisung(art: .unteragent, von: von, fertig: unteragentFertig(t)) : Einspeisung(art: .agent, von: von)
        }
        if t.passt(#"\[Subagent Context\]"#) { return Einspeisung(art: .unteragent, von: agentAus(t), fertig: unteragentFertig(t)) }
        if let m = t.treffer(#"^Rückmeldung von\s+([^\n]+)"#) {
            return Einspeisung(art: .agent, von: m[1]?.jsTrim, fertig: false)
        }
        if t.passt(#"<<<BEGIN_OPENCLAW_INTERNAL_CONTEXT>>>"#) { return Einspeisung(art: .system) }
        if t.passt(#"OpenClaw resumed this CLI session"#) { return Einspeisung(art: .system) }
        if t.passt(#"\[Retry after the previous model attempt"#) { return Einspeisung(art: .system) }
        if t.passt(#"^System:"#, "m") || t.passt(#"^Systemmeldung:"#) || t.passt(#"^<system"#, "i") { return Einspeisung(art: .system) }
        if t.passt(#"^Aufsicht \(Skript"#) { return Einspeisung(art: .aufsicht) }
        if t.passt(#"^\[OpenClaw"#, "i") || t.passt(#"^(An async command completion|Exec completed|Exec failed|Read HEARTBEAT)"#, "i")
            || t.passt(#"^This session is being continued from a previous conversation"#) { return Einspeisung(art: .system) }
        if t.passt(#"^A scheduled reminder has been triggered"#, "i") || t.passt(#"^\[cron:"#, "i") || t.passt(#"^Arbeitslauf\."#) {
            return Einspeisung(art: .automation)
        }
        return nil
    }
}

struct ZwischenEintrag: Equatable, Identifiable, Sendable {
    var id: String
    var quelle: Einspeisung
    var ts: Double?
    var kurz: String?
    var voll: String?
}

struct Zwischendurch: Equatable, Identifiable, Sendable {
    var id: String
    var eintraege: [ZwischenEintrag]

    var kopf: String { "Zwischendurch · \(eintraege.count) \(eintraege.count == 1 ? "Meldung" : "Meldungen")" }
}

enum NachrichtStatus: String, Equatable, Sendable {
    case gesendet, wartet, inArbeit, beantwortet

    var text: String {
        switch self {
        case .gesendet: return "gesendet"
        case .wartet: return "wartet"
        case .inArbeit: return "in Arbeit"
        case .beantwortet: return "beantwortet"
        }
    }
}

struct LeisteInfo: Equatable, Sendable {
    var zugId: String
    var anfang: String
    var status: NachrichtStatus?
}

enum Unterhaltung {
    private static func eintrag(_ z: Zug) -> ZwischenEintrag? {
        if istAuftragsErgebnis(z) { return nil }
        guard case .ereignis(let e)? = z.start, e.art != .fehler, e.art != .nachricht, e.quelle != nil || e.art != .automation, !e.warnung, z.bilder.isEmpty, z.widgets.isEmpty,
              !z.laeuft, !z.hinweise.contains(where: \.warnung) else { return nil }
        let quelle: Einspeisung = e.quelle ?? {
            switch e.art {
            case .automation: return Einspeisung(art: .automation)
            case .meldung: return Einspeisung(art: .agent, von: e.von)
            default: return Einspeisung(art: .system)
            }
        }()
        return ZwischenEintrag(id: z.id, quelle: quelle, ts: e.ts ?? z.von, kurz: z.antwort.map { ersterSatz($0.text) }.flatMap { $0.isEmpty ? nil : $0 },
                              voll: z.antwort.map { $0.text.jsTrim }.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func istAuftragsErgebnis(_ z: Zug) -> Bool {
        guard case .ereignis(let e)? = z.start, e.quelle?.auftrag == true, e.quelle?.probe != true, !z.laeuft, let a = z.antwort else { return false }
        return !a.text.jsTrim.isEmpty
    }

    static let auftragsVermerk = "Ergebnis eines Auftrags"

    static func kanalNachricht(_ z: Zug) -> ZugEreignis? {
        if case .ereignis(let e)? = z.start, e.art == .nachricht { return e }
        return nil
    }

    static func antwortAn(_ z: Zug) -> String? { kanalNachricht(z).map { "Antwort an " + $0.titel } }

    static func istProbe(_ z: Zug) -> Bool {
        switch z.start {
        case .user?: return false
        case .ereignis(let e)? where e.quelle?.probe == true: return true
        default: return z.antwort.map { SystemMuster.istProbeQuittung($0.text) } ?? false
        }
    }

    static func ohneProben(_ bloecke: [ZugBlock]) -> [ZugBlock] {
        bloecke.filter { b in
            guard case .zug(let z) = b, istProbe(z) else { return true }
            if case .ereignis(let e)? = z.start, e.warnung || e.art == .fehler { return true }
            return z.hinweise.contains(where: \.warnung)
        }
    }

    static func gruppiere(_ bloecke: [ZugBlock]) -> [ZugBlock] {
        var out: [ZugBlock] = []
        for b in bloecke {
            guard case .zug(let z) = b, let ein = eintrag(z) else { out.append(b); continue }
            if case .zwischen(var g)? = out.last {
                g.eintraege.append(ein)
                out[out.count - 1] = .zwischen(g)
            } else {
                out.append(.zwischen(Zwischendurch(id: "zwischen-" + ein.id, eintraege: [ein])))
            }
        }
        return out
    }

    static func ersterSatz(_ text: String, max: Int = 140) -> String {
        var t = text.ersetzeAlle(#"```[\s\S]*?```"#, " ")
        t = t.ersetzeAlle(#"\[([^\]]*)\]\([^)]*\)"#, "$1")
        t = t.ersetzeAlle(#"(?m)^\s*(#{1,6}|[-*•]|\d+[.)])\s+"#, "")
        t = t.ersetzeAlle(#"[*_`>|]"#, "")
        let zeilen = t.components(separatedBy: "\n").map { $0.jsTrim }.filter { !$0.isEmpty }
        guard var erste = zeilen.first else { return "" }
        if let m = erste.treffer(#"^(.*?\p{L}{3,}[.!?])(?:\s|$)"#), let satz = m[1] { erste = satz }
        erste = erste.ersetzeAlle(#"\s+"#, " ").jsTrim
        return erste.jsLaenge > max ? erste.jsSlice(0, max - 1).jsTrim + "…" : erste
    }

    static func status(_ z: Zug, zustand: ZustellZustand?, live: ChatLive?) -> NachrichtStatus? {
        guard case .user(_, _, let ts, let pending)? = z.start else { return nil }
        if zustand == .fehlgeschlagen { return nil }
        if z.antwort != nil, !z.laeuft { return .beantwortet }
        if z.laeuft { return live?.phase == .queued ? .wartet : (live?.phase == .sending ? .gesendet : .inArbeit) }
        switch zustand {
        case .wirdGesendet?: return .gesendet
        case .angekommen?: return live == nil ? .gesendet : .wartet
        case .arbeitet?: return .inArbeit
        case .fertig?: return nil
        default: break
        }
        if let live, let ts, ts != 0, live.startedAt.timeIntervalSince1970 * 1000 <= ts { return .wartet }
        if pending { return .gesendet }
        return nil
    }

    static func leiste(_ bloecke: [ZugBlock], status: (Zug) -> NachrichtStatus?) -> LeisteInfo? {
        guard let i = bloecke.lastIndex(where: { if case .zug(let z) = $0, case .user? = z.start { return true }; return false }),
              case .zug(let z) = bloecke[i], case .user(_, let text, _, _)? = z.start else { return nil }
        let kamenMeldungen = bloecke[(i + 1)...].contains { b in
            if case .zwischen = b { return true }
            if case .zug(let x) = b, case .ereignis? = x.start { return true }
            return false
        }
        guard kamenMeldungen else { return nil }
        let t = text.ersetzeAlle(#"\s+"#, " ").jsTrim
        return LeisteInfo(zugId: z.id, anfang: t.jsLaenge > 42 ? t.jsSlice(0, 41).jsTrim + "…" : t, status: status(z))
    }
}
