import SwiftUI
import UIKit

struct SideState: Equatable {
    var kalender: Double = 0
    var bereiche: Double = 0
    var statistik: Double = 0
    var dragging = false
    var velocity: Double = 0
    var seitlich = false

    func progress(_ page: Page) -> Double {
        switch page {
        case .kalender: return kalender
        case .bereiche: return bereiche
        case .statistik: return statistik
        case .today, .seneca: return 0
        }
    }

    static func only(_ page: Page, _ progress: Double, dragging: Bool = false) -> SideState {
        var s = SideState(dragging: dragging)
        switch page {
        case .kalender: s.kalender = progress
        case .bereiche: s.bereiche = progress
        case .statistik: s.statistik = progress
        case .today, .seneca: break
        }
        return s
    }
}

struct DayAway: ViewModifier, Animatable {
    var m: Metrics
    var side: SideState
    var reduceMotion: Bool

    init(m: Metrics, side: SideState, reduceMotion: Bool) {
        self.m = m
        self.side = side
        self.reduceMotion = reduceMotion
        kalender = side.kalender; bereiche = side.bereiche; statistik = side.statistik
    }
    private var kalender: Double
    private var bereiche: Double
    private var statistik: Double
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(kalender, bereiche), statistik) }
        set { kalender = newValue.first.first; bereiche = newValue.first.second; statistik = newValue.second }
    }

    func body(content: Content) -> some View {
        let p = max(kalender, bereiche, statistik)
        let unten = side.seitlich ? 0 : bereiche, rechts = side.seitlich ? bereiche : 0
        let von: PageFade.Richtung = unten > 0 ? .unten : kalender > 0 ? .links : .rechts
        content
            .offset(x: reduceMotion ? 0 : m.size.width * 0.32 * (kalender - statistik - rechts),
                    y: reduceMotion ? 0 : -m.y(120) * unten)
            .opacity(reduceMotion ? 1 - PageFade.blende(p) : 1 - 0.5 * p)
            .mask { PageFade.kante(p: p, von: von, ebene: false, size: m.size, aus: reduceMotion) }
    }
}

extension View {
    func dayAway(m: Metrics, side: SideState, reduceMotion: Bool) -> some View {
        modifier(DayAway(m: m, side: side, reduceMotion: reduceMotion))
            .animation(PageMotion.animation(side.dragging, reduceMotion, velocity: side.velocity), value: side)
    }
}

struct PageMotion: ViewModifier, Animatable {
    var progress: Double
    var dragging: Bool
    var away: CGSize
    var reduceMotion: Bool
    var velocity: Double = 0
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    static func animation(_ dragging: Bool, _ reduceMotion: Bool, velocity: Double = 0) -> Animation? {
        dragging ? nil : reduceMotion ? Sundartha.fade : Sundartha.page(velocity)
    }
    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : away.width * (1 - progress), y: reduceMotion ? 0 : away.height * (1 - progress))
            .opacity(reduceMotion ? PageFade.blende(progress) : 0.5 + 0.5 * progress)
            .mask { PageFade.kante(p: progress, von: away.height > 0 ? .unten : away.width > 0 ? .rechts : .links, ebene: true,
                                   size: UIScreen.main.bounds.size, aus: reduceMotion) }
    }
}

enum PageFade {
    enum Richtung { case links, rechts, oben, unten }
    static let feder: CGFloat = 64

    static func blende(_ p: Double) -> Double { seg(p, 0.3, 0.7) }

