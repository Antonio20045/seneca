import SwiftUI
import UIKit

enum Stil {

    enum Schrift: CaseIterable {
        case gross
        case titel
        case sache
        case text
        case zeile
        case zeileWichtig
        case klein
        case etikett
        case zahl

        var groesse: CGFloat {
            switch self {
            case .gross: 34
            case .titel: 28
            case .sache: 22
            case .text: 17
            case .zeile, .zeileWichtig: 16
            case .klein: 13
            case .etikett: 12
            case .zahl: 56
            }
        }

        var font: Font {
            switch self {
            case .gross, .titel, .sache, .zahl: Sundartha.serif(groesse)
            case .text: Sundartha.grotesk(groesse, .light)
            case .zeile, .klein: Sundartha.grotesk(groesse, .regular)
            case .zeileWichtig, .etikett: Sundartha.grotesk(groesse, .medium)
            }
        }

        var zeilenAbstand: CGFloat {
            switch self {
            case .text: 5
            case .zeile, .zeileWichtig: 3
            case .klein: 2
            default: 0
            }
        }

        var sperrung: CGFloat {
            switch self {
            case .etikett: 0.4
            case .gross, .titel: -0.2
            default: 0
            }
        }

        var kursiv: Font { Sundartha.serif(groesse, italic: true) }
    }

    struct Abstaende {
        let xs: CGFloat = 4
        let s: CGFloat = 8
        let m: CGFloat = 12
        let l: CGFloat = 16
        let xl: CGFloat = 24
        let xxl: CGFloat = 32
        let xxxl: CGFloat = 48
    }
    static let abstand = Abstaende()

    static let rand: CGFloat = 24
    static let tippFlaeche: CGFloat = 44
    static let zeilenHoehe: CGFloat = 52
    static let knopfHoehe: CGFloat = 48
    static let rundKnopf: CGFloat = 36
    static let kopfOben: CGFloat = 8
    static let unten: CGFloat = 16

    struct Tinten {
        let voll = Sundartha.ink
        let zweit = Sundartha.ink.opacity(0.72)
        let leise = Sundartha.ink.opacity(0.48)
        let linie = Sundartha.ink.opacity(0.12)
        let flaeche = Sundartha.ink.opacity(0.08)
        let flaecheStark = Sundartha.ink.opacity(0.14)
    }
    static let tinte = Tinten()

    struct Farben {
        let himmel = Sundartha.himmel
        let gruen = Sundartha.gruen
        let bernstein = Sundartha.bernstein
        let koralle = Sundartha.koralle
        let aufHell = Sundartha.aufHell
        let grund = Sundartha.grund
    }
    static let farbe = Farben()

    struct Radien {
        let klein: CGFloat = 10
        let mittel: CGFloat = 16
        let gross: CGFloat = 24
    }
    static let radius = Radien()

    enum SymbolGroesse { case klein, mittel }
    static func symbol(_ g: SymbolGroesse, gewicht: Font.Weight = .regular) -> Font {
        .system(size: g == .klein ? 15 : 20, weight: gewicht)
    }

    @MainActor static var fensterRaender: UIEdgeInsets {
        let fenster = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return (fenster.first { $0.isKeyWindow } ?? fenster.first)?.safeAreaInsets ?? .zero
    }
}

extension View {
    func schrift(_ s: Stil.Schrift) -> some View {
        font(s.font).lineSpacing(s.zeilenAbstand).kerning(s.sperrung)
    }

    func seitenRand() -> some View {
        padding(.horizontal, Stil.rand)
    }

    func tippFlaeche() -> some View {
        frame(minWidth: Stil.tippFlaeche, minHeight: Stil.tippFlaeche).contentShape(Rectangle())
    }
}
