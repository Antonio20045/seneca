import SwiftUI

struct SnBerichteSeite: View {
    var ergebnisse: [TageslaufSicht.Ergebnis]
    var gelesen = true
    var automationen: [BerichteWeb.Bericht] = []
    var jetzt: Double = Date().timeIntervalSince1970 * 1000
    var oeffne: (BerichteWeb.Bericht) -> Void = { _ in }

    static func satz(_ e: [TageslaufSicht.Ergebnis], gelesen: Bool) -> (String, String) {
        guard gelesen else { return ("Der Tag wird gelesen.", "") }
        let n = e.count, w = e.filter(\.wartetAufAbnahme).count
        if n == 0 { return ("Heute hat noch kein Mitarbeiter etwas abgegeben.", "") }
        let erst = n == 1 ? "Heute hat ein Mitarbeiter ein Ergebnis abgegeben." : "Heute haben deine Mitarbeiter \(ArbeitsplanText.zahl(n)) Ergebnisse abgegeben."
        let zweit = w == 0 ? "" : (w == 1 ? (n == 1 ? "Es wartet auf deine Abnahme." : "Eines wartet auf deine Abnahme.")
                                         : (w == n ? "Alle warten auf deine Abnahme." : "\(ArbeitsplanText.zahl(w).prefix(1).uppercased() + ArbeitsplanText.zahl(w).dropFirst()) warten auf deine Abnahme."))
        return (erst, zweit)
    }

    var body: some View {
        GeometryReader { g in
            let rand = min(120, max(40, (g.size.width - 1000) * 0.2727))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    let s = Self.satz(ergebnisse, gelesen: gelesen)
                    (Text(s.0 + (s.1.isEmpty ? "" : " ")).font(Schrift.serif(44)).foregroundStyle(Color.white)
                        + Text(s.1).font(Schrift.serif(44, kursiv: true)).foregroundStyle(Farbe.bernstein))
                        .lineHeight(.exact(points: 50))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 900, alignment: .leading)
                        .snMaske()
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(ergebnisse.enumerated()), id: \.element.id) { i, e in
                            zeile(e).snRein(min(0.5, 0.1 + Double(i) * 0.05))
                        }
                    }
                    .padding(.top, 44)
                    if !automationen.isEmpty {
                        Text("Aus den Automationen").font(Schrift.grotesk(14, .medium)).tracking(0.3).foregroundStyle(Farbe.ink3)
                            .padding(.top, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(Farbe.linie).frame(height: 1) }
                            .padding(.top, 48)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 8) {
                            ForEach(automationen) { b in BerichtZeile(bericht: b, jetzt: jetzt) { oeffne(b) } }
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, rand).padding(.top, 96).padding(.bottom, 150)
                .frame(width: g.size.width, alignment: .leading)
            }
            .scrollClipDisabled()
            .snSeitenBlende()
        }
        .accessibilityIdentifier("seite-berichte")
    }

    private func zeile(_ e: TageslaufSicht.Ergebnis) -> some View {
        let zwischen = e.runde > 0 && !e.wartetAufAbnahme ? "Zwischenstand nach Runde \(e.runde), die Arbeit läuft weiter" : nil
        let stand = [e.wer, e.geprueft ? "vom Prüfer geprüft" : nil, e.wartetAufAbnahme ? "wartet auf deine Abnahme" : nil, zwischen].compactMap { $0 }.filter { !$0.isEmpty }
        return HStack(alignment: .top, spacing: 20) {
            Text(e.zeit).font(Schrift.mono(13)).tracking(0.2).foregroundStyle(Farbe.ink3)
                .frame(width: 52, height: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(e.titel).font(Schrift.grotesk(17)).lineHeight(.exact(points: 24)).foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(e.titel == e.wortlaut ? "" : "Wortlaut der Karte: " + e.wortlaut)
                if !e.ergebnis.isEmpty {
                    Text(Arbeitsplan.ganzeSaetze(Menschlich.ohnePfade(Menschlich.klartext(e.ergebnis)), max: 320))
                        .font(Schrift.grotesk(14)).lineHeight(.exact(points: 21)).foregroundStyle(Farbe.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !stand.isEmpty {
                    Text(stand.joined(separator: " · ")).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19))
                        .foregroundStyle(e.wartetAufAbnahme ? Farbe.bernstein : Farbe.ink3)
                }
                SnBelege(belege: e.belege)
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }
}

struct SnBerichteEcht: View {
    @ObservedObject var modell: AppModell
    @ObservedObject private var uebersicht: OverviewStore
    @ObservedObject private var tageslauf = TageslaufModell.gemeinsam

    init(modell: AppModell) {
        self.modell = modell
        _uebersicht = ObservedObject(wrappedValue: modell.uebersicht)
    }

    var body: some View {
        let d = uebersicht.daten
        let sicht = tageslauf.tag.map { TageslaufSicht($0, name: { d.mitarbeiterName($0) ?? Arbeitsplan.agentName($0, d) }) }
        SnBerichteSeite(ergebnisse: sicht?.ergebnisse ?? [], gelesen: tageslauf.tag != nil || tageslauf.einmalGelesen,
                        automationen: uebersicht.berichte.liste, jetzt: uebersicht.jetzt, oeffne: { modell.gehe(Route(.berichte, id: $0.id)) })
            .task { await tageslauf.beobachte() }
            .task { await uebersicht.ladeBerichte() }
    }
}
