import SwiftUI
import CoreLocation

struct SinneView: View {
    var zurueck: String? = "Einstellungen"
    var beimZurueck: (() -> Void)?

    var body: some View {
        Seite(titel: "Orte und Erlaubnisse", zurueck: zurueck, beimZurueck: beimZurueck) {
            SinneInhalt()
        }
        .senecaGrund()
    }
}

@MainActor
struct SinneInhalt: View {
    @ObservedObject private var sinne = Sinne.shared
    @Environment(\.openURL) private var openURL
    @State private var orte: [SinnOrt] = []
    @State private var hinweis: String?
    @State private var speichert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Seneca merkt von selbst, wenn du an einem deiner Orte ankommst oder gehst, liest deine Termine und Trainings und meldet sich einmal am Tag. Alles geht nur an deinen Mac.")
                .schrift(.text)
                .foregroundStyle(Stil.tinte.zweit)
                .fixedSize(horizontal: false, vertical: true)

            AbschnittKopf("Erlaubnisse")
            VStack(spacing: 0) {
                standortZeile
                Zeile(titel: "Kalender", unter: "Seneca liest die Termine aller Kalender auf diesem iPhone.",
                      hinten: .text(sinne.kalenderErlaubt ? "erlaubt" : "Erlauben"),
                      aktion: sinne.kalenderErlaubt ? nil : { Task { await sinne.kalenderFragen() } })
                Zeile(titel: "Mitteilungen", unter: "Seneca meldet sich, wenn du nach Hause kommst.",
                      hinten: .text(sinne.mitteilungenErlaubt ? "erlaubt" : "Erlauben"),
                      linie: false,
                      aktion: sinne.mitteilungenErlaubt ? nil : { Task { await sinne.mitteilungenFragen() } })
            }

            AbschnittKopf("Kommt es an?")
            Text(SinneBericht.saetze(sinne.lage, jetzt: Date()).joined(separator: " "))
                .schrift(.text)
                .foregroundStyle(Stil.tinte.zweit)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sinne.zustand")
            if sinne.wartend > 0 {
                TextKnopf("Jetzt noch einmal senden", stufe: .klein) { Task { await sinne.nachliefern() } }
            }

            AbschnittKopf("Orte")
            VStack(alignment: .leading, spacing: Stil.abstand.m) {
                ForEach($orte) { $ort in
                    VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                        SchreibFeld("Name", text: $ort.name, zeilen: 1...1)
                        SchreibFeld("Straße, Hausnummer, Ort", text: $ort.adresse, zeilen: 1...2)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }
            }
            Text("Jeder Ort ist ein Kreis von 150 Metern um die Adresse." + (hausnummerFehlt ? " Für Köln fehlt noch die Hausnummer; erst mit ihr liegt der Kreis um deine Wohnung." : ""))
                .schrift(.klein)
                .foregroundStyle(Stil.tinte.leise)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Stil.abstand.m)
            if let hinweis { HinweisZeile(hinweis, art: .info).padding(.top, Stil.abstand.s) }
            if speichert {
                LadeZeile("Suche die Adressen …").padding(.top, Stil.abstand.s)
            } else {
                HauptKnopf("Orte speichern", breit: true) { Task { await speichern() } }
                    .disabled(orte == sinne.orte)
                    .padding(.top, Stil.abstand.l)
            }
        }
        .onAppear {
            orte = sinne.orte
            sinne.rechteLesen()
        }
    }

    private var hausnummerFehlt: Bool { sinne.orte.contains { $0.id == "koeln" && $0.adresse == SinnOrt.standard[2].adresse } }

    @ViewBuilder private var standortZeile: some View {
        switch sinne.ortsRecht {
        case .notDetermined:
            Zeile(titel: "Standort", unter: "Fehlt noch. Damit merkt Seneca, wenn du an einem deiner Orte ankommst oder gehst.",
                  hinten: .text("Erlauben")) { sinne.standortFragen() }
        case .authorizedWhenInUse where !sinne.immerSchonGefragt:
            Zeile(titel: "Standort", unter: "Nur bei offener App. Im zweiten Schritt fragt iOS nach „Immer“.",
                  hinten: .text("Erlauben")) { sinne.standortFragen() }
        case .authorizedWhenInUse:
            Zeile(titel: "Standort", unter: "Nur bei offener App. Stelle ihn in den iOS-Einstellungen auf „Immer“, damit Seneca dich auch bei geschlossener App bemerkt.",
                  hinten: .text("Öffnen")) { iosEinstellungen() }
        case .authorizedAlways:
            Zeile(titel: "Standort", unter: "Immer, auch bei geschlossener App.", hinten: .text("erlaubt"))
        default:
            Zeile(titel: "Standort", unter: "Ausgeschaltet. Ohne ihn bemerkt Seneca nicht, wo du bist.",
                  hinten: .text("Öffnen")) { iosEinstellungen() }
        }
    }

    private func iosEinstellungen() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func speichern() async {
        speichert = true
        defer { speichert = false }
        let fehlt = await sinne.orteSpeichern(orte)
        orte = sinne.orte
        hinweis = fehlt.isEmpty ? nil : "Die neue Adresse für \(fehlt.joined(separator: " und ")) habe ich nicht gefunden. Dort gilt weiter die alte."
    }
}
