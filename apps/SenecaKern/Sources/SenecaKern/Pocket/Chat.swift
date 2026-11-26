import Foundation
import Combine

enum ZustellZustand: String, Codable, Sendable, Comparable {
    case wirdGesendet
    case angekommen
    case arbeitet
    case fertig
    case fehlgeschlagen

    private var rang: Int {
        switch self { case .wirdGesendet: 0; case .angekommen: 1; case .arbeitet: 2; case .fertig: 3; case .fehlgeschlagen: 4 }
    }
    static func < (a: ZustellZustand, b: ZustellZustand) -> Bool { a.rang < b.rang }
    var istOffen: Bool { self == .wirdGesendet || self == .angekommen || self == .arbeitet }
}

enum ZustellPlan {
    static let sendeTimeout: Double = 180
    static let maxAbbrueche = 3
    static let pausen: [Double] = [2, 5, 10, 20, 30]
    static let gesamtFrist: TimeInterval = 1800
    static let antwortFrist: TimeInterval = 3600
    static let pingIntervall: Double = 15
    static let abonnierPausen: [Double] = [2, 5, 10, 20, 30]

    static func abbruchGibtAuf(abbrueche: Int) -> Bool { abbrueche >= maxAbbrueche }

    enum Entscheidung: Equatable { case wiederholen(nach: Double), aufgeben }

    static func entscheide(fehler: Error, fehlversuche: Int, seit: TimeInterval) -> Entscheidung {
        if case SenecaError.refused(let r) = fehler {
            let code = r.code.uppercased()
            if !(code.contains("UNAVAILABLE") || code.contains("TIMEOUT")) { return .aufgeben }
        }
        if seit > gesamtFrist { return .aufgeben }
        return .wiederholen(nach: pausen[max(0, min(fehlversuche - 1, pausen.count - 1))])
    }
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, seneca, dritter }
    var id: String
    var role: Role
    var text: String
    var date: Date?
    var fromPhone = false
    var key: String?
    var zustand: ZustellZustand?
    var vermerk: String?
    var absender: String?

    init(id: String, role: Role, text: String, date: Date? = nil, fromPhone: Bool = false, key: String? = nil, zustand: ZustellZustand? = nil, vermerk: String? = nil,
         absender: String? = nil) {
        self.vermerk = vermerk
        self.absender = absender
        self.id = id; self.role = role; self.text = text; self.date = date; self.fromPhone = fromPhone
        self.key = key; self.zustand = zustand
    }

    var istLokal: Bool { id.hasPrefix("lokal-") }
}

struct ChatPartner: Identifiable, Equatable, Sendable {
    var id: String
    var kopfName: String
    var nominativ: String
    var dativ: String
    var platzhalter: String
    var festerSchluessel: String?

    static let seneca = ChatPartner(id: Hauptagent.id, kopfName: "Seneca", nominativ: "Seneca", dativ: "Seneca", platzhalter: "Frag Seneca etwas")
    static let alle: [ChatPartner] = [.seneca]
    static let demoPartner: [ChatPartner] = [.seneca,
        ChatPartner(id: "powerbi", kopfName: "Vodafone", nominativ: "Vodafone", dativ: "Vodafone", platzhalter: "Schreib Vodafone"),
        ChatPartner(id: "sundartha", kopfName: "Sundartha", nominativ: "Sundartha", dativ: "Sundartha", platzhalter: "Schreib Sundartha")]
    nonisolated(unsafe) static var agentNamen: [String: String] = [:]

    func sessionKey(main: String) -> String {
        if let festerSchluessel { return festerSchluessel }
        return id == Hauptagent.id ? main : "agent:\(id):main"
    }
    var ohneFrage: Bool { festerSchluessel == nil && id != Hauptagent.id }
    var satzName: String { nominativ.prefix(1).uppercased() + nominativ.dropFirst() }

    static func mit(id: String) -> ChatPartner? { alle.first { $0.id == id } }

    static func zu(sessionKey raw: String, agent: String? = nil, main: String, hilfsweise: Bool = false) -> ChatPartner? {
        let key = raw.hasPrefix("agent:") ? raw : "agent:\(agent ?? Hauptagent.id):\(raw)"
        if key == main || raw == main { return .seneca }
        for p in alle where p.id != Hauptagent.id && p.sessionKey(main: main) == key { return p }
        if key == Hauptagent.sitzung { return .seneca }
        guard hilfsweise else { return nil }
        return ChatPartner(id: raw, kopfName: "Seneca", nominativ: "Seneca", dativ: "Seneca", platzhalter: "Frag Seneca etwas", festerSchluessel: raw)
    }

    static func satzName(sessionKey key: String) -> String {
        let id = AreasLogic.agentID(of: key)
        if let n = agentNamen[id], !n.isEmpty, id != Hauptagent.id { return n }
        return "Seneca"
    }
}

struct ChatFill: Equatable, Sendable {
    var used: Int
    var window: Int
    var fresh = true
    var fraction: Double { window > 0 ? min(1, max(0, Double(used) / Double(window))) : 0 }
    var percent: Int { Int((fraction * 100).rounded()) }
}

struct ChatConversation: Identifiable, Equatable, Sendable {
    var key: String
    var agentId: String
    var title: String
    var lastMessage: String?
    var updatedAt: Date?
    var isRunning = false
    var isMain = false
    var fill: ChatFill?
    var id: String { key }
}

struct ChatLive: Equatable, Sendable {
    enum Phase: String, Sendable {
        case sending
        case queued
        case working
        case writing
    }
    var question: String
    var sessionKey: String
    var schluessel = ""
    var phase: Phase = .sending
    var text = ""
    var activity: String?
    var startedAt = Date()
    var partnerName: String { ChatPartner.satzName(sessionKey: sessionKey) }
    var waitingSentence: String? {
        guard phase == .queued else { return nil }
        let leiter = partnerName != "Seneca"
        return "\(partnerName) ist gerade noch mit etwas anderem beschäftigt. Deine \(leiter ? "Nachricht" : "Frage") ist als Nächstes dran."
    }
    var thinkingSentence: String { "\(partnerName) denkt nach …" }
}

enum ChatAdminState: Equatable, Sendable {
    case unknown
    case granted
    case notGranted
    case awaitingApproval(requestId: String?)

    var sentence: String? {
        switch self {
        case .awaitingApproval: return "Bitte gib die neuen Rechte für dieses iPhone einmal am Mac frei."
        case .notGranted: return "Leeren geht erst, wenn du dem iPhone am Mac die vollen Rechte gibst."
        case .unknown, .granted: return nil
        }
    }
}

enum ChatCommand: Equatable, Sendable {
    case reset
    case stop
    case fill

