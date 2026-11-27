import SwiftUI
import AppKit
import Combine

private final class WellenGlaetter {
    var pegel = 0.0
    var ausschlag = 0.0
    var schimmer = 0.0
    var schimmerStart = Date()
}

struct DiktatHorizont: View {
    @ObservedObject var dienst: DiktatDienst
    @State private var bild = Bild.aus
    @State private var seit = Date()
    @State private var aufSeit = Date()
    @State private var glaetter = WellenGlaetter()

    static let laenge: CGFloat = 440
    private static let hoehe: CGFloat = 48

    enum Bild: Equatable { case aus, oeffnet, hoert, schreibt, eingefuegt, fehler, beendet }

    private var aktuell: Bild {
        if dienst.beendetHinweis { return .beendet }
        if dienst.startetAnzeige { return .oeffnet }
        switch dienst.anzeigeZustand {
        case .ruht: return dienst.zustand == .ruht ? .aus : .hoert
        case .hoert: return .hoert
        case .erkennt: return .schreibt
        case .eingefuegt: return .eingefuegt
        case .fehler: return .fehler
        }
    }

    private var ruht: Bool { dienst.zustand == .ruht && !dienst.beendetHinweis && !dienst.startetAnzeige }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: ruht)) { ctx in
            let dt = ctx.date.timeIntervalSince(seit)
            let zieh = bild == .eingefuegt ? Self.seg(dt, 0.85, 1.45) : 0
            VStack(spacing: 6) {
                ZStack {
                    zeile(ctx.date).id(bild)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.15).delay(0.12)), removal: .opacity.animation(.easeIn(duration: 0.12))))
                }
                .animation(.easeInOut(duration: 0.15), value: bild)
                    .opacity((0.35 + 0.65 * Self.seg(ctx.date.timeIntervalSince(aufSeit), 0, 0.5)) * (1 - zieh))
                Canvas { g, groesse in male(g, groesse, ctx.date) }.frame(height: Self.hoehe)
            }
            .frame(width: Self.laenge + 40)
            .background(EllipticalGradient(colors: [TafelFarbe.hex(0x061632, 0.6 * (1 - zieh)), TafelFarbe.hex(0x061632, 0.3 * (1 - zieh)), TafelFarbe.hex(0x061632, 0)]).frame(width: Self.laenge + 160, height: 150))
        }
        .onAppear { wechsle(aktuell) }
        .onChange(of: aktuell) { _, neu in wechsle(neu) }
        .accessibilityElement(children: .combine)
    }

    private func wechsle(_ neu: Bild) {
        let jetzt = Date()
        if bild == .aus || neu == .oeffnet || neu == .beendet || neu == .hoert && bild != .oeffnet { aufSeit = jetzt }
        if neu == .schreibt { glaetter.schimmerStart = jetzt }
        bild = neu
        seit = jetzt
    }

    private func marke(_ t: String, _ farbe: Color) -> some View {
        Text(t).font(Schrift.mono(11)).tracking(2.6).foregroundStyle(farbe).lineLimit(1)
    }

    @ViewBuilder private func zeile(_ jetzt: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            switch bild {
            case .aus, .oeffnet:
                marke("MIKROFON ÖFFNET", TafelFarbe.zweit); Spacer(minLength: 0)
            case .hoert:
                let still = DiktatWache.ichHoereNichts(sekundenSeitAusschlag: jetzt.timeIntervalSince(dienst.letzterAusschlag))
                marke(still ? "ICH HÖRE NICHTS" : "HÖRT ZU", still ? TafelFarbe.jetzt : TafelFarbe.zweit); Spacer(minLength: 0)
                marke(DiktatWache.laufzeit(jetzt.timeIntervalSince(dienst.aufnahmeBeginn)), Self.tinte3).monospacedDigit()
            case .schreibt:
                marke("SCHREIBT", TafelFarbe.zweit); Spacer(minLength: 0)
            case .eingefuegt:
                marke("EINGEFÜGT", TafelFarbe.hex(0x9FE3B6)); Spacer(minLength: 0)
                if case .eingefuegt(let t) = dienst.anzeigeZustand { marke("\(Self.woerter(t)) \(Self.woerter(t) == 1 ? "WORT" : "WÖRTER")", Self.tinte3) }
            case .beendet:
                marke("AUFNAHME BEENDET", TafelFarbe.zweit); Spacer(minLength: 0)
                marke("MIKROFON LIEFERT NICHTS", Self.tinte3)
            case .fehler:
                if case .fehler(let meldung, _) = dienst.anzeigeZustand {
                    Text(meldung).font(Schrift.grotesk(13)).foregroundStyle(Farbe.warnText).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if dienst.letzteAufnahme != nil {
                    Button("Erneut erkennen") { dienst.erneutErkennen() }.buttonStyle(.plain)
                        .font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.himmel).accessibilityIdentifier("diktat-erneut")
                }
                Button { dienst.schliessePille() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(TafelFarbe.zweit)
                    .accessibilityLabel("Hinweis schließen")
            }
        }
        .padding(.horizontal, 20)
    }

    private func male(_ g: GraphicsContext, _ groesse: CGSize, _ jetzt: Date) {
        let dt = jetzt.timeIntervalSince(seit), dtAuf = jetzt.timeIntervalSince(aufSeit)
        let t = jetzt.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
        let auf = Self.seg(dtAuf, 0, 0.5)
        switch bild {
        case .hoert: glaetter.pegel += (dienst.pegelQuelle.wert - glaetter.pegel) * 0.22
        case .schreibt, .eingefuegt: break
        default: glaetter.pegel = 0
        }
        let atem = 1 + 0.35 * sin(t * .pi * 2 / 1.6)
        let ruhig = bild == .schreibt ? Self.seg(dt, 0, 0.8) : 1
        let lv = bild == .hoert ? glaetter.pegel : bild == .schreibt ? glaetter.pegel * (1 - ruhig) : 0
        let glatt = bild == .eingefuegt ? 1 - Self.seg(dt, 0, 0.55) : 1
        let ziel: Double = switch bild {
        case .hoert: (0.2 + lv) * Self.seg(dtAuf, 0.15, 0.6)
        case .schreibt: (0.2 + lv) * (1 + (atem * 1.1 - 1) * ruhig)
        case .eingefuegt: 0.2 * atem * 1.1 * glatt
        default: 0
        }
        glaetter.ausschlag += (ziel - glaetter.ausschlag) * (bild == .eingefuegt ? 0.3 : 0.2)
        let amp = glaetter.ausschlag
        let schimmerZiel = bild == .schreibt ? Self.seg(dt, 0.05, 0.5) : 0
        glaetter.schimmer = schimmerZiel > glaetter.schimmer ? schimmerZiel : glaetter.schimmer + (0 - glaetter.schimmer) * 0.12
        let sh = glaetter.schimmer
        let schimmerOrt = -0.1 + 1.2 * (jetzt.timeIntervalSince(glaetter.schimmerStart) / 1.15).truncatingRemainder(dividingBy: 1)
        let gruen = bild == .eingefuegt ? Self.seg(dt, 0.35, 0.65) : 0
        let flash = bild == .eingefuegt ? Self.seg(dt, 0.4, 0.6) * (1 - Self.seg(dt, 0.7, 1.2)) : 0
        let zieh = bild == .eingefuegt ? Self.seg(dt, 0.85, 1.45) : 0
        let erlischt = bild == .eingefuegt ? Self.seg(dt, 1.15, 1.58) : 0
        let sicht = (0.35 + 0.65 * auf) * (1 - erlischt)
        let l = Self.laenge * (0.06 + 0.94 * auf) * (1 - zieh * 0.95)
        let mitte = groesse.height / 2, x0 = groesse.width / 2 - l / 2, x1 = groesse.width / 2 + l / 2
        let grund: (Double, Double, Double) = switch bild {
        case .fehler: (240, 122, 95)
        case .beendet: (107, 118, 134)
        default: (255 + (107 - 255) * gruen, 255 + (217 - 255) * gruen, 255 + (143 - 255) * gruen)
        }
        let grundAlpha = bild == .fehler || bild == .beendet ? 0.85 : 0.95 + (0.72 - 0.95) * sh + ((0.55 + flash * 0.45) - (0.95 + (0.72 - 0.95) * sh)) * gruen
        let nebenAlpha = bild == .oeffnet || bild == .hoert || bild == .schreibt || bild == .eingefuegt ? glatt : 0
        let welle: (Int, Double) -> Path = { k, breite in
            var p = Path()
            var px = x0
            while px <= x1 {
                let u = (px - x0) / max(1, x1 - x0), huelle = pow(sin(.pi * u), 1.4), q = Double(px - x0) + 230, kd = Double(k)
                let y = mitte + huelle * amp * (17 - kd * 4.5) * sin(q * (0.05 + kd * 0.022) - t * (5 + kd * 1.7) + kd * 1.3) * sin(q * 0.017 + t * 1.3 + kd)
                if px == x0 { p.move(to: CGPoint(x: px, y: y)) } else { p.addLine(to: CGPoint(x: px, y: y)) }
                px += breite
            }
            return p
        }
        let waagrecht = { (stops: [Gradient.Stop]) in GraphicsContext.Shading.linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)) }
        var d = g
        d.addFilter(.blur(radius: 2.5))
        let unter = (0...32).map { i -> Gradient.Stop in
            let u = Double(i) / 32
            return .init(color: .black.opacity(0.4 * sicht * min(1, u / 0.18, (1 - u) / 0.18)), location: u)
        }
        d.stroke(welle(0, 1), with: waagrecht(unter), lineWidth: 4)
        for k in [2, 1, 0] {
            let anteil = k == 0 ? 1 : nebenAlpha
            if anteil < 0.01 { continue }
            let stops = (0...32).map { i -> Gradient.Stop in
                let u = Double(i) / 32, rand = min(1, u / 0.18, (1 - u) / 0.18), band = sh * exp(-pow((u - schimmerOrt) / 0.075, 2))
                var (r, gg, bb) = k == 0 ? grund : (143.0, 182.0, 227.0)
                var a = k == 0 ? grundAlpha : (k == 1 ? 0.7 : 0.5) * anteil
                r += (255 - r) * band; gg += (255 - gg) * band; bb += (255 - bb) * band; a = min(1, a + band * 0.6)
                return .init(color: Color(.sRGB, red: r / 255, green: gg / 255, blue: bb / 255, opacity: a * rand * sicht), location: u)
            }
            var c = g
            c.blendMode = .plusLighter
            c.addFilter(.shadow(color: (gruen > 0.5 && k == 0 ? Farbe.gruen : bild == .fehler ? TafelFarbe.jetzt : Farbe.himmel).opacity(0.95 * sicht),
                                radius: k == 0 ? 5 + flash * 7 + lv * 4 + sh * 2 : 2.5))
            c.stroke(welle(k, 1), with: waagrecht(stops), lineWidth: k == 0 ? 1.5 + flash * 1.2 : 1)
        }
        if sh > 0.01 {
            let stops = (0...48).map { i -> Gradient.Stop in
                let u = Double(i) / 48, band = exp(-pow((u - schimmerOrt) / 0.06, 2)) * min(1, u / 0.12, (1 - u) / 0.12)
                return .init(color: Color(.sRGB, red: 220 / 255, green: 236 / 255, blue: 1, opacity: 0.85 * band * sh * sicht), location: u)
            }
            var c = g
            c.blendMode = .plusLighter
            c.addFilter(.shadow(color: TafelFarbe.hex(0xCFE4FA, sicht), radius: 7))
            c.stroke(welle(0, 1), with: waagrecht(stops), lineWidth: 2.6)
        }
    }

    private static let tinte3 = TafelFarbe.hex(0x8A93A0)
    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { ease(min(1, max(0, (t - a) / (b - a)))) }
    static func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func woerter(_ t: String) -> Int { t.split(whereSeparator: \.isWhitespace).count }
}

