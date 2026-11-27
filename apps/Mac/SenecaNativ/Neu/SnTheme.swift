import SwiftUI

extension Farbe {
    static let grundOben = Color(hex: 0x0E2A57)
    static let kugelKern = Color(hex: 0xCFE4FA)
    static let himmelLicht2 = Color(hex: 0x6E9CE0)
    static let blatt = Color(hex: 0xEFE9DD)
    static let blattTinte = Color(hex: 0x12294C)
    static let blattTinte2 = Color(hex: 0x536076)
    static let blattRot = Color(hex: 0xA34A2A)
    static let blattRand = Color(hex: 0xC46246, deckkraft: 0.45)
    static let blattLinie = Color(hex: 0x12294C, deckkraft: 0.12)
    static let zeileHover = Color(hex: 0x142B4C, deckkraft: 0.85)
}

extension Kurve {
    static func sn(_ dauer: Double) -> Animation { .timingCurve(0.22, 0.8, 0.24, 1, duration: dauer) }
    static var snFeder: Animation { .spring(response: 0.5, dampingFraction: 0.75) }
}

private struct SnRein: ViewModifier {
    var verzoegerung: Double
    @State private var da = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    func body(content: Content) -> some View {
        content
            .opacity(da ? 1 : 0)
            .offset(y: da || ruhig ? 0 : 14)
            .onAppear {
                withAnimation(ruhig ? .easeOut(duration: 0.2) : Kurve.sn(0.7).delay(verzoegerung)) { da = true }
            }
    }
}

private struct SnMaske: ViewModifier {
    var verzoegerung: Double
    @State private var da = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    func body(content: Content) -> some View {
        content
            .opacity(da ? 1 : 0)
            .offset(y: da || ruhig ? 0 : 26)
            .mask(alignment: .top) {
                GeometryReader { g in
                    Rectangle()
                        .frame(width: g.size.width + 40, height: ruhig || da ? g.size.height * 1.6 : 0)
                        .offset(x: -20, y: -g.size.height * 0.15)
                }
            }
            .onAppear {
                withAnimation(ruhig ? .easeOut(duration: 0.2) : Kurve.sn(0.9).delay(verzoegerung)) { da = true }
            }
    }
}

extension View {
    func snSeitenBlende() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.62), .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom).frame(height: 92)
                Color.black
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.5), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom).frame(height: 150)
            }
        }
    }

    func snRein(_ verzoegerung: Double = 0) -> some View { modifier(SnRein(verzoegerung: verzoegerung)) }
    func snMaske(_ verzoegerung: Double = 0) -> some View { modifier(SnMaske(verzoegerung: verzoegerung)) }
}

extension View {
    func snFlaeche(_ radius: CGFloat = 16, deckkraft: Double = 0.06) -> some View {
        let form = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(form.fill(Color.white.opacity(deckkraft)))
            .overlay(form.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.1), location: 0), .init(color: .clear, location: 0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false))
    }

    @ViewBuilder func snGlas<S: InsettableShape>(_ form: S) -> some View {
        Group {
            if HeuteBild.ziel != nil {
                self.background(Color.white.opacity(0.08), in: form)
            } else if #available(macOS 26, *) {
                self.glassEffect(.regular.tint(Color.white.opacity(0.08)), in: form)
            } else {
                self.background(.ultraThinMaterial, in: form)
                    .background(Color.white.opacity(0.08), in: form)
            }
        }
        .overlay {
            form.strokeBorder(LinearGradient(stops: [
                .init(color: Color.white.opacity(0.18), location: 0),
                .init(color: Color.white.opacity(0), location: 0.12),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .allowsHitTesting(false)
        }
        .shadow(color: Color(hex: 0x020816, deckkraft: 0.45), radius: 18, y: 16)
    }
}

struct SnKugel: View {
    var groesse: CGFloat
    var atmet = true
    @Environment(\.accessibilityReduceMotion) private var ruhig
    @Environment(\.fensterSichtbar) private var sichtbar

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !atmet || ruhig || !sichtbar)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let e = atmet && !ruhig ? (1 - cos(2 * .pi * t / 18)) / 2 : 0
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Farbe.kugelKern, location: 0.22),
                    .init(color: Farbe.himmelLicht2.opacity(0.45), location: 0.5),
                    .init(color: Farbe.himmelLicht2.opacity(0), location: 0.72),
                ], center: .center, startRadius: 0, endRadius: groesse * 0.7071))
                .frame(width: groesse, height: groesse)
                .scaleEffect(1 + 0.06 * e)
        }
        .frame(width: groesse, height: groesse)
        .accessibilityHidden(true)
    }
}

struct SnAgentKugel: View {
    var initial: String
    var groesse: CGFloat

    var body: some View {
        if initial.isEmpty {
            SnKugel(groesse: groesse, atmet: false)
        } else {
            Text(initial)
                .font(Schrift.serif((groesse * 0.55).rounded()))
                .foregroundStyle(Color.white)
                .frame(width: groesse, height: groesse)
                .background(Circle().fill(RadialGradient(colors: [Color(hex: 0x2E5185), Color(hex: 0x142B4C)],
                                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: groesse * 0.8)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}
