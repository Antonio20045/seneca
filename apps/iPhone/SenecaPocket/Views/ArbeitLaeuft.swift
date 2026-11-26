import SwiftUI

struct ArbeitLaeuft: View {
    let liste: ArbeitsListe
    let jetzt: Date

    @EnvironmentObject private var store: SenecaStore
    @ObservedObject private var modell = ListenModell.gemeinsam
    @Environment(\.wege) private var wege
    @Environment(\.dismiss) private var schliessen
    @State private var offen: String?

    var body: some View {
        let haengt = ArbeitWorte.haengt(liste)
        let laeuft = ArbeitWorte.laeuft(liste)
        let haengend = Set(haengt.map(\.id))
        let wartet = liste.schlange.filter { !haengend.contains($0.id) }
        let fertig = liste.fertig.filter { !modell.gelesen.contains($0.gelesenKennung) }

        VStack(alignment: .leading, spacing: 0) {
            if haengt.isEmpty && laeuft.isEmpty && wartet.isEmpty && fertig.isEmpty {
                LeerSatz("Gerade läuft nichts.")
                    .accessibilityIdentifier("laeuft.leer")
            }
            if !haengt.isEmpty {
                AbschnittKopf("Hängt", zahl: haengt.count, oben: false)
                ForEach(Array(haengt.enumerated()), id: \.element.id) { i, z in
                    zeile(z, farbe: Stil.farbe.koralle, unter: [z.haltGrund.isEmpty ? "hängt" : z.haltGrund, ArbeitWorte.wer(z)],
                          seit: ArbeitWorte.seit(z), letzte: i == haengt.count - 1)
                        .accessibilityIdentifier("laeuft.haengt")
                }
            }
            if !laeuft.isEmpty {
                AbschnittKopf("Läuft", zahl: laeuft.count, oben: !haengt.isEmpty)
                ForEach(Array(laeuft.enumerated()), id: \.element.id) { i, z in
                    zeile(z, farbe: Stil.farbe.himmel,
                          unter: [ArbeitWorte.wer(z), z.art == "auftrag" ? "läuft dauerhaft" : "",
                                  z.projekt == nil ? "" : z.projektName, z.frist.map { ArbeitWorte.frist($0, jetzt) } ?? ""],
                          seit: ArbeitWorte.seit(z), betont: ArbeitWorte.dringend(z.frist, jetzt), letzte: i == laeuft.count - 1)
                        .accessibilityIdentifier("laeuft.zeile")
                }
            }
            if !wartet.isEmpty {
                AbschnittKopf("Wartet auf Start", zahl: wartet.count, oben: !(haengt.isEmpty && laeuft.isEmpty))
                ForEach(Array(wartet.enumerated()), id: \.element.id) { i, z in
                    zeile(z, farbe: Stil.tinte.leise,
                          unter: [ArbeitWorte.wer(z), z.projekt == nil ? "" : z.projektName, z.frist.map { ArbeitWorte.frist($0, jetzt) } ?? ""],
                          seit: nil, betont: ArbeitWorte.dringend(z.frist, jetzt), leise: true, letzte: i == wartet.count - 1)
                }
            }
            if !fertig.isEmpty {
                AbschnittKopf("Fertig", zahl: fertig.count, aktion: ("Alle gelesen", { gelesen(fertig) }),
                              oben: !(haengt.isEmpty && laeuft.isEmpty && wartet.isEmpty))
                ForEach(Array(fertig.enumerated()), id: \.element.id) { i, z in
                    zeile(z, farbe: Stil.farbe.gruen, unter: [ArbeitWorte.wer(z), z.projekt == nil ? "" : z.projektName],
                          seit: z.fertigUm ?? z.seit, ohneSeit: true, letzte: i == fertig.count - 1)
                        .contextMenu {
                            Button { gelesen([z]) } label: { Label("Gelesen", systemImage: "checkmark") }
                        }
                        .accessibilityIdentifier("laeuft.fertig")
                }
            }
        }
        .bewegt(.wechsel, wert: offen)
        .bewegt(.wechsel, wert: fertig.map(\.id))
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["SENECA_DEMO_ARBEIT_OFFEN"] == "erste" { offen = ArbeitWorte.laeuft(liste).first?.id } }
        #endif
        .accessibilityIdentifier("laeuft")
    }

    private func zeile(_ z: ListenZeile, farbe: Color, unter: [String], seit: Date?, ohneSeit: Bool = false,
                       betont: Bool = false, leise: Bool = false, letzte: Bool) -> some View {
        let an = offen == z.id
        let hinten: Zeile.Hinten = seit.map { .text((ohneSeit ? "" : "seit ") + ArbeitWorte.uhr($0, jetzt)) } ?? .keins
        return VStack(alignment: .leading, spacing: 0) {
            Zeile(vorn: .punkt(farbe), titel: z.titel, unter: unter.filter { !$0.isEmpty }.joined(separator: " · "),
                  hinten: hinten, betont: betont, leise: leise, linie: !an && !letzte) {
                Haptik.auswahl()
                Bewegung.mit(.wechsel) { offen = an ? nil : z.id }
            }
            .accessibilityHint(an ? "Blendet die Einzelheiten aus" : "Zeigt die Einzelheiten")
            if an {
                einzelheiten(z)
                    .padding(.leading, ArbeitMass.einzug)
                    .padding(.bottom, Stil.abstand.m)
                    .transition(.wechsel)
                if !letzte { ArbeitLinie() }
            }
        }
    }

    private func einzelheiten(_ z: ListenZeile) -> some View {
        let weg = ArbeitWorte.weg(z, jetzt)
        let name = ArbeitWorte.wer(z)
        return VStack(alignment: .leading, spacing: Stil.abstand.xs) {
            if !weg.isEmpty {
                Text(weg.prefix(1).uppercased() + weg.dropFirst())
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.zweit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let f = z.frist, z.zustand != "fertig" {
                Text(ArbeitWorte.frist(f, jetzt).prefix(1).uppercased() + ArbeitWorte.frist(f, jetzt).dropFirst())
                    .schrift(.klein)
                    .foregroundStyle(ArbeitWorte.dringend(f, jetzt) ? Stil.farbe.koralle : Stil.tinte.zweit)
            }
            HStack(spacing: Stil.abstand.xl) {
                TextKnopf("Mit \(name) schreiben ›", stufe: .klein) { chat(ArbeitWorte.kennung(z)) }
                if z.zustand == "fertig", !z.gelesenKennung.isEmpty {
                    TextKnopf("Gelesen", stufe: .klein) { gelesen([z]) }
                        .accessibilityIdentifier("laeuft.gelesen")
                }
            }
        }
    }

    private func gelesen(_ zeilen: [ListenZeile]) {
        Haptik.erledigt()
        Bewegung.mit(.wechsel) {
            for z in zeilen { modell.markiereGelesen(z.gelesenKennung, store: store) }
            if zeilen.contains(where: { $0.id == offen }) { offen = nil }
        }
    }

    private func chat(_ kennung: String) {
        let id = Namen.reineKennung(kennung)
        schliessen()
        wege.oeffne(.chat(mitarbeiter: id.isEmpty || id == "main" ? nil : id))
    }
}
