import SwiftUI
import UIKit

struct HauptKnopf: View {
    var titel: String
    var breit = false
    var aktion: () -> Void
    init(_ titel: String, breit: Bool = false, aktion: @escaping () -> Void) {
        self.titel = titel; self.breit = breit; self.aktion = aktion
    }
    var body: some View {
        Button(titel) { Haptik.tipp(); aktion() }
            .buttonStyle(KapselStil(art: .haupt, breit: breit))
    }
}

struct ZweitKnopf: View {
    var titel: String
    var breit = false
    var aktion: () -> Void
    init(_ titel: String, breit: Bool = false, aktion: @escaping () -> Void) {
        self.titel = titel; self.breit = breit; self.aktion = aktion
    }
    var body: some View {
        Button(titel) { Haptik.tipp(); aktion() }
            .buttonStyle(KapselStil(art: .zweit, breit: breit))
    }
}

struct TextKnopf: View {
    var titel: String
    var stufe: Stil.Schrift = .zeile
    var aktion: () -> Void
    init(_ titel: String, stufe: Stil.Schrift = .zeile, aktion: @escaping () -> Void) {
        self.titel = titel; self.stufe = stufe; self.aktion = aktion
    }
    var body: some View {
        Button(titel, action: aktion).buttonStyle(TextKnopfStil(stufe: stufe))
    }
}

struct RundKnopf: View {
    var symbol: String
    var beschriftung: String
    var voll = false
    var aktion: () -> Void
    init(_ symbol: String, beschriftung: String, voll: Bool = false, aktion: @escaping () -> Void) {
        self.symbol = symbol; self.beschriftung = beschriftung; self.voll = voll; self.aktion = aktion
    }
    var body: some View {
        Button { Haptik.tipp(); aktion() } label: {
            Image(systemName: symbol)
                .font(Stil.symbol(.klein, gewicht: .semibold))
                .foregroundStyle(voll ? Stil.farbe.aufHell : Stil.tinte.voll)
                .frame(width: Stil.rundKnopf, height: Stil.rundKnopf)
                .background(Circle().fill(voll ? AnyShapeStyle(Stil.tinte.voll) : AnyShapeStyle(Stil.tinte.flaecheStark)))
        }
        .buttonStyle(RundKnopfStil())
        .accessibilityLabel(beschriftung)
    }
}

struct KapselStil: ButtonStyle {
    enum Art { case haupt, zweit }
    var art: Art
    var breit = false
    func makeBody(configuration: Configuration) -> some View {
        KapselKoerper(art: art, breit: breit, configuration: configuration)
    }

    private struct KapselKoerper: View {
        var art: Art
        var breit: Bool
        var configuration: Configuration
        @Environment(\.isEnabled) private var aktiv
        var body: some View {
            let gedrueckt = configuration.isPressed
            configuration.label
                .schrift(.zeileWichtig)
                .lineLimit(1)
                .foregroundStyle(vordergrund)
                .padding(.horizontal, Stil.abstand.xl)
                .frame(maxWidth: breit ? .infinity : nil, minHeight: Stil.knopfHoehe)
                .background(Capsule().fill(hintergrund))
                .opacity(gedrueckt ? 0.78 : 1)
                .scaleEffect(gedrueckt ? 0.97 : 1)
                .contentShape(Capsule())
                .bewegt(.klein, wert: gedrueckt)
        }
        private var vordergrund: Color {
            guard aktiv else { return Stil.tinte.leise }
            return art == .haupt ? Stil.farbe.aufHell : Stil.tinte.voll
        }
        private var hintergrund: Color {
            guard aktiv else { return Stil.tinte.flaeche }
            return art == .haupt ? Stil.tinte.voll : Stil.tinte.flaecheStark
        }
    }
}

struct TextKnopfStil: ButtonStyle {
    var stufe: Stil.Schrift = .zeile
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .schrift(stufe)
            .foregroundStyle(Stil.tinte.zweit)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: Stil.tippFlaeche)
            .contentShape(Rectangle())
            .bewegt(.klein, wert: configuration.isPressed)
    }
}

struct RundKnopfStil: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .frame(width: Stil.tippFlaeche, height: Stil.tippFlaeche)
            .contentShape(Rectangle())
            .bewegt(.klein, wert: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KapselStil {
    static var haupt: KapselStil { KapselStil(art: .haupt) }
    static var zweit: KapselStil { KapselStil(art: .zweit) }
}

extension ButtonStyle where Self == TextKnopfStil {
    static var text: TextKnopfStil { TextKnopfStil() }
}

@MainActor
enum Haptik {
    static func tipp() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func auswahl() { UISelectionFeedbackGenerator().selectionChanged() }
    static func erledigt() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
