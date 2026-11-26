import Foundation

private func text(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty ? nil : $0 } }
private func zahl(_ v: Any?) -> Double? {
    if v is NSNull { return nil }
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    return nil
}
private func wahr(_ v: Any?) -> Bool { (v as? Bool) ?? ((v as? NSNumber)?.boolValue ?? false) }

struct OvEreignis: Equatable {
    var art: String
    var at: Double
    var vonStatus: String?
    var nachStatus: String?
}

struct OvKommentar: Equatable {
    var id: String?
    var body: String
    var createdAt: Double
    var author: String?
}

struct OvNachweis: Equatable {
    var id: String
    var status: String
    var label: String?
    var note: String?
    var befehl: String? = nil
    var createdAt: Double? = nil
}

struct OvKarte: Equatable, Identifiable {
    var id: String
    var title: String
    var notes: String?
    var status: String
    var priority: String?
    var agentId: String?
    var sessionKey: String?
    var updatedAt: Double?
    var createdAt: Double?
    var completedAt: Double?
    var labels: [String]
    var boardId: String
    var archiviert: Bool
    var events: [OvEreignis] = []
    var kommentare: [OvKommentar] = []
    var nachweise: [OvNachweis] = []
    var belege: [String] = []
    var position: Double = 0

    init(id: String, title: String, notes: String? = nil, status: String = "todo", priority: String? = nil, agentId: String? = nil,
         sessionKey: String? = nil, updatedAt: Double? = nil, createdAt: Double? = nil, completedAt: Double? = nil,
         labels: [String] = [], boardId: String = "default", archiviert: Bool = false) {
        self.id = id; self.title = title; self.notes = notes; self.status = status; self.priority = priority; self.agentId = agentId
        self.sessionKey = sessionKey; self.updatedAt = updatedAt; self.createdAt = createdAt; self.completedAt = completedAt
        self.labels = labels; self.boardId = boardId; self.archiviert = archiviert
    }

    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String else { return nil }
        let meta = j["metadata"] as? [String: Any]
        let auto = meta?["automation"] as? [String: Any]
        self.init(id: id, title: j["title"] as? String ?? "", notes: text(j["notes"]), status: j["status"] as? String ?? "todo",
                  priority: text(j["priority"]), agentId: text(j["agentId"]), sessionKey: text(j["sessionKey"]),
                  updatedAt: zahl(j["updatedAt"]), createdAt: zahl(j["createdAt"]), completedAt: zahl(j["completedAt"]),
                  labels: (j["labels"] as? [Any])?.compactMap { $0 as? String } ?? [],
                  boardId: auto?["boardId"] as? String ?? "default",
                  archiviert: meta?["archivedAt"] != nil && !(meta?["archivedAt"] is NSNull))
        position = zahl(j["position"]) ?? 0
        events = (j["events"] as? [[String: Any]] ?? []).compactMap { e in
            guard let at = zahl(e["at"]) else { return nil }
            return OvEreignis(art: e["kind"] as? String ?? "", at: at, vonStatus: text(e["fromStatus"]), nachStatus: text(e["toStatus"]))
        }
        kommentare = (meta?["comments"] as? [[String: Any]] ?? []).compactMap { k in
            guard let body = k["body"] as? String, let at = zahl(k["createdAt"]) else { return nil }
            return OvKommentar(id: text(k["id"]), body: body, createdAt: at, author: text(k["author"]))
        }
        nachweise = (meta?["proof"] as? [[String: Any]] ?? []).compactMap { n in
            guard let id = n["id"] as? String else { return nil }
            return OvNachweis(id: id, status: n["status"] as? String ?? "unknown", label: text(n["label"]), note: text(n["note"]),
                              befehl: text(n["command"]), createdAt: zahl(n["createdAt"]))
        }
        belege = (meta?["artifacts"] as? [[String: Any]] ?? []).compactMap { a in text(a["path"]) ?? text(a["url"]) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }
}

