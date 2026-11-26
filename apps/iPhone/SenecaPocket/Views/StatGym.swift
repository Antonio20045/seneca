import SwiftUI

struct StatGymView: View {
    @ObservedObject var model: StatistikModel
    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var dismiss
    private enum Feld: Hashable { case kg, wdh }
    @FocusState private var fokus: Feld?
    @State private var uebung: String?
    @State private var kg = 20.0
    @State private var kgText = "20"
    @State private var wdh = 8
    @State private var wdhText = "8"
    @State private var extra: [String] = []
    @State private var suche = false
    @State private var uhr: GymUhr? = GymUhr.laden()

    private var heute: String { StatKalender.schluessel(store.clock()) }
    private static let kgSchritte: [[Double]] = [[-5, -2.5, -1.25, -0.5], [0.5, 1.25, 2.5, 5]]

    var body: some View {
        let jetzt = store.clock()
        let daten = model.daten(jetzt: jetzt)
        let alle = StatGym.sortiert(daten, extra: extra, heute: heute)
        let aktuell = uebung ?? StatGym.uebungen(daten, extra: extra).first
        let heutige = aktuell.map { StatGym.saetze($0, daten, am: heute) } ?? []
        var chips = StatGym.haeufig(daten, extra: extra, heute: heute)
        if let a = aktuell, !chips.contains(a) { chips = [a] + chips.prefix(5) }
        return Seite(titel: "Training", zurueck: "Statistik", beimZurueck: { dismiss() }) {
            status(daten)
            uebungsReihe(chips, aktuell: aktuell, daten: daten).padding(.top, Stil.abstand.m)

            if let name = aktuell {
                Text(name).schrift(.gross).foregroundStyle(Stil.tinte.voll).lineLimit(2).minimumScaleFactor(0.6)
                    .padding(.top, Stil.abstand.xl)
                    .accessibilityAddTraits(.isHeader)
                StatDetailText(text: StatGym.letztesMal(name, daten, heute: heute) ?? "Das ist dein erster Satz in dieser Übung.")
                    .padding(.top, Stil.abstand.s)
                gewichtBlock
                wdhBlock
                satzListe(heutige)
            } else {
                LeerSatz("Lege deine erste Übung an. Tippe auf „Übung suchen oder neu“ und gib ihr einen Namen, zum Beispiel Bankdrücken.")
            }

            if model.wartetAufMac {
                HinweisZeile("Gespeichert. Geht an deinen Mac, sobald er erreichbar ist.", art: .offline)
                    .padding(.top, Stil.abstand.m)
                    .accessibilityIdentifier("statGym.wartet")
            } else if let hinweis = model.meldung {
                HinweisZeile(hinweis, art: .fehler)
                    .padding(.top, Stil.abstand.m)
                    .accessibilityIdentifier("statGym.meldung")
            }
        }
        .unten {
            if let name = aktuell { eintragenLeiste(name, nr: heutige.count + 1) }
        }
        .senecaGrund()
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { n in
            if let f = n.object as? UITextField { DispatchQueue.main.async { f.selectAll(nil) } }
        }
        .onChange(of: fokus) { alt, _ in
            if alt == .kg { kgText = StatGym.kgFeld(kg) }
            if alt == .wdh { wdhText = "\(wdh)" }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if uebung == nil, let erste = StatGym.uebungen(daten, extra: extra).first { waehlen(erste, daten) }
            else if aktuell == nil { suche = true }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .accessibilityAction(.escape) { dismiss() }
        .senecaBlatt(isPresented: $suche, groesse: .voll, titel: "Übung wählen") {
            StatUebungSuche(namen: alle, aktuell: aktuell) { name, neu in
                if neu, !extra.contains(name) { extra.insert(name, at: 0) }
                waehlen(name, daten)
            }
        }
    }

    private func status(_ daten: StatDaten) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let j = store.clock()
            HStack(spacing: Stil.abstand.l) {
                if let st = GymUhr.stand(lokal: uhr, daten: daten, jetzt: j, heute: heute) {
                    Text(GymUhr.trainingText(j.timeIntervalSince(st.start))).accessibilityIdentifier("statGym.training")
                    Text("Pause " + GymUhr.pauseText(GymUhr.pause(letzter: st.letzter, jetzt: j))).monospacedDigit().accessibilityIdentifier("statGym.pause")
                } else {
                    Text("Noch kein Satz").accessibilityIdentifier("statGym.training")
                }
                Spacer(minLength: 0)
            }
            .schrift(.klein)
            .foregroundStyle(Stil.tinte.zweit)
            .lineLimit(1)
        }
    }

    private func uebungsReihe(_ chips: [String], aktuell: String?, daten: StatDaten) -> some View {
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            StatFlow(spacingX: Stil.abstand.s, spacingY: Stil.abstand.s) {
                ForEach(chips, id: \.self) { n in
                    StatChip(n, gewaehlt: n == aktuell) { waehlen(n, daten) }
                        .accessibilityIdentifier("statGym.chip.\(n)")
                }
            }
            TextKnopf("Übung suchen oder neu") { fokus = nil; suche = true }
                .accessibilityIdentifier("statGym.neueUebung")
        }
    }

    private var gewichtBlock: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            AbschnittKopf("Gewicht")
            HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.s) {
                TextField("0", text: $kgText)
                    .schrift(.zahl).foregroundStyle(Stil.tinte.voll).tint(Stil.farbe.himmel)
                    .keyboardType(.decimalPad).focused($fokus, equals: .kg)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: 200, alignment: .leading)
                    .onChange(of: kgText) { _, t in
                        let sauber = String(t.filter { "0123456789,.-\u{2212}".contains($0) }.prefix(9))
                        if sauber != t { kgText = sauber; return }
                        if let v = StatGym.kgParsen(t) { kg = v }
                    }
                    .accessibilityLabel("Gewicht in Kilogramm")
                    .accessibilityIdentifier("statGym.kg.feld")
                Text("kg").schrift(.titel).foregroundStyle(Stil.tinte.zweit).fixedSize()
                Spacer(minLength: 0)
            }
            if StatGym.kgParsen(kgText) == nil {
                Text("Das Gewicht kann ich nicht lesen. Zum Beispiel 62,5.").schrift(.klein).foregroundStyle(Stil.farbe.koralle)
                    .accessibilityIdentifier("statGym.kg.hinweis")
            }
            StatChip(kg < 0 ? "Mit Unterstützung: Gewicht wird abgezogen" : "Mit Unterstützung", gewaehlt: kg < 0) { vorzeichen() }
                .accessibilityIdentifier("statGym.kg.vorzeichen")
                .accessibilityLabel("Mit Unterstützung")
                .accessibilityValue(kg < 0 ? "an" : "aus")
            ForEach(Self.kgSchritte, id: \.self) { reihe in
                HStack(spacing: Stil.abstand.s) {
                    ForEach(reihe, id: \.self) { d in schrittKnopf(d) }
                }
            }
        }
    }

    private func schrittKnopf(_ d: Double) -> some View {
        let text = (d < 0 ? "\u{2212}" : "+") + StatFormat.kg(abs(d))
        let id = d == 2.5 ? "statGym.kg.plus" : d == -2.5 ? "statGym.kg.minus" : "statGym.kg.\(d < 0 ? "minus" : "plus")\(StatGym.kgFeld(abs(d)))"
        return StatChip(text, breit: true) {
            fokus = nil
            kg = StatGym.kgSchritt(StatGym.kgParsen(kgText) ?? kg, d)
            kgText = StatGym.kgFeld(kg)
        }
        .accessibilityLabel("\(StatFormat.kg(abs(d))) kg \(d < 0 ? "weniger" : "mehr")")
        .accessibilityIdentifier(id)
    }

    private var wdhBlock: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            AbschnittKopf("Wiederholungen")
            HStack(spacing: Stil.abstand.m) {
                RundKnopf("minus", beschriftung: "Eine weniger") { setzeWdh(-1) }
                    .accessibilityIdentifier("statGym.wdh.minus")
                TextField("0", text: $wdhText)
                    .schrift(.zahl).foregroundStyle(Stil.tinte.voll).tint(Stil.farbe.himmel)
                    .keyboardType(.numberPad).focused($fokus, equals: .wdh)
                    .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.5)
                    .onChange(of: wdhText) { _, t in
                        let ziffern = String(t.filter(\.isNumber).prefix(3))
                        if ziffern != t { wdhText = ziffern; return }
                        if let v = Int(ziffern), (1...100).contains(v) { wdh = v }
                    }
                    .accessibilityLabel("Wiederholungen")
                    .accessibilityIdentifier("statGym.wdh.feld")
                RundKnopf("plus", beschriftung: "Eine mehr") { setzeWdh(1) }
                    .accessibilityIdentifier("statGym.wdh.plus")
            }
        }
    }

    private func satzListe(_ heutige: [StatSatz]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !heutige.isEmpty { AbschnittKopf("Heute", zahl: heutige.count) }
            ForEach(Array(heutige.enumerated().reversed()), id: \.element.id) { i, s in
                Zeile(vorn: .zeit("\(i + 1)"), titel: StatAbschnitte.satzText(s), linie: i > 0)
                    .accessibilityIdentifier("statGym.satz.\(i + 1)")
            }
            if heutige.last != nil {
                TextKnopf("Letzten Satz löschen", stufe: .klein) { loeschen(heutige[heutige.count - 1]) }
                    .accessibilityIdentifier("statGym.loeschen")
            }
        }
    }

    private func eintragenLeiste(_ name: String, nr: Int) -> some View {
        let gueltig = StatGym.kgParsen(kgText) != nil && (1...100).contains(Int(wdhText) ?? 0)
        return HStack(spacing: Stil.abstand.s) {
            if fokus != nil {
                ZweitKnopf("Fertig") { fokus = nil }
                    .accessibilityIdentifier("statGym.tastatur.fertig")
            }
            HauptKnopf("Satz \(nr) eintragen", breit: true) { eintragen(name) }
                .disabled(!gueltig)
                .accessibilityIdentifier("statGym.eintragen")
        }
    }

    private func waehlen(_ name: String, _ daten: StatDaten) {
        fokus = nil
        uebung = name
        let v = StatGym.vorbelegung(name, daten, heute: heute)
        kg = v.kg; kgText = StatGym.kgFeld(v.kg)
        wdh = v.wdh; wdhText = "\(v.wdh)"
    }

    private func vorzeichen() {
        guard let v = StatGym.kgParsen(kgText) else { return }
        fokus = nil
        kg = StatGym.kgVorzeichen(v)
        kgText = StatGym.kgFeld(kg)
    }

    private func setzeWdh(_ schritt: Int) {
        fokus = nil
        wdh = min(100, max(1, (Int(wdhText) ?? wdh) + schritt))
        wdhText = "\(wdh)"
    }

    private func eintragen(_ name: String) {
        guard let k = StatGym.kgParsen(kgText), let w = Int(wdhText), (1...100).contains(w) else { return }
        fokus = nil
        Haptik.erledigt()
        let jetzt = store.clock()
        uhr = GymUhr.eintragen(uhr, jetzt: jetzt, heute: heute)
        GymUhr.speichern(uhr)
        model.schreiben([StatOp.satz(uebung: name, kg: k, wdh: w, datum: heute, zeit: jetzt)], store: store)
    }

    private func loeschen(_ satz: StatSatz) {
        Haptik.tipp()
        if uhr?.tag == heute, model.daten(jetzt: store.clock()).saetze.filter({ $0.datum == heute }).count <= 1 {
            uhr = nil
            GymUhr.speichern(nil)
        }
        model.schreiben([StatOp.satzEntfernen(satz: satz.id)], store: store)
    }
}

struct StatFlow: Layout {
    var spacingX: CGFloat
    var spacingY: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, zeile: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x > 0, x + g.width > breite { y += zeile + spacingY; x = 0; zeile = 0 }
            x += g.width + spacingX; zeile = max(zeile, g.height); maxX = max(maxX, x - spacingX)
        }
        return CGSize(width: min(breite, maxX), height: y + zeile)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, zeile: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + g.width > bounds.maxX { y += zeile + spacingY; x = bounds.minX; zeile = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
            x += g.width + spacingX; zeile = max(zeile, g.height)
        }
    }
}
