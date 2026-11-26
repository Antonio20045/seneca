import AppKit

@MainActor
final class DiktatTaste {
    var tipp: () -> Void = {}
    var escape: () -> Void = {}

    private var erkennung = DiktatTippErkennung()
    private var monitore: [Any] = []

    private static let maske: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]

    var installiert: Bool { !monitore.isEmpty }

    func installiere() {
        entferne()
        erkennung = DiktatTippErkennung()
        let systemweit = MacPfade.profil == .echt && !Hintergrund.an
            || ProcessInfo.processInfo.environment["SENECA_DIKTAT_GLOBAL"] == "1"
        if systemweit, let m = NSEvent.addGlobalMonitorForEvents(matching: Self.maske, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.ereignis(e) }
        }) { monitore.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: Self.maske, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.ereignis(e) }
            return e
        }) { monitore.append(m) }
    }

    func entferne() {
        for m in monitore { NSEvent.removeMonitor(m) }
        monitore.removeAll()
    }

    private func ereignis(_ e: NSEvent) {
        let z: DiktatTippErkennung.Ereignis
        switch e.type {
        case .flagsChanged: z = .flaggen(code: e.keyCode, flags: e.modifierFlags.rawValue, zeit: e.timestamp)
        case .keyDown: z = .taste(code: e.keyCode, zeit: e.timestamp)
        default: z = .zeiger(zeit: e.timestamp)
        }
        pruefe(z)
    }

    func pruefe(_ z: DiktatTippErkennung.Ereignis) {
        switch erkennung.verarbeite(z) {
        case .tipp: tipp()
        case .escape: escape()
        case .nichts: break
        }
    }
}
