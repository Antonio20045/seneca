import SwiftUI

extension Color {
    init(hex: UInt32, deckkraft: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: deckkraft)
    }
}

enum Farbe {
    static let nacht = Color(hex: 0x0A2245)
    static let nachtUnten = Color(hex: 0x061632)
    static let papier = Color(hex: 0x142B4C)
    static let papier2 = Color(hex: 0x1E3454)
    static let himmel = Color(hex: 0x8FB6E3)
    static let himmelFlaeche = Color(hex: 0x8FB6E3, deckkraft: 0.12)
    static let gruen = Color(hex: 0x6BD98F)
    static let bernstein = Color(hex: 0xE8B84B)
    static let koralle = Color(hex: 0xE88A6B)
    static let ink = Color(hex: 0xE2E4E9)
    static let ink1 = Color.white
    static let ink2 = Color(hex: 0xBAC1CB)
    static let ink3 = Color(hex: 0x939EAD)
    static let ink4 = Color(hex: 0x939EAD, deckkraft: 0.62)
    static let flaeche = Color.white.opacity(0.05)
    static let flaeche2 = Color.white.opacity(0.08)
    static let linie = Color.white.opacity(0.12)
    static let linie2 = Color.white.opacity(0.07)
    static let aufWeiss = Color(hex: 0x0A2245)
    static let kugelLicht = Color(hex: 0xCFE0F5)
    static let perleNeutral = Color.white.opacity(0.589)
    static let perleGedanke = Color.white.opacity(0.285)
    static let pille = Color.white.opacity(0.063)
    static let pilleLauf = Color.white.opacity(0.094)
    static let kantePille = Color(hex: 0x8FB6E3, deckkraft: 0.11)
    static let warnFlaeche = Color(hex: 0xE88A6B, deckkraft: 0.08)
    static let warnKante = Color(hex: 0xE88A6B, deckkraft: 0.35)
    static let gedankeZeichen = Color.white.opacity(0.38)
    static let kapsel = Color.white.opacity(0.07)
    static let schatten = Color.black.opacity(0.11)
    static let leiste = Color.black.opacity(0.16)
    static let hinweisSchatten = Color.black.opacity(0.35)
    static let schleier = Color(hex: 0x030C1E, deckkraft: 0.62)
    static let kasten = Color(hex: 0x142B4C, deckkraft: 0.97)
    static let kastenSchatten = Color.black.opacity(0.5)
    static let feld = Color.white.opacity(0.06)
    static let auswahl = Color(hex: 0x8FB6E3, deckkraft: 0.10)
    static let stufeFrontier = Color(hex: 0xC9A7FF)
    static let warnText = Color(hex: 0xF3C2B2)
    static let neuFragen = Color(hex: 0x3A1407)

    static var grund: LinearGradient { LinearGradient(colors: [nacht, nachtUnten], startPoint: .top, endPoint: .bottom) }
}

enum Mass {
    static let radius: CGFloat = 20
    static let radiusKlein: CGFloat = 14
    static let randBreit: CGFloat = 72
    static let randSchmal: CGFloat = 20
    static let seitenleisteOffen: CGFloat = 256
    static let seitenleisteSchmal: CGFloat = 84
    static let panel: CGFloat = 440
}

enum Schrift {
    enum Gewicht: String { case light = "Light", regular = "Regular", medium = "Medium" }

    static func serif(_ groesse: CGFloat, kursiv: Bool = false) -> Font {
        .custom(kursiv ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: groesse)
    }
    static func grotesk(_ groesse: CGFloat, _ gewicht: Gewicht = .regular) -> Font {
        .custom("SpaceGrotesk-\(gewicht.rawValue)", size: groesse)
    }
    static func mono(_ groesse: CGFloat, _ gewicht: Gewicht = .regular) -> Font { .custom("IBMPlexMono-\(gewicht == .medium ? "Medium" : "Regular")", size: groesse) }
}

enum Kurve {
    static func ease(_ dauer: Double = 0.18) -> Animation { .timingCurve(0.22, 0.8, 0.24, 1, duration: dauer) }
    static func feder(_ dauer: Double = 0.35) -> Animation { .timingCurve(0.34, 1.32, 0.5, 1, duration: dauer) }
}

struct HauptKnopfStil: ButtonStyle {
    @Environment(\.isEnabled) private var aktiv
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Schrift.grotesk(14, .medium))
            .foregroundStyle(Farbe.aufWeiss)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Farbe.himmel.opacity(aktiv ? (configuration.isPressed ? 0.8 : 1) : 0.35), in: Capsule())
            .animation(Kurve.ease(), value: configuration.isPressed)
    }
}

struct NebenKnopfStil: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Schrift.grotesk(13, .medium))
            .foregroundStyle(Farbe.ink)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(configuration.isPressed ? Farbe.flaeche2 : Farbe.flaeche, in: Capsule())
            .overlay(Capsule().stroke(Farbe.linie, lineWidth: 1))
            .animation(Kurve.ease(), value: configuration.isPressed)
    }
}