struct OvBoard: Equatable {
    var id: String
    var name: String?
    var archiviert: Bool
    var standardAgent: String?

    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String else { return nil }
        self.id = id
        name = text(j["name"])
        archiviert = j["archivedAt"] != nil && !(j["archivedAt"] is NSNull)
        standardAgent = text((j["orchestration"] as? [String: Any])?["defaultAssignee"])
    }
    init(id: String, name: String? = nil, archiviert: Bool = false, standardAgent: String? = nil) {
        self.id = id; self.name = name; self.archiviert = archiviert; self.standardAgent = standardAgent
    }
}

struct OvAuftrag: Equatable {
    var id: String
    var name: String?
    var displayName: String?
    var agentId: String?
    var effectiveAgentId: String?
    var aktiv: Bool
    var art: String?
    var everyMs: Double?
    var anchorMs: Double?
    var nextRunAtMs: Double?
    var runningAtMs: Double?
    var lastRunAtMs: Double?
    var lastRunStatus: String?
    var deliveryMode: String?
    var letzterFehler: String?
    var cronAusdruck: String?

    init(id: String, name: String? = nil, displayName: String? = nil, agentId: String? = nil, effectiveAgentId: String? = nil, aktiv: Bool = true,
         art: String? = nil, everyMs: Double? = nil, anchorMs: Double? = nil, nextRunAtMs: Double? = nil, runningAtMs: Double? = nil,
         lastRunAtMs: Double? = nil, lastRunStatus: String? = nil) {
        self.id = id; self.name = name; self.displayName = displayName; self.agentId = agentId; self.effectiveAgentId = effectiveAgentId
        self.aktiv = aktiv; self.art = art; self.everyMs = everyMs; self.anchorMs = anchorMs; self.nextRunAtMs = nextRunAtMs
        self.runningAtMs = runningAtMs; self.lastRunAtMs = lastRunAtMs; self.lastRunStatus = lastRunStatus
    }

    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String else { return nil }
        let s = j["schedule"] as? [String: Any] ?? [:]
        let st = j["state"] as? [String: Any] ?? [:]
        self.init(id: id, name: text(j["name"]), displayName: text(j["displayName"]), agentId: text(j["agentId"]),
                  effectiveAgentId: text(j["effectiveAgentId"]), aktiv: (j["enabled"] as? Bool) ?? true,
                  art: text(s["kind"]), everyMs: zahl(s["everyMs"]), anchorMs: zahl(s["anchorMs"]),
                  nextRunAtMs: zahl(st["nextRunAtMs"]), runningAtMs: zahl(st["runningAtMs"]),
                  lastRunAtMs: zahl(st["lastRunAtMs"]), lastRunStatus: text(st["lastRunStatus"]))
        deliveryMode = text((j["delivery"] as? [String: Any])?["mode"])
        letzterFehler = text((st["lastDiagnostics"] as? [String: Any])?["summary"]) ?? text(st["lastError"])
        cronAusdruck = text(s["expr"])
    }

    var agent: String { agentId ?? effectiveAgentId ?? "" }
}

struct OvSitzung: Equatable {
    var key: String
    var agentId: String?
    var status: String?
    var aktiverLauf: Bool
    var spawnedBy: String?
    var label: String?
    var derivedTitle: String?
    var displayName: String?
    var startedAt: Double?
    var sessionStartedAt: Double?
    var createdAt: Double?
    var updatedAt: Double?
    var endedAt: Double?
    var archiviert = false
    var imHintergrund = false
    var erzeugtDurch: String?
    var letzteAktion: Double?
    var modellAnbieter: String?
    var modell: String?
    var laufzeit: String?
    var modellQuelle: String?
    var modellGesperrt = false
    var effort: String?
    var effortStandard: String?
    var effortStufen: [OvEffortStufe]?
    var tokens: Double?
    var tokensFrisch = true
    var kontextFenster: Double?
    var sitzungsId: String?
    var letzterFehler: String?

