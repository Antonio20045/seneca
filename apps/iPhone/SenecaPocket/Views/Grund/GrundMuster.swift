#if DEBUG
import SwiftUI

enum GrundMusterSeite {
    static var ausDemo: String? {
        let env = ProcessInfo.processInfo.environment
        guard env["SENECA_DEMO"] == "1", let p = env["SENECA_DEMO_PAGE"],
              ["grund", "grund-mehr", "grund-schrift", "grund-blatt"].contains(p) else { return nil }
        return p
    }

    @ViewBuilder static func ansicht(_ p: String) -> some View {
        GrundMuster(teil: p == "grund-schrift" ? .schrift : p == "grund-mehr" ? .mehr : .bausteine, blattOffen: p == "grund-blatt")
    }
}

struct GrundMuster: View {
    enum Teil { case bausteine, mehr, schrift }
    @State var teil: Teil
    @State var blattOffen: Bool
    @State private var erledigt: Set<Int> = [1]
    @State private var entwurf = "Kannst du mir bis morgen die Zahlen aus dem Reporting zusammenfassen und dabei auf die Abweichungen achten?"

    var body: some View {
        Seite(titel: "Fundament", zurueck: "Heute") {
            Group {
                switch teil {
                case .bausteine: bausteine
                case .mehr: mehr
                case .schrift: schrift
                }
            }
            .transition(.wechsel)
        }
        .reiter {
            ReiterLeiste(auswahl: $teil, optionen: [.init(.bausteine, "Bausteine"), .init(.mehr, "Mehr"), .init(.schrift, "Schrift", zahl: 9)])
        }
        .rechts { RundKnopf("plus", beschriftung: "Neu") { blattOffen = true } }
        .senecaGrund()
        .senecaBlatt(isPresented: $blattOffen, titel: "Aufgabe") {
            SchreibFeld("Was ist zu tun?", text: .constant("Steuerberater anrufen"), zeilen: 1...3)
            AbschnittKopf("Wann")
            Zeile(titel: "Heute", hinten: .pfeil) {}
            Zeile(titel: "Bis wann", unter: "Freitag, 20. November", hinten: .pfeil) {}
            Zeile(titel: "Bereich", unter: "Sundartha", hinten: .pfeil, linie: false) {}
        } unten: {
            HauptKnopf("Speichern", breit: true) { blattOffen = false }
        }
    }

    private var bausteine: some View {
        VStack(alignment: .leading, spacing: 0) {
            AbschnittKopf("Braucht dich", oben: false)
            Text("Soll Hermes mit Instagram anfangen?")
                .schrift(.sache)
                .foregroundStyle(Stil.tinte.voll)
            Text("Hermes fragt · seit 7:00")
                .schrift(.klein)
                .foregroundStyle(Stil.tinte.zweit)
                .padding(.top, Stil.abstand.xs)
            HStack(spacing: Stil.abstand.s) {
                HauptKnopf("Ja") {}
                ZweitKnopf("Nein") {}
                TextKnopf("Später") {}
                    .padding(.leading, Stil.abstand.s)
            }
            .padding(.top, Stil.abstand.l)
            TextKnopf("Danach noch 2 ›", stufe: .klein) {}

            AbschnittKopf("Heute", zahl: 3, aktion: ("Alle", {}))
            ForEach(0..<3) { i in
                let titel = ["Einmal in Power BI anmelden", "Kleinunternehmerstatus mit dem Steuerberater klären und Unterlagen schicken", "Webhook-Kette prüfen"][i]
                let unter = ["Vodafone · Power-BI-Reportings für alle Services", "Sundartha · bis Freitag", "Vodafone"][i]
                Zeile(vorn: .haken(an: erledigt.contains(i)) {
                                if erledigt.contains(i) { erledigt.remove(i) } else { erledigt.insert(i) }
                            },
                            titel: titel, unter: unter, linie: i < 2) {}
            }

            AbschnittKopf("Kalender")
            Zeile(vorn: .zeit("9:30"), titel: "Wochenstart im Team", unter: "9:30–10:00 · Teams", leise: true)
            Zeile(vorn: .zeit("10:15"), titel: "Abstimmung zum Angebot", unter: "10:15–10:45 · Telefon", betont: true)
            Zeile(vorn: .zeit("12:00"), titel: "Mittag mit Lena", unter: "12:00–13:00", linie: false)
        }
    }