    @ViewBuilder static func kante(p: Double, von: Richtung, ebene: Bool, size: CGSize, aus: Bool) -> some View {
        if aus || (!ebene && p <= 0) || (ebene && p >= 1) {
            Color.black
        } else {
            let laenge = von == .oben || von == .unten ? size.height : size.width
            let mitte = CGFloat(p) * (laenge + feder) - feder / 2
            let a = (mitte - feder / 2) / laenge, b = (mitte + feder / 2) / laenge
            let farben: [Color] = ebene ? [.black, .clear] : [.clear, .black]
            switch von {
            case .links:
                LinearGradient(colors: farben, startPoint: UnitPoint(x: a, y: 0.5), endPoint: UnitPoint(x: b, y: 0.5))
            case .rechts:
                LinearGradient(colors: farben, startPoint: UnitPoint(x: 1 - a, y: 0.5), endPoint: UnitPoint(x: 1 - b, y: 0.5))
            case .oben:
                LinearGradient(colors: farben, startPoint: UnitPoint(x: 0.5, y: a), endPoint: UnitPoint(x: 0.5, y: b))
            case .unten:
                LinearGradient(colors: farben, startPoint: UnitPoint(x: 0.5, y: 1 - a), endPoint: UnitPoint(x: 0.5, y: 1 - b))
            }
        }
    }
}

extension View {
    func pageMotion(progress: Double, dragging: Bool, away: CGSize, reduceMotion: Bool, velocity: Double = 0) -> some View {
        modifier(PageMotion(progress: progress, dragging: dragging, away: away, reduceMotion: reduceMotion, velocity: velocity))
            .animation(PageMotion.animation(dragging, reduceMotion, velocity: velocity), value: progress)
    }
}

struct SenecaCover: ViewModifier, Animatable {
    var t: TransitionState
    var reduceMotion = false
    var animatableData: Double {
        get { t.p }
        set { t.p = newValue }
    }
    func body(content: Content) -> some View {
        content
            .opacity(t.seitlich ? 1 : 1 - seg(t.p, 0.05, 0.5))
            .modifier(UnterSenecaSeitlich(p: t.p, an: t.seitlich, breite: UIScreen.main.bounds.width, reduceMotion: reduceMotion))
    }
}

struct UnterSenecaSeitlich: ViewModifier, Animatable {
    var p: Double
    var an: Bool
    var breite: CGFloat
    var reduceMotion: Bool
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let wirkt = an && !reduceMotion
        let q = min(1, max(0, p))
        let kante = 1 - q, weich = Double(16 / max(breite, 1))
        let stops: [Gradient.Stop] = wirkt
            ? [.init(color: .black, location: 0), .init(color: .black, location: max(0, kante - weich)), .init(color: .clear, location: max(0, kante))]
            : [.init(color: .black, location: 0), .init(color: .black, location: 1)]
        content
            .offset(x: wirkt ? -0.3 * breite * CGFloat(q) : 0)
            .opacity(an ? (reduceMotion ? 1 - q : 1 - 0.3 * q) : 1)
            .mask(LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing))
    }
}

struct UnterSenecaLive: ViewModifier {
    @ObservedObject var zug: Wisch.Wert<TransitionState>
    var breite: CGFloat
    var reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .modifier(UnterSenecaSeitlich(p: zug.wert.p, an: zug.wert.seitlich, breite: breite, reduceMotion: reduceMotion))
            .animation(zug.wert.animation(reduceMotion), value: zug.wert.p)
    }
}

extension View {
    func senecaCover(t: TransitionState, reduceMotion: Bool) -> some View {
        modifier(SenecaCover(t: t, reduceMotion: reduceMotion))
            .animation(t.animation(reduceMotion), value: t.p)
    }
}

@MainActor
final class Haptics: ObservableObject {
    @Published private(set) var ticks = 0
    @Published private(set) var detents = 0
    @Published private(set) var pulses = 0
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)

    var probe: String { "tick \(ticks) · rast \(detents) · puls \(pulses)" }

    func tick() {
        light.impactOccurred()
        ticks += 1
    }

    func prepareDetent() { rigid.prepare() }

    func detent() {
        rigid.impactOccurred(intensity: 0.7)
        rigid.prepare()
        detents += 1
    }

    func recordPulse() {
        pulses += 1
        soft.impactOccurred(intensity: 0.6)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(540))
            soft.impactOccurred(intensity: 0.45)
        }
    }
}
