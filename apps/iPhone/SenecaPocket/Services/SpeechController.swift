import AVFoundation
import Combine
import Speech

@MainActor
final class SpeechController: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var error: String?
    @Published private(set) var denied = false
    @Published private(set) var failed = false
    @Published private(set) var isSpeaking = false

    private let engine = AVAudioEngine()
    private(set) var gespraechAktiv = false
    private var mikroWill = false
    private var erkennungId = UUID()
    private var neustarts: [Date] = []
    private let eingang = AudioEingang()
    var onAudioGenommen: (() -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var speechDone: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    var gateway: (@MainActor (_ method: String, _ params: [String: Any], _ timeout: TimeInterval) async throws -> [String: Any])?
    private var voiceMemory = VoiceMemory()
    private var speakToken = UUID()
    private var player: AVAudioPlayer?
    private var playerDone: CheckedContinuation<Void, Never>?
    private var playerOK = true
    private var clipWaiter: CheckedContinuation<Void, Never>?
    private var fetch: ClipFetch?
    private var strom: Strom?

    private final class ClipFetch {
        var results: [Int: Result<SpeechClip, VoiceFailure>] = [:]
        var started: Set<Int> = []
        var cancelled = false
    }

    private final class Strom {
        var buendel = SpeechLogic.Buendel()
        var abschnitte: [String] = []
        var clips: [Int: Result<AVAudioPlayer, VoiceFailure>] = [:]
        var bestellt: Set<Int> = []
        var aktuell = 0
        var geschlossen = false
        var system = false
        var abgebrochen = false
        var lauf: Task<Void, Never>?
        var pause: Task<Void, Never>?
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated {
                if self?.player != nil { self?.stopSpeaking() }
                if self?.gespraechAktiv == true { self?.onAudioGenommen?() }
            }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mikroNeuStarten() }
        }
    }

    @discardableResult
    func checkDenied() -> Bool {
        if denied { return true }
        let mic = AVAudioApplication.shared.recordPermission == .denied
        let recognition = [.denied, .restricted].contains(SFSpeechRecognizer.authorizationStatus())
        guard mic || recognition else { return false }
        error = mic ? "Mikrofon nicht erlaubt." : "Spracherkennung nicht erlaubt."
        denied = true
        return true
    }

    @discardableResult
    func gespraechBeginnen() async -> Bool {
        if gespraechAktiv { return true }
        error = nil
        failed = false
        transcript = ""
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Mikrofon nicht erlaubt."
            denied = true
            return false
        }
        let authorization = await withCheckedContinuation {
            (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else {
            error = "Spracherkennung nicht erlaubt."
            denied = true
            return false
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Die deutsche Spracherkennung ist gerade nicht verfügbar."
            failed = true
            return false
        }
        stopSpeaking()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            self.error = "Die Aufnahme konnte nicht gestartet werden."
            failed = true
            return false
        }
        gespraechAktiv = true
        return true
    }

    func hoeren() {
        guard gespraechAktiv else { return }
        mikroWill = true
        guard !engine.isRunning else { return }
        do {
            try? AVAudioSession.sharedInstance().setActive(true)
            let input = engine.inputNode
            try? input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                error = "Das Mikrofon ist gerade nicht verfügbar."
                failed = true
                mikroAus()
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [eingang] buffer, _ in eingang.anhaengen(buffer) }
            hasInputTap = true
            engine.prepare()
            try engine.start()
            isRecording = true
            transcript = ""
            starteErkennung()
        } catch {
            self.error = "Die Aufnahme konnte nicht gestartet werden."
            failed = true
            mikroAus()
        }
    }

    func mikroAus() {
        mikroWill = false
        erkennungId = UUID()
        isRecording = false
        if engine.isRunning { engine.stop() }
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        eingang.beenden()
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    func neueRunde() {
        transcript = ""
        guard mikroWill else { return }
        erkennungId = UUID()
        eingang.beenden()
        recognitionTask?.cancel()
        recognitionTask = nil
        starteErkennung()
    }

    func gespraechBeenden() {
        mikroAus()
        stopSpeaking()
        transcript = ""
        guard gespraechAktiv else { return }
        gespraechAktiv = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func mikroNeuStarten() {
        guard mikroWill, gespraechAktiv, !engine.isRunning else { return }
        mikroAus()
        hoeren()
    }

    private func starteErkennung() {
        guard mikroWill, let recognizer else { return }
        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true
        audioRequest.taskHint = .dictation
        audioRequest.addsPunctuation = true
        eingang.setze(audioRequest)
        let id = UUID()
        erkennungId = id
        recognitionTask = recognizer.recognitionTask(with: audioRequest) { [weak self] result, failure in
            Task { @MainActor [weak self] in
                guard let self, self.erkennungId == id else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if failure != nil || result?.isFinal == true { self.erkennungEndete() }
            }
        }
    }

    private func erkennungEndete() {
        guard mikroWill else { return }
        let now = Date()
        neustarts = neustarts.filter { now.timeIntervalSince($0) < 8 } + [now]
        guard neustarts.count <= 4 else {
            error = "Die Spracherkennung ist gerade nicht erreichbar."
            failed = true
            mikroAus()
            return
        }
        let id = UUID()
        erkennungId = id
        eingang.beenden()
        recognitionTask = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.erkennungId == id, self.mikroWill else { return }
            self.starteErkennung()
        }
    }

    func speak(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stopSpeaking()
        do {
            let session = AVAudioSession.sharedInstance()
            if !gespraechAktiv { try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers) }
            try session.setActive(true)
        } catch {
            self.error = "Die Sprachausgabe konnte nicht gestartet werden."
            return
        }
        let token = UUID()
        speakToken = token
        isSpeaking = true
        var rest = text
        if gateway != nil, voiceMemory.shouldTryGateway() {
            let left = await speakWithGatewayVoice(SpeechLogic.chunks(text), token: token)
            guard speakToken == token else { return }
            if left.isEmpty {
                isSpeaking = false
                finishSpeakingIfIdle()
                return
            }
            rest = left.joined(separator: " ")
        }
        await speakWithSystemVoice(rest, token: token)
    }

    func speakAppend(_ satz: String) {
        guard let s = offenerStrom() else { return }
        if let abschnitt = s.buendel.add(satz) { s.abschnitte.append(abschnitt) }
        s.pause?.cancel()
        s.pause = nil
        if s.buendel.wartet {
            s.pause = Task { [weak self, weak s] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, let s, !Task.isCancelled, !s.abgebrochen, let abschnitt = s.buendel.flush() else { return }
                s.abschnitte.append(abschnitt)
                self.vorabAnfordern(s)
                self.wakeClipWaiter()
            }
        }
        vorabAnfordern(s)
        wakeClipWaiter()
    }

    func speakAbschliessen() async {
        guard let s = strom else { return }
        s.pause?.cancel()
        if let abschnitt = s.buendel.flush() { s.abschnitte.append(abschnitt) }
        s.geschlossen = true
        vorabAnfordern(s)
        wakeClipWaiter()
        await s.lauf?.value
    }

    private func offenerStrom() -> Strom? {
        if let s = strom, !s.geschlossen, !s.abgebrochen { return s }
        stopSpeaking()
        do {
            let session = AVAudioSession.sharedInstance()
            if !gespraechAktiv { try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers) }
            try session.setActive(true)
        } catch {
            self.error = "Die Sprachausgabe konnte nicht gestartet werden."
            return nil
        }
        let token = UUID()
        speakToken = token
        isSpeaking = true
        let s = Strom()
        s.system = !(gateway != nil && voiceMemory.shouldTryGateway())
        strom = s
        s.lauf = Task { [weak self] in await self?.spieleStrom(s, token: token) }
        return s
    }

    private func vorabAnfordern(_ s: Strom) {
        guard let gateway, !s.system, !s.abgebrochen, s.aktuell < s.abschnitte.count else { return }
        for i in s.aktuell...min(s.aktuell + SpeechLogic.lookahead, s.abschnitte.count - 1) {
            guard s.bestellt.insert(i).inserted else { continue }
            let text = s.abschnitte[i]
            let timeout = i == 0 ? SpeechLogic.firstTimeout : SpeechLogic.laterTimeout
            Task { [weak self, weak s] in
                let began = Date()
                let result: Result<AVAudioPlayer, VoiceFailure>
                do {
                    let payload = try await gateway("stimme.sprechen", ["text": text], timeout)
                    if let clip = SpeechLogic.clip(from: payload) {
                        if let self, let audio = Self.makePlayer(clip, delegate: self) { result = .success(audio) } else { result = .failure(.badAudio) }
                    } else { result = .failure(.badAudio) }
                } catch {
                    result = .failure(SpeechLogic.failure(for: error, elapsed: Date().timeIntervalSince(began), timeout: timeout))
                }
                guard let self, let s, !s.abgebrochen else { return }
                s.clips[i] = result
                self.wakeClipWaiter()
            }
        }
    }

    private func spieleStrom(_ s: Strom, token: UUID) async {
        var i = 0
        while speakToken == token {
            while i >= s.abschnitte.count, !s.geschlossen, speakToken == token { await warteAufStrom() }
            guard speakToken == token else { return }
            guard i < s.abschnitte.count else { break }
            s.aktuell = i
            if s.system {
                let text = s.abschnitte[i...].joined(separator: " ")
                i = s.abschnitte.count
                await speakWithSystemVoice(text, token: token)
                continue
            }
            vorabAnfordern(s)
            while s.clips[i] == nil, speakToken == token { await warteAufStrom() }
            guard speakToken == token else { return }
            guard case .success(let audio)? = s.clips[i] else {
                if case .failure(let why)? = s.clips[i] {
                    voiceMemory.recordFailure(why)
                    tempo("Stimme: Rückfall auf die Systemstimme ab Satz \(i + 1) (\(String(describing: why)))")
                }
                s.system = true
                continue
            }
            let played = await play(audio)
            guard speakToken == token else { return }
            guard played else { voiceMemory.recordFailure(.badAudio); s.system = true; continue }
            voiceMemory.recordSuccess()
            tempo("Stimme: Satz \(i + 1) vom Gateway gesprochen")
            i += 1
            s.aktuell = i
            vorabAnfordern(s)
        }
        guard speakToken == token else { return }
        if strom === s { strom = nil }
        isSpeaking = false
        finishSpeakingIfIdle()
    }

    private func warteAufStrom() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in clipWaiter = c }
    }

    private func speakWithGatewayVoice(_ chunks: [String], token: UUID) async -> [String] {
        guard let gateway, !chunks.isEmpty else { return chunks }
        let batch = ClipFetch()
        fetch = batch
        defer { batch.cancelled = true; if fetch === batch { fetch = nil } }

        func order(_ i: Int) {
            guard i < chunks.count, batch.started.insert(i).inserted else { return }
            let timeout = i == 0 ? SpeechLogic.firstTimeout : SpeechLogic.laterTimeout
            let text = chunks[i]
            Task { [weak self] in
                let began = Date()
                let result: Result<SpeechClip, VoiceFailure>
                do {
                    let payload = try await gateway("stimme.sprechen", ["text": text], timeout)
                    if let clip = SpeechLogic.clip(from: payload) { result = .success(clip) } else { result = .failure(.badAudio) }
                } catch {
                    result = .failure(SpeechLogic.failure(for: error, elapsed: Date().timeIntervalSince(began), timeout: timeout))
                }
                guard let self, !batch.cancelled else { return }
                batch.results[i] = result
                self.wakeClipWaiter()
            }
        }

        for i in chunks.indices {
            for j in i...min(i + SpeechLogic.lookahead, chunks.count - 1) { order(j) }
            while batch.results[i] == nil, speakToken == token {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in clipWaiter = c }
            }
            guard speakToken == token else { return [] }
            guard case .success(let clip)? = batch.results[i] else {
                if case .failure(let why)? = batch.results[i] {
                    voiceMemory.recordFailure(why)
                    tempo("Stimme: Rückfall auf die Systemstimme ab Satz \(i + 1) (\(String(describing: why)))")
                }
                return Array(chunks[i...])
            }
            guard let audio = Self.makePlayer(clip, delegate: self) else {
                voiceMemory.recordFailure(.badAudio)
                return Array(chunks[i...])
            }
            let played = await play(audio)
            guard speakToken == token else { return [] }
            guard played else {
                voiceMemory.recordFailure(.badAudio)
                return Array(chunks[i...])
            }
            voiceMemory.recordSuccess()
            tempo("Stimme: Satz \(i + 1) von \(chunks.count) vom Gateway gesprochen")
        }
        return []
    }

    private func speakWithSystemVoice(_ text: String, token: UUID) async {
        guard speakToken == token else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestGermanVoice()
        utterance.prefersAssistiveTechnologySettings = false
        isSpeaking = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            speechDone[ObjectIdentifier(utterance)] = continuation
            synthesizer.speak(utterance)
        }
        if !synthesizer.isSpeaking { isSpeaking = false }
    }

    private static func makePlayer(_ clip: SpeechClip, delegate: AVAudioPlayerDelegate) -> AVAudioPlayer? {
        let hint: String? = switch clip.mimeType?.lowercased() {
        case "audio/mpeg", "audio/mp3": AVFileType.mp3.rawValue
        case "audio/wav", "audio/x-wav", "audio/wave": AVFileType.wav.rawValue
        case "audio/mp4", "audio/aac", "audio/x-m4a": AVFileType.m4a.rawValue
        default: nil
        }
        guard let audio = try? AVAudioPlayer(data: clip.data, fileTypeHint: hint) else { return nil }
        audio.delegate = delegate
        audio.prepareToPlay()
        return audio
    }

    private func play(_ audio: AVAudioPlayer) async -> Bool {
        player = audio
        playerOK = true
        guard audio.play() else { player = nil; return false }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in playerDone = c }
        if player === audio { player = nil }
        return playerOK
    }

    fileprivate func playerFinished(_ id: ObjectIdentifier, ok: Bool) {
        guard let current = player, ObjectIdentifier(current) == id else { return }
        playerOK = ok
        resumePlayerWaiter()
    }

    private func resumePlayerWaiter() {
        let waiting = playerDone
        playerDone = nil
        waiting?.resume()
    }

    private func wakeClipWaiter() {
        let waiting = clipWaiter
        clipWaiter = nil
        waiting?.resume()
    }

    func stopSpeaking() {
        speakToken = UUID()
        fetch?.cancelled = true
        fetch = nil
        if let s = strom {
            s.abgebrochen = true
            s.pause?.cancel()
            s.clips.removeAll()
            strom = nil
        }
        player?.stop()
        player = nil
        resumePlayerWaiter()
        wakeClipWaiter()
        synthesizer.stopSpeaking(at: .immediate)
        let waiting = speechDone
        speechDone.removeAll()
        waiting.values.forEach { $0.resume() }
        isSpeaking = false
    }

    static func bestGermanVoice() -> AVSpeechSynthesisVoice? {
        let german = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "de-DE" && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let best = german.max { a, b in
            a.quality.rawValue != b.quality.rawValue ? a.quality.rawValue < b.quality.rawValue : a.name > b.name
        }
        return best ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    fileprivate func finished(_ utterance: ObjectIdentifier) {
        speechDone.removeValue(forKey: utterance)?.resume()
        if speechDone.isEmpty { isSpeaking = false }
        finishSpeakingIfIdle()
    }

    private func finishSpeakingIfIdle() {
        guard !gespraechAktiv, !isRecording, !synthesizer.isSpeaking, player == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension SpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
}

extension SpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.playerFinished(id, ok: flag) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.playerFinished(id, ok: false) }
    }
}

