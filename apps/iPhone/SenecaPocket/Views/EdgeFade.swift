import SwiftUI
import UIKit

struct StatusBarEdgeFade: ViewModifier {
    var m: Metrics
    var active = true

    @MainActor var statusTop: CGFloat { max(m.safeTop, Stil.fensterRaender.top) }
    @MainActor var clearUntil: CGFloat { max(0, statusTop - 12) }
    @MainActor var solidFrom: CGFloat { statusTop + 24 }

    func body(content: Content) -> some View {
        systemEdgeOff(content).mask(alignment: .top) {
            VStack(spacing: 0) {
                Color.black.opacity(active ? 0 : 1).frame(height: clearUntil)
                LinearGradient(stops: [.init(color: .black.opacity(active ? 0 : 1), location: 0),
                                       .init(color: .black.opacity(active ? 0.3 : 1), location: 0.45),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: solidFrom - clearUntil)
                Color.black
            }
        }
    }
}

private extension StatusBarEdgeFade {
    func systemEdgeOff(_ content: Content) -> some View { content.systemKanteAus() }
}

extension View {
    @ViewBuilder func systemKanteAus() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

struct WeicheKante: ViewModifier {
    var hoehe: CGFloat
    var unten = false
    func body(content: Content) -> some View {
        content.systemKanteAus().mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                       .init(color: .black.opacity(0.35), location: 0.4),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: hoehe)
                Color.black
                if unten {
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: hoehe)
                }
            }
        }
    }
}

extension View {
    func statusBarEdgeFade(_ m: Metrics, active: Bool = true) -> some View {
        modifier(StatusBarEdgeFade(m: m, active: active))
    }

    func weicheKante(_ hoehe: CGFloat = Stil.abstand.l, unten: Bool = false) -> some View {
        modifier(WeicheKante(hoehe: hoehe, unten: unten))
    }
}
