import SwiftUI
import AppKit
import Combine
#if DEBUG
import ScreenCaptureKit
import Vision
#endif

@MainActor
final class MenueZeichenModell: ObservableObject {
    @Published private(set) var zeichen = MenueZeichen.entscheide(meetingNimmtAuf: false, meetingDauer: 0, meetingArbeitet: false, braucht: 0)
    private var abos: Set<AnyCancellable> = []

    func starte(dienste: MacDienste, store: SenecaStore) {
        guard abos.isEmpty else { return }
        Publishers.CombineLatest3(MeetingDienst.gemeinsam.$zustand, MeetingDienst.gemeinsam.$dauer, store.$stand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] m, dauer, stand in
                MainActor.assumeIsolated {
                    var arbeitet = false
                    if case .wertAus = m { arbeitet = true }
                    let neu = MenueZeichen.entscheide(meetingNimmtAuf: m == .nimmtAuf, meetingDauer: dauer,
                                                      meetingArbeitet: arbeitet, braucht: stand?.zaehler?.braucht ?? 0, fokus: stand?.ruhe?.grund == "fokus")
                    if neu.text != nil { MenueZeichenModell.festeZiffern() }
                    if let self, neu != self.zeichen { self.zeichen = neu }
                }
            }
            .store(in: &abos)
    }

    static func festeZiffern() {
        let f = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        for k in MenueFenster.statusKnoepfe() where k.font != f { k.font = f }
    }

    #if DEBUG
    func probeSetze(_ z: MenueZeichen) { zeichen = z }
    #endif

    static func punkt(_ farbe: String) -> NSImage {
        let b = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            (farbe == "rot" ? NSColor.systemRed : NSColor(red: 0.91, green: 0.72, blue: 0.29, alpha: 1)).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        b.isTemplate = false
        return b
    }
}

@MainActor
final class VorneMerker: ObservableObject {
    static let gemeinsam = VorneMerker()

    enum Ziel {
        case vorneLassen(String)
        case zurueck(NSRunningApplication)
        case seneca
    }

    @Published private(set) var stand = 0
    private var fremde: NSRunningApplication?
    var zuletztFremd: NSRunningApplication? { fremde.flatMap { $0.isTerminated ? nil : $0 } }
    private var senecaAktivSeit: Date?
    private var menueOffenSeit: Date?
    private var senecaWarVornBeimKlick: Bool?
    private var klickBeobachter: Any?
    private var abos: Set<AnyCancellable> = []
    private let ich = ProcessInfo.processInfo.processIdentifier

    func starte() {
        guard abos.isEmpty else { return }
        if let v = NSWorkspace.shared.frontmostApplication {
            if v.processIdentifier == ich { senecaAktivSeit = .distantPast } else { fremde = v }
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] n in
                let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.aktiviert(app) }
            }
            .store(in: &abos)
        klickBeobachter = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            MainActor.assumeIsolated {
                if e.window?.className.contains("StatusBar") == true { self?.senecaWarVornBeimKlick = NSApp.isActive }
            }
            return e
        }
    }

    private func aktiviert(_ app: NSRunningApplication?) {
        guard let app else { return }
        if app.processIdentifier == ich {
            if senecaAktivSeit == nil { senecaAktivSeit = Date() }
        } else {
            fremde = app
            senecaAktivSeit = nil
            senecaWarVornBeimKlick = nil
        }
        stand += 1
    }

    func menueGeoeffnet() {
        menueOffenSeit = Date()
        stand += 1
    }

    func ziel() -> Ziel {
        let vorn = NSWorkspace.shared.frontmostApplication
        let lebt = fremde.map { !$0.isTerminated } ?? false
        switch MenueDiktatZiel.entscheide(senecaVorn: vorn?.processIdentifier == ich, senecaAktivSeit: senecaAktivSeit?.timeIntervalSinceReferenceDate,
                                          menueOffenSeit: menueOffenSeit?.timeIntervalSinceReferenceDate, hatFremde: lebt,
                                          senecaWarVornBeimKlick: senecaWarVornBeimKlick) {
        case .vorneLassen: return .vorneLassen(vorn?.localizedName ?? "die App vorn")
        case .zurueck: if let fremde { return .zurueck(fremde) } else { return .seneca }
        case .seneca: return .seneca
        }
    }

    func vorneName() -> String {
        switch ziel() {
        case .vorneLassen(let n): return n
        case .zurueck(let app): return app.localizedName ?? ""
        case .seneca: return "Seneca"
        }
    }

    var zielSatz: String {
        switch ziel() {
        case .vorneLassen(let n): return "Der Text geht in \(n)"
        case .zurueck(let app): return "Der Text geht in \(app.localizedName ?? "die App davor")"
        case .seneca: return "Der Text geht in dein Seneca-Fenster"
        }
    }
}

@MainActor
enum MenueFenster {
    static weak var fenster: NSWindow?

