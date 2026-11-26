import SwiftUI

struct TransitionState: Equatable {
    var p: Double = 0
    var dragging = false
    var dir: Double = 1
    var quick = false
    var velocity: Double = 0
    var seitlich = false

    func animation(_ reduceMotion: Bool) -> Animation? {
        if dragging { return nil }
        if reduceMotion { return Sundartha.fade }
        return Sundartha.page(velocity, duration: quick ? 0.55 : 0.85)
    }
}

private struct OutEffect: ViewModifier, Animatable {
    var p: Double
    var range: (Double, Double)
    var lift: CGFloat
    var reduceMotion: Bool
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let lp = seg(p, range.0, range.1)
        content
            .opacity(1 - lp)
            .offset(y: reduceMotion ? 0 : -lift * lp)
    }
}

private struct OutEffectLive: ViewModifier {
    @ObservedObject var zug: Wisch.Wert<TransitionState>
    var range: (Double, Double)
    var lift: CGFloat
    var reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .modifier(OutEffect(p: zug.wert.seitlich ? 0 : zug.wert.p, range: range, lift: lift, reduceMotion: reduceMotion))
            .animation(zug.wert.animation(reduceMotion), value: zug.wert.p)
    }
}

extension View {
    fileprivate func outEffect(_ zug: Wisch.Wert<TransitionState>, _ range: (Double, Double), lift: CGFloat, reduceMotion: Bool) -> some View {
        modifier(OutEffectLive(zug: zug, range: range, lift: lift, reduceMotion: reduceMotion))
    }
}

extension TodayLayer: Equatable {
    static func == (a: TodayLayer, b: TodayLayer) -> Bool {
        a.m == b.m && a.day == b.day && a.zug === b.zug && a.notice == b.notice
            && a.heroOverride == b.heroOverride && a.reduceMotion == b.reduceMotion
    }
}

