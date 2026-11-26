import Foundation
import CryptoKit

protocol VertragSocket: AnyObject {
    func oeffnen()
    func senden(_ text: String) async throws
    func empfangen() async throws -> String
    func schliessen(code: Int)
    var schliessCode: Int? { get }
}

final class URLSessionVertragSocket: VertragSocket {
    private let task: URLSessionWebSocketTask
    init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 32 * 1024 * 1024
    }
    func oeffnen() { task.resume() }
    func senden(_ text: String) async throws { try await task.send(.string(text)) }
    func empfangen() async throws -> String {
        do {
            switch try await task.receive() {
            case .string(let s): return s
            case .data(let d): return String(decoding: d, as: UTF8.self)
            @unknown default: return ""
            }
        } catch {
            for _ in 0..<10 where task.closeCode == .invalid { try? await Task.sleep(for: .milliseconds(20)) }
            throw error
        }
    }
    func schliessen(code: Int) { task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil) }
    var schliessCode: Int? { task.closeCode == .invalid ? nil : task.closeCode.rawValue }
}

struct VertragGeraet {
    var id: String
    var publicKey: String
    var signiere: (Data) throws -> String

    init(schluessel: Curve25519.Signing.PrivateKey) {
        let pub = schluessel.publicKey.rawRepresentation
        id = SHA256.hash(data: pub).map { String(format: "%02x", $0) }.joined()
        publicKey = Self.base64url(pub)
        signiere = { Self.base64url(try schluessel.signature(for: $0)) }
    }
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
final class VertragVerbindung: SenecaVertrag {
    struct Einstellung {
        var url: URL
        var geraet: VertragGeraet
        var token: String
        var rechte: [String] = ["lesen", "schreiben"]
        var clientName = "Seneca Pocket"
        var clientVersion = "2.0.0"
        var faehigkeiten = ["werkzeug-ereignisse", "nur-antworttext"]
        var tokenSpeichern: (String) -> Void = { _ in }
        var halloFrist: Double = 20
        var pingAlle: Double = 25
        var sperre: (String) throws -> Void = { try SimulatorSperre.pruefe(adresse: $0) }
    }

    var aufEreignis: ((VertragEreignis) -> Void)?
    var aufGetrennt: ((VertragFehler) -> Void)?
    var aufZugang: ((VertragZugang) -> Void)?
    private(set) var angemeldet = false
    private(set) var rechte: [String] = []

    private let e: Einstellung
    private let socket: VertragSocket
    private var laeuft = 0
    private var naechsteId = 0
    private var wartende: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var fristen: [String: Task<Void, Never>] = [:]
    private var empfaenger: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var zuletzt = Date()

    init(_ einstellung: Einstellung, socket: VertragSocket? = nil) {
        e = einstellung
        self.socket = socket ?? URLSessionVertragSocket(url: einstellung.url)
    }

    func verbinde() async throws {
        try e.sperre(e.url.absoluteString)
        socket.oeffnen()
        zuletzt = Date()
        empfaenger = Task { [weak self] in await self?.lesen() }
        let hallo: [String: Any] = [
            "version": "1.1",
            "client": ["art": "app", "name": e.clientName, "version": e.clientVersion],
            "geraet": ["id": e.geraet.id, "publicKey": e.geraet.publicKey],
            "rechte": e.rechte, "faehigkeiten": e.faehigkeiten,
            "token": e.token,
        ]
        do {
            let antwort = try await rufe("vertrag.hallo", hallo, zeitlimit: e.halloFrist, id: "hallo")
            if let token = antwort["geraeteToken"] as? String, !token.isEmpty { e.tokenSpeichern(token) }
            rechte = antwort["rechte"] as? [String] ?? []
            aufZugang?(VertragZugang(rechte: rechte, admin: rechte.contains("admin") ? .gewaehrt : .nein))
            angemeldet = true
            starteLebenszeichen()
        } catch {
            beenden(code: 1000)
            throw error
        }
    }

    func trenne() {
        beenden(code: 1000)
        failAlle(.getrennt)
    }

