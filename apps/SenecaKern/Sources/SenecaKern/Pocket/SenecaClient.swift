import Foundation
import Combine
import CryptoKit
import Security
import OSLog

struct PendingOp: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case move, create, day, update, archive, seen }
    var id = UUID().uuidString
    var kind: Kind
    var taskId: String? = nil
    var status: String? = nil
    var title: String? = nil
    var dayKey: String? = nil
    var day: DayRecord? = nil
    var archived: Bool? = nil
    var ids: [String]? = nil
    var expected: Double? = nil
    var plan: String? = nil
    var frist: String? = nil
    var board: String? = nil
}

let tempoLog = Logger(subsystem: "de.antonio.senecapocket", category: "Tempo")
func tempo(_ step: String) {
    let ms = Int64(Date().timeIntervalSince1970 * 1000)
    tempoLog.notice("[TEMPO] \(ms, privacy: .public) \(step, privacy: .public)")
}

struct KalenderLang: Equatable {
    var termine: [KalenderTermin]
    var checkedAt: Date?
    var loadedAt: Date
}

@MainActor
final class SenecaStore: ObservableObject {
    @Published var today: TodaySnapshot?
    @Published private(set) var days: [String: DayRecord] = [:]
    @Published private(set) var outbox: [PendingOp] = []
    @Published private(set) var localSeen: [String: Double] = [:]
    @Published var connectionStatus = "Nicht verbunden"
    @Published var error: String?
    @Published private(set) var saveFailure: String?
    @Published var isConnected = false
    @Published var isLoading = false
    @Published private(set) var isConfigured = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var kalenderLang: KalenderLang?
    private(set) var lastLocalChange = Date.distantPast

    var clock: () -> Date = { Date() }
    var demo = false

