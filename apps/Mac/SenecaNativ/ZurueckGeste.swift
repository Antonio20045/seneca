import AppKit

struct WischErkennung {
    static let strecke: CGFloat = 70
    static let verhaeltnis: CGFloat = 2.5
    private(set) var x: CGFloat = 0
    private(set) var y: CGFloat = 0

    mutating func fuettere(_ e: NSEvent) -> Bool {
        guard e.hasPreciseScrollingDeltas, e.momentumPhase.isEmpty else { return false }
        if e.phase.contains(.began) || e.phase.contains(.mayBegin) { x = 0; y = 0 }
        x += e.isDirectionInvertedFromDevice ? e.scrollingDeltaX : -e.scrollingDeltaX
        y += e.scrollingDeltaY
        guard e.phase.contains(.ended) else { return false }
        defer { x = 0; y = 0 }
        return x > Self.strecke && x > Self.verhaeltnis * abs(y)
    }
}

@MainActor
final class ZurueckGeste {
    private var monitor: Any?
    private var erkennung = WischErkennung()
    private var gesperrt = false
    private let zurueck: (NSWindow) -> Void

    init(zurueck: @escaping (NSWindow) -> Void) { self.zurueck = zurueck }

    func installiere() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            MainActor.assumeIsolated { self?.beobachte(e) }
            return e
        }
    }

    private func beobachte(_ e: NSEvent) {
        guard let fenster = e.window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        if e.phase.contains(.began) { gesperrt = Self.waagerechtRollbar(fenster, e.locationInWindow) }
        if erkennung.fuettere(e), !gesperrt { zurueck(fenster) }
    }

    private static func waagerechtRollbar(_ fenster: NSWindow, _ ort: NSPoint) -> Bool {
        guard let inhalt = fenster.contentView, let ziel = inhalt.hitTest(inhalt.convert(ort, from: nil)) else { return false }
        var v: NSView? = ziel
        while let a = v {
            if let s = a as? NSScrollView, let d = s.documentView, d.frame.width > s.contentView.bounds.width + 1 { return true }
            v = a.superview
        }
        return false
    }
}
