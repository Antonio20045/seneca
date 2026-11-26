import SwiftUI

struct StatLaufenView: View {
    @ObservedObject var model: StatistikModel
    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = model.laufenSeite(jetzt: store.clock())
        Seite(titel: "Laufen", zurueck: "Statistik", beimZurueck: { dismiss() }) {
            StatDetailText(text: s.untertitel)
            if let leer = s.leer {
                LeerSatz(leer)
            } else {
                StatWerteView(werte: s.werte).padding(.top, Stil.abstand.xl)
                AbschnittKopf("Kilometer pro Woche")
                StatMonatsBalkenView(b: StatMonatsBalken(werte: s.wochenKm, namen: s.wochenNamen, hervor: nil, aktuell: s.wochenKm.count - 1))
                if let p = s.wochenPace {
                    AbschnittKopf("Tempo pro Woche")
                    StatLinieView(l: p, hoehe: 72)
                }
                if !s.bestwerte.isEmpty {
                    AbschnittKopf("Bestwerte")
                    VStack(alignment: .leading, spacing: Stil.abstand.s) {
                        ForEach(s.bestwerte, id: \.self) { StatDetailText(text: $0) }
                    }
                }
                AbschnittKopf("Alle Läufe")
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(s.liste) { l in
                        Zeile(titel: "\(l.tag) · \(l.km)", unter: "\(l.zeit) · \(l.pace) pro km", linie: l.id != s.liste.last?.id)
                    }
                }
            }
        }
        .senecaGrund()
        .accessibilityAction(.escape) { dismiss() }
    }
}

enum StatBuchModus: Identifiable {
    case neu
    case bearbeiten(StatBuch)
    var id: String { if case .bearbeiten(let b) = self { return b.id }; return "neu" }
    var titel: String { if case .bearbeiten = self { return "Buch bearbeiten" }; return "Neues Buch" }
}

struct StatBuecherView: View {
    @ObservedObject var model: StatistikModel
    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var dismiss
    @State private var modus: StatBuchModus?
    @State private var eintragen: StatBlatt?

    var body: some View {
        let jetzt = store.clock()
        let s = model.buecherSeite(jetzt: jetzt)
        let daten = model.daten(jetzt: jetzt)
        Seite(titel: "Bücher", zurueck: "Statistik", beimZurueck: { dismiss() }) {
            if let a = s.aktuell {
                AbschnittKopf("Du liest gerade", oben: false)
                Text(a.titel).font(Stil.Schrift.gross.kursiv).foregroundStyle(Stil.tinte.voll)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                StatDetailText(text: a.seit).padding(.top, Stil.abstand.s)
                StatSchnellLesen(model: model) { eintragen = .lesen }.padding(.top, Stil.abstand.l)
                if let f = a.fortschritt { StatFortschrittView(f: f, hoehe: 6).padding(.top, Stil.abstand.xl) }
                if let t = a.schnitt { StatDetailText(text: t).padding(.top, Stil.abstand.m) }
                if a.tage.count >= 2 {
                    AbschnittKopf("Lesezeit pro Tag in diesem Buch")
                    HStack(alignment: .bottom, spacing: Stil.abstand.xs) {
                        ForEach(Array(a.tage.enumerated()), id: \.offset) { _, t in
                            Group {
                                if t.da {
                                    UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3)
                                        .fill(t.heute ? Stil.tinte.voll : Stil.farbe.himmel).frame(height: max(3, 74 * t.anteil))
                                } else {
                                    Capsule().fill(Stil.tinte.linie).frame(height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 80, alignment: .bottom)
                    .padding(.bottom, Stil.abstand.s)
                    HStack { StatKlein(text: a.tageLinks); Spacer(); StatKlein(text: "heute") }
                }
                HStack(spacing: Stil.abstand.s) {
                    ZweitKnopf("Buch abschließen") {
                        model.schreiben([StatOp.buchBeenden(id: a.id, datum: StatKalender.schluessel(store.clock()))], store: store)
                    }
                    .accessibilityIdentifier("statBuecher.abschliessen")
                    TextKnopf("Bearbeiten") { if let b = daten.buch(a.id) { modus = .bearbeiten(b) } }
                    Spacer(minLength: 0)
                }
                .padding(.top, Stil.abstand.xl)
            } else {
                LeerSatz("Noch kein Buch. Lege mit „Neues Buch“ eines an, dann zählt die App die Lesezeit für dieses Buch.")
            }

            AbschnittKopf(s.listeLabel ?? "Bücher", aktion: (titel: "Neues Buch", ausfuehren: { modus = .neu }))
            VStack(spacing: 0) {
                ForEach(s.liste) { z in
                    Zeile(titel: z.titel, unter: z.zeile, hinten: .pfeil, linie: z.id != s.liste.last?.id) {
                        if let b = daten.buch(z.id) { modus = .bearbeiten(b) }
                    }
                }
            }
        }
        .senecaGrund()
        .senecaBlatt(item: $modus, groesse: .voll, titel: { $0.titel }) { mod in
            StatBuchBlatt(modus: mod, model: model)
        }
        .senecaBlatt(item: $eintragen, groesse: .voll, titel: { _ in "Lesen eintragen" }) { _ in
            StatEintragBlatt(model: model)
        }
        .accessibilityAction(.escape) { dismiss() }
    }
}

struct StatBuchBlatt: View {
    var modus: StatBuchModus
    @ObservedObject var model: StatistikModel
    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var dismiss
    @State private var titel = ""
    @State private var autor = ""
    @State private var begonnen = Date()
    @State private var geladen = false
    @FocusState private var fokus: Bool

    private var bearbeiten: StatBuch? { if case .bearbeiten(let b) = modus { return b }; return nil }
    private var leer: Bool { titel.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.l) {
            SchreibFeld("Titel", text: $titel, zeilen: 1...2)
                .focused($fokus)
                .modifier(FocusOnAppearWenn(aktiv: bearbeiten == nil, focus: $fokus))
                .accessibilityIdentifier("statBuch.titel")
            SchreibFeld("Autor (kann leer bleiben)", text: $autor, zeilen: 1...1)
                .accessibilityIdentifier("statBuch.autor")
            DatePicker("Begonnen am", selection: $begonnen, in: ...store.clock(), displayedComponents: .date)
                .schrift(.zeile).foregroundStyle(Stil.tinte.voll).tint(Stil.farbe.himmel)
            HauptKnopf(bearbeiten == nil ? "Beginnen" : "Speichern", breit: true, aktion: speichern)
                .disabled(leer)
                .accessibilityIdentifier("statBuch.speichern")
            if let b = bearbeiten {
                TextKnopf("Buch entfernen") {
                    model.schreiben([StatOp.buchEntfernen(id: b.id)], store: store)
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !geladen, let b = bearbeiten else { return }
            geladen = true
            titel = b.titel; autor = b.autor ?? ""
            begonnen = StatKalender.tag(b.begonnen) ?? Date()
        }
    }

    private func speichern() {
        let t = titel.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = StatKalender.schluessel(begonnen)
        if let b = bearbeiten {
            model.schreiben([StatOp.buchAendern(id: b.id, titel: t, autor: autor.trimmingCharacters(in: .whitespacesAndNewlines), begonnen: tag)], store: store)
        } else {
            model.schreiben([StatOp.buchBeginnen(titel: t, autor: autor, datum: tag, beendeAktuelles: true)], store: store)
        }
        dismiss()
    }
}
