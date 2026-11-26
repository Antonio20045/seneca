import AppKit
import ApplicationServices

struct SensorRegeln: Equatable {
    var verweilenS: Double
    var sicherheitProzent: Double
    var modellS: Double
    var markiertZeichen: Int

    static func aus(_ stand: [String: Any]) -> SensorRegeln? {
        guard let r = stand["regeln"] as? [String: Any] else { return nil }
        func zahl(_ n: String) -> Double? { (r[n] as? NSNumber)?.doubleValue }
        guard let v = zahl("sensor_verweilen_s"), let p = zahl("sensor_sicherheit_prozent"), let m = zahl("sensor_modell_s"), let z = zahl("sensor_markiert_zeichen") else { return nil }
        return SensorRegeln(verweilenS: v, sicherheitProzent: p, modellS: m, markiertZeichen: Int(z))
    }
}

struct SensorUrteil: Equatable {
    var hilfe = false
    var vorschlag = ""
    var sicherheit = 0.0
    var brauchtBild = false

    static let system = """
    Du bist Seneca, Antonios Assistent. Du siehst, welche App und welches Fenster vorn ist, manchmal markierten Text. Kann ich hier helfen? Schlag höchstens eine konkrete Sache vor, die Seneca für Antonio erledigen kann, als kurzen Satz ohne Fragezeichen. \
    Antworte nur mit JSON: {"hilfe": true|false, "vorschlag": "…", "sicherheit": 0 bis 1, "braucht_bild": true|false}. "braucht_bild" nur, wenn du ohne Foto des Fensters nicht entscheiden kannst. Im Zweifel: hilfe false.
    """

    static func lies(_ text: String) throws -> SensorUrteil {
        guard let o = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw OllamaFehler(text: "Antwort ist kein JSON") }
        return SensorUrteil(hilfe: o["hilfe"] as? Bool ?? false, vorschlag: (o["vorschlag"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                            sicherheit: (o["sicherheit"] as? NSNumber)?.doubleValue ?? 0, brauchtBild: o["braucht_bild"] as? Bool ?? false)
    }

    func meldet(_ r: SensorRegeln) -> Bool { hilfe && !vorschlag.isEmpty && sicherheit * 100 >= r.sicherheitProzent }
}

@MainActor
final class Sensor: ObservableObject {
    typealias Rufe = (String, [String: Any]) async throws -> [String: Any]

    static let gemeinsam = Sensor()
    private static let schalter = "sensor.an"

    @Published private(set) var fehlt: HierFreigabe?
    @Published var an: Bool { didSet { UserDefaults.standard.set(an, forKey: Self.schalter); pruefe() } }

    private var rufe: Rufe?
    private var regeln: SensorRegeln?
    private var vorne: (app: HierLeser.Vorne, titel: String, seit: Date)?
    private var beobachter: NSObjectProtocol?
    private var warten: Task<Void, Never>?

    init() { an = UserDefaults.standard.object(forKey: Self.schalter) as? Bool ?? true }

    var satz: String? { fehlt == nil ? nil : "Seneca darf deinen Bildschirm noch nicht sehen." }

    func pruefe() {
        fehlt = !AXIsProcessTrusted() ? .bedienungshilfen : !CGPreflightScreenCaptureAccess() ? .bildschirm : nil
    }

    func freigeben() {
        if fehlt == .bedienungshilfen { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
        fehlt?.oeffne()
    }

    func starte(rufe: @escaping Rufe) {
        self.rufe = rufe
        pruefe()
        Task { do { regeln = SensorRegeln.aus(try await rufe("seneca.stand", ["geraet": "mac"])) } catch { regeln = nil } }
        guard beobachter == nil else { return }
        beobachter = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wechsel() }
        }
    }

    private var bereit: Bool { an && fehlt == nil && rufe != nil && regeln != nil }

    private func wechsel() {
        pruefe()
        let jetzt = Date()
        if let alt = vorne, bereit {
            melde(["art": "spur", "app": alt.app.name, "titel": alt.titel, "von": Self.ms(alt.seit), "bis": Self.ms(jetzt)])
        }
        warten?.cancel()
        vorne = nil
        guard bereit, let r = regeln, let v = HierLeser.vorne() else { return }
        vorne = (v, HierLeser.ax(v.pid).titel, jetzt)
        warten = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(r.verweilenS)) } catch { return }
            await self?.frageModell(v, r)
        }
    }

    private func frageModell(_ v: HierLeser.Vorne, _ r: SensorRegeln) async {
        guard bereit, HierLeser.vorne()?.pid == v.pid else { return }
        let a = HierLeser.ax(v.pid)
        do {
            let u = try await urteil(v, a, r)
            if u.meldet(r) { melde(["art": "vorschlag", "text": u.vorschlag, "app": v.name, "titel": a.titel, "sicherheit": u.sicherheit]) }
        } catch { return }
    }

    private func urteil(_ v: HierLeser.Vorne, _ a: (markiert: String, titel: String), _ r: SensorRegeln) async throws -> SensorUrteil {
        let t = OllamaURLSession()
        let o = try JSONSerialization.jsonObject(with: try await t.anfrage(methode: "GET", pfad: "/api/tags", body: nil, zeitlimit: r.modellS)) as? [String: Any]
        guard let modell = OllamaModell.waehle(aus: ((o?["models"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }) else { throw OllamaFehler(text: "Kein Modell") }
        let k = OllamaKlient(transport: t, modell: modell)
        let lage = "App: \(v.name)\nFenster: \(a.titel)\nMarkiert: \(a.markiert.prefix(r.markiertZeichen))"
        let u = try SensorUrteil.lies(try await k.antwort(system: SensorUrteil.system, nutzer: lage, json: true, zeitlimit: r.modellS))
        guard u.brauchtBild, let foto = await HierLeser.fensterfoto(v.pid) else { return u }
        defer { try? FileManager.default.removeItem(at: foto) }
        return try SensorUrteil.lies(try await k.antwort(system: SensorUrteil.system, nutzer: lage, json: true, zeitlimit: r.modellS, bilder: [try Data(contentsOf: foto)]))
    }

    private func melde(_ wert: [String: Any]) {
        guard let rufe else { return }
        let h: [String: Any] = ["kennung": UUID().uuidString, "geraet": "mac", "art": "eingang.sensor", "wert": wert, "zeit_geraet": Self.ms(Date())]
        Task { do { _ = try await rufe("seneca.handeln", h) } catch { return } }
    }

    private static func ms(_ d: Date) -> Double { (d.timeIntervalSince1970 * 1000).rounded() }
}
