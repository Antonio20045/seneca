import SwiftUI
import AppKit
import AVFoundation
import Combine
@preconcurrency import CoreML
import FluidAudio

enum DiktatPfade {
    static var ordner: URL? {
        guard let b = MacPfade.datenOrdner?.appendingPathComponent("diktat", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return b
    }

    static var protokoll: URL? { ordner?.appendingPathComponent("diktat-log.jsonl") }

    static var modellOrdner: URL {
        if let p = ProcessInfo.processInfo.environment["SENECA_DIKTAT_MODELL"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
        }
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        let name = MacPfade.profil == .test ? "FluidAudio/Models Test/parakeet-tdt-0.6b-v3-coreml" : "FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml"
        return basis.appendingPathComponent(name, isDirectory: true)
    }

    static var echtOrdner: URL? {
        guard let b = MacPfade.echterBasisOrdner?.appendingPathComponent("diktat", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return b
    }

    static var mikrofonSperrdatei: URL? { echtOrdner?.appendingPathComponent("mikrofon.lock") }

    static func neueAufnahme() -> URL? {
        guard let o = ordner else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        f.locale = Locale(identifier: "de_DE")
        return o.appendingPathComponent("diktat-\(f.string(from: Date())).wav")
    }
}

struct DiktatEintrag: Codable {
    var losgelassen: String
    var textFertig: String?
    var eingefuegt: String?
    var text: String
    var ergebnis: String
    var meldung: String?
    var aufnahme: String
    var wartezeitMs: Int?
    var ziel: String?
}

enum DiktatProtokoll {
    static let zeit: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func schreibe(_ e: DiktatEintrag) {
        guard let url = DiktatPfade.protokoll else { return }
        let kodierer = JSONEncoder()
        kodierer.outputFormatting = []
        guard var daten = try? kodierer.encode(e) else { return }
        daten.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: daten)
        } else {
            try? daten.write(to: url, options: .atomic)
        }
    }
}

actor DiktatErkenner {
    enum Fehler: LocalizedError {
        case modellFehlt(URL)
        case vokabular(URL)
        case nichtBereit
        case leer

        var errorDescription: String? {
            switch self {
            case .modellFehlt(let u): return "Das Sprachmodell fehlt: \(u.lastPathComponent) in \(u.deletingLastPathComponent().path)"
            case .vokabular(let u): return "Die Wortliste des Modells ist unlesbar: \(u.path)"
            case .nichtBereit: return "Das Sprachmodell ist noch nicht geladen."
            case .leer: return "In der Aufnahme war kein Wort zu hören."
            }
        }
    }

    private var manager: AsrManager?
    private var geladen = false

    var bereit: Bool { geladen }

    func waermeVor() async throws {
        if geladen { return }
        let ordner = DiktatPfade.modellOrdner
        let vokabular = try Self.vokabular(aus: ordner.appendingPathComponent("parakeet_vocab.json"))
        let modelle = AsrModels(
            encoder: try Self.lade("Encoder.mlmodelc", in: ordner, units: .cpuAndNeuralEngine),
            preprocessor: try Self.lade("Preprocessor.mlmodelc", in: ordner, units: .cpuOnly),
            decoder: try Self.lade("Decoder.mlmodelc", in: ordner, units: .cpuAndNeuralEngine),
            joint: try Self.lade("JointDecision.mlmodelc", in: ordner, units: .cpuAndNeuralEngine),
            configuration: AsrModels.defaultConfiguration(),
            vocabulary: vokabular,
            version: .v3)
        let m = AsrManager(config: .default)
        try await m.loadModels(modelle)
        var zustand = try TdtDecoderState()
        _ = try? await m.transcribe([Float](repeating: 0, count: 16_000), decoderState: &zustand)
        manager = m
        geladen = true
    }

    func erkenne(datei: URL) async throws -> String {
        guard let m = manager else { throw Fehler.nichtBereit }
        var zustand = try TdtDecoderState()
        let ergebnis = try await m.transcribe(datei, decoderState: &zustand)
        let text = ergebnis.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw Fehler.leer }
        return text
    }

    func woerter(datei: URL) async throws -> [MeetingWort] {
        guard let m = manager else { throw Fehler.nichtBereit }
        var zustand = try TdtDecoderState()
        let r = try await m.transcribe(datei, decoderState: &zustand)
        return Self.woerter(r)
    }

    func woerter(proben: [Float]) async throws -> [MeetingWort] {
        guard let m = manager else { throw Fehler.nichtBereit }
        var zustand = try TdtDecoderState()
        let r = try await m.transcribe(proben, decoderState: &zustand)
        return Self.woerter(r)
    }

    private static func woerter(_ r: ASRResult) -> [MeetingWort] {
        MeetingTranskript.woerter(aus: (r.tokenTimings ?? []).map { ($0.token, $0.startTime, $0.endTime) })
    }

    private static func lade(_ name: String, in ordner: URL, units: MLComputeUnits) throws -> MLModel {
        let url = ordner.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw Fehler.modellFehlt(url) }
        let c = MLModelConfiguration()
        c.computeUnits = units
        c.allowLowPrecisionAccumulationOnGPU = true
        return try MLModel(contentsOf: url, configuration: c)
    }

    private static func vokabular(aus url: URL) throws -> [Int: String] {
        guard let daten = try? Data(contentsOf: url),
              let roh = try? JSONSerialization.jsonObject(with: daten) else { throw Fehler.modellFehlt(url) }
        var w: [Int: String] = [:]
        if let d = roh as? [String: String] {
            for (k, v) in d { if let i = Int(k) { w[i] = v } }
        } else if let a = roh as? [String] {
            for (i, v) in a.enumerated() { w[i] = v }
        }
        guard !w.isEmpty else { throw Fehler.vokabular(url) }
        return w
    }
}

