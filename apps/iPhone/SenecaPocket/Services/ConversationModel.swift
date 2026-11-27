import SwiftUI
import Combine

@MainActor
final class ConversationModel: ObservableObject {
    @Published var transcript = ""
    @Published var target: ConversationTarget?
    @Published private(set) var keyboardDismissTick = 0
    @Published private(set) var lateAnswer: String?
    private var geoeffnet = false
    @Published private(set) var voiceState = "still"
    @Published private(set) var spokenText = ""
    @Published private(set) var liestVor = false
    private var vorleseLauf = UUID()
    var tippt = false
    @Published private(set) var entwurfTick = 0
    @Published var sprechWunsch = 0
    var sprechWunschOffen = false
    var sprechWunschTaste = true
    @Published var stumm = false
    @Published private(set) var vonTaste = false
    @Published private(set) var letzteFrage = ""

    let speech = SpeechController()
    weak var store: SenecaStore?
    private var bag: Set<AnyCancellable> = []
    #if DEBUG
    var demoAnswer: String?
    var demoAnswers: [String] = []
    var demoVoice: String?
    var demoVoices: [String] = []
    var demoMic = false
    var demoMute = false
    let demoOffline = ProcessInfo.processInfo.environment["SENECA_DEMO_CHAT_FEHLER"] == "offline"
    #endif

    var macUnreachable: Bool {
        #if DEBUG
        if demoOffline { return true }
        #endif
        guard let store, !store.demo else { return false }
        return !store.isConnected && store.connectionStatus == "Mac nicht erreichbar"
    }

    var isRunning: Bool { !offen.isEmpty }
    var isListening: Bool { hoertZu }

    var kopfFrame: CGRect?
    @Published private(set) var offen: [String: Int] = [:]
    @Published private(set) var schluss: [String: String] = [:]
    @Published private(set) var zustandsHinweis: String?
    @Published private(set) var gespraech = Gespraech()
    var hoertZu: Bool { gespraech.phase == .hoert }
    private(set) var entwurfGesprochen = false
    private(set) var gesprochen: Set<String> = []
    private var angehalten: Set<String> = []
    private var hinweisAufgabe: Task<Void, Never>?
    private var gespraechFeld: ((String) -> Void)?
    private var gespraechSenden: ((String) -> Bool)?
    private var gespraechLauf = UUID()
    private var gespraechRunde = 0
    private var zeitAufgabe: Task<Void, Never>?
    private var zuhoerSenke: AnyCancellable?
    private struct VorleseStrom {
        let lauf: UUID
        let runde: Int
        let frage: String
        var saetze = SatzStrom()
    }
    private var strom: VorleseStrom?
    private var stromSenke: AnyCancellable?
    #if DEBUG
    private var demoVoiceBenutzt = false
    private var demoStimmeEnde = Date.distantPast
    #endif

    func istOffen(_ p: ChatPartner) -> Bool { (offen[p.id] ?? 0) > 0 }

    func zeigeHinweis(_ satz: String, sekunden: Double = 3) {
        zustandsHinweis = satz
        hinweisAufgabe?.cancel()
        hinweisAufgabe = Task { [weak self] in
            try? await Task.sleep(for: .seconds(sekunden))
            guard !Task.isCancelled else { return }
            self?.zustandsHinweis = nil
        }
    }