struct TodayLayer: View {
    var m: Metrics
    var day: DayState
    var zug: Wisch.Wert<TransitionState>
    var notice: String?
    var heroOverride: HeroText?
    var reduceMotion: Bool
    var openSeneca: () -> Void
    var openSettings: () -> Void
    var retry: () -> Void
    var toggleTodo: (String) -> Void
    var toggleRoutine: () -> Void = {}
    var allowTap: () -> Bool
    var showCalendar: () -> Void = {}
    var showAreas: () -> Void = {}
    var showStatistics: () -> Void = {}

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.wege) private var wege
    @ObservedObject private var quelle = TagesablaufQuelle.shared
    @ObservedObject private var listen = ListenModell.gemeinsam
    @State private var neuOffen = false
    @State private var laeuftOffen = false
    @State private var bereit = false

    @State private var fenster: UIEdgeInsets = .zero
    private var oben: CGFloat { max(m.safeTop, fenster.top) }
    private var unten: CGFloat { max(m.safeBottom, fenster.bottom) }

    var body: some View {
        #if DEBUG
        let _ = (WischMessung.heute += 1)
        #endif
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            let now = store.clock()
            VStack(alignment: .leading, spacing: 0) {
                kopf(now)
                    .outEffect(zug, (0.15, 0.55), lift: 20, reduceMotion: reduceMotion)
                if let o = heroOverride {
                    HeuteSatzText(satz: KopfSatz(vor: o.line1 + " " + o.line2Prefix, akzent: o.emphasis, nach: o.line2Suffix, leise: o.sub))
                        .padding(.top, Stil.abstand.xl)
                        .contentShape(Rectangle())
                        .onTapGesture { if allowTap() { wege.oeffne(.chat()) } }
                        .outEffect(zug, (0.06, 0.52), lift: 40, reduceMotion: reduceMotion)
                        .accessibilityIdentifier("heute.satz")
                } else {
                    HeuteJetzt(m: m, day: day, jetzt: now, punkte: quelle.punkte, bereit: bereit, reduceMotion: reduceMotion,
                               allowTap: allowTap, toggleRoutine: toggleRoutine)
                        .padding(.top, Stil.abstand.l)
                        .outEffect(zug, (0.03, 0.5), lift: 30, reduceMotion: reduceMotion)
                    if let hinweis = hinweisText {
                        hinweisZeile(hinweis)
                            .padding(.top, Stil.abstand.m)
                            .transition(.wechsel)
                            .outEffect(zug, (0, 0.45), lift: 30, reduceMotion: reduceMotion)
                    }
                    HeuteTodos(jetzt: now, allowTap: allowTap, toggleTodo: toggleTodo)
                        .padding(.top, Stil.abstand.s)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .outEffect(zug, (0, 0.45), lift: 30, reduceMotion: reduceMotion)
                    fuss(now)
                        .outEffect(zug, (0, 0.45), lift: 30, reduceMotion: reduceMotion)
                }
                if heroOverride != nil { Spacer(minLength: 0) }
            }
            .bewegt(.wechsel, wert: hinweisText)
            .seitenRand()
        }
        .padding(.top, oben + Stil.kopfOben)
        .padding(.bottom, unten + Stil.unten - Stil.abstand.m)
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .ignoresSafeArea(.keyboard)
        .onAppear { DispatchQueue.main.async { fenster = Stil.fensterRaender } }
        .neueAufgabeBlatt(isPresented: $neuOffen, jetzt: { store.clock() })
        .senecaBlatt(isPresented: $laeuftOffen, groesse: .halb, titel: "Läuft gerade") {
            LaeuftInhalt(zeilen: quelle.laeuft ?? [])
        }
        #if DEBUG
        .task {
            if let r = ProcessInfo.processInfo.environment["SENECA_DEMO_ARBEIT"].flatMap(ArbeitReiter.init(rawValue:)) {
                try? await Task.sleep(for: .seconds(2.5))
                wege.oeffne(.arbeit(r == .fragen ? .fragen : r == .board ? .laeuft : .projekte))
                return
            }
            guard ProcessInfo.processInfo.environment["SENECA_DEMO_HEUTE_BLATT"] == "laeuft" else { return }
            try? await Task.sleep(for: .seconds(2.5))
            laeuftOffen = true
        }
        #endif
        .task(id: heroOverride == nil) {
            guard heroOverride == nil else { bereit = false; return }
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled { bereit = true }
        }
    }

    private func kopf(_ now: Date) -> some View {
        var zeile = day.dateLine
        if heroOverride == nil, let g = Tagesablauf.ganztags(quelle.punkte, jetzt: now) { zeile += " · " + g }
        return HStack(alignment: .center, spacing: Stil.abstand.s) {
            Text(zeile)
                .schrift(.klein)
                .foregroundStyle(Stil.tinte.zweit)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.6) { wege.oeffne(.einstellungen) }
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("day.date")
                .accessibilityAction(named: "Einstellungen") { wege.oeffne(.einstellungen) }
                .accessibilityAction(named: "Kalender zeigen") { wege.oeffne(.kalender()) }
                .accessibilityAction(named: "Aufgaben zeigen") { wege.oeffne(.aufgaben) }
                .accessibilityAction(named: "Statistik zeigen") { wege.oeffne(.statistik) }
            Spacer(minLength: Stil.abstand.s)
            if heroOverride == nil {
                RundKnopf("plus", beschriftung: "Neu: Aufgabe oder Termin") {
                    guard allowTap() else { return }
                    neuOffen = true
                }
                .accessibilityIdentifier("heute.neueAufgabe")
            }
        }
        .frame(minHeight: Stil.tippFlaeche)
        .padding(.trailing, -Stil.abstand.xs)
    }

    private var hinweisText: String? {
        guard heroOverride == nil, let notice, !notice.hasPrefix("Mac nicht erreichbar") else { return nil }
        return notice
    }

    private func hinweisZeile(_ hinweis: String) -> some View {
        let spaet = hinweis.hasPrefix("Seneca hat")
        return HinweisZeile(spaet ? "Seneca hat auf deine Frage geantwortet." : hinweis, art: spaet ? .info : .fehler,
                            aktion: (spaet ? "Lesen" : "Nochmal", { if allowTap() { retry() } }))
            .accessibilityIdentifier("day.notice")
    }

    @ViewBuilder
    private func fuss(_ now: Date) -> some View {
        let laufen: Int = {
            if let l = listen.liste { return BoardSicht(l, jetzt: now, gelesen: listen.gelesen).laeuftZeilen.count }
            return quelle.laeuft?.count ?? 0
        }()
        VStack(alignment: .leading, spacing: 0) {
            HeuteBraucht(jetzt: now, allowTap: allowTap)
            if laufen > 0 {
                Button {
                    guard allowTap() else { return }
                    if listen.liste != nil { wege.oeffne(.arbeit(.laeuft)) } else { laeuftOffen = true }
                } label: {
                    HStack(spacing: Stil.abstand.s) {
                        LaeuftPunkte()
                        Text(laufen == 1 ? "1 Arbeit läuft ›" : "\(laufen) Arbeiten laufen ›")
                    }
                }
                .buttonStyle(TextKnopfStil(stufe: .klein))
                .accessibilityHint("Zeigt, wer woran arbeitet")
                .accessibilityIdentifier(listen.liste != nil ? "heute.board" : "heute.laeuft")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bewegt(.wechsel, wert: laufen > 0)
    }
}

struct TodayGestures: Equatable {
    var rowOpen = false
    var typing = false
    var listFrame: CGRect?
    var rowsFrame: CGRect?
    func claims(_ point: CGPoint) -> Bool { typing || (listFrame?.contains(point) ?? false) }
    func ownsLeftSwipe(_ point: CGPoint) -> Bool { rowsFrame?.contains(point) ?? false }
}

struct CheckRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.checkPressed, configuration.isPressed)
    }
}

private struct CheckPressedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var checkPressed: Bool {
        get { self[CheckPressedKey.self] }
        set { self[CheckPressedKey.self] = newValue }
    }
}

extension SenecaStore {
    var macUnerreichbar: Bool { !isConnected && connectionStatus == "Mac nicht erreichbar" && isConfigured }

    func topDreiMitGehaltenen(_ gehalten: Set<String>, anzahl: Int = 3, jetzt: Date? = nil) -> [SenecaTask] {
        Array(heutigeAufgaben(jetzt: jetzt).filter { !$0.isDone || gehalten.contains($0.id) }.prefix(anzahl))
    }

    func kommendeAufgaben(nach jetzt: Date, anzahl: Int = 3, _ cal: Calendar = .current) -> [DayLogic.AusblickTag] {
        let start = cal.startOfDay(for: jetzt)
        var tage: [DayLogic.AusblickTag] = []
        var gesamt = 0
        for n in 1...35 where gesamt < anzahl {
            guard let tag = cal.date(byAdding: .day, value: n, to: start) else { break }
            let titel = aufgaben(fuerTag: tag, jetzt: jetzt, cal).filter { !$0.isDone }.prefix(anzahl - gesamt).map { HeuteLogik.anzeigeTitel($0.title) }
            if !titel.isEmpty { tage.append(DayLogic.AusblickTag(tag: tag, titel: Array(titel))); gesamt += titel.count }
        }
        return tage
    }
}
