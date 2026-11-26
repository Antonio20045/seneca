import Foundation
import Network
import CryptoKit

final class DemoGateway: @unchecked Sendable {
    enum Modus {
        case normal
        case kopplung
    }

    static let anfrageNummer = "A-4711"
    static let geraeteToken = "g1.demo-geraetetoken"

    let modus: Modus
    let wortPause: Double
    let schrittPause: Double
    private(set) var port: UInt16 = 0
    var url: String { "http://127.0.0.1:\(port)" }

    private let queue = DispatchQueue(label: "seneca.demo-gateway")
    private let lock = NSLock()
    private var listener: NWListener?
    private var verbindungen: [ObjectIdentifier: Verbindung] = [:]
    private var protokoll: [(fn: String, daten: [String: Any])] = []
    private var verlauf: [String: [[String: Any]]] = [:]
    private var laeufe: [String: Lauf] = [:]
    private var zaehler = 0
    private var uebersichtKarten: [[String: Any]]?
    private var gesehenIds: [String: Double] = [:]
    private var angelegteTermine: [[String: Any]] = []
    private var entschieden: [String: String] = [:]
    private var zurueckgestellt: [String: Double] = [:]
    private var neueEntscheidung = false
    func legeNeueEntscheidungAn() { lock.withLock { neueEntscheidung = true } }
    private var projektFelder: [String: [String: Any]]?
    private var projektRevision = 1
    private var einstellungen: [String: [String: Any]] = [:]
    private var kontextLeer: [String: Int] = [:]
    private var pins: [[String: Any]] = []
    private var bewertungen: [String: [String: [String: Any]]] = [:]
    private let speicher: URL?
    let ansichten: Bool
    let leer: Bool
    let htmlServer = TestHtmlServer()

    private final class Verbindung {
        let c: NWConnection
        var publicKey: String?
        var seq = 0
        init(_ c: NWConnection) { self.c = c }
    }
    private struct Lauf { var sessionKey: String; var abgebrochen = false; var laeuft = true }

    init(modus: Modus = .normal, wortPause: Double = 0.07, schrittPause: Double = 1.2, vorlauf: Int = 0, ansichten: Bool = false, speicher: URL? = nil, leer: Bool = false) {
        self.leer = leer
        self.modus = modus
        self.wortPause = wortPause
        self.schrittPause = schrittPause
        self.ansichten = ansichten
        self.speicher = speicher?.appendingPathComponent("demo-ansichten.json")
        verlauf["agent:main:main"] = Self.langerVerlauf(vorlauf) + Self.beispielVerlauf() + (ansichten ? Self.ansichtenVerlauf() : []) + Self.schaufensterVerlauf()
        let vor = Self.jetztMs()
        verlauf["agent:alpha-lead:main"] = [Self.zeile("user", "Wie weit ist der Plan für Projekt Alpha?", id: "al-1", ms: vor - 7_200_000, key: "al-1"),
                                            Self.zeile("assistant", "Der Plan steht zu **drei Vierteln**. Offen sind noch der Lieferant und die Abnahme.", id: "al-2", ms: vor - 7_190_000, key: nil)]
        verlauf["agent:haus-lead:main"] = [Self.zeile("user", "Was steht im Haushalt diese Woche an?", id: "ha-1", ms: vor - 86_400_000, key: "ha-1"),
                                           Self.zeile("assistant", "Diese Woche: Preise vergleichen und den Staubsauger entscheiden.", id: "ha-2", ms: vor - 86_390_000, key: nil)]
        ladeAnsichtenSpeicher()
    }