final class DiktatAufnahme: @unchecked Sendable {
    enum Fehler: LocalizedError {
        case keinOrdner
        case keinMikrofon
        case keineFreigabe
        case hintergrundOderTest
        case andereInstanzAktiv

        var errorDescription: String? {
            switch self {
            case .keinOrdner: return "Der Ordner für Aufnahmen lässt sich nicht anlegen."
            case .keinMikrofon: return "Es ist kein Mikrofon da, das aufnehmen könnte."
            case .keineFreigabe: return "Seneca darf das Mikrofon nicht benutzen. Du kannst das in den Systemeinstellungen unter „Datenschutz & Sicherheit“ ändern."
            case .hintergrundOderTest: return "Hintergrund- oder Test-Instanzen dürfen das Mikrofon nicht anfassen."
            case .andereInstanzAktiv: return "Eine andere Seneca-Instanz nimmt gerade auf."
            }
        }
    }

    private let motor = AVAudioEngine()
    private let schloss = NSLock()
    private var datei: AVAudioFile?
    private var wandler: AVAudioConverter?
    private var ziel: AVAudioFormat?
    private(set) var url: URL?
    private(set) var geraeteName: String?
    private var laeuft = false
    private var konfigurationsBeobachter: NSObjectProtocol?
    private var letzterPuffer = Date()
    var motorAktiv: Bool { motor.isRunning }
    var sekundenSeitLetztemPuffer: TimeInterval {
        schloss.lock()
        defer { schloss.unlock() }
        return Date().timeIntervalSince(letzterPuffer)
    }
    var unterbrochen: (@Sendable () -> Void)?
    var pegel: (@Sendable (Float) -> Void)?

