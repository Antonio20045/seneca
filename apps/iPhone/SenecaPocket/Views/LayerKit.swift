import SwiftUI
import UIKit

struct PageGestures: Equatable {
    var holdsBack = false
}

extension EnvironmentValues {
    @Entry var listeOben: (Bool) -> Void = { _ in }
}

private struct ListeOben: ViewModifier {
    @Environment(\.listeOben) private var melde
    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 1 } action: { _, oben in melde(oben) }
    }
}

struct ScrollClaimsKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    func claimsVerticalDrags(active: Bool = true) -> some View {
        background {
            GeometryReader { g in
                Color.clear.preference(key: ScrollClaimsKey.self, value: active ? [g.frame(in: .global)] : [])
            }
        }
    }

    func listeOben() -> some View { modifier(ListeOben()) }

    func scrollClaims(visible: Bool) -> some View {
        transformPreference(ScrollClaimsKey.self) { if !visible { $0 = [] } }
    }
}

struct ReadingDocument: Identifiable, Equatable {
    var id: String
    var kicker: String
    var title: String
    var body: String
    var format: Format = .bericht

    enum Format: Equatable {
        case bericht
        case markdown
        case text
    }
}

struct ConversationTarget: Equatable {
    var sessionKey: String
    var leaderName: String
    var opening: String?
}

struct AppActions: Equatable {
    var stand = 0
    static func == (a: AppActions, b: AppActions) -> Bool { a.stand == b.stand }

    var openReading: (ReadingDocument) -> Void = { _ in }
    var openConversation: (ConversationTarget) -> Void = { _ in }
    var showPage: (Page) -> Void = { _ in }
    var openKalender: (KalenderFokus?) -> Void = { _ in }
    var dateiOeffnen: (String) async -> String? = { _ in nil }
    var frage: (String) -> Void = { _ in }
}

struct KalenderFokus: Equatable {
    var itemId: String
    var from: CGRect = .zero
}

struct KalenderFokusZeileKey: PreferenceKey {
    static let raum = "kalender.ebene"
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

struct KalenderFokusEintragKey: PreferenceKey {
    static let defaultValue: AgendaEintrag? = nil
    static func reduce(value: inout AgendaEintrag?, nextValue: () -> AgendaEintrag?) { value = nextValue() ?? value }
}

struct KalenderBrueckeFlug: ViewModifier, Animatable {
    var p: Double
    var von: CGPoint
    var nach: CGPoint
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + 0.22 * (1 - p), anchor: .topLeading)
            .offset(x: von.x + (nach.x - von.x) * p, y: von.y + (nach.y - von.y) * p)
            .opacity(seg(p, 0, 0.3))
    }
}

private struct AppActionsKey: EnvironmentKey {
    static let defaultValue = AppActions()
}

private struct KalenderFokusKey: EnvironmentKey {
    static let defaultValue: KalenderFokus? = nil
}

private struct KalenderFokusVerdecktKey: EnvironmentKey {
    static let defaultValue = false
}

private struct KalenderTagKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var appActions: AppActions {
        get { self[AppActionsKey.self] }
        set { self[AppActionsKey.self] = newValue }
    }
    var kalenderFokus: KalenderFokus? {
        get { self[KalenderFokusKey.self] }
        set { self[KalenderFokusKey.self] = newValue }
    }
    var kalenderTag: Date? {
        get { self[KalenderTagKey.self] }
        set { self[KalenderTagKey.self] = newValue }
    }
    var kalenderFokusVerdeckt: Bool {
        get { self[KalenderFokusVerdecktKey.self] }
        set { self[KalenderFokusVerdecktKey.self] = newValue }
    }
}

@available(iOS 18.0, *)
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    var allows: (CGFloat) -> Bool
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void
    var cancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        context.coordinator.allows = allows
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.allows = allows
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dx = pan.translation(in: pan.view).x
        switch pan.state {
        case .began, .changed: changed(dx)
        case .ended: ended(dx, dx + pan.velocity(in: pan.view).x * 0.25)
        case .cancelled, .failed: cancelled()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var allows: (CGFloat) -> Bool = { _ in false }
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.2 && allows(v.x)
        }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
