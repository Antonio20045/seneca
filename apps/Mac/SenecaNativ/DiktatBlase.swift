import SwiftUI
import AppKit
import Combine

struct PegelKugel: View {
    @ObservedObject var quelle: PegelQuelle
    let groesse: CGFloat, wachs: Double, schatten: Double, ruhig: Bool

    var body: some View {
        let p = quelle.wert
        SnKugel(groesse: groesse, atmet: false)
            .scaleEffect(ruhig ? 1 : 1 + wachs * p)
            .opacity(0.8 + 0.2 * p)
            .shadow(color: Farbe.himmelLicht2.opacity(0.3 + 0.6 * p), radius: 6 + schatten * p)
            .animation(.easeOut(duration: 0.1), value: p)
    }
}

struct PegelBalken: View {
    @ObservedObject var quelle: PegelQuelle
    let ruhig: Bool

    var body: some View {
        let p = max(0.04, quelle.wert)
        ZStack(alignment: .leading) {
            Capsule().fill(Farbe.ink3.opacity(0.18))
            Capsule().fill(Farbe.himmelLicht2).scaleEffect(x: p, y: 1, anchor: .leading)
        }
        .frame(width: 120, height: 5)
        .animation(ruhig ? nil : .easeOut(duration: 0.1), value: p)
        .accessibilityHidden(true)
    }
}

struct DiktatBlasenInhalt: View {
    @ObservedObject var dienst: DiktatDienst
    @Environment(\.accessibilityReduceMotion) private var ruhig
    private var anzeige: DiktatDienst.Zustand { dienst.anzeigeZustand }

    var body: some View {
        kapsel
            .accessibilityIdentifier("diktat-blase")
    }

    private var kapsel: some View {
        HStack(spacing: 16) {
            zeichen
            VStack(alignment: .leading, spacing: 4) {
                inhalt
            }
            .frame(minWidth: 230, maxWidth: 400, alignment: .leading)
            if istFehler {
                if dienst.letzteAufnahme != nil {
                    Button("Erneut erkennen") { dienst.erneutErkennen() }
                        .buttonStyle(.plain)
                        .font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.himmel)
                        .accessibilityIdentifier("diktat-erneut")
                }
                Button { dienst.schliessePille() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Farbe.ink3)
                    .accessibilityLabel("Hinweis schließen")
            }
        }
        .padding(.leading, 16).padding(.trailing, 28).padding(.vertical, istFehler ? 18 : 14)
        .snGlas(Capsule())
        .overlay(istFehler ? Capsule().stroke(Farbe.warnKante, lineWidth: 1) : nil)
        .padding(40)
        .fixedSize()
        .animation(Kurve.feder(0.35), value: anzeige)
    }

    @ViewBuilder private var inhalt: some View {
        if dienst.beendetHinweis || !hoert {
            Text(text)
                .font(Schrift.grotesk(16, .medium)).foregroundStyle(istFehler ? Farbe.warnText : Farbe.ink)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if let zeile = unterzeile {
                Text(zeile).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
            }
        } else if dienst.startetAnzeige {
            Text("Starte …").font(Schrift.grotesk(16, .medium)).foregroundStyle(Farbe.ink)
            Text("Das Mikrofon wird geöffnet").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let still = DiktatWache.ichHoereNichts(sekundenSeitAusschlag: ctx.date.timeIntervalSince(dienst.letzterAusschlag))
                VStack(alignment: .leading, spacing: 4) {
                    Text(still ? "Ich höre nichts" : "Hört zu …")
                        .font(Schrift.grotesk(16, .medium)).foregroundStyle(still ? Farbe.warnText : Farbe.ink)
                    HStack(spacing: 10) {
                        Text(DiktatWache.laufzeit(ctx.date.timeIntervalSince(dienst.aufnahmeBeginn)))
                            .font(Schrift.grotesk(13, .medium)).monospacedDigit().foregroundStyle(Farbe.ink2)
                        PegelBalken(quelle: dienst.pegelQuelle, ruhig: ruhig)
                    }
                    Text(dienst.geraeteName ?? "Mikrofon")
                        .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(1)
                }
            }
        }
    }

    private var hoert: Bool { if case .hoert = anzeige { return true } else { return false } }

    private var istFehler: Bool { if case .fehler = anzeige { return true } else { return false } }

    @ViewBuilder private var zeichen: some View {
        switch anzeige {
        case .hoert:
            PegelKugel(quelle: dienst.pegelQuelle, groesse: 52, wachs: 0.45, schatten: 22, ruhig: ruhig)
                .frame(width: 60, height: 60)
        case .erkennt:
            SnKugel(groesse: 44, atmet: true)
                .shadow(color: Farbe.himmelLicht2.opacity(0.35), radius: 8)
                .frame(width: 44, height: 44)
        case .eingefuegt:
            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Farbe.gruen)
                .frame(width: 44, height: 44)
        case .fehler(_, let zwischenablage):
            Image(systemName: zwischenablage ? "doc.on.clipboard" : "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Farbe.koralle)
                .frame(width: 44, height: 44)
        case .ruht:
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var text: String {
        if dienst.beendetHinweis { return "Aufnahme beendet" }
        return zustandText
    }

    private var zustandText: String {
        switch anzeige {
        case .ruht: return ""
        case .hoert: return "Hört zu …"
        case .erkennt: return "Erkennt …"
        case .eingefuegt(let t): return t.count <= 90 ? t : String(t.prefix(88)) + "…"
        case .fehler(let meldung, _): return meldung
        }
    }

    private var unterzeile: String? {
        if dienst.beendetHinweis {
            if case .hoert = anzeige { return "Das Mikrofon hat nichts mehr geliefert." }
            let z = zustandText
            return z.isEmpty ? "Das Mikrofon hat nichts mehr geliefert." : z
        }
        return nil
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

    private func messe() {
        if sichtbarLaut, let p = panel, p.alphaValue > 0, !p.isVisible { p.orderFrontRegardless() }
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