    func starte(port festerPort: UInt16? = nil) throws {
        let ws = NWProtocolWebSocket.Options()
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: festerPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any)
        let bereit = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { [weak self, weak l] state in
            if case .ready = state { self?.port = l?.port?.rawValue ?? 0; bereit.signal() }
            if case .failed = state { bereit.signal() }
        }
        l.newConnectionHandler = { [weak self] c in self?.neu(c) }
        l.start(queue: queue)
        guard bereit.wait(timeout: .now() + 5) == .success, port != 0 else { throw URLError(.cannotConnectToHost) }
        listener = l
        SimulatorSperre.meldeDemoAn(self, adresse: url)
        try htmlServer.starte()
    }

    func stoppe() {
        SimulatorSperre.meldeDemoAb(self)
        htmlServer.stoppe()
        listener?.cancel()
        listener = nil
        lock.lock(); let alle = verbindungen.values; verbindungen = [:]; lock.unlock()
        for v in alle { v.c.cancel() }
    }

    var verlaufVerzug: TimeInterval {
        get { lock.withLock { _verlaufVerzug } }
        set { lock.withLock { _verlaufVerzug = newValue } }
    }
    private var _verlaufVerzug: TimeInterval = 0
    private struct Paket: @unchecked Sendable { let daten: [String: Any] }

    func empfangeneAnfragen() -> [(fn: String, daten: [String: Any])] {
        lock.lock(); defer { lock.unlock() }
        return protokoll
    }

    private func neu(_ c: NWConnection) {
        let v = Verbindung(c)
        lock.lock(); verbindungen[ObjectIdentifier(c)] = v; lock.unlock()
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.lock.lock(); self?.verbindungen[ObjectIdentifier(c)] = nil; self?.lock.unlock()
            default: break
            }
        }
        c.start(queue: queue)
        lesen(v)
    }

    private func lesen(_ v: Verbindung) {
        v.c.receiveMessage { [weak self, weak v] data, _, _, error in
            guard let self, let v else { return }
            if let data, !data.isEmpty { self.verarbeite(data, v) }
            if error == nil { self.lesen(v) } else { v.c.cancel() }
        }
    }

    private func senden(_ o: [String: Any], _ v: Verbindung) {
        guard let data = try? JSONSerialization.data(withJSONObject: o) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "text", metadata: [meta])
        v.c.send(content: data, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func antwort(_ id: String, _ daten: [String: Any] = [:], _ v: Verbindung) {
        senden(["t": "antwort", "id": id, "ok": true, "daten": daten], v)
    }

    private func fehler(_ id: String, _ code: String, _ text: String, details: [String: Any]? = nil, _ v: Verbindung) {
        var f: [String: Any] = ["code": code, "text": text]
        if let details { f["details"] = details }
        senden(["t": "antwort", "id": id, "ok": false, "fehler": f], v)
    }

    private func ereignis(_ name: String, _ daten: [String: Any], _ v: Verbindung) {
        lock.lock(); v.seq += 1; let s = v.seq; lock.unlock()
        senden(["t": "ereignis", "name": name, "seq": s, "daten": daten], v)
    }

    private func verarbeite(_ data: Data, _ v: Verbindung) {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let t = o["t"] as? String else { return }
        if t == "ping" { senden(["t": "pong"], v); return }
        guard t == "anfrage", let id = o["id"] as? String, let fn = o["fn"] as? String else { return }
        let daten = o["daten"] as? [String: Any] ?? [:]
        lock.lock(); protokoll.append((fn, daten)); lock.unlock()

        switch fn {
        case "vertrag.hallo":
            if modus == .kopplung {
                fehler(id, "KOPPLUNG_NOETIG", "Dieses Gerät muss freigegeben werden.", details: ["anfrageId": Self.anfrageNummer], v)
                return
            }
            v.publicKey = (daten["geraet"] as? [String: Any])?["publicKey"] as? String
            ereignis("vertrag.herausforderung", ["nonce": "n-demo", "zuSignieren": "demo-herausforderung", "gueltigBis": 4_000_000_000_000], v)
        case "vertrag.signieren":
            guard let pub = v.publicKey, let sig = daten["signatur"] as? String, Self.gueltig(signatur: sig, text: "demo-herausforderung", publicKey: pub) else {
                fehler("hallo", "NICHT_ANGEMELDET", "Die Signatur stimmt nicht.", v)
                fehler(id, "NICHT_ANGEMELDET", "Die Signatur stimmt nicht.", v)
                return
            }
            antwort("hallo", ["version": "1.1.0", "geraeteToken": Self.geraeteToken, "rechte": ["lesen", "schreiben"],
                              "server": ["name": "Demo-Gateway", "version": "1"], "standardSitzung": "agent:main:main"], v)
            antwort(id, ["ok": true], v)
        case "sitzung.abonnieren", "sitzungen.abonnieren", "sitzung.abbestellen":
            antwort(id, ["ok": true], v)
        case "sitzung.beschreibung":
            antwort(id, ["session": ["sessionId": "demo", "totalTokens": 12_000, "contextTokens": 1_000_000]], v)
        case "chat.verlauf":
            let key = daten["sessionKey"] as? String ?? "agent:main:main"
            lock.lock(); var rows = verlauf[key] ?? []; lock.unlock()
            if rows.isEmpty, !leer, let r = key.range(of: ":cron:") { rows = Self.cronVerlauf(jobId: String(key[r.upperBound...])) }
            let fertig: [String: Any] = ["messages": rows, "hasMore": false, "nextOffset": rows.count]
            let verzug = verlaufVerzug
            guard verzug > 0 else { antwort(id, fertig, v); break }
            let paket = Paket(daten: fertig)
            Task.detached { [weak self] in
                try? await Task.sleep(for: .seconds(verzug))
                self?.antwort(id, paket.daten, v)
            }
        case "chat.senden":
            sende(id, daten, v)
        case "chat.abbrechen":
            brich(id, daten, v)
        case "widget.dokument":
            widgetDokument(id, daten, v)
        case "seneca.pins":
            antwort(id, ["pins": lock.withLock { pins }], v)
        case "seneca.pins.setzen":
            antwort(id, ["ok": true, "name": pinSetzen(daten)], v)
        case "seneca.pins.entfernen":
            let name = daten["name"] as? String ?? ""
            lock.withLock { pins.removeAll { ($0["name"] as? String) == name } }
            speichereAnsichten()
            antwort(id, ["ok": true], v)
        case "seneca.bewerten":
            guard let agent = daten["agentId"] as? String, let karte = daten["kartenId"] as? String, !agent.isEmpty, !karte.isEmpty,
                  let urteil = daten["urteil"] as? String, urteil == "passt" || urteil == "passt_nicht" else {
                fehler(id, "UNGUELTIG", "agentId, kartenId und urteil (passt oder passt_nicht) sind nötig.", v)
                return
            }
            lock.withLock { bewertungen[agent, default: [:]][karte] = ["urteil": urteil, "am": Date().timeIntervalSince1970 * 1000] }
            speichereAnsichten()
            antwort(id, ["ok": true], v)
        case "seneca.bewertungen":
            antwort(id, ["agenten": bewertungsListe()], v)
        case "seneca.datei":
            let pfad = daten["pfad"] as? String ?? ""
            if let d = dateiAntwort(pfad) { antwort(id, d, v) } else { fehler(id, "NICHT_GEFUNDEN", "Datei nicht gefunden: \(pfad)", v) }
        case "karten.liste", "auftraege.liste", "agenten.liste", "seneca.kalender", "seneca.gesehen", "seneca.gesehen.setzen", "seneca.bereiche",
             "seneca.projekte", "seneca.entscheidungen", "sitzungen.liste", "karte.anlegen", "karte.aendern", "karte.verschieben",
             "karte.kommentieren", "karte.starten", "seneca.projekte.speichern", "modelle.liste", "seneca.konten", "verbrauch.stand", "sitzung.einstellen", "seneca.kontext.neu", "sitzung.anlegen",
             "seneca.kalender.anlegen", "seneca.entscheidung.treffen", "seneca.entscheidung.spaeter", "auftrag.laeufe", "auftrag.starten":
            antwort(id, uebersicht(fn, daten), v)
        default:
            if fn.hasPrefix("seneca.") || fn.hasSuffix(".liste") { antwort(id, ["ok": true], v) }
            else { fehler(id, "UNBEKANNT", "Im Demo-Gateway nicht vorhanden: \(fn)", v) }
        }
    }

    static func gueltig(signatur: String, text: String, publicKey: String) -> Bool {
        func roh(_ s: String) -> Data? {
            var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            return Data(base64Encoded: b)
        }
        guard let p = roh(publicKey), let s = roh(signatur), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: p) else { return false }
        return key.isValidSignature(s, for: Data(text.utf8))
    }

    private func sende(_ id: String, _ daten: [String: Any], _ v: Verbindung) {
        let session = daten["sessionKey"] as? String ?? "agent:main:main"
        let schluessel = daten["idempotencyKey"] as? String ?? UUID().uuidString
        let nachricht = daten["message"] as? String ?? ""
        let frage = ChatLogic.stripPhoneHint(nachricht)
        let nun = Date().timeIntervalSince1970 * 1000
        lock.lock()
        let schonDa = laeufe[schluessel] != nil
        let eintrag = Self.zeile("user", nachricht, id: "u-\(schluessel)", ms: nun, key: schluessel + ":user")
        if !schonDa {
            laeufe[schluessel] = Lauf(sessionKey: session)
            verlauf[session, default: []].append(eintrag)
        }
        lock.unlock()
        antwort(id, ["runId": schluessel, "status": schonDa ? "in_flight" : "started"], v)
        guard !schonDa else { return }
        ereignis("sitzung.nachricht", ["sessionKey": session, "message": eintrag, "messageId": "u-\(schluessel)", "runId": schluessel], v)
        let recherche = frage.lowercased().contains("recherchiere")
        let text = recherche ? Self.rechercheAntwort : frage.lowercased().contains("karte") ? Self.kartenAntwort : Self.beispielAntwort(frage)
        Task.detached { [weak self] in
            if recherche { await self?.arbeite(run: schluessel, session: session, v) }
            await self?.strom(text, run: schluessel, session: session, v)
        }
    }

    private func arbeite(run: String, session: String, _ v: Verbindung) async {
        for (i, schritt) in Self.rechercheSchritte.enumerated() {
            try? await Task.sleep(for: .seconds(schrittPause))
            let weg = lock.withLock { laeufe[run]?.abgebrochen ?? true }
            if weg { return }
            var bloecke: [[String: Any]] = []
            if i == 0 { bloecke.append(["type": "thinking", "thinking": "Erst die Quellen sichten, dann die Notizen lesen und zuletzt den Stand im Git prüfen."]) }
            bloecke.append(["type": "toolCall", "id": "t-\(run)-\(i)", "name": schritt.name, "arguments": schritt.args])
            let nun = Date().timeIntervalSince1970 * 1000
            lock.withLock {
                verlauf[session, default: []].append(["role": "assistant", "timestamp": nun, "content": bloecke,
                                                      "__openclaw": ["id": "w-\(run)-\(i)", "runId": run]])
            }
            ereignis("chat.werkzeug", ["sessionKey": session, "runId": run, "stream": "tool",
                                       "data": ["phase": "start", "name": schritt.name, "args": schritt.args]], v)
        }
    }

    private func strom(_ text: String, run: String, session: String, _ v: Verbindung) async {
        var bisher = ""
        let worte = text.components(separatedBy: " ")
        for (i, wort) in worte.enumerated() {
            try? await Task.sleep(for: .seconds(wortPause))
            let weg = lock.withLock { laeufe[run]?.abgebrochen ?? true }
            if weg {
                lock.withLock { laeufe[run]?.laeuft = false }
                ereignis("chat.strom", ["sessionKey": session, "runId": run, "state": "aborted", "message": bisher], v)
                return
            }
            let stueck = (i == 0 ? "" : " ") + wort
            bisher += stueck
            ereignis("chat.strom", ["sessionKey": session, "runId": run, "state": "delta", "deltaText": stueck], v)
        }
        let eintrag = Self.zeile("assistant", text, id: "a-\(run)", ms: Date().timeIntervalSince1970 * 1000, key: nil, run: run)
        lock.withLock {
            laeufe[run]?.laeuft = false
            verlauf[session, default: []].append(eintrag)
        }
        ereignis("chat.strom", ["sessionKey": session, "runId": run, "state": "final", "message": text], v)
        ereignis("sitzung.nachricht", ["sessionKey": session, "message": eintrag, "messageId": "a-\(run)", "runId": run], v)
    }

    private func brich(_ id: String, _ daten: [String: Any], _ v: Verbindung) {
        let session = daten["sessionKey"] as? String
        let run = daten["runId"] as? String
        var gestoppt = false
        lock.lock()
        for (k, l) in laeufe where l.laeuft && (run == nil || run == k) && (session == nil || session == l.sessionKey) {
            laeufe[k]?.abgebrochen = true
            gestoppt = true
        }
        lock.unlock()
        antwort(id, ["aborted": gestoppt], v)
    }

    static func beispielAntwort(_ frage: String) -> String {
        let kurz = frage.count > 60 ? String(frage.prefix(60)) + "…" : frage
        return "Das ist eine **Beispielantwort** des Demo-Gateways auf deine Frage „\(kurz)“.\n\n- Sie kommt Wort für Wort an.\n- Mit *Stopp* lässt sie sich anhalten.\n- Nichts davon sind echte Daten.\n\nAm Ende steht ein längerer Satz, damit der Strom lange genug dauert, um ihn in Ruhe zu beobachten und bei Bedarf zu stoppen."
    }

    static func zeile(_ rolle: String, _ text: String, id: String, ms: Double, key: String?, run: String? = nil) -> [String: Any] {
        var meta: [String: Any] = ["id": id]
        if rolle == "user" { meta["senderId"] = "gateway-owner"; meta["senderIsOwner"] = true }
        if let key { meta["idempotencyKey"] = key }
        if let run { meta["runId"] = run }
        var z: [String: Any] = ["role": rolle, "content": text, "timestamp": ms, "__openclaw": meta]
        if rolle == "assistant" { z["stopReason"] = "stop" }
        return z
    }

    static let rechercheAntwort = "Die Lieferzeit für Projekt Alpha beträgt **zwei Wochen**.\n\n- Material: 5 Tage\n- Montage: 9 Tage\n\nQuellen sind die Notizen im Projektordner und die Seite des Lieferanten. Der Plan ist angepasst."

    static let rechercheSchritte: [(name: String, args: [String: Any])] = [
        ("web_search", ["query": "Lieferzeiten Projekt Alpha 2026"]),
        ("web_fetch", ["url": "https://www.example.com/lieferzeiten?stand=aktuell"]),
        ("read", ["path": "/Users/test/Projekte/alpha/notizen.md"]),
        ("exec", ["command": "git -C ~/Projekte/alpha log --oneline -5", "description": "Letzte Änderungen ansehen"]),
        ("edit", ["file_path": "/Users/test/Projekte/alpha/plan.md", "old_string": "a", "new_string": "b"]),
    ]

    static func langerVerlauf(_ n: Int) -> [[String: Any]] {
        guard n > 0 else { return [] }
        let start = Date().timeIntervalSince1970 * 1000 - 4 * 86_400_000
        var rows: [[String: Any]] = []
        var i = 0
        while rows.count < n {
            let ms = start + Double(i) * 600_000
            rows.append(zeile("user", "Frage \(i + 1): Wie weit ist Aufgabe \(i + 1)?", id: "v\(i)u", ms: ms, key: "v\(i)u:user"))
            if i % 3 == 0 {
                rows.append(["role": "assistant", "timestamp": ms + 1000, "__openclaw": ["id": "v\(i)w"], "content": [
                    ["type": "toolCall", "id": "v\(i)a", "name": "read", "arguments": ["path": "/Users/test/Projekte/alpha/notiz-\(i).md"]],
                    ["type": "toolCall", "id": "v\(i)b", "name": "web_search", "arguments": ["query": "Aufgabe \(i + 1) Stand"]],
                ]])
            }
            rows.append(zeile("assistant", "Aufgabe \(i + 1) ist zu etwa \((i * 7) % 100) Prozent erledigt. Der Rest folgt in den nächsten Tagen.", id: "v\(i)r", ms: ms + 5000, key: nil, run: "v\(i)u"))
            i += 1
        }
        return rows
    }

    static func beispielVerlauf() -> [[String: Any]] {
        let nun = Date().timeIntervalSince1970 * 1000
        let gestern = nun - 86_400_000
        let t0 = nun - 5 * 3_600_000
        func text(_ t: String) -> [[String: Any]] { [["type": "text", "text": t]] }
        func ass(_ id: String, _ ms: Double, _ inhalt: [[String: Any]], stopp: Bool = false, extra: [String: Any] = [:]) -> [String: Any] {
            var z: [String: Any] = ["role": "assistant", "timestamp": ms, "content": inhalt, "__openclaw": ["id": id]]
            if stopp { z["stopReason"] = "stop"; z["model"] = "demo-modell" }
            for (k, w) in extra { z[k] = w }
            return z
        }
        func nutzer(_ id: String, _ ms: Double, _ t: String, eingespeist: Bool = false) -> [String: Any] {
            let meta: [String: Any] = eingespeist ? ["id": id] : ["id": id, "senderId": "gateway-owner", "senderIsOwner": true]
            return ["role": "user", "timestamp": ms, "content": text(t), "__openclaw": meta]
        }
        var rows: [[String: Any]] = [
            zeile("user", "Guten Morgen. Was steht heute an?", id: "h1", ms: gestern, key: "h1:user"),
            zeile("assistant", "Guten Morgen. Heute stehen **zwei Termine** an: ein Gespräch am Vormittag und eine Abgabe am Abend. Sonst ist der Tag frei.", id: "h2", ms: gestern + 4000, key: nil, run: "h1"),
            zeile("user", "Danke. Bitte erinnere mich an die Abgabe.", id: "h3", ms: gestern + 60_000, key: "h3:user"),
            zeile("assistant", "Gern. Ich erinnere dich um *17:00 Uhr* an die Abgabe.", id: "h4", ms: gestern + 64_000, key: nil, run: "h3"),
        ]
        rows.append(nutzer("d1", t0, "Recherchiere bitte die Lieferzeiten für Projekt Alpha. [Vom iPhone, Antwort bitte kurz und ohne Tabellen]"))
        rows.append(ass("d2", t0 + 5000, [
            ["type": "thinking", "thinking": "**Plan** Erst die Quellen sichten, dann die Notizen lesen und zuletzt den Stand im Git prüfen."],
            ["type": "text", "text": "Lass mich erst nachsehen, was dazu vorliegt."],
            ["type": "toolCall", "id": "d-t1", "name": "web_search", "arguments": rechercheSchritte[0].args],
            ["type": "toolCall", "id": "d-t2", "name": "web_fetch", "arguments": rechercheSchritte[1].args],
            ["type": "toolCall", "id": "d-t3", "name": "read", "arguments": rechercheSchritte[2].args],
            ["type": "toolCall", "id": "d-t4", "name": "exec", "arguments": rechercheSchritte[3].args],
            ["type": "toolCall", "id": "d-t5", "name": "edit", "arguments": rechercheSchritte[4].args],
        ]))
        rows.append(["role": "toolResult", "timestamp": t0 + 6000, "toolCallId": "d-t1", "content": text("Ergebnis der Suche")])
        rows.append(ass("d3", t0 + 250_000, text(rechercheAntwort), stopp: true))
        rows.append(nutzer("e1", t0 + 3_600_000, "A scheduled reminder has been triggered. The reminder content is:\nAutomation \"Morgenbericht\" failed 3 times. Letzter Fehler: Zeitüberschreitung.", eingespeist: true))
        rows.append(ass("e2", t0 + 3_630_000, text("Der Morgenbericht ist dreimal ausgefallen. Ich habe die Ursache gefunden: Der Mailserver war nicht erreichbar."), stopp: true))
        rows.append(nutzer("e3", t0 + 7_200_000, "[Inter-session message] sourceSession=agent:vodafone:telco-pm completed\nThis content was routed from another session.\nDie Preise sind geprüft und liegen im Ordner Angebote.", eingespeist: true))
        rows.append(nutzer("x1", t0 + 7_260_000, "HEARTBEAT check", eingespeist: true))
        rows.append(nutzer("x2", t0 + 7_261_000, "[OpenClaw heartbeat poll]", eingespeist: true))
        rows.append(nutzer("q1", t0 + 7_800_000, "Kannst du die Preise noch einmal prüfen?"))
        rows.append(["role": "custom", "timestamp": t0 + 7_805_000, "content": "Run did not run: another run was active"])
        rows.append(ass("e4", t0 + 8_000_000, text("I couldn't continue this session after a gateway restart.")))
        rows.append(["role": "system", "timestamp": t0 + 9_000_000, "__openclaw": ["kind": "reset", "id": "r1"], "content": []])
        rows.append(nutzer("n1", t0 + 9_100_000, "Wie ist das Wetter?"))
        rows.append(ass("n2", t0 + 9_110_000, [["type": "thinking", "thinking": "Kurz überlegen, was gefragt ist, dann ohne Umweg antworten."]]))
        rows.append(ass("n3", t0 + 9_120_000, text("Heute bleibt es trocken, bei 14 Grad und leichtem Wind."), stopp: true))
        return rows
    }

    static func schaufensterVerlauf() -> [[String: Any]] {
        let nun = Date().timeIntervalSince1970 * 1000
        return [
            zeile("user", "Fass den Stand zusammen und schreib dem Kunden kurz Bescheid.", id: "p1", ms: nun - 10_000, key: "p1:user"),
            zeile("assistant", schaufensterAntwort, id: "p2", ms: nun - 4_000, key: nil, run: "p1"),
        ]
    }

    static let schaufensterAntwort = """
    Hier der Stand:

    | Bereich | Fortschritt | Frist |
    | --- | --- | --- |
    | Material | fertig | 3. Nov. |
    | Montage | läuft | 20. Nov. |
    | Abnahme | offen | 28. Nov. |

    Noch offen:
    - [x] Lieferzeiten geprüft
    - [x] Plan angepasst
    - [ ] Kunde informieren

    Den Bericht findest du hier: ~/Documents/Bericht-Alpha.pdf

    Mehr Hintergrund steht auf der [Lieferanten-Seite](https://www.example.com/lieferzeiten?stand=aktuell).

    Entwurf

    Betreff: Kurzes Update zu Projekt Alpha
    An: kunde@beispiel.de

    Hallo,

    kurzer Zwischenstand: Material ist da, die Montage läuft nach Plan, die Abnahme ist für Ende November vorgesehen.

    Viele Grüße
    Antonio
    """
}

