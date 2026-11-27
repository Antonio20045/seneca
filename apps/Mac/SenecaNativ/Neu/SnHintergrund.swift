import AppKit

enum Hintergrund {
    static let aktiv: Bool = {
        let v = ProcessInfo.processInfo.environment["SENECA_HINTERGRUND"]
        return v != nil && !v!.isEmpty && v != "0"
    }()
    static var an: Bool { aktiv }

    @MainActor static func aktiviere() {
        if aktiv {
            for w in NSApp.windows where w.canBecomeKey && !(w is NSPanel) { w.makeKey() }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor static func legeAb(_ w: NSWindow) {
        if ProcessInfo.processInfo.environment["SENECA_HINTERGRUND_RENDERN"] == "1" {
            w.alphaValue = 0.01
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.orderFrontRegardless()
        } else {
            w.orderBack(nil)
        }
    }

    @MainActor private static var bilderGeplant = false

    @MainActor static func planeBilder(_ w: NSWindow) {
        guard !bilderGeplant, let liste = ProcessInfo.processInfo.environment["SENECA_HINTERGRUND_BILDER"] else { return }
        bilderGeplant = true
        for eintrag in liste.split(separator: ",") {
            let t = eintrag.split(separator: ":", maxSplits: 1)
            guard t.count == 2, let s = Double(t[0]) else { continue }
            let pfad = String(t[1])
            DispatchQueue.main.asyncAfter(deadline: .now() + s) {
                MainActor.assumeIsolated {
                    let alt = w.alphaValue
                    w.alphaValue = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        MainActor.assumeIsolated {
                            let p = Process()
                            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                            p.arguments = ["-l", String(w.windowNumber), "-o", "-x", pfad]
                            try? p.run()
                            p.waitUntilExit()
                            w.alphaValue = alt
                        }
                    }
                }
            }
        }
    }

    @MainActor static func zeige(_ w: NSWindow) {
        if aktiv { legeAb(w) } else { w.makeKeyAndOrderFront(nil) }
    }

    @MainActor static func defaults() -> UserDefaults {
        guard aktiv, let d = UserDefaults(suiteName: "sn-hintergrund-\(ProcessInfo.processInfo.processIdentifier)") else { return .standard }
        let echt = UserDefaults.standard
        if let z = ProcessInfo.processInfo.environment["SENECA_HINTERGRUND_ZIEL"] ?? echt.string(forKey: GegenueberModell.zielKey) { d.set(z, forKey: GegenueberModell.zielKey) }
        return d
    }
}