    static func schliesse() {
        guard let f = fenster, f.isVisible else { return }
        if let knopf = statusKnopf() { knopf.performClick(knopf) } else { f.close() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { if fenster?.isVisible == true { fenster?.close() } } }
    }

    static func statusKnopf() -> NSStatusBarButton? {
        let alle = statusKnoepfe()
        return alle.first { $0.action != nil && ($0.window?.frame.width ?? 0) > 0 } ?? alle.first
    }

    static func statusKnoepfe() -> [NSStatusBarButton] {
        NSApp.windows.filter { $0.className.contains("StatusBar") }.compactMap { finde($0.contentView) }
    }

    private static func finde(_ v: NSView?) -> NSStatusBarButton? {
        guard let v else { return nil }
        if let k = v as? NSStatusBarButton { return k }
        for u in v.subviews { if let k = finde(u) { return k } }
        return nil
    }
}

struct MenueFensterLeser: NSViewRepresentable {
    var geoeffnet: () -> Void

    final class Sicht: NSView {
        var geoeffnet: (() -> Void)?
        private var beobachter: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let b = beobachter { NotificationCenter.default.removeObserver(b); beobachter = nil }
            guard let w = window else { return }
            MenueFenster.fenster = w
            geoeffnet?()
            beobachter = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.geoeffnet?() }
            }
        }
    }

    func makeNSView(context: Context) -> Sicht {
        let s = Sicht()
        s.geoeffnet = geoeffnet
        return s
    }

    func updateNSView(_ nsView: Sicht, context: Context) { nsView.geoeffnet = geoeffnet }
}

extension MacDienste {
    func sprechen() {
        let ziel = VorneMerker.gemeinsam.ziel()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                MenueFenster.schliesse()
                Task { @MainActor in
                    if case .zurueck(let app) = ziel {
                        NSApp.yieldActivation(to: app)
                        _ = app.activate(options: [])
                        for _ in 0..<12 where NSApp.isActive { try? await Task.sleep(for: .milliseconds(50)) }
                    } else {
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                    DiktatDienst.gemeinsam.umschalten()
                }
            }
        }
    }

    func zeigeBildschirm() {
        DispatchQueue.main.async { MainActor.assumeIsolated { MenueFenster.schliesse(); self.panel.zeige() } }
    }

    func meetingStand(_ z: MeetingDienst.Zustand) {
        let auf = z == .nimmtAuf
        merkKuerzel.aktion = { MeetingDienst.gemeinsam.merke() }
        meetingKuerzel.aktion = { if Self.meetingFensterVorn() { MeetingDienst.gemeinsam.umschalten() } else { NSApp.activate(); MeetingDienst.gemeinsam.oeffneFenster?() } }
        merkKuerzel.setze(auf ? Kuerzel(taste: 46, modifier: Kuerzel.cmd | Kuerzel.shift, zeichen: "⌘⇧M") : nil)
        meetingKuerzel.setze(auf ? Kuerzel(taste: 15, modifier: Kuerzel.cmd | Kuerzel.shift, zeichen: "⌘⇧R") : nil)
        var wertet = false
        if case .wertAus = z { wertet = true }
        let vorher = meetingWertetAus
        meetingWertetAus = wertet
        let ablage = MeetingDienst.gemeinsam.ablage
        guard MeetingMeldung.soll(vorherWertetAus: vorher, jetztFertig: z == .fertig, hatDatei: ablage != nil, fensterVorn: Self.meetingFensterVorn()),
              let ablage else { return }
        var fehlt = false
        if case .ohneZusammenfassung = ablage.ergebnis.stand { fehlt = true }
        let m = MeetingMeldung.text(ablage.ergebnis, vorschlaege: MeetingDienst.gemeinsam.vorschlaege.count)
        guard MacPfade.profil == .echt, !Hintergrund.aktiv else { return }
        guard einstellungen.mitteilungenAn else { return }
        guard meetingGemeldet.insert(MeetingMeldung.kennung(datei: ablage.datei.path, zusammenfassungFehlt: fehlt)).inserted else { return }
        Task { await mitteilungen.zeigeMeeting("fertig", m.titel, m.text, m.knoepfe) }
    }

    static func meetingFensterVorn() -> Bool {
        guard NSApp.isActive, let w = NSApp.keyWindow ?? NSApp.mainWindow, w.isVisible else { return false }
        return w.identifier?.rawValue.lowercased().contains("meeting") == true || w.title == "Meeting"
    }
}