    func lebt(frist: Double) async -> Bool {
        guard angemeldet else { return false }
        let marke = Date()
        try? await socket.senden("{\"t\":\"ping\"}")
        let ende = marke.addingTimeInterval(frist)
        while Date() < ende {
            if zuletzt > marke { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return zuletzt > marke
    }

    func rufe(_ fn: String, _ daten: [String: Any], zeitlimit: Double = 20) async throws -> [String: Any] {
        if fn != "vertrag.hallo", !angemeldet { throw VertragFehler.getrennt }
        return try await rufe(fn, daten, zeitlimit: zeitlimit, id: nil)
    }

    private func rufe(_ fn: String, _ daten: [String: Any], zeitlimit: Double, id vorgabe: String?) async throws -> [String: Any] {
        naechsteId += 1
        let id = vorgabe ?? "a\(naechsteId)"
        let rahmen: [String: Any] = ["t": "anfrage", "id": id, "fn": fn, "daten": daten]
        guard let data = try? JSONSerialization.data(withJSONObject: rahmen), let text = String(data: data, encoding: .utf8) else {
            throw VertragFehler.ungueltig("Ungültige Anfrage.")
        }
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any], Error>) in
            wartende[id] = c
            fristen[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(zeitlimit))
                guard !Task.isCancelled else { return }
                self?.erledige(id, .failure(VertragFehler.zeitlimit))
            }
            Task { [weak self] in
                do { try await self?.socket.senden(text) }
                catch { self?.erledige(id, .failure(VertragFehler.getrennt)) }
            }
        }
    }

    private func erledige(_ id: String, _ ergebnis: Result<[String: Any], Error>) {
        fristen.removeValue(forKey: id)?.cancel()
        guard let c = wartende.removeValue(forKey: id) else { return }
        c.resume(with: ergebnis)
    }

    private static func lies(_ text: String) async -> [String: Any]? {
        if text.utf8.count < 64_000 { return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] }
        return await Task.detached(priority: .userInitiated) { () -> [String: Any]? in
            (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        }.value
    }

    private func lesen() async {
        while !Task.isCancelled {
            do {
                let text = try await socket.empfangen()
                zuletzt = Date()
                guard let obj = await Self.lies(text), let t = obj["t"] as? String else { continue }
                switch t {
                case "antwort": antwort(obj)
                case "ereignis": ereignis(obj)
                default: break
                }
            } catch {
                if Task.isCancelled { return }
                verloren()
                return
            }
        }
    }

    private func antwort(_ o: [String: Any]) {
        guard let id = o["id"] as? String else { return }
        if o["ok"] as? Bool == true { erledige(id, .success(o["daten"] as? [String: Any] ?? [:])); return }
        let f = o["fehler"] as? [String: Any] ?? [:]
        let details = f["details"] as? [String: Any]
        let karte = (details?["card"] as? [String: Any]).map { KartenStand(status: $0["status"] as? String, aktualisiert: ($0["updatedAt"] as? NSNumber)?.doubleValue) }
        erledige(id, .failure(VertragFehler.antwort(code: f["code"] as? String ?? "UNBEKANNT", text: f["text"] as? String ?? "", anfrageId: details?["anfrageId"] as? String, karte: karte)))
    }

    private func ereignis(_ o: [String: Any]) {
        guard let name = o["name"] as? String else { return }
        let daten = o["daten"] as? [String: Any] ?? [:]
        if name == "vertrag.herausforderung" { signiere(daten); return }
        aufEreignis?(VertragEreignis(name: name, daten: daten, seq: (o["seq"] as? NSNumber)?.intValue ?? 0))
    }

    private func signiere(_ h: [String: Any]) {
        guard let s = h["zuSignieren"] as? String else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let signatur = try self.e.geraet.signiere(Data(s.utf8))
                _ = try await self.rufe("vertrag.signieren", ["signatur": signatur], zeitlimit: 30, id: "sig-" + UUID().uuidString.prefix(8))
            } catch {  }
        }
    }

    private func starteLebenszeichen() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.e.pingAlle))
                guard !Task.isCancelled, self.angemeldet else { return }
                if Date().timeIntervalSince(self.zuletzt) > self.e.pingAlle * 2.2 { self.verloren(); return }
                try? await self.socket.senden("{\"t\":\"ping\"}")
            }
        }
    }

    private func verloren() {
        let code = socket.schliessCode
        let fehler: VertragFehler = code == 4403 ? .nurLokal : .getrennt
        let warAngemeldet = angemeldet
        beenden(code: 1001)
        failAlle(fehler)
        if warAngemeldet { aufGetrennt?(fehler) }
    }

    private func beenden(code: Int) {
        angemeldet = false
        pingTask?.cancel(); pingTask = nil
        empfaenger?.cancel(); empfaenger = nil
        socket.schliessen(code: code)
    }

    private func failAlle(_ fehler: VertragFehler) {
        for id in Array(wartende.keys) { erledige(id, .failure(fehler)) }
    }
}