final class AudioEingang: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setze(_ neu: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = neu
    }

    func anhaengen(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }

    func beenden() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = nil
    }
}

#if DEBUG
extension SpeechController {
    static func demoGateway(_ mode: String) -> @MainActor (String, [String: Any], TimeInterval) async throws -> [String: Any] {
        final class Count { var n = 0 }
        let count = Count()
        return { _, _, timeout in
            count.n += 1
            if mode == "fehler" || (mode == "mitte" && count.n > 1) {
                throw SenecaError.refused(GatewayRefusal(code: "UNAVAILABLE", reason: nil, requestId: nil,
                                                         message: "TTS conversion failed: no provider registered"))
            }
            switch mode {
            case "langsam":
                try await Task.sleep(for: .seconds(min(10, timeout)))
                throw SenecaError.offline
            default:
                try await Task.sleep(for: .milliseconds(300))
                return ["audioBase64": demoTone(Double(count.n)).base64EncodedString(), "mimeType": "audio/wav", "provider": "demo"]
            }
        }
    }

    private static func demoTone(_ step: Double) -> Data {
        let rate = 22_050, count = rate
        var pcm = Data()
        for i in 0..<count {
            let fade = min(1, Double(min(i, count - i)) / 1_500)
            let v = Int16(sin(2 * .pi * (330 + 110 * step) * Double(i) / Double(rate)) * 9_000 * fade)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        var wav = Data("RIFF".utf8) + le32(36 + pcm.count) + Data("WAVEfmt ".utf8) + le32(16) + le16(1) + le16(1)
        wav += le32(rate) + le32(rate * 2) + le16(2) + le16(16) + Data("data".utf8) + le32(pcm.count) + pcm
        return wav
    }
}
#endif
