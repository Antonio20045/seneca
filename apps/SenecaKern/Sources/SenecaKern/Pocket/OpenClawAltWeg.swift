import Foundation
import CryptoKit
import OSLog

@MainActor
final class OpenClawAltWeg: SenecaVertrag {
    nonisolated static let alleScopes = ["operator.admin", "operator.read", "operator.write", "operator.approvals", "operator.questions", "operator.pairing"]
    nonisolated static let baseScopes = ["operator.read", "operator.write"]
    nonisolated static let connectCaps = ["chat-only-assistant-text", "tool-events"]
    nonisolated static let clientKennung = ClientProfil.aktuell.kennung
    nonisolated static let profil = ClientProfil.aktuell

    var aufEreignis: ((VertragEreignis) -> Void)?
    var aufGetrennt: ((VertragFehler) -> Void)?
    var aufZugang: ((VertragZugang) -> Void)?

    private let log = Logger(subsystem: "de.antonio.senecapocket", category: "Gateway")
    private let endpoint: String
    private let sperre: (String) throws -> Void
    private let sharedToken: String
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var connectionWaiter: CheckedContinuation<Void, Error>?
    private var handshakeDeadline: Task<Void, Never>?
    private var handshakeStarted = false
    private var generation = UUID()
    private var pingTask: Task<Void, Never>?
    private var lastFrameAt = Date()
    private var verbunden = false
    private var scopes = OpenClawAltWeg.alleScopes
    private var adminPausedUntil = Date.distantPast
    private var useSharedTokenOnce = false
    private var adminStand: VertragZugang.Admin = .unbekannt

    init(adresse: String, zugangsschluessel: String, ohneAdminAnfrage: Bool = false,
         sperre: @escaping (String) throws -> Void = { try SimulatorSperre.pruefe(adresse: $0) }) {
        self.sperre = sperre
        endpoint = adresse
        sharedToken = zugangsschluessel
        if ohneAdminAnfrage { adminPausedUntil = .distantFuture }
    }

    func verbinde() async throws { try await openConnectionWithFallback() }

    func trenne() {
        kappen()
        failPending()
        finishHandshake(.failure(SenecaError.message("Verbindung beendet.")))
    }

    func rufe(_ fn: String, _ daten: [String: Any], zeitlimit: Double) async throws -> [String: Any] {
        guard let alt = VertragNamen.neuZuAlt[fn] else { throw VertragFehler.antwort(code: "UNBEKANNT", text: "Funktion nicht im Vertrag: \(fn)", anfrageId: nil) }
        return try await request(alt, params: daten, timeout: zeitlimit)
    }

    func lebt(frist: Double) async -> Bool {
        guard let socket else { return false }
        return await Self.ping(socket, timeout: frist)
    }

    private func kappen() {
        generation = UUID()
        pingTask?.cancel()
        pingTask = nil
        receiver?.cancel()
        receiver = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        verbunden = false
        handshakeStarted = false
    }