struct DiktatBlasenInhalt: View {
    @ObservedObject var dienst: DiktatDienst

    var body: some View {
        DiktatHorizont(dienst: dienst)
            .padding(40).fixedSize()
            .accessibilityIdentifier("diktat-blase")
    }
}


private final class DiktatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BlasenAnzeige: ObservableObject {
    @Published var ort = CGPoint.zero
    @Published var flaeche = CGSize(width: 1, height: 1)
}

struct DiktatBlasenBuehne: View {
    @ObservedObject var dienst: DiktatDienst
    @ObservedObject var anzeige: BlasenAnzeige
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        ZStack {
            DiktatBlasenInhalt(dienst: dienst)
                .position(anzeige.ort)
        }
        .frame(width: anzeige.flaeche.width, height: anzeige.flaeche.height)
        .animation(ruhig ? .easeOut(duration: 0.15) : Kurve.feder(0.45), value: anzeige.ort)
    }
}

@MainActor
final class DiktatBlase {
    private var panel: DiktatPanel?
    private var host: NSHostingView<DiktatBlasenBuehne>?
    private var abo: AnyCancellable?
    private var dienst: DiktatDienst?
    private let anzeige = BlasenAnzeige()
    private var takt: Timer?
    private var messt = false
    private var zustand: DiktatDienst.Zustand = .ruht
    private var beendetHinweis = false
    private var hindernisse: [CGRect] = []
    private var schirm: NSScreen?
    private var wechselAbo: AnyCancellable?

