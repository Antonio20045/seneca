import Foundation
import Combine
import CryptoKit
import Security
import OSLog

let tempoLog = Logger(subsystem: "de.antonio.senecapocket", category: "Tempo")
func tempo(_ step: String) {
    let ms = Int64(Date().timeIntervalSince1970 * 1000)
    tempoLog.notice("[TEMPO] \(ms, privacy: .public) \(step, privacy: .public)")
}

@MainActor
final class SenecaStore: ObservableObject {
    @Published var today: TodaySnapshot?
    @Published var connectionStatus = "Nicht verbunden"
    @Published var error: String?
    @Published var isConnected = false
    @Published private(set) var getrenntSeit: Date?
    @Published var isLoading = false
    @Published private(set) var isConfigured = false
    @Published private(set) var lastSync: Date?

    var clock: () -> Date = { Date() }
    var demo = false

    private var endpoint = ""
    private var sharedToken = ""
    private var sessionKey = Hauptagent.sitzung
    private(set) var daten: SenecaDaten?
    @Published private(set) var stand: SenecaStand?
    @Published private(set) var wartendeTodos: Set<String> = []
    @Published private(set) var neueTodos: [Handlung] = []
    @Published private(set) var ohneNetz = false
    @Published var abgleich: Abgleich?
    struct Abgleich: Equatable { var text: String; var ansehen = false }
    private var generation = UUID()
    private var answerWaiters: [String: CheckedContinuation<String, Error>] = [:]
    private var asks: [String: AskTracker] = [:]
    private var delivering: Set<String> = []
    private var subscribeRetry: Set<String> = []
    nonisolated static let alleRechte = ["lesen", "schreiben", "admin"]
    let chat = ChatService()
    private let gatewayLog = Logger(subsystem: "de.antonio.senecapocket", category: "Gateway")
    private let defaults = UserDefaults.standard

