import SwiftUI

@MainActor
struct EinstellungenSeite: View {
    var zurueckName: String
    var schliessen: () -> Void
    var uhrVerbinden: () -> Void

    @EnvironmentObject private var store: SenecaStore
    @ObservedObject private var sinne = Sinne.shared
    @AppStorage("gatewayURL") private var gespeicherteAdresse = ""
    @AppStorage("sitzung") private var gespeichertesGespraech = Hauptagent.sitzung

    private enum Unterseite { case orte }
    @State private var unterseite: Unterseite?
    @State private var bearbeitet = false
    @State private var adresse = ""
    @State private var schluessel = ""
    @State private var fehler: String?
    @State private var verbindet = false
    @State private var technik = false
    @State private var gespraechAendern = false
    @State private var gespraech = ""

    var body: some View {
        ZStack {
            hauptseite
            if unterseite == .orte {
                SinneView(beimZurueck: { Bewegung.mit(.seite) { unterseite = nil } })
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .senecaGrund()
        .wischZurueck(ebene: {
            guard unterseite != nil else { return false }
            Bewegung.mit(.seite) { unterseite = nil }
            return true
        }) { schliessen() }
        .accessibilityIdentifier("einstellungen")
    }

    private var hauptseite: some View {
        Seite(titel: "Einstellungen", zurueck: zurueckName) {
            AbschnittKopf("Verbindung", oben: false)
            verbindung
            AbschnittKopf("Dein iPhone")
            Zeile(titel: "Orte und Erlaubnisse", unter: erlaubnisSatz, hinten: .pfeil, linie: false) {
                Bewegung.mit(.seite) { unterseite = .orte }
            }
            .accessibilityIdentifier("einstellungen.orte")
            Zeile(titel: "Uhr verbinden", hinten: .pfeil, linie: false) { uhrVerbinden() }
            technikTeil
        }
        .onAppear {
            adresse = gespeicherteAdresse
            gespraech = gespeichertesGespraech
            bearbeitet = gespeicherteAdresse.isEmpty && !store.demo
            sinne.rechteLesen()
        }
    }

    private var stand: (text: String, farbe: Color) {
        if store.demo || store.isConnected { return ("Verbunden mit deinem Mac", Stil.farbe.gruen) }
        if !store.isConfigured { return ("Noch nicht mit deinem Mac verbunden", Stil.farbe.bernstein) }
        if let zuletzt = store.lastSync {
            return ("Mac antwortet nicht seit \(zuletzt.formatted(date: .omitted, time: .shortened))", Stil.farbe.bernstein)
        }
        return ("Mac antwortet nicht", Stil.farbe.bernstein)
    }

    private var adresseKurz: String? {
        guard !gespeicherteAdresse.isEmpty else { return nil }
        return URL(string: gespeicherteAdresse)?.host ?? gespeicherteAdresse
    }

    @ViewBuilder private var verbindung: some View {
        Zeile(vorn: .punkt(stand.farbe), titel: stand.text, unter: adresseKurz, linie: false)
            .accessibilityIdentifier("einstellungen.stand")
        if bearbeitet {
            VStack(alignment: .leading, spacing: Stil.abstand.s) {
                SchreibFeld("Adresse deines Macs", text: $adresse, zeilen: 1...1)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("einstellungen.adresse")
                SchreibFeld(gespeicherteAdresse.isEmpty ? "Schlüssel" : "Schlüssel (leer lassen: der bisherige)",
                            text: $schluessel, zeilen: 1...1, geheim: true)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("einstellungen.schluessel")
                Text("Die Adresse beginnt mit https:// und endet auf ts.net. Der Mac selbst ist von hier aus nur über sie erreichbar.")
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.leise)
                    .fixedSize(horizontal: false, vertical: true)
                if let meldung = fehler ?? store.error, !meldung.isEmpty {
                    HinweisZeile(meldung, art: .fehler)
                }
                if verbindet {
                    LadeZeile("Verbinde …")
                } else {
                    HStack(spacing: Stil.abstand.s) {
                        HauptKnopf("Verbinden") { Task { await verbinden() } }
                            .disabled(adresse.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("einstellungen.verbinden")
                        if !gespeicherteAdresse.isEmpty {
                            TextKnopf("Abbrechen") { Bewegung.mit(.klein) { bearbeitet = false; fehler = nil; schluessel = ""; adresse = gespeicherteAdresse } }
                        }
                    }
                }
            }
            .padding(.top, Stil.abstand.s)
            .transition(.wechsel)
        } else {
            TextKnopf("Adresse ändern") { Bewegung.mit(.klein) { bearbeitet = true } }
                .accessibilityIdentifier("einstellungen.aendern")
        }
    }

    private func verbinden() async {
        verbindet = true
        defer { verbindet = false }
        let sauber = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: sauber), let host = url.host, !host.isEmpty,
              ["https", "wss", "http", "ws"].contains(url.scheme ?? "") else {
            fehler = "Bitte eine gültige Adresse eintragen, zum Beispiel https://dein-mac.…ts.net."
            return
        }
        if host == "127.0.0.1" || host == "localhost" {
            fehler = "Diese Adresse erreicht deinen Mac vom iPhone aus nicht. Nimm die private Adresse mit ts.net."
            return
        }
        let neuerSchluessel = schluessel.trimmingCharacters(in: .whitespacesAndNewlines)
        let verwendet = neuerSchluessel.isEmpty ? CredentialStore.load() : neuerSchluessel
        do { try CredentialStore.save(verwendet) } catch { fehler = error.localizedDescription; return }
        fehler = nil
        gespeicherteAdresse = sauber
        let gespraechsSchluessel = gespraech.trimmingCharacters(in: .whitespacesAndNewlines)
        gespeichertesGespraech = gespraechsSchluessel.isEmpty ? Hauptagent.sitzung : gespraechsSchluessel
        store.configure(url: sauber, token: verwendet, sessionKey: gespeichertesGespraech)
        await store.connect()
        if store.isConnected || store.demo {
            Bewegung.mit(.klein) { bearbeitet = false }
            schluessel = ""
        } else {
            fehler = store.error ?? "Der Mac antwortet nicht. Stimmen Adresse und Schlüssel?"
        }
    }

    private var erlaubnisSatz: String {
        let lage = sinne.lage
        var fehlt: [String] = []
        if lage.standort != .immer { fehlt.append("Standort") }
        if !lage.kalender { fehlt.append("Kalender") }
        if !lage.mitteilungen { fehlt.append("Mitteilungen") }
        if fehlt.isEmpty { return "Alles erlaubt" }
        return "Es fehlt: " + fehlt.joined(separator: ", ")
    }

    @ViewBuilder private var technikTeil: some View {
        TextKnopf(technik ? "Technik ⌃" : "Technik ›", stufe: .klein) { Bewegung.mit(.blatt) { technik.toggle() } }
            .padding(.top, Stil.abstand.xl)
            .accessibilityIdentifier("einstellungen.technik")
        if technik {
            VStack(alignment: .leading, spacing: Stil.abstand.m) {
                Text("Nur für den Notfall. Normalerweise brauchst du hier nichts zu ändern.")
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.leise)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Gespräch").schrift(.zeileWichtig).foregroundStyle(Stil.tinte.voll)
                Text("Läuft mit \(Namen.mitarbeiter(gespeichertesGespraech)), wie das Hauptgespräch auf deinem Mac.")
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.zweit)
                    .fixedSize(horizontal: false, vertical: true)
                if gespraechAendern {
                    SchreibFeld("Kennung des Gesprächs", text: $gespraech, zeilen: 1...1)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Wird mit „Verbinden“ oben übernommen.").schrift(.klein).foregroundStyle(Stil.tinte.leise)
                } else {
                    TextKnopf("Anderes Gespräch", stufe: .klein) { gespraechAendern = true; bearbeitet = true }
                }
            }
            .transition(.wechsel)
        }
    }
}
