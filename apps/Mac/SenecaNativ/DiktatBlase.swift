import SwiftUI
import AppKit
import Combine

struct PegelWelle: View {
    @ObservedObject var quelle: PegelQuelle
    var hoehe: CGFloat = 18
    var anzahl = 12
    @State private var werte: [Double] = []

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(werte.enumerated()), id: \.offset) { _, w in RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.9)).frame(width: 2.5, height: max(4, hoehe * min(1, w))) }
            ForEach(Array([5.0, 3, 4, 3, 5, 3, 4, 3, 5, 3].prefix(anzahl / 3).enumerated()), id: \.offset) { _, h in RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.35)).frame(width: 2.5, height: h) }
        }
        .frame(height: hoehe).accessibilityHidden(true)
        .onChange(of: quelle.wert) { _, w in werte = Array((werte + [w]).suffix(anzahl)) }
    }
}

struct DiktatPille: View {
    @ObservedObject var dienst: DiktatDienst
    var feld = false

    private func taste(_ t: String) -> Text { Text(" \(t) ").font(Schrift.mono(11)).foregroundColor(TafelFarbe.zweit) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let still = DiktatWache.ichHoereNichts(sekundenSeitAusschlag: ctx.date.timeIntervalSince(dienst.letzterAusschlag))
            HStack(spacing: feld ? 14 : 10) {
                Circle().fill(TafelFarbe.jetzt).frame(width: 8, height: 8).background(Circle().fill(TafelFarbe.jetzt.opacity(0.18)).frame(width: 16, height: 16))
                    .phaseAnimator([0.35, 1]) { v, p in v.opacity(p) } animation: { _ in .easeInOut(duration: 0.8) }
                Text(still ? "Ich höre nichts" : "Hört zu").font(Schrift.grotesk(feld ? 15 : 14, .medium)).foregroundStyle(still ? TafelFarbe.jetzt : .white)
                Text(DiktatWache.laufzeit(ctx.date.timeIntervalSince(dienst.aufnahmeBeginn))).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.zweit).monospacedDigit()
                if feld { Spacer(minLength: 0) }
                PegelWelle(quelle: dienst.pegelQuelle, hoehe: feld ? 22 : 18, anzahl: feld ? 30 : 12)
                Spacer(minLength: 0)
                if feld {
                    HStack(spacing: 4) {
                        Text("fertig"); taste("rechte ⌘").overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                        Text("· verwerfen"); taste("esc").overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    }.font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
                } else if let z = dienst.zielText {
                    HStack(spacing: 6) { Text("→").foregroundStyle(TafelFarbe.aus); Text(z).lineLimit(1) }.font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
                }
            }
            .padding(.leading, feld ? 20 : 18).padding(.trailing, feld ? 16 : 18)
        }
    }
}

struct DiktatBlasenInhalt: View {
    @ObservedObject var dienst: DiktatDienst
    @Environment(\.accessibilityReduceMotion) private var ruhig
    private var anzeige: DiktatDienst.Zustand { dienst.anzeigeZustand }

    var body: some View {
        Group {
            if hoert, !dienst.beendetHinweis, !dienst.startetAnzeige {
                DiktatPille(dienst: dienst).frame(width: 560, height: 46)
                    .background(Capsule().fill(TafelFarbe.hex(0x0C1A32, 0.92)).shadow(color: .black.opacity(0.6), radius: 22, y: 18))
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)], startPoint: .top, endPoint: .center), lineWidth: 1))
                    .padding(40).fixedSize()
            } else { kapsel }
        }
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
        }
    }

    private var hoert: Bool { if case .hoert = anzeige { return true } else { return false } }

    private var istFehler: Bool { if case .fehler = anzeige { return true } else { return false } }

    @ViewBuilder private var zeichen: some View {
        switch anzeige {
        case .hoert:
            SnKugel(groesse: 44, atmet: true).frame(width: 44, height: 44)
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
        if !sichtbarLaut || (dienst?.imFeld == true && NSApp.isActive && !istFehler) {
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
