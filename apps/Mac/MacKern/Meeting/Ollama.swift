import Foundation

protocol OllamaTransport: Sendable {
    func anfrage(methode: String, pfad: String, body: Data?, zeitlimit: TimeInterval) async throws -> Data
}

struct OllamaFehler: LocalizedError {
    var text: String
    var errorDescription: String? { text }
}

struct OllamaURLSession: OllamaTransport {
    static let basis = URL(string: "http://127.0.0.1:11434")!

    func anfrage(methode: String, pfad: String, body: Data?, zeitlimit: TimeInterval) async throws -> Data {
        guard let url = URL(string: pfad, relativeTo: Self.basis), url.host == "127.0.0.1" else { throw OllamaFehler(text: "Ungültiger Pfad") }
        var r = URLRequest(url: url, timeoutInterval: zeitlimit)
        r.httpMethod = methode
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (d, a) = try await URLSession.shared.data(for: r)
        if let h = a as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw OllamaFehler(text: "Ollama antwortet mit \(h.statusCode)") }
        return d
    }
}

protocol OllamaProzess: Sendable {
    func appPfad() -> String?
    func oeffneApp() async -> Bool
    func programmPfad() -> String?
    func starteServe(programm: String) throws
}

enum OllamaStand: Equatable {
    case bereit(modell: String, selbstGestartet: Bool)
    case keinModell
    case nichtErreichbar(String)

    var meldung: String {
        switch self {
        case .bereit(let m, _): return "Ollama bereit (\(m))"
        case .keinModell: return "In Ollama ist kein Sprachmodell installiert (`ollama list` ist leer)."
        case .nichtErreichbar(let g): return "Ollama ist nicht erreichbar: \(g)"
        }
    }
}

enum OllamaModell {
    static func waehle(aus namen: [String], vorgabe: String? = nil) -> String? {
        if let v = vorgabe, !v.isEmpty, let treffer = namen.first(where: { $0 == v || $0.hasPrefix(v + ":") }) { return treffer }
        if let v = vorgabe, !v.isEmpty, v != "llama3.2", let treffer = namen.first(where: { $0 == "llama3.2" || $0.hasPrefix("llama3.2:") }) { return treffer }
        let chat = namen.filter { !$0.lowercased().contains("embed") && !$0.lowercased().contains("rerank") }
        for bevorzugt in ["qwen", "gemma", "llama", "mistral", "phi"] {
            if let m = chat.first(where: { $0.lowercased().hasPrefix(bevorzugt) }) { return m }
        }
        return chat.first
    }
}

final class OllamaStarter: @unchecked Sendable {
    let transport: OllamaTransport
    let prozess: OllamaProzess
    let pause: @Sendable (TimeInterval) async -> Void
    let versuche: Int
    let vorgabeModell: String?

    init(transport: OllamaTransport = OllamaURLSession(), prozess: OllamaProzess, versuche: Int = 30, vorgabeModell: String? = nil,
         pause: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.transport = transport; self.prozess = prozess; self.versuche = versuche; self.vorgabeModell = vorgabeModell; self.pause = pause
    }