    init() {
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
                today = cached
                lastSync = cached.updatedAt
            }
        }
    }

    var isActive = true { didSet { if isActive { daten?.jetztVersuchen() } } }

    func addTodoHeute(_ title: String) {
        addTask(title, plan: DayLogic.dayKey(clock(), .current))
    }

    func addTask(_ title: String, plan: String? = nil) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        todo("anlegen", nil, ["titel": .text(t)].merging(plan.map { ["tag": JSONWert.text($0)] } ?? [:]) { a, _ in a })
    }


    func connect() async {
        guard !demo, isConfigured else { return }
        if daten == nil { daten = neueDaten() }
        guard let daten else { return }
        if daten.zustand == .aus { daten.starten() } else { daten.jetztVersuchen() }
        if await daten.verbindung.warteVerbunden(frist: daten.verbindung.regeln.antwortFristS), isConnected {
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
        d.$gestrichelt.sink { [weak self] h in
            self?.wartendeTodos = Set(h.filter { $0.art == "todo.erledigt" }.compactMap(\.ziel))
            self?.neueTodos = h.filter { $0.art == "todo.anlegen" }
        }.store(in: &zustandsAbos)
        d.$rechte.dropFirst().sink { [weak self] scopes in
            self?.chat.setAccess(rechte: scopes.compactMap { ["operator.read": "lesen", "operator.write": "schreiben"][$0] }, admin: .notGranted)
        }.store(in: &zustandsAbos)
        d.$zustand.dropFirst().sink { [weak self] z in self?.zustandGeaendert(z, gen) }.store(in: &zustandsAbos)
        d.$netz.sink { [weak self] da in self?.ohneNetz = !da }.store(in: &zustandsAbos)
        d.$letztesErgebnis.compactMap { $0 }.sink { [weak self] e in self?.nachErgebnis(e.handlung, e.ergebnis) }.store(in: &zustandsAbos)
        return d
    }

    private var zustandsAbos: Set<AnyCancellable> = []

    private func nachErgebnis(_ h: Handlung, _ e: HandlungsErgebnis) {
        let neu: Abgleich
        switch e {
        case .schonBeantwortet(let wahl, let geraet, let um):
            let f = stand?.braucht_dich?.first { $0.id == h.ziel }
            neu = Abgleich(text: "Schon beantwortet · " + HeuteTafelLogik.antwortZeile(f, SenecaStand.Antwort(wahl: wahl, geraet: geraet, zeit: um)))
        case .abgelehnt where h.art.hasPrefix("todo."):
            neu = Abgleich(text: (stand?.todos?.first { $0.id == h.ziel }?.titel).map { "\($0) · Ging nicht mehr" } ?? "Ging nicht mehr", ansehen: true)
        default: return
        }
        abgleich = neu
        Task { try? await Task.sleep(for: .seconds(5)); if abgleich == neu { abgleich = nil } }
    }

    func zeigeBeispiel(_ name: String) {
        stand = HeuteTafelLogik.beispiel(name)
        #if DEBUG
        guard let s = stand else { return }
        let cal = Calendar.current, tage = Double(cal.dateComponents([.day], from: cal.startOfDay(for: HeuteTafelLogik.datum(s.jetzt)), to: cal.startOfDay(for: Date())).day ?? 0)
        stand?.verlauf?.quittungen = s.verlauf?.quittungen?.map { var q = $0; q.von += tage * 86_400_000; q.bis += tage * 86_400_000; return q }
        #endif
    }

    func erledige(todo id: String) { todo("erledigt", id) }

    func verstehen(_ satz: String) async -> Verstanden? {
        let roh: Data?
        if demo { roh = Bundle.main.url(forResource: "Beispiel-Verstanden", withExtension: "json").flatMap { try? Data(contentsOf: $0) } }
        else { roh = try? JSONSerialization.data(withJSONObject: await daten?.rufe("seneca.verstehen", ["satz": satz]) ?? [:]) }
        return roh.flatMap { try? JSONDecoder().decode(Verstanden.self, from: $0) }
    }

    func todo(_ aktion: String, _ id: String? = nil, _ felder: [String: JSONWert] = [:]) {
        let wert: JSONWert? = felder.isEmpty ? nil : .objekt(felder)
        guard !demo else {
            if aktion == "erledigt", let id { wartendeTodos.insert(id) }
            if aktion == "wiederherstellen", let id { wartendeTodos.remove(id) }
            if aktion == "anlegen" { neueTodos.append(Handlung(kennung: UUID().uuidString, geraet: "demo", art: "todo.anlegen", wert: wert, zeit_geraet: 0, gesehen_revision: 0)) }
            return
        }
        daten?.handeln("todo." + aktion, ziel: id, wert: wert)
    }

    func rueckgaengig(_ ziel: String) { daten?.handeln("rueckgaengig", ziel: ziel) }

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
        if case .getrennt(let seit) = z { getrenntSeit = seit } else if z == .verbunden { getrenntSeit = nil }
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
        await loadToday()
    }

    var aufPraesenz: (([[String: Any]]) -> Void)?

    private func gatewayEreignis(_ name: String, _ payload: [String: Any]) {
        if name == "presence" { aufPraesenz?(payload["presence"] as? [[String: Any]] ?? []) }
        guard ["chat", "session.tool", "session.message"].contains(name), matchesSession(payload) else { return }
        receiveSessionEvent(name, payload)
    }

    func rufe(_ fn: String, params: [String: Any] = [:], timeout: Double = 20) async throws -> [String: Any] {
        guard let daten, isConnected else { throw SenecaError.offline }
        guard let fenster = Self.lesefenster[fn] else {
            let betroffen = fn.hasPrefix("sessions.") || fn == "chat.send" ? "sessions.list" : nil
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

    private static let lesefenster: [String: Double] = ["agents.list": 60, "sessions.list": 10]
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
        let destination = cacheKey
        isLoading = true
        defer { if generation == current { isLoading = false } }
        var failures: [String] = []
        var snapshot = today ?? TodaySnapshot(calendar: [], tasks: [], briefings: [], updatedAt: .distantPast)
        do {
            snapshot.jobs = SenecaPayloadParser.jobs(try await rufe("cron.list"))
        } catch { failures.append("Mitarbeiter") }
        if let result = try? await rufe("sessions.list", params: ["limit": 200, "configuredAgentsOnly": true]) {
            snapshot.sessions = SenecaPayloadParser.sessions(result)
        }
        if let result = try? await rufe("agents.list") { snapshot.agentNames = SenecaPayloadParser.agentNames(result) }
        guard generation == current else { return }
        snapshot.updatedAt = Date()
        merkeTag(snapshot, kennung: destination)
        today = snapshot
        lastSync = snapshot.updatedAt
        error = failures.isEmpty ? nil : "Nicht geladen: " + failures.joined(separator: ", ")
        if reloadAgain {
            reloadAgain = false
            isLoading = false
            Task { await self.loadToday() }
        }
    }

    var kalenderTermine: [KalenderTermin] {
        (stand?.wochenplan?.tage ?? []).flatMap { t in
            t.bloecke.filter { $0.art == "termin" }.map {
                KalenderTermin(id: $0.uid ?? $0.id, title: $0.titel, start: Date(timeIntervalSince1970: $0.start / 1000), end: Date(timeIntervalSince1970: $0.ende / 1000),
                               calendar: $0.detail?.kalender, place: $0.detail?.ort, note: $0.detail?.notiz)
            } + t.ganztag.map { KalenderTermin(id: "\(t.tag)-\($0)", title: $0, start: Date(timeIntervalSince1970: t.tag / 1000), end: Date(timeIntervalSince1970: t.tag / 1000 + 86_400), isAllDay: true) }
        }
    }
    var kalenderEintraege: [CalendarEntry] { KalenderParser.eintraege(kalenderTermine) }

    private var reloadAgain = false


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
        let id = idempotencyKey ?? VerlaufLogik.schluessel()
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

    func zuruecknehmen(_ id: String) async {
        guard let t = asks[id] else { return }
        for run in t.abortableRunIds { _ = try? await rufe("chat.abort", params: ["sessionKey": t.sessionKey, "agentId": AreasLogic.agentID(of: t.sessionKey), "runId": run, "discardPendingInput": true]) }
        finishAsk(id, .failure(SenecaError.stopped))
        chat.speicher.entferne(sitzung: t.sessionKey, schluessel: id)
    }

    func vorziehen(_ id: String) async {
        if let t = asks[id] { await abortAsk(sessionKey: t.sessionKey, ausser: id) }
    }

    func abortAsk(sessionKey key: String, ausser: String? = nil) async {
        let open = asks.filter { $0.value.sessionKey == key && $0.key != ausser }
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
            if !partial.isEmpty, let run = current.abortableRunIds.last {
                chat.speicher.angehalten["strom-" + run.lowercased()] = Date().timeIntervalSince(current.live.startedAt)
                chat.speicher.nimmStromEnde(sitzung: key, lauf: run, text: partial, frage: id) }
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
    func loadDemo(now: Date) {
        demo = true
        isConfigured = true
        zeigeBeispiel(ProcessInfo.processInfo.environment["SENECA_DEMO_STAND"] ?? "Beispiel-Stand")
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) - 1
        func job(_ id: String, _ name: String, _ agent: String, _ expr: String) -> AgentJob {
            AgentJob(id: id, name: name, agentId: agent, enabled: true, kind: "cron", expr: expr, tz: TimeZone.current.identifier)
        }
        let jobs = [
            job("a", "Sundartha Planung", "sundartha", "45 6 * * *"),
            job("b", "Morgen-Briefing mit Anruf", Hauptagent.id, "30 7 * * *"),
            job("d", "Sundartha Ideen", "sundartha", "0 17 * * \(weekday)"),
            job("g", "🌙 Abendbericht", Hauptagent.id, "0 19 * * *"),
        ]
        today = TodaySnapshot(calendar: [], tasks: [], briefings: [], updatedAt: now, jobs: jobs, leaders: ["sundartha": "Sundartha", "powerbi": "Vodafone"])
        lastSync = now
        isConnected = false
        connectionStatus = ProcessInfo.processInfo.environment["SENECA_DEMO_OFFLINE"] == "1" ? "Mac nicht erreichbar" : "Demo"
    }
    #endif
}
