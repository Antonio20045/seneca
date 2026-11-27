import Foundation
import Network
#if os(macOS)
import AppKit
#endif

public enum Verbindungszustand: Equatable, Sendable {
    case aus, verbindet, verbunden, getrennt(seit: Date), neuKoppeln(String)
}

public struct VerbindungsFehler: LocalizedError, Equatable, Sendable {
    public var code: String
    public var text: String
    public var anfrage: String?
    public var details: String?
    public var karteStatus: String?
    public var karteZeit: Double?
    public var errorDescription: String? { text }
    public static let offline = VerbindungsFehler(code: "OFFLINE", text: "Seneca ist gerade nicht erreichbar.")
}

struct Rahmen: @unchecked Sendable { let inhalt: [String: Any] }

@MainActor
public final class Verbindung {
    public struct Einstellung {
        public var adresse: String
        public var token: String
        public var profil: ClientProfil
        public var ablage: Schluesselablage
        public var sperre: (String) throws -> Void
        public init(adresse: String, token: String, profil: ClientProfil = .aktuell, ablage: Schluesselablage, sperre: @escaping (String) throws -> Void = { _ in }) {
            self.adresse = adresse; self.token = token; self.profil = profil; self.ablage = ablage; self.sperre = sperre
        }
    }

    public private(set) var zustand: Verbindungszustand = .aus {
        didSet {
            guard zustand != oldValue else { return }
            aufZustand?(zustand)
            guard zustand != .verbindet else { return }
            let w = wartende
            wartende = []
            for c in w { c.resume() }
        }
    }
    private var wartende: [CheckedContinuation<Void, Never>] = []
    public private(set) var letzterFehler: VerbindungsFehler?
    public var aufZustand: ((Verbindungszustand) -> Void)?
    public var aufEreignis: ((String, [String: Any]) -> Void)?
    public var aufVerbunden: (([String]) -> Void)?
    public var aufNetz: ((Bool) -> Void)?
    public var regeln = Verbindungsregeln() { didSet { schleife.regeln = regeln } }

    private let einstellung: Einstellung
    private var schleife = Wiederverbinden()
    private var socket: URLSessionWebSocketTask?
    private var generation = UUID()
    private var offen: [String: CheckedContinuation<Rahmen, Error>] = [:]
    private var handschlag: CheckedContinuation<Void, Error>?
    private var aufgaben: [Task<Void, Never>] = []
    private var warten: Task<Void, Never>?
    private var tickMs: Double = 30_000
    private var letzterRahmen = Date()
    private var aktiv = false
    private var netz: NWPathMonitor?