    private func startPing(_ task: URLSessionWebSocketTask, generation gen: UUID) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ZustellPlan.pingIntervall))
                guard !Task.isCancelled, let self, self.generation == gen else { return }
                guard self.verbunden else { continue }
                if await Self.ping(task, timeout: ZustellPlan.pongFrist) { continue }
                guard self.generation == gen, self.verbunden else { return }
                if Date().timeIntervalSince(self.lastFrameAt) < ZustellPlan.pongFrist { continue }
                self.log.info("ping: kein Pong, verbinde sofort neu")
                self.kappen()
                self.failPending()
                self.finishHandshake(.failure(SenecaError.offline))
                self.aufGetrennt?(.getrennt)
                return
            }
        }
    }

    private nonisolated static func ping(_ task: URLSessionWebSocketTask, timeout: Double) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let einmal = EinmalAntwort()
            task.sendPing { error in einmal.feuere { c.resume(returning: error == nil) } }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                einmal.feuere { c.resume(returning: false) }
            }
        }
    }

    private func openConnectionWithFallback() async throws {
        try sperre(endpoint)
        let askAdmin = Date() >= adminPausedUntil
        scopes = askAdmin ? Self.alleScopes : Self.baseScopes
        var schleife = ConnectSchleife()
        for _ in 0..<ConnectSchleife.maxVersuche {
            do {
                try await openConnection()
                return
            } catch SenecaError.refused(let refusal) {
                let schritt = schleife.schritt(refusal, askedAdmin: scopes.contains("operator.admin"))
                let decision = schritt.entscheidung
                log.info("connect refused \(refusal.code, privacy: .public) \(refusal.reason ?? "-", privacy: .public) -> \(String(describing: decision), privacy: .public)")
                switch decision {
                case .retrySharedToken:
                    await Schluesselbund.loescheAbseits(await deviceTokenAccount(admin: true))
                    useSharedTokenOnce = true
                case .retryWithoutAdmin(let awaiting):
                    adminPausedUntil = Date().addingTimeInterval(10 * 60)
                    scopes = Self.baseScopes
                    adminStand = awaiting ? .wartet(anfrageId: refusal.requestId) : .nein
                    aufZugang?(VertragZugang(rechte: nil, admin: adminStand))
                case .repair:
                    await Schluesselbund.loescheGeraeteTokenAbseits(adresse: endpoint)
                    useSharedTokenOnce = true
                    if let pause = schritt.pause { try? await Task.sleep(for: .seconds(pause)) }
                case .giveUp:
                    throw SenecaError.refused(refusal)
                }
            }
        }
        try await openConnection()
    }

    private func deviceTokenAccount(admin: Bool) async -> String {
        let origin = URLComponents(string: endpoint)?.host ?? endpoint
        let publicKey = await Schluesselbund.liesAbseits("device-key").flatMap { try? Curve25519.Signing.PrivateKey(rawRepresentation: $0) }?.publicKey.rawRepresentation ?? Data()
        let deviceID = SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
        return "device-token:\(origin):\(deviceID)" + (admin ? ":admin" : "")
    }

    private func openConnection() async throws {
        try sperre(endpoint)
        guard var parts = URLComponents(string: endpoint),
              let host = parts.host, !host.isEmpty,
              ["http", "https", "ws", "wss"].contains(parts.scheme?.lowercased() ?? "") else {
            throw SenecaError.message("Trage die private HTTPS-Adresse deines Macs in den Einstellungen ein.")
        }
        if parts.user != nil || parts.password != nil || parts.query != nil || parts.fragment != nil {
            throw SenecaError.message("Die Server-Adresse darf keine Zugangsdaten, Parameter oder Fragmente enthalten.")
        }
        let originalScheme = parts.scheme!.lowercased()
        if originalScheme == "http" || originalScheme == "ws" {
            guard ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) else {
                throw SenecaError.message("Auf dem iPhone wird eine private HTTPS-Adresse benötigt, z. B. über Tailscale Serve.")
            }
        }
        parts.scheme = ["https", "wss"].contains(originalScheme) ? "wss" : "ws"
        parts.path = "/"
        guard let url = parts.url else { throw SenecaError.message("Ungültige Server-Adresse.") }
        generation = UUID()
        let currentGeneration = generation
        handshakeStarted = false
        tempo("socket öffnen")
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 32 * 1024 * 1024
        socket = task
        lastFrameAt = Date()
        task.resume()
        startPing(task, generation: currentGeneration)
        receiver = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let frame = try await task.receive()
                    guard let self, self.generation == currentGeneration else { return }
                    self.lastFrameAt = Date()
                    let data: Data
                    switch frame {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    self.receive(object)
                } catch {
                    guard let self, self.generation == currentGeneration, !Task.isCancelled else { return }
                    let warVerbunden = self.verbunden
                    self.verbunden = false
                    self.failPending()
                    self.finishHandshake(.failure(error))
                    if warVerbunden { self.aufGetrennt?(.getrennt) }
                    return
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectionWaiter = continuation
            handshakeDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                self.finishHandshake(.failure(SenecaError.message("Der Mac antwortet nicht.")))
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func receive(_ frame: [String: Any]) {
        if frame["type"] as? String == "res", let id = frame["id"] as? String,
           let continuation = pending.removeValue(forKey: id) {
            deadlines.removeValue(forKey: id)?.cancel()
            if frame["ok"] as? Bool == true {
                continuation.resume(returning: frame["payload"] as? [String: Any] ?? [:])
            } else {
                let e = frame["error"] as? [String: Any] ?? [:]
                let details = e["details"] as? [String: Any] ?? [:]
                let code = details["code"] as? String ?? e["code"] as? String ?? ""
                var message = e["message"] as? String ?? "Anfrage fehlgeschlagen."
                let request = details["requestId"] as? String
                let reason = details["reason"] as? String
                if code.uppercased().contains("PAIRING") {
                    message = reason == "scope-upgrade"
                        ? "Gib die neuen Rechte für dieses iPhone einmal auf dem Mac frei."
                        : "Dieses iPhone muss einmal auf deinem Mac freigegeben werden."
                    if let request { message += " Geräteanfrage: \(request)" }
                }
                var refusal = GatewayRefusal(code: code, reason: reason, requestId: request, message: message)
                refusal.readCard(fromError: e)
                continuation.resume(throwing: SenecaError.refused(refusal))
            }
            return
        }
        guard frame["type"] as? String == "event", let event = frame["event"] as? String else { return }
        let payload = frame["payload"] as? [String: Any] ?? [:]
        if event == "connect.challenge", !handshakeStarted {
            tempo("challenge erhalten")
            handshakeStarted = true
            let current = generation
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.authenticate(payload)
                    guard self.generation == current else { return }
                    self.verbunden = true
                    tempo("handshake fertig")
                    self.finishHandshake(.success(()))
                } catch {
                    guard self.generation == current else { return }
                    self.receiver?.cancel()
                    self.finishHandshake(.failure(error))
                    self.socket?.cancel(with: .policyViolation, reason: nil)
                }
            }
            return
        }
        let daten = payload
        let name: String
        switch event {
        case "chat": name = "chat.strom"
        case "agent", "session.tool": name = "chat.werkzeug"
        case "session.message": name = "sitzung.nachricht"
        default: return
        }
        aufEreignis?(VertragEreignis(name: name, daten: daten, seq: 0))
    }

    private func authenticate(_ challenge: [String: Any]) async throws {
        guard let nonce = challenge["nonce"] as? String,
              let timestamp = challenge["ts"] as? NSNumber else {
            throw SenecaError.message("Unvollständige Geräteprüfung.")
        }
        let origin = URLComponents(string: endpoint)?.host ?? endpoint
        let privateKey = try await Schluesselbund.geraeteSchluesselAbseits()
        let publicKey = privateKey.publicKey.rawRepresentation
        let deviceID = SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
        let scopes = self.scopes
        let deviceTokenAccount = "device-token:\(origin):\(deviceID)" + (scopes.contains("operator.admin") ? ":admin" : "")
        let storedToken = useSharedTokenOnce ? nil : await Schluesselbund.liesAbseits(deviceTokenAccount).flatMap { String(data: $0, encoding: .utf8) }
        var token = storedToken ?? sharedToken
        #if DEBUG
        if ProcessInfo.processInfo.environment["SENECA_GATEWAY_TOKEN"]?.isEmpty == false, !sharedToken.isEmpty { token = sharedToken }
        #endif
        guard !token.isEmpty else {
            throw SenecaError.message("Hinterlege deinen Seneca-Zugangsschlüssel in den Einstellungen.")
        }
        let signedAt = timestamp.int64Value
        let signingPayload = ["v3", deviceID, Self.profil.kennung, "ui", "operator", scopes.joined(separator: ","), String(signedAt), token, nonce, Self.profil.platform, Self.profil.deviceFamily].joined(separator: "|")
        let signature = try privateKey.signature(for: Data(signingPayload.utf8))
        let params: [String: Any] = [
            "minProtocol": 4, "maxProtocol": 4,
            "client": ["id": Self.profil.kennung, "displayName": Self.profil.anzeigename, "version": "2.0.0", "platform": Self.profil.platform, "deviceFamily": Self.profil.deviceFamily, "mode": "ui"],
            "role": "operator", "scopes": scopes,
            "caps": Self.connectCaps, "commands": [], "permissions": [:],
            "auth": ["token": token], "locale": "de-DE", "userAgent": Self.profil.userAgent,
            "device": ["id": deviceID, "publicKey": VertragGeraet.base64url(publicKey), "signature": VertragGeraet.base64url(signature), "signedAt": signedAt, "nonce": nonce]
        ]
        let hello = try await request("connect", params: params)
        useSharedTokenOnce = false
        let auth = hello["auth"] as? [String: Any]
        if let issued = auth?["deviceToken"] as? String {
            try await Schluesselbund.speichereAbseits(Data(issued.utf8), konto: deviceTokenAccount)
        }
        let granted = auth?["scopes"] as? [String] ?? scopes
        if granted.contains("operator.admin") { adminStand = .gewaehrt; adminPausedUntil = .distantPast }
        else if case .wartet = adminStand {}
        else { adminStand = .nein }
        var rechte: [String] = []
        if granted.contains("operator.read") { rechte.append("lesen") }
        if granted.contains("operator.write") { rechte.append("schreiben") }
        if granted.contains("operator.admin") { rechte.append("admin") }
        aufZugang?(VertragZugang(rechte: rechte, admin: adminStand))
    }

    private func finishHandshake(_ result: Result<Void, Error>) {
        handshakeDeadline?.cancel()
        handshakeDeadline = nil
        connectionWaiter?.resume(with: result)
        connectionWaiter = nil
    }

    private func request(_ method: String, params: [String: Any] = [:], timeout: Double = 20) async throws -> [String: Any] {
        guard let socket else { throw SenecaError.offline }
        if method != "connect", !verbunden { throw SenecaError.offline }
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["type": "req", "id": id, "method": method, "params": params])
        guard let string = String(data: data, encoding: .utf8) else { throw SenecaError.message("Ungültige Anfrage.") }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            deadlines[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled, let self else { return }
                self.deadlines.removeValue(forKey: id)
                self.pending.removeValue(forKey: id)?.resume(throwing: SenecaError.offline)
            }
            Task {
                do { try await socket.send(.string(string)) }
                catch {
                    self.deadlines.removeValue(forKey: id)?.cancel()
                    self.pending.removeValue(forKey: id)?.resume(throwing: SenecaError.offline)
                }
            }
        }
    }

    private func failPending() {
        for task in deadlines.values { task.cancel() }
        deadlines.removeAll()
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values { continuation.resume(throwing: SenecaError.offline) }
    }
}

private final class EinmalAntwort: @unchecked Sendable {
    private let lock = NSLock()
    private var gefeuert = false
    func feuere(_ aktion: () -> Void) {
        lock.lock()
        let erster = !gefeuert
        gefeuert = true
        lock.unlock()
        if erster { aktion() }
    }
}
