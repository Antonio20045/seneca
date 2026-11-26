import SwiftUI
import Combine

@MainActor
final class Wisch: ObservableObject {
    @MainActor
    final class Wert<T: Equatable>: ObservableObject {
        @Published var wert: T
        init(_ wert: T) { self.wert = wert }
    }

    struct Lage: Equatable {
        var page: Page
        var kalender: Bool
        var bereiche: Bool
        var statistik: Bool
        var senecaZu: Bool
        var seiteRuht: Page?

        init(_ t: TransitionState, _ side: SideState) {
            if t.p > 0.5 { page = .seneca }
            else if side.statistik > 0.5 { page = .statistik }
            else if side.kalender > 0.5 { page = .kalender }
            else if side.bereiche > 0.5 { page = .bereiche }
            else { page = .today }
            kalender = side.kalender > 0
            bereiche = side.bereiche > 0
            statistik = side.statistik > 0
            senecaZu = t.p == 0 && !t.dragging
            seiteRuht = side.dragging ? nil : [Page.statistik, .kalender, .bereiche].first { side.progress($0) == 1 }
        }
    }

    let seneca: Wert<TransitionState>
    let seiten: Wert<SideState>
    private(set) var lage: Lage

    init(side: SideState = SideState()) {
        seneca = Wert(TransitionState())
        seiten = Wert(side)
        lage = Lage(TransitionState(), side)
    }

    var t: TransitionState {
        get { seneca.wert }
        set {
            guard newValue != seneca.wert else { return }
            seneca.wert = newValue
            lagePruefen()
        }
    }

    var side: SideState {
        get { seiten.wert }
        set {
            guard newValue != seiten.wert else { return }
            seiten.wert = newValue
            lagePruefen()
        }
    }

    private func lagePruefen() {
        let neu = Lage(seneca.wert, seiten.wert)
        guard neu != lage else { return }
        objectWillChange.send()
        lage = neu
    }
}

struct DayAwayLive: ViewModifier {
    @ObservedObject var zug: Wisch.Wert<SideState>
    var m: Metrics
    var reduceMotion: Bool
    func body(content: Content) -> some View {
        content.dayAway(m: m, side: zug.wert, reduceMotion: reduceMotion)
    }
}

struct PageMotionLive: ViewModifier {
    @ObservedObject var zug: Wisch.Wert<SideState>
    var page: Page
    var away: CGSize
    var awaySeitlich: CGSize? = nil
    var reduceMotion: Bool
    func body(content: Content) -> some View {
        let s = zug.wert
        let a = s.seitlich ? (awaySeitlich ?? away) : away
        content.pageMotion(progress: s.progress(page), dragging: s.dragging, away: a, reduceMotion: reduceMotion, velocity: s.velocity)
    }
}

struct KalenderWeichtLive: ViewModifier {
    @ObservedObject var zug: Wisch.Wert<SideState>
    var m: Metrics
    var reduceMotion: Bool
    func body(content: Content) -> some View {
        content.kalenderWeicht(m: m, side: zug.wert, reduceMotion: reduceMotion)
    }
}

struct SenecaCoverLive: ViewModifier {
    @ObservedObject var zug: Wisch.Wert<TransitionState>
    var reduceMotion: Bool
    func body(content: Content) -> some View {
        content.senecaCover(t: zug.wert, reduceMotion: reduceMotion)
    }
}

struct HaptikProbe: View {
    @ObservedObject var haptics: Haptics
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("app.haptics")
            .accessibilityValue(haptics.probe)
    }
}

@MainActor
final class TagStand {
    private var minute: Int?
    private var stand: (input: DayInput, day: DayState)?
    private var veraltet = true
    private var abo: AnyCancellable?
    private weak var quelle: SenecaStore?

    func stand(now: Date, store: SenecaStore, eingabe: (Date) -> DayInput) -> (input: DayInput, day: DayState) {
        if quelle !== store {
            quelle = store
            veraltet = true
            abo = store.objectWillChange.sink { [weak self] _ in self?.veraltet = true }
        }
        let m = Int((now.timeIntervalSince1970 / 60).rounded(.down))
        if !veraltet, minute == m, let stand { return stand }
        let input = eingabe(now)
        let neu = (input: input, day: DayLogic.state(input))
        #if DEBUG
        WischMessung.tag += 1
        #endif
        veraltet = false
        minute = m
        stand = neu
        return neu
    }
}

