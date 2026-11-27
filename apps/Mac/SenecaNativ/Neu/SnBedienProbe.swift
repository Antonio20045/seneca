import AppKit

@MainActor
enum SnBedienProbe {
    static func ablauf(_ host: NSView, _ ordner: String) async {
        var protokoll: [String] = []
        NSApp.setActivationPolicy(.accessory)
        host.window?.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        host.window?.orderFrontRegardless()
        func pruefe(_ was: String, _ ok: Bool) { protokoll.append((ok ? "OK      " : "FEHLER  ") + was) }
        guard let fenster = host.window else { return }
        let geste = ZurueckGeste { f in
            guard let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: f.windowNumber, context: nil,
                                             characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53) else { return }
            _ = f.performKeyEquivalent(with: esc)
        }
        geste.installiere()
        await klick(host, CGPoint(x: 262, y: 330))
        pruefe("Klick auf Laufen öffnet „\(SnStatistikProbe.gesehen)“", SnStatistikProbe.gesehen == "Laufen Woche")
        bild(host, "\(ordner)/zurueck-vorher.png")
        await wisch(fenster, dx: 40, dy: 120)
        pruefe("Senkrechtes Rollen mit leichtem Zittern lässt „\(SnStatistikProbe.gesehen)“ stehen", SnStatistikProbe.gesehen == "Laufen Woche")
        await wisch(fenster, dx: -150, dy: 0)
        pruefe("Wischen nach links lässt „\(SnStatistikProbe.gesehen)“ stehen", SnStatistikProbe.gesehen == "Laufen Woche")
        await wisch(fenster, dx: 30, dy: 0)
        pruefe("Ein kurzer Wisch nach rechts lässt „\(SnStatistikProbe.gesehen)“ stehen", SnStatistikProbe.gesehen == "Laufen Woche")
        await wisch(fenster, dx: 180, dy: 10)
        pruefe("Zwei-Finger-Wisch nach rechts bringt zurück zu „\(SnStatistikProbe.gesehen)“", SnStatistikProbe.gesehen == "Übersicht Woche")
        bild(host, "\(ordner)/zurueck-nachher.png")
        try? (protokoll.joined(separator: "\n") + "\n").write(toFile: "\(ordner)/ablauf-zurueck.txt", atomically: true, encoding: .utf8)
    }

    static func heute(_ host: NSView, _ ordner: String) async {
        var protokoll: [String] = []
        func pruefe(_ was: String, _ ok: Bool) { protokoll.append((ok ? "OK      " : "FEHLER  ") + was) }
        NSApp.setActivationPolicy(.accessory)
        guard let f = host.window else { return }
        f.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        f.makeKeyAndOrderFront(nil)
        let k = SnHeuteMass.kalender, h = host.bounds.height
        pruefe(String(format: "Fenster %.0f×%.0f: Kalender %.0f bis %.0f, ganz sichtbar ohne Rollen", host.bounds.width, h, k.minY, k.maxY), k.height > 0 && k.minY >= 0 && k.maxY <= h - 84)
        bild(host, "\(ordner)/heute-a.png")
        try? await Task.sleep(for: .seconds(3))
        bild(host, "\(ordner)/heute-b.png")
        func feld(_ v: NSView) -> NSTextField? { (v as? NSTextField).flatMap { $0.isEditable ? $0 : nil } ?? v.subviews.lazy.compactMap(feld).first }
        guard let tf = feld(host) else { pruefe("Notizfeld gefunden", false); return schreibe(protokoll, ordner) }
        let mitte = tf.convert(NSPoint(x: tf.bounds.midX, y: tf.bounds.midY), to: nil)
        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: art, location: mitte, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: f.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { f.sendEvent(e) }
        }
        try? await Task.sleep(for: .milliseconds(300))
        for (zeichen, code) in Array("Steuer anrufen").map({ (String($0), UInt16(0)) }) + [("\r", UInt16(36))] {
            for art in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: art, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: f.windowNumber, context: nil, characters: zeichen, charactersIgnoringModifiers: zeichen, isARepeat: false, keyCode: code) { f.sendEvent(e) }
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        for _ in 0..<12 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
        pruefe("Klick ins Feld, „Steuer anrufen“ tippen, Enter: an den To-do-Weg übergeben \(SnHeuteMass.notiert)", SnHeuteMass.notiert == ["Steuer anrufen"])
        pruefe("Feld danach leer und weiter bereit: „\(feld(host)?.stringValue ?? "?")“", feld(host)?.stringValue == "")
        bild(host, "\(ordner)/heute-notiert.png")
        schreibe(protokoll, ordner)
    }

    private static func schreibe(_ protokoll: [String], _ ordner: String) {
        try? (protokoll.joined(separator: "\n") + "\n").write(toFile: "\(ordner)/ablauf-heute.txt", atomically: true, encoding: .utf8)
    }

    private static func wisch(_ f: NSWindow, dx: CGFloat, dy: CGFloat) async {
        let schritte = 12
        let invertiert = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0).flatMap(NSEvent.init(cgEvent:))?.isDirectionInvertedFromDevice ?? true
        for i in 0...schritte + 1 {
            let phase: Int64 = i == 0 ? 1 : (i == schritte + 1 ? 4 : 2)
            let teil = i == 0 || i == schritte + 1 ? 0 : 1.0 / CGFloat(schritte)
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy * teil), wheel2: Int32((invertiert ? dx : -dx) * teil), wheel3: 0) else { continue }
            cg.location = CGPoint(x: f.frame.minX + 600, y: (NSScreen.screens.first?.frame.height ?? 0) - f.frame.maxY + 500)
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            cg.setIntegerValueField(CGEventField(rawValue: 91)!, value: Int64(f.windowNumber))
            cg.setIntegerValueField(CGEventField(rawValue: 92)!, value: Int64(f.windowNumber))
            cg.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(f.windowNumber))
            guard let e = NSEvent(cgEvent: cg) else { continue }
            NSApp.sendEvent(e)
            try? await Task.sleep(for: .milliseconds(16))
        }
        for _ in 0..<12 { try? await Task.sleep(for: .milliseconds(50)); f.contentView?.layoutSubtreeIfNeeded(); CATransaction.flush() }
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
