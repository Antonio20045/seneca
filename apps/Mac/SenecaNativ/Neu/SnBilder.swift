import SwiftUI
import AppKit
import QuartzCore

@MainActor
final class SnBilder: NSObject {
    private var link: CADisplayLink?
    private var zeiten: [Double] = []
    private var cpu0: UInt64 = 0

    static var aktiv: Bool { Hintergrund.aktiv && Messung.aktiv && ProcessInfo.processInfo.environment["SENECA_MESSUNG_UEBERGANG"].map { $0 == "1" || $0 == "seiten" } ?? false }

    func starte(_ fenster: NSWindow) {
        zeiten = []
        cpu0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let l = fenster.displayLink(target: self, selector: #selector(takt(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func takt(_ l: CADisplayLink) { zeiten.append(l.timestamp) }

    func beende(_ name: String) {
        link?.invalidate(); link = nil
        let cpu = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpu0) / 1e6
        guard zeiten.count > 2 else { Messung.notiere("  \(name): zu wenige Takte (\(zeiten.count))"); return }
        let dt = zip(zeiten.dropFirst(), zeiten).map { ($0 - $1) * 1000 }
        let soll = dt.sorted()[dt.count / 2]
        let verpasst = dt.reduce(0) { $0 + max(0, Int((($1 / soll)).rounded()) - 1) }
        let lang = dt.filter { $0 > soll * 1.5 }.count
        Messung.notiere(String(format: "  %@: %d Takte, Soll %.1f ms, längster %.1f ms, Lücken %d, verpasste Bilder %d (%.1f %%), Hauptthread-CPU %.0f ms",
                               name, dt.count, soll, dt.max() ?? 0, lang, verpasst, 100 * Double(verpasst) / Double(dt.count + verpasst), cpu))
    }

    static func laufe(modell: AppModell) async {
        guard aktiv else { return }
        let m = SnBilder()
        let runden = Int(ProcessInfo.processInfo.environment["SENECA_MESSUNG_RUNDEN"] ?? "") ?? 3
        try? await Task.sleep(for: .seconds(12))
        guard let w = modell.hauptfenster else { Messung.notiere("# kein Fenster"); return }
        if ProcessInfo.processInfo.environment["SENECA_MESSUNG_UEBERGANG"] == "seiten" {
            Messung.notiere("# Seitenwechsel")
            for i in 1...runden {
                for s in [Seite.projekte, .kalender, .entscheidungen, .chat, .heute] {
                    m.starte(w); modell.gehe(s == .heute ? .heute : Route(s))
                    try? await Task.sleep(for: .seconds(0.9)); m.beende("\(s.rawValue) \(i)")
                    try? await Task.sleep(for: .seconds(0.4))
                }
            }
            Messung.notiere("# ende")
            return
        }
        Messung.notiere("# Übergang Dock/Chat")
        for i in 1...runden {
            m.starte(w); modell.zeigeGespraechSeite()
            try? await Task.sleep(for: .seconds(1.8)); m.beende("öffnen \(i)")
            try? await Task.sleep(for: .seconds(1))
            m.starte(w); modell.zeigeGespraechSeite()
            try? await Task.sleep(for: .seconds(1.8)); m.beende("schließen \(i)")
            try? await Task.sleep(for: .seconds(1))
        }
        Messung.notiere("# ende")
    }
}
