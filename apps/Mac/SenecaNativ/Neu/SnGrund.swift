import SwiftUI

struct SnGrund: View, Animatable {
    var fortschritt: Double

    var animatableData: Double {
        get { fortschritt }
        set { fortschritt = newValue }
    }

    var body: some View {
        let p = min(1, max(0, fortschritt))
        GeometryReader { g in
            let b = g.size.width, h = g.size.height
            let r1 = hypot(max(0.74 * b, 0.26 * b), max(0.14 * h, 0.86 * h))
            let r2 = hypot(max(0.06 * b, 0.94 * b), h)
            ZStack {
                LinearGradient(colors: [Farbe.grundOben, Farbe.nachtUnten], startPoint: .top, endPoint: .bottom)
                Rectangle()
                    .fill(RadialGradient(stops: [
                        .init(color: Farbe.himmel.opacity(0.5), location: 0),
                        .init(color: Farbe.himmel.opacity(0.3), location: 0.09),
                        .init(color: Farbe.himmel.opacity(0.12), location: 0.18),
                        .init(color: Farbe.himmel.opacity(0), location: 0.27),
                    ], center: UnitPoint(x: 0.74, y: 0.14), startRadius: 0, endRadius: r1))
                    .opacity(0.5 + 0.5 * p)
                Rectangle()
                    .fill(RadialGradient(colors: [Farbe.himmelLicht2.opacity(0.2), Farbe.himmelLicht2.opacity(0)],
                                         center: UnitPoint(x: 0.06, y: 1), startRadius: 0, endRadius: r2 * 0.3))
                LinearGradient(stops: [
                    .init(color: Farbe.nachtUnten.opacity(0), location: 0.52),
                    .init(color: Farbe.nachtUnten.opacity(0.4), location: 0.80),
                    .init(color: Farbe.nachtUnten.opacity(0.7), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: b, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