    private var mehr: some View {
        VStack(alignment: .leading, spacing: 0) {
            AbschnittKopf("Mitarbeiter", oben: false)
            Zeile(vorn: .punkt(Stil.farbe.koralle), titel: Namen.mitarbeiter(Hauptagent.id), unter: "Fragt nach deiner Freigabe", hinten: .text("7:12")) {}
            Zeile(vorn: .punkt(Stil.farbe.bernstein), titel: Namen.mitarbeiter("agent:reporting:main"), unter: "Liest die Zahlen vom Montag", hinten: .text("8:40")) {}
            Zeile(titel: Namen.mitarbeiter("power-bi"), unter: "Wettbewerber CALL-E · 3× nichts Neues", hinten: .pfeil, linie: false) {}

            AbschnittKopf("Schreiben")
            SchreibFeld("Frag Seneca etwas", text: $entwurf, senden: {})
                .links { RundKnopf("mic", beschriftung: "Sprechen") {} }
            SchreibFeld("Neue Aufgabe", text: .constant(""), zeilen: 1...1, eingabeSendet: true, senden: {})
                .padding(.top, Stil.abstand.s)
            HauptKnopf("Eintragen", breit: true) {}
                .padding(.top, Stil.abstand.xl)
            HauptKnopf("Eintragen", breit: true) {}
                .disabled(true)
                .padding(.top, Stil.abstand.s)
            AbschnittKopf("Zustände")
            LadeZeile("Seneca schreibt …")
            HinweisZeile("Stand von 7:12, der Mac antwortet gerade nicht.", art: .offline)
            HinweisZeile("Nicht gesendet.", art: .fehler, aktion: ("Nochmal senden", {}))
            LeerSatz("Nichts braucht dich gerade.")

        }
    }

    private var schrift: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.l) {
            let stufen: [(Stil.Schrift, String, String)] = [
                (.gross, "gross · Serif 34", "Jetzt Wochenstart im Team, bis 10:00."),
                (.titel, "titel · Serif 28", "Aufgaben"),
                (.sache, "sache · Serif 22", "Soll Hermes mit Instagram anfangen?"),
                (.text, "text · Grotesk Light 17", "Danach 10:15 Abstimmung zum Angebot. Fließtext und Antworten im Chat stehen in dieser Stufe."),
                (.zeile, "zeile · Grotesk 16", "Einmal in Power BI anmelden"),
                (.zeileWichtig, "zeileWichtig · Grotesk Medium 16", "Abstimmung zum Angebot"),
                (.klein, "klein · Grotesk 13", "Vodafone · seit 7:00"),
                (.etikett, "etikett · Grotesk Medium 12", "Braucht dich"),
                (.zahl, "zahl · Serif 56", "42"),
            ]
            ForEach(Array(stufen.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                    Text(s.1).schrift(.etikett).foregroundStyle(Stil.tinte.leise)
                    Text(s.2).schrift(s.0).foregroundStyle(Stil.tinte.voll)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            AbschnittKopf("Tinte")
            HStack(spacing: Stil.abstand.s) {
                ForEach(Array([Stil.tinte.voll, Stil.tinte.zweit, Stil.tinte.leise, Stil.tinte.flaecheStark, Stil.tinte.flaeche, Stil.tinte.linie].enumerated()), id: \.offset) { _, f in
                    RoundedRectangle(cornerRadius: Stil.radius.klein).fill(f).frame(height: Stil.tippFlaeche)
                }
            }
            HStack(spacing: Stil.abstand.s) {
                ForEach(Array([Stil.farbe.himmel, Stil.farbe.gruen, Stil.farbe.bernstein, Stil.farbe.koralle].enumerated()), id: \.offset) { _, f in
                    RoundedRectangle(cornerRadius: Stil.radius.klein).fill(f).frame(height: Stil.tippFlaeche)
                }
            }
        }
    }
}
#endif
