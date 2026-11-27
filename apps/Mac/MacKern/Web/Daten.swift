import Foundation

private func text(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty ? nil : $0 } }
private func zahl(_ v: Any?) -> Double? {
    if v is NSNull { return nil }
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    return nil
}
private func wahr(_ v: Any?) -> Bool { (v as? Bool) ?? ((v as? NSNumber)?.boolValue ?? false) }

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

private extension String { var nilWennLeer: String? { isEmpty ? nil : self } }

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

struct OvDaten: Equatable {
    var jobs: [OvAuftrag] = []
    var agents: [OvAgent] = []
    var defaultAgent = Hauptagent.id
    var rows: [OvSitzung] = []
    var sitzungsStandard = OvSitzungsStandard()
    var geladen = false

    func label(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "" }
        if let n = agents.first(where: { $0.id == id })?.name, !n.isEmpty { return n }
        return id
    }

    func agent(_ id: String?) -> OvAgent? { id.flatMap { i in agents.first { $0.id == i } } }

    func emoji(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "" }
        return agent(id)?.emoji ?? ""
    }
}
