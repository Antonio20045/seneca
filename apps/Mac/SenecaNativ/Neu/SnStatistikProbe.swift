import AppKit

@MainActor
enum SnStatistikProbe {
    static var gesehen = ""

    static func ablauf(_ host: NSView, _ ordner: String) async {
        var protokoll: [String] = []
        NSApp.setActivationPolicy(.accessory)
        host.window?.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        host.window?.orderFrontRegardless()
        func pruefe(_ was: String, _ ok: Bool) { protokoll.append((ok ? "OK      " : "FEHLER  ") + was) }
        let zurueck = CGPoint(x: 130, y: 100)
        for (bereich, ort) in [("Laufen", CGPoint(x: 200, y: 405)), ("Krafttraining", CGPoint(x: 200, y: 590))] {
            await klick(host, ort)
            pruefe("Klick auf die Kachel \(bereich) öffnet „\(gesehen)“", gesehen == "\(bereich) Woche")
            bild(host, "\(ordner)/klick-\(bereich).png")
            await klick(host, zurueck)
            pruefe("‹ Statistik führt zurück zu „\(gesehen)“", gesehen == "Übersicht Woche")
        }
        for (z, ort) in [("Monat", CGPoint(x: 1254, y: 125)), ("Jahr", CGPoint(x: 1315, y: 125)), ("Woche", CGPoint(x: 1186, y: 125))] {
            await klick(host, ort)
            pruefe("Umschalter \(z) zeigt „\(gesehen)“", gesehen == "Übersicht \(z)")
            if z == "Jahr" {
                bild(host, "\(ordner)/klick-Jahr.png")
                await klick(host, CGPoint(x: 200, y: 590))
                pruefe("im Jahr öffnet Krafttraining „\(gesehen)“", gesehen == "Krafttraining Jahr")
                await klick(host, zurueck)
                pruefe("zurück landet wieder im Jahr: „\(gesehen)“", gesehen == "Übersicht Jahr")
            }
        }
        try? (protokoll.joined(separator: "\n") + "\n").write(toFile: "\(ordner)/ablauf.txt", atomically: true, encoding: .utf8)
    }

    private static func klick(_ host: NSView, _ oben: CGPoint) async {
        guard let f = host.window else { return }
        let ort = NSPoint(x: oben.x, y: host.bounds.height - oben.y)
        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: art, location: ort, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: f.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { f.sendEvent(e) }
        }
        for _ in 0..<12 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
    }

    private static func bild(_ host: NSView, _ pfad: String) {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: pfad))
    }
}