extension DemoGateway {

    static let meldeJobs: [(id: String, agent: String, name: String, stunde: Double, tageVor: Double)] = [
        ("j-morgen", "main", "Morgenbericht", 7, 0), ("j-woche", "alpha-lead", "Wochenübersicht", 12.5, 1),
        ("j-kurse", "alpha-lead", "Kursabgleich", 10, 0), ("j-lager", "haus-lead", "Lagerbestand", 10.08, 0),
    ]

    static func meldeLaeufe(_ m: (id: String, agent: String, name: String, stunde: Double, tageVor: Double)) -> [(start: Double, dauer: Double, text: String)] {
        let tag = tagMs()
        let erster = tag + m.stunde * 3_600_000 - m.tageVor * 86_400_000
        return [(0.0, 0), (1, 1), (3, 2), (6, 3)].map { (vor, i) in
            (start: erster - vor * 86_400_000, dauer: 48_000.0 + Double(i) * 9_000, text: meldeText(m.id, i))
        }
    }

    static func meldeText(_ jobId: String, _ i: Int) -> String {
        switch jobId {
        case "j-morgen":
            return i == 0 ? "Guten Morgen. Heute stehen **drei Dinge** an: der Zahnarzttermin um 14:30, die Entscheidung zum Lieferanten und der Preisabgleich.\n\nAlles andere läuft ruhig."
                : "Guten Morgen. Gestern wurden zwei Aufgaben erledigt, eine Entscheidung wartet noch."
        case "j-woche":
            return i == 0 ? kartenAntwort : "Die Woche in Projekt Alpha: drei Aufgaben erledigt, eine offen. Der Plan liegt im Zeitrahmen."
        case "j-kurse":
            return "Der Kursabgleich ist durch. Alle Werte liegen innerhalb der Grenzen, es ist nichts zu tun.\n\n- Euro: unverändert\n- Rohstoffe: leicht schwächer"
        default:
            return "Im Lager sind alle Vorräte ausreichend. Nur der Spülmittelvorrat geht in etwa einer Woche zur Neige."
        }
    }

    static func cronVerlauf(jobId: String) -> [[String: Any]] {
        guard let m = meldeJobs.first(where: { $0.id == jobId }) else { return [] }
        return meldeLaeufe(m).enumerated().flatMap { (n, l) -> [[String: Any]] in
            [["role": "user", "timestamp": l.start + 500, "content": [["type": "text", "text": "Führe den Auftrag „\(m.name)“ aus."]], "__openclaw": ["id": "cu-\(jobId)-\(n)"]],
             ["role": "assistant", "timestamp": l.start + l.dauer - 3_000, "content": [["type": "text", "text": l.text]], "__openclaw": ["id": "ca-\(jobId)-\(n)"], "stopReason": "stop"]]
        }
    }