    init(key: String, agentId: String? = nil, status: String? = nil, aktiverLauf: Bool = false, spawnedBy: String? = nil, label: String? = nil,
         derivedTitle: String? = nil, displayName: String? = nil, startedAt: Double? = nil, sessionStartedAt: Double? = nil,
         createdAt: Double? = nil, updatedAt: Double? = nil, endedAt: Double? = nil) {
        self.key = key; self.agentId = agentId; self.status = status; self.aktiverLauf = aktiverLauf; self.spawnedBy = spawnedBy
        self.label = label; self.derivedTitle = derivedTitle; self.displayName = displayName; self.startedAt = startedAt
        self.sessionStartedAt = sessionStartedAt; self.createdAt = createdAt; self.updatedAt = updatedAt; self.endedAt = endedAt
    }

    init?(json j: [String: Any]) {
        guard let key = j["key"] as? String else { return nil }
        let ids = (j["activeRunIds"] as? [Any]) ?? []
        self.init(key: key, agentId: text(j["agentId"]), status: text(j["status"]), aktiverLauf: wahr(j["hasActiveRun"]) || !ids.isEmpty,
                  spawnedBy: text(j["spawnedBy"]), label: text(j["label"]), derivedTitle: text(j["derivedTitle"]), displayName: text(j["displayName"]),
                  startedAt: zahl(j["startedAt"]), sessionStartedAt: zahl(j["sessionStartedAt"]), createdAt: zahl(j["createdAt"]),
                  updatedAt: zahl(j["updatedAt"]), endedAt: zahl(j["endedAt"]))
        archiviert = wahr(j["archived"])
        imHintergrund = wahr(j["isBackground"])
        erzeugtDurch = text(j["createdVia"])
        letzteAktion = zahl(j["lastInteractionAt"])
        modellAnbieter = text(j["modelProvider"])
        modell = text(j["model"])
        laufzeit = text((j["agentRuntime"] as? [String: Any])?["id"])
        modellQuelle = text(j["modelOverrideSource"])
        modellGesperrt = (j["modelSelectionLocked"] as? Bool) == true
        effort = text(j["thinkingLevel"])
        effortStandard = text(j["thinkingDefault"])
        if let l = j["thinkingLevels"] as? [[String: Any]] { effortStufen = l.compactMap(OvEffortStufe.init(json:)) }
        else if let l = j["thinkingOptions"] as? [Any] { effortStufen = l.compactMap { ($0 as? String).map { OvEffortStufe(id: $0) } } }
        tokens = zahl(j["totalTokens"])
        tokensFrisch = (j["totalTokensFresh"] as? Bool) != false
        kontextFenster = zahl(j["contextTokens"])
        sitzungsId = text(j["sessionId"])
        letzterFehler = text(j["lastRunError"])
    }

    var live: Bool { aktiverLauf }
}

struct OvEffortStufe: Equatable {
    var id: String
    var label: String?
    init(id: String, label: String? = nil) { self.id = id; self.label = label }
    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String, !id.isEmpty else { return nil }
        self.init(id: id, label: text(j["label"]))
    }
}

struct OvAgent: Equatable {
    var id: String
    var name: String
    var emoji = ""
    var modellErstwahl: String?
    var modellAusweich: [String]?

    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String else { return nil }
        self.id = id
        emoji = ((j["identity"] as? [String: Any])?["emoji"] as? String) ?? ""
        if let m = j["model"] as? [String: Any] {
            modellErstwahl = text(m["primary"])
            modellAusweich = (m["fallbacks"] as? [Any])?.compactMap { $0 as? String }
        } else if let m = text(j["model"]) { modellErstwahl = m }
        let identity = ((j["identity"] as? [String: Any])?["name"] as? String)?.trimmingCharacters(in: .whitespaces)
        let n = (j["name"] as? String)?.trimmingCharacters(in: .whitespaces)
        name = [identity, n].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }
}

struct OvTermin: Equatable {
    var titel: String
    var start: Double
    var ende: Double
    var kalender: String?
    var ganztags: Bool
    var ort: String?
    var id: String = ""

    init(titel: String, start: Double, ende: Double, kalender: String? = nil, ganztags: Bool = false, ort: String? = nil) {
        self.titel = titel; self.start = start; self.ende = ende; self.kalender = kalender; self.ganztags = ganztags; self.ort = ort
    }
}

