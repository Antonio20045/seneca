#if DEBUG
import SwiftUI
import QuartzCore
import os

@MainActor
enum WischMessung {
    static var wurzel = 0
    static var tag = 0
    static var heute = 0
    private static var schritte = 0
    private static var anfang: (wurzel: Int, tag: Int, heute: Int)?
    private static var losgelassen: (wurzel: Int, tag: Int, heute: Int)?
    private static var ebene = ""
    private static var lauf = 0
    private static let takt = Takt()
    private static let log = Logger(subsystem: "de.antonio.senecapocket", category: "Wisch")

    private final class Takt: NSObject {
        var link: CADisplayLink?
        var zeiten: [CFTimeInterval] = []
        @objc func bild(_ l: CADisplayLink) { zeiten.append(l.timestamp) }
        func start() {
            stop()
            zeiten = []
            let l = CADisplayLink(target: self, selector: #selector(bild(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        func stop() { link?.invalidate(); link = nil }
    }

    static func start(_ name: String) {
        ebene = name
        schritte = 0
        anfang = (wurzel, tag, heute)
        losgelassen = nil
        lauf += 1
        takt.start()
    }

    static func schritt() { if anfang != nil { schritte += 1 } }

    static func ende() {
        guard anfang != nil else { return }
        losgelassen = (wurzel, tag, heute)
        let nr = lauf
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if nr == lauf { schreiben() }
        }
    }

    private static func schreiben() {
        guard let a = anfang, let l = losgelassen else { return }
        takt.stop()
        anfang = nil
        let z = takt.zeiten
        let dauer = (z.last ?? 0) - (z.first ?? 0)
        let abstaende = zip(z.dropFirst(), z).map { ($0 - $1) * 1000 }
        let rate = dauer > 0 ? Double(z.count - 1) / dauer : 0
        let zeile = String(format: "%@ | Finger-Schritte %d | beim Wischen: Wurzel %d, Tagesberechnung %d, Heute-Inhalt %d | mit Feder: Wurzel %d, Tagesberechnung %d, Heute-Inhalt %d | %d Bilder in %.2f s = %.1f/s | längster Abstand %.0f ms | über 25 ms: %d",
                           ebene, schritte, l.wurzel - a.wurzel, l.tag - a.tag, l.heute - a.heute,
                           wurzel - a.wurzel, tag - a.tag, heute - a.heute,
                           z.count, dauer, rate, abstaende.max() ?? 0, abstaende.filter { $0 > 25 }.count)
        log.notice("\(zeile, privacy: .public)")
        guard ProcessInfo.processInfo.environment["SENECA_DEMO"] == "1" else { return }
        let datei = FileManager.default.temporaryDirectory.appendingPathComponent("wisch-messung.txt")
        let alt = (try? String(contentsOf: datei, encoding: .utf8)) ?? ""
        try? (alt + zeile + "\n").write(to: datei, atomically: true, encoding: .utf8)
    }
}
#endif