struct WischZurueck: ViewModifier {
    var vollbild: Bool
    var ebene: (() -> Bool)? = nil
    var zurueck: () -> Void
    @State private var x: CGFloat = 0
    @State private var breite: CGFloat = 390
    @State private var fertig = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: vollbild ? x : x * 0.5)
            .opacity(vollbild ? 1 : 1 - Double(min(x / breite, 1)) * 0.5)
            .shadow(color: .black.opacity(vollbild && x > 0 ? 0.35 : 0), radius: 18, x: -6)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 > 0 { breite = $0 } }
            .gesture(ZurueckPan(
                zieht: { dx in guard !fertig else { return }; x = max(0, dx) },
                losgelassen: { dx, vx in
                    guard !fertig else { return }
                    if WischZurueckLogik.schliesst(dx: dx, vx: vx, breite: breite), let ebene, ebene() {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { x = 0 }
                    } else if WischZurueckLogik.schliesst(dx: dx, vx: vx, breite: breite) {
                        fertig = true
                        UISelectionFeedbackGenerator().selectionChanged()
                        let rest = max(breite - x, 1)
                        let feder: Animation = reduceMotion ? .easeOut(duration: 0.12)
                            : .interpolatingSpring(duration: 0.32, bounce: 0, initialVelocity: Double(min(max(vx, 0) / rest, 12)))
                        withAnimation(feder, completionCriteria: .logicallyComplete) { x = breite } completion: {
                            if vollbild {
                                var t = Transaction(); t.disablesAnimations = true
                                withTransaction(t) { zurueck() }
                            } else {
                                zurueck()
                            }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { x = 0 }
                    }
                }))
            .modifier(KlarerGrund(an: vollbild))
            .accessibilityAction(named: "Zurück") { zurueck() }
    }
}

private struct KlarerGrund: ViewModifier {
    var an: Bool
    func body(content: Content) -> some View {
        if an { content.presentationBackground(.clear) } else { content }
    }
}

enum WischZurueckLogik {
    static func schliesst(dx: CGFloat, vx: CGFloat, breite: CGFloat) -> Bool {
        if vx < -200 { return false }
        if vx > 500 && dx > 30 { return true }
        return dx > breite / 3
    }
    static func beginnt(dx: CGFloat, dy: CGFloat) -> Bool { dx > 0 && dx >= 1.3 * abs(dy) }
}

struct ZurueckPan: UIGestureRecognizerRepresentable {
    var zieht: (CGFloat) -> Void
    var losgelassen: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Delegat { Delegat() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let r = UIPanGestureRecognizer()
        r.maximumNumberOfTouches = 1
        r.delegate = context.coordinator
        return r
    }

    func handleUIGestureRecognizerAction(_ r: UIPanGestureRecognizer, context: Context) {
        let t = r.translation(in: r.view)
        switch r.state {
        case .began, .changed: zieht(t.x)
        case .ended: losgelassen(t.x, r.velocity(in: r.view).x)
        case .cancelled, .failed: losgelassen(0, 0)
        default: break
        }
    }

    final class Delegat: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let t = pan.translation(in: view), v = pan.velocity(in: view)
            let dx = abs(t.x) + abs(t.y) > 2 ? t.x : v.x, dy = abs(t.x) + abs(t.y) > 2 ? t.y : v.y
            guard WischZurueckLogik.beginnt(dx: dx, dy: dy) else { return false }
            var v2 = view.hitTest(pan.location(in: view), with: nil)
            while let s = v2 {
                if let sv = s as? UIScrollView, sv.contentSize.width > sv.bounds.width + 1,
                   sv.contentOffset.x > -sv.adjustedContentInset.left + 1 { return false }
                v2 = s.superview
            }
            return true
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let sv = other.view as? UIScrollView, other === sv.panGestureRecognizer else { return false }
            return sv.contentSize.width <= sv.bounds.width + 1
        }
    }
}

extension View {
    func wischZurueck(vollbild: Bool = true, ebene: (() -> Bool)? = nil, _ zurueck: @escaping () -> Void) -> some View {
        modifier(WischZurueck(vollbild: vollbild, ebene: ebene, zurueck: zurueck))
    }
}