struct OvKalender: Equatable {
    var ok: Bool
    var geprueftAm: String?
    var hinweis: String?
    var fehlt: Bool
    var termine: [OvTermin]
    var schreibbar: [String] = []
    var zeitraumTage: Int = 0
    var vergangen: OvVergangen?

    init(ok: Bool, geprueftAm: String? = nil, hinweis: String? = nil, fehlt: Bool = false, termine: [OvTermin] = []) {
        self.ok = ok; self.geprueftAm = geprueftAm; self.hinweis = hinweis; self.fehlt = fehlt; self.termine = termine
    }

    init(json j: [String: Any]) {
        self.init(ok: (j["ok"] as? Bool) != false, geprueftAm: text(j["geprueftAm"]), hinweis: text(j["hinweis"]), fehlt: false,
                  termine: Self.termine(j["termine"]))
        schreibbar = (j["schreibbar"] as? [Any])?.compactMap { $0 as? String } ?? []
        zeitraumTage = Int(zahl(j["zeitraumTage"]) ?? 0)
        if let v = j["vergangen"] as? [String: Any] {
            vergangen = OvVergangen(ok: (v["ok"] as? Bool) != false, ab: zahl(v["ab"]) ?? 0, tage: Int(zahl(v["tage"]) ?? 0), termine: Self.termine(v["termine"]))
        }
    }

    static func termine(_ roh: Any?) -> [OvTermin] {
        var gesehen: [String: Int] = [:]
        let liste: [OvTermin] = (roh as? [[String: Any]] ?? []).compactMap { t in
            guard let titel = t["titel"] as? String, let start = zahl(t["start"]) else { return nil }
            var o = OvTermin(titel: titel, start: start, ende: zahl(t["ende"]) ?? start, kalender: text(t["kalender"]),
                             ganztags: wahr(t["ganztags"]), ort: text(t["ort"]))
            let basis = "\(Int(start / 1000))-\(titel)"
            let n = (gesehen[basis] ?? 0) + 1
            gesehen[basis] = n
            o.id = n == 1 ? basis : "\(basis)-\(n)"
            return o
        }
        return liste.sorted { ($0.start, $0.titel) < ($1.start, $1.titel) }
    }
}

struct OvVergangen: Equatable {
    var ok: Bool
    var ab: Double
    var tage: Int
    var termine: [OvTermin]
}

struct OvOption: Equatable {
    var key: String
    var titel: String
    var wirkung: String?
    var aufwand: String?
    var beschreibung: String?
}

struct OvEmpfehlung: Equatable {
    var key: String?
    var text: String
}

struct OvBlockiert: Equatable {
    var id: String
    var titel: String
    var status: String?
}

struct OvEntscheidung: Equatable, Identifiable {
    var id: String
    var frage: String
    var boardId: String
    var bereichId: String?
    var gestelltAm: Double
    var frist: Double?
    var plan: Double?
    var ruhend: Bool
    var bis: Double?
    var kennung: String?
    var kurz: String?
    var kontext = ""
    var optionen: [OvOption] = []
    var empfehlung: OvEmpfehlung?
    var folge: String?
    var risiko: String?
    var projektName = ""
    var leiter: String?
    var leiterSession: String?
    var blockiert: [OvBlockiert] = []
    var notes = ""
    var updatedAt: Double = 0

    init(id: String, frage: String = "Entscheidung", boardId: String = "default", bereichId: String? = nil, gestelltAm: Double = 0,
         frist: Double? = nil, plan: Double? = nil, ruhend: Bool = false, bis: Double? = nil) {
        self.id = id; self.frage = frage; self.boardId = boardId; self.bereichId = bereichId; self.gestelltAm = gestelltAm
        self.frist = frist; self.plan = plan; self.ruhend = ruhend; self.bis = bis; self.projektName = boardId
    }