    func zeige(dienst: DiktatDienst) {
        guard panel == nil else { return }
        self.dienst = dienst
        let h = NSHostingView(rootView: DiktatBlasenBuehne(dienst: dienst, anzeige: anzeige))
        h.sizingOptions = []
        let p = DiktatPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = h
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.alphaValue = 0
        panel = p
        host = h
        let ws = NSWorkspace.shared.notificationCenter
        wechselAbo = Publishers.Merge(ws.publisher(for: NSWorkspace.activeSpaceDidChangeNotification), ws.publisher(for: NSWorkspace.didActivateApplicationNotification))
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.nachziehen() } }
        abo = Publishers.CombineLatest(dienst.$zustand, dienst.$beendetHinweis).removeDuplicates { $0 == $1 }
            .sink { [weak self] z, hinweis in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.aktualisiere(z, beendetHinweis: hinweis) } }
            }
    }

    private func kapselGroesse() -> CGSize {
        guard let dienst else { return CGSize(width: 400, height: 60) }
        let f = NSHostingView(rootView: DiktatBlasenInhalt(dienst: dienst)).fittingSize
        return CGSize(width: max(60, f.width - 80), height: max(40, f.height - 80))
    }

    private func standardMitte(_ sichtbar: CGRect, _ kapsel: CGSize) -> CGPoint {
        CGPoint(x: sichtbar.midX, y: sichtbar.minY + 48 + kapsel.height / 2)
    }

    private var istFehler: Bool { if case .fehler = zustand { return true } else { return false } }

    private func lage(_ sichtbar: CGRect, _ kapsel: CGSize) -> BlasenLage {
        let standard = standardMitte(sichtbar, kapsel)
        var h = hindernisse
        #if DEBUG
        if MacPfade.profil == .demo, ProcessInfo.processInfo.environment["SENECA_DIKTAT_HINDERNIS"] == "feld" {
            h.append(CGRect(x: standard.x - 330, y: standard.y - 22, width: 290, height: 44))
        }
        #endif
        if NSApp.isActive, let w = NSApp.mainWindow, w.isVisible, w.frame.width > 800, w.identifier?.rawValue.contains("haupt") == true {
            h.append(CGRect(x: w.frame.midX - 380, y: w.frame.minY, width: 760, height: 150))
        }
        return BlasenPlatz.entscheide(standard: standard, grossGroesse: kapsel, hindernisse: h, bildschirm: sichtbar)
    }

    private func setzeLage(_ l: BlasenLage, _ sichtbar: CGRect, _ kapsel: CGSize) {
        guard let p = panel else { return }
        let flaeche: CGRect
        if istFehler {
            flaeche = CGRect(x: l.zentrum.x - kapsel.width / 2 - 40, y: l.zentrum.y - kapsel.height / 2 - 40, width: kapsel.width + 80, height: kapsel.height + 80)
        } else {
            flaeche = schirm?.frame ?? sichtbar
        }
        if p.frame != flaeche { p.setFrame(flaeche, display: false) }
        anzeige.flaeche = flaeche.size
        anzeige.ort = CGPoint(x: l.zentrum.x - flaeche.minX, y: flaeche.maxY - l.zentrum.y)
    }

    private func neuBerechnen(sprung: Bool) {
        guard panel != nil else { return }
        let sichtbar = schirm?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let kapsel = kapselGroesse()
        let l = lage(sichtbar, kapsel)
        if sprung { withTransaction(Transaction(animation: nil)) { setzeLage(l, sichtbar, kapsel) } } else { setzeLage(l, sichtbar, kapsel) }
    }

    private func starteTakt() {
        guard takt == nil else { return }
        takt = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.messe() }
        }
    }

    private func stoppeTakt() { takt?.invalidate(); takt = nil }

    private func nachziehen() {
        if sichtbarLaut, let p = panel, p.alphaValue > 0, !(p.isVisible && p.isOnActiveSpace) { p.orderFrontRegardless() }
    }

    private func messe() {
        nachziehen()
        guard !messt, zustand != .ruht else { return }
        messt = true
        let hoehe = NSScreen.screens.first?.frame.height ?? 900
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task.detached(priority: .utility) { [weak self] in
            let h = BlasenHindernisse.lesen(primaerHoehe: hoehe, vorderePid: pid)
            await MainActor.run {
                guard let self else { return }
                self.messt = false
                guard self.zustand != .ruht, h != self.hindernisse else { return }
                self.hindernisse = h
                self.neuBerechnen(sprung: false)
            }
        }
    }

    private var sichtbarLaut: Bool {
        DiktatWache.blaseSichtbar(phase: DiktatDienst.phase(zustand), zeigtBeendetHinweis: beendetHinweis)
    }

    private func aktualisiere(_ z: DiktatDienst.Zustand, beendetHinweis hinweis: Bool) {
        guard let p = panel else { return }
        zustand = z
        beendetHinweis = hinweis
        if !sichtbarLaut {
            stoppeTakt()
            NSAnimationContext.runAnimationGroup({ c in
                c.duration = 0.25
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak p] in
                MainActor.assumeIsolated {
                    guard let self, !self.sichtbarLaut, p?.alphaValue == 0 else { return }
                    p?.orderOut(nil)
                    self.hindernisse = []
                }
            })
            return
        }
        p.ignoresMouseEvents = !istFehler
        let neuAuf = !p.isVisible || p.alphaValue == 0
        if neuAuf {
            schirm = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        }
        neuBerechnen(sprung: neuAuf || istFehler)
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.2
            p.animator().alphaValue = 1
        }
        starteTakt()
        messe()
    }
}