    static func freigabe() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func starte() throws -> URL {
        if DiktatMikrofonRegel.gesperrtFuerHintergrundOderTest(
            hintergrundAktiv: Hintergrund.aktiv, profilTest: MacPfade.profil == .test || MacPfade.nebenher,
            datenOrdnerUeberschrieben: ProcessInfo.processInfo.environment["SENECA_DATEN"] != nil) {
            throw Fehler.hintergrundOderTest
        }
        if let sperre = DiktatPfade.mikrofonSperrdatei, PfadSperre.istFremdBelegt(bei: sperre) {
            throw Fehler.andereInstanzAktiv
        }
        guard let u = DiktatPfade.neueAufnahme() else { throw Fehler.keinOrdner }
        let verfuegbare = MikrofonGeraete.verfuegbare()
        let zielUID = MikrofonAuswahl.zielUID(fuer: MacEinstellungen.mikrofonQuelleGespeichert, verfuegbare: verfuegbare)
        geraeteName = verfuegbare.first { $0.uid == zielUID }?.name ?? "Systemstandard"
        MikrofonGeraete.setze(motor, aufUID: zielUID)
        let quelle = motor.inputNode.inputFormat(forBus: 0)
        guard quelle.sampleRate > 0, quelle.channelCount > 0 else { throw Fehler.keinMikrofon }
        let einstellungen: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let f = try AVAudioFile(forWriting: u, settings: einstellungen)
        let zielFormat = f.processingFormat
        guard let w = AVAudioConverter(from: quelle, to: zielFormat) else { throw Fehler.keinMikrofon }
        schloss.lock()
        datei = f
        wandler = w
        ziel = zielFormat
        url = u
        laeuft = true
        schloss.unlock()

        schloss.lock(); letzterPuffer = Date(); schloss.unlock()

        motor.inputNode.installTap(onBus: 0, bufferSize: 2048, format: quelle) { [weak self] puffer, _ in
            self?.merkePuffer()
            self?.messe(puffer)
            self?.schreibe(puffer)
        }
        konfigurationsBeobachter = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: motor, queue: .main) { [weak self] _ in
            self?.unterbrochen?()
        }
        motor.prepare()
        do {
            try motor.start()
        } catch {
            if let b = konfigurationsBeobachter { NotificationCenter.default.removeObserver(b); konfigurationsBeobachter = nil }
            motor.inputNode.removeTap(onBus: 0)
            schloss.lock(); datei = nil; laeuft = false; schloss.unlock()
            throw error
        }
        if let sperre = DiktatPfade.mikrofonSperrdatei { PfadSperre.belege(bei: sperre) }
        return u
    }

    private func merkePuffer() {
        schloss.lock()
        letzterPuffer = Date()
        schloss.unlock()
    }

    private func messe(_ puffer: AVAudioPCMBuffer) {
        guard let rueckruf = pegel, let kanal = puffer.floatChannelData?[0], puffer.frameLength > 0 else { return }
        var summe: Float = 0
        for i in 0..<Int(puffer.frameLength) { summe += kanal[i] * kanal[i] }
        let effektiv = (summe / Float(puffer.frameLength)).squareRoot()
        let db = 20 * log10(max(effektiv, 1e-5))
        rueckruf(min(1, max(0, (db + 50) / 40)))
    }

    private func schreibe(_ puffer: AVAudioPCMBuffer) {
        schloss.lock()
        defer { schloss.unlock() }
        guard laeuft, let f = datei, let w = wandler, let z = ziel else { return }
        let rahmen = AVAudioFrameCount(Double(puffer.frameLength) * z.sampleRate / puffer.format.sampleRate) + 1024
        guard let aus = AVAudioPCMBuffer(pcmFormat: z, frameCapacity: rahmen) else { return }
        var gegeben = false
        var fehler: NSError?
        w.convert(to: aus, error: &fehler) { _, status in
            if gegeben { status.pointee = .noDataNow; return nil }
            gegeben = true
            status.pointee = .haveData
            return puffer
        }
        guard fehler == nil, aus.frameLength > 0 else { return }
        try? f.write(from: aus)
    }

    func beende() -> URL? {
        guard laeuft else { return nil }
        if let b = konfigurationsBeobachter { NotificationCenter.default.removeObserver(b); konfigurationsBeobachter = nil }
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        if let sperre = DiktatPfade.mikrofonSperrdatei { PfadSperre.gibFrei(bei: sperre) }
        schloss.lock()
        laeuft = false
        datei = nil
        wandler = nil
        let u = url
        schloss.unlock()
        return u
    }

    func verwirf() {
        guard let u = beende() else { return }
        try? FileManager.default.removeItem(at: u)
        url = nil
    }
}