    private var endpoint = ""
    private var sharedToken = ""
    private var sessionKey = Hauptagent.sitzung
    private(set) var daten: SenecaDaten?
    @Published private(set) var stand: SenecaStand?
    @Published private(set) var wartendeTodos: Set<String> = []
    private var generation = UUID()
    private var answerWaiters: [String: CheckedContinuation<String, Error>] = [:]
    private var asks: [String: AskTracker] = [:]
    private var flushing = false
    private var delivering: Set<String> = []
    private var subscribeRetry: Set<String> = []
    nonisolated static let alleRechte = ["lesen", "schreiben", "admin"]
    let chat = ChatService()
    private let gatewayLog = Logger(subsystem: "de.antonio.senecapocket", category: "Gateway")
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "seneca-pocket.days"), let saved = try? JSONDecoder().decode([String: DayRecord].self, from: data) { days = saved }
        if let data = defaults.data(forKey: "seneca-pocket.outbox"), let saved = try? JSONDecoder().decode([PendingOp].self, from: data) { outbox = saved }
        if let data = defaults.data(forKey: "seneca-pocket.seen"), let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            let cutoff = Date().timeIntervalSince1970 * 1000 - 45 * 86_400_000
            localSeen = saved.filter { $0.value > cutoff }
        }
        chat.store = self
    }

    private var cacheKey: String {
        SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static let tagesstandVorsatz = "seneca-pocket.today-cache."
    nonisolated static func tagesstandDatei(_ kennung: String, in ordner: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) -> URL? {
        ordner?.appendingPathComponent(Bundle.main.bundleIdentifier ?? "seneca", isDirectory: true).appendingPathComponent("tagesstand-\(kennung.prefix(16)).json")
    }
    nonisolated static func merkbar(_ s: TodaySnapshot, jetzt: Date = Date()) -> TodaySnapshot {
        let ab = (jetzt.timeIntervalSince1970 - 2 * 86_400) * 1000
        var m = s
        m.tasks = s.tasks.filter { !$0.isDone || ($0.updatedAt ?? 0) >= ab }
        m.cards = s.cards?.filter { $0.status != "done" || ($0.updatedAt ?? 0) >= ab }
        return m
    }
    private struct TagAblage: @unchecked Sendable { let defaults: UserDefaults; let snapshot: TodaySnapshot?; let alt: String }
    private func merkeTag(_ snapshot: TodaySnapshot, kennung: String) {
        let a = TagAblage(defaults: defaults, snapshot: snapshot, alt: Self.tagesstandVorsatz)
        Task.detached(priority: .utility) {
            if let s = a.snapshot, let url = Self.tagesstandDatei(kennung), let data = try? JSONEncoder().encode(Self.merkbar(s)) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            }
            for k in a.defaults.dictionaryRepresentation().keys where k.hasPrefix(a.alt) { a.defaults.removeObject(forKey: k) }
        }
    }
    private func gemerkterTag() -> TodaySnapshot? {
        guard let url = Self.tagesstandDatei(cacheKey), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TodaySnapshot.self, from: data)
    }

    func configure(url: String, token: String, sessionKey: String = Hauptagent.sitzung) {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointChanged = endpoint != normalized
        if endpointChanged || sharedToken != token || self.sessionKey != sessionKey { disconnect() }
        endpoint = normalized
        sharedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        chat.configure(mainKey: self.sessionKey)
        isConfigured = !normalized.isEmpty
        if endpointChanged {
            today = nil
            if let cached = gemerkterTag() {
                today = applyOutbox(to: cached)
                lastSync = cached.updatedAt
            }
        }
    }

    var isActive = true { didSet { if isActive { daten?.jetztVersuchen() } } }

    private struct KartenAntwort: @unchecked Sendable { let w: [String: Any] }

    func addTodoHeute(_ title: String) {
        addTask(title, plan: DayLogic.dayKey(clock(), .current))
    }


    func connect() async {
        guard !demo, isConfigured else { return }
        if daten == nil { daten = neueDaten() }
        guard let daten else { return }
        if daten.zustand == .aus { daten.starten() } else { daten.jetztVersuchen() }
        if await daten.verbindung.warteVerbunden(frist: daten.verbindung.regeln.antwortFristS), isConnected {
            await flushOutbox()
            await loadToday()
        }
    }

    func disconnect() {
        generation = UUID()
        daten?.stoppen()
        daten = nil
        isConnected = false
        isLoading = false
        failPending(SenecaError.message("Verbindung beendet."), keepAsks: false)
        connectionStatus = "Nicht verbunden"
    }

    private func neueDaten() -> SenecaDaten {
        let einstellung = Verbindung.Einstellung(adresse: endpoint, token: sharedToken, ablage: KernAblage(),
                                                 sperre: { try SimulatorSperre.pruefe(adresse: $0) })
        let d = SenecaDaten(einstellung, ordner: MacPfade.datenOrdner)
        let gen = generation
        d.aufEreignis = { [weak self] name, inhalt in
            guard let self, self.generation == gen else { return }
            self.gatewayEreignis(name == "agent" ? "session.tool" : name, inhalt)
        }
        d.$stand.sink { [weak self] s in self?.stand = s }.store(in: &zustandsAbos)
        d.$gestrichelt.sink { [weak self] h in self?.wartendeTodos = Set(h.filter { $0.art == "todo.erledigt" }.compactMap(\.ziel)) }.store(in: &zustandsAbos)
        d.$rechte.dropFirst().sink { [weak self] scopes in
            self?.chat.setAccess(rechte: scopes.compactMap { ["operator.read": "lesen", "operator.write": "schreiben"][$0] }, admin: .notGranted)
        }.store(in: &zustandsAbos)
        d.$zustand.dropFirst().sink { [weak self] z in self?.zustandGeaendert(z, gen) }.store(in: &zustandsAbos)
        return d
    }

    private var zustandsAbos: Set<AnyCancellable> = []

    func zeigeBeispiel(_ name: String) {
        stand = HeuteTafelLogik.beispiel(name)
    }

    func erledige(todo id: String) {
        guard !demo else { wartendeTodos.insert(id); return }
        daten?.handeln("todo.erledigt", ziel: id)
    }

    func antworte(frage id: String, wahl: String) {
        daten?.handeln("frage.antwort", ziel: id, wert: .objekt(["wahl": .text(wahl)]))
    }

    func handle(_ art: String, ziel: String, text: String? = nil) {
        daten?.handeln(art, ziel: ziel, wert: text.map { .text($0) })
    }

    func handle(_ art: String, ziel: String?, wert: [String: JSONWert]) {
        daten?.handeln(art, ziel: ziel, wert: .objekt(wert))
    }

    private func zustandGeaendert(_ z: Verbindungszustand, _ gen: UUID) {
        guard generation == gen else { return }
        switch z {
        case .verbunden:
            isConnected = true
            error = nil
            connectionStatus = "Verbunden"
            Task { await nachVerbinden() }
        case .verbindet:
            connectionStatus = "Verbinde mit Seneca …"
        case .getrennt, .aus:
            let war = isConnected
            isConnected = false
            connectionStatus = "Mac nicht erreichbar"
            error = daten?.verbindung.letzterFehler?.text ?? (war ? "Die Verbindung zum Mac ist abgebrochen." : nil)
            if war { failPending(SenecaError.offline) }
        case .neuKoppeln(let grund):
            isConnected = false
            connectionStatus = "Neu koppeln"
            error = grund
            failPending(SenecaError.offline)
        }
    }

    private func nachVerbinden() async {
        _ = try? await rufe("sessions.messages.subscribe", params: ["key": sessionKey, "agentId": agentID, "subscriptionId": "seneca-pocket-" + sessionKey])
        targetSessions = []
        for key in chat.partnerSitzungen { await subscribeSession(key) }
        await resumeAsks()
        await flushOutbox()
        await loadToday()
    }

    private func gatewayEreignis(_ name: String, _ payload: [String: Any]) {
        guard ["chat", "session.tool", "session.message"].contains(name), matchesSession(payload) else { return }
        receiveSessionEvent(name, payload)
    }

    func rufe(_ fn: String, params: [String: Any] = [:], timeout: Double = 20) async throws -> [String: Any] {
        guard let daten, isConnected else { throw SenecaError.offline }
        guard let fenster = Self.lesefenster[fn] else {
            let betroffen = fn.hasPrefix("workboard.") ? "workboard.cards.list" : fn.hasPrefix("sessions.") || fn == "chat.send" ? "sessions.list" : nil
            if let betroffen {
                leseStand = leseStand.filter { !$0.key.hasPrefix(betroffen) }
                leseLaeuft = leseLaeuft.filter { !$0.key.hasPrefix(betroffen) }
                leseAenderung += 1
            }
            return try await Self.gateway(daten, fn, params, timeout)
        }
        if leseGeneration != generation { leseStand = [:]; leseLaeuft = [:]; leseGeneration = generation }
        let schluessel = fn + "|" + ((try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "")
        if let s = leseStand[schluessel], Date().timeIntervalSince(s.zeit) < fenster { return s.antwort }
        if let laufend = leseLaeuft[schluessel] { return try await laufend.value }
        let aufruf = Task { () throws -> [String: Any] in try await Self.gateway(daten, fn, params, timeout) }
        leseLaeuft[schluessel] = aufruf
        let gen = generation, stand = leseAenderung
        defer { if leseGeneration == gen, leseLaeuft[schluessel] == aufruf { leseLaeuft[schluessel] = nil } }
        let antwort = try await aufruf.value
        if leseGeneration == gen, leseAenderung == stand { leseStand[schluessel] = (Date(), antwort) }
        return antwort
    }

    static func gateway(_ daten: SenecaDaten, _ fn: String, _ params: [String: Any], _ timeout: Double) async throws -> [String: Any] {
        do { return try await daten.rufe(fn, params, frist: timeout) }
        catch let f as VerbindungsFehler { throw f.alsSenecaFehler }
    }

    private static let lesefenster: [String: Double] = ["workboard.cards.list": 60, "agents.list": 60, "sessions.list": 10]
    private var leseStand: [String: (zeit: Date, antwort: [String: Any])] = [:]
    private var leseLaeuft: [String: Task<[String: Any], Error>] = [:]
    private var leseGeneration = UUID()
    private var leseAenderung = 0

    private func failPending(_ error: Error, keepAsks: Bool = true) {
        stromTexte.removeAll()
        guard !keepAsks else { return }
        let answers = answerWaiters
        answerWaiters.removeAll()
        for (id, t) in asks { chat.speicher.setzeZustand(sitzung: t.sessionKey, schluessel: id, ChatService.zustand(nach: SenecaError.offline, bisher: t.zustand)) }
        asks.removeAll()
        gemeldet.removeAll()
        publishLives()
        for continuation in answers.values { continuation.resume(throwing: SenecaError.offline) }
    }

    func loadToday() async {
        guard isConnected, !isLoading else {
            if isLoading { reloadAgain = true }
            return
        }
        let current = generation
        let started = Date()
        let destination = cacheKey
        isLoading = true
        defer { if generation == current { isLoading = false } }
        var failures: [String] = []
        var snapshot = today ?? TodaySnapshot(calendar: [], tasks: [], briefings: [], updatedAt: .distantPast)
        do {
            let result = try await rufe("workboard.cards.list")
            let roh = KartenAntwort(w: result)
            (snapshot.tasks, snapshot.cards, snapshot.boardNames) = await Task.detached(priority: .userInitiated) {
                (Self.personalTasks(roh.w), SenecaPayloadParser.cards(roh.w), Self.boardNames(roh.w))
            }.value
        } catch { failures.append("Aufgaben") }
        do {
            let result = try await rufe("seneca.kalender")
            snapshot.calendarStatus = SenecaPayloadParser.calendarStatus(result)
            if result["ok"] as? Bool != false { snapshot.calendar = SenecaPayloadParser.calendar(result) }
            else { failures.append("Kalender") }
        } catch {
            snapshot.calendarStatus = nil
            failures.append("Kalender")
        }
        if kalenderLang.map({ Date().timeIntervalSince($0.loadedAt) >= 120 }) ?? true { await loadKalenderLang() }
        do {
            snapshot.jobs = SenecaPayloadParser.jobs(try await rufe("cron.list"))
        } catch { failures.append("Mitarbeiter") }
        if let result = try? await rufe("seneca.bereiche") {
            snapshot.leaders = SenecaPayloadParser.leaders(result)
            snapshot.areas = SenecaPayloadParser.areas(result)
        }
        if let result = try? await rufe("seneca.projekte") {
            snapshot.projects = SenecaPayloadParser.projects(result)
            snapshot.projectDue = SenecaPayloadParser.projectDue(result)
        }
        let window = AufgabenLogic.fenster(jetzt: clock())
        let plugin = (try? await rufe("seneca.aufgaben", params: ["von": window.von, "bis": window.bis])).flatMap { SenecaPayloadParser.aufgaben($0) }
        snapshot.tasks = AufgabenLogic.angereichert(snapshot.tasks, plugin: plugin, projects: snapshot.projects, due: snapshot.projectDue, areas: snapshot.areas?.areas)
        if let result = try? await rufe("seneca.fortschritt") { mergeDays(SenecaPayloadParser.days(result)) }
        if let result = try? await rufe("sessions.list", params: ["limit": 200, "configuredAgentsOnly": true]) {
            snapshot.sessions = SenecaPayloadParser.sessions(result)
        }
        if let result = try? await rufe("seneca.gesehen"), let seen = SenecaPayloadParser.seen(result) { snapshot.seen = seen }
        if let result = try? await rufe("agents.list") { snapshot.agentNames = SenecaPayloadParser.agentNames(result) }
        guard generation == current else { return }
        if lastLocalChange > started, let local = today?.tasks {
            snapshot.tasks = local
            reloadAgain = true
        }
        snapshot.updatedAt = Date()
        merkeTag(snapshot, kennung: destination)
        today = applyOutbox(to: snapshot)
        lastSync = snapshot.updatedAt
        error = failures.isEmpty ? nil : "Nicht geladen: " + failures.joined(separator: ", ")
        syncTodayRecord()
        if reloadAgain {
            reloadAgain = false
            isLoading = false
            Task { await self.loadToday() }
        }
    }

    var kalenderTermine: [KalenderTermin] {
        KalenderLogic.gemeinsam(kurz: today?.calendar ?? [], lang: kalenderLang?.termine,
                                kurzAm: today?.calendarStatus?.checkedDate, langAm: kalenderLang?.checkedAt)
    }
    var kalenderEintraege: [CalendarEntry] { KalenderParser.eintraege(kalenderTermine) }
    var kalenderStand: Date? { [calendarCheckedAt, kalenderLang?.checkedAt].compactMap { $0 }.max() }

    @discardableResult
    func loadKalenderLang(vergangen: Int? = nil) async -> [String: Any]? {
        guard !demo else { return nil }
        var params: [String: Any] = ["tage": KalenderLogic.horizon]
        if let vergangen { params["vergangen"] = vergangen }
        guard let result = try? await rufe("seneca.kalender", params: params), result["ok"] as? Bool != false else { return nil }
        kalenderLang = KalenderLang(termine: KalenderParser.termine(result), checkedAt: SenecaPayloadParser.date(result["geprueftAm"]), loadedAt: Date())
        return result
    }

    func addEvent(titel: String, start: Date, ende: Date, kalender: String, ort: String) async throws {
        guard isConnected else { throw SenecaError.offline }
        let result: [String: Any]
        do {
            result = try await rufe("seneca.kalender.anlegen",
                                       params: TerminEingabeLogik.params(titel: titel, start: start, ende: ende, kalender: kalender, ort: ort),
                                       timeout: 45)
        } catch SenecaError.offline {
            throw SenecaError.message("Keine Antwort vom Mac. Sieh im Kalender nach, ob der Termin schon steht, bevor du es noch einmal versuchst.")
        }
        if result["ok"] as? Bool != false {
            var snap = today ?? TodaySnapshot(calendar: [], tasks: [], briefings: [], updatedAt: .distantPast)
            snap.calendarStatus = SenecaPayloadParser.calendarStatus(result)
            snap.calendar = SenecaPayloadParser.calendar(result)
            today = snap
            syncTodayRecord()
        }
        Task { await loadKalenderLang() }
    }

    var calendarCheckedAt: Date? {
        guard let today else { return nil }
        return today.calendarStatus?.checkedDate ?? (today.updatedAt == .distantPast ? nil : today.updatedAt)
    }
    func calendarStandText(now: Date? = nil) -> String? {
        CalendarFreshness.standText(checkedAt: calendarCheckedAt, now: now ?? clock())
    }

    private var reloadAgain = false

    nonisolated static func boardNames(_ result: [String: Any]) -> [String: String] {
        var names: [String: String] = [:]
        for b in result["boards"] as? [[String: Any]] ?? [] {
            if let id = b["id"] as? String, let name = b["name"] as? String, !name.isEmpty { names[id] = name }
        }
        return names
    }

    nonisolated static func personalTasks(_ result: [String: Any]) -> [SenecaTask] {
        let boardNames = Self.boardNames(result)
        return (result["cards"] as? [[String: Any]] ?? []).compactMap { card in
            let metadata = card["metadata"] as? [String: Any]
            if metadata?["archivedAt"] != nil { return nil }
            guard let id = card["id"] as? String, let title = card["title"] as? String else { return nil }
            let automation = metadata?["automation"] as? [String: Any]
            let board = automation?["boardId"] as? String ?? "default"
            let assignedAgent = card["agentId"] as? String ?? ""
            guard board == "privat" || assignedAgent.isEmpty else { return nil }
            let status = card["status"] as? String ?? "todo"
            let displayTitle = title.replacingOccurrences(of: "^\\[[^\\]]*\\]\\s*", with: "", options: .regularExpression)
            let labels = (card["labels"] as? [Any])?.compactMap { $0 as? String }
            return SenecaTask(id: id, title: displayTitle, isDone: ["done", "completed"].contains(status), status: status,
                              updatedAt: (card["updatedAt"] as? NSNumber)?.doubleValue, notes: card["notes"] as? String,
                              isParked: title.uppercased().hasPrefix("[PARKIERT"),
                              completedAt: (card["completedAt"] as? NSNumber)?.doubleValue,
                              priority: card["priority"] as? String, rawTitle: title,
                              projektId: board, projektName: boardNames[board] ?? (board == "privat" ? "Privat" : nil),
                              plan: AufgabenLogic.labelTag(labels, "plan"), frist: AufgabenLogic.labelTag(labels, "frist"))
        }
    }

    func toggleTask(_ id: String) {
        guard var snap = today, let index = snap.tasks.firstIndex(where: { $0.id == id }) else { return }
        let before = snap.tasks[index]
        snap.tasks[index].isDone.toggle()
        lastLocalChange = Date()
        let done = snap.tasks[index].isDone
        if done, !before.isDone { statusVorErledigt[id] = before.status }
        let status = TodoEdits.statusNachHaken(done: done, previous: statusVorErledigt[id])
        snap.tasks[index].status = status
        snap.tasks[index].completedAt = done ? clock().timeIntervalSince1970 * 1000 : nil
        today = snap
        saveFailure = nil
        TodoEdits.setStatus(&outbox, taskId: id, status: status, title: snap.tasks[index].title, expected: before.updatedAt)
        persistOutbox()
        syncTodayRecord()
        Task { await flushOutbox() }
    }

    private var statusVorErledigt: [String: String] = [:]

    private static func setzeProjekt(_ task: inout SenecaTask, board: String?, in snap: TodaySnapshot) {
        guard let z = NeueAufgabeLogik.ziel(board: board, boardNames: snap.boardNames, projects: snap.projects,
                                            areas: snap.areas?.areas, tasks: snap.tasks) else { return }
        task.projektId = z.board
        task.projektName = z.projektName
        task.bereichId = z.bereichId
        task.bereichName = z.bereichName
    }

    func addTask(_ title: String, plan: String? = nil, frist: String? = nil, board: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let localID = "local-" + UUID().uuidString
        var snap = today ?? TodaySnapshot(calendar: [], tasks: [], briefings: [], updatedAt: .distantPast)
        var neu = SenecaTask(id: localID, title: title, isDone: false, status: "todo", updatedAt: clock().timeIntervalSince1970 * 1000)
        neu.plan = plan
        neu.frist = frist
        Self.setzeProjekt(&neu, board: board, in: snap)
        snap.tasks.append(neu)
        today = snap
        lastLocalChange = Date()
        outbox.append(PendingOp(kind: .create, taskId: localID, status: "todo", title: title, plan: plan, frist: frist, board: board))
        persistOutbox()
        syncTodayRecord()
        Task { await flushOutbox() }
    }

    private var inFlightOp: String? { flushing ? outbox.first?.id : nil }

    func parkTask(_ id: String) -> TodoUndo? {
        guard var snap = today, let i = snap.tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let task = snap.tasks[i]
        let raw = TodoEdits.parkedTitle(task.fullTitle, on: clock(), .current)
        snap.tasks[i].rawTitle = raw
        snap.tasks[i].isParked = true
        var box = outbox
        let change = TodoEdits.setTitle(&box, taskId: id, title: raw, previous: task.fullTitle, inFlight: inFlightOp)
        commitTaskChange(snap, box)
        return TodoUndo(kind: .park, task: task, index: i, change: change)
    }

    func archiveTask(_ id: String) -> TodoUndo? {
        guard var snap = today, let i = snap.tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let task = snap.tasks.remove(at: i)
        var box = outbox
        let change = TodoEdits.archive(&box, taskId: id, title: task.fullTitle, inFlight: inFlightOp)
        commitTaskChange(snap, box)
        return TodoUndo(kind: .archive, task: task, index: i, change: change)
    }

    func renameTask(_ id: String, to text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var snap = today, let i = snap.tasks.firstIndex(where: { $0.id == id }), snap.tasks[i].title != text else { return }
        let raw = TodoEdits.renamedTitle(snap.tasks[i].fullTitle, to: text)
        let previous = snap.tasks[i].fullTitle
        snap.tasks[i].rawTitle = raw
        snap.tasks[i].title = text
        var box = outbox
        _ = TodoEdits.setTitle(&box, taskId: id, title: raw, previous: previous, inFlight: inFlightOp)
        commitTaskChange(snap, box)
    }

    func undoTask(_ undo: TodoUndo) {
        var box = outbox
        TodoEdits.undo(&box, undo.change, inFlight: inFlightOp)
        var snap = today ?? TodaySnapshot(calendar: [], tasks: [], briefings: [], updatedAt: .distantPast)
        if let i = snap.tasks.firstIndex(where: { $0.id == undo.task.id }) { snap.tasks[i] = undo.task }
        else { snap.tasks.insert(undo.task, at: min(undo.index, snap.tasks.count)) }
        commitTaskChange(snap, box)
    }

    private func commitTaskChange(_ snap: TodaySnapshot, _ box: [PendingOp]) {
        today = snap
        outbox = box
        saveFailure = nil
        lastLocalChange = Date()
        persistOutbox()
        syncTodayRecord()
        Task { await flushOutbox() }
    }

    func setRoutine(_ done: Bool) {
        let key = DayLogic.dayKey(clock(), .current)
        var record = days[key] ?? DayRecord(routine: false, erledigt: 0, aktualisiert: 0)
        record.routine = done
        days[key] = record
        lastLocalChange = Date()
        syncTodayRecord(force: true)
    }

    func routineDone(on date: Date) -> Bool { days[DayLogic.dayKey(date, .current)]?.routine ?? false }

    func syncTodayRecord(force: Bool = false) {
        let now = clock()
        let cal = Calendar.current
        let key = DayLogic.dayKey(now, cal)
        let doneTodos = DayLogic.todosToday(today?.tasks ?? [], dayStart: cal.startOfDay(for: now)).filter(\.isDone).count
        var record = days[key] ?? DayRecord(routine: false, erledigt: 0, aktualisiert: 0)
        let erledigt = (record.routine ? 1 : 0) + doneTodos
        guard force || record.erledigt != erledigt || record.aktualisiert == 0 else { return }
        guard force || today != nil else { return }
        record.erledigt = erledigt
        record.aktualisiert = now.timeIntervalSince1970 * 1000
        days[key] = record
        persistDays()
        outbox.removeAll { $0.kind == .day && $0.dayKey == key }
        outbox.append(PendingOp(kind: .day, dayKey: key, day: record))
        persistOutbox()
        Task { await flushOutbox() }
    }

    private func mergeDays(_ remote: [String: DayRecord]) {
        var merged = days
        for (key, value) in remote where (merged[key]?.aktualisiert ?? -1) <= value.aktualisiert {
            if outbox.contains(where: { $0.kind == .day && $0.dayKey == key }) { continue }
            merged[key] = value
        }
        days = merged
        persistDays()
    }

    private func applyOutbox(to snapshot: TodaySnapshot) -> TodaySnapshot {
        var snap = snapshot
        for op in outbox {
            switch op.kind {
            case .move:
                if let i = snap.tasks.firstIndex(where: { $0.id == op.taskId }) {
                    let done = op.status == "done"
                    if snap.tasks[i].isDone != done {
                        snap.tasks[i].isDone = done
                        snap.tasks[i].status = op.status ?? "todo"
                        snap.tasks[i].completedAt = done ? clock().timeIntervalSince1970 * 1000 : nil
                    }
                }
            case .create:
                if let id = op.taskId, !snap.tasks.contains(where: { $0.id == id }) {
                    let raw = op.title ?? ""
                    var neu = SenecaTask(id: id, title: TodoEdits.display(raw), isDone: op.status == "done", status: op.status ?? "todo",
                                         isParked: TodoEdits.isParked(raw),
                                         completedAt: op.status == "done" ? clock().timeIntervalSince1970 * 1000 : nil, rawTitle: raw)
                    neu.plan = op.plan
                    neu.frist = op.frist
                    Self.setzeProjekt(&neu, board: op.board, in: snap)
                    snap.tasks.append(neu)
                }
            case .update:
                if let raw = op.title, let i = snap.tasks.firstIndex(where: { $0.id == op.taskId }) {
                    snap.tasks[i].rawTitle = raw
                    snap.tasks[i].title = TodoEdits.display(raw)
                    snap.tasks[i].isParked = TodoEdits.isParked(raw)
                }
            case .archive:
                if op.archived == false {
                    if let id = op.taskId, let raw = op.title, !snap.tasks.contains(where: { $0.id == id }) {
                        snap.tasks.append(SenecaTask(id: id, title: TodoEdits.display(raw), isDone: false, isParked: TodoEdits.isParked(raw), rawTitle: raw))
                    }
                } else {
                    snap.tasks.removeAll { $0.id == op.taskId }
                }
            case .day, .seen: break
            }
        }
        return snap
    }

    func flushOutbox() async {
        guard !demo, isConnected, !flushing, !outbox.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        var reload = false
        while let op = outbox.first, isConnected {
            do {
                switch op.kind {
                case .move:
                    var params: [String: Any] = ["id": op.taskId ?? "", "status": op.status ?? "todo"]
                    if let expected = op.expected { params["expectedUpdatedAt"] = expected }
                    let moved = try await rufe("workboard.cards.move", params: params)
                    let card = moved["card"] as? [String: Any] ?? moved
                    let fresh = (card["updatedAt"] as? NSNumber)?.doubleValue
                    TodoEdits.adoptUpdatedAt(&outbox, taskId: op.taskId ?? "", updatedAt: fresh)
                    if let fresh, let i = today?.tasks.firstIndex(where: { $0.id == op.taskId }) { today?.tasks[i].updatedAt = fresh }
                    reload = true
                case .create:
                    let created = try await rufe("workboard.cards.create", params: TodoEdits.createParams(title: op.title ?? "", plan: op.plan, frist: op.frist, board: op.board, key: op.id))
                    let card = created["card"] as? [String: Any] ?? created
                    let status = outbox.first(where: { $0.id == op.id })?.status ?? op.status
                    if status == "done", let newID = card["id"] as? String {
                        _ = try await rufe("workboard.cards.move", params: ["id": newID, "status": "done"])
                    }
                    reload = true
                case .update:
                    let updated = try await rufe("workboard.cards.update", params: ["id": op.taskId ?? "", "patch": ["title": op.title ?? ""]])
                    TodoEdits.adoptUpdatedAt(&outbox, taskId: op.taskId ?? "", updatedAt: ((updated["card"] as? [String: Any] ?? updated)["updatedAt"] as? NSNumber)?.doubleValue)
                    reload = true
                case .archive:
                    let archived = try await rufe("workboard.cards.archive", params: ["id": op.taskId ?? "", "archived": op.archived ?? true])
                    TodoEdits.adoptUpdatedAt(&outbox, taskId: op.taskId ?? "", updatedAt: ((archived["card"] as? [String: Any] ?? archived)["updatedAt"] as? NSNumber)?.doubleValue)
                    reload = true
                case .seen:
                    let result = try await rufe("seneca.gesehen.setzen", params: ["ids": op.ids ?? []])
                    if let seen = SenecaPayloadParser.seen(result) { today?.seen = seen }
                case .day:
                    if let key = op.dayKey, let day = op.day {
                        let result = try await rufe("seneca.fortschritt.setzen", params: ["tag": key, "routine": day.routine, "erledigt": day.erledigt, "aktualisiert": day.aktualisiert])
                        let remote = SenecaPayloadParser.days(result)
                        outbox.removeAll { $0.id == op.id }; persistOutbox()
                        mergeDays(remote)
                        continue
                    }
                }
                outbox.removeAll { $0.id == op.id }
                persistOutbox()
            } catch SenecaError.offline {
                break
            } catch SenecaError.refused(let refusal) where op.kind == .move && refusal.isConflictAlreadyAt(op.status ?? "todo") {
                TodoEdits.adoptUpdatedAt(&outbox, taskId: op.taskId ?? "", updatedAt: refusal.cardUpdatedAt)
                if let fresh = refusal.cardUpdatedAt, let i = today?.tasks.firstIndex(where: { $0.id == op.taskId }) { today?.tasks[i].updatedAt = fresh }
                outbox.removeAll { $0.id == op.id }
                persistOutbox()
                reload = true
            } catch {
                let failed = op
                outbox.removeAll { $0.id == op.id }
                persistOutbox()
                if failed.kind == .seen { continue }
                saveFailure = failed.kind == .day ? "Dein Tagesstand wurde nicht gespeichert." : "„\(failed.title ?? "To-do")“ wurde nicht gespeichert. Tippe zum Wiederholen."
                reload = true
            }
        }
        if reload && outbox.allSatisfy({ $0.kind == .day }) { await loadToday() }
    }

    private func persistOutbox() {
        guard !demo else { return }
        if let data = try? JSONEncoder().encode(outbox) { defaults.set(data, forKey: "seneca-pocket.outbox") }
    }
    private func persistDays() {
        guard !demo else { return }
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: "seneca-pocket.days") }
    }
    func clearSaveFailure() { saveFailure = nil }

    func markSeen(_ keys: [String]) {
        let fresh = keys.filter { localSeen[$0] == nil && today?.seen?[$0] == nil }
        guard !fresh.isEmpty else { return }
        let now = Date().timeIntervalSince1970 * 1000
        for k in fresh { localSeen[k] = now }
        if !demo, let data = try? JSONEncoder().encode(localSeen) { defaults.set(data, forKey: "seneca-pocket.seen") }
        for start in stride(from: 0, to: fresh.count, by: 50) {
            outbox.append(PendingOp(kind: .seen, ids: Array(fresh[start..<min(start + 50, fresh.count)])))
        }
        persistOutbox()
        Task { await flushOutbox() }
    }

    func lastRunSummary(_ jobId: String) async -> String? {
        #if DEBUG
        if demo { return nil }
        #endif
        guard isConnected, let result = try? await rufe("cron.runs", params: ["id": jobId, "limit": 1]) else { return nil }
        let entry = (result["entries"] as? [[String: Any]])?.first
        let summary = (entry?["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary?.isEmpty == false ? summary : nil
    }

    nonisolated static let connectCaps = ["chat-only-assistant-text", "tool-events"]

    #if os(iOS)
    nonisolated static let phoneHint = "\n\n[Vom iPhone: erst ein kurzer Ergebnissatz, dann knapp; Termine als „HH:MM Titel“.]"
    #else
    nonisolated static let phoneHint = ""
    #endif

    private func publishLives() {
        chat.setLives(asks.values.map(\.live))
        for (id, t) in asks where gemeldet[id] != t.zustand {
            gemeldet[id] = t.zustand
            chat.speicher.setzeZustand(sitzung: t.sessionKey, schluessel: id, t.zustand)
        }
    }
    private var gemeldet: [String: ZustellZustand] = [:]
    private var stromTexte: [String: String] = [:]

    func ask(_ text: String, sessionKey target: String? = nil, idempotencyKey: String? = nil, anhaenge: [[String: Any]] = []) async throws -> String {
        tempo("ask() verbunden=\(isConnected)")
        let key = AreasLogic.chatSession(target, main: sessionKey)
        let id = idempotencyKey ?? UUID().uuidString
        guard asks[id] == nil else { throw SenecaError.message("Diese Frage wird schon gesendet.") }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        asks[id] = AskTracker(key: id, sessionKey: key, question: question, sentAt: Date())
        if chat.speicher.zustand(sitzung: key, schluessel: id) == nil { chat.speicher.legeFrageAn(sitzung: key, text: question, schluessel: id) }
        if !anhaenge.isEmpty { askAnhaenge[id] = anhaenge }
        publishLives()
        return try await withCheckedThrowingContinuation { continuation in
            answerWaiters[id] = continuation
            watchAsk(id)
            deliver(id)
        }
    }

    private func deliver(_ id: String) {
        guard let tracker = asks[id], !tracker.quittiert, !delivering.contains(id), isConnected else { return }
        delivering.insert(id)
        Task { [weak self] in
            guard let self else { return }
            await self.deliverLoop(id)
            self.delivering.remove(id)
        }
    }

    private var askAnhaenge: [String: [[String: Any]]] = [:]

    private func deliverLoop(_ id: String) async {
        while let tracker = asks[id], !tracker.quittiert {
            guard isConnected else { return }
            let gen = generation
            await subscribeSession(tracker.sessionKey)
            guard asks[id] != nil, isConnected, generation == gen else { continue }
            asks[id]?.versuchBeginnt()
            do {
                tempo("chat.send raus id=\(id.prefix(8)) session=\(tracker.sessionKey) versuch=\(tracker.versuche + 1)")
                var sendeParams: [String: Any] = ["sessionKey": tracker.sessionKey, "agentId": AreasLogic.agentID(of: tracker.sessionKey),
                                                  "message": tracker.question + Self.phoneHint, "idempotencyKey": id, "queueMode": "followup"]
                if let anhaenge = askAnhaenge[id] { sendeParams["attachments"] = anhaenge }
                let result = try await rufe("chat.send", params: sendeParams, timeout: ZustellPlan.sendeTimeout)
                let runID = result["runId"] as? String
                let status = result["status"] as? String ?? "-"
                tempo("chat.send bestätigt run=\((runID ?? "-").prefix(8)) status=\(status)")
                guard asks[id] != nil else { return }
                asks[id]?.acknowledged(runId: runID)
                publishLives()
                if status != "started" || (asks[id]?.versuche ?? 0) > 1 {
                    Task { await self.chat.speicher.nachholen(tracker.sessionKey, grund: .eigenerLauf) }
                }
                return
            } catch {
                guard var current = asks[id] else { return }
                if current.quittiert { return }
                guard isConnected, generation == gen else {
                    current.abbruchNachSenden()
                    asks[id] = current
                    if ZustellPlan.abbruchGibtAuf(abbrueche: current.abbrueche) {
                        tempo("chat.send riss die Verbindung \(current.abbrueche)-mal ab, gebe auf id=\(id.prefix(8))")
                        finishAsk(id, .failure(SenecaError.nichtGesendet))
                    }
                    return
                }
                current.versuchFehlgeschlagen()
                asks[id] = current
                switch ZustellPlan.entscheide(fehler: error, fehlversuche: current.fehlversuche, seit: Date().timeIntervalSince(current.sentAt)) {
                case .aufgeben:
                    tempo("chat.send endgültig gescheitert id=\(id.prefix(8))")
                    if case SenecaError.refused = error { finishAsk(id, .failure(error)) } else { finishAsk(id, .failure(SenecaError.nichtGesendet)) }
                    return
                case .wiederholen(let pause):
                    tempo("chat.send ohne Quittung id=\(id.prefix(8)), neuer Versuch in \(Int(pause)) s (gleicher Schlüssel)")
                    try? await Task.sleep(for: .seconds(pause))
                }
            }
        }
    }

    func subscribeSession(_ key: String) async {
        guard isConnected, key != sessionKey, !targetSessions.contains(key) else { return }
        if await abonniere(key) { return }
        guard subscribeRetry.insert(key).inserted else { return }
        let gen = generation
        Task { [weak self] in
            for pause in ZustellPlan.abonnierPausen {
                try? await Task.sleep(for: .seconds(pause))
                guard let self, self.isConnected, self.generation == gen, !self.targetSessions.contains(key) else { break }
                if await self.abonniere(key) { break }
            }
            self?.subscribeRetry.remove(key)
        }
    }

    private func abonniere(_ key: String) async -> Bool {
        let gen = generation
        do {
            _ = try await rufe("sessions.messages.subscribe", params: ["key": key, "agentId": AreasLogic.agentID(of: key), "subscriptionId": "seneca-pocket-" + key], timeout: 60)
            guard generation == gen else { return false }
            targetSessions.insert(key)
            return true
        } catch {
            gatewayLog.info("subscribe \(key, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func abortAsk(sessionKey key: String) async {
        let open = asks.filter { $0.value.sessionKey == key }
        guard isConnected else { return }
        let agent = AreasLogic.agentID(of: key)
        if open.isEmpty {
            _ = try? await rufe("chat.abort", params: ["sessionKey": key, "agentId": agent])
            return
        }
        for (id, tracker) in open {
            var stopped = false
            for run in tracker.abortableRunIds {
                let plain = try? await rufe("chat.abort", params: ["sessionKey": key, "agentId": agent, "runId": run])
                if plain?["aborted"] as? Bool == true { stopped = true; continue }
                let queued = try? await rufe("chat.abort", params: ["sessionKey": key, "agentId": agent, "runId": run, "discardPendingInput": true])
                if queued?["aborted"] as? Bool == true { stopped = true }
            }
            tempo("gestoppt id=\(id.prefix(8)) aborted=\(stopped)")
            guard let current = asks[id] else { continue }
            let partial = current.live.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty, let run = current.abortableRunIds.last { chat.speicher.nimmStromEnde(sitzung: key, lauf: run, text: partial, frage: id) }
            finishAsk(id, partial.isEmpty ? .failure(SenecaError.stopped) : .success(partial))
        }
    }

    private func resumeAsks() async {
        for (id, tracker) in asks {
            await subscribeSession(tracker.sessionKey)
            if !tracker.quittiert { deliver(id) }
        }
        chat.speicher.nachVerbinden(auch: [chat.currentKey] + asks.values.map(\.sessionKey))
    }

    private func watchAsk(_ id: String) {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let tracker = self.asks[id] else { return }
                let total = Date().timeIntervalSince(tracker.sentAt)
                if !tracker.quittiert {
                    if total > ZustellPlan.gesamtFrist { self.finishAsk(id, .failure(SenecaError.nichtGesendet)); return }
                } else if total > ZustellPlan.antwortFrist {
                    self.finishAsk(id, .failure(SenecaError.message("\(ChatPartner.satzName(sessionKey: tracker.sessionKey)) braucht gerade sehr lange. Die Antwort erscheint hier im Chat, sobald sie da ist.")))
                    return
                }
            }
        }
    }

    private func finishAsk(_ id: String, _ result: Result<String, Error>) {
        let tracker = asks.removeValue(forKey: id)
        askAnhaenge[id] = nil
        gemeldet[id] = nil
        publishLives()
        if let tracker {
            switch result {
            case .success: chat.speicher.setzeZustand(sitzung: tracker.sessionKey, schluessel: id, .fertig)
            case .failure(let fehler):
                chat.speicher.setzeZustand(sitzung: tracker.sessionKey, schluessel: id, ChatService.zustand(nach: fehler, bisher: tracker.zustand))
            }
        }
        guard let waiter = answerWaiters.removeValue(forKey: id) else { return }
        if case .success = result, let tracker { chat.answered(sessionKey: tracker.sessionKey) }
        tempo("antwort zugeordnet id=\(id.prefix(8)) ok=\((try? result.get()) != nil)")
        waiter.resume(with: result)
    }

    private var agentID: String { sessionKey.split(separator: ":").dropFirst().first.map(String.init) ?? Hauptagent.id }
    private var targetSessions: Set<String> = []
    private func matchesSession(_ payload: [String: Any]) -> Bool {
        guard let key = payload["sessionKey"] as? String else { return false }
        return ([sessionKey] + targetSessions + asks.values.map(\.sessionKey)).contains { s in Self.sameSession(key, s, agent: payload["agentId"] as? String) }
    }
    nonisolated static func sameSession(_ key: String, _ s: String, agent: String?) -> Bool {
        key == s || (agent == AreasLogic.agentID(of: s) && s.hasSuffix(":" + key))
    }
    private func sitzungsSchluessel(_ key: String, agent: String?) -> String {
        for s in [sessionKey] + Array(targetSessions) + asks.values.map(\.sessionKey) where Self.sameSession(key, s, agent: agent) { return s }
        return key.hasPrefix("agent:") ? key : "agent:\(agent ?? Hauptagent.id):\(key)"
    }

    private func receiveSessionEvent(_ event: String, _ payload: [String: Any]) {
        let key = sitzungsSchluessel(payload["sessionKey"] as? String ?? "", agent: payload["agentId"] as? String)
        let run = payload["runId"] as? String
        if event == "session.message" {
            let zeile = payload["message"] as? [String: Any]
            if let zeile {
                chat.speicher.nimmNachricht(sitzung: key, zeile: zeile, lauf: run, kennung: payload["messageId"] as? String,
                                            seq: (payload["messageSeq"] as? NSNumber)?.intValue)
                chat.neueZeile(key, zeile)
            }
            for (id, t) in asks where t.sessionKey == key {
                guard ChatLogic.gehoertZurFrage(zeile, idempotencyKey: id) else { continue }
                var eigene = t
                if let lauf = ChatLogic.ownRunId(message: zeile, payloadRunId: run, idempotencyKey: id) {
                    eigene.claim(run: lauf, bisher: stromTexte[lauf.lowercased()])
                    tempo("eigener Lauf über Verlaufszeile id=\(id.prefix(8)) run=\(lauf.prefix(8))")
                } else {
                    eigene.gatewayKenntFrage()
                }
                asks[id] = eigene
                publishLives()
            }
            if zeile?["role"] as? String == "assistant" { pruefeFragen(key) }
            return
        }
        if event == "chat", let run {
            let r = run.lowercased()
            let state = payload["state"] as? String ?? ""
            let message = ChatLogic.text(of: payload["message"])
            if state == "delta" {
                let delta = payload["deltaText"] as? String
                if payload["replace"] as? Bool == true { stromTexte[r] = message.isEmpty ? (delta ?? "") : message }
                else if let delta { stromTexte[r, default: ""] += delta }
                else if !message.isEmpty { stromTexte[r] = message }
            } else if ["final", "aborted", "error"].contains(state) {
                let text = message.isEmpty ? (stromTexte[r] ?? "") : message
                stromTexte[r] = nil
                let eigene = asks.first { $0.value.sessionKey == key && $0.value.runIds.contains(r) }?.key
                if state != "error" { chat.speicher.nimmStromEnde(sitzung: key, lauf: run, text: text, frage: eigene) }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chat.speicher.laufZuEnde(key, eigen: eigene != nil) }
            }
        }
        for id in Array(asks.keys) {
            guard var tracker = asks[id], tracker.sessionKey == key else { continue }
            let hadDelta = tracker.sawDelta, hadTool = tracker.sawTool
            let step = tracker.handle(event: event, payload: payload)
            asks[id] = tracker
            if !hadDelta && tracker.sawDelta { tempo("erstes Delta id=\(id.prefix(8)) run=\((run ?? "-").prefix(8))") }
            if !hadTool && tracker.sawTool { tempo("erstes Werkzeug-Ereignis id=\(id.prefix(8)) \(tracker.activity ?? "")") }
            switch step {
            case .ignore: continue
            case .update: publishLives()
            case .stopped: finishAsk(id, .failure(SenecaError.stopped))
            case .finished(let text):
                tempo("\(payload["state"] as? String ?? "final") übernommen id=\(id.prefix(8))")
                finishAsk(id, .success(text))
            case .failed(let message): finishAsk(id, .failure(SenecaError.message(message)))
            }
        }
    }

    func pruefeFragen(_ key: String) {
        for (id, t) in asks where t.sessionKey == key {
            if let antwort = chat.speicher.antwort(sitzung: key, schluessel: id) {
                tempo("Antwort im Speicher id=\(id.prefix(8))")
                finishAsk(id, .success(antwort))
            } else if !t.quittiert, chat.speicher.bestaetigt(sitzung: key, schluessel: id) {
                asks[id]?.gatewayKenntFrage()
                publishLives()
            }
        }
    }

    #if DEBUG
    func loadDemo(now: Date, streak: Int, record: Int, todos: Bool, routineDone: Bool, needs: Bool = false) {
        demo = true
        isConfigured = true
        zeigeBeispiel(ProcessInfo.processInfo.environment["SENECA_DEMO_STAND"] ?? "Beispiel-Stand")
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func at(_ h: Int, _ m: Int, _ offset: Int = 0) -> Date { cal.date(byAdding: .minute, value: h * 60 + m, to: cal.date(byAdding: .day, value: offset, to: day)!)! }
        var entries: [CalendarEntry] = []
        for offset in [0, 1] {
            for (t, s, e) in [("Aufwachen", (5, 0), (5, 15)), ("Laufen", (5, 30), (6, 30)), ("Lesen", (6, 30), (7, 30)), ("Programmieren lernen", (7, 30), (8, 0)), ("To-Dos sichten", (8, 0), (8, 15))] {
                entries.append(CalendarEntry(id: "\(offset)\(t)", title: t, start: at(s.0, s.1, offset), end: at(e.0, e.1, offset), calendar: "Routine"))
            }
        }
        func job(_ id: String, _ name: String, _ agent: String, _ expr: String) -> AgentJob {
            AgentJob(id: id, name: name, agentId: agent, enabled: true, kind: "cron", expr: expr, tz: TimeZone.current.identifier)
        }
        let weekday = cal.component(.weekday, from: now) - 1
        let jobs = [
            job("a", "Sundartha Planung", "sundartha", "45 6 * * *"),
            job("b", "Morgen-Briefing mit Anruf", Hauptagent.id, "30 7 * * *"),
            job("c", "Wettbewerber CALL-E — täglicher Check", "sundartha", "30 8 * * *"),
            job("d", "Sundartha Ideen", "sundartha", "0 17 * * \(weekday)"),
            job("e", "Vodafone Ideen", "powerbi", "15 17 * * \(weekday)"),
            job("f", "Sundartha Status", "sundartha", "30 18 * * *"),
            job("g", "🌙 Abendbericht", Hauptagent.id, "0 19 * * *"),
        ]
        let demoEnv = ProcessInfo.processInfo.environment
        let aufgaben = AufgabenLogic.demo(now: now, cal)
        let useAufgaben = demoEnv["SENECA_DEMO_AUFGABEN"] != "0"
        let tasks = !todos ? [] : useAufgaben ? aufgaben.tasks : AufgabenLogic.vorgaben()
        var jobList = jobs
        var cards: [WorkCard]? = nil
        if needs {
            let run = at(6, 45) < now ? at(6, 45) : at(6, 45, -1)
            jobList[0].lastRunAtMs = run.timeIntervalSince1970 * 1000
            jobList[0].lastRunStatus = "error"
            jobList[0].lastError = "Job execution timed out after 600000ms"
            jobList[0].lastDurationMs = 600_000
            cards = [WorkCard(id: "demo-review", title: "Website-Texte prüfen", status: "review", agentId: "sundartha", sessionKey: "agent:sundartha:main",
                              boardId: "sundartha", updatedAt: now.addingTimeInterval(-7200).timeIntervalSince1970 * 1000)]
        }
        let (areas, areaCards) = Self.demoAreas(now: now, cal)
        let seenAreaCards = Dictionary(uniqueKeysWithValues: areaCards.map { (NeedsYou.cardKey($0), now.timeIntervalSince1970 * 1000) })
        today = TodaySnapshot(calendar: entries, tasks: tasks, briefings: [], updatedAt: now, jobs: jobList, leaders: ["sundartha": "Sundartha", "powerbi": "Vodafone"],
                              cards: (cards ?? []) + areaCards, sessions: needs ? [] : nil, seen: seenAreaCards, agentNames: needs ? [Hauptagent.id: "Seneca"] : nil,
                              areas: areas, projects: useAufgaben ? aufgaben.projects : nil, projectDue: useAufgaben ? aufgaben.due : nil)
        localSeen = [:]
        var history: [String: DayRecord] = [:]
        for i in 0..<streak { history[DayLogic.dayKey(cal.date(byAdding: .day, value: -(i + 1), to: day)!, cal)] = DayRecord(routine: true, erledigt: 1, aktualisiert: 1) }
        history[DayLogic.dayKey(cal.date(byAdding: .day, value: -(streak + 2), to: day)!, cal)] = DayRecord(routine: false, erledigt: record, aktualisiert: 1)
        history[DayLogic.dayKey(day, cal)] = DayRecord(routine: routineDone, erledigt: routineDone ? 1 : 0, aktualisiert: 1)
        days = history
        outbox = []
        lastSync = now
        isConnected = false
        connectionStatus = "Demo"
        let env = ProcessInfo.processInfo.environment
        if let s = env["SENECA_DEMO_STAND"], case let p = s.split(separator: ":").compactMap({ Int($0) }), p.count == 2 {
            let stand = at(p[0], p[1])
            today?.updatedAt = stand
            today?.calendarStatus = CalendarStatus(ok: true, checkedAt: ISO8601DateFormatter().string(from: stand))
            lastSync = stand
        }
        if env["SENECA_DEMO_OFFLINE"] == "1" { connectionStatus = "Mac nicht erreichbar" }
    }

    static func demoAreas(now: Date, _ cal: Calendar) -> (AreaRegistry, [WorkCard]) {
        let day = cal.startOfDay(for: now)
        let status = cal.date(bySettingHour: 12, minute: 30, second: 0, of: day)! < now
            ? cal.date(bySettingHour: 12, minute: 30, second: 0, of: day)!
            : cal.date(bySettingHour: 18, minute: 30, second: 0, of: cal.date(byAdding: .day, value: -1, to: day)!)!
        let earlier = cal.date(byAdding: .day, value: -1, to: status)!
        func stamp(_ d: Date, time: Bool) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = time ? "dd.MM.yyyy, HH:mm" : "dd.MM.yyyy"
            return "Stand " + f.string(from: d) + ":"
        }
        func due(_ days: Int) -> String {
            let f = DateFormatter(); f.dateFormat = "dd.MM."
            return f.string(from: cal.date(byAdding: .day, value: days, to: day)!)
        }
        let registry = AreaRegistry(areas: [
            Area(id: "sundartha", name: "Sundartha", leader: "sundartha", leaderName: "Sundartha",
                 specialists: ["sp-newsletter", "sp-website", "sp-security"],
                 summary: .init(exists: true, lines: [
                    "\(stamp(status, time: true)) Der Ideenlauf ist vollständig gelaufen und hat zwei neue Entscheidungen (E-8 ElevenLabs-Speicherfrist, E-9 fehlende Widerrufs-Einwilligung im Checkout) in die Inbox gelegt.",
                    "Der CALL-E-Tagescheck lief ohne Abschlussantwort; die heutige Beobachtung fällt dadurch aus.",
                    "Bei Antonio liegen weiterhin E-6 und E-7."], changedAt: status.timeIntervalSince1970 * 1000)),
            Area(id: "vodafone", name: "Vodafone", leader: "powerbi", leaderName: "Vodafone",
                 specialists: ["sp-reporting", "sp-marktanalyse"],
                 summary: .init(exists: true, lines: [
                    "\(stamp(earlier, time: false)) Power BI ruht auf Antonios Anweisung und wartet auf die einmalige Anmeldung.",
                    "Vier Abnahmen (P-32, P-3, P-2b, P-28) stehen noch auf NEEDS_WORK."], changedAt: earlier.timeIntervalSince1970 * 1000)),
        ], shared: ["researcher", "claude", "pruefer"])
        let t = now.timeIntervalSince1970 * 1000
        func card(_ id: String, _ title: String, _ status: String, _ agent: String?, _ board: String, notes: String? = nil, ago: Double) -> WorkCard {
            WorkCard(id: id, title: title, status: status, agentId: agent, boardId: board, updatedAt: t - ago * 3_600_000, notes: notes)
        }
        let cards = [
            card("s1", "Widerrufs-Einwilligung im Checkout ergänzen", "review", "sundartha", "sundartha", ago: 3),
            card("s2", "Newsletter Oktober entwerfen", "running", "sp-newsletter", "sundartha", notes: "Frist \(due(3))", ago: 1),
            card("s3", "ElevenLabs-Speicherfrist klären bis \(due(5))", "todo", "sundartha", "hermes", ago: 20),
            card("s4", "Preisseite auf sundartha.com überarbeiten", "todo", "sp-website", "default", ago: 30),
            card("s5", "Rufnummernweg absichern", "ready", "sp-security", "sundartha", ago: 40),
            card("s6", "Alte Landingpage archivieren", "done", "sp-website", "sundartha", ago: 2),
            card("v1", "Power-BI-Anmeldung durch Antonio", "blocked", "powerbi", "powerbi", ago: 50),
            card("v2", "OneNumber-Report für KW 42, fällig \(due(4))", "todo", "sp-reporting", "vodafone", ago: 10),
            card("v3", "Telco-Radar: Tarife der Wettbewerber vergleichen", "todo", "sp-marktanalyse", "telco-radar", ago: 26),
            card("p1", "Steuererklärung abgeben", "todo", nil, "privat", ago: 5),
        ]
        return (registry, cards)
    }

    func loadDemoManyTodos() {
        let titles = ["Steuererklärung abgeben", "Friseurtermin vereinbaren", "Geschenk für Mama besorgen", "Fahrrad zur Inspektion bringen",
                      "Handyvertrag kündigen", "Stromrechnung prüfen", "Bücher in die Bibliothek bringen", "Reifenwechsel buchen",
                      "Passfoto machen lassen", "Wohnungsübergabe vorbereiten", "Datenbankzugang schließen"]
        today?.tasks = titles.enumerated().map { SenecaTask(id: "m\($0.offset)", title: $0.element, isDone: false) }
    }
    #endif
}