    static func parse(_ raw: String) -> ChatCommand? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.hasPrefix("/") else { return nil }
        let word = String(text.dropFirst().prefix { !$0.isWhitespace })
        switch word {
        case "clear", "reset", "new", "neu", "leeren", "neustart": return .reset
        case "stop", "abbrechen", "stopp": return .stop
        case "context", "status", "kontext", "fuellstand", "füllstand": return .fill
        default: return nil
        }
    }
}

enum ChatLogic {
    static let phoneMarker = "\n\n[Vom iPhone"

    static func stripPhoneHint(_ text: String) -> String {
        guard let r = text.range(of: phoneMarker) ?? text.range(of: "[Vom iPhone") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func text(of value: Any?) -> String {
        if let text = value as? String { return text }
        if let blocks = value as? [[String: Any]] {
            return blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        if let message = value as? [String: Any] { return text(of: message["content"] ?? message["text"]) }
        return ""
    }

    static func isBackgroundUserText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let prefixes = ["System:", "A scheduled reminder", "[Inter-session message]", SystemMarken.fortgesetzt,
                        "An async command completion", "Read HEARTBEAT", "[cron", "[Cron", "Exec completed", "Exec failed"]
        return prefixes.contains { t.hasPrefix($0) }
    }

    private static func gesetzt(_ value: Any?) -> Bool { value != nil && !(value is NSNull) }

    private static func feld(_ row: [String: Any], _ name: String) -> Any? {
        if let v = row[name], gesetzt(v) { return v }
        if let v = (row["__openclaw"] as? [String: Any])?[name], gesetzt(v) { return v }
        return nil
    }

    static func idempotencyKey(of row: [String: Any]) -> String { feld(row, "idempotencyKey") as? String ?? "" }

    static func runKey(_ row: [String: Any]) -> String? {
        var key = (row["__openclaw"] as? [String: Any])?["runId"] as? String ?? ""
        if key.isEmpty {
            key = idempotencyKey(of: row)
            if key.hasSuffix(":user") { key = String(key.dropLast(5)) }
            if key.hasPrefix("cli-assistant:") { key = String(key.dropFirst("cli-assistant:".count)) }
            if let r = key.range(of: ":message-tool:") { key = String(key[..<r.lowerBound]) }
        }
        key = key.trimmingCharacters(in: .whitespaces).lowercased()
        return key.isEmpty ? nil : key
    }

    static func rowID(_ index: Int, _ role: String, _ date: Date?, _ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        let ms = date.map { Int($0.timeIntervalSince1970 * 1000) } ?? -index
        return "z-\(ms)-\(role.prefix(1))-\(String(hash, radix: 16))"
    }

    static func normiert(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    static func gehoertZurFrage(_ message: [String: Any]?, idempotencyKey: String) -> Bool {
        guard let message, message["role"] as? String == "user" else { return false }
        let key = self.idempotencyKey(of: message)
        return !key.isEmpty && key.lowercased().hasPrefix(idempotencyKey.lowercased())
    }

    static func ownRunId(message: [String: Any]?, payloadRunId: String?, idempotencyKey: String) -> String? {
        guard gehoertZurFrage(message, idempotencyKey: idempotencyKey) else { return nil }
        return payloadRunId ?? ((message?["__openclaw"] as? [String: Any])?["runId"] as? String)
    }

    static func activeRunIds(_ result: [String: Any]) -> [String] {
        let info = result["sessionInfo"] as? [String: Any] ?? result
        return info["activeRunIds"] as? [String] ?? []
    }

    static func fill(_ row: [String: Any]) -> ChatFill? {
        func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? String).flatMap { Int($0) } }
        guard let used = int(row["totalTokens"]), let window = int(row["contextTokens"]), window > 0 else { return nil }
        return ChatFill(used: used, window: window, fresh: row["totalTokensFresh"] as? Bool ?? true)
    }