@MainActor
enum DiktatEinfueger {
    private static var fenster: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
    }

    static func feldImFokus() -> NSTextView? {
        guard let f = fenster else { return nil }
        if let feld = f.firstResponder as? NSTextView, feld.isEditable { return feld }
        if let feld = f.firstResponder as? NSTextField, feld.isEditable, let e = feld.currentEditor() as? NSTextView { return e }
        return nil
    }

    static func inFokus(_ text: String) -> Bool {
        if let feld = feldImFokus() {
            let bereich = feld.selectedRange()
            let alt = feld.string as NSString
            let fuge = braucheLuecke(vor: bereich.location, in: alt) ? " " : ""
            feld.insertText(fuge + text, replacementRange: bereich)
            return true
        }
        if let fr = fenster?.firstResponder, let eingabe = fr as? NSTextInputClient {
            eingabe.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            return true
        }
        if let feld = fenster?.firstResponder as? NSTextField, feld.isEditable {
            let alt = feld.stringValue
            feld.stringValue = alt + (alt.isEmpty || alt.hasSuffix(" ") ? "" : " ") + text
            return true
        }
        return false
    }

    private static func braucheLuecke(vor stelle: Int, in alt: NSString) -> Bool {
        guard stelle > 0, stelle <= alt.length else { return false }
        let letztes = alt.substring(with: NSRange(location: stelle - 1, length: 1))
        return letztes.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    static func inZwischenablage(_ text: String) {
        let p = NSPasteboard.general
        p.clearContents()
        p.setString(text, forType: .string)
    }

    static func zusammen(_ alt: String, _ neu: String) -> String {
        guard !alt.isEmpty else { return neu }
        return alt.hasSuffix(" ") || alt.hasSuffix("\n") ? alt + neu : alt + " " + neu
    }
}

@MainActor
final class DiktatEinstellungen: ObservableObject {
    private let d: UserDefaults
    private static func sch(_ n: String) -> String { "seneca-nativ.diktat-\(n)" + MacPfade.profil.endung }

    @Published var an: Bool { didSet { d.set(an, forKey: Self.sch("an")) } }

    init(_ d: UserDefaults = .standard) {
        self.d = d
        an = d.object(forKey: Self.sch("an")) as? Bool ?? true
    }
}

@MainActor
final class PegelQuelle: ObservableObject {
    @Published private(set) var wert: Double = 0
    private var zuletzt = Date.distantPast

    func setze(_ neu: Double) {
        if neu == wert { return }
        let jetzt = Date()
        if neu != 0, abs(neu - wert) < 0.04 || jetzt.timeIntervalSince(zuletzt) < 0.08 { return }
        zuletzt = jetzt
        wert = neu
    }
}

@MainActor
final class DiktatDienst: ObservableObject {
    static let gemeinsam = DiktatDienst()

    enum Zustand: Equatable {
        case ruht
        case hoert
        case erkennt
        case eingefuegt(String)
        case fehler(String, zwischenablage: Bool)
    }

    @Published private(set) var zustand: Zustand = .ruht {
        didSet {
            zustandSeit = Date()
            if zustand != .ruht { anzeigeZustand = zustand }
            if zustand == .ruht { stoppeWache() } else { starteWache() }
        }
    }
    @Published private(set) var anzeigeZustand: Zustand = .ruht
    @Published private(set) var modellBereit = false
    @Published private(set) var modellFehler: String?
    @Published private(set) var letzteAufnahme: URL?
    let pegelQuelle = PegelQuelle()
    private(set) var pegel: Double {
        get { pegelQuelle.wert }
        set { pegelQuelle.setze(newValue) }
    }

    let einstellungen = DiktatEinstellungen()
    let rechte = DiktatRechte.gemeinsam
    private let taste = DiktatTaste()
    let erkenner = DiktatErkenner()
    private var aufnahme: DiktatAufnahme?
    private var startet = false { didSet { startetAnzeige = startet } }
    private var abblendArbeit: Task<Void, Never>?
    @Published private(set) var beendetHinweis = false
    private var beendetHinweisArbeit: Task<Void, Never>?
    private var zustandSeit = Date()
    private(set) var aufnahmeBeginn = Date()
    private(set) var letzterAusschlag = Date()
    @Published private(set) var geraeteName: String?
    @Published private(set) var startetAnzeige = false
    private var aufnahmeSekunden: TimeInterval = 0
    private var erkennNummer = 0
    private var erkennArbeit: Task<Void, Never>?
    private var wacheTakt: Timer?
    private var wacheAus = false
    private let blase = DiktatBlase()
    var chatZiel: ((String) -> Bool)?

