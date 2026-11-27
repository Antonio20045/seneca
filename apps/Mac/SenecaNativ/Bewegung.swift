import SwiftUI

struct Bezier {
    var x1: Double, y1: Double, x2: Double, y2: Double
    static let ease = Bezier(x1: 0.22, y1: 0.8, x2: 0.24, y2: 1)
    static let cssEase = Bezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)

    func wert(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        func b(_ t: Double, _ a: Double, _ c: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * c * t * t * (1 - t) + t * t * t }
        var unten = 0.0, oben = 1.0
        for _ in 0..<24 {
            let mitte = (unten + oben) / 2
            if b(mitte, x1, x2) < x { unten = mitte } else { oben = mitte }
        }
        return b((unten + oben) / 2, y1, y2)
    }
}

private func weich(_ p: Double) -> Double { 0.5 - cos(Double.pi * min(max(p, 0), 1)) / 2 }

struct Kugel: View {
    var seite: CGFloat = 18
    @Environment(\.fensterSichtbar) private var sichtbar

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !sichtbar)) { ctx in
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
            let atmen = weich(p < 0.5 ? p * 2 : (1 - p) * 2)
            let welle = Bezier.ease.wert(p)
            ZStack {
                Circle().strokeBorder(Farbe.himmel.opacity(0.30), lineWidth: 1)
                    .scaleEffect(0.55 + 1.45 * welle).opacity(0.9 * (1 - welle))
                Circle()
                    .fill(RadialGradient(stops: [.init(color: Farbe.papier, location: 0), .init(color: Farbe.kugelLicht, location: 0.3),
                                                 .init(color: Farbe.himmel, location: 0.62), .init(color: Farbe.himmel, location: 1)],
                                         center: UnitPoint(x: 0.34, y: 0.32), startRadius: 0, endRadius: (seite - 6) / 1.6))
                    .padding(3)
                    .scaleEffect(1 - 0.2 * atmen)
                    .shadow(color: Farbe.himmel.opacity(0.41 - 0.19 * atmen), radius: 12 - 7 * atmen)
            }
            .frame(width: seite, height: seite)
        }
        .accessibilityHidden(true)
    }
}

struct PulsPunkt: View {
    var farbe: Color
    var laeuft: Bool
    var groesse: CGFloat = 7
    @Environment(\.fensterSichtbar) private var sichtbar

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !laeuft || !sichtbar)) { ctx in
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
            let f = Bezier.cssEase.wert(min(p / 0.7, 1))
            let ring = laeuft ? 7 * f : 0
            ZStack {
                Circle().strokeBorder(Farbe.koralle.opacity(0.45 * (1 - f)), lineWidth: max(ring, 0.001))
                    .frame(width: groesse + 2 * ring, height: groesse + 2 * ring)
                Circle().fill(farbe).frame(width: groesse, height: groesse)
            }
            .frame(width: groesse, height: groesse)
        }
    }
}

struct BlinkStrich: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let an = Int(ctx.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
            RoundedRectangle(cornerRadius: 2).fill(Farbe.himmel).frame(width: 8, height: 16).opacity(an ? 1 : 0.25)
        }
        .accessibilityHidden(true)
    }
}

extension SchrittArt {
    var farbe: Color {
        switch self {
        case .web, .lesen, .suche: return Farbe.himmel
        case .agent: return Farbe.gruen
        case .schreiben, .plan: return Farbe.bernstein
        case .gedanke: return Farbe.perleGedanke
        case .befehl, .warten, .nachricht, .sonst: return Farbe.perleNeutral
        }
    }

    var symbol: String {
        switch self {
        case .web: return "globe"
        case .lesen: return "book"
        case .suche: return "magnifyingglass"
        case .schreiben: return "pencil"
        case .befehl: return "terminal"
        case .agent: return "person.2"
        case .plan: return "list.bullet"
        case .gedanke: return "sparkles"
        case .warten: return "clock"
        case .nachricht: return "bubble.left"
        case .sonst: return "plus"
        }
    }
}

private struct SatzWeg: ViewModifier {
    var aktiv: Bool
    var richtung: CGFloat
    func body(content: Content) -> some View {
        content.opacity(aktiv ? 0 : 1).offset(y: aktiv ? 11 * richtung : 0).blur(radius: aktiv ? 3 : 0)
    }
}