#if DEBUG
enum MenueProbe {
    @MainActor static func laufe(dienste: MacDienste) async {
        guard MacPfade.profil == .demo, let ordner = MacPfade.datenOrdner else { return }
        try? await Task.sleep(for: .seconds(4))
        if ProcessInfo.processInfo.environment["SENECA_MENUE_PROBE"] == "breite" {
            let k = await breiteProbe(dienste: dienste)
            if let daten = try? JSONSerialization.data(withJSONObject: k, options: [.sortedKeys, .prettyPrinted]) {
                try? daten.write(to: ordner.appendingPathComponent("menue-breite.json"))
            }
            return
        }
        var w: [String: Any] = [:]
        let z = dienste.zeichen.zeichen
        w["zeichen"] = ["symbol": z.symbol, "text": z.text ?? "", "punkt": z.punkt ?? "", "ansage": z.ansage] as [String: Any]
        let d = DiktatDienst.gemeinsam
        w["diktat"] = ["zustand": "\(DiktatDienst.phase(d.zustand))", "anzeige": "\(DiktatDienst.phase(d.anzeigeZustand))"]
        w["blase"] = NSApp.windows.filter { $0.className.contains("DiktatPanel") }.map { p in
            ["sichtbar": p.isVisible, "alpha": Double(p.alphaValue), "ebene": p.level.rawValue, "verhalten": p.collectionBehavior.rawValue,
             "rahmen": NSStringFromRect(p.frame), "nichtVerdeckt": p.occlusionState.contains(.visible), "aufAktivemSchreibtisch": p.isOnActiveSpace] as [String: Any]
        }
        w["ziel"] = VorneMerker.gemeinsam.zielSatz
        if let p = NSApp.windows.first(where: { $0.className.contains("DiktatPanel") }) { w["blaseBild"] = await lies(fenster: p, sichern: nil) }
        if let h = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            w["fensterBild"] = await lies(fenster: h, sichern: ordner.appendingPathComponent("fenster-probe.png"))
        }
        if ProcessInfo.processInfo.environment["SENECA_MENUE_PROBE"] == "foto" {
            switch await BildschirmFoto.nimm(display: BildschirmFoto.unterMaus()) {
            case .foto(let u):
                let g = ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0
                w["foto"] = ["ergebnis": "foto", "bytes": g, "datei": u.path] as [String: Any]
            case .keineFreigabe: w["foto"] = ["ergebnis": "keineFreigabe"]
            case .fehler: w["foto"] = ["ergebnis": "fehler"]
            }
        }
        if let daten = try? JSONSerialization.data(withJSONObject: w, options: [.sortedKeys, .prettyPrinted]) {
            try? daten.write(to: ordner.appendingPathComponent("menue-probe.json"))
        }
    }

    @MainActor static func breiteProbe(dienste: MacDienste) async -> [String: Any] {
        var w: [String: Any] = [:]
        w["statusFenster"] = NSApp.windows.filter { $0.className.contains("StatusBar") }.count
        w["fensterKennungen"] = NSApp.windows.map { "\($0.className)|\($0.identifier?.rawValue ?? "-")|main=\($0.canBecomeMain)" }
        guard let k = MenueFenster.statusKnopf() else { w["knopf"] = false; return w }
        MenueZeichenModell.festeZiffern()
        var breite: [String: Double] = [:]
        for t in ["00:00", "11:11", "44:44", "17:41"] {
            dienste.zeichen.probeSetze(MenueZeichen(bild: .aufnahme, text: t, ansage: "Probe"))
            try? await Task.sleep(for: .milliseconds(350))
            breite[t] = Double(k.window?.frame.width ?? -1)
        }
        w["breite"] = breite
        w["knopfSchrift"] = k.font?.fontName ?? ""
        dienste.zeichen.probeSetze(MenueZeichen.entscheide(meetingNimmtAuf: false, meetingDauer: 0, meetingArbeitet: false, braucht: dienste.braucht))
        return w
    }

    @MainActor private static func lies(fenster: NSWindow, sichern: URL?) async -> [String: Any] {
        guard CGPreflightScreenCaptureAccess(),
              let inhalt = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let f = inhalt.windows.first(where: { $0.windowID == CGWindowID(fenster.windowNumber) }) else { return ["messbar": false] }
        let cfg = SCStreamConfiguration()
        cfg.width = Int(f.frame.width * 2); cfg.height = Int(f.frame.height * 2)
        cfg.showsCursor = false
        guard let bild = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: f), configuration: cfg) else { return ["messbar": false] }
        if let sichern, let png = NSBitmapImageRep(cgImage: bild).representation(using: .png, properties: [:]) { try? png.write(to: sichern) }
        let anfrage = VNRecognizeTextRequest()
        anfrage.recognitionLevel = .accurate
        anfrage.recognitionLanguages = ["de-DE"]
        try? VNImageRequestHandler(cgImage: bild).perform([anfrage])
        let zeilen = (anfrage.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        func hat(_ w: String) -> Bool { zeilen.contains { $0.localizedCaseInsensitiveContains(w) } }
        return ["messbar": true, "zeilen": zeilen.count, "hoertZu": hat("Hört zu") || hat("höre nichts"), "mikrofonName": hat("Mikrofon"),
                "hinweisFertig": hat("wenn du fertig bist"), "groesse": "\(bild.width)x\(bild.height)"]
    }
}
#endif
