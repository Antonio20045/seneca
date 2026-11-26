import SwiftUI

struct AufgabeBlatt: View {
    var aufgabeId: String
    var jetzt: Date
    var abhaken: () -> Void
    var geloescht: (TodoUndo) -> Void

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var schliessen
    @Environment(\.calendar) private var cal

    @State private var titel = ""
    @State private var tag: NeueAufgabeLogik.TagWahl = .ohne
    @State private var datum = Date()
    @State private var frist: FristWahl = .keine
    @State private var fristDatum = Date()
    @State private var wichtig = false
    @State private var bereit = false
    @State private var fehler: String?
    @FocusState private var titelFokus: Bool

    private var aufgabe: SenecaTask? { store.aufgaben.first { $0.id == aufgabeId } }
    private var start: Date { cal.startOfDay(for: jetzt) }
    private var heute: String { DayLogic.dayKey(start, cal) }
    private var morgen: String { DayLogic.dayKey(cal.date(byAdding: .day, value: 1, to: start) ?? start, cal) }

    var body: some View {
        if let a = aufgabe {
            inhalt(a)
        } else {
            LeerSatz("Diese Aufgabe gibt es nicht mehr.")
        }
    }

    private func inhalt(_ a: SenecaTask) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Stil.abstand.m) {
                Button {
                    titelSichern()
                    abhaken()
                    schliessen()
                } label: {
                    HakenKreis(an: a.isDone, groesse: 26).tippFlaeche()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a.isDone ? "Erledigt, zurücknehmen" : "Erledigt")
                .accessibilityIdentifier("aufgabe.blatt.haken")
                SchreibFeld("Titel", text: $titel, zeilen: 1...4)
                    .focused($titelFokus)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("aufgabe.blatt.titel")
            }
            if let ort = ortZeile(a) {
                Text(ort)
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.zweit)
                    .padding(.leading, Stil.tippFlaeche + Stil.abstand.m)
                    .padding(.top, Stil.abstand.s)
            }
            if let fehler {
                HinweisZeile(fehler, art: .offline)
            }

            AbschnittKopf("Wann")
            ChipFluss {
                WahlChip("Heute", an: tag == .heute) { setzeTag(.heute) }
                WahlChip("Morgen", an: tag == .morgen) { setzeTag(.morgen) }
                WahlChip(tag == .datum ? DatumWort.kurz(datum, jetzt: jetzt, cal) : "Datum …", an: tag == .datum) { setzeTag(.datum) }
                WahlChip("Ohne Tag", an: tag == .ohne) { setzeTag(.ohne) }
            }
            if tag == .datum { DatumWahl(titel: "Tag", datum: $datum, ab: start) }

            AbschnittKopf("Bis wann")
            ChipFluss {
                WahlChip("Keine Frist", an: frist == .keine) { setzeFrist(.keine) }
                WahlChip("Heute", an: frist == .heute) { setzeFrist(.heute) }
                WahlChip("Ende der Woche", an: frist == .wochenEnde) { setzeFrist(.wochenEnde) }
                WahlChip(frist == .datum ? DatumWort.kurz(fristDatum, jetzt: jetzt, cal) : "Datum …", an: frist == .datum) { setzeFrist(.datum) }
            }
            if frist == .datum { DatumWahl(titel: "Frist", datum: $fristDatum, ab: start) }

            AbschnittKopf("Wichtig")
            Toggle(isOn: $wichtig) {
                Text(wichtig ? "Ja, steht oben" : "Nein").schrift(.zeile).foregroundStyle(Stil.tinte.voll)
            }
            .tint(Stil.farbe.himmel)
            .frame(minHeight: Stil.tippFlaeche)
            .accessibilityIdentifier("aufgabe.blatt.wichtig")

            Button(role: .destructive) {
                titelFokus = false
                if let undo = store.archiveTask(aufgabeId) {
                    Haptik.tipp()
                    geloescht(undo)
                }
                schliessen()
            } label: {
                HStack(spacing: Stil.abstand.s) {
                    Image(systemName: "trash").font(Stil.symbol(.klein))
                    Text("Aufgabe löschen").schrift(.zeile)
                }
                .foregroundStyle(Stil.farbe.koralle)
                .tippFlaeche()
            }
            .buttonStyle(.plain)
            .padding(.top, Stil.abstand.xxl)
            .accessibilityIdentifier("aufgabe.blatt.loeschen")
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
        .onAppear { uebernehmen(a) }
        .onDisappear { titelSichern() }
        .onChange(of: titelFokus) { _, an in if !an { titelSichern() } }
        .onChange(of: datum) { _, d in
            guard bereit, tag == .datum else { return }
            senden(.plan(DayLogic.dayKey(d, cal)))
        }
        .onChange(of: fristDatum) { _, d in
            guard bereit, frist == .datum else { return }
            senden(.frist(DayLogic.dayKey(d, cal)))
        }
        .onChange(of: wichtig) { _, an in
            guard bereit else { return }
            let vorher = aufgabe?.priority
            senden(.prioritaet(an ? (vorher == "urgent" ? "urgent" : "high") : "normal"))
        }
    }

    private func ortZeile(_ a: SenecaTask) -> String? {
        let teile = AufgabenLogic.ortTeile(bereich: a.bereichName, projekt: a.projektName)
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    private func uebernehmen(_ a: SenecaTask) {
        titel = AufgabenLogic.anzeigeTitel(a.title)
        switch a.plan {
        case nil: tag = .ohne
        case heute?: tag = .heute
        case morgen?: tag = .morgen
        case let p?:
            tag = .datum
            datum = AufgabenLogic.datum(p, cal) ?? start
        }
        let wochenEnde = FristWahl.wochenEnde.tag(datum: start, jetzt: jetzt, cal)
        switch a.frist {
        case nil: frist = .keine
        case heute?: frist = .heute
        case let f? where f == wochenEnde: frist = .wochenEnde
        case let f?:
            frist = .datum
            fristDatum = AufgabenLogic.datum(f, cal) ?? start
        }
        if a.plan == nil || tag != .datum { datum = cal.date(byAdding: .day, value: 2, to: start) ?? start }
        if frist != .datum { fristDatum = cal.date(byAdding: .day, value: 7, to: start) ?? start }
        wichtig = AufgabenLogic.gewicht(a) == .wichtig
        DispatchQueue.main.async { bereit = true }
    }

    private func setzeTag(_ neu: NeueAufgabeLogik.TagWahl) {
        tag = neu
        senden(.plan(NeueAufgabeLogik.plan(neu, datum: datum, jetzt: jetzt, cal)))
    }

    private func setzeFrist(_ neu: FristWahl) {
        frist = neu
        senden(.frist(neu.tag(datum: fristDatum, jetzt: jetzt, cal)))
    }

    private func titelSichern() {
        let neu = titel.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = aufgabe, !neu.isEmpty, neu != AufgabenLogic.anzeigeTitel(a.title) else { return }
        store.renameTask(aufgabeId, to: neu)
    }

    private func senden(_ aenderung: AufgabenAenderung) {
        fehler = nil
        Task { @MainActor in
            do {
                try await store.aendereAufgabe(aufgabeId, aenderung)
            } catch {
                fehler = "Am Mac noch nicht gespeichert. Er übernimmt es nicht von selbst, bitte später noch einmal wählen."
            }
        }
    }
}