    public init(_ einstellung: Einstellung) {
        self.einstellung = einstellung
        #if os(macOS)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.jetztVersuchen() }
        }
        #endif
    }

    public func starten() {
        guard !aktiv else { return }
        aktiv = true
        let n = NWPathMonitor()
        n.pathUpdateHandler = { [weak self] pfad in
            let da = pfad.status == .satisfied
            Task { @MainActor in
                self?.aufNetz?(da)
                if da { self?.jetztVersuchen() }
            }
        }
        n.start(queue: DispatchQueue(label: "seneca.netz"))
        netz = n
        versuche()
    }

    public func stoppen() {
        aktiv = false
        netz?.cancel()
        netz = nil
        warten?.cancel()
        kappen(VerbindungsFehler.offline)
        zustand = .aus
    }

    public func jetztVersuchen() {
        guard aktiv, zustand != .verbunden, zustand != .verbindet else { return }
        if case .neuKoppeln = zustand { return }
        warten?.cancel()
        schleife.sofort()
        versuche()
    }

    public func warteVerbunden(frist: Double) async -> Bool {
        if zustand == .verbindet {
            let wache = Task { [weak self] in
                try? await Task.sleep(for: .seconds(frist))
                guard let self, !Task.isCancelled else { return }
                let w = self.wartende
                self.wartende = []
                for c in w { c.resume() }
            }
            await withCheckedContinuation { wartende.append($0) }
            wache.cancel()
        }
        return zustand == .verbunden
    }

    public func rufe(_ methode: String, _ params: [String: Any] = [:], frist: Double? = nil) async throws -> [String: Any] {
        guard zustand == .verbunden else { throw VerbindungsFehler.offline }
        return try await anfrage(methode, params, frist: frist ?? regeln.antwortFristS).inhalt
    }

    private func versuche() {
        warten?.cancel()
        zustand = .verbindet
        warten = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.oeffnen()
                self.schleife.verbunden()
            } catch let f as VerbindungsFehler {
                self.nachFehler(anmeldung: Wiederverbinden.istAnmeldefehler(f.code), f)
            } catch {
                self.nachFehler(anmeldung: false, VerbindungsFehler(code: "NETZ", text: error.localizedDescription))
            }
        }
    }

    private func nachFehler(anmeldung: Bool, _ f: VerbindungsFehler) {
        letzterFehler = f
        kappen(f)
        guard aktiv else { return }
        switch schleife.nachFehler(anmeldung: anmeldung) {
        case .neuKoppeln:
            zustand = .neuKoppeln(f.text)
        case .warte(let s):
            if case .getrennt = zustand {} else { zustand = .getrennt(seit: Date()) }
            warten = Task { [weak self] in
                try? await Task.sleep(for: .seconds(s))
                guard !Task.isCancelled, let self, self.aktiv else { return }
                self.versuche()
            }
        }
    }

    private func oeffnen() async throws {
        try einstellung.sperre(einstellung.adresse)
        guard var teile = URLComponents(string: einstellung.adresse), let host = teile.host, !host.isEmpty,
              let schema = teile.scheme?.lowercased(), ["http", "https", "ws", "wss"].contains(schema) else {
            throw VerbindungsFehler(code: "ADRESSE", text: "Die Adresse des Servers fehlt oder ist ungültig.")
        }
        teile.scheme = ["https", "wss"].contains(schema) ? "wss" : "ws"
        teile.path = "/"
        guard let url = teile.url else { throw VerbindungsFehler(code: "ADRESSE", text: "Die Adresse des Servers ist ungültig.") }
        kappen(nil)
        let gen = UUID()
        generation = gen
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 32 * 1024 * 1024
        socket = task
        letzterRahmen = Date()
        task.resume()
        aufgaben.append(Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    let roh = try await task.receive()
                    let daten: Data
                    switch roh {
                    case .data(let d): daten = d
                    case .string(let s): daten = Data(s.utf8)
                    @unknown default: continue
                    }
                    guard let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any] else { continue }
                    let rahmen = Rahmen(inhalt: objekt)
                    await self?.empfange(rahmen, gen)
                } catch {
                    await self?.abgerissen(gen, error)
                    return
                }
            }
        })
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in handschlag = c }
        guard generation == gen else { throw VerbindungsFehler.offline }
        letzterFehler = nil
        zustand = .verbunden
        wache(gen)
    }

    private func wache(_ gen: UUID) {
        aufgaben.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .milliseconds(Int(self.tickMs)))
                guard self.generation == gen, self.zustand == .verbunden else { return }
                if Date().timeIntervalSince(self.letzterRahmen) * 1000 > 2 * self.tickMs {
                    self.nachFehler(anmeldung: false, VerbindungsFehler(code: "STILLE", text: "Seneca antwortet nicht mehr."))
                    return
                }
            }
        })
    }

    private func abgerissen(_ gen: UUID, _ fehler: Error) {
        guard generation == gen else { return }
        if let handschlag {
            self.handschlag = nil
            handschlag.resume(throwing: VerbindungsFehler(code: "NETZ", text: fehler.localizedDescription))
            return
        }
        nachFehler(anmeldung: false, VerbindungsFehler(code: "NETZ", text: fehler.localizedDescription))
    }

    private func empfange(_ rahmen: Rahmen, _ gen: UUID) {
        guard generation == gen else { return }
        letzterRahmen = Date()
        let f = rahmen.inhalt
        if f["type"] as? String == "res", let id = f["id"] as? String, let c = offen.removeValue(forKey: id) {
            if f["ok"] as? Bool == true { c.resume(returning: Rahmen(inhalt: f["payload"] as? [String: Any] ?? [:])) }
            else { c.resume(throwing: Self.fehler(f["error"] as? [String: Any] ?? [:])) }
            return
        }
        guard f["type"] as? String == "event", let name = f["event"] as? String else { return }
        let inhalt = f["payload"] as? [String: Any] ?? [:]
        if name == "connect.challenge" {
            Task { await self.anmelden(inhalt, gen) }
            return
        }
        if name == "tick" { return }
        aufEreignis?(name, inhalt)
    }

    private func anmelden(_ herausforderung: [String: Any], _ gen: UUID) async {
        do {
            guard let nonce = herausforderung["nonce"] as? String, let ts = herausforderung["ts"] as? NSNumber else {
                throw VerbindungsFehler(code: "HANDSCHLAG", text: "Unvollständige Geräteprüfung.")
            }
            let geraet = try await GeraeteSchluessel.laden(einstellung.ablage)
            let konto = geraet.tokenKonto(adresse: einstellung.adresse)
            let gespeichert = await einstellung.ablage.lies(konto).flatMap { String(data: $0, encoding: .utf8) }
            let token = schleife.anmeldefehler > 0 ? einstellung.token : (gespeichert ?? einstellung.token)
            guard !token.isEmpty else { throw VerbindungsFehler(code: "UNAUTHORIZED", text: "Dieses Gerät ist noch nicht gekoppelt.") }
            let params = try geraet.anmeldung(profil: einstellung.profil, token: token, nonce: nonce, signedAt: ts.int64Value)
            let hallo = try await anfrage("connect", params, frist: regeln.antwortFristS, vorHandschlag: true).inhalt
            let auth = hallo["auth"] as? [String: Any]
            if let neu = auth?["deviceToken"] as? String { try? await einstellung.ablage.speichere(Data(neu.utf8), konto: konto) }
            if let t = ((hallo["policy"] as? [String: Any])?["tickIntervalMs"] as? NSNumber)?.doubleValue, t > 0 { tickMs = t }
            if schleife.anmeldefehler > 0, gespeichert != nil, auth?["deviceToken"] == nil { await einstellung.ablage.loesche(konto) }
            aufVerbunden?(auth?["scopes"] as? [String] ?? einstellung.profil.scopes)
            guard generation == gen else { return }
            handschlag?.resume()
            handschlag = nil
        } catch {
            guard generation == gen else { return }
            handschlag?.resume(throwing: error)
            handschlag = nil
        }
    }

    private func anfrage(_ methode: String, _ params: [String: Any], frist: Double, vorHandschlag: Bool = false) async throws -> Rahmen {
        guard let socket, vorHandschlag || zustand == .verbunden else { throw VerbindungsFehler.offline }
        let id = UUID().uuidString
        let daten = try JSONSerialization.data(withJSONObject: ["type": "req", "id": id, "method": methode, "params": params])
        let text = String(decoding: daten, as: UTF8.self)
        return try await withCheckedThrowingContinuation { c in
            offen[id] = c
            Task { [weak self] in
                do { try await socket.send(.string(text)) } catch { self?.offen.removeValue(forKey: id)?.resume(throwing: VerbindungsFehler.offline) }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(frist))
                self?.offen.removeValue(forKey: id)?.resume(throwing: VerbindungsFehler(code: "ZEITLIMIT", text: "Seneca antwortet nicht."))
            }
        }
    }

    private func kappen(_ fehler: VerbindungsFehler?) {
        generation = UUID()
        for a in aufgaben { a.cancel() }
        aufgaben = []
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        let alle = offen
        offen = [:]
        for c in alle.values { c.resume(throwing: fehler ?? VerbindungsFehler.offline) }
        if let h = handschlag { handschlag = nil; h.resume(throwing: fehler ?? VerbindungsFehler.offline) }
    }

    static func fehler(_ e: [String: Any]) -> VerbindungsFehler {
        let details = e["details"] as? [String: Any] ?? [:]
        let code = details["code"] as? String ?? e["code"] as? String ?? "FEHLER"
        let reason = details["reason"] as? String
        let anfrage = details["requestId"] as? String
        var text = e["message"] as? String ?? "Anfrage fehlgeschlagen."
        if code.uppercased().contains("PAIRING") {
            text = reason == "scope-upgrade" ? "Gib die neuen Rechte für dieses Gerät einmal frei." : "Dieses Gerät muss einmal freigegeben werden."
            if let anfrage { text += " Geräteanfrage: \(anfrage)" }
        }
        if code.uppercased().contains("TOKEN_MISMATCH") { text = "Die Kopplung dieses Geräts gilt nicht mehr. Bitte neu koppeln." }
        let karte = details["card"] as? [String: Any]
        return VerbindungsFehler(code: code, text: text, anfrage: anfrage, details: reason,
                                 karteStatus: karte?["status"] as? String, karteZeit: (karte?["updatedAt"] as? NSNumber)?.doubleValue)
    }
}
