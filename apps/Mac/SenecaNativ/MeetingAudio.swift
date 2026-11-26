import Foundation
import AVFoundation
import CoreMedia
import ScreenCaptureKit
@preconcurrency import CoreML
import FluidAudio

final class MeetingWandler: @unchecked Sendable {
    static let ziel = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var wandler: AVAudioConverter?
    private var quelle: AVAudioFormat?

    func wandle(_ puffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if quelle != puffer.format {
            quelle = puffer.format
            wandler = AVAudioConverter(from: puffer.format, to: Self.ziel)
        }
        guard let w = wandler else { return nil }
        let rahmen = AVAudioFrameCount(Double(puffer.frameLength) * Self.ziel.sampleRate / puffer.format.sampleRate) + 1024
        guard let aus = AVAudioPCMBuffer(pcmFormat: Self.ziel, frameCapacity: rahmen) else { return nil }
        var gegeben = false
        var fehler: NSError?
        w.convert(to: aus, error: &fehler) { _, status in
            if gegeben { status.pointee = .noDataNow; return nil }
            gegeben = true; status.pointee = .haveData; return puffer
        }
        return fehler == nil && aus.frameLength > 0 ? aus : nil
    }
}

final class MeetingSchreiber: @unchecked Sendable {
    let url: URL
    private var datei: AVAudioFile?
    private let schloss = NSLock()
    private var offen: [Float] = []
    private var verbraucht = 0
    private(set) var ersterPuffer: Date?

    init(url: URL) throws {
        self.url = url
        datei = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
    }

    func schreibe(_ puffer: AVAudioPCMBuffer) {
        schloss.lock(); defer { schloss.unlock() }
        if ersterPuffer == nil { ersterPuffer = Date() }
        try? datei?.write(from: puffer)
        if let k = puffer.floatChannelData?[0] { offen.append(contentsOf: UnsafeBufferPointer(start: k, count: Int(puffer.frameLength))) }
    }

    func schliesse() { schloss.lock(); datei = nil; schloss.unlock() }

    func entnimm(mindestens: Int) -> (proben: [Float], ab: Double)? {
        schloss.lock(); defer { schloss.unlock() }
        guard offen.count >= mindestens else { return nil }
        let r = (offen, Double(verbraucht) / 16_000)
        verbraucht += offen.count
        offen = []
        return r
    }
}

final class MeetingMikrofon: @unchecked Sendable {
    private let motor = AVAudioEngine()
    private let wandler = MeetingWandler()
    private var schreiber: MeetingSchreiber?
    private var konfigurationsBeobachter: NSObjectProtocol?
    var pegel: (@Sendable (Float) -> Void)?
    private(set) var geraeteName: String = "Mikrofon"
    var fehlgeschlagen: (@Sendable (String) -> Void)?

    func starte(in s: MeetingSchreiber) throws {
        schreiber = s
        let verfuegbare = MikrofonGeraete.verfuegbare()
        let quelle = MacEinstellungen.mikrofonQuelleGespeichert
        geraeteName = MikrofonAuswahl.anzeigeName(fuer: quelle, verfuegbare: verfuegbare)
        MikrofonGeraete.setze(motor, aufUID: MikrofonAuswahl.zielUID(fuer: quelle, verfuegbare: verfuegbare))
        try installiereUndStarte()
        konfigurationsBeobachter = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: motor, queue: .main) { [weak self] _ in
            self?.konfigurationGeaendert()
        }
    }

    private func installiereUndStarte() throws {
        let format = motor.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DiktatAufnahme.Fehler.keinMikrofon }
        motor.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] puffer, _ in
            guard let self else { return }
            if let k = puffer.floatChannelData?[0], puffer.frameLength > 0, let r = self.pegel {
                var summe: Float = 0
                for i in 0..<Int(puffer.frameLength) { summe += k[i] * k[i] }
                let db = 20 * log10(max((summe / Float(puffer.frameLength)).squareRoot(), 1e-5))
                r(min(1, max(0, (db + 50) / 40)))
            }
            if let aus = self.wandler.wandle(puffer) { self.schreiber?.schreibe(aus) }
        }
        motor.prepare()
        do { try motor.start() } catch { motor.inputNode.removeTap(onBus: 0); throw error }
    }

    private func konfigurationGeaendert() {
        motor.inputNode.removeTap(onBus: 0)
        do { try installiereUndStarte() }
        catch {
            beende()
            fehlgeschlagen?("Das Mikrofon („\(geraeteName)“) wurde während der Aufnahme getrennt oder hat das Format gewechselt. Das Meeting wurde beendet.")
        }
    }

    func beende() {
        if let b = konfigurationsBeobachter { NotificationCenter.default.removeObserver(b); konfigurationsBeobachter = nil }
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        schreiber = nil
    }
}

