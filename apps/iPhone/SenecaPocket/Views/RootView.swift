import SwiftUI
import Combine

@MainActor
struct RootView: View {
    @EnvironmentObject private var store: SenecaStore
    @StateObject private var conversation = ConversationModel()
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("sitzung") private var sessionKey = Hauptagent.sitzung
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var sinne = Sinne.shared
    @State private var eingangLaeuft = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var wisch = Wisch(side: RootView.startSide)
    private var t: TransitionState {
        get { wisch.t }
        nonmutating set { wisch.t = newValue }
    }
    private var side: SideState {
        get { wisch.side }
        nonmutating set { wisch.side = newValue }
    }
    @State private var tag = TagStand()
    @State private var dragStart: Double?
    @State private var dragIgnored = false
    @StateObject private var berichte = BerichteModel()
    @State private var dragLayer: Page?
    @State private var dragSeitlich = false
    @State private var chatZugStart: Double?
    @State private var dayMounted = RootView.startSide == SideState()
    @State private var haptics = Haptics()
    @State private var lastDragEnd = Date.distantPast
    @State private var dragNull = CGSize.zero
    @State private var lightPulse = 0
    @State private var lastDone: Int?
    @State private var einstellungen = false
    @State private var arbeit: ArbeitReiter?
    @State private var entscheide: SenecaStand.Frage?
    @State private var auftragNeu: SenecaStand.AuftragNeu?
    @State private var kalenderTag: Date?
    @State private var sinneFrage = false
    @State private var keyboard: CGFloat = 0
    @State private var clockOffset: TimeInterval = 0
    @State private var todayGestures = TodayGestures()

    @State private var pagesAlive: Set<Page> = Set([Page.kalender, .bereiche, .statistik].filter { RootView.startSide.progress($0) > 0 })
    @State private var pageGestures: [Page: PageGestures] = [:]
    @State private var scrollClaims: [CGRect] = []
    @State private var reading: ReadingDocument?
    @State private var kalenderFokus: KalenderFokus?
    @State private var lichtEingang: Double = 0
    @State private var bruecke: KalenderFokus?
    @State private var brueckeZiel: CGRect?
    @State private var brueckeEintrag: AgendaEintrag?
    @State private var brueckeP: Double = 0
    @State private var brueckeNr = 0
    @State private var brueckeAb = Date.distantPast
    @State private var inhaltEingang: Double = 0

    var body: some View {
        app
    }

