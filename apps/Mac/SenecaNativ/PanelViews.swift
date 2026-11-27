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
            ScrollView {
                Group {
                    switch inhalt {
                    case .widget(let t, let id):
                        WidgetKarte(quelle: .ansicht(id), titel: t, modus: .panel)
                    case .html(let t, let h):
                        WidgetKarte(quelle: .html(h, streng: false), titel: t, modus: .panel)
                    case .karte(let k, _): KarteAnsicht(karte: k, ort: .panel)
                    case .datei(let pfad, let t): DateiAnsicht(pfad: pfad, titel: t)
                    }
                }
                .padding(18)
                .id(inhalt.kennung)
                .seiteEin()
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
            } else if fehler {
                Text("Diese Datei lässt sich gerade nicht öffnen.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2)
            } else {
                SchimmerFlaeche(radius: 12).frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: pfad) {
            if let t = await ansichten.datei(pfad: pfad) { inhalt = t } else { fehler = true }
        }
        .accessibilityIdentifier("datei")
    }
}
