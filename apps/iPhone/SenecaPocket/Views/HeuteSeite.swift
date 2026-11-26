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
        a.m == b.m && a.day == b.day && a.zug === b.zug
            && a.heroOverride == b.heroOverride && a.reduceMotion == b.reduceMotion
    }
}

struct TodayLayer: View {
    var m: Metrics
    var day: DayState
    var zug: Wisch.Wert<TransitionState>
    var heroOverride: HeroText?
    var reduceMotion: Bool
    var openSeneca: () -> Void
    var allowTap: () -> Bool

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.wege) private var wege

    @State private var fenster: UIEdgeInsets = .zero
    private var oben: CGFloat { max(m.safeTop, fenster.top) }
    private var unten: CGFloat { max(m.safeBottom, fenster.bottom) }

    var body: some View {
        if heroOverride == nil {
            Group {
                if let r = store.stand?.rueckblick {
                    RueckblickTafel(r: r) { store.antworte(frage: $0, wahl: $1) }
                } else if let stand = store.stand {
                    HeuteTafel(stand: stand, wartend: store.wartendeTodos, erledige: { store.erledige(todo: $0) },
                               antworte: { f, wahl in store.antworte(frage: f.id, wahl: wahl) }, oeffne: oeffne, allowTap: allowTap)
                } else {
                    HeuteSkelett()
                }
            }
            .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
            .outEffect(zug, (0, 0.5), lift: 30, reduceMotion: reduceMotion)
        } else {
            sprechSeite
        }
    }

    private func oeffne(_ z: HeuteTafel.Ziel) {
        switch z {
        case .gespraeche: openSeneca()
        case .aufgaben: wege.oeffne(.aufgaben)
        case .laeuft: wege.oeffne(.arbeit(.laeuft))
        case .frage: wege.oeffne(.arbeit(.fragen))
        case .einstellungen: wege.oeffne(.einstellungen)
        }
    }

    private var sprechSeite: some View {
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
                }
                Spacer(minLength: 0)
            }
            .seitenRand()
        }
        .padding(.top, oben + Stil.kopfOben)
        .padding(.bottom, unten + Stil.unten - Stil.abstand.m)
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .onAppear { DispatchQueue.main.async { fenster = Stil.fensterRaender } }
    }

    private func kopf(_ now: Date) -> some View {
        let zeile = day.dateLine
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
        }
        .frame(minHeight: Stil.tippFlaeche)
        .padding(.trailing, -Stil.abstand.xs)
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
}
