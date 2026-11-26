import SwiftUI

struct SnKalenderSeite: View {
    let projekte: any SnProjekteQuelle
    private let route: Route
    @ObservedObject private var k: SnKalenderSpeicher
    @State private var wischen = SnKalWischen()

    init(projekte: any SnProjekteQuelle, route: Route, speicher: SnKalenderSpeicher = .gemeinsam) {
        self.projekte = projekte
        self.route = route
        k = speicher
    }

    var body: some View {
        GeometryReader { g in
            let rand = min(72, max(28, (g.size.width - 1000) * 0.2))
            VStack(alignment: .leading, spacing: 0) {
                kopf
                hinweis
                HStack(alignment: .top, spacing: 24) {
                    inhalt.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if k.entwurf != nil {
                        SnKalFormular(k: k)
                            .frame(width: 340)
                            .transition(.opacity.combined(with: .offset(x: 14)))
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, rand).padding(.top, 84).padding(.bottom, 104)
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if k.sprungOffen {
                    SnKalSprung(k: k).padding(.leading, rand).padding(.top, 84 + 58)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            .overlay(alignment: .bottom) { rueckZeile.padding(.bottom, 100) }
        }
        .accessibilityIdentifier("seite-kalender")
        .task {
            k.verbinde(projekte)
            if let a = KalAnsicht(rawValue: route.q["ansicht"] ?? "") { k.wechsle(a) }
            while !Task.isCancelled {
                k.tick()
                await k.lade(erzwinge: k.zugriff != .direkt)
                try? await Task.sleep(for: .seconds(k.zugriff == .direkt ? 30 : 120))
            }
        }
        .onChange(of: projekte.kalender.termine) { _, _ in k.verbinde(projekte); k.gatewayStand() }
        .onAppear { wischen.starte { k.blaettere($0) } }
        .onDisappear { wischen.halte() }
    }

    private var kopf: some View {
        HStack(alignment: .center, spacing: 6) {
            Button { withAnimation(Kurve.sn(0.18)) { k.sprungOffen.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(k.titel).font(Schrift.serif(44)).lineHeight(.exact(points: 50)).foregroundStyle(Color.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.opacity)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Farbe.ink3)
                        .rotationEffect(.degrees(k.sprungOffen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Zu einem Datum springen")
            .accessibilityLabel("\(k.titel), zu einem Datum springen")
            .accessibilityAddTraits(.isHeader)
            .snProbeRahmen("titel")
            if k.stand.ansicht == .woche {
                Text("Woche \(KalRaster.kalenderwoche(k.stand.anker, k.cal))").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                    .padding(.leading, 10).padding(.top, 14).fixedSize()
            }
            Spacer(minLength: 16)
            SnKalPille(titel: "Heute", matt: k.zeigtHeute) { k.heute() }.snProbeRahmen("heute")
            SnRundKnopf(symbol: "chevron.left", beschriftung: "Zurück") { k.blaettere(-1) }.snProbeRahmen("zurueck")
            SnRundKnopf(symbol: "chevron.right", beschriftung: "Weiter") { k.blaettere(1) }.snProbeRahmen("weiter")
            SnKalUmschalter(gewaehlt: k.stand.ansicht) { k.wechsle($0) }.padding(.leading, 8)
        }
        .frame(height: 52)
    }

    @ViewBuilder private var hinweis: some View {
        if let m = k.meldung {
            HStack(spacing: 12) {
                Text(m).font(Schrift.grotesk(13)).foregroundStyle(Farbe.warnText)
                Button("Schließen") { k.meldung = nil }.buttonStyle(SnLeiserStil()).font(Schrift.grotesk(13, .medium))
            }
            .padding(.top, 8)
        } else if k.zugriff == .fragen || k.zugriff == .verweigert {
            HStack(spacing: 12) {
                Text(k.zugriff == .fragen
                     ? "Seneca liest den Kalender gerade über den Umweg des Gateways: nur die nächsten sechs Wochen, anlegen ja, ändern und Notizen nein."
                     : "Der direkte Zugriff auf Apple Kalender ist abgelehnt (Systemeinstellungen, Datenschutz, Kalender). Bis dahin: nur die nächsten sechs Wochen, anlegen ja, ändern und Notizen nein.")
                    .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
                if k.zugriff == .fragen {
                    Button("Direkten Zugriff erlauben") { Task { await k.erlaube() } }
                        .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.himmel).fixedSize()
                }
            }
            .padding(.top, 8)
        }
    }

    private var inhalt: some View {
        let tage = k.tage
        let schub = CGFloat(k.richtung) * 22
        return ZStack(alignment: .topLeading) {
            switch k.stand.ansicht {
            case .monat:
                SnKalMonat(k: k, tage: tage)
                    .id(tage[0])
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: schub)), removal: .opacity))
            case .tag, .woche:
                SnKalZeitraster(k: k, tage: tage).id(k.stand.ansicht).transition(.opacity)
            }
        }
    }

    @ViewBuilder private var rueckZeile: some View {
        if let r = k.rueck {
            HStack(spacing: 14) {
                Text(r.text).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1).lineLimit(1)
                Button("Rückgängig") { k.macheRueckgaengig() }
                    .buttonStyle(.plain).font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.himmel)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .snGlas(Capsule())
            .transition(.opacity.combined(with: .offset(y: 8)))
            .accessibilityIdentifier("kalender-rueckgaengig")
        }
    }
}