    static func cleanTitle(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { s in
            if s.value == 0xFE0F || s.value == 0x200D { return false }
            return !(s.properties.isEmojiPresentation || (s.properties.isEmoji && s.value > 0x2100))
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isBackgroundSession(_ key: String) -> Bool {
        let k = key.lowercased()
        return [":subagent:", ":cron:", ":acp:", ":heartbeat", "inter-session", ":hook:"].contains { k.contains($0) }
    }

    static func isSenecaMain(_ key: String) -> Bool {
        key == Hauptagent.id || (AreasLogic.agentID(of: key) == Hauptagent.id && key.hasSuffix(":main"))
    }

    static func kontextNeuParams(key: String, expectedSessionId: String? = nil) -> [String: Any] {
        let voll = key.hasPrefix("agent:") ? key : "agent:main:\(key)"
        var params: [String: Any] = ["key": voll, "agentId": AreasLogic.agentID(of: voll)]
        if let id = expectedSessionId, !id.isEmpty { params["expectedSessionId"] = id }
        return params
    }

    static func isTechnicalText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBackgroundUserText(t) || (t.hasPrefix("[") && !t.contains("](")) { return true }
        if ["NO_REPLY", "HEARTBEAT_OK", "no_reply"].contains(t) { return true }
        return ["sourceSession=", "isUser=", "HEARTBEAT", "heartbeat poll"].contains { t.contains($0) }
    }

    static func preview(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = stripPhoneHint(raw)
        if text.isEmpty || isTechnicalText(text) { return nil }
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("|") || l.hasPrefix("```") || l.allSatisfy({ "-=_*|: ".contains($0) }) { continue }
            while let first = l.first, "#>".contains(first) { l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces) }
            for bullet in ["- ", "* ", "+ ", "• "] where l.hasPrefix(bullet) { l = String(l.dropFirst(bullet.count)) }
            if isTechnicalText(l) { continue }
            lines.append(l)
        }
        var out = lines.joined(separator: " ")
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\([^)]*\\)") {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1")
        }
        for mark in ["**", "__", "`", "*", "~~"] { out = out.replacingOccurrences(of: mark, with: "") }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    static func conversations(_ result: [String: Any], agentNames: [String: String] = [:]) -> [ChatConversation] {
        let rows = result["sessions"] as? [[String: Any]] ?? []
        var out: [ChatConversation] = []
        for row in rows {
            guard let key = row["key"] as? String, !isBackgroundSession(key) else { continue }
            if row["archived"] as? Bool == true { continue }
            let agent = row["agentId"] as? String ?? AreasLogic.agentID(of: key)
            let candidates = [row["label"], row["displayName"], row["derivedTitle"]].compactMap { ($0 as? String).map(cleanTitle) }
                .filter { !isTechnicalText($0) }
            let rawTitles = [row["label"], row["derivedTitle"]].compactMap { $0 as? String }
            if !key.hasSuffix(":main"), !rawTitles.isEmpty, rawTitles.allSatisfy(isTechnicalText) { continue }
            if let kind = (row["kind"] as? String)?.lowercased(), ["heartbeat", "subagent", "cron", "inter-session", "system"].contains(kind) { continue }
            let fallback = key.hasSuffix(":main") ? (agentNames[agent] ?? agent.capitalized) : String(key.split(separator: ":").last ?? "")
                .replacingOccurrences(of: "-", with: " ").capitalized
            let title = candidates.first { !$0.isEmpty } ?? fallback
            let last = preview(row["lastMessagePreview"] as? String)
            let running = row["hasActiveRun"] as? Bool ?? (row["status"] as? String == "running")
            let date = SenecaPayloadParser.date(row["lastInteractionAt"] ?? row["updatedAt"])
            out.append(ChatConversation(key: key, agentId: agent, title: title, lastMessage: last,
                                        updatedAt: date, isRunning: running, isMain: row["isMain"] as? Bool ?? key.hasSuffix(":main"),
                                        fill: fill(row)))
        }
        return out.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    static func activity(tool rawName: String, args: Any? = nil, subject: String = "Seneca") -> String {
        let sentence = senecaActivity(tool: rawName, args: args)
        return subject == "Seneca" ? sentence : subject + sentence.dropFirst("Seneca".count)
    }

    private static func senecaActivity(tool rawName: String, args: Any? = nil) -> String {
        let name = rawName.lowercased()
        var detail = ""
        if let a = args as? [String: Any] {
            detail = a.values.compactMap { $0 as? String }.joined(separator: " ").lowercased()
        } else if let s = args as? String { detail = s.lowercased() }
        let all = name + " " + detail
        func has(_ words: String...) -> Bool { words.contains { all.contains($0) } }
        if has("tagesstand") { return "Seneca sieht sich deinen Tag an …" }
        if has("kalender", "icalbuddy", "calendar", "termin") { return "Seneca schaut in den Kalender …" }
        if has("entscheid", "inbox") { return "Seneca sieht die offenen Entscheidungen durch …" }
        if has("workboard", "cards", "todo", "aufgabe") { return "Seneca sieht bei den Aufgaben nach …" }
        if has("powerbi", "power bi", "bericht", "report", "dataset") { return "Seneca schaut in die Berichte …" }
        if has("mail") { return "Seneca sieht in die Mails …" }
        if has("memory", "gedaechtnis", "gedächtnis") { return "Seneca erinnert sich an Früheres …" }
        if has("web_search", "websearch", "web_fetch", "webfetch", "browser", "http") { return "Seneca sucht im Netz …" }
        if has("sessions_send", "sessions_spawn", "subagent", "agent_send") { return "Seneca fragt bei einem Mitarbeiter nach …" }
        if has("cron") { return "Seneca schaut in die Zeitpläne …" }
        if has("session_status") { return "Seneca schaut auf die Uhr …" }
        if ["read", "grep", "glob", "ls", "file_read"].contains(name) { return "Seneca liest nach …" }
        if ["write", "edit", "multiedit", "file_write"].contains(name) { return "Seneca schreibt etwas auf …" }
        return "Seneca arbeitet am Mac …"
    }
}

struct AskTracker: Equatable {
    enum Phase: Equatable { case sent, queued, running }
    enum Step: Equatable {
        case ignore
        case update
        case stopped
        case finished(String)
        case failed(String)
    }

    let key: String
    let sessionKey: String
    let question: String
    let sentAt: Date
    private(set) var phase: Phase = .sent
    private(set) var runIds: Set<String>
    private(set) var abortableRunIds: [String]
    private(set) var text = ""
    private(set) var activity: String?
    private(set) var lastEventAt: Date
    private(set) var sawDelta = false
    private(set) var sawTool = false
    private(set) var quittiert = false
    private(set) var versuche = 0
    private(set) var fehlversuche = 0
    private(set) var abbrueche = 0

    init(key: String, sessionKey: String, question: String, sentAt: Date) {
        self.key = key
        self.sessionKey = sessionKey
        self.question = question
        self.sentAt = sentAt
        runIds = [key.lowercased()]
        abortableRunIds = [key]
        lastEventAt = sentAt
    }

    var live: ChatLive {
        let p: ChatLive.Phase
        switch phase {
        case .queued: p = .queued
        case .sent: p = .sending
        case .running: p = text.isEmpty ? .working : .writing
        }
        return ChatLive(question: question, sessionKey: sessionKey, schluessel: key, phase: p, text: text, activity: activity, startedAt: sentAt)
    }

    var zustand: ZustellZustand {
        if phase == .running { return .arbeitet }
        return quittiert || phase == .queued ? .angekommen : .wirdGesendet
    }

    mutating func versuchBeginnt() { versuche += 1 }
    mutating func versuchFehlgeschlagen() { fehlversuche += 1 }
    mutating func abbruchNachSenden() { abbrueche += 1 }
    mutating func gatewayKenntFrage() { quittiert = true }

    private mutating func nimm(_ run: String) {
        guard !run.isEmpty, runIds.insert(run.lowercased()).inserted else { return }
        abortableRunIds.append(run)
    }

    mutating func acknowledged(runId: String?) {
        quittiert = true
        if let runId { nimm(runId) }
    }

    mutating func markQueued() {
        phase = .queued
        text = ""
        activity = nil
    }

    mutating func claim(run: String, bisher: String? = nil) {
        quittiert = true
        let neu = !runIds.contains(run.lowercased())
        nimm(run)
        if neu, let bisher, !bisher.isEmpty { text = bisher; phase = .running }
    }

    mutating func handle(event: String, payload: [String: Any], now: Date = Date()) -> Step {
        guard let run = payload["runId"] as? String, runIds.contains(run.lowercased()) else { return .ignore }
        lastEventAt = now
        if event == "chat" {
            let message = ChatLogic.text(of: payload["message"])
            switch payload["state"] as? String ?? "" {
            case "delta":
                let delta = payload["deltaText"] as? String
                if payload["replace"] as? Bool == true { text = message.isEmpty ? (delta ?? "") : message }
                else if let delta { text += delta }
                else if !message.isEmpty { text = message }
                phase = .running
                sawDelta = true
                return .update
            case "final":
                var full = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if full.isEmpty { full = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                if !full.isEmpty { return .finished(full) }
                markQueued()
                return .update
            case "aborted":
                let partial = (message.isEmpty ? text : message).trimmingCharacters(in: .whitespacesAndNewlines)
                return partial.isEmpty ? .stopped : .finished(partial)
            case "error":
                return .failed(payload["errorMessage"] as? String ?? "Seneca konnte die Frage nicht beantworten.")
            default:
                return .ignore
            }
        }
        let stream = payload["stream"] as? String ?? "tool"
        let data = payload["data"] as? [String: Any] ?? [:]
        if stream == "tool", (data["phase"] as? String ?? "start") == "start", let name = data["name"] as? String {
            activity = ChatLogic.activity(tool: name, args: data["args"], subject: ChatPartner.satzName(sessionKey: sessionKey))
            phase = .running
            sawTool = true
            return .update
        }
        if stream == "lifecycle" || stream == "item" || stream == "thinking" {
            if phase != .running { phase = .running; return .update }
        }
        return .ignore
    }
}

@MainActor
final class ChatService: ObservableObject {
    @Published private(set) var partner: ChatPartner = .seneca
    @Published private(set) var lives: [String: ChatLive] = [:]
    @Published private(set) var neu: Set<String> = []
    @Published private(set) var alleLives: [String: [ChatLive]] = [:]
    @Published private(set) var live: ChatLive?
    @Published private(set) var adminState: ChatAdminState = .unknown
    @Published private(set) var grantedRechte: [String] = []
    @Published private(set) var problem: String?
    @Published private(set) var fuellstand: [String: ChatFill] = [:]

