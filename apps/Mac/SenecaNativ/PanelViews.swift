import SwiftUI

struct SeiteEin: ViewModifier {
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(da ? 1 : 0).offset(y: da ? 0 : 8)
            .onAppear { withAnimation(Kurve.ease(0.26)) { da = true } }
    }
}

extension View {
    func seiteEin() -> some View { modifier(SeiteEin()) }
}

struct PanelView: View {
    @EnvironmentObject private var ansichten: AnsichtModell

    var body: some View {
        let inhalt = ansichten.panel ?? ansichten.zuletzt
        VStack(spacing: 0) {
            kopf(inhalt)
            Divider().overlay(Farbe.linie2)
            ScrollViewReader { leser in
            ScrollView {
                Group {
                    switch inhalt {
                    case .angeheftet: AngeheftetListe()
                    case .widget(let t, let id):
                        WidgetKarte(quelle: .ansicht(id), titel: t, modus: .panel)
                    case .html(let t, let h):
                        WidgetKarte(quelle: .html(h, streng: false), titel: t, modus: .panel)
                    case .karte(let k, _): KarteAnsicht(karte: k, ort: .panel)
                    case .datei(let pfad, let t): DateiAnsicht(pfad: pfad, titel: t)
                    case .projektKarte(let id, _): ProjektKartePanel(kartenId: id)
                    }
                }
                .padding(18)
                .id(inhalt.kennung)
                .seiteEin()
            }
            #if DEBUG
            .task {
                guard MacPfade.profil == .demo, let n = ProcessInfo.processInfo.environment["SENECA_TEST_PINHOCH"], !n.isEmpty else { return }
                for _ in 0..<4 {
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation(nil) { leser.scrollTo(n, anchor: .top) }
                }
            }
            #endif
            }
        }
        .background(Farbe.grund)
        .onExitCommand { ansichten.schliesse() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seitenfeld")
    }

    private func kopf(_ inhalt: PanelInhalt) -> some View {
        HStack(spacing: 8) {
            if !ansichten.zurueck.isEmpty {
                Button { ansichten.zurueckGehen() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(Farbe.ink2).help("Zurück").accessibilityLabel("Zurück")
            }
            Text(inhalt.titel).font(Schrift.serif(24, kursiv: true)).foregroundStyle(Farbe.ink1).lineLimit(1)
            Spacer(minLength: 0)
            Button { ansichten.schliesse() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain).foregroundStyle(Farbe.ink2).help("Schließen").accessibilityLabel("Seitenfeld schließen")
            .accessibilityIdentifier("panel-zu")
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 12)
    }
}

struct AngeheftetListe: View {
    @EnvironmentObject private var ansichten: AnsichtModell

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if ansichten.pins.isEmpty {
                Text("Noch nichts angeheftet. Karten und Widgets aus dem Chat lassen sich mit „Anheften“ hierher legen.")
                    .font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2).padding(.top, 4)
            }
            ForEach(ansichten.pins) { pin in
                eintrag(pin)
                    .id(pin.name)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await ansichten.ladePins() }
    }

    @ViewBuilder private func eintrag(_ pin: AngeheftetesPin) -> some View {
        let weg: () -> Void = { Task { await ansichten.entferne(name: pin.name) } }
        switch pin.art {
        case .karte:
            if let k = pin.karte { KarteAnsicht(karte: k, ort: .pin, anzeige: pin.anzeige, onEntfernen: weg) }
        case .widget:
            if let h = pin.html { WidgetKarte(quelle: .html(h, streng: pin.anzeige != nil), titel: pin.titel, modus: .pin, anzeige: pin.anzeige, onEntfernen: weg) }
        case .datei:
            if let p = pin.pfad {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").foregroundStyle(Farbe.ink2)
                    Button { ansichten.oeffne(.datei(pfad: p, titel: pin.titel)) } label: {
                        Text(pin.titel).font(Schrift.grotesk(14.5, .medium)).foregroundStyle(Farbe.ink).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button(action: weg) { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(Farbe.ink2).help("Entfernen").accessibilityLabel("Entfernen")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Farbe.papier, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .innenRand(18)
                .karteEin()
                .accessibilityIdentifier("pin-datei")
            }
        }
    }
}

struct DateiAnsicht: View {
    var pfad: String
    var titel: String
    @EnvironmentObject private var ansichten: AnsichtModell
    @State private var inhalt: String?
    @State private var fehler = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let inhalt {
                SenecaTextView(text: inhalt, live: false)
                HStack {
                    Spacer(minLength: 0)
                    PinKnopf(an: ansichten.pins.contains { $0.art == .datei && $0.pfad == pfad }) { await ansichten.heftAn(AngeheftetesPin.setzen(pfad: pfad, titel: titel)) }
                }
            } else if fehler {
                Text("Diese Datei lässt sich gerade nicht öffnen.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2)
            } else {
                SchimmerFlaeche(radius: 12).frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: pfad) {
            if let r = await ansichten.datei(pfad: pfad), let t = r["inhalt"] as? String { inhalt = t } else { fehler = true }
        }
        .accessibilityIdentifier("datei")
    }
}
