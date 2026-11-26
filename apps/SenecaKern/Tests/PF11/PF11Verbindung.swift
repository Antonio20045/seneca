import Foundation
import Network
import Testing
@testable import SenecaVerbindung

actor Ablage: Schluesselablage {
    var werte: [String: Data] = [:]
    func lies(_ konto: String) async -> Data? { werte[konto] }
    func speichere(_ daten: Data, konto: String) async throws { werte[konto] = daten }
    func loesche(_ konto: String) async { werte.removeValue(forKey: konto) }
}

final class ProbeServer: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "probe")
    var verbindungen: [NWConnection] = []
    var revision = 1
    var anmeldungen = 0
    var handlungen: [[String: Any]] = []

    init() throws {
        let p = NWParameters.tcp
        p.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        listener = try NWListener(using: p, on: .any)
        listener.newConnectionHandler = { [unowned self] c in
            verbindungen.append(c)
            c.start(queue: queue)
            lesen(c)
            senden(["type": "event", "event": "connect.challenge", "payload": ["nonce": "n1", "ts": 1_000]], c)
        }
        let bereit = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { bereit.signal() } }
        listener.start(queue: queue)
        bereit.wait()
    }

    var adresse: String { "http://127.0.0.1:\(listener.port!.rawValue)" }

    func senden(_ o: [String: Any], _ c: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        c.send(content: try! JSONSerialization.data(withJSONObject: o), contentContext: .init(identifier: "t", metadata: [meta]), isComplete: true, completion: .idempotent)
    }

    func lesen(_ c: NWConnection) {
        c.receiveMessage { [unowned self] daten, _, _, fehler in
            if let daten, let f = try? JSONSerialization.jsonObject(with: daten) as? [String: Any], let id = f["id"] as? String {
                let p = f["params"] as? [String: Any] ?? [:]
                switch f["method"] as? String {
                case "connect":
                    anmeldungen += 1
                    senden(["type": "res", "id": id, "ok": true, "payload": ["type": "hello-ok", "auth": ["deviceToken": "g1", "scopes": p["scopes"] ?? []], "policy": ["tickIntervalMs": 15_000]]], c)
                case "seneca.stand":
                    let unveraendert = (p["revision"] as? Int) == revision
                    senden(["type": "res", "id": id, "ok": true, "payload": unveraendert ? ["schema": 1, "revision": revision, "jetzt": 1, "unveraendert": true] : ["schema": 1, "revision": revision, "jetzt": 1, "todos": [["id": "t\(revision)", "titel": "Rev \(revision)"]]]], c)
                case "seneca.handeln":
                    handlungen.append(p)
                    revision += 1
                    senden(["type": "res", "id": id, "ok": true, "payload": ["ergebnis": "angenommen", "revision": revision]], c)
                    senden(["type": "event", "event": "plugin.seneca.stand", "payload": ["revision": revision]], c)
                default:
                    senden(["type": "res", "id": id, "ok": false, "error": ["code": "UNKNOWN", "message": "unbekannt"]], c)
                }
            }
            if fehler == nil { lesen(c) }
        }
    }

    func abreissen() { queue.sync { for c in verbindungen { c.cancel() }; verbindungen = [] } }
}

@Suite("PF11 Verbindung gegen einen Probe-Server")
@MainActor
struct PF11Verbindung {
    func warte(_ bedingung: () -> Bool, sekunden: Double = 8) async {
        let ende = Date().addingTimeInterval(sekunden)
        while !bedingung(), Date() < ende { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test("Handschlag, Stand, Handlung bis zur Bestätigung, neuer Stand per Ereignis, nach Abriss wieder verbunden")
    func ablauf() async throws {
        let server = try ProbeServer()
        let ablage = Ablage()
        let d = SenecaDaten(.init(adresse: server.adresse, token: "geteilt", profil: .iphone, ablage: ablage), ordner: nil)
        d.starten()
        await warte { d.stand?.revision == 1 }
        #expect(d.zustand == .verbunden)
        #expect(d.rechte == ClientProfil.iphone.scopes)
        #expect(await ablage.werte.keys.contains { $0.hasPrefix("device-token:127.0.0.1:") })
        let h = try #require(d.handeln("todo.erledigt", ziel: "t1"))
        await warte { !d.istGestrichelt(h.kennung) && d.stand?.revision == 2 }
        #expect(d.letztesErgebnis?.ergebnis == .angenommen)
        #expect(d.stand?.todos?.first?.id == "t2")
        #expect(server.handlungen.first?["kennung"] as? String == h.kennung)
        #expect(server.handlungen.first?["gesehen_revision"] as? Int == 1)
        server.abreissen()
        await warte { if case .getrennt = d.zustand { return true } else { return false } }
        await warte { d.zustand == .verbunden && server.anmeldungen == 2 }
        #expect(server.anmeldungen == 2)
        d.stoppen()
    }
}