    let speicher: ChatSpeicher

    private(set) var mainKey = Hauptagent.sitzung

    private var zuletztGesetzteLives: [ChatLive] = []
    private var zurueckgehalteneLives: [ChatLive]?
    private var livesVeroeffentlicht: Date?
    private var drosselTask: Task<Void, Never>?

    var currentKey: String { partner.sessionKey(main: mainKey) }
    var messages: [ChatMessage] { speicher.nachrichten(currentKey) }
    var fill: ChatFill? { fuellstand[currentKey] }
    var canReset: Bool { grantedRechte.contains("admin") }
    var isMainConversation: Bool { ChatLogic.isSenecaMain(currentKey) }

    var isShowing = false {
        didSet { if isShowing { neu.remove(partner.id); speicher.oeffne(currentKey) } }
    }

    weak var store: SenecaStore? {
        didSet {
            speicher.rufe = { [weak self] fn, params, frist in
                guard let store = self?.store else { throw SenecaError.offline }
                return try await store.rufe(fn, params: params, timeout: frist)
            }
        }
    }
    private(set) var demo = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, speicher: URL? = ChatService.standardSpeicher) {
        self.defaults = defaults
        self.speicher = ChatSpeicher(ordner: speicher)
        if MacPfade.profil.echteDaten, let ordner = MacPfade.datenOrdner {
            self.speicher.zaehler = VerlaufsZaehler(url: ordner.appendingPathComponent(VerlaufsZaehler.dateiname))
        }
        if let saved = defaults.stringArray(forKey: Self.scopesKey) { grantedRechte = saved }
        if let id = defaults.string(forKey: Self.partnerKey), let saved = ChatPartner.mit(id: id) { partner = saved }
        self.speicher.nachgeholt = { [weak self] key, antwort in
            guard let self else { return }
            if let info = antwort["sessionInfo"] as? [String: Any], let f = ChatLogic.fill(info), self.fuellstand[key] != f { self.fuellstand[key] = f }
            self.store?.pruefeFragen(key)
        }
    }
    static let scopesKey = "seneca-pocket.granted-rechte"
    static let partnerKey = "seneca-pocket.chat.partner"
    static let entwurfKey = "seneca-pocket.entwurf."
    nonisolated static var standardSpeicher: URL? { MacPfade.datenOrdner }

    func waehle(_ neuer: ChatPartner) {
        if partner != neuer { partner = neuer }
        neu.remove(neuer.id)
        synchronisiereLive()
        if neuer.festerSchluessel == nil { defaults.set(neuer.id, forKey: Self.partnerKey) }
        guard !demo else { return }
        let key = neuer.sessionKey(main: mainKey)
        if isShowing { speicher.oeffne(key) }
        Task { [weak self] in await self?.store?.subscribeSession(key) }
    }

    func entwurf(fuer p: ChatPartner) -> String { defaults.string(forKey: Self.entwurfKey + p.id) ?? "" }

    func setzeEntwurf(_ text: String, fuer p: ChatPartner) {
        if text.isEmpty { defaults.removeObject(forKey: Self.entwurfKey + p.id) } else { defaults.set(text, forKey: Self.entwurfKey + p.id) }
    }

    var partnerSitzungen: [String] { (ChatPartner.alle + (partner.id == Hauptagent.id ? [] : [partner])).map { $0.sessionKey(main: mainKey) } }

    func loadHistory() async { await speicher.nachholen(currentKey, grund: .hand) }

    func refreshFill(_ p: ChatPartner? = nil) async {
        guard !demo, let store else { return }
        let key = (p ?? partner).sessionKey(main: mainKey)
        if let result = try? await store.rufe("sessions.describe", params: ["key": key]) {
            let row = result["session"] as? [String: Any] ?? result
            if let f = ChatLogic.fill(row) { fuellstand[key] = f }
        }
    }

    private var anhangMerker: [String: [ChatAnhang]] = [:]

    func send(_ text: String, an p: ChatPartner, demoAntwort: String? = nil, anhaenge: [ChatAnhang] = []) async throws -> String {
        var text = text, anhaenge = anhaenge
        if anhaenge.isEmpty {
            let z = ChatAnhang.zerlege(text)
            if !z.namen.isEmpty { anhaenge = anhangMerker[ChatLogic.normiert(text)] ?? []; text = z.text }
        }
        if anhaenge.isEmpty, let command = ChatCommand.parse(text) { return await perform(command, fuer: p) }
        guard let store else { throw SenecaError.offline }
        var question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.isEmpty, !anhaenge.isEmpty { question = ChatAnhang.leerText }
        let key = p.sessionKey(main: mainKey)
        if let problem = ChatAnhang.problem(anhaenge: anhaenge, text: question) { throw SenecaError.message(problem) }
        let nutzlast = try anhaenge.map { try $0.json() }
        let zeile = ChatAnhang.faden(text: question, anhaenge: anhaenge)
        if !anhaenge.isEmpty { anhangMerker[ChatLogic.normiert(zeile)] = anhaenge }
        let schluessel = speicher.legeFrageAn(sitzung: key, text: zeile)
        let answer: String
        do {
            #if DEBUG
            if demo, ProcessInfo.processInfo.environment["SENECA_DEMO_CHAT_FEHLER"] == "antwort" {
                try await Task.sleep(for: .milliseconds(1200))
                throw SenecaError.nichtGesendet
            }
            #endif
            if demo {
                speicher.setzeZustand(sitzung: key, schluessel: schluessel, .angekommen)
                answer = await simulateDemoReply(demoAntwort ?? ChatDemo.answer(to: question, partner: p), question: question, sessionKey: key)
                speicher.nimmStromEnde(sitzung: key, lauf: schluessel, text: answer, frage: schluessel)
            } else {
                answer = try await store.ask(question, sessionKey: key, idempotencyKey: schluessel, anhaenge: nutzlast)
            }
        } catch {
            speicher.setzeZustand(sitzung: key, schluessel: schluessel, Self.zustand(nach: error, bisher: speicher.zustand(sitzung: key, schluessel: schluessel)))
            throw error
        }
        speicher.setzeZustand(sitzung: key, schluessel: schluessel, .fertig)
        if p.id != partner.id || !isShowing { neu.insert(p.id) }
        return answer
    }