    static func liste(json roh: [[String: Any]], pm: [String: OvProjektFelder], jetzt: Double) -> [OvEntscheidung] {
        func ms(_ v: Any?) -> Double? {
            if let z = zahl(v) { return z }
            guard let s = v as? String, !s.isEmpty else { return nil }
            if s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return Menschlich.ausIso(s) }
            return SenecaPayloadParser.date(s).map { $0.timeIntervalSince1970 * 1000 }
        }
        func t(_ v: Any?) -> String? {
            guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        func pfadlos(_ v: Any?) -> String { Menschlich.ohnePfade((v as? String) ?? (v.map { "\($0)" } ?? "")) }
        var out: [OvEntscheidung] = []
        for r in roh {
            guard let id = r["id"] as? String, (r["status"] as? String) != "done" else { continue }
            let boardId = (r["boardId"] as? String) ?? "default"
            let bis = ms(r["gesnooztBis"])
            var e = OvEntscheidung(id: id, frage: Menschlich.klartext(r["frage"] as? String).nilWennLeer ?? "Entscheidung", boardId: boardId,
                                   bereichId: text(r["bereichId"]) ?? pm[boardId]?.bereichId, gestelltAm: ms(r["gestelltAm"]) ?? jetzt,
                                   frist: ms(r["frist"]), plan: ms(r["plan"]),
                                   ruhend: wahr(r["ruhend"]) || (bis.map { $0 > jetzt } ?? false), bis: bis)
            e.kennung = t(r["kennung"])
            e.kurz = pfadlos(r["kurz"]).nilWennLeer
            e.kontext = pfadlos(r["kontext"])
            e.optionen = (r["optionen"] as? [[String: Any]] ?? []).compactMap { o in
                guard let k = o["key"], !(k is NSNull), "\(k)" != "" else { return nil }
                return OvOption(key: "\(k)", titel: Menschlich.ohnePfade(o["titel"] as? String ?? ""), wirkung: t(o["wirkung"]), aufwand: t(o["aufwand"]), beschreibung: t(o["beschreibung"]))
            }
            if let m = r["empfehlung"] as? [String: Any], (text(m["text"]) != nil || text(m["key"]) != nil) {
                e.empfehlung = OvEmpfehlung(key: text(m["key"]), text: Menschlich.ohnePfade(m["text"] as? String ?? ""))
            }
            e.folge = t(r["folge"]).map(Menschlich.ohnePfade)
            e.risiko = t(r["risiko"]).map(Menschlich.ohnePfade)
            e.projektName = Menschlich.klartext((r["projektName"] as? String) ?? boardId)
            e.leiter = (r["leiter"] as? String) ?? ((r["leiter"] as? [String: Any])?["id"] as? String)
            e.leiterSession = t(r["leiterSession"])
            e.blockiert = (r["blockiertKarten"] as? [[String: Any]] ?? []).compactMap { k in
                guard let kid = k["id"] else { return nil }
                return OvBlockiert(id: "\(kid)", titel: Menschlich.klartext(k["titel"] as? String), status: text(k["status"]))
            }
            e.notes = (r["notes"] as? String) ?? ""
            e.updatedAt = zahl(r["updatedAt"]) ?? 0
            out.append(e)
        }
        return out
    }
}

private extension String { var nilWennLeer: String? { isEmpty ? nil : self } }

struct OvMeilenstein: Equatable {
    var name: String
    var erreicht: Bool
    var datum: Double?

    init(name: String, erreicht: Bool = false, datum: Double? = nil) {
        self.name = name; self.erreicht = erreicht; self.datum = datum
    }

    init?(json j: [String: Any]) {
        guard let n = (j["name"] as? String)?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        name = n
        erreicht = (j["erreicht"] as? Bool) ?? ((j["status"] as? String) == "erreicht")
        if let z = zahl(j["datum"]) { datum = z } else if let s = j["datum"] as? String { let m = Menschlich.ausIso(s); datum = m.isNaN ? nil : m } else { datum = nil }
    }
}

struct OvProjektFelder: Equatable {
    var name: String
    var bereichId: String
    var unterabteilungId: String
    var abteilung: String
    var ziel: String
    var faellig: Double?
    var status: String
    var meilensteine: [OvMeilenstein]

