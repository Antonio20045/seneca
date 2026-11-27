import SwiftUI
import AppKit

struct FensterHalter: NSViewRepresentable {
    @ObservedObject var modell: AppModell

    func makeCoordinator() -> Koordinator { Koordinator(modell: modell) }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { context.coordinator.haengeAn(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.fenster == nil { DispatchQueue.main.async { context.coordinator.haengeAn(nsView.window) } }
    }

    @MainActor
    final class Koordinator {
        let modell: AppModell
        weak var fenster: NSWindow?
        private var beobachter: [NSObjectProtocol] = []

        init(modell: AppModell) { self.modell = modell }

        private static func ohneGroessenabfrage(_ w: NSWindow) {
            w.contentMinSize = NSSize(width: 1100, height: 680)
            var v: NSView? = w.contentView
            var tiefe = 0
            while let x = v, tiefe < 4 {
                if let h = x as? GroessenabfrageAus { h.schalteAus(); return }
                v = x.subviews.first; tiefe += 1
            }
        }

        func haengeAn(_ w: NSWindow?) {
            guard let w, fenster == nil else { return }
            fenster = w
            modell.hauptfenster = w
            if Hintergrund.aktiv { Hintergrund.planeBilder(w) } else { FensterSicht.haupt.haengeAn(w) }
            Self.ohneGroessenabfrage(w)
            if let f = Fensterstand.lies(), f.passt(auf: NSScreen.screens.map(\.visibleFrame)) {
                w.setFrame(f.rahmen, display: true)
            }
            modell.rahmen = w.frame
            modell.merke()
            for n in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                beobachter.append(NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.speichere() }
                })
            }
        }

        private func speichere() {
            guard let w = fenster else { return }
            modell.rahmen = w.frame
            modell.merke()
        }

        deinit { beobachter.forEach(NotificationCenter.default.removeObserver) }
    }
}

@MainActor
final class FensterSicht: ObservableObject {
    static let haupt = FensterSicht()
    @Published private(set) var sichtbar = true
    private weak var fenster: NSWindow?
    private var beobachter: NSObjectProtocol?

    func haengeAn(_ w: NSWindow) {
        guard w !== fenster else { return }
        if let b = beobachter { NotificationCenter.default.removeObserver(b) }
        fenster = w
        beobachter = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lies() }
        }
        lies()
    }

    private func lies() {
        let neu = fenster.map { $0.occlusionState.contains(.visible) } ?? true
        if neu != sichtbar { sichtbar = neu }
    }
}

private struct FensterSichtbarSchluessel: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    @Entry var festeZeit: Double?
    var fensterSichtbar: Bool {
        get { self[FensterSichtbarSchluessel.self] }
        set { self[FensterSichtbarSchluessel.self] = newValue }
    }
}

private struct FensterSichtGeber: ViewModifier {
    @ObservedObject private var sicht = FensterSicht.haupt
    func body(content: Content) -> some View { content.environment(\.fensterSichtbar, sicht.sichtbar) }
}

extension View {
    func fensterSichtAusHauptfenster() -> some View { modifier(FensterSichtGeber()) }
}

@MainActor
private protocol GroessenabfrageAus { func schalteAus() }
extension NSHostingView: GroessenabfrageAus {
    func schalteAus() { sizingOptions = [] }
}