    static func zustand(nach fehler: Error, bisher: ZustellZustand?) -> ZustellZustand {
        switch fehler {
        case SenecaError.stopped: return .fertig
        case SenecaError.nichtGesendet, SenecaError.refused, SenecaError.offline: return .fehlgeschlagen
        default: return bisher.map { $0 == .wirdGesendet ? .fehlgeschlagen : $0 } ?? .fehlgeschlagen
        }
    }

    func send(_ text: String, sessionKey: String? = nil) async throws -> String {
        let p = sessionKey.flatMap { ChatPartner.zu(sessionKey: $0, main: mainKey, hilfsweise: true) } ?? partner
        return try await send(text, an: p)
    }

    func configure(mainKey newKey: String) {
        guard !demo, newKey != mainKey else { return }
        mainKey = newKey
        if partner.festerSchluessel != nil { partner = .seneca }
        synchronisiereLive()
    }

    func perform(_ command: ChatCommand, fuer p: ChatPartner? = nil) async -> String {
        let p = p ?? partner
        let key = p.sessionKey(main: mainKey)
        switch command {
        case .stop:
            guard lives[key] != nil else { return "Gerade läuft *nichts*, das ich anhalten könnte." }
            await stop(p)
            return "Ich habe *aufgehört*."
        case .fill:
            if !demo { await refreshFill(p) }
            guard let fill = fuellstand[key] else { return "Wie voll das Gespräch ist, weiß ich gerade *nicht*." }
            return "Das Gespräch ist zu *\(fill.percent) %* gefüllt.\n\(fill.used.formatted(.number.locale(Locale(identifier: "de_DE")))) von \(fill.window.formatted(.number.locale(Locale(identifier: "de_DE")))) Tokens."
        case .reset:
            guard await reset(p) else { return "Leeren hat gerade *nicht* geklappt.\n" + (problem ?? "") }
            return "Das Gespräch ist *geleert*.\n\(p.satzName) beginnt neu, der alte Verlauf bleibt im Archiv."
        }
    }

    func stop(_ p: ChatPartner? = nil) async {
        if demo { demoStop = true; return }
        guard let store else { return }
        await store.abortAsk(sessionKey: (p ?? partner).sessionKey(main: mainKey))
    }

    private(set) var resets = 0

    @discardableResult
    func reset(_ p: ChatPartner? = nil) async -> Bool {
        let p = p ?? partner
        let key = p.sessionKey(main: mainKey)
        if demo {
            speicher.leere(key)
            fuellstand[key] = ChatFill(used: 0, window: fuellstand[key]?.window ?? 1_000_000)
            resets += 1
            return true
        }
        guard let store else { problem = "Der Mac ist gerade nicht erreichbar."; return false }
        var sessionId: String?
        if let described = try? await store.rufe("sessions.describe", params: ["key": key]) {
            sessionId = ((described["session"] as? [String: Any]) ?? described)["sessionId"] as? String
        }
        let params = ChatLogic.kontextNeuParams(key: key, expectedSessionId: sessionId)
        do {
            do {
                _ = try await store.rufe("seneca.kontext.neu", params: params)
            } catch where canReset {
                var direkt = params
                direkt["reason"] = "new"
                _ = try await store.rufe("sessions.reset", params: direkt)
            }
            speicher.leere(key)
            problem = nil
            resets += 1
            await speicher.nachholen(key, grund: .hand)
            await refreshFill(p)
            return true
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Leeren hat nicht geklappt."
            return false
        }
    }