    static func teamDatei(_ pfad: String) -> (String, Double)? {
        let name = pfad.split(separator: "/").last.map(String.init) ?? ""
        let stunde = 3_600_000.0
        let heute = iso(jetztMs())
        func kz(_ id: String, _ label: String, _ wert: Double, _ einheit: String, ziel: Double? = nil, ampel: String = "gruen", tag: String? = nil) -> [String: Any] {
            var k: [String: Any] = ["id": id, "name": label, "art": "zahl", "wert": wert, "einheit": einheit, "ampel": ampel, "letzter_datentag": tag ?? heute]
            if let ziel { k["ziel"] = ziel }
            return k
        }
        func stamp(_ alter: Double) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            return f.string(from: Date(timeIntervalSince1970: (jetztMs() - alter) / 1000))
        }
        func messwerte(_ agent: String, _ liste: [[String: Any]], alter: Double) -> String {
            text(["agent": agent, "stand": stamp(alter), "kennzahlen": liste])
        }
        switch name {
        case "main.json":
            return (messwerte("main", [kz("antworten", "Antworten heute", 14, ""), kz("erledigt", "Erledigt in 7 Tagen", 21, "Aufgaben", ziel: 20)], alter: 2 * stunde), 2 * stunde)
        case "alpha-lead.json":
            return (messwerte("alpha-lead", [kz("termin", "Aufgaben im Zeitplan", 83, "%", ziel: 90, ampel: "gelb"), kz("erledigt", "Erledigt in 7 Tagen", 9, "Aufgaben")], alter: 3 * stunde), 3 * stunde)
        case "haus-lead.json":
            return (messwerte("haus-lead", [kz("offen", "Offene Aufgaben", 1, "", ziel: 3, tag: iso(jetztMs() - 2 * 86_400_000))], alter: 30 * stunde), 30 * stunde)
        case "alpha-spez.json":
            return (messwerte("alpha-spez", [kz("entwuerfe", "Entwürfe geprüft", 4, "")], alter: 3 * stunde), 3 * stunde)
        case "vertrauen.json":
            func v(_ stufe: Int, _ vor: Double, _ grund: String) -> [String: Any] { ["stufe": stufe, "wirksam": stufe, "seit": iso(tagMs() - vor * 86_400_000), "grund": grund] }
            return (text(["stand": stamp(3 * stunde), "agenten": ["main": v(3, 40, "Arbeitet seit Wochen zuverlässig."), "alpha-lead": v(2, 12, "Pläne sind meist im Zeitrahmen."),
                                                      "haus-lead": v(1, 3, "Startstufe")]]), 3 * stunde)
        case "stand.json" where pfad.contains("/geld/"):
            func k(_ n: String, _ bisher: Double, _ budget: Double, _ prognose: Double, _ ampel: String) -> [String: Any] {
                ["name": n, "bisher_eur": bisher, "budget_eur": budget, "hochrechnung_eur": prognose, "anteil_budget_prozent": bisher / budget * 100, "ampel": ampel]
            }
            return (text(["stand": stamp(4 * stunde), "kostenstellen": ["main": k("Seneca", 8.1, 20, 14.3, "gruen"), "alpha-lead": k("Mara", 3.2, 10, 11.4, "gelb")]]), 4 * stunde)
        case "stand.json" where pfad.contains("/beobachten/"):
            return (text(["stand": stamp(6 * stunde), "offen": [["id": "b1"]], "gefunden": [["zeit": heute, "agent": "alpha-lead", "text": "Zwei Pläne haben seit zehn Tagen keine Änderung."]]]), 6 * stunde)
        default:
            return nil
        }
    }

    private static func text(_ o: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func standDatei(_ pfad: String) -> String? {
        if pfad.contains("/alpha/") {
            return "# Stand Projekt Alpha\n\n## Kurzstand\n\nDer Plan steht zu drei Vierteln. Offen sind der Lieferant und die Abnahme.\n\n## Bericht\n\nDiese Woche wurden drei Aufgaben abgeschlossen. Das Budget wird abgestimmt, sobald das dritte Angebot da ist.\n\n- Lieferantenvergleich läuft\n- Entwurf des Projektplans liegt zur Prüfung vor\n- Entscheidung zum Lieferanten wartet auf dich"
        }
        return nil
    }

    static let beispielBericht = "# Wochenbericht\n\nDie Woche war **ruhig**. Drei Aufgaben sind erledigt, zwei sind offen.\n\n- Erledigt: Angebot geprüft, Termin bestätigt, Rechnung abgelegt\n- Offen: Plan für Projekt Alpha, Rückruf beim Lieferanten\n\n## Ausblick\n\nNächste Woche steht die Abgabe an. Alles Weitere steht im Plan."

    static let kartenAntwort = """
    Hier ist die **Übersicht** der Woche als Karte.

    ```seneca
    {"titel":"Woche 45","marke":{"text":"Achtung","ton":"hoch"},
     "zahlen":[{"label":"Offen","wert":"12","ton":"kritisch","detail":"seit Montag"},{"label":"Erledigt","wert":"34","ton":"ok"},{"label":"Quote","wert":"87 %","ton":"mittel"},{"label":"Stunden","wert":"6,5 h","ton":"hoch"}],
     "fortschritt":{"wert":34,"von":46,"text":"34 von 46 Aufgaben"},
     "diagramm":{"art":"balken","titel":"Stunden je Tag","einheit":"h","punkte":[{"label":"Mo","wert":6},{"label":"Di","wert":7.5},{"label":"Mi","wert":4},{"label":"Do","wert":8},{"label":"Fr","wert":5.5}]},
     "punkte":[{"text":"Abgabe am **Freitag**","ton":"kritisch","meta":"in 5 Tagen"},{"text":"Gespräch am Vormittag","ton":"mittel","meta":"Di"},{"text":"Rechnung abgelegt","ton":"ok"}],
     "aufgaben":[{"text":"Plan für Alpha","wer":"Anna","bis":"Fr"},{"text":"Rückruf Lieferant","fertig":true}],
     "bericht":"Berichte/woche-45.md",
     "aktionen":[{"label":"Mehr dazu","prompt":"Erzähl mir mehr zu Woche 45"}]}
    ```

    Sag Bescheid, wenn ich etwas genauer aufschlüsseln soll.
    """

    static func ansichtenVerlauf() -> [[String: Any]] {
        let t = Date().timeIntervalSince1970 * 1000 - 3_600_000
        return [
            zeile("user", "Gib mir eine Wochenübersicht als Karte.", id: "k1", ms: t, key: "k1:user"),
            zeile("assistant", kartenAntwort, id: "k2", ms: t + 4000, key: nil, run: "k1"),
            zeile("user", "Zeig mir den Wochenverbrauch als Widget.", id: "w1", ms: t + 600_000, key: "w1:user"),
            ["role": "assistant", "timestamp": t + 606_000, "__openclaw": ["id": "w2"], "content": [
                ["type": "canvas", "preview": ["kind": "canvas", "viewId": "demo-verbrauch", "title": "Wochenverbrauch"]],
                ["type": "text", "text": "Das Widget zeigt den **Verbrauch** der Woche."],
            ], "stopReason": "stop", "model": "demo-modell"],
        ]
    }

    private func widgetDokument(_ id: String, _ daten: [String: Any], _ v: Verbindung) {
        let docId = daten["docId"] as? String ?? ""
        if docId.hasPrefix("weg") { fehler(id, "NICHT_GEFUNDEN", "view not found", v); return }
        let origin = docId.hasPrefix("fremd") ? "http://fremd.example:8444" : htmlServer.origin
        antwort(id, ["html": Self.beispielWidgetHtml, "sandboxUrl": "/mcp-app-sandbox?csp=demo", "sandboxOrigin": origin], v)
    }

    static var beispielWidgetHtml: String { TestHtmlServer.beispielWidget }

    private func pinSetzen(_ d: [String: Any]) -> String {
        let nun = Date().timeIntervalSince1970 * 1000
        var pin: [String: Any] = [:]
        let art = d["art"] as? String ?? "karte"
        let titel = (d["titel"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Übersicht"
        let name = (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "pin-" + String(titel.lowercased().unicodeScalars.map { $0.properties.isAlphabetic || $0.properties.numericType != nil ? Character($0) : "-" }.prefix(24)) + "-\(Int(nun) % 100_000)"
        pin["name"] = name; pin["art"] = art; pin["titel"] = titel; pin["von"] = "Seneca"; pin["aktualisiert"] = nun
        for k in ["karte", "html", "pfad"] { if let x = d[k] { pin[k] = x } }
        lock.withLock {
            if let i = pins.firstIndex(where: { ($0["name"] as? String) == name }) { pins[i] = pin } else { pins.append(pin) }
        }
        speichereAnsichten()
        return name
    }

    private func bewertungsListe() -> [[String: Any]] {
        let nun = Date().timeIntervalSince1970 * 1000
        return lock.withLock {
            bewertungen.map { agent, karten in
                func zaehle(_ seit: Double) -> [String: Any] {
                    let ur = karten.values.filter { (($0["am"] as? Double) ?? 0) >= seit }.compactMap { $0["urteil"] as? String }
                    let passt = ur.filter { $0 == "passt" }.count, nein = ur.count - passt
                    var z: [String: Any] = ["passt": passt, "passtNicht": nein, "anzahl": ur.count]
                    if !ur.isEmpty { z["quote"] = Int((Double(passt) / Double(ur.count) * 100).rounded()) } else { z["quote"] = NSNull() }
                    return z
                }
                return ["agentId": agent, "gesamt": zaehle(0), "tage7": zaehle(nun - 7 * 86_400_000),
                        "liste": karten.map { ["kartenId": $0.key, "urteil": $0.value["urteil"] as? String ?? ""] }]
            }
        }
    }

    private func ladeAnsichtenSpeicher() {
        if let url = speicher, let data = try? Data(contentsOf: url), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            pins = o["pins"] as? [[String: Any]] ?? []
            bewertungen = o["bewertungen"] as? [String: [String: [String: Any]]] ?? [:]
        } else if ansichten {
            pins = Self.beispielPins()
            speichereAnsichten()
        }
    }

    private func speichereAnsichten() {
        guard let url = speicher else { return }
        let o: [String: Any] = lock.withLock { ["pins": pins, "bewertungen": bewertungen] }
        if let data = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }

    static func beispielPins() -> [[String: Any]] {
        let nun = Date()
        let iso = ISO8601DateFormatter()
        func tag(_ plus: Int) -> String {
            let d = Calendar.current.date(byAdding: .day, value: plus, to: nun) ?? nun
            let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
        }
        func anzeige(_ zweck: String, ende: [String: Any] = ["art": "dauerhaft"], stand: Double = 1_800, extra: [String: Any] = [:]) -> [String: Any] {
            var a: [String: Any] = ["zweck": zweck, "ende": ende, "stand": iso.string(from: nun.addingTimeInterval(-stand))]
            for (k, v) in extra { a[k] = v }
            return a
        }
        let ms = nun.timeIntervalSince1970 * 1000
        func pin(_ name: String, _ titel: String, _ baustein: [String: Any], _ a: [String: Any], _ minuten: Double) -> [String: Any] {
            ["name": name, "art": "karte", "titel": titel, "von": "Seneca", "aktualisiert": ms - minuten * 60_000,
             "karte": ["titel": titel, "bausteine": [baustein]], "anzeige": a]
        }
        return [
            pin("anzeige-projekt", "Projekt Alpha", ["typ": "fortschritt", "label": "Aufgaben erledigt", "wert": 5, "von": 8, "text": "5 von 8 Aufgaben",
                                                    "seitStart": ["wert": 2, "von": 1, "am": tag(-9)]], anzeige("Projekt im Blick", ende: ["art": "bis", "bis": tag(20)]), 30),
            pin("anzeige-gewicht", "Gewicht", ["typ": "zahl", "label": "Gewicht", "wert": 82.5, "einheit": "kg", "ziel": 80, "seitStart": -1.5,
                                              "verlauf": [["am": tag(-6), "wert": 84], ["am": tag(-4), "wert": 83.6], ["am": tag(-2), "wert": 83], ["am": tag(0), "wert": 82.5]]],
                anzeige("Gewicht im Blick"), 20),
            pin("anzeige-offen", "Offene Punkte", ["typ": "liste", "label": "Diese Woche", "punkte": [["text": "Plan für Alpha abgeben", "ton": "kritisch", "meta": "heute"], ["text": "Lieferanten zurückrufen", "ton": "hoch", "meta": "Do"], ["text": "Rechnung ablegen", "ton": "ok"]]],
                anzeige("Offene Punkte", extra: ["fehler": "Quelle nicht lesbar", "fehlerSeit": iso.string(from: nun.addingTimeInterval(-3 * 3600))]), 45),
            pin("anzeige-termine", "Termine", ["typ": "zeitleiste", "label": "Bis zur Abgabe", "punkte": [["text": "Entwurf fertig", "datum": tag(-5), "erledigt": true], ["text": "Abstimmung", "datum": tag(3)], ["text": "Abgabe", "datum": tag(12)]]],
                anzeige("Termine im Blick", ende: ["art": "bis", "bis": tag(12)]), 60),
            pin("anzeige-abgabe", "Abgabe", ["typ": "countdown", "label": "Abgabe Projekt Alpha", "bis": tag(2)], anzeige("Abgabe im Blick", ende: ["art": "bis", "bis": tag(2)]), 15),
            ["name": "pin-widget", "art": "widget", "titel": "Wochenverbrauch", "von": "Seneca", "aktualisiert": ms - 90 * 60_000, "html": TestHtmlServer.beispielWidget],
            ["name": "pin-bericht", "art": "datei", "titel": "Wochenbericht", "von": "Seneca", "aktualisiert": ms - 120 * 60_000, "pfad": "Berichte/woche-45.md"],
        ]
    }
}

extension DemoGateway {
    private static func jetztMs() -> Double { Date().timeIntervalSince1970 * 1000 }
    private static func tagMs() -> Double { Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000 }
    private static func ausIso(_ s: String) -> Double? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { $0.timeIntervalSince1970 * 1000 }
    }
    private static func iso(_ ms: Double) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: ms / 1000))
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    private static func beispielKarten() -> [[String: Any]] {
        let nun = jetztMs(), heute = iso(tagMs()), gestern = iso(tagMs() - 86_400_000), tag = 86_400_000.0
        func karte(_ id: String, _ titel: String, _ status: String, board: String, agent: String? = nil, labels: [String] = [], prio: String = "normal",
                   notiz: String? = nil, vor: Double = 3_600_000, fertig: Bool = false, angelegt: Double = 5 * 86_400_000,
                   verlauf: [(String, String, Double)] = [], kommentare: [(String, Double)] = [], nachweise: [[String: Any]] = []) -> [String: Any] {
            var meta: [String: Any] = ["automation": ["boardId": board]]
            if !kommentare.isEmpty { meta["comments"] = kommentare.enumerated().map { ["id": "c\($0.offset)-\(id)", "body": $0.element.0, "createdAt": nun - $0.element.1, "author": "Mara"] as [String: Any] } }
            if !nachweise.isEmpty { meta["proof"] = nachweise }
            var k: [String: Any] = ["id": id, "title": titel, "status": status, "priority": prio, "labels": labels, "updatedAt": nun - vor, "createdAt": nun - angelegt,
                                    "metadata": meta]
            if let agent { k["agentId"] = agent }
            if let notiz { k["notes"] = notiz }
            if fertig { k["completedAt"] = nun - vor }
            if !verlauf.isEmpty { k["events"] = verlauf.map { ["kind": "status", "at": nun - $0.2, "fromStatus": $0.0, "toStatus": $0.1] as [String: Any] } }
            return k
        }
        let frist = iso(tagMs() + 5 * tag)
        return [
            karte("k-geschenk", "Geschenk für Lena besorgen", "todo", board: "privat", labels: ["plan:\(heute)"]),
            karte("k-steuer", "Steuerunterlagen sortieren", "todo", board: "privat", labels: ["plan:\(gestern)"], prio: "high", notiz: "Fertig, wenn alle Belege im Ordner liegen."),
            karte("k-zahnarzt", "Zahnarzttermin bestätigen", "todo", board: "privat", labels: ["plan:\(heute)T14:30"]),
            karte("k-fertig", "Blumen gießen", "done", board: "privat", labels: ["plan:\(heute)"], vor: 1_800_000, fertig: true),
            karte("k-a1", "Lieferantenvergleich erstellen", "running", board: "alpha", agent: "alpha-lead", notiz: "Drei Angebote gegenüberstellen, Preis und Lieferzeit.", vor: 600_000,
                  verlauf: [("todo", "running", 3_600_000)], kommentare: [("Zwei Angebote sind da, das dritte fehlt noch.", 1_800_000)]),
            karte("k-a2", "Entwurf Projektplan prüfen", "review", board: "alpha", agent: "alpha-lead", notiz: "Entwurf liegt im Ordner Alpha.", vor: 7_200_000,
                  verlauf: [("running", "review", 7_200_000)],
                  nachweise: [["id": "n1", "status": "passed", "label": "Rechtschreibung geprüft"], ["id": "n2", "status": "skipped", "label": "Zahlen gegengerechnet", "note": "Fehlt noch."]]),
            karte("k-a3", "Budget abstimmen", "todo", board: "alpha", agent: "alpha-lead", labels: ["frist:\(frist)"], prio: "high", notiz: "Ergebnis: ein abgestimmtes Budget als Tabelle."),
            karte("k-a4", "Kickoff-Notizen ablegen", "done", board: "alpha", agent: "alpha-lead", vor: 86_400_000, fertig: true, angelegt: 9 * 86_400_000),
            karte("k-a5", "Ansprechpartner klären", "done", board: "alpha", agent: "alpha-lead", vor: 3 * 86_400_000, fertig: true, angelegt: 9 * 86_400_000),
            karte("k-a6", "Zeitplan skizzieren", "done", board: "alpha", agent: "alpha-lead", vor: 5 * 86_400_000, fertig: true, angelegt: 9 * 86_400_000),
            karte("k-a7", "Vorlagen sammeln", "done", board: "alpha", vor: 8 * 86_400_000, fertig: true, angelegt: 12 * 86_400_000),
            karte("k-a8", "Rückruf beim Lieferanten", "todo", board: "alpha"),
            karte("k-a9", "Messebesuch prüfen", "backlog", board: "alpha", vor: 6 * 86_400_000),
            karte("k-h1", "Vorräte prüfen", "todo", board: "haushalt", agent: "haus-lead", vor: 4 * 86_400_000),
            karte("k-f1", "Farbmuster besorgen", "done", board: "flur", agent: "haus-lead", vor: 2 * 86_400_000, fertig: true, angelegt: 6 * 86_400_000),
            karte("k-f2", "Wand abkleben", "done", board: "flur", agent: "haus-lead", vor: 86_400_000, fertig: true, angelegt: 6 * 86_400_000),
            karte("k-f3", "Erste Schicht streichen", "todo", board: "flur", agent: "haus-lead"),
            karte("k-f4", "Leisten lackieren", "todo", board: "flur"),
            karte("k-h3", "Preise für Bodenleisten einholen", "running", board: "flur", agent: "haus-lead", vor: 240_000,
                  verlauf: [("todo", "running", 1_500_000)], kommentare: [("Vier Händler angefragt, zwei haben schon geantwortet.", 420_000)]),
            karte("k-a11", "Liefervertrag unterschreiben", "blocked", board: "alpha", agent: "alpha-lead", labels: ["wartet-auf-antonio"], vor: 5 * 3_600_000,
                  verlauf: [("running", "blocked", 5 * 3_600_000)]),
            karte("k-a10", "Angebote nachrechnen", "done", board: "alpha", agent: "alpha-lead", vor: 2_400_000, fertig: true, angelegt: 2 * 86_400_000),
            karte("k-h2", "Staubsauger-Modelle vergleichen", "done", board: "haushalt", agent: "haus-lead", vor: 7_200_000, fertig: true, angelegt: 86_400_000),
            karte("k-f5", "Grundierung besorgen", "done", board: "flur", agent: "haus-lead", vor: 4 * 3_600_000, fertig: true, angelegt: 2 * 86_400_000),
        ]
    }

    static func beispielPlan() -> String {
        let f = iso(tagMs() + 16 * 86_400_000)
        return """
        # Plan Projekt Alpha

        **Nächster Schritt:** Lieferantenvergleich abschließen

        ```seneca-plan
        {"ziel":"Der Projektplan ist geprüft und abgegeben.","fertig":"fertig, wenn der Plan unterschrieben vorliegt","frist":"\(f)","budget":"4.000 Euro",
         "risiko":"bequem","freigabe":"erteilt","stand":"Stand 19.10.: Recherche abgeschlossen, Entwurf in Arbeit.",
         "teile":[{"name":"Recherche","zustand":"fertig","wer":"Mara","fertigWenn":"fertig, wenn drei Angebote vorliegen"},
                  {"name":"Entwurf","zustand":"klar","wer":"Mara"},
                  {"name":"Abgabe","zustand":"unbekannt","wer":"Antonio"}],
         "offen":["Wer unterschreibt den Plan?"]}
        ```
        """
    }

    static let effortStufen: [[String: Any]] = [["id": "low", "label": "niedrig"], ["id": "medium", "label": "mittel"], ["id": "high", "label": "hoch"], ["id": "xhigh", "label": "sehr hoch"]]
    static let erstwahl: [String: String] = ["main": "anthropic/claude-opus-5-5", "alpha-lead": "openai-codex/gpt-6.1-sol", "haus-lead": "zai/glm-5.1"]

    static let katalog: [[String: Any]] = {
        func m(_ provider: String, _ id: String, _ name: String, _ fenster: Double, bilder: Bool = false, lokal: Bool = false, erlaubt: Bool = true, erreichbar: Bool = true) -> [String: Any] {
            var o: [String: Any] = ["id": id, "provider": provider, "name": name, "contextWindow": fenster, "input": bilder ? ["text", "image"] : ["text"], "available": erreichbar]
            if lokal { o["local"] = true }
            if !erlaubt { o["manualSelectionAllowed"] = false }
            if provider == "claude-cli" { o["agentRuntime"] = ["id": "claude-cli"] }
            return o
        }
        return [
            m("anthropic", "claude-opus-5-5", "Claude Opus 5.5", 1_000_000, bilder: true),
            m("anthropic", "claude-fable-5-1", "Claude Fable 5.1", 1_000_000, bilder: true),
            m("anthropic", "claude-sonnet-5-5", "Claude Sonnet 5.5", 248_000, bilder: true),
            m("claude-cli", "claude-sonnet-5-5", "Claude Sonnet 5.5 (Claude CLI)", 248_000),
            m("anthropic", "claude-sonnet-5-4", "Claude Sonnet 5.4", 248_000),
            m("anthropic", "claude-haiku-5", "Claude Haiku 5", 200_000),
            m("anthropic", "claude-mythos-1", "Claude Mythos 1", 1_000_000, erlaubt: false),
            m("openai-codex", "gpt-6.1-astra", "gpt-6.1-astra", 400_000),
            m("openai-codex", "gpt-6.1-sol", "gpt-6.1-sol", 400_000),
            m("openai-codex", "gpt-6.1-luna", "gpt-6.1-luna", 272_000),
            m("openai-codex", "gpt-6.1-pro", "gpt-6.1-pro", 400_000, erlaubt: false),
            m("openai-codex", "gpt-6.1-nova", "gpt-6.1-nova", 272_000, erreichbar: false),
            m("zai", "glm-5.1", "glm-5.1", 200_000),
            m("zai", "glm-5-turbo", "glm-5-turbo", 200_000),
            m("zai", "glm-5.1-flash", "glm-5.1-flash", 128_000),
            m("ollama", "llama-lokal", "Llama lokal", 128_000, lokal: true),
        ]
    }()

    private func sitzungsZeile(key: String, agent: String, nun: Double) -> [String: Any] {
        let (e, leer) = lock.withLock { (einstellungen[key] ?? [:], kontextLeer[key] ?? 0) }
        let ref = (e["model"] as? String) ?? Self.erstwahl[agent] ?? "anthropic/claude-opus-5-5"
        let teile = ref.split(separator: "/", maxSplits: 1).map(String.init)
        var z: [String: Any] = ["key": key, "agentId": agent, "modelProvider": teile[0], "model": teile.count > 1 ? teile[1] : ref,
                                "thinkingLevels": Self.effortStufen, "thinkingDefault": "medium", "sessionId": "s-\(agent)-\(leer)",
                                "totalTokens": leer > 0 ? 0 : (agent == "main" ? 96_000 : 21_000), "totalTokensFresh": true,
                                "contextTokens": Self.katalog.first { ($0["id"] as? String) == (teile.count > 1 ? teile[1] : ref) }?["contextWindow"] ?? 248_000,
                                "updatedAt": nun - 3_600_000]
        if e["model"] != nil { z["modelOverrideSource"] = "user" }
        if let t = e["thinkingLevel"] { z["thinkingLevel"] = t }
        if teile[0] == "claude-cli" { z["agentRuntime"] = ["id": "claude-cli"] }
        return z
    }

    func dateiAntwort(_ pfad: String) -> [String: Any]? {
        if leer { return nil }
        if pfad.contains("/_team/") {
            guard let (inhalt, alter) = Self.teamDatei(pfad) else { return nil }
            return ["name": pfad.split(separator: "/").last.map(String.init) ?? "", "pfad": pfad, "art": "json", "groesse": inhalt.utf8.count,
                    "geaendertAm": Self.jetztMs() - alter, "inhalt": inhalt]
        }
        if pfad.hasSuffix("/STAND.md") {
            guard let md = Self.standDatei(pfad) else { return nil }
            return ["name": "STAND.md", "pfad": pfad, "art": "md", "groesse": md.utf8.count, "geaendertAm": Self.jetztMs() - 5_400_000, "inhalt": md]
        }
        if pfad.hasSuffix("/PLAN.md") {
            guard pfad.contains("/alpha/projekte/alpha/") else { return nil }
            let md = Self.beispielPlan()
            return ["name": "PLAN.md", "pfad": pfad, "art": "md", "groesse": md.utf8.count, "geaendertAm": Self.jetztMs() - 20 * 86_400_000, "inhalt": md]
        }
        return ["name": pfad.split(separator: "/").last.map(String.init) ?? "Bericht.md", "pfad": pfad, "art": "md", "groesse": Self.beispielBericht.utf8.count,
                "geaendertAm": Date().timeIntervalSince1970 * 1000 - 3_600_000, "inhalt": Self.beispielBericht]
    }

    func uebersicht(_ fn: String, _ daten: [String: Any]) -> [String: Any] {
        let nun = Self.jetztMs(), tag = Self.tagMs()
        func h(_ std: Double) -> Double { tag + std * 3_600_000 }
        if leer {
            switch fn {
            case "karten.liste": return ["cards": [], "boards": []]
            case "auftraege.liste": return ["jobs": []]
            case "agenten.liste": return ["defaultId": "main", "agents": [["id": "main", "name": "Seneca", "model": ["primary": "anthropic/claude-opus-5-5", "fallbacks": []]]]]
            case "seneca.bereiche": return ["registry": "ok", "bereiche": []]
            case "seneca.projekte": return ["version": 1, "revision": 1, "projekte": [:]]
            case "seneca.entscheidungen": return ["entscheidungen": []]
            case "seneca.kalender": return ["ereignisse": [], "ok": true]
            case "seneca.gesehen": return ["gesehen": [:]]
            case "auftrag.laeufe": return ["entries": []]
            default: break
            }
        }
        switch fn {
        case "auftrag.laeufe":
            let jid = daten["id"] as? String ?? ""
            guard let m = Self.meldeJobs.first(where: { $0.id == jid }) else { return ["entries": []] }
            let eintraege: [[String: Any]] = Self.meldeLaeufe(m).map { l in
                ["runAtMs": l.start, "durationMs": l.dauer, "status": "ok", "deliveryStatus": "delivered", "summary": l.text,
                 "sessionKey": "agent:\(m.agent):cron:\(m.id):run:r\(Int64(l.start))"]
            }
            return ["entries": eintraege]
        case "auftrag.starten":
            return ["ok": true, "id": daten["id"] as? String ?? ""]
        case "karten.liste":
            let karten = lock.withLock { () -> [[String: Any]] in
                if uebersichtKarten == nil { uebersichtKarten = Self.beispielKarten() }
                return uebersichtKarten ?? []
            }
            return ["cards": karten, "boards": [
                ["id": "privat", "name": "Privat"],
                ["id": "alpha", "name": "Projekt Alpha", "orchestration": ["defaultAssignee": "alpha-lead"]],
                ["id": "haushalt", "name": "Haushalt", "orchestration": ["defaultAssignee": "haus-lead"]],
                ["id": "flur", "name": "Flur streichen", "orchestration": ["defaultAssignee": "haus-lead"]],
            ]]
        case "auftraege.liste":
            return ["jobs": [
                ["id": "j-morgen", "delivery": ["mode": "announce"], "name": "Morgenbericht", "agentId": "main", "enabled": true, "schedule": ["kind": "every", "everyMs": 86_400_000, "anchorMs": h(7)],
                 "state": ["lastRunAtMs": h(7), "lastRunStatus": "ok"]],
                ["id": "j-woche", "delivery": ["mode": "announce"], "name": "Wochenübersicht", "agentId": "alpha-lead", "enabled": true, "schedule": ["kind": "every", "everyMs": 86_400_000, "anchorMs": h(12.5)],
                 "state": ["lastRunAtMs": h(12.5) - 86_400_000, "lastRunStatus": "ok"]],
                ["id": "j-preise", "name": "Preisabgleich", "agentId": "haus-lead", "enabled": true, "schedule": ["kind": "every", "everyMs": 86_400_000, "anchorMs": h(6.25)],
                 "state": ["lastRunAtMs": h(6.25), "lastRunStatus": "error"]],
                ["id": "j-kurse", "delivery": ["mode": "announce"], "name": "Kursabgleich", "agentId": "alpha-lead", "enabled": true, "schedule": ["kind": "every", "everyMs": 86_400_000, "anchorMs": h(10)],
                 "state": ["lastRunAtMs": h(10), "lastRunStatus": "ok"]],
                ["id": "j-lager", "delivery": ["mode": "announce"], "name": "Lagerbestand", "agentId": "haus-lead", "enabled": true, "schedule": ["kind": "every", "everyMs": 86_400_000, "anchorMs": h(10.08)],
                 "state": ["lastRunAtMs": h(10.08), "lastRunStatus": "ok"]],
                ["id": "j-post", "name": "Posteingang prüfen", "agentId": "main", "enabled": true, "schedule": ["kind": "every", "everyMs": 1_800_000, "anchorMs": h(0)],
                 "state": ["lastRunAtMs": nun - 600_000, "lastRunStatus": "ok"]],
            ]]
        case "agenten.liste":
            func ag(_ id: String, _ name: String, _ modell: String, _ ausweich: [String] = []) -> [String: Any] {
                ["id": id, "name": name, "model": ["primary": modell, "fallbacks": ausweich]]
            }
            return ["defaultId": "main", "agents": [
                ag("main", "Seneca", "anthropic/claude-opus-5-5", ["anthropic/claude-sonnet-5-5"]),
                ag("alpha-lead", "Mara", "openai-codex/gpt-6.1-sol"), ag("haus-lead", "Jonas", "zai/glm-5.1"),
                ag("alpha-spez", "Tim", "anthropic/claude-haiku-5"), ag("alpha-einkauf", "Nora", "anthropic/claude-haiku-5"),
            ]]
        case "seneca.kalender":
            func t(_ titel: String, _ von: Double, _ bis: Double, _ kal: String, ort: String? = nil, ganztags: Bool = false) -> [String: Any] {
                var o: [String: Any] = ["titel": titel, "start": von, "ende": bis, "kalender": kal, "ganztags": ganztags]
                if let ort { o["ort"] = ort }
                return o
            }
            func tg(_ n: Double, _ std: Double) -> Double { tag + n * 86_400_000 + std * 3_600_000 }
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            let angelegt = lock.withLock { angelegteTermine }
            var heute: [[String: Any]] = [
                t("Geburtstag Lena", tag, tag + 86_400_000, "Familie", ganztags: true),
                t("Frühstück mit Jonas", h(8.5), h(9.25), "Privat"),
                t("Daily", h(9), h(9.5), "Arbeit"),
                t("Planung Projekt Alpha", h(10), h(11.5), "Arbeit", ort: "Raum 1"),
                t("Review Lieferanten", h(10.5), h(12), "Arbeit"),
                t("Abstimmung Projekt Alpha", h(11.5), h(12.25), "Arbeit", ort: "Raum 2"),
                t("Mittag mit Nora", h(12.5), h(13.5), "Privat"),
                t("Spaziergang", h(17), h(18), "Privat"),
            ]
            heute += [
                t("Zahnarzt", tg(1, 9), tg(1, 10), "Privat", ort: "Praxis Dr. Berg"),
                t("Workshop Einkauf", tg(2, 13), tg(2, 16), "Arbeit"),
                t("Gespräch mit Mara", tg(2, 14), tg(2, 14.5), "Arbeit"),
                t("Standup", tg(2, 14.25), tg(2, 14.5), "Arbeit"),
                t("Elternabend", tg(4, 19), tg(4, 21), "Familie"),
                t("Wochenmarkt", tg(6, 9), tg(6, 11), "Privat"),
                t("Abgabe Plan Alpha", tg(9, 0), tg(10, 0), "Arbeit", ganztags: true),
                t("Hausverwaltung", tg(12, 15), tg(12, 16), "Arbeit"),
                t("Geburtstag Jonas", tg(16, 0), tg(17, 0), "Familie", ganztags: true),
                t("Heizungswartung", tg(21, 10), tg(21, 11), "Privat"),
            ]
            let vergangen: [[String: Any]] = [
                t("Quartalsgespräch", tg(-3, 10), tg(-3, 11.5), "Arbeit"),
                t("Kino", tg(-6, 20), tg(-6, 22.25), "Privat"),
                t("Steuerberater", tg(-12, 14), tg(-12, 15), "Arbeit"),
            ]
            return ["ok": true, "geprueftAm": f.string(from: Date().addingTimeInterval(-300)), "zeitraumTage": 42, "schreibbar": ["Privat", "Arbeit"],
                    "termine": heute + angelegt,
                    "vergangen": ["ok": true, "ab": tg(-31, 0), "tage": 31, "termine": vergangen]]
        case "seneca.kalender.anlegen":
            let titel = (daten["titel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let kal = daten["kalender"] as? String ?? ""
            if titel.contains("Fehler") { return ["ok": false, "fehler": "Der Kalender hat den Termin nicht angenommen."] }
            if !["Privat", "Arbeit"].contains(kal) { return ["ok": false, "fehler": "Kalender „\(kal)“ ist nicht beschreibbar."] }
            var o: [String: Any] = ["titel": titel, "start": daten["start"] ?? nun, "ende": daten["ende"] ?? nun, "kalender": kal, "ganztags": false]
            if let ort = daten["ort"] as? String { o["ort"] = ort }
            lock.withLock { angelegteTermine.append(o) }
            return ["ok": true, "angelegt": o]
        case "seneca.gesehen":
            return ["gesehen": lock.withLock { gesehenIds }]
        case "seneca.gesehen.setzen":
            let ids = daten["ids"] as? [String] ?? []
            return ["ok": true, "gesehen": lock.withLock { () -> [String: Double] in for i in ids { gesehenIds[i] = nun }; return gesehenIds }]
        case "seneca.bereiche":
            return ["registry": "ok", "bereiche": [
                ["id": "alpha", "name": "Projekt Alpha", "leiter": "alpha-lead", "leiterName": "Mara", "emoji": "A", "spezialisten": ["alpha-spez"],
                 "unterabteilungen": [["id": "einkauf", "name": "Einkauf", "agent": "alpha-einkauf"]],
                 "kurzstand": ["vorhanden": true, "zeilen": ["Der Plan steht zu drei Vierteln, offen sind der Lieferant und die Abnahme.", "Das Budget wird diese Woche abgestimmt."],
                               "geaendertAm": nun - 5_400_000]],
                ["id": "haushalt", "name": "Haushalt", "leiter": "haus-lead", "leiterName": "Jonas", "emoji": "H",
                 "kurzstand": ["vorhanden": true, "zeilen": ["Diese Woche stehen Preise vergleichen und der Staubsauger an."], "geaendertAm": nun - 9 * 86_400_000]],
            ]]
        case "seneca.projekte":
            let (felder, rev) = lock.withLock { () -> ([String: [String: Any]], Int) in
                if projektFelder == nil {
                    projektFelder = ["alpha": ["bereichId": "alpha", "abteilung": "", "ziel": "Plan abgeben", "faellig": Self.iso(tag + 16 * 86_400_000)],
                                     "haushalt": ["bereichId": "haushalt", "abteilung": "", "ziel": ""],
                                     "flur": ["bereichId": "haushalt", "abteilung": "", "ziel": "Flur ist in neuer Farbe gestrichen"]]
                }
                return (projektFelder ?? [:], projektRevision)
            }
            return ["version": 1, "revision": rev, "projekte": felder]
        case "seneca.projekte.speichern":
            guard let boardId = daten["boardId"] as? String, let neu = daten["felder"] as? [String: Any] else { return ["ok": false] }
            return lock.withLock { () -> [String: Any] in
                if projektFelder == nil { projektFelder = [:] }
                var f = projektFelder?[boardId] ?? [:]
                for (a, b) in neu { f[a] = b }
                projektFelder?[boardId] = f
                projektRevision += 1
                return ["version": 1, "revision": projektRevision, "projekte": projektFelder ?? [:]]
            }
        case "karte.kommentieren":
            let id = daten["id"] as? String ?? ""
            return lock.withLock { () -> [String: Any] in
                guard let i = uebersichtKarten?.firstIndex(where: { ($0["id"] as? String) == id }) else { return ["ok": false] }
                var k = uebersichtKarten![i]
                var meta = k["metadata"] as? [String: Any] ?? [:]
                var kommentare = meta["comments"] as? [[String: Any]] ?? []
                kommentare.append(["id": "c\(kommentare.count)-\(id)", "body": daten["body"] as? String ?? "", "createdAt": nun, "author": "Antonio"])
                meta["comments"] = kommentare
                k["metadata"] = meta
                k["updatedAt"] = nun
                uebersichtKarten![i] = k
                return ["card": k]
            }
        case "karte.starten":
            let id = daten["id"] as? String ?? ""
            return lock.withLock { () -> [String: Any] in
                guard let i = uebersichtKarten?.firstIndex(where: { ($0["id"] as? String) == id }) else { return ["ok": false] }
                var k = uebersichtKarten![i]
                let vorher = k["status"] as? String ?? "todo"
                k["status"] = "running"
                var ev = k["events"] as? [[String: Any]] ?? []
                ev.append(["kind": "status", "at": nun, "fromStatus": vorher, "toStatus": "running"])
                k["events"] = ev
                k["updatedAt"] = nun
                uebersichtKarten![i] = k
                return ["card": k]
            }
        case "seneca.entscheidungen":
            let (fertig, spaeter) = lock.withLock { (entschieden, zurueckgestellt) }
            let neu = lock.withLock { neueEntscheidung }
            func e(_ id: String, _ frage: String, board: String, bereich: String, leiter: String, vor: Double, frist: Double? = nil, kurz: String, kontext: String,
                   optionen: [[String: Any]], empfehlung: [String: Any]?, folge: String? = nil, risiko: String? = nil, blockiert: [[String: Any]] = []) -> [String: Any]? {
                if fertig[id] != nil { return nil }
                var o: [String: Any] = ["id": id, "frage": frage, "boardId": board, "bereichId": bereich, "projektName": board == "alpha" ? "Projekt Alpha" : "Haushalt",
                                        "leiter": leiter, "leiterSession": "agent:\(leiter):main", "gestelltAm": nun - vor, "status": "open", "updatedAt": nun - vor + 60_000,
                                        "kurz": kurz, "kontext": kontext, "optionen": optionen]
                if let frist { o["frist"] = frist }
                if let empfehlung { o["empfehlung"] = empfehlung }
                if let folge { o["folge"] = folge }
                if let risiko { o["risiko"] = risiko }
                if !blockiert.isEmpty { o["blockiertKarten"] = blockiert }
                if let bis = spaeter[id] { o["gesnooztBis"] = bis; o["ruhend"] = true }
                return o
            }
            let liste: [[String: Any]] = [
                e("e-1", "Lieferant A oder B für Projekt Alpha?", board: "alpha", bereich: "alpha", leiter: "alpha-lead", vor: 4 * 86_400_000, frist: tag - 86_400_000,
                  kurz: "Beide Angebote liegen vor. A ist 8 Prozent günstiger, B liefert zwei Wochen früher.",
                  kontext: "Die Angebote wurden am Montag eingeholt. Lieferant A verlangt Vorkasse, Lieferant B Zahlung nach Lieferung. Die Probelieferung von B war ohne Mängel.",
                  optionen: [["key": "A", "titel": "Lieferant A nehmen", "wirkung": "Günstiger, spätere Lieferung", "aufwand": "klein"],
                             ["key": "B", "titel": "Lieferant B nehmen", "wirkung": "Früher fertig, etwas teurer", "aufwand": "klein"],
                             ["key": "C", "titel": "Beide anfragen und später entscheiden", "wirkung": "Zeitverlust von etwa einer Woche", "aufwand": "mittel"]],
                  empfehlung: ["key": "B", "text": "B, weil die Frist sonst reißt und die Probelieferung gut war."],
                  folge: "Mara bestellt noch heute und gibt den Plan an den Einkauf weiter.", risiko: "Bei B sind die Preise nur bis Freitag garantiert.",
                  blockiert: [["id": "k-bestellung", "titel": "Bestellung auslösen", "status": "todo"], ["id": "k-lager", "titel": "Lagerplatz vorbereiten", "status": "todo"]]),
                e("e-2", "Neuen Staubsauger anschaffen?", board: "haushalt", bereich: "haushalt", leiter: "haus-lead", vor: 3_600_000, frist: tag + 2 * 86_400_000,
                  kurz: "Der alte Sauger verliert Saugkraft. Ein neuer kostet etwa 280 Euro, eine Reparatur 90.",
                  kontext: "Der Motor ist sieben Jahre alt. Die Reparatur lohnt sich nur, wenn danach noch drei Jahre Ruhe sind.",
                  optionen: [["key": "neu", "titel": "Neu kaufen", "wirkung": "280 Euro, Ruhe für Jahre"], ["key": "rep", "titel": "Reparieren lassen", "wirkung": "90 Euro, ungewiss"]],
                  empfehlung: ["key": "neu", "text": "Neu kaufen: die Reparatur lohnt bei dem Alter kaum."]),
                e("e-3", "Soll Jonas die Heizungswartung schon im Dezember buchen?", board: "haushalt", bereich: "haushalt", leiter: "haus-lead", vor: 9_000_000,
                  kurz: "Die Wartung ist ab Dezember günstiger. Ein Termin vor Weihnachten wäre noch frei.",
                  kontext: "Der Betrieb hat im Dezember einen Rabatt von 15 Prozent. Danach gelten wieder die normalen Preise.",
                  optionen: [["key": "ja", "titel": "Im Dezember buchen"], ["key": "nein", "titel": "Im Januar buchen"]],
                  empfehlung: ["key": "ja", "text": "Im Dezember buchen, wegen des Rabatts."]),
                e("e-4", "Wie soll das Protokoll der Abstimmung verteilt werden?", board: "alpha", bereich: "alpha", leiter: "alpha-lead", vor: 20 * 3_600_000, frist: tag + 4 * 86_400_000,
                  kurz: "Das Protokoll ist fertig. Es kann an alle gehen oder nur an die Projektleitung.",
                  kontext: "Im Protokoll stehen auch Preise des Lieferanten.",
                  optionen: [["key": "alle", "titel": "An alle Beteiligten"], ["key": "leitung", "titel": "Nur an die Projektleitung"]], empfehlung: nil),
                e("e-5", "Welche Farbe soll der Flur bekommen?", board: "haushalt", bereich: "haushalt", leiter: "haus-lead", vor: 6 * 86_400_000,
                  kurz: "Zur Wahl stehen ein warmes Weiß und ein helles Grau.",
                  kontext: "Die Muster hängen seit Samstag im Flur.",
                  optionen: [["key": "weiss", "titel": "Warmes Weiß"], ["key": "grau", "titel": "Helles Grau"]], empfehlung: ["key": "weiss", "text": "Warmes Weiß macht den Flur heller."]),
                neu ? e("e-neu", "Soll das Team die Preisliste noch heute verschicken?", board: "haushalt", bereich: "haushalt", leiter: "haus-lead", vor: 60_000,
                        kurz: "Die Liste ist fertig und geprüft.", kontext: "Der Versand ginge heute Abend raus.",
                        optionen: [["key": "ja", "titel": "Heute verschicken"], ["key": "nein", "titel": "Morgen verschicken"]], empfehlung: nil) : nil,
            ].compactMap { $0 }
            return ["entscheidungen": liste]
        case "seneca.entscheidung.treffen":
            let eid = daten["id"] as? String ?? ""
            let wahl = (daten["wahl"] as? String) ?? "anders"
            lock.withLock { entschieden[eid] = wahl }
            return ["ok": true, "id": eid, "leiterSession": "agent:alpha-lead:main", "leiterName": "Mara",
                    "nachricht": "Antonio hat entschieden (\(eid)): \(wahl). Bitte umsetzen und die Karten entsperren."]
        case "seneca.entscheidung.spaeter":
            let eid = daten["id"] as? String ?? ""
            let bis = (daten["bis"] as? String).flatMap { Self.ausIso($0) } ?? tag + 86_400_000
            lock.withLock { zurueckgestellt[eid] = bis }
            return ["ok": true, "id": eid]
        case "sitzungen.liste":
            var zeilen: [[String: Any]] = [
                ["key": "agent:alpha-lead:sub-1", "agentId": "alpha-lead", "status": "running", "hasActiveRun": true, "spawnedBy": "agent:main:main",
                 "label": "Alpha — Lieferantenvergleich", "startedAt": nun - 12 * 60_000, "updatedAt": nun - 20_000],
            ]
            for (key, agent) in [("agent:main:main", "main"), ("agent:alpha-lead:main", "alpha-lead"), ("agent:haus-lead:main", "haus-lead")] {
                zeilen.append(sitzungsZeile(key: key, agent: agent, nun: nun))
            }
            return ["sessions": zeilen, "defaults": ["modelProvider": "anthropic", "model": "claude-opus-5-5",
                                                       "thinkingLevels": Self.effortStufen, "thinkingDefault": "medium"]]
        case "modelle.liste":
            let alle = (daten["view"] as? String) == "all"
            return ["models": Self.katalog.filter { alle || ($0["manualSelectionAllowed"] as? Bool) != false }]
        case "seneca.konten":
            return ["claude": ["angemeldet": true, "abo": "max", "email": "demo@example.test"],
                    "anbieter": ["openai-codex": ["art": "oauth", "email": "demo@example.test"], "zai": ["art": "api_key"]],
                    "routen": ["anthropic": ["runtime": "claude-cli"]],
                    "standard": "anthropic/claude-opus-5-5", "ausweich": ["anthropic/claude-sonnet-5-5"]]
        case "verbrauch.stand":
            return ["providers": [["provider": "openai", "displayName": "ChatGPT", "plan": "plus",
                                   "windows": [["label": "5h", "usedPercent": 18], ["label": "Week", "usedPercent": 42]]]]]
        case "sitzung.einstellen":
            let key = daten["key"] as? String ?? ""
            return lock.withLock { () -> [String: Any] in
                var e = einstellungen[key] ?? [:]
                if daten.keys.contains("model") { if let m = daten["model"] as? String { e["model"] = m } else { e.removeValue(forKey: "model") } }
                if daten.keys.contains("thinkingLevel") { if let t = daten["thinkingLevel"] as? String { e["thinkingLevel"] = t } else { e.removeValue(forKey: "thinkingLevel") } }
                einstellungen[key] = e
                let agent = key.split(separator: ":").dropFirst().first.map(String.init) ?? "main"
                let ref = (e["model"] as? String) ?? Self.erstwahl[agent] ?? "anthropic/claude-opus-5-5"
                let teile = ref.split(separator: "/", maxSplits: 1).map(String.init)
                var r: [String: Any] = ["modelProvider": teile[0], "model": teile.count > 1 ? teile[1] : ref, "thinkingLevels": Self.effortStufen, "thinkingDefault": "medium"]
                r["thinkingLevel"] = e["thinkingLevel"] ?? NSNull()
                return ["ok": true, "resolved": r]
            }
        case "seneca.kontext.neu":
            let key = daten["key"] as? String ?? ""
            lock.withLock { kontextLeer[key, default: 0] += 1 }
            return ["ok": true]
        case "sitzung.anlegen":
            let agent = daten["agentId"] as? String ?? "main"
            return ["key": "agent:\(agent):neu-\(UUID().uuidString.prefix(6).lowercased())"]
        case "karte.anlegen":
            let id = "k-neu-" + UUID().uuidString.prefix(8).lowercased()
            var k: [String: Any] = ["id": id, "title": daten["title"] as? String ?? "", "status": daten["status"] as? String ?? "todo",
                                    "priority": daten["priority"] as? String ?? "normal", "labels": [String](), "updatedAt": nun, "createdAt": nun,
                                    "metadata": ["automation": ["boardId": daten["boardId"] as? String ?? "default"]]]
            if let n = daten["notes"] as? String { k["notes"] = n }
            lock.withLock { if uebersichtKarten == nil { uebersichtKarten = Self.beispielKarten() }; uebersichtKarten?.append(k) }
            return ["card": k]
        case "karte.aendern", "karte.verschieben":
            let id = daten["id"] as? String ?? ""
            return lock.withLock { () -> [String: Any] in
                guard let i = uebersichtKarten?.firstIndex(where: { ($0["id"] as? String) == id }) else { return ["ok": false] }
                var k = uebersichtKarten![i]
                if fn == "karte.verschieben", let s = daten["status"] as? String {
                    k["status"] = s
                    if s == "done" { k["completedAt"] = nun } else { k.removeValue(forKey: "completedAt") }
                } else if let patch = daten["patch"] as? [String: Any] {
                    for (a, b) in patch { k[a] = b }
                }
                k["updatedAt"] = nun
                uebersichtKarten![i] = k
                return ["card": k]
            }
        default:
            return ["ok": true]
        }
    }
}