    @discardableResult
    func senden(_ raw: String, an p: ChatPartner) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chat = store?.chat else { return false }
        if macUnreachable { zeigeHinweis("Deine Nachricht bleibt im Feld, bis der Mac wieder da ist."); return false }
        tempo("senden gedrückt (\(text.count) Zeichen)")
        let imGespraech = gespraech.phase == .wartet
        let gespraechsRunde: Int? = imGespraech ? gespraechRunde : nil
        if !imGespraech { zuhoerEnde() }
        stoppeVorlesen()
        schluss[p.id] = nil
        angehalten.remove(p.id)
        let warGesprochen = entwurfGesprochen
        if entwurfGesprochen { gesprochen.insert(p.id) } else { gesprochen.remove(p.id) }
        entwurfGesprochen = false
        if ChatCommand.parse(text) != nil {
            if imGespraech { ereignis(.fehlgeschlagen) }
            Task { [weak self] in
                let satz = (try? await chat.send(text, an: p)) ?? ""
                self?.zeigeHinweis(satz.replacingOccurrences(of: "*", with: ""), sekunden: 4)
            }
            return true
        }
        if let gespraechsRunde { starteStrom(frage: text, partner: p, chat: chat, runde: gespraechsRunde) }
        offen[p.id, default: 0] += 1
        Task { [weak self] in
            var ende: String?
            var antwort = ""
            var nichtAngekommen = false
            do {
                var demoAntwort: String?
                #if DEBUG
                demoAntwort = self?.nextDemoAnswer()
                #endif
                antwort = try await chat.send(text, an: p, demoAntwort: demoAntwort)
                if self?.angehalten.contains(p.id) == true { ende = "Hier angehalten." }
            } catch SenecaError.stopped {
                ende = "Angehalten, bevor eine Antwort kam."
            } catch SenecaError.nichtGesendet {
                ende = "Die Frage ist nicht gesendet worden."
                nichtAngekommen = true
            } catch {
                ende = "Die Antwort ist nicht angekommen."
                nichtAngekommen = true
            }
            guard let self else { return }
            if !self.geoeffnet, ende == nil { self.lateAnswer = text }
            let rest = max(0, (self.offen[p.id] ?? 1) - 1)
            self.offen[p.id] = rest == 0 ? nil : rest
            if let ende { self.schluss[p.id] = ende }
            if rest == 0 { self.angehalten.remove(p.id) }
            let sichtbar = self.geoeffnet && chat.partner.id == p.id
            if nichtAngekommen, sichtbar { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            if nichtAngekommen, chat.entwurf(fuer: p).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chat.setzeEntwurf(text, fuer: p)
                if sichtbar { self.entwurfGesprochen = warGesprochen }
                self.entwurfTick += 1
                self.zeigeHinweis("Deine Frage steht wieder im Feld.", sekunden: 4)
            }
            let gleicheRunde = gespraechsRunde != nil && gespraechsRunde == self.gespraechRunde
            let gespraechWartet = gleicheRunde && self.gespraech.phase == .wartet
            let gespraechSpricht = gleicheRunde && self.gespraech.phase == .spricht && self.strom?.runde == gespraechsRunde
            if gespraechWartet, ende != nil || !sichtbar { self.ereignis(.fehlgeschlagen) }
            if gespraechSpricht, ende != nil || !sichtbar { self.zuhoerEnde(.fehler) }
            guard ende == nil, sichtbar else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: "\(p.satzName) hat geantwortet.") }
            if gespraechWartet {
                self.stromVerwerfen()
                self.ereignis(.antwort(Self.sprechtext(antwort)))
            } else if gespraechSpricht {
                self.stromBeenden(antwort)
            }
        }
        return true
    }

    private func starteStrom(frage: String, partner p: ChatPartner, chat: ChatService, runde: Int) {
        let key = p.sessionKey(main: chat.mainKey)
        let lauf = UUID()
        strom = VorleseStrom(lauf: lauf, runde: runde, frage: frage)
        stromSenke = chat.$lives.dropFirst().sink { [weak self] lives in self?.liveText(lives[key], lauf: lauf) }
    }

    private func liveText(_ live: ChatLive?, lauf: UUID) {
        guard var s = strom, s.lauf == lauf, s.runde == gespraechRunde, let live, live.question == s.frage, live.phase == .writing,
              gespraech.phase == .wartet || gespraech.phase == .spricht else { return }
        let neue = s.saetze.neu(live.text)
        strom = s
        for satz in neue { stimmeSatz(satz, lauf: lauf) }
    }

    private func stromBeenden(_ antwort: String) {
        guard var s = strom else { return }
        let lauf = s.lauf
        let rest = s.saetze.neu(antwort, ende: true)
        strom = s
        stromSenke = nil
        for satz in rest { stimmeSatz(satz, lauf: lauf) }
        let gespraechsLauf = gespraechLauf
        Task { [weak self] in
            guard let self else { return }
            await self.stimmeAbschliessen()
            guard self.vorleseLauf == lauf else { return }
            self.strom = nil
            self.liestVor = false
            self.voiceState = "vorgelesen"
            if self.gespraechLauf == gespraechsLauf { self.ereignis(.vorgelesen) }
        }
    }

    private func stromVerwerfen() {
        strom = nil
        stromSenke = nil
    }

    private func stimmeSatz(_ satz: String, lauf: UUID) {
        guard strom?.lauf == lauf else { return }
        let erster = gespraech.phase == .wartet
        ereignis(erster ? .antwortBeginnt(satz) : .satzDazu(satz))
        guard gespraech.phase == .spricht, strom?.lauf == lauf else { return }
        if erster {
            vorleseLauf = lauf
            spokenText = ""
            voiceState = "liest vor"
            liestVor = true
        }
        spokenText += (spokenText.isEmpty ? "" : " ") + satz
        if stumm { return }
        #if DEBUG
        if demoMute {
            demoStimmeEnde = max(Date(), demoStimmeEnde).addingTimeInterval(min(5, max(1.0, Double(satz.count) * 0.055)))
            return
        }
        #endif
        speech.speakAppend(satz)
    }

    private func stimmeAbschliessen() async {
        if stumm { return }
        #if DEBUG
        if demoMute {
            let lauf = vorleseLauf
            while Date() < demoStimmeEnde, vorleseLauf == lauf { try? await Task.sleep(for: .milliseconds(100)) }
            return
        }
        #endif
        await speech.speakAbschliessen()
    }

    private static func sprechtext(_ antwort: String) -> String { AnswerParser.spoken(AnswerParser.parse(antwort)) }

    private func lesVor(_ text: String) async -> Bool {
        guard !text.isEmpty else { return true }
        let lauf = UUID()
        vorleseLauf = lauf
        spokenText = text
        voiceState = "liest vor"
        liestVor = true
        #if DEBUG
        if demoMute { try? await Task.sleep(for: .seconds(min(5, max(1.5, Double(text.count) * 0.055)))) } else if !stumm { await speech.speak(text) }
        #else
        if !stumm { await speech.speak(text) }
        #endif
        guard vorleseLauf == lauf else { return false }
        liestVor = false
        voiceState = "vorgelesen"
        return true
    }

    func unterbrechen() {
        if gespraech.phase == .spricht { ereignis(.unterbrochen) } else { stoppeVorlesen() }
    }

    func stoppeVorlesen() {
        vorleseLauf = UUID()
        stromVerwerfen()
        #if DEBUG
        demoStimmeEnde = .distantPast
        #endif
        speech.stopSpeaking()
        if liestVor { liestVor = false }
        if voiceState == "liest vor" { voiceState = "vorgelesen" }
    }

    func anhalten(_ p: ChatPartner) {
        guard let chat = store?.chat else { return }
        zuhoerEnde(.beendet)
        stoppeVorlesen()
        angehalten.insert(p.id)
        Task { await chat.stop(p) }
    }

    func gespraechStarten(taste: Bool = false, feld: @escaping (String) -> Void, senden: @escaping (String) -> Bool) {
        guard !gespraech.aktiv else { return }
        vonTaste = taste
        letzteFrage = ""
        stoppeVorlesen()
        gespraechFeld = feld
        gespraechSenden = senden
        entwurfGesprochen = true
        gespraechLauf = UUID()
        #if DEBUG
        demoVoiceBenutzt = false
        #endif
        zuhoerSenke = speech.$transcript.dropFirst().removeDuplicates().sink { [weak self] text in self?.gehoert(text) }
        ereignis(.start)
    }

    func zuhoerEnde(_ grund: Gespraech.Ende = .verlassen) {
        guard gespraech.aktiv else { return }
        ereignis(.beenden(grund))
    }

    private func ereignis(_ e: Gespraech.Ereignis) {
        var neu = gespraech
        let aktionen = neu.handle(e)
        if neu != gespraech { gespraech = neu }
        for aktion in aktionen {
            switch aktion {
            case .hoeren: hoerenStarten()
            case .neueRunde: neueRunde()
            case .mikroAus: if !pretendsMicrophone { speech.mikroAus() }
            case .sende(let text): sendeGesprochen(text)
            case .lesVor: liesVorImGespraech()
            case .stoppeVorlesen: stoppeVorlesen()
            case .ende(let grund): gespraechAufraeumen(grund)
            }
        }
        plane()
    }

    private func plane() {
        zeitAufgabe?.cancel()
        zeitAufgabe = nil
        guard gespraech.phase == .hoert else { return }
        let lauf = gespraechLauf
        let leer = gespraech.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let sekunden = leer ? Gespraech.leerlaufSekunden : Gespraech.stilleSekunden
        zeitAufgabe = Task { [weak self] in
            try? await Task.sleep(for: .seconds(sekunden))
            guard let self, !Task.isCancelled, self.gespraechLauf == lauf else { return }
            self.ereignis(leer ? .leerlauf : .stille)
        }
    }

    private func hoerenStarten() {
        let lauf = gespraechLauf
        #if DEBUG
        if pretendsMicrophone { if gespraech.phase == .hoert { demoSprechen(lauf) }; return }
        #endif
        if speech.gespraechAktiv { speech.hoeren(); return }
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.speech.gespraechBeginnen()
            guard self.gespraechLauf == lauf, self.gespraech.aktiv else {
                if !self.gespraech.aktiv { self.speech.gespraechBeenden() }
                return
            }
            guard ok else { self.ereignis(.beenden(.fehler)); return }
            self.speech.hoeren()
        }
    }

    private func neueRunde() {
        #if DEBUG
        if pretendsMicrophone { demoSprechen(gespraechLauf); return }
        #endif
        if speech.isRecording { speech.neueRunde() } else { speech.hoeren() }
    }

    private func gehoert(_ text: String) {
        ereignis(.erkannt(text))
        if gespraech.phase == .hoert { gespraechFeld?(gespraech.text) }
    }

    func jetztSenden() {
        if gespraech.phase == .hoert { ereignis(.stille) }
    }

    func umStumm() {
        stumm.toggle()
        if stumm, gespraech.phase == .spricht { speech.stopSpeaking() }
    }

    private func sendeGesprochen(_ text: String) {
        letzteFrage = text
        vonTaste = false
        gespraechRunde += 1
        entwurfGesprochen = true
        gespraechFeld?(text)
        if gespraechSenden?(text) != true { ereignis(.fehlgeschlagen) }
    }

    private func liesVorImGespraech() {
        let lauf = gespraechLauf
        let text = gespraech.vorgelesen
        Task { [weak self] in
            guard let self else { return }
            let zuEnde = await self.lesVor(text)
            if zuEnde, self.gespraechLauf == lauf { self.ereignis(.vorgelesen) }
        }
    }

    private func gespraechAufraeumen(_ grund: Gespraech.Ende) {
        zeitAufgabe?.cancel()
        zeitAufgabe = nil
        zuhoerSenke = nil
        gespraechLauf = UUID()
        if grund == .schluss { gespraechFeld?("") }
        if !pretendsMicrophone { speech.gespraechBeenden() }
        if grund == .fehler, speech.denied || speech.failed, let satz = speech.error { zeigeHinweis(satz, sekunden: 4) }
        gespraechFeld = nil
        gespraechSenden = nil
    }

    #if DEBUG
    private func demoSprechen(_ lauf: UUID) {
        let voice: String
        if let v = demoVoice, !demoVoiceBenutzt { demoVoiceBenutzt = true; voice = v }
        else if !demoVoices.isEmpty { voice = demoVoices.removeFirst() }
        else { return }
        Task { [weak self] in
            for i in 1...max(1, voice.count) {
                guard let self, self.gespraechLauf == lauf, self.gespraech.phase == .hoert, !Task.isCancelled else { return }
                self.gehoert(String(voice.prefix(i)))
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }
    #endif

    var sprechenErlaubt: Bool { pretendsMicrophone || !speech.denied }
    func pruefeMikrofon() { if !pretendsMicrophone { speech.checkDenied() } }

    func entwurfVerworfen() { if !gespraech.aktiv { entwurfGesprochen = false } }

    init() {
        speech.gateway = { [weak self] method, params, timeout in
            guard let store = self?.store else { throw SenecaError.offline }
            return try await store.rufe(method, params: params, timeout: timeout)
        }
        speech.$denied.filter { $0 }.sink { [weak self] _ in self?.zuhoerEnde(.fehler) }.store(in: &bag)
        speech.$failed.filter { $0 }.sink { [weak self] _ in self?.zuhoerEnde(.fehler) }.store(in: &bag)
        speech.onAudioGenommen = { [weak self] in self?.zuhoerEnde(.fehler) }
    }

    private var pretendsMicrophone: Bool {
        #if DEBUG
        return demoMic || demoVoice != nil
        #else
        return false
        #endif
    }

    func begin(after delay: Double) {
        geoeffnet = true
        lateAnswer = nil
    }

    func suspend() {
        zuhoerEnde()
        stoppeVorlesen()
    }

    func dismissKeyboard() {
        keyboardDismissTick += 1
    }

    func end() {
        geoeffnet = false
        zuhoerEnde()
        stoppeVorlesen()
        target = nil
    }

    func submitTyped() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chat = store?.chat else { return }
        if senden(text, an: chat.partner) { transcript = "" }
    }

    #if DEBUG
    private func nextDemoAnswer() -> String? {
        if demoAnswers.count > 1 { return demoAnswers.removeFirst() }
        return demoAnswers.first ?? demoAnswer
    }
    #endif

}