    private init() {}

    func starte() async {
        blase.zeige(dienst: self)
        taste.tipp = { [weak self] in self?.tippe() }
        taste.escape = { [weak self] in self?.escape() }
        wende()
        Publishers.CombineLatest3(einstellungen.$an, rechte.$bedienung, rechte.$eingabe)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.wende() } }
            .store(in: &abos)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.rechte.aktualisiere() } }
            .store(in: &abos)
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.publisher(for: name)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.erneuereTaste() } }
                .store(in: &abos)
        }
        async let modell: Void = waermeVor()
        if einstellungen.an { await rechte.frageErstmals() }
        await modell
    }

    private var abos: Set<AnyCancellable> = []

    func waermeVor() async {
        do {
            try await erkenner.waermeVor()
            modellBereit = true
            modellFehler = nil
        } catch {
            modellBereit = false
            modellFehler = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func erneuereTaste() {
        guard einstellungen.an else { return }
        taste.installiere()
    }

    private func wende() {
        if einstellungen.an {
            taste.installiere()
        } else {
            taste.entferne()
            if aufnahme != nil { brichAb() }
        }
    }

    #if DEBUG
    func blasenProbe(_ art: String) {
        guard MacPfade.profil != .echt || (Hintergrund.aktiv && ProcessInfo.processInfo.environment["SENECA_DATEN"] != nil) else { return }
        wacheAus = true
        switch art {
        case "hoert":
            geraeteName = "MacBook Pro-Mikrofon"
            aufnahmeBeginn = Date()
            letzterAusschlag = Date()
            zustand = .hoert
            Task { @MainActor in
                var t = 0.0
                while !Task.isCancelled { pegel = max(0, min(1, 0.5 + 0.5 * sin(t) * sin(t * 0.37 + 1))); letzterAusschlag = Date(); t += 0.35; try? await Task.sleep(for: .milliseconds(50)) }
            }
        case "still":
            geraeteName = "MacBook Pro-Mikrofon"
            aufnahmeBeginn = Date().addingTimeInterval(-7)
            letzterAusschlag = Date().addingTimeInterval(-7)
            zustand = .hoert
        case "start":
            startetAnzeige = true
            zustand = .hoert
        case "beendet":
            zustand = .ruht
            zeigeBeendetHinweis()
        case "startfehler": zustand = .fehler(DiktatAufnahme.Fehler.keinMikrofon.errorDescription ?? "", zwischenablage: false)
        case "erkennt": zustand = .erkennt
        case "eingefuegt": zustand = .eingefuegt("Ruf morgen Frau Schneider an und frag nach dem Angebot von Telekom.")
        default: zustand = .fehler("Text in die Zwischenablage kopiert. Zum Einfügen in andere Apps braucht Seneca die Freigabe „Bedienungshilfen“ (Einstellungen).", zwischenablage: true)
        }
    }
    #endif

    private func tippe() {
        guard einstellungen.an else { return }
        schalte()
    }

    func umschalten() {
        guard !MacPfade.nebenher else { return }
        schalte()
    }

    var hoertZu: Bool { zustand == .hoert }

    private func schalte() {
        switch DiktatWache.tippen(phase: phase, hatAufnahme: aufnahme != nil, startet: startet, seit: Date().timeIntervalSince(zustandSeit)) {
        case .lasseLos: lasseLos()
        case .beginne: beginne()
        case .erkennungAbbrechenUndBeginne:
            gibErkennungAuf()
            beginne()
        case .nichts: break
        }
    }

    static func phase(_ zustand: Zustand) -> DiktatWache.Phase {
        switch zustand {
        case .ruht: return .ruht
        case .hoert: return .hoert
        case .erkennt: return .erkennt
        case .eingefuegt: return .eingefuegt
        case .fehler: return .fehler
        }
    }

    private var phase: DiktatWache.Phase { Self.phase(zustand) }

    private func starteWache() {
        guard wacheTakt == nil, !wacheAus else { return }
        wacheTakt = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.wache() }
        }
    }

    private func stoppeWache() {
        wacheTakt?.invalidate()
        wacheTakt = nil
    }

    func wache() {
        guard !wacheAus else { return }
        let u = DiktatWache.urteil(phase: phase, hatAufnahme: aufnahme != nil, motorLaeuft: aufnahme?.motorAktiv ?? false,
                                   startet: startet, seit: Date().timeIntervalSince(zustandSeit),
                                   erkennFrist: DiktatWache.erkennFrist(aufnahmeSekunden: aufnahmeSekunden),
                                   seitLetztemPuffer: aufnahme?.sekundenSeitLetztemPuffer)
        switch u {
        case .ok: break
        case .zuruecksetzen:
            abblendArbeit?.cancel()
            zustand = .ruht
        case .aufnahmeBeenden:
            zeigeBeendetHinweis()
            lasseLos()
        case .erkennungHaengt:
            gibErkennungAuf()
            zustand = .fehler("Die Erkennung antwortet nicht. Tippe die rechte ⌘ für eine neue Aufnahme oder wähle „Erneut erkennen“.", zwischenablage: false)
        }
    }

    private func gibErkennungAuf() {
        erkennNummer += 1
        erkennArbeit?.cancel()
        erkennArbeit = nil
    }

    private func escape() {
        if aufnahme != nil {
            brichAb()
        } else if zustand == .erkennt {
            gibErkennungAuf()
            zustand = .ruht
        } else if case .fehler = zustand {
            schliessePille()
        }
    }

    private func zeigeBeendetHinweis() {
        beendetHinweisArbeit?.cancel()
        beendetHinweis = true
        beendetHinweisArbeit = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(DiktatWache.beendetHinweisHoechstens))
            guard !Task.isCancelled else { return }
            self?.beendetHinweis = false
        }
    }

    private func beginne() {
        startet = true
        beendetHinweisArbeit?.cancel()
        beendetHinweis = false
        abblendArbeit?.cancel()
        letzteAufnahme = nil
        let a = DiktatAufnahme()
        a.pegel = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                if p >= DiktatWache.ausschlagAb { self.letzterAusschlag = Date() }
                self.pegel = Double(p)
            }
        }
        a.unterbrochen = { [weak self] in
            Task { @MainActor in
                self?.erneuereTaste()
                self?.wache()
            }
        }
        geraeteName = nil
        zustand = .hoert
        Task {
            defer { self.startet = false }
            guard await DiktatAufnahme.freigabe() else {
                self.rechte.aktualisiere()
                self.meldeStartFehler(DiktatAufnahme.Fehler.keineFreigabe.errorDescription ?? "Keine Freigabe.")
                return
            }
            do {
                _ = try a.starte()
                self.aufnahme = a
                self.aufnahmeBeginn = Date()
                self.letzterAusschlag = Date()
                self.geraeteName = a.geraeteName
                self.pegel = 0
                self.zustand = .hoert
            } catch {
                self.meldeStartFehler((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func meldeStartFehler(_ meldung: String) {
        zustand = .fehler(meldung, zwischenablage: false)
        let jetzt = DiktatProtokoll.zeit.string(from: Date())
        DiktatProtokoll.schreibe(DiktatEintrag(losgelassen: jetzt, textFertig: nil, eingefuegt: nil, text: "",
                                               ergebnis: "start_fehlgeschlagen", meldung: meldung, aufnahme: "", wartezeitMs: nil, ziel: nil))
        erneuereTaste()
    }

    private func brichAb() {
        guard let a = aufnahme else { return }
        aufnahme = nil
        a.pegel = nil
        a.unterbrochen = nil
        a.verwirf()
        pegel = 0
        if zustand == .hoert { zustand = .ruht }
    }

    private func lasseLos() {
        guard let a = aufnahme else { return }
        aufnahme = nil
        a.pegel = nil
        pegel = 0
        let losgelassen = Date()
        a.unterbrochen = nil
        aufnahmeSekunden = losgelassen.timeIntervalSince(aufnahmeBeginn)
        guard let datei = a.beende() else { zustand = .ruht; return }
        letzteAufnahme = datei
        starteErkennung(datei, losgelassen: losgelassen)
    }

    func erneutErkennen() {
        guard let datei = letzteAufnahme else { return }
        starteErkennung(datei, losgelassen: Date())
    }

    private func starteErkennung(_ datei: URL, losgelassen: Date) {
        gibErkennungAuf()
        let nummer = erkennNummer
        zustand = .erkennt
        erkennArbeit = Task { await verarbeite(aufnahme: datei, losgelassen: losgelassen, nummer: nummer) }
    }

    enum Ergebnis {
        case eingefuegt(text: String, ziel: String)
        case zwischenablage(text: String)
        case fehlgeschlagen(meldung: String)
    }

    @discardableResult
    func verarbeite(aufnahme datei: URL, losgelassen: Date, nummer: Int? = nil) async -> Ergebnis {
        if !modellBereit { await waermeVor() }
        var eintrag = DiktatEintrag(losgelassen: DiktatProtokoll.zeit.string(from: losgelassen),
                                    textFertig: nil, eingefuegt: nil, text: "",
                                    ergebnis: "fehlgeschlagen", meldung: nil,
                                    aufnahme: datei.lastPathComponent, wartezeitMs: nil, ziel: nil)
        let text: String
        do {
            text = try await erkenner.erkenne(datei: datei)
        } catch {
            if nummer != nil, nummer != erkennNummer { return .fehlgeschlagen(meldung: "Abgebrochen.") }
            let meldung = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            eintrag.meldung = meldung
            DiktatProtokoll.schreibe(eintrag)
            zustand = .fehler(meldung, zwischenablage: false)
            return .fehlgeschlagen(meldung: meldung)
        }
        if nummer != nil, nummer != erkennNummer {
            eintrag.meldung = "Erkennung kam nach dem Abbruch; Text verworfen."
            eintrag.text = text
            DiktatProtokoll.schreibe(eintrag)
            return .fehlgeschlagen(meldung: "Abgebrochen.")
        }
        let fertig = Date()
        eintrag.text = text
        eintrag.textFertig = DiktatProtokoll.zeit.string(from: fertig)

        var ziel: String?
        if NSApp.isActive || NSApp.keyWindow is SchnellfrageFenster || ProcessInfo.processInfo.environment["SENECA_DIKTAT_MESSUNG"] != nil {
            if DiktatEinfueger.inFokus(text) {
                ziel = "fokus"
            } else if chatZiel?(text) == true {
                ziel = "chat"
            }
        } else if let weg = await DiktatFremdeApp.fuegeEin(text) {
            ziel = "\(weg.rawValue):\(DiktatFremdeApp.vorne?.bundleIdentifier ?? "?")"
        }
        let ende = Date()
        eintrag.eingefuegt = DiktatProtokoll.zeit.string(from: ende)
        eintrag.wartezeitMs = Int((ende.timeIntervalSince(losgelassen) * 1000).rounded())
        if let ziel {
            eintrag.ergebnis = "erfolgreich"
            eintrag.ziel = ziel
            DiktatProtokoll.schreibe(eintrag)
            letzteAufnahme = nil
            zeige(.eingefuegt(text))
            return .eingefuegt(text: text, ziel: ziel)
        }
        DiktatEinfueger.inZwischenablage(text)
        rechte.aktualisiere()
        eintrag.ergebnis = "zwischenablage"
        eintrag.meldung = rechte.bedienung ? "Kein Feld konnte den Text nehmen." : "Bedienungshilfen nicht freigegeben."
        DiktatProtokoll.schreibe(eintrag)
        let hinweis = rechte.bedienung
            ? "Text in die Zwischenablage kopiert, da Einfügen nicht möglich war."
            : "Text in die Zwischenablage kopiert. Zum Einfügen in andere Apps braucht Seneca die Freigabe „Bedienungshilfen“ (Einstellungen)."
        zustand = .fehler(hinweis, zwischenablage: true)
        return .zwischenablage(text: text)
    }

    private func zeige(_ neu: Zustand) {
        zustand = neu
        abblendArbeit?.cancel()
        abblendArbeit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard let self, case .eingefuegt = self.zustand else { return }
            self.zustand = .ruht
        }
    }

    func schliessePille() {
        abblendArbeit?.cancel()
        zustand = .ruht
    }
}
