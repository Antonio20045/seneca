import SwiftUI
import UIKit

enum Bewegung: Equatable {
    case seite(geschwindigkeit: Double = 0)
    case blatt
    case wechsel
    case klein
    case atmen

    static let seite = Bewegung.seite()

    var kurve: Animation {
        switch self {
        case .seite(let v):
            let antwort = 0.38, daempfung = 0.86
            let steif = pow(2 * .pi / antwort, 2)
            return .interpolatingSpring(mass: 1, stiffness: steif, damping: 4 * .pi * daempfung / antwort,
                                        initialVelocity: max(-12, min(12, v)))
        case .blatt: return .spring(response: 0.42, dampingFraction: 0.9)
        case .wechsel: return .timingCurve(0.22, 1, 0.36, 1, duration: 0.25)
        case .klein: return .timingCurve(0.22, 1, 0.36, 1, duration: 0.15)
        case .atmen: return .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
        }
    }

    func kurve(reduziert: Bool) -> Animation? {
        guard reduziert else { return kurve }
        switch self {
        case .seite, .blatt: return .easeOut(duration: 0.2)
        case .wechsel, .klein: return kurve
        case .atmen: return nil
        }
    }

    @discardableResult
    static func mit<Ergebnis>(_ b: Bewegung, _ aenderung: () throws -> Ergebnis) rethrows -> Ergebnis {
        try withAnimation(b.kurve(reduziert: UIAccessibility.isReduceMotionEnabled), aenderung)
    }

    static func schwung(_ vp: Double, von p: Double, nach ziel: Double) -> Double {
        let rest = ziel - p
        return abs(rest) < 0.001 ? 0 : max(-12, min(12, vp / rest))
    }
}

private struct Bewegt<Wert: Equatable>: ViewModifier {
    var art: Bewegung
    var wert: Wert
    @Environment(\.accessibilityReduceMotion) private var reduziert
    func body(content: Content) -> some View {
        content.animation(art.kurve(reduziert: reduziert), value: wert)
    }
}

extension View {
    func bewegt<Wert: Equatable>(_ art: Bewegung, wert: Wert) -> some View {
        modifier(Bewegt(art: art, wert: wert))
    }
}

extension AnyTransition {
    static var wechsel: AnyTransition {
        .asymmetric(insertion: .opacity.animation(Bewegung.wechsel.kurve.delay(0.08)),
                    removal: .opacity.animation(Bewegung.klein.kurve))
    }
}

struct LaeuftPunkte: View {
    var farbe: Color = Stil.farbe.gruen
    @Environment(\.accessibilityReduceMotion) private var reduziert
    @State private var an = false

    var body: some View {
        HStack(spacing: Stil.abstand.xs) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(farbe)
                    .frame(width: 6, height: 6)
                    .opacity(reduziert ? 0.9 : (an ? 1 : 0.28))
                    .animation(Bewegung.atmen.kurve(reduziert: reduziert)?.delay(Double(i) * 0.25), value: an)
            }
        }
        .onAppear { an = true }
        .accessibilityHidden(true)
    }
}