    func setLives(_ values: [ChatLive]) {
        switch StromDrossel.entscheide(alt: zuletztGesetzteLives, neu: values, zuletzt: livesVeroeffentlicht) {
        case .sofort:
            drosselTask?.cancel(); drosselTask = nil
            veroeffentliche(values)
        case .halten(let in_):
            zurueckgehalteneLives = values
            guard drosselTask == nil else { return }
            drosselTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(in_))
                guard let self, !Task.isCancelled else { return }
                self.drosselTask = nil
                if let offen = self.zurueckgehalteneLives { self.zurueckgehalteneLives = nil; self.veroeffentliche(offen) }
            }
        }
    }

    private func veroeffentliche(_ values: [ChatLive]) {
        zuletztGesetzteLives = values
        livesVeroeffentlicht = Date()
        zurueckgehalteneLives = nil
        var neueLives: [String: ChatLive] = [:]
        var alle: [String: [ChatLive]] = [:]
        for value in values.sorted(by: { $0.startedAt < $1.startedAt }) {
            let aktiv = value.phase == .working || value.phase == .writing
            if aktiv || neueLives[value.sessionKey].map({ $0.phase != .working && $0.phase != .writing }) ?? true { neueLives[value.sessionKey] = value }
            alle[value.sessionKey, default: []].append(value)
        }
        if lives != neueLives { lives = neueLives }
        if alleLives != alle { alleLives = alle }
        synchronisiereLive()
    }

    private func synchronisiereLive() {
        let value = lives[currentKey]
        if live != value { live = value }
    }

    func answered(sessionKey: String) {
        guard !demo, let p = ChatPartner.zu(sessionKey: sessionKey, main: mainKey, hilfsweise: true) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.refreshFill(p)
        }
    }

    func setAccess(rechte: [String]?, admin: ChatAdminState) {
        if let rechte {
            grantedRechte = rechte
            defaults.set(rechte, forKey: Self.scopesKey)
        }
        adminState = admin
    }

    func neueZeile(_ key: String, _ zeile: [String: Any]) {
        guard !demo, zeile["role"] as? String == "assistant", ["stop", "end_turn"].contains((zeile["stopReason"] as? String ?? "").lowercased()),
              let p = ChatPartner.zu(sessionKey: key, main: mainKey), p.id != partner.id || !isShowing else { return }
        let t = ChatLogic.text(of: zeile["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || ChatLogic.isTechnicalText(t) { return }
        neu.insert(p.id)
    }

    private var demoStop = false
    var demoPace = "normal"
    var demoQueued = false

    func loadDemo(now: Date, admin: String = "1", partnerId: String? = nil, art: String? = nil, neuIds: String? = nil) {
        demo = true
        let env = ProcessInfo.processInfo.environment
        mainKey = Hauptagent.sitzung
        for p in ChatPartner.demoPartner {
            let key = p.sessionKey(main: mainKey)
            speicher.ersetze(key, zeilen: ChatDemo.zeilen(ChatDemo.verlauf(p, now: now, art: art ?? env["SENECA_DEMO_FADEN"])))
            fuellstand[key] = ChatDemo.fill(p)
        }
        func demoMit(_ id: String) -> ChatPartner? { ChatPartner.demoPartner.first { $0.id == id } }
        partner = demoMit(partnerId ?? env["SENECA_DEMO_PARTNER"] ?? Hauptagent.id) ?? .seneca
        neu = Set((neuIds ?? env["SENECA_DEMO_NEU"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { demoMit($0) != nil && $0 != partner.id })
        lives = [:]
        synchronisiereLive()
        switch admin {
        case "0": grantedRechte = ["lesen", "schreiben"]; adminState = .notGranted
        case "warten": grantedRechte = ["lesen", "schreiben"]; adminState = .awaitingApproval(requestId: "demo-anfrage")
        default: grantedRechte = SenecaStore.alleRechte; adminState = .granted
        }
    }

    private func setzeDemoLive(_ value: ChatLive?, sessionKey: String) {
        if let value { if lives[sessionKey] != value { lives[sessionKey] = value } } else { lives[sessionKey] = nil }
        alleLives[sessionKey] = value.map { [$0] } ?? []
        synchronisiereLive()
    }

    func simulateDemoReply(_ answer: String, question: String = "", sessionKey: String? = nil) async -> String {
        demoStop = false
        let slow = demoPace == "langsam"
        guard demoPace != "aus" else {
            try? await Task.sleep(for: .milliseconds(1400))
            return answer
        }
        let key = sessionKey ?? currentKey
        var t = AskTracker(key: "demo-\(UUID().uuidString)", sessionKey: key, question: question, sentAt: Date())
        setzeDemoLive(t.live, sessionKey: key)
        if demoQueued {
            t.markQueued()
            setzeDemoLive(t.live, sessionKey: key)
            try? await Task.sleep(for: .milliseconds(slow ? 2500 : 600))
        }
        let tool: [String: Any]
        switch AreasLogic.agentID(of: key) {
        case "powerbi": tool = ["phase": "start", "name": "Bash", "args": ["command": "powerbi report refresh"]]
        case "sundartha": tool = ["phase": "start", "name": "Read", "args": ["path": "newsletter/oktober.md"]]
        default: tool = ["phase": "start", "name": "Bash", "args": ["command": "icalBuddy eventsToday+1"]]
        }
        _ = t.handle(event: "session.tool", payload: ["runId": t.key, "stream": "tool", "data": tool])
        setzeDemoLive(t.live, sessionKey: key)
        try? await Task.sleep(for: .milliseconds(slow ? 2200 : 450))
        let words = answer.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let budget = slow ? 4000.0 : 800.0
        let step = max(12, min(120, budget / Double(max(1, words.count))))
        for (i, word) in words.enumerated() {
            if demoStop { break }
            _ = t.handle(event: "chat", payload: ["runId": t.key, "state": "delta", "deltaText": (i == 0 ? "" : " ") + word])
            setzeDemoLive(t.live, sessionKey: key)
            try? await Task.sleep(for: .milliseconds(Int(step)))
        }
        try? await Task.sleep(for: .milliseconds(slow ? 600 : 150))
        let text = demoStop ? t.live.text : answer
        setzeDemoLive(nil, sessionKey: key)
        return text
    }
}

enum ChatDemo {
    static func zeilen(_ nachrichten: [ChatMessage]) -> [[String: Any]] {
        var lauf = ""
        return nachrichten.enumerated().map { i, m in
            let ms = (m.date ?? Date(timeIntervalSince1970: Double(i))).timeIntervalSince1970 * 1000
            if m.role == .user {
                lauf = m.id
                return ["role": "user", "content": m.text, "timestamp": ms, "idempotencyKey": m.id + ":user",
                        "__openclaw": ["id": m.id, "senderId": "gateway-owner", "recordTimestampMs": ms, "seq": i] as [String: Any]]
            }
            return ["role": "assistant", "content": [["type": "text", "text": m.text] as [String: Any]], "timestamp": ms, "stopReason": "stop",
                    "__openclaw": ["id": m.id, "runId": lauf, "recordTimestampMs": ms, "seq": i] as [String: Any]]
        }
    }

    static func conversations(now: Date) -> [ChatConversation] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            ChatConversation(key: Hauptagent.sitzung, agentId: Hauptagent.id, title: "Seneca", lastMessage: "Gern, dann erinnere ich dich um halb sechs an den Anruf.",
                             updatedAt: ago(4), isRunning: false, isMain: true, fill: ChatFill(used: 200_000, window: 1_000_000)),
            ChatConversation(key: "agent:sundartha:main", agentId: "sundartha", title: "Sundartha", lastMessage: "Der Newsletter-Entwurf für Oktober liegt zur Durchsicht bereit.",
                             updatedAt: ago(35), isRunning: true, isMain: true, fill: ChatFill(used: 116_276, window: 258_400)),
            ChatConversation(key: "agent:powerbi:main", agentId: "powerbi", title: "Vodafone", lastMessage: "Power BI wartet weiter auf deine einmalige Anmeldung.",
                             updatedAt: ago(190), isRunning: false, isMain: true, fill: ChatFill(used: 61_000, window: 258_400)),
            ChatConversation(key: "agent:main:reise-mailand", agentId: Hauptagent.id, title: "Reise nach Mailand", lastMessage: "Der Zug am Montag um 7:10 Uhr ist gebucht.",
                             updatedAt: ago(60 * 26), fill: ChatFill(used: 34_000, window: 1_000_000)),
            ChatConversation(key: "agent:main:steuer-2025", agentId: Hauptagent.id, title: "Steuererklärung 2025", lastMessage: "Für Oktober fehlen noch zwei Belege.",
                             updatedAt: ago(60 * 52), fill: ChatFill(used: 52_000, window: 1_000_000)),
            ChatConversation(key: "agent:main:geschenk-mama", agentId: Hauptagent.id, title: "Geschenk für Mama", lastMessage: "Drei Ideen stehen jetzt in deiner Notiz.",
                             updatedAt: ago(60 * 24 * 4), fill: ChatFill(used: 12_000, window: 1_000_000)),
        ]
    }

    static func fill(_ p: ChatPartner) -> ChatFill {
        switch p.id {
        case "powerbi": return ChatFill(used: 61_000, window: 258_400)
        case "sundartha": return ChatFill(used: 116_276, window: 258_400)
        default: return ChatFill(used: 200_000, window: 1_000_000)
        }
    }

    static func verlauf(_ p: ChatPartner, now: Date, art: String? = nil) -> [ChatMessage] {
        switch p.id {
        case "powerbi": return vodafone(now: now)
        case "sundartha": return sundartha(now: now)
        default:
            if art == "lang" { return langerFaden(now: now) }
            var out = history(for: Hauptagent.sitzung, now: now)
            if art == "langeantwort" { out += langeAntwort(now: now) }
            return out
        }
    }

    private static func zeit(_ now: Date, tage: Int, _ h: Int, _ m: Int) -> Date {
        let cal = Calendar.current
        let tag = cal.date(byAdding: .day, value: -tage, to: cal.startOfDay(for: now)) ?? now
        let d = cal.date(bySettingHour: h, minute: m, second: 0, of: tag) ?? tag
        return min(d, now.addingTimeInterval(-90))
    }

    private static func wechsel(_ id: String, _ frage: String, _ antwort: String, um d: Date, phone: Bool = true) -> [ChatMessage] {
        [ChatMessage(id: "demo-\(id)-f", role: .user, text: frage, date: d, fromPhone: phone),
         ChatMessage(id: "demo-\(id)-a", role: .seneca, text: antwort, date: d.addingTimeInterval(14))]
    }

    private static func vodafone(now: Date) -> [ChatMessage] {
        func bericht(_ id: String, _ text: String, _ d: Date) -> ChatMessage { ChatMessage(id: "demo-powerbi-\(id)", role: .seneca, text: text, date: d) }
        return [
            bericht("b1", "Guten Morgen. Der Tagesbericht zu den Vodafone-Zahlen liegt bereit.\n\nDie Aktivierungen lagen gestern bei 1.284 und damit leicht über dem Wochenschnitt von 1.240. Auffällig ist der Shop in Köln-Ehrenfeld mit gut 18 Prozent mehr als sonst, der Standort am Flughafen Düsseldorf liegt dagegen unter dem Schnitt.\n\nDie Zahlen stammen noch aus der Datei vom Vorabend. Power BI selbst wartet weiter auf deine einmalige Anmeldung, danach lese ich die Berichte direkt und der Bericht kommt eine Stunde früher.", zeit(now, tage: 1, 7, 35)),
            bericht("b2", "Der Abendbericht ist da, kurz zusammengefasst.\n\n- Aktivierungen heute bis 18 Uhr: 1.197\n- Beste Region: Rheinland, schwächste: Ostwestfalen\n- Offene Rückfragen: keine\n\nMorgen früh folgt wie gewohnt der Tagesbericht.", zeit(now, tage: 1, 18, 10)),
            bericht("b3", "Guten Morgen. Gestern endeten die Aktivierungen bei 1.351, das ist der beste Wert dieser Woche.\n\nDer Zuwachs kommt fast vollständig aus dem Rheinland. Ostwestfalen hat gegenüber dem Vortag aufgeholt, liegt aber weiter unter dem Schnitt.\n\nFür heute habe ich nichts, was deine Entscheidung braucht.", zeit(now, tage: 0, 7, 40)),
        ]
    }

    private static func sundartha(now: Date) -> [ChatMessage] {
        wechsel("sundartha-1", "Wie weit ist der Newsletter für Oktober?",
                "Der Entwurf für den Oktober-Newsletter steht, und ich bin mit dem Aufbau ziemlich zufrieden.\n\nEr beginnt mit der Geschichte der Woche: Eine Kundin aus Hamburg hat uns geschrieben, wie sie das Programm in ihren Morgen eingebaut hat. Das ist persönlich, kurz und lädt zum Weiterlesen ein. Danach folgen drei kurze Abschnitte: die neue Preisseite, der Termin für das Webinar am 22. Oktober und die Atemübung der Woche.\n\nZwei Dinge brauche ich noch von dir:\n\n- Ob das Foto der Kundin verwendet werden darf. Ich habe ihr gestern geschrieben, die Antwort steht noch aus.\n- Ob der Betreff persönlicher klingen soll. Mein Vorschlag lautet „Ein Morgen, der anders beginnt“, die sachliche Variante wäre „Sundartha im Oktober“.\n\nWenn beides geklärt ist, kann der Newsletter am Donnerstag um 10 Uhr rausgehen. Davor teste ich den Versand an die interne Liste und prüfe die Links auf dem iPhone und im Mailprogramm.",
                um: zeit(now, tage: 1, 16, 20))
        + wechsel("sundartha-2", "Der Betreff gefällt mir, nimm den persönlichen. Das Foto klären wir morgen.",
                  "Gut, dann nehme ich „Ein Morgen, der anders beginnt“.\n\nDen Versand lasse ich vorerst auf Donnerstag um 10 Uhr stehen. Sagt die Kundin bis Mittwoch nicht zu, nehme ich das Titelbild aus unserem eigenen Archiv, damit nichts hängen bleibt.",
                  um: zeit(now, tage: 0, 9, 5))
    }

    private static func langeAntwort(now: Date) -> [ChatMessage] {
        wechsel("lang-1", "Fass mir bitte zusammen, was diese Woche bei Sundartha und Vodafone ansteht.",
                "Die Woche ist ruhig geplant, aber an zwei Stellen brauche ich dich.\n\n**Sundartha.** Der Oktober-Newsletter geht am Donnerstag um 10 Uhr raus. Der Betreff steht, offen ist nur das Foto der Kundin aus Hamburg. Parallel baut der Website-Spezialist die Widerrufs-Einwilligung in den Checkout ein; das ist heute beauftragt und sollte bis Mittwoch fertig sein. Danach prüft Sundartha die Preisseite noch einmal auf dem Handy.\n\n**Vodafone.** Die Tagesberichte laufen weiter aus der Datei vom Vorabend. Sobald du dich einmal bei Power BI anmeldest, liest Vodafone die Berichte direkt, und sie kommen eine Stunde früher. Die Zahlen sind gut: Die Aktivierungen liegen seit Montag über dem Wochenschnitt, vor allem im Rheinland.\n\n**Von dir gebraucht:**\n\n- Das Foto der Kundin für den Newsletter freigeben oder verwerfen (bis Mittwoch)\n- Die einmalige Anmeldung bei Power BI (ungefähr zwei Minuten am Mac)\n\nAlles andere läuft ohne dich. Wenn du willst, erinnere ich dich morgen früh an beide Punkte, dann sind sie erledigt, bevor der Tag voll wird.",
                um: now.addingTimeInterval(-6 * 60))
    }

    private static func langerFaden(now: Date) -> [ChatMessage] {
        let paare: [(String, String)] = [
            ("Was steht heute an?", "Zwei Termine und ein Anruf, nichts Dringendes.\n10:30 Abstimmung Website\n17:30 Anruf mit Jonas"),
            ("Verschieb die Abstimmung auf elf.", "Erledigt, die Abstimmung beginnt jetzt um 11 Uhr."),
            ("Hat Sundartha etwas gemeldet?", "Ja, zwei neue Entscheidungen liegen in deiner Inbox. Die erste betrifft die Speicherfrist bei ElevenLabs, die zweite die Widerrufs-Einwilligung im Checkout."),
            ("Was empfiehlst du bei der Einwilligung?", "Ich würde sie sofort ergänzen. Ohne sie ist jeder digitale Kauf zwei Wochen lang widerrufbar, das Risiko ist größer als der Aufwand."),
            ("Gut, mach das so.", "Ist beauftragt. Der Website-Spezialist baut es heute noch ein."),
            ("Wie lange brauche ich heute noch für die To-dos?", "Etwa anderthalb Stunden, wenn nichts dazwischenkommt. Der längste Punkt ist die Webhook-Kette."),
            ("Erinnere mich vor dem Anruf.", "Mache ich, um 17:15 melde ich mich."),
            ("Wie wird das Wetter morgen?", "Morgen bleibt es trocken, bis zu 14 Grad, am Nachmittag kommt etwas Sonne raus."),
            ("Trag bitte den Zahnarzt am Freitag um 9 Uhr ein.", "Steht im Kalender, Freitag um 9 Uhr. Ich erinnere dich am Abend vorher."),
            ("Hat Vodafone geschrieben?", "Ja, der Tagesbericht ist da. Die Aktivierungen liegen über dem Wochenschnitt, vor allem im Rheinland."),
            ("Was war die letzte Mail von Jonas?", "Er fragt, ob der Anruf auch eine halbe Stunde später gehen würde. Eine Antwort habe ich nicht verschickt."),
            ("Sag ja, aber nicht später als 18 Uhr.", "Habe ich ihm so geschrieben. Der Anruf ist jetzt für 18 Uhr eingetragen."),
            ("Danke dir.", "Gern. Ich melde mich vor dem Anruf."),
            ("Was habe ich morgen früh vor?", "Um 9:30 Uhr der Steuerberater, davor ist der Morgen frei."),
            ("Schlag mir ein Abendessen vor.", "Wie wäre eine Gemüsepfanne mit Ofenkartoffeln? Du hast alles im Haus, außer Feta; den müsstest du mitnehmen."),
        ]
        var out: [ChatMessage] = []
        let proTag = [7, 8, 8, 7]
        let cal = Calendar.current
        var n = 0
        for (i, anzahl) in proTag.enumerated() {
            let tage = 3 - i
            for k in 0..<anzahl {
                let (f, a) = paare[n % paare.count]
                let d: Date
                if tage == 0 {
                    let start = cal.startOfDay(for: now)
                    let von = now.timeIntervalSince(start) > 8 * 3600 ? start.addingTimeInterval(6 * 3600) : start
                    d = von.addingTimeInterval(max(60, now.timeIntervalSince(von) - 300) * Double(k + 1) / Double(anzahl + 1))
                } else {
                    d = zeit(now, tage: tage, 8 + k * 2, (n * 7) % 50)
                }
                out += wechsel("tag-\(n)", f, a, um: d, phone: n % 3 != 1)
                n += 1
            }
        }
        return out
    }

    static func history(for key: String, now: Date) -> [ChatMessage] {
        let pairs: [(String, String)]
        if key == "agent:powerbi:main" { return vodafone(now: now) }
        if key == "agent:sundartha:main" { return sundartha(now: now) }
        if key == Hauptagent.sitzung {
            pairs = [
                ("Guten Morgen, was steht heute an?", "Ein ruhiger Tag, vormittags die Abstimmung und abends ein *Anruf*.\n10:30 Abstimmung Website, heute\n17:30 Anruf mit Jonas, heute"),
                ("Verschieb die Abstimmung bitte auf elf.", "Erledigt, die Abstimmung beginnt jetzt um *11 Uhr*.\n11:00 Abstimmung Website, heute"),
                ("Hat Sundartha heute Nacht etwas gemeldet?", "Ja, zwei neue *Entscheidungen* liegen in deiner Inbox.\n- E-8 Speicherfrist bei ElevenLabs\n- E-9 Widerrufs-Einwilligung im Checkout"),
                ("Was empfiehlst du bei E-9?", "Ich würde die Einwilligung *sofort* ergänzen.\nOhne sie ist jeder digitale Kauf zwei Wochen lang widerrufbar, das Risiko ist größer als der Aufwand."),
                ("Gut, dann soll der Website-Spezialist das machen.", "Ist beauftragt, die Karte liegt beim *Website*-Spezialisten.\n- Widerrufs-Einwilligung im Checkout ergänzen"),
                ("Wie lange brauche ich heute noch für die To-dos?", "Etwa *anderthalb* Stunden, wenn nichts dazwischenkommt.\nDrei offene Punkte, der längste ist die Webhook-Kette."),
                ("Erinnere mich vor dem Anruf mit Jonas.", "Mache ich, um *17:15* melde ich mich.\n17:15 Erinnerung Anruf Jonas, heute"),
                ("Danke dir.", "Gern, dann erinnere ich dich um halb sechs an den *Anruf*."),
            ]
        } else {
            pairs = [
                ("Wie ist der Stand?", "Alles läuft nach Plan, nichts braucht dich *heute*."),
                ("Gut, danke.", "Gern, ich melde mich, wenn sich etwas *ändert*."),
            ]
        }
        var out: [ChatMessage] = []
        for (i, (q, a)) in pairs.enumerated() {
            let base = now.addingTimeInterval(-Double(pairs.count - i) * 38 * 60)
            out.append(ChatMessage(id: "demo-\(key)-f\(i)", role: .user, text: q, date: base, fromPhone: i % 3 != 1))
            out.append(ChatMessage(id: "demo-\(key)-a\(i)", role: .seneca, text: a, date: base.addingTimeInterval(14)))
        }
        return out
    }

    static func answer(to question: String, partner: ChatPartner = .seneca) -> String {
        let q = question.lowercased()
        switch partner.id {
        case "powerbi": return "Verstanden, ich schaue in die Berichte.\n\nSobald ich die aktuellen Zahlen habe, schreibe ich dir kurz, was sich gegenüber gestern geändert hat."
        case "sundartha": return "Das übernehme ich.\n\nIch melde mich, sobald der Entwurf zur Durchsicht bereitliegt."
        default: break
        }
        if q.contains("morgen") { return "Morgen ist es *ruhig*, es stehen nur die Routine und der Steuerberater an.\n09:30 Steuerberater, morgen" }
        if q.contains("heute") || q.contains("an?") { return "Heute geht es am Nachmittag weiter, das nächste um *17 Uhr*.\n17:00 Sundartha Ideen\n17:30 Anruf mit Jonas" }
        return "Verstanden, ich kümmere mich *darum*.\nIch sage Bescheid, sobald es erledigt ist."
    }
}