    func modelle() async throws -> [String] {
        let d = try await transport.anfrage(methode: "GET", pfad: "/api/tags", body: nil, zeitlimit: 3)
        let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        return ((o?["models"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
    }

    func geladenerKontext(modell: String) async -> Int? {
        guard let d = try? await transport.anfrage(methode: "GET", pfad: "/api/ps", body: nil, zeitlimit: 3),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let m = ((o["models"] as? [[String: Any]]) ?? []).first { ($0["name"] as? String) == modell || ($0["model"] as? String) == modell }
        return (m?["context_length"] as? NSNumber)?.intValue
    }

    func sichereBereit() async -> OllamaStand {
        var gestartet = false
        var namen: [String]
        if let n = try? await modelle() { namen = n } else {
            if prozess.appPfad() != nil {
                guard await prozess.oeffneApp() else { return .nichtErreichbar("Die Ollama-App ließ sich nicht öffnen.") }
            } else if let p = prozess.programmPfad() {
                do { try prozess.starteServe(programm: p) } catch { return .nichtErreichbar("`ollama serve` ließ sich nicht starten (\(error.localizedDescription)).") }
            } else {
                return .nichtErreichbar("Ollama ist nicht installiert (weder die App noch das Programm `ollama`).")
            }
            gestartet = true
            var gefunden: [String]?
            for _ in 0..<versuche {
                await pause(1)
                if let n = try? await modelle() { gefunden = n; break }
            }
            guard let n = gefunden else { return .nichtErreichbar("Der Server antwortet nach \(versuche) Sekunden noch nicht.") }
            namen = n
        }
        guard let m = OllamaModell.waehle(aus: namen, vorgabe: vorgabeModell) else { return .keinModell }
        return .bereit(modell: m, selbstGestartet: gestartet)
    }
}

struct OllamaKlient: Sendable {
    let transport: OllamaTransport
    let modell: String
    var kontext: Int? = 8192
    var halten: String? = nil
    var ohneKuerzen = false

    static let gemeinsamerKontext = 32768
    static let gemeinsamesHalten = "45m"

    static func gemeinsam(transport: OllamaTransport = OllamaURLSession(), modell: String, geladen: Int? = nil) -> OllamaKlient {
        OllamaKlient(transport: transport, modell: modell, kontext: geladen ?? gemeinsamerKontext, halten: gemeinsamesHalten, ohneKuerzen: true)
    }

    func antwort(system: String, nutzer: String, json: Bool, zeitlimit: TimeInterval = 600) async throws -> String {
        var optionen: [String: Any] = ["temperature": 0.2]
        if let kontext { optionen["num_ctx"] = kontext }
        var koerper: [String: Any] = [
            "model": modell, "stream": false,
            "messages": [["role": "system", "content": system], ["role": "user", "content": nutzer]],
            "options": optionen,
        ]
        if json { koerper["format"] = "json" }
        if let halten { koerper["keep_alive"] = halten }
        if ohneKuerzen { koerper["truncate"] = false; koerper["shift"] = false }
        let d = try await transport.anfrage(methode: "POST", pfad: "/api/chat", body: try JSONSerialization.data(withJSONObject: koerper), zeitlimit: zeitlimit)
        guard let o = try JSONSerialization.jsonObject(with: d) as? [String: Any], let m = o["message"] as? [String: Any], let t = m["content"] as? String
        else { throw OllamaFehler(text: "Unerwartete Antwort von Ollama") }
        return t
    }
}

struct MeetingAuswertung: Sendable {
    let klient: OllamaKlient
    var versuche = 2
    var wartezeit: TimeInterval = 20
    var pause: @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    var gescheitert: (@Sendable (Int, String) -> Void)? = nil

    private func frage(system: String, nutzer: String) async throws -> MeetingAnalyse {
        var letzter: Error = OllamaFehler(text: "Kein Versuch")
        let n = max(1, versuche)
        for i in 1...n {
            do {
                let a = MeetingAufgaben.lies(try await klient.antwort(system: system, nutzer: nutzer, json: true))
                if !a.zusammenfassung.isEmpty { return a }
                throw OllamaFehler(text: "Die Antwort des Modells war leer oder nicht lesbar")
            } catch {
                letzter = error
                gescheitert?(i, error.localizedDescription)
                if Task.isCancelled { break }
                if i < n { await pause(wartezeit) }
            }
        }
        throw letzter
    }

    func analysiere(transkript: String) async throws -> MeetingAnalyse {
        let teile = MeetingAufgaben.stuecke(transkript, zeichen: MeetingAufgaben.stueckGroesse(kontext: klient.kontext))
        var analysen: [MeetingAnalyse] = []
        for (i, t) in teile.enumerated() {
            analysen.append(try await frage(system: MeetingAufgaben.systemAnalyse,
                                            nutzer: MeetingAufgaben.nutzerAnalyse(transkript: t, teil: teile.count > 1 ? (i + 1, teile.count) : nil)))
        }
        var ergebnis = MeetingAufgaben.vereine(analysen)
        if analysen.count > 1, let v = try? await frage(system: MeetingAufgaben.systemVerdichten, nutzer: ergebnis.zusammenfassung) {
            ergebnis.zusammenfassung = v.zusammenfassung
            if !v.titel.isEmpty { ergebnis.titel = v.titel }
        }
        return ergebnis
    }

    func nachfrage(_ frage: String, segmente: [MeetingSegment]) async throws -> String {
        try await klient.antwort(system: MeetingAufgaben.systemNachfrage, nutzer: MeetingAufgaben.nutzerNachfrage(frage: frage, segmente: segmente), json: false, zeitlimit: 120)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