#if DEBUG
extension DiktatBlase {
    var pruefung: [String: Any]? {
        panel.map { p in
            let r = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
            let w = r?.first { ($0[kCGWindowNumber as String] as? Int) == p.windowNumber }
            return ["ebene": p.level.rawValue, "verhalten": p.collectionBehavior.rawValue,
                    "stil": p.styleMask.rawValue, "nichtAktivierend": p.styleMask.contains(.nonactivatingPanel), "schwebend": p.isFloatingPanel,
                    "klicksDurch": p.ignoresMouseEvents, "kannSchluessel": p.canBecomeKey, "kannHaupt": p.canBecomeMain,
                    "sichtbar": p.isVisible, "alpha": Double(p.alphaValue), "aufAktivemSchreibtisch": p.isOnActiveSpace,
                    "rahmen": NSStringFromRect(p.frame), "fensterserverSichtbar": (w?[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                    "fensterserverEbene": (w?[kCGWindowLayer as String] as? Int) ?? -1]
        }
    }
}

enum DiktatSicht {
    nonisolated static var datei: String? { ProcessInfo.processInfo.environment["SENECA_DIKTAT_SICHT"].flatMap { $0.isEmpty ? nil : $0 } }

    @MainActor static func laufe(_ dienst: DiktatDienst, datei: String) async {
        NSApp.setActivationPolicy(.regular)
        try? await Task.sleep(for: .seconds(2))
        var zeilen: [[String: Any]] = []
        let schirm = NSScreen.screens.first?.frame ?? .zero
        for art in ["hoert", "erkennt", "eingefuegt", "startfehler", "beendet"] {
            dienst.blasenProbe(art)
            try? await Task.sleep(for: .seconds(1.3))
            var z = dienst.blasenPruefung ?? [:]
            let vorn = NSWorkspace.shared.frontmostApplication
            let fenster = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
                .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == vorn?.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
            let b = fenster.compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }.max { $0.height < $1.height }
            z["phase"] = art
            z["vorn"] = vorn?.bundleIdentifier ?? "?"
            z["senecaVorn"] = NSApp.isActive
            z["vornVollbild"] = b.map { $0.width >= schirm.width && $0.maxY >= schirm.height } ?? false
            z["entscheidung"] = DiktatWache.blaseSichtbar(phase: DiktatDienst.phase(dienst.zustand), zeigtBeendetHinweis: dienst.beendetHinweis)
            zeilen.append(z)
        }
        let daten = try? JSONSerialization.data(withJSONObject: zeilen, options: [.sortedKeys, .prettyPrinted])
        try? daten?.write(to: URL(fileURLWithPath: datei))
        exit(0)
    }
}

enum DiktatFilm {
    nonisolated static var ordner: String? { ProcessInfo.processInfo.environment["SENECA_DIKTAT_FILM"].flatMap { $0.isEmpty ? nil : $0 } }

    static func laufe(_ ordner: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let dienst = DiktatDienst.gemeinsam
            let szene = ZStack(alignment: .bottom) {
                LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
                DiktatBlasenInhalt(dienst: dienst).padding(.bottom, 8)
            }
            .frame(width: 900, height: 280).preferredColorScheme(.dark)
            let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 280), styleMask: [.borderless], backing: .buffered, defer: true)
            let host = NSHostingView(rootView: szene)
            fenster.contentView = host
            try? FileManager.default.createDirectory(atPath: ordner, withIntermediateDirectories: true)
            let start = Date()
            var phase = ""
            var n = 0
            while Date().timeIntervalSince(start) < 7.2 {
                let t = Date().timeIntervalSince(start)
                let soll = t < 3.4 ? "hoert" : t < 4.8 ? "erkennt" : "eingefuegt"
                if soll != phase { phase = soll; dienst.blasenProbe(soll) }
                host.layoutSubtreeIfNeeded(); CATransaction.flush()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ordner + String(format: "/%@-%04d-%.2f.png", phase, n, t)))
                    n += 1
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
            exit(0)
        }
        app.run()
        exit(0)
    }
}
#endif
