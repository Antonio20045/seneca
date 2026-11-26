import SwiftUI
import AppKit

@MainActor
final class AufgabenGesehen {
    static let gemeinsam = AufgabenGesehen()

    private var regel = GesehenRegel()
    private var quellen: [String: Set<String>] = [:]
    private var beobachter: [NSObjectProtocol] = []

    private init() {
        let z = NotificationCenter.default
        beobachter.append(z.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.verlassen() }
        })
        beobachter.append(z.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.verlassen() }
        })
        beobachter.append(z.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.zaehleNeu() }
        })
    }

    func zeigt(_ quelle: String, _ ids: Set<String>) {
        quellen[quelle] = ids
        if NSApp.isActive { zaehleNeu() }
    }

    private func zaehleNeu() {
        regel.zeigt(quellen.values.reduce(into: Set<String>()) { $0.formUnion($1) }, jetzt: Date())
    }

    func weg(_ quelle: String) {
        quellen[quelle] = nil
        if quellen.isEmpty { verlassen() }
    }

    private func verlassen() {
        guard regel.verlassen(jetzt: Date()) else { return }
        guard MacPfade.profil == .echt, !MacPfade.nebenher else { return }
        Task {
            _ = await Kindprozess.laufe(AufgabenModell.befehl, ["gesehen"], limit: 15, ausgabe: false)
            await AufgabenModell.gemeinsam.lade()
        }
    }
}

private struct SnNeuSichtbar: ViewModifier {
    let quelle: String
    let ids: Set<String>

    func body(content: Content) -> some View {
        content
            .onAppear { AufgabenGesehen.gemeinsam.zeigt(quelle, ids) }
            .onChange(of: ids) { _, neu in AufgabenGesehen.gemeinsam.zeigt(quelle, neu) }
            .onDisappear { AufgabenGesehen.gemeinsam.weg(quelle) }
    }
}

extension View {
    func snNeuSichtbar(_ quelle: String, ids: Set<String>) -> some View { modifier(SnNeuSichtbar(quelle: quelle, ids: ids)) }
}