    init(bereichId: String, abteilung: String, ziel: String, faellig: Double?, name: String = "",
         unterabteilungId: String = "", status: String = "laeuft", meilensteine: [OvMeilenstein] = []) {
        self.name = name; self.bereichId = bereichId; self.unterabteilungId = unterabteilungId
        self.abteilung = abteilung; self.ziel = ziel; self.faellig = faellig
        self.status = status; self.meilensteine = meilensteine
    }
}

struct OvProjektOrdnung: Equatable {
    var revision: Int = 0
    var projekte: [String: OvProjektFelder] = [:]

    init() {}
    init?(json j: [String: Any]) {
        guard let p = j["projekte"] as? [String: Any], let rev = (j["revision"] as? NSNumber)?.intValue else { return nil }
        revision = rev
        for (id, v) in p {
            guard let f = v as? [String: Any] else { continue }
            var faellig: Double?
            if let z = zahl(f["faellig"]) { faellig = z } else if let s = f["faellig"] as? String { let m = Menschlich.ausIso(s); faellig = m.isNaN ? nil : m }
            let meilensteine = (f["meilensteine"] as? [[String: Any]])?.compactMap(OvMeilenstein.init(json:)) ?? []
            projekte[id] = OvProjektFelder(bereichId: f["bereichId"] as? String ?? "", abteilung: f["abteilung"] as? String ?? "",
                                           ziel: f["ziel"] as? String ?? "", faellig: faellig, name: f["name"] as? String ?? "",
                                           unterabteilungId: f["unterabteilungId"] as? String ?? "",
                                           status: f["status"] as? String ?? "laeuft", meilensteine: meilensteine)
        }
    }
}

struct OvSitzungsStandard: Equatable {
    var anbieter: String?
    var modell: String?
    var effortStufen: [OvEffortStufe] = []
    var effortStandard: String?

    init() {}
    init(json j: [String: Any]) {
        anbieter = text(j["modelProvider"]); modell = text(j["model"])
        effortStufen = (j["thinkingLevels"] as? [[String: Any]])?.compactMap(OvEffortStufe.init(json:)) ?? []
        effortStandard = text(j["thinkingDefault"])
    }
}

struct OvUnterabteilung: Equatable {
    var id: String
    var name: String
    var agent: String
}

struct OvDaten: Equatable {
    var cards: [OvKarte] = []
    var boards: [OvBoard] = []
    var jobs: [OvAuftrag] = []
    var agents: [OvAgent] = []
    var defaultAgent = Hauptagent.id
    var rows: [OvSitzung] = []
    var kalender: OvKalender?
    var gesehen: [String: Double] = [:]
    var bereiche: AreaRegistry?
    var unterabteilungen: [String: [OvUnterabteilung]] = [:]
    var sitzungsStandard = OvSitzungsStandard()
    var pm = OvProjektOrdnung()
    var entRoh: [OvEntscheidung]?
    var liste: ArbeitsListe?
    var geladen = false
    var workboardFehler = false

    func label(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "" }
        if let n = mitarbeiterName(id) { return n }
        if let n = bereiche?.areas.first(where: { $0.leader == id })?.leaderName, !n.isEmpty { return n }
        if let n = agents.first(where: { $0.id == id })?.name, !n.isEmpty { return n }
        if let n = bereiche?.areas.first(where: { $0.id == id })?.leaderName, !n.isEmpty { return n }
        return id
    }

    func mitarbeiterName(_ id: String) -> String? {
        for b in bereiche?.areas ?? [] { if let m = b.mitarbeiter.first(where: { $0.id == id }), !m.name.isEmpty { return m.name } }
        return nil
    }

    func agent(_ id: String?) -> OvAgent? { id.flatMap { i in agents.first { $0.id == i } } }

    func emoji(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "" }
        if let e = bereiche?.areas.first(where: { $0.leader == id })?.emoji, !e.isEmpty { return e }
        return agent(id)?.emoji ?? ""
    }
}
