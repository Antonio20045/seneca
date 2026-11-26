import SwiftUI

@MainActor
enum LightImages {
    static let softPadding: CGFloat = 60
    static let soft: Image = {
        let view = Circle()
            .fill(RadialGradient(stops: [
                .init(color: Sundartha.himmel.opacity(0.42), location: 0),
                .init(color: Sundartha.himmel.opacity(0.28), location: 0.26),
                .init(color: Sundartha.himmel.opacity(0.11), location: 0.48),
                .init(color: Sundartha.himmel.opacity(0), location: 0.66),
            ], center: .center, startRadius: 0, endRadius: 438.4))
            .frame(width: 620, height: 620)
            .blur(radius: 30)
            .padding(softPadding)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.5
        return renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "circle")
    }()
    static let coreSize: CGFloat = 200
    static let core: Image = {
        let view = Circle()
            .fill(RadialGradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.96), location: 0.20),
                .init(color: Color(red: 207 / 255, green: 228 / 255, blue: 250 / 255).opacity(0.8), location: 0.42),
                .init(color: Color(red: 110 / 255, green: 156 / 255, blue: 224 / 255).opacity(0.45), location: 0.60),
                .init(color: Color(red: 110 / 255, green: 156 / 255, blue: 224 / 255).opacity(0), location: 0.76),
            ], center: .center, startRadius: 0, endRadius: 127.3))
            .frame(width: coreSize, height: coreSize)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "circle.fill")
    }()
}

final class BreathClock {
    private var last: Date?
    private var phase: Double = 0
    func advance(to date: Date, period: Double) -> Double {
        if let last { phase += max(0, min(0.1, date.timeIntervalSince(last))) / period }
        last = date
        phase = phase.truncatingRemainder(dividingBy: 1000)
        return phase
    }
}

struct LightField: View {
    enum Breath { case calm, listen, think }
    var metrics: Metrics
    var center: CGPoint
    var scale: CGFloat
    var lightAnimation: Animation?
    var progress: Double
    var burst: Int
    var coreOpacity: Double
    var coreAnimation: Animation?
    var breath: Breath
    var reduceMotion: Bool
    var pulse: Int = 0

    @State private var clock = BreathClock()
    @State private var driftStart = Date()

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSince(driftStart)
                let e = reduceMotion ? 0 : (1 - cos(2 * .pi * t / 18)) / 2
                Self.softLight(metrics: metrics)
                    .scaleEffect(1 + 0.06 * e)
                    .offset(x: 18 * e * metrics.sx, y: -22 * e * metrics.sy)
            }
            .keyframeAnimator(initialValue: 1.0, trigger: burst) { content, value in
                content.scaleEffect(value)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.35, duration: 0.54)
                    CubicKeyframe(1.0, duration: 1.26)
                }
            }
            .keyframeAnimator(initialValue: 0.0, trigger: pulse) { content, k in
                content
                    .scaleEffect(1 + 0.04 * k)
                    .overlay { if k > 0.001 { content.opacity(0.12 * k) } }
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.0, duration: 0.25)
                    CubicKeyframe(1.0, duration: 0.3)
                    CubicKeyframe(0.0, duration: 0.9)
                }
            }
            .scaleEffect(0.7 + 0.55 * progress)
            .opacity(0.45 + 0.55 * progress)
            .animation(reduceMotion ? nil : Sundartha.ease(1.6), value: progress)

            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || coreOpacity < 0.01)) { context in
                let period = breath == .calm ? 5.0 : breath == .listen ? 1.4 : 0.7
                let phase = clock.advance(to: context.date, period: period)
                let s = reduceMotion ? 1 : 1 + 0.08 * (1 - cos(2 * .pi * phase)) / 2
                LightImages.core
                    .resizable()
                    .frame(width: LightImages.coreSize / 0.7 * metrics.fs, height: LightImages.coreSize / 0.7 * metrics.fs)
                    .scaleEffect(s)
            }
            .opacity(coreOpacity)
            .animation(coreAnimation, value: coreOpacity)
        }
        .frame(width: 0, height: 0)
        .scaleEffect(scale)
        .position(x: metrics.x(center.x), y: metrics.y(center.y))
        .animation(lightAnimation, value: center)
        .animation(lightAnimation, value: scale)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func softLight(metrics: Metrics) -> some View {
        let side = (620 + 2 * LightImages.softPadding) * metrics.fs
        return LightImages.soft.resizable().frame(width: side, height: side)
    }
}

struct BottomShade: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Sundartha.grundUnten.opacity(0), location: 0.52),
            .init(color: Sundartha.grundUnten.opacity(0.4), location: 0.80),
            .init(color: Sundartha.grundUnten.opacity(0.7), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
