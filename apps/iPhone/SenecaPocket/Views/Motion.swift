import SwiftUI

extension Sundartha {
    static func exit(_ seconds: Double) -> Animation { .timingCurve(0.55, 0, 1, 0.45, duration: seconds) }
    static func travel(_ seconds: Double) -> Animation { .timingCurve(0.65, 0, 0.35, 1, duration: seconds) }
    static let press = Animation.spring(duration: 0.2, bounce: 0)
    static let small = Animation.spring(duration: 0.35, bounce: 0.2)
    static let layout = Animation.spring(duration: 0.5, bounce: 0)
    static let morph = Animation.spring(duration: 0.6, bounce: 0)
    static let light = Animation.spring(duration: 0.8, bounce: 0)
    static func page(_ velocity: Double = 0, duration: Double = 0.55) -> Animation {
        .interpolatingSpring(duration: duration, bounce: 0, initialVelocity: max(-12, min(12, velocity)))
    }
    static let fade = Animation.easeOut(duration: 0.2)
}

func springVelocity(_ vp: Double, from p: Double, to target: Double) -> Double {
    let distance = target - p
    return abs(distance) < 0.001 ? 0 : max(-12, min(12, vp / distance))
}

struct SpringRelease: Equatable {
    var at: Date
    var from: Double
    var to: Double
    var velocity: Double
    var duration: Double = 0.55

    func value(at now: Date = Date()) -> Double {
        let t = now.timeIntervalSince(at)
        let distance = to - from
        guard t < duration * 2, abs(distance) > 0.0001 else { return to }
        let spring = Spring(duration: duration, bounce: 0)
        let moved = spring.value(target: distance, initialVelocity: velocity * distance, time: t)
        return from + moved
    }
}

struct Unmask: ViewModifier, Animatable {
    var p: Double
    var lineHeight: CGFloat
    var travel: CGFloat? = nil
    var reduceMotion = false
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(p)
        } else {
            content
                .offset(y: (1 - p) * (travel ?? lineHeight * 1.05))
                .padding(.vertical, lineHeight * 0.18)
                .padding(.horizontal, lineHeight * 0.08)
                .clipShape(Rectangle())
                .padding(.vertical, -lineHeight * 0.18)
                .padding(.horizontal, -lineHeight * 0.08)
        }
    }
}

extension AnyTransition {
    static func quietLine(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: Unmask(p: 0, lineHeight: 18, travel: 8), identity: Unmask(p: 1, lineHeight: 18, travel: 8)),
            removal: .opacity)
    }
}

struct ProgressIn: ViewModifier, Animatable {
    var p: Double
    var range: (Double, Double)
    var lift: CGFloat = 0
    var maxOpacity: Double = 1
    var reduceMotion: Bool
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let lp = seg(p, range.0, range.1)
        content
            .opacity(maxOpacity * lp)
            .offset(y: reduceMotion ? 0 : (1 - lp) * lift)
    }
}

extension View {
    func progressIn(_ t: TransitionState, _ range: (Double, Double), lift: CGFloat = 0, maxOpacity: Double = 1, reduceMotion: Bool) -> some View {
        modifier(ProgressIn(p: t.p, range: range, lift: lift, maxOpacity: maxOpacity, reduceMotion: reduceMotion))
            .animation(t.animation(reduceMotion), value: t.p)
    }
}