    private var app: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size, safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
            TimelineView(.everyMinute) { context in
                let now = context.date.addingTimeInterval(clockOffset)
                let stand = tag.stand(now: now, store: store) { dayInput($0) }
                screen(m, day: stand.day, input: stand.input, now: now)
                    .onChange(of: stand.day.dayKey) { _, _ in Task { await store.loadToday(); store.syncTodayRecord() } }
            }
        }
        .ignoresSafeArea()
        .background(Sundartha.grund.ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? Sundartha.fade : Sundartha.ease(0.9)) { lichtEingang = 1 }
            withAnimation((reduceMotion ? Sundartha.fade : Sundartha.ease(0.8)).delay(reduceMotion ? 0.05 : 0.18)) { inhaltEingang = 1 }
        }
        .onChange(of: side.kalender > 0) { _, open in keepAlive(open, .kalender) }
        .onChange(of: side.bereiche > 0) { _, open in keepAlive(open, .bereiche) }
        .onChange(of: side.statistik > 0) { _, open in keepAlive(open, .statistik) }
        .onChange(of: wisch.lage.seiteRuht) { _, _ in unmountDayLater(side) }
        .onChange(of: t.p == 0 && !t.dragging) { _, closed in if closed { unmountDayLater(side) } }
        .senecaBlatt(isPresented: $sinneFrage, groesse: .voll, titel: "Orte und Erlaubnisse", fertig: true) { SinneInhalt() }
        .onChange(of: sinne.offeneFrage) { _, id in
            guard let id else { return }
            sinne.offeneFrage = nil
            if let f = store.stand?.braucht_dich?.first(where: { $0.id == id }) { entscheide = f }
        }
        .modifier(TeamWege(store: store, arbeit: $arbeit, entscheide: $entscheide, auftragNeu: $auftragNeu,
                           chat: { oeffne(.chat(mitarbeiter: $0)) }, berichte: { oeffne(.berichte) }, laeuft: { oeffne(.arbeit(.laeuft)) }))
        .onReceive(Publishers.keyboardHeight) { keyboard = $0 }
        .task { await launch() }
        #if DEBUG
        .overlay { SperreProbe.aus(store.stand) }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: SenecaWunsch.meldung)) { _ in if scenePhase == .active { wunschErfuellen() } }
        .onOpenURL { _ in eingangVerarbeiten() }
        .onChange(of: scenePhase) { _, phase in
            store.isActive = phase == .active
            if phase == .active { Task { await reconnect() }; wunschErfuellen(); eingangVerarbeiten() }
            if phase == .background && t.p > 0.5 { conversation.suspend() }
        }
    }

    private func wunschErfuellen() {
        guard SenecaWunsch.abholen() == SenecaWunsch.diktat else { return }
        einstellungen = false
        reading = nil
        setSide(SideState())
        if t.p < 0.5 { go(1, quick: false) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 950))
            conversation.sprechWunschOffen = true
            conversation.sprechWunsch += 1
        }
    }

    private func eingangVerarbeiten() {
        guard !eingangLaeuft, !store.demo else { return }
        eingangLaeuft = true
        Task { @MainActor in
            defer { eingangLaeuft = false }
            await TeilenVerarbeiten.merken()
            guard TeilenVerarbeiten.hatFragen else { return }
            for _ in 0..<16 where !store.isConnected { try? await Task.sleep(for: .milliseconds(500)) }
            guard store.isConnected else { return }
            einstellungen = false
            reading = nil
            setSide(SideState())
            if t.p < 0.5 { go(1, quick: false) }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 950))
            await TeilenVerarbeiten.fragen { text in
                conversation.transcript = text
                conversation.submitTyped()
                return conversation.transcript.isEmpty
            }
        }
    }

    private func keepAlive(_ open: Bool, _ page: Page) {
        if open { pagesAlive.insert(page); return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if side.progress(page) == 0 {
                pagesAlive.remove(page)
                pageGestures[page] = nil
            }
        }
    }

    private func unmountDayLater(_ state: SideState) {
        guard dayMounted, sidePageOpen(state) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if side == state, sidePageOpen(side), t.p == 0, !t.dragging { dayMounted = false }
        }
    }

    private func sidePageOpen(_ state: SideState) -> Bool {
        !state.dragging && [Page.statistik, .kalender, .bereiche].contains { state.progress($0) == 1 }
    }

    @discardableResult
    private func mountDay() -> Bool {
        guard !dayMounted else { return false }
        dayMounted = true
        return true
    }

    private func setSide(_ next: SideState) {
        if mountDay() {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                side = next
            }
        } else {
            side = next
        }
    }

    private func alive(_ page: Page) -> Bool { side.progress(page) > 0 || pagesAlive.contains(page) }

    private var page: Page {
        if t.p > 0.5 { return .seneca }
        if side.statistik > 0.5 { return .statistik }
        if side.kalender > 0.5 { return .kalender }
        if side.bereiche > 0.5 { return .bereiche }
        return .today
    }

    private var appActions: AppActions {
        AppActions(stand: reduceMotion ? 1 : 0,
                   openReading: { reading = $0 },
                   openConversation: { target in
                       conversation.target = target
                       go(1, quick: false)
                   },
                   showPage: { show($0) },
                   openKalender: { fokus in
                       kalenderFokus = fokus
                       brueckeBauen(fokus)
                       show(.kalender)
                   },
                   dateiOeffnen: { pfad in
                       await DateiOeffner.oeffnen(pfad: pfad, partner: store.chat.partner, store: store, lesen: { reading = $0 })
                   },
                   frage: { text in
                       reading = nil
                       conversation.senden(text, an: store.chat.partner)
                       go(1, quick: false)
                   })
    }

    private var wege: Wege {
        Wege(zurueck: { zurueck() }, oeffne: { oeffne($0) })
    }

    private func zurueck() {
        if reading != nil { reading = nil; return }
        if einstellungen { einstellungenSchliessen(); return }
        if t.p > 0 { go(0, quick: false); return }
        switch page {
        case .statistik, .kalender, .bereiche: show(.today)
        case .today, .seneca: break
        }
    }

    private func oeffne(_ ziel: Ziel) {
        if ziel != .einstellungen { einstellungen = false }
        if case .arbeit = ziel {} else { arbeit = nil }
        switch ziel {
        case .chat(let mitarbeiter):
            reading = nil
            if let mitarbeiter {
                let kennung = Namen.reineKennung(mitarbeiter)
                let schluessel = Hauptagent.ist(kennung) ? store.chat.mainKey : "agent:\(kennung):main"
                conversation.target = ConversationTarget(sessionKey: schluessel, leaderName: Namen.mitarbeiter(mitarbeiter), opening: nil)
            }
            go(1, quick: false)
        case .aufgaben:
            berichte.tab = .aufgaben
            show(.bereiche)
        case .berichte:
            berichte.tab = .berichte
            show(.bereiche)
        case .arbeit(let teil):
            if teil == .fragen, let f = store.stand.flatMap({ TeamLogik.offeneFragen($0).first }) { entscheide = f } else { arbeit = .board }
        case .kalender(let tag):
            kalenderTag = tag
            show(.kalender)
        case .statistik:
            show(.statistik)
        case .einstellungen:
            einstellungenOeffnen()
        }
    }

    private func einstellungenOeffnen() {
        guard !einstellungen else { return }
        reading = nil
        if t.p > 0 { go(0, quick: false) }
        Bewegung.mit(.seite) { einstellungen = true }
    }

    private func einstellungenSchliessen() {
        Bewegung.mit(.seite) { einstellungen = false }
    }

    private func federOhneFinger(_ layer: Page, to target: Double) {
        release = SpringRelease(at: Date(), from: visible(layer), to: target, velocity: 0, duration: reduceMotion ? 0.2 : 0.55)
        releaseLayer = layer
    }

    private func show(_ target: Page) {
        switch target {
        case .seneca: go(1, quick: false)
        case .today:
            if t.p > 0 { go(0, quick: false) }
            if let offen = [Page.statistik, .kalender, .bereiche].first(where: { side.progress($0) > 0 }) {
                federOhneFinger(offen, to: 0)
            }
            kalenderFokus = nil
            kalenderTag = nil
            brueckeEnde()
            setSide(SideState())
        case .kalender, .bereiche, .statistik:
            if t.p > 0 { go(0, quick: false) }
            if let offen = [Page.statistik, .kalender, .bereiche].first(where: { $0 != target && side.progress($0) > 0 }) {
                federOhneFinger(offen, to: 0)
            }
            federOhneFinger(target, to: 1)
            guard !alive(target) else { setSide(SideState.only(target, 1)); return }
            pagesAlive.insert(target)
            let waits = mountDay()
            if !waits { side = SideState.only(target, 0) }
            Task { @MainActor in
                if waits {
                    try? await Task.sleep(for: .milliseconds(30))
                    side = SideState.only(target, 0)
                }
                try? await Task.sleep(for: .milliseconds(30))
                if side.progress(target) == 0 { side = SideState.only(target, 1) }
            }
        }
    }

    private func brueckeBauen(_ fokus: KalenderFokus?) {
        brueckeEnde()
        guard let fokus, fokus.from != .zero, !reduceMotion else { return }
        bruecke = fokus
        brueckeAb = Date()
        brueckeNr += 1
        let nr = brueckeNr
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if nr == brueckeNr { brueckeEnde() }
        }
    }

    private func brueckeStarten() {
        guard bruecke != nil, brueckeZiel != nil, brueckeEintrag != nil, brueckeP == 0 else { return }
        let nr = brueckeNr
        DispatchQueue.main.async {
            guard nr == brueckeNr else { return }
            withAnimation(Animation.spring(duration: 0.7, bounce: 0), completionCriteria: .logicallyComplete) {
                brueckeP = 1
            } completion: {
                let rest = 1.6 - Date().timeIntervalSince(brueckeAb)
                Task { @MainActor in
                    if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
                    if nr == brueckeNr { brueckeEnde() }
                }
            }
        }
    }

    private func brueckeEnde() {
        guard bruecke != nil || brueckeP != 0 else { return }
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) {
            bruecke = nil; brueckeZiel = nil; brueckeEintrag = nil; brueckeP = 0
        }
        brueckeNr += 1
    }

    private func screen(_ m: Metrics, day: DayState, input: DayInput, now: Date) -> some View {
        #if DEBUG
        WischMessung.wurzel += 1
        #endif
        let center = CGPoint(x: 110, y: 465)
        let scale: CGFloat = 1
        let lightAnimation: Animation? = reduceMotion ? nil : Sundartha.light
        let coreOpacity = 0.0
        let coreAnimation: Animation? = nil
        let breath: LightField.Breath = conversation.isRunning ? .think : conversation.isListening ? .listen : .calm
        return ZStack(alignment: .topLeading) {
            Sundartha.grund
            LightField(metrics: m, center: center, scale: scale, lightAnimation: lightAnimation,
                       progress: day.progress, burst: 0, coreOpacity: coreOpacity, coreAnimation: coreAnimation,
                       breath: breath, reduceMotion: reduceMotion, pulse: reduceMotion ? 0 : lightPulse)
                .opacity(lichtEingang)
            BottomShade()
                .opacity(lichtEingang)
            if dayMounted {
                TodayLayer(m: m, day: day, zug: wisch.seneca, heroOverride: heroOverride, reduceMotion: reduceMotion,
                           openSeneca: { openFromHero(day) }, allowTap: { tapAllowed() })
                    .equatable()
                    .modifier(DayAwayLive(zug: wisch.seiten, m: m, reduceMotion: reduceMotion))
                    .modifier(UnterSenecaLive(zug: wisch.seneca, breite: m.size.width, reduceMotion: reduceMotion))
                    .opacity(inhaltEingang)
                    .offset(y: reduceMotion ? 0 : 12 * (1 - inhaltEingang))
                    .allowsHitTesting(page == .today)
                    .modifier(AXHidden(hidden: page != .today))
            }
            if alive(.kalender) {
                KalenderLayer(m: m, input: input, now: now, back: { zurueck() },
                              gesturesChanged: { pageGestures[.kalender] = $0 })
                    .environment(\.kalenderFokus, kalenderFokus)
                    .environment(\.kalenderFokusVerdeckt, bruecke != nil)
                    .environment(\.kalenderTag, kalenderTag)
                    .modifier(PageMotionLive(zug: wisch.seiten, page: .kalender, away: CGSize(width: -m.size.width * 0.32, height: 0), reduceMotion: reduceMotion))
                    .modifier(SenecaCoverLive(zug: wisch.seneca, reduceMotion: reduceMotion))
                    .allowsHitTesting(page == .kalender)
                    .modifier(AXHidden(hidden: page != .kalender))
                    .scrollClaims(visible: page == .kalender)
            }
            if alive(.bereiche) {
                AufgabenLayer(m: m, now: now, back: { zurueck() }, allowTap: { tapAllowed() }, gesturesChanged: { pageGestures[.bereiche] = $0 })
                    .environmentObject(berichte)
                    .modifier(PageMotionLive(zug: wisch.seiten, page: .bereiche, away: CGSize(width: 0, height: m.y(120)),
                                             awaySeitlich: CGSize(width: m.size.width * 0.32, height: 0), reduceMotion: reduceMotion))
                    .statusBarEdgeFade(m)
                    .modifier(SenecaCoverLive(zug: wisch.seneca, reduceMotion: reduceMotion))
                    .allowsHitTesting(page == .bereiche)
                    .modifier(AXHidden(hidden: page != .bereiche))
                    .scrollClaims(visible: page == .bereiche)
            }
            if alive(.statistik) {
                StatistikLayer(m: m, back: { zurueck() }, gesturesChanged: { pageGestures[.statistik] = $0 }, allowTap: { tapAllowed() })
                    .modifier(PageMotionLive(zug: wisch.seiten, page: .statistik, away: CGSize(width: m.size.width * 0.32, height: 0), reduceMotion: reduceMotion))
                    .modifier(SenecaCoverLive(zug: wisch.seneca, reduceMotion: reduceMotion))
                    .allowsHitTesting(page == .statistik)
                    .modifier(AXHidden(hidden: page != .statistik))
                    .scrollClaims(visible: page == .statistik)
            }
            if let bruecke, let ziel = brueckeZiel, let e = brueckeEintrag {
                KalenderZeile(m: m, e: e, stil: .tag, cal: input.calendar, offen: false, umschalten: {})
                    .frame(width: ziel.width, alignment: .topLeading)
                    .modifier(KalenderBrueckeFlug(p: brueckeP,
                                                  von: CGPoint(x: ziel.minX, y: bruecke.from.maxY + m.y(6)),
                                                  nach: ziel.origin))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("app.state")
                .accessibilityValue(page.rawValue)
            HaptikProbe(haptics: haptics)
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("app.overlay")
                .accessibilityValue(reading != nil ? "lesen" : einstellungen ? "einstellungen" : "")
            SenecaLayer(m: m, zug: wisch.seneca, aktiv: page == .seneca, sichtbar: !wisch.lage.senecaZu, model: conversation, reduceMotion: reduceMotion, keyboardHeight: keyboard,
                        close: { go(0, quick: false) }, allowTap: { tapAllowed() }, zurueckZiel: senecaZurueckZiel,
                        zurueckZieht: { chatZurueckZieht($0, breite: m.size.width) },
                        zurueckLos: { chatZurueckLos($0, $1, breite: m.size.width) })
                .allowsHitTesting(t.p > 0.5 && reading == nil)
                .modifier(AXHidden(hidden: t.p <= 0.5 || reading != nil))
                .scrollClaims(visible: t.p > 0.5)
            if einstellungen {
                EinstellungenSeite(zurueckName: senecaZurueckZiel, schliessen: { einstellungen = false })
                    .transition(.move(edge: .trailing))
                    .zIndex(0.5)
            }
            if let reading {
                ReadingView(m: m, doc: reading, close: { self.reading = nil })
                    .wischZurueck { self.reading = nil }
                    .id(reading.id)
                    .transition(.identity)
                    .zIndex(1)
            }
        }
        .frame(width: m.size.width, height: m.size.height)
        .contentShape(Rectangle())
        .onPreferenceChange(ScrollClaimsKey.self) { scrollClaims = $0 }
        .onPreferenceChange(KalenderFokusZeileKey.self) { rahmen in
            guard bruecke != nil, let rahmen else { return }
            if let alt = brueckeZiel, abs(alt.minY - rahmen.minY) < 0.5, abs(alt.minX - rahmen.minX) < 0.5 { return }
            brueckeZiel = rahmen
            brueckeStarten()
        }
        .onPreferenceChange(KalenderFokusEintragKey.self) { e in
            guard bruecke != nil, let e else { return }
            brueckeEintrag = e
            brueckeStarten()
        }
        .environment(\.appActions, appActions)
        .environment(\.wege, wege)
        .simultaneousGesture(drag(m))
    }

    private func dayState(_ now: Date) -> DayState { DayLogic.state(dayInput(now)) }

    private func dayInput(_ now: Date) -> DayInput {
        let snap = store.today
        return DayInput(now: now, calendar: .current, entries: store.kalenderEintraege, jobs: snap?.jobs ?? [],
                             leaders: snap?.leaders ?? [:], tasks: snap?.tasks ?? [], days: store.days,
                             routineDoneToday: store.routineDone(on: now),
                             needs: snap.map { NeedsInput(now: now, calendar: .current, snapshot: $0, localSeen: store.localSeen) })
    }

    private var heroOverride: HeroText? {
        guard store.today == nil else { return nil }
        if !store.isConfigured {
            return HeroText(line1: "Verbinde mich", line2Prefix: "mit deinem ", emphasis: "Mac", line2Suffix: ".", sub: "Halte das Datum gedrückt, um die Verbindung einzurichten.", mode: .plain)
        }
        let unreachable = store.connectionStatus == "Mac nicht erreichbar"
        return HeroText(line1: "Einen Moment,", line2Prefix: "ich hole deinen ", emphasis: "Tag", line2Suffix: ".",
                        sub: unreachable ? "Dein Mac ist gerade nicht erreichbar. Ich versuche es weiter." : "Seneca verbindet sich mit deinem Mac.", mode: .plain)
    }

    private var notice: String? {
        if let failure = store.saveFailure { return failure }
        if conversation.lateAnswer != nil { return "Seneca hat auf deine Frage geantwortet. Tippe hier, um die Antwort zu lesen." }
        guard store.isConfigured, !store.demo || store.connectionStatus == "Mac nicht erreichbar", store.today != nil else { return nil }
        if !store.isConnected && store.connectionStatus == "Mac nicht erreichbar" {
            let waiting = store.outbox.filter { $0.kind != .day && $0.kind != .seen }.count
            return DayLogic.offlineSatz(stand: store.lastSync, now: Date(), wartend: waiting, .current)
        }
        return store.isConnected ? store.error : nil
    }

    private func openFromHero(_ day: DayState) {
        if heroOverride == nil, reading == nil, let erste = day.needs.first, erste.kind == .results, erste.lines.count > 1 {
            berichte.tab = .berichte
            show(.bereiche)
            return
        }
        openChat(day)
    }

    private func openChat(_ day: DayState) {
        go(1, quick: false)
        guard heroOverride == nil, !day.needs.isEmpty else { return }
        let keys = NeedsYou.keys(day.needs)
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.25 : 0.9))
            store.markSeen(keys)
        }
    }

    private var senecaZurueckZiel: String {
        if side.bereiche > 0.5 { return "Aufgaben" }
        if side.kalender > 0.5 { return "Kalender" }
        if side.statistik > 0.5 { return "Statistik" }
        return "Heute"
    }

    private func chatZurueckZieht(_ dx: CGFloat, breite: CGFloat) {
        if chatZugStart == nil {
            guard dragLayer == nil, reading == nil else { return }
            brueckeEnde()
            chatZugStart = visible(.seneca)
            release = nil
            haptics.prepareDetent()
        }
        guard let start = chatZugStart else { return }
        zieh(.seneca, start: start, auf: min(1, max(0, start - Double(dx / max(breite, 1)))), seitlich: true)
    }

    private func chatZurueckLos(_ dx: CGFloat, _ vx: CGFloat, breite: CGFloat) {
        guard let start = chatZugStart else { return }
        chatZugStart = nil
        if abs(dx) >= tapSlop { lastDragEnd = Date() }
        loslassen(.seneca, start: start, speed: -Double(vx), distanz: Double(breite), seitlich: true)
    }

    @State private var release: SpringRelease?
    @State private var releaseLayer: Page?
    @State private var dragReach: CGFloat = 0
    private let tapSlop: CGFloat = 24

    private func go(_ target: Double, quick: Bool, velocity: Double = 0, seitlich: Bool = false) {
        let opening = target == 1 && t.p < 1
        let from = visible(.seneca)
        t = TransitionState(p: target, dragging: false, dir: target, quick: quick, velocity: velocity, seitlich: seitlich)
        release = SpringRelease(at: Date(), from: from, to: target, velocity: velocity, duration: quick ? 0.55 : 0.85)
        releaseLayer = .seneca
        if target == 1 {
            if opening { conversation.begin(after: quick ? 0.35 : 0.9) }
        } else {
            conversation.end()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private func progress(of layer: Page) -> Double {
        switch layer {
        case .seneca: return t.p
        case .kalender, .bereiche, .statistik: return side.progress(layer)
        case .today: return 0
        }
    }

    private func visible(_ layer: Page) -> Double {
        if let release, releaseLayer == layer, !(layer == .seneca ? t.dragging : side.dragging) {
            return release.value()
        }
        return progress(of: layer)
    }

    private var visiblePage: Page {
        if visible(.seneca) > 0.5 { return .seneca }
        for layer in [Page.statistik, .kalender, .bereiche] where visible(layer) > 0.5 { return layer }
        return .today
    }

    private func tapAllowed() -> Bool {
        if dragReach >= tapSlop { return false }
        return Date().timeIntervalSince(lastDragEnd) > 0.1
    }

    private func drag(_ m: Metrics) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                dragReach = max(dragReach, hypot(dx, dy))
                if dragIgnored { return }
                if dragLayer == nil {
                    guard let axis = PageGesture.axis(dx: dx, dy: dy) else { return }
                    let from = visiblePage
                    if reading != nil || einstellungen { dragIgnored = true; return }
                    if from == .seneca {
                        if keyboard > 0, axis == .vertical, dy > 0 {
                            if !scrollClaims.contains(where: { $0.contains(value.startLocation) }) { conversation.dismissKeyboard() }
                            dragIgnored = true; return
                        }
                        guard axis == .vertical, dy < 0,
                              conversation.kopfFrame?.contains(value.startLocation) == true else { dragIgnored = true; return }
                    } else if keyboard > 0 || (from == .today && todayGestures.typing) {
                        dragIgnored = true
                        if from != .today {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        return
                    }
                    if from == .today {
                        if axis == .vertical, todayGestures.claims(value.startLocation) { dragIgnored = true; return }
                        if axis == .horizontal && todayGestures.rowOpen { dragIgnored = true; return }
                        if axis == .horizontal && dx < 0 && todayGestures.ownsLeftSwipe(value.startLocation) { dragIgnored = true; return }
                    }
                    if axis == .vertical, !(from == .bereiche && dy > 0), scrollClaims.contains(where: { $0.contains(value.startLocation) }) { dragIgnored = true; return }
                    guard let layer = PageGesture.layer(from: from, axis: axis, dx: dx, dy: dy) else { dragIgnored = true; return }
                    if layer == from, pageGestures[from]?.holdsBack == true { dragIgnored = true; return }
                    if layer != .seneca { mountDay() }
                    dragLayer = layer
                    dragSeitlich = layer == .bereiche && axis == .horizontal
                    brueckeEnde()
                    dragStart = visible(layer)
                    dragNull = value.translation
                    release = nil
                    haptics.prepareDetent()
                    #if DEBUG
                    WischMessung.start(layer.rawValue)
                    #endif
                }
                guard let layer = dragLayer, let start = dragStart else { return }
                let formel = dragSeitlich ? Page.statistik : layer
                zieh(layer, start: start, auf: PageGesture.progress(formel, start: start, dx: dx - dragNull.width, dy: dy - dragNull.height,
                                                                    travel: m.travel, width: m.size.width), seitlich: dragSeitlich)
            }
            .onEnded { value in
                defer {
                    dragStart = nil; dragLayer = nil; dragIgnored = false; dragNull = .zero; dragSeitlich = false
                    if dragReach >= tapSlop { lastDragEnd = Date() }
                    dragReach = 0
                }
                guard let layer = dragLayer, let start = dragStart, !dragIgnored else { return }
                let formel = dragSeitlich ? Page.statistik : layer
                loslassen(layer, start: start, speed: PageGesture.speed(formel, vx: value.velocity.width, vy: value.velocity.height),
                          distanz: PageGesture.distance(formel, travel: m.travel, width: m.size.width), seitlich: dragSeitlich)
            }
    }

    private func zieh(_ layer: Page, start: Double, auf p: Double, seitlich: Bool = false) {
        #if DEBUG
        WischMessung.schritt()
        #endif
        let before = (layer == .seneca ? t.dragging : side.dragging) ? progress(of: layer) : start
        if PageGesture.crossesThreshold(start: start, from: before, to: p) { haptics.detent() }
        switch layer {
        case .seneca:
            var next = t
            next.p = p
            next.dragging = true
            next.dir = p >= start ? 1 : 0
            next.velocity = 0
            next.seitlich = seitlich
            t = next
        case .kalender, .bereiche, .statistik:
            var next = SideState.only(layer, p, dragging: true)
            next.seitlich = seitlich
            side = next
        case .today: break
        }
    }

    private func loslassen(_ layer: Page, start: Double, speed: Double, distanz distance: Double, seitlich: Bool = false) {
        let current = progress(of: layer)
        let target = PageGesture.target(start: start, progress: current, speed: speed)
        let v = springVelocity(speed / distance, from: current, to: target)
        switch layer {
        case .seneca:
            if target == 1 && start >= 0.5 {
                t = TransitionState(p: 1, dragging: false, dir: 1, quick: true, velocity: v, seitlich: seitlich)
            } else if target == 0 && start < 0.5 {
                t = TransitionState(p: 0, dragging: false, dir: 0, quick: true, velocity: v, seitlich: seitlich)
            } else {
                go(target, quick: true, velocity: v, seitlich: seitlich)
            }
        case .kalender, .bereiche, .statistik:
            var next = SideState.only(layer, target)
            next.velocity = v
            next.seitlich = seitlich
            side = next
        case .today: break
        }
        release = SpringRelease(at: Date(), from: current, to: target, velocity: v)
        releaseLayer = layer
        #if DEBUG
        WischMessung.ende()
        #endif
    }

    #if DEBUG
    private func kunstWisch(_ layer: Page) async {
        guard layer != .today else { return }
        if layer != .seneca { mountDay() }
        brueckeEnde()
        let start = visible(layer)
        dragLayer = layer
        dragStart = start
        release = nil
        haptics.prepareDetent()
        WischMessung.start(layer.rawValue)
        let ziel = start < 0.5 ? 0.7 : 0.3
        for i in 1...30 {
            zieh(layer, start: start, auf: start + (ziel - start) * Double(i) / 30)
            try? await Task.sleep(for: .milliseconds(16))
        }
        let mm = Metrics(size: UIScreen.main.bounds.size, safeTop: 0, safeBottom: 0)
        loslassen(layer, start: start, speed: 0, distanz: PageGesture.distance(layer, travel: mm.travel, width: mm.size.width))
        dragStart = nil
        dragLayer = nil
    }
    #endif

    private func launch() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["SENECA_DEMO"] == "1" {
            var now = Date()
            if let time = env["SENECA_DEMO_TIME"], let parts = Optional(time.split(separator: ":").compactMap { Int($0) }), parts.count == 2 {
                let day = env["SENECA_DEMO_DATE"].flatMap { try? Date($0 + "T12:00:00Z", strategy: .iso8601) } ?? Date()
                now = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)!
                let real = Date()
                let minuteStart = Calendar.current.dateInterval(of: .minute, for: real)!.start
                clockOffset = now.timeIntervalSince(minuteStart)
                let offset = clockOffset
                store.clock = { Date().addingTimeInterval(offset) }
            }
            store.loadDemo(now: now, streak: Int(env["SENECA_DEMO_STREAK"] ?? "") ?? 11, record: Int(env["SENECA_DEMO_REKORD"] ?? "") ?? 3,
                           todos: env["SENECA_DEMO_AUFGABEN"] != "0", routineDone: env["SENECA_DEMO_ROUTINE"] != "0",
                           needs: env["SENECA_DEMO_NEEDS"] == "1")
            if env["SENECA_DEMO_AUFGABEN"] == "many" { store.loadDemoManyTodos() }
            store.chat.loadDemo(now: now, admin: env["SENECA_DEMO_ADMIN"] ?? "1")
            store.chat.demoPace = env["SENECA_DEMO_LIVE"] ?? "normal"
            store.chat.demoQueued = env["SENECA_DEMO_WARTESCHLANGE"] == "1"
            conversation.store = store
            conversation.demoAnswer = env["SENECA_DEMO_ANSWER"]?.replacingOccurrences(of: "\\n", with: "\n")
            conversation.demoVoice = env["SENECA_DEMO_VOICE"]
            conversation.demoAnswers = env["SENECA_DEMO_ANSWERS"].map { $0.replacingOccurrences(of: "\\n", with: "\n").components(separatedBy: "||") } ?? []
            conversation.demoVoices = env["SENECA_DEMO_VOICES"].map { $0.components(separatedBy: "||") } ?? []
            conversation.demoMute = env["SENECA_DEMO_MUTE"] == "1"
            if let mode = env["SENECA_DEMO_GATEWAYVOICE"] { conversation.speech.gateway = SpeechController.demoGateway(mode) }
            conversation.demoMic = env["SENECA_DEMO_MIC"] == "1"
            await runDemoScript(env)
            return
        }
        conversation.store = store
        if env["SENECA_DEMO_WECHSEL"] == "1" { Task { try? await Task.sleep(for: .seconds(6)); go(1, quick: true) } }
        if let debugURL = env["SENECA_GATEWAY_URL"] {
            let debugToken = env["SENECA_GATEWAY_TOKEN"] ?? ""
            let session = env["SENECA_SESSION"] ?? Hauptagent.sitzung
            if env["SENECA_PERSIST_CONNECTION"] == "1", let parsed = URL(string: debugURL), parsed.scheme == "https", parsed.host?.hasSuffix(".ts.net") == true {
                try? CredentialStore.save(debugToken)
                gatewayURL = debugURL
                sessionKey = session
            }
            store.configure(url: debugURL, token: debugToken, sessionKey: session)
            await store.connect()
            await runDemoScript(env)
            return
        }
        #endif
        conversation.store = store
        if !gatewayURL.isEmpty {
            if Sinne.shared.sollFragen {
                Sinne.shared.gefragtMerken()
                sinneFrage = true
            }
            await reconnect()
        }
    }

    private func reconnect() async {
        #if DEBUG
        if store.demo { return }
        if ProcessInfo.processInfo.environment["SENECA_GATEWAY_URL"] != nil { await store.connect(); return }
        #endif
        guard !gatewayURL.isEmpty else { return }
        store.configure(url: gatewayURL, token: CredentialStore.load(), sessionKey: sessionKey)
        await store.connect()
    }

    private static var startSide: SideState {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["SENECA_DEMO"] == "1" else { return SideState() }
        switch env["SENECA_DEMO_PAGE"] {
        case "kalender": return SideState.only(.kalender, 1)
        case "statistik": return SideState.only(.statistik, 1)
        case "bereiche": return SideState.only(.bereiche, 1)
        default: return SideState()
        }
        #else
        return SideState()
        #endif
    }

    #if DEBUG
    private func runDemoScript(_ env: [String: String]) async {
        if env["SENECA_DEMO_PAGE"] == "lesen" { reading = .demo }
        if let p = env["SENECA_DEMO_P"].flatMap(Double.init) {
            t = TransitionState(p: p, dragging: true, dir: 1, quick: false)
        }
        guard let script = env["SENECA_DEMO_SCRIPT"] else { return }
        let start = Date()
        for step in script.split(separator: ",") {
            let parts = step.split(separator: "@")
            guard parts.count == 2, let at = Double(parts[1]) else { continue }
            let wait = at - Date().timeIntervalSince(start)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            let action = String(parts[0])
            switch action {
            case "routine": store.setRoutine(!store.routineDone(on: store.clock()))
            case "open": go(1, quick: false)
            case "hero": openFromHero(dayState(store.clock()))
            case "close": go(0, quick: false)
            case "kalender", "morgen": show(.kalender)
            case "bereiche": show(.bereiche)
            case "statistik": show(.statistik)
            case "einstellungen": oeffne(.einstellungen)
            case "arbeit": oeffne(.arbeit(.fragen))
            case "laeuft": oeffne(.arbeit(.laeuft))
            case "zurueck": zurueck()
            case "sprechen", "gespraech":
                conversation.sprechWunschTaste = action == "sprechen"
                conversation.sprechWunschOffen = true
                conversation.sprechWunsch += 1
            case "lesen": reading = .demo
            case "heute": setSide(SideState()); reading = nil
            case "ask":
                conversation.transcript = env["SENECA_DEMO_ASK"] ?? "Was steht heute noch an?"
                conversation.submitTyped()
            default:
                if action.hasPrefix("ask:") { conversation.transcript = String(action.dropFirst(4)); conversation.submitTyped() }
                else if action.hasPrefix("offen:"), let n = Int(action.dropFirst(6)) {
                    for t in store.heutigeAufgaben().filter({ !$0.isDone }).dropFirst(n) { store.toggleTask(t.id) }
                }
                else if action.hasPrefix("wisch:"), let ebene = Page(rawValue: String(action.dropFirst(6))) { await kunstWisch(ebene) }
                else if action.hasPrefix("seitlich=") { t = TransitionState(p: Double(action.dropFirst(9)) ?? 0.5, dragging: true, seitlich: true) }
                else if action.hasPrefix("halb:"), let ebene = Page(rawValue: String(action.dropFirst(5))) {
                    pagesAlive.insert(ebene); mountDay(); side = SideState.only(ebene, 0.45, dragging: true)
                }
                else if action.hasPrefix("aufgabenSeitlich=") {
                    var s = SideState.only(.bereiche, Double(action.dropFirst(17)) ?? 0.5, dragging: true)
                    s.seitlich = true
                    mountDay(); side = s
                }
                else if action.hasPrefix("p=") { t = TransitionState(p: Double(action.dropFirst(2)) ?? 0, dragging: true, dir: 1, quick: false) }
                else if action.hasPrefix("add:") { store.addTask(String(action.dropFirst(4))) }
                else if action.hasPrefix("todo:"), let n = Int(action.dropFirst(5)) {
                    let todos = dayState(store.clock()).todos
                    if n < todos.count { store.toggleTask(todos[n].id) }
                }
                else { store.toggleTask(action) }
            }
        }
    }
    #endif
}

extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let show = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0 }
        let hide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification).map { _ in CGFloat(0) }
        return show.merge(with: hide).eraseToAnyPublisher()
    }
}

private struct AXHidden: ViewModifier {
    var hidden: Bool
    func body(content: Content) -> some View {
        content.accessibilityHidden(hidden)
    }
}