final class MeetingSystemton: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var strom: SCStream?
    private let wandler = MeetingWandler()
    private var schreiber: MeetingSchreiber?
    private let schlange = DispatchQueue(label: "seneca.meeting.systemton")
    var abgebrochen: (@Sendable (Error) -> Void)?
    private let schloss = NSLock()
    private var gewollt = false

    static func freigegeben() -> Bool { CGPreflightScreenCaptureAccess() }
    static func frageFreigabe() { _ = CGRequestScreenCaptureAccess() }

    func starte(in s: MeetingSchreiber) async throws {
        schreiber = s
        let inhalt = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let anzeige = inhalt.displays.first else { throw MeetingFehler.text("Kein Bildschirm für die Tonaufnahme gefunden.") }
        let filter = SCContentFilter(display: anzeige, excludingApplications: [], exceptingWindows: [])
        let c = SCStreamConfiguration()
        c.capturesAudio = true
        c.excludesCurrentProcessAudio = true
        c.sampleRate = 48_000
        c.channelCount = 2
        c.width = 2; c.height = 2
        c.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let st = SCStream(filter: filter, configuration: c, delegate: self)
        try st.addStreamOutput(self, type: .audio, sampleHandlerQueue: schlange)
        try await st.startCapture()
        strom = st
    }

    func beende() async {
        schloss.withLock { gewollt = true }
        try? await strom?.stopCapture()
        strom = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, let s = schreiber, let puffer = Self.puffer(aus: sb), let aus = wandler.wandle(puffer) else { return }
        s.schreibe(aus)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if schloss.withLock({ gewollt }) { return }
        abgebrochen?(error)
    }

    private static func puffer(aus sb: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fd = sb.formatDescription, var asbd = fd.audioStreamBasicDescription, let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let n = AVAudioFrameCount(CMSampleBufferGetNumSamples(sb))
        guard n > 0, let p = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { return nil }
        p.frameLength = n
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(n), into: p.mutableAudioBufferList)
        return status == noErr ? p : nil
    }
}

enum MeetingFehler: LocalizedError {
    case text(String)
    var errorDescription: String? { if case .text(let t) = self { return t }; return nil }
}

enum MeetingSprechertrennung {
    static var modellOrdner: URL { OfflineDiarizerModels.defaultModelsDirectory() }

    static func modelleDa() -> Bool {
        let fm = FileManager.default
        var gefunden = Set<String>()
        guard let e = fm.enumerator(at: modellOrdner, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        for case let u as URL in e where u.path.contains("speaker-diarization") {
            let n = u.lastPathComponent
            if ModelNames.OfflineDiarizer.requiredModels.contains(n) { gefunden.insert(n) }
        }
        return gefunden == ModelNames.OfflineDiarizer.requiredModels
    }

    static func trenne(datei: URL) async throws -> [SprecherAbschnitt] {
        let m = OfflineDiarizerManager()
        try await m.prepareModels(directory: modellOrdner)
        let r = try await m.process(datei)
        return r.segments.map { SprecherAbschnitt(kennung: $0.speakerId, start: Double($0.startTimeSeconds), ende: Double($0.endTimeSeconds)) }
    }
}

final class OllamaProzessEcht: OllamaProzess, @unchecked Sendable {
    private var kind: Process?
    private let schloss = NSLock()

    func appPfad() -> String? {
        ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"].first { FileManager.default.fileExists(atPath: $0) }
    }

    func oeffneApp() async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-a", "Ollama"]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    func programmPfad() -> String? {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func starteServe(programm: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: programm)
        p.arguments = ["serve"]
        p.environment = ProcessInfo.processInfo.environment.merging(["OLLAMA_HOST": "127.0.0.1:11434"]) { _, neu in neu }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        schloss.lock(); kind = p; schloss.unlock()
    }

    func beendeKind() {
        schloss.lock(); let k = kind; kind = nil; schloss.unlock()
        if let k, k.isRunning { k.terminate() }
    }
}
