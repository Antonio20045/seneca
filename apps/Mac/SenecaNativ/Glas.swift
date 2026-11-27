import SwiftUI

extension Color {
    static func mische(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func k(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) / 255 }
        func m(_ s: UInt32) -> Double { k(a, s) + (k(b, s) - k(a, s)) * min(1, max(0, t)) }
        return Color(.sRGB, red: m(16), green: m(8), blue: m(0), opacity: 1)
    }
}

extension View {
    @ViewBuilder func glas<S: Shape>(_ form: S, toenung: Color? = nil, interaktiv: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if interaktiv {
                self.glassEffect(.regular.tint(toenung).interactive(), in: form)
            } else {
                self.glassEffect(.regular.tint(toenung), in: form)
            }
        } else {
            self.background(.ultraThinMaterial, in: form)
                .overlay(form.stroke(Farbe.linie, lineWidth: 1))
        }
    }

    @ViewBuilder func glasKnopf() -> some View {
        if #available(macOS 26, *) { self.buttonStyle(.glass) } else { self.buttonStyle(NebenKnopfStil()) }
    }
}

struct GlasTief<S: InsettableShape>: ViewModifier {
    var form: S
    var hebt: Bool
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    func body(content: Content) -> some View {
        let oben = hover ? 0.55 : 0.38
        content
            .glas(form, toenung: Color.white.opacity(0.02), interaktiv: hebt)
            .overlay {
                form.fill(LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)))
                    .allowsHitTesting(false)
            }
            .overlay {
                form.strokeBorder(LinearGradient(stops: [
                    .init(color: Color.white.opacity(oben), location: 0),
                    .init(color: Color.white.opacity(0.07), location: 0.45),
                    .init(color: Color.white.opacity(0.14), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false)
            }
            .background {
                form.fill(Color.black.opacity(hover ? 0.5 : 0.38))
                    .blur(radius: hover ? 30 : 24).offset(y: hover ? 18 : 14)
                    .mask { Rectangle().padding(-120).overlay { form.fill(Color.black).blendMode(.destinationOut) }.compositingGroup() }
                    .allowsHitTesting(false)
            }
            .scaleEffect(hebt && hover && !ruhig ? 1.008 : 1)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: hover)
            .onHover { if hebt { hover = $0 } }
    }
}

struct HoverSchein: ViewModifier {
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var ruhig
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(hover ? 0.07 : 0))
                    .padding(.horizontal, -12).padding(.vertical, 2)
            }
            .offset(x: hover && !ruhig ? 2 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hover)
            .onHover { hover = $0 }
    }
}

extension View {
    func glasTief<S: InsettableShape>(_ form: S, hebt: Bool = false) -> some View { modifier(GlasTief(form: form, hebt: hebt)) }
    func hoverSchein() -> some View { modifier(HoverSchein()) }
}

struct Abschnittstitel: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(Schrift.grotesk(11, .medium)).tracking(1.1).foregroundStyle(Farbe.ink3)
    }
}