extension AnyTransition {
    static var satz: AnyTransition {
        .asymmetric(insertion: .modifier(active: SatzWeg(aktiv: true, richtung: 1), identity: SatzWeg(aktiv: false, richtung: 1)),
                    removal: .modifier(active: SatzWeg(aktiv: true, richtung: -1), identity: SatzWeg(aktiv: false, richtung: -1)))
    }
}

struct Erscheint: ViewModifier {
    enum Art {
        case steigt, laufrein, mzrein, auf
        var dauer: Double { switch self { case .steigt: return 0.55; case .laufrein: return 0.6; case .mzrein: return 0.5; case .auf: return 0.35 } }
        var abstand: CGFloat { switch self { case .steigt: return 22; case .laufrein: return 10; case .mzrein: return 7; case .auf: return -4 } }
        var groesse: CGFloat { switch self { case .steigt: return 0.97; case .laufrein: return 0.96; default: return 1 } }
        var unschaerfe: CGFloat { self == .mzrein ? 3 : 0 }
        var kurve: Animation { self == .auf ? Kurve.ease(dauer) : Kurve.feder(dauer) }
    }
    var art: Art
    var aktiv = true
    var verzoegerung = 0.0
    @State private var da = false

    func body(content: Content) -> some View {
        content
            .opacity(!aktiv || da ? 1 : 0)
            .offset(y: !aktiv || da ? 0 : art.abstand)
            .scaleEffect(!aktiv || da ? 1 : art.groesse)
            .blur(radius: !aktiv || da ? 0 : art.unschaerfe)
            .onAppear { if aktiv { withAnimation(art.kurve.delay(verzoegerung)) { da = true } } }
    }
}

extension View {
    func erscheint(_ art: Erscheint.Art, wenn aktiv: Bool = true, verzoegerung: Double = 0) -> some View {
        modifier(Erscheint(art: art, aktiv: aktiv, verzoegerung: verzoegerung))
    }
}

private struct Aufklappen: Shape {
    var anteil: Double
    var animatableData: Double { get { anteil } set { anteil = newValue } }
    func path(in r: CGRect) -> Path {
        Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * anteil), cornerRadius: 24, style: .continuous)
    }
}

struct Entfaltet: ViewModifier {
    var aktiv: Bool
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(!aktiv || da ? 1 : 0)
            .offset(y: !aktiv || da ? 0 : -8)
            .clipShape(Aufklappen(anteil: !aktiv || da ? 1.2 : 0))
            .onAppear { if aktiv { withAnimation(Kurve.ease(0.95).delay(0.1)) { da = true } } }
    }
}

struct KernRein: ViewModifier {
    var aktiv: Bool
    var dauer = 0.8
    var verzoegerung = 0.16
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(!aktiv || da ? 1 : 0)
            .offset(y: !aktiv || da ? 0 : 9)
            .blur(radius: !aktiv || da ? 0 : 6)
            .onAppear { if aktiv { withAnimation(Kurve.ease(dauer).delay(verzoegerung)) { da = true } } }
    }
}

struct SpurLandet: ViewModifier {
    var aktiv: Bool
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(!aktiv || da ? 1 : 0)
            .scaleEffect(!aktiv || da ? 1 : 0.94)
            .blur(radius: !aktiv || da ? 0 : 5)
            .onAppear { if aktiv { withAnimation(Kurve.ease(0.75)) { da = true } } }
    }
}

struct PerleLandet: ViewModifier {
    var aktiv: Bool
    var index: Int
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(!aktiv || da ? 1 : 0)
            .offset(x: !aktiv || da ? 0 : 40 + CGFloat(index) * 10)
            .scaleEffect(!aktiv || da ? 1 : 1.5)
            .onAppear { if aktiv { withAnimation(Kurve.feder(0.7).delay(Double(index) * 0.055)) { da = true } } }
    }
}

extension View {
    func entfaltet(_ aktiv: Bool) -> some View { modifier(Entfaltet(aktiv: aktiv)) }
    func kernRein(_ aktiv: Bool, dauer: Double = 0.8, verzoegerung: Double = 0.16) -> some View {
        modifier(KernRein(aktiv: aktiv, dauer: dauer, verzoegerung: verzoegerung))
    }
    func spurLandet(_ aktiv: Bool) -> some View { modifier(SpurLandet(aktiv: aktiv)) }
    func perleLandet(_ aktiv: Bool, index: Int) -> some View { modifier(PerleLandet(aktiv: aktiv, index: index)) }
}
