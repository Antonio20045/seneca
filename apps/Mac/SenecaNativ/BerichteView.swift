import SwiftUI

struct BerichteView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var rand: CGFloat

    init(modell: AppModell, rand: CGFloat) {
        self.modell = modell
        self.store = modell.uebersicht
        self.rand = rand
    }

    var body: some View {
        let stand = store.berichte
        Group {
            if let id = modell.route.id, !id.isEmpty {
                BerichtOffen(modell: modell, store: store, stand: stand, id: id, rand: rand)
            } else {
                liste(stand)
            }
        }
        .task { await store.ladeBerichte() }
        .accessibilityIdentifier("seite-berichte")
    }

    private func liste(_ stand: BerichteWeb.Stand) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(BerichteWeb.ueberschrift(stand)).font(Schrift.serif(30)).foregroundStyle(Farbe.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("berichte-kopf")
                    Spacer(minLength: 8)
                    if stand.ungelesen > 0 {
                        Button("Alle als gelesen markieren") {
                            Task { await store.markiere(stand.liste.filter(\.neu).map(\.schluessel)) }
                        }
                        .buttonStyle(KartenKnopfStil(leise: true))
                        .accessibilityIdentifier("berichte-alle-gelesen")
                    }
                }
                if stand.liste.isEmpty && stand.fertig {
                    Text("Sobald eine Automation etwas für dich zusammenfasst, liegt es hier.")
                        .font(Schrift.serif(20, kursiv: true)).foregroundStyle(Farbe.ink2).padding(.top, 14)
                        .accessibilityIdentifier("berichte-leer")
                }
                VStack(spacing: 8) {
                    ForEach(Array(stand.liste.enumerated()), id: \.element.id) { i, b in
                        BerichtZeile(bericht: b, jetzt: store.jetzt) { modell.gehe(Route(.berichte, id: b.id)) }
                            .steigen(i, start: 0.05, takt: 0.04, dauer: 0.45)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, rand).padding(.top, 30).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BerichtZeile: View {
    var bericht: BerichteWeb.Bericht
    var jetzt: Double
    var tu: () -> Void
    @State private var darueber = false

    var body: some View {
        Button(action: tu) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(bericht.neu ? Farbe.himmel : Color.clear).frame(width: 8, height: 8).padding(.top, 7)
                    .animation(Kurve.ease(), value: bericht.neu)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(bericht.von) · \(bericht.name)").font(Schrift.grotesk(15, bericht.neu ? .medium : .regular)).foregroundStyle(Farbe.ink1).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(Menschlich.tagText(bericht.zeit, jetzt: jetzt)), \(Menschlich.hhmm(bericht.zeit))").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                    }
                    Text(bericht.satz).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12).padding(.horizontal, 16)
            .background(darueber ? Farbe.flaeche2 : Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(bericht.neu ? Farbe.himmel.opacity(0.25) : Farbe.linie2, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(Kurve.ease(), value: darueber)
        }
        .buttonStyle(.plain)
        .onHover { darueber = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bericht-\(bericht.id)")
    }
}

private struct BerichtOffen: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var stand: BerichteWeb.Stand
    var id: String
    var rand: CGFloat

    var body: some View {
        let b = BerichteWeb.finde(id, in: stand)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { modell.gehe(.berichte) } label: { Text("← Berichte") }
                    .buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                    .accessibilityIdentifier("bericht-zurueck")
                if let b {
                    Text("\(b.von) · \(b.name) · \(Menschlich.tagText(b.zeit, jetzt: store.jetzt)), \(Menschlich.hhmm(b.zeit))")
                        .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                        .accessibilityIdentifier("bericht-kopf")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(teile(b.text).enumerated()), id: \.offset) { i, teil in
                            switch teil {
                            case .text(let t): SenecaTextView(text: t, live: false).padding(.vertical, 4)
                            case .karte(let k): KarteAnsicht(karte: k, ort: .pin).padding(.vertical, 8).steigen(i)
                            case .baut: EmptyView()
                            }
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .accessibilityIdentifier("bericht-text")
                    BewertungsZeile(kartenId: b.schluessel)
                    Button("Im Gespräch öffnen") { modell.oeffneChat(key: b.chatKey, agentId: b.agentId) }
                        .buttonStyle(KartenKnopfStil(leise: true))
                        .accessibilityIdentifier("bericht-im-gespraech")
                } else {
                    Text(stand.fertig ? "Diesen Bericht gibt es nicht mehr oder er ist älter als 30 Tage." : "Lädt …")
                        .font(Schrift.serif(20, kursiv: true)).foregroundStyle(Farbe.ink2)
                        .accessibilityIdentifier("bericht-fehlt")
                }
            }
            .padding(.horizontal, rand).padding(.top, 30).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: b?.schluessel) {
            if let b, b.neu { await store.markiere([b.schluessel]) }
        }
        .seiteEin()
    }
}