struct SnKalUmschalter: View {
    let gewaehlt: KalAnsicht
    let waehle: (KalAnsicht) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(KalAnsicht.allCases, id: \.self) { a in
                SnKalSegment(titel: a.name, an: a == gewaehlt) { waehle(a) }
                    .help("\(a.name) (Taste \(a.name.prefix(1)))")
                    .snProbeRahmen("ansicht-\(a.rawValue)")
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ansicht")
    }
}

private struct SnKalSegment: View {
    let titel: String
    let an: Bool
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Text(titel).font(Schrift.grotesk(13, .medium)).lineHeight(.exact(points: 18))
                .foregroundStyle(an || hover ? Color.white : Farbe.ink2)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(an ? Color.white.opacity(0.14) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.18), value: an)
        .accessibilityAddTraits(an ? .isSelected : [])
    }
}

struct SnKalPille: View {
    let titel: String
    var matt = false
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Text(titel).font(Schrift.grotesk(13, .medium)).lineHeight(.exact(points: 18))
                .foregroundStyle(hover ? Color.white : (matt ? Farbe.ink3 : Farbe.ink1))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(hover ? Color.white.opacity(0.08) : .clear))
                .overlay(Capsule().strokeBorder(Color.white.opacity(matt ? 0.08 : 0.16), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.18), value: hover)
    }
}

struct SnKalSprung: View {
    @ObservedObject var k: SnKalenderSpeicher

    var body: some View {
        let form = RoundedRectangle(cornerRadius: 18, style: .continuous)
        SnKalMiniMonat(cal: k.cal, beginn: k.stand.anker, markiert: k.stand.ansicht == .monat ? [] : Set(k.tage), heute: k.cal.startOfDay(for: k.jetzt)) { k.springe($0) }
            .padding(16)
            .background(form.fill(Color(hex: 0x10274A)))
            .overlay(form.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: Color(hex: 0x020816, deckkraft: 0.55), radius: 22, y: 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Datum wählen")
    }
}

struct SnKalMiniKnopf: View {
    let symbol: String
    let name: String
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(hover ? Color.white : Farbe.ink2)
                .frame(width: 26, height: 26).background(Circle().fill(hover ? Color.white.opacity(0.08) : .clear)).contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }.accessibilityLabel(name)
    }
}

@MainActor
enum SnKalenderTasten {
    static func taste(_ e: NSEvent, _ z: String) -> Bool {
        let k = SnKalenderSpeicher.gemeinsam
        switch e.keyCode {
        case 123: k.blaettere(-1); return true
        case 124: k.blaettere(1); return true
        case 53:
            if k.sprungOffen { withAnimation(Kurve.sn(0.18)) { k.sprungOffen = false }; return true }
            if k.entwurf != nil { k.schliesse(); return true }
            return false
        case 51, 117:
            if let o = k.original, o.aenderbar { k.loesche(o); return true }
            return false
        default: break
        }
        switch z {
        case "t": k.heute()
        case "d", "1": k.wechsle(.tag)
        case "w", "2": k.wechsle(.woche)
        case "m", "3": k.wechsle(.monat)
        default: return false
        }
        return true
    }
}

@MainActor
final class SnKalWischen {
    private var monitor: Any?
    private var x: CGFloat = 0, y: CGFloat = 0
    private var ausgeloest = false

    func starte(_ blaettere: @escaping (Int) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, e.momentumPhase == [], e.hasPreciseScrollingDeltas else { return e }
            if e.phase == .began { self.x = 0; self.y = 0; self.ausgeloest = false }
            self.x += e.scrollingDeltaX; self.y += e.scrollingDeltaY
            if !self.ausgeloest, abs(self.x) > 60, abs(self.x) > 2.5 * abs(self.y) {
                self.ausgeloest = true
                blaettere(self.x < 0 ? 1 : -1)
            }
            return e
        }
    }

    func halte() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

extension Color {
    static func kal(_ hex: UInt32?) -> Color { hex.map { Color(hex: $0) } ?? Farbe.himmel }
}

extension View {
    @ViewBuilder func snProbeRahmen(_ name: String) -> some View {
        if Bildprobe.ziel != nil {
            background(GeometryReader { g in Color.clear.onAppear { SnKalenderBild.rahmen[name] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in SnKalenderBild.rahmen[name] = f } })
        } else { self }
    }
}
