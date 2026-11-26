import SwiftUI

extension View {
    func neueAufgabeBlatt(isPresented: Binding<Bool>, jetzt: @escaping () -> Date, vorgabe: NeueAufgabeLogik.TagWahl = .heute) -> some View {
        senecaBlatt(isPresented: isPresented, groesse: .halb, scrollt: false) {
            NeueAufgabeBlatt(jetzt: jetzt(), vorgabe: vorgabe) { isPresented.wrappedValue = false }
        }
    }
}

struct NeueAufgabeEinstieg: View {
    var id: String
    var aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: Stil.abstand.s) {
                Image(systemName: "plus").font(Stil.symbol(.klein, gewicht: .medium))
                Text("Neue Aufgabe").schrift(.zeile)
            }
            .foregroundStyle(Stil.tinte.zweit)
            .tippFlaeche()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Neue Aufgabe")
        .accessibilityIdentifier(id)
    }
}

struct NeueAufgabeBlatt: View {
    var jetzt: Date
    var vorgabe: NeueAufgabeLogik.TagWahl = .heute
    var fertig: () -> Void

    private enum Art: Hashable { case aufgabe, termin }

    @EnvironmentObject private var store: SenecaStore
    @State private var art = Art.aufgabe
    @State private var titel = ""
    @State private var tag: NeueAufgabeLogik.TagWahl = .heute
    @State private var datum = Date()
    @State private var frist: FristWahl = .keine
    @State private var fristDatum = Date()
    @State private var board: String? = nil
    @State private var von = Date.distantPast
    @State private var bis = Date.distantPast
    @State private var ort = ""
    @State private var kalender = TerminEingabeLogik.kalender[0]
    @State private var sendet = false
    @State private var fehler: String? = nil
    @FocusState private var fokus: Bool
    @Environment(\.calendar) private var cal

    private var termin: Bool { art == .termin }
    private var kannAnlegen: Bool { !titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sendet }
    private var start: Date { cal.startOfDay(for: jetzt) }

    private var gruppen: [NeueAufgabeLogik.Gruppe] {
        let snap = store.today
        return NeueAufgabeLogik.gruppen(boardNames: snap?.boardNames, projects: snap?.projects, areas: snap?.areas?.areas,
                                        cards: snap?.cards, tasks: snap?.tasks ?? [])
    }
    private var ziel: NeueAufgabeLogik.Ziel? {
        let snap = store.today
        return NeueAufgabeLogik.ziel(board: board, boardNames: snap?.boardNames, projects: snap?.projects,
                                     areas: snap?.areas?.areas, tasks: snap?.tasks ?? [])
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ReiterLeiste(auswahl: $art, optionen: [.init(.aufgabe, "Aufgabe"), .init(.termin, "Termin")])
                SchreibFeld(termin ? "Was steht an?" : "Was ist zu tun?", text: $titel, zeilen: 1...1)
                    .onSubmit(anlegen)
                    .focused($fokus)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("neueAufgabe.titel")
                    .padding(.top, Stil.abstand.m)
                if let fehler {
                    HinweisZeile(fehler, art: .fehler)
                        .accessibilityIdentifier("neueAufgabe.fehler")
                }
                AbschnittKopf("Wann")
                ChipFluss {
                    WahlChip("Heute", an: tag == .heute) { tag = .heute }
                    WahlChip("Morgen", an: tag == .morgen) { tag = .morgen }
                    WahlChip(tag == .datum ? DatumWort.kurz(datum, jetzt: jetzt, cal) : "Datum …", an: tag == .datum) { tag = .datum }
                    if !termin { WahlChip("Ohne Tag", an: tag == .ohne) { tag = .ohne } }
                }
                if tag == .datum { DatumWahl(titel: "Tag", datum: $datum, ab: start) }
                if termin { terminFelder } else { aufgabeFelder }
            }
            .seitenRand()
            .padding(.bottom, Stil.abstand.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .weicheKante(unten: true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HauptKnopf(termin ? (sendet ? "Wird eingetragen …" : "Eintragen") : "Hinzufügen", breit: true, aktion: anlegen)
                .disabled(!kannAnlegen)
                .accessibilityIdentifier("neueAufgabe.hinzufuegen")
                .seitenRand()
                .padding(.top, Stil.abstand.s)
                .padding(.bottom, Stil.abstand.l)
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
        .onAppear {
            tag = vorgabe
            datum = cal.date(byAdding: .day, value: 2, to: start) ?? start
            fristDatum = cal.date(byAdding: .day, value: 7, to: start) ?? start
            let v = TerminEingabeLogik.vorgabe(jetzt: jetzt, cal)
            von = v.von
            bis = v.bis
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            fokus = true
        }
        .onChange(of: von) { alt, neu in
            if alt != .distantPast { bis = TerminEingabeLogik.bisNachVon(altVon: alt, altBis: bis, neuVon: neu, cal) }
        }
        .onChange(of: art) { _, neu in
            fehler = nil
            if neu == .termin, tag == .ohne { tag = .heute }
        }
        .onChange(of: titel) { _, _ in fehler = nil }
    }

    @ViewBuilder private var aufgabeFelder: some View {
        AbschnittKopf("Bis wann")
        ChipFluss {
            WahlChip("Keine Frist", an: frist == .keine) { frist = .keine }
            WahlChip("Heute", an: frist == .heute) { frist = .heute }
            WahlChip("Ende der Woche", an: frist == .wochenEnde) { frist = .wochenEnde }
            WahlChip(frist == .datum ? DatumWort.kurz(fristDatum, jetzt: jetzt, cal) : "Datum …", an: frist == .datum) { frist = .datum }
        }
        if frist == .datum { DatumWahl(titel: "Frist", datum: $fristDatum, ab: start) }
        if !gruppen.isEmpty {
            AbschnittKopf("Bereich")
            BereichWahl(board: $board, gruppen: gruppen, beschriftung: NeueAufgabeLogik.beschriftung(ziel))
        }
    }

    @ViewBuilder private var terminFelder: some View {
        AbschnittKopf("Uhrzeit")
        HStack(spacing: Stil.abstand.m) {
            DatePicker("Von", selection: $von, displayedComponents: .hourAndMinute)
                .labelsHidden().accessibilityLabel("Beginn").accessibilityIdentifier("neueAufgabe.von")
            Text("bis").schrift(.zeile).foregroundStyle(Stil.tinte.zweit)
            DatePicker("Bis", selection: $bis, displayedComponents: .hourAndMinute)
                .labelsHidden().accessibilityLabel("Ende").accessibilityIdentifier("neueAufgabe.bis")
        }
        .tint(Stil.farbe.himmel)
        .frame(minHeight: Stil.tippFlaeche, alignment: .leading)
        AbschnittKopf("Ort")
        SchreibFeld("Wo? (kann leer bleiben)", text: $ort, zeilen: 1...1)
            .accessibilityIdentifier("neueAufgabe.ort")
        AbschnittKopf("Kalender")
        ChipFluss {
            ForEach(TerminEingabeLogik.kalender, id: \.self) { name in
                WahlChip(name, an: kalender == name) { kalender = name }
            }
        }
    }

    private func anlegen() {
        guard kannAnlegen else { return }
        if termin { terminEintragen(); return }
        let plan = NeueAufgabeLogik.plan(tag, datum: datum, jetzt: jetzt, cal)
        store.addTask(titel, plan: plan, frist: frist.tag(datum: fristDatum, jetzt: jetzt, cal), board: board)
        Haptik.erledigt()
        fertig()
    }

    private func terminEintragen() {
        let z = TerminEingabeLogik.zeitraum(tag: tag, datum: datum, von: von, bis: bis, jetzt: jetzt, cal)
        if let problem = TerminEingabeLogik.pruefen(titel: titel, ort: ort, start: z.start, ende: z.ende, jetzt: jetzt) {
            fehler = problem
            return
        }
        sendet = true
        fehler = nil
        fokus = false
        Task {
            do {
                try await store.addEvent(titel: titel, start: z.start, ende: z.ende, kalender: kalender, ort: ort)
                Haptik.erledigt()
                fertig()
            } catch {
                fehler = error.localizedDescription
                sendet = false
            }
        }
    }
}

enum FristWahl: Hashable {
    case keine, heute, wochenEnde, datum

    func tag(datum: Date, jetzt: Date, _ cal: Calendar) -> String? {
        let start = cal.startOfDay(for: jetzt)
        switch self {
        case .keine: return nil
        case .heute: return DayLogic.dayKey(start, cal)
        case .wochenEnde:
            let bisSonntag = (8 - cal.component(.weekday, from: start)) % 7
            return DayLogic.dayKey(cal.date(byAdding: .day, value: bisSonntag, to: start) ?? start, cal)
        case .datum: return DayLogic.dayKey(datum, cal)
        }
    }
}

enum DatumWort {
    static func kurz(_ d: Date, jetzt: Date, _ cal: Calendar) -> String {
        AufgabenLogic.kurzTag(DayLogic.dayKey(d, cal), jetzt: jetzt, cal) ?? "Datum …"
    }
}

struct WahlChip: View {
    var titel: String
    var an: Bool
    var aktion: () -> Void
    init(_ titel: String, an: Bool, aktion: @escaping () -> Void) {
        self.titel = titel; self.an = an; self.aktion = aktion
    }
    var body: some View {
        Button {
            Haptik.auswahl()
            Bewegung.mit(.klein) { aktion() }
        } label: {
            Text(titel)
                .schrift(an ? .zeileWichtig : .zeile)
                .lineLimit(1)
                .foregroundStyle(an ? Stil.tinte.voll : Stil.tinte.zweit)
                .padding(.horizontal, Stil.abstand.m)
                .padding(.vertical, Stil.abstand.s)
                .background(RoundedRectangle(cornerRadius: Stil.radius.klein, style: .continuous)
                    .fill(an ? Stil.tinte.flaecheStark : Stil.tinte.flaeche))
                .overlay(RoundedRectangle(cornerRadius: Stil.radius.klein, style: .continuous)
                    .strokeBorder(an ? Stil.tinte.leise : .clear, lineWidth: 1))
                .padding(.vertical, Stil.abstand.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(an ? .isSelected : [])
    }
}

struct ChipFluss: Layout {
    var abstand: CGFloat = Stil.abstand.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? .infinity
        let reihen = anordnen(subviews, breite: breite)
        let hoehe = reihen.last.map { $0.y + $0.hoehe } ?? 0
        let maxX = reihen.flatMap(\.rahmen).map(\.maxX).max() ?? 0
        return CGSize(width: proposal.width ?? maxX, height: hoehe)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var i = 0
        for reihe in anordnen(subviews, breite: bounds.width) {
            for r in reihe.rahmen {
                subviews[i].place(at: CGPoint(x: bounds.minX + r.minX, y: bounds.minY + r.minY), proposal: ProposedViewSize(r.size))
                i += 1
            }
        }
    }

    private struct Reihe { var y: CGFloat; var hoehe: CGFloat; var rahmen: [CGRect] }

    private func anordnen(_ subviews: Subviews, breite: CGFloat) -> [Reihe] {
        var reihen: [Reihe] = []
        var x: CGFloat = 0, y: CGFloat = 0
        var aktuell = Reihe(y: 0, hoehe: 0, rahmen: [])
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x > 0, x + g.width > breite {
                reihen.append(aktuell)
                y += aktuell.hoehe + abstand / 2
                x = 0
                aktuell = Reihe(y: y, hoehe: 0, rahmen: [])
            }
            aktuell.rahmen.append(CGRect(x: x, y: y, width: g.width, height: g.height))
            aktuell.hoehe = max(aktuell.hoehe, g.height)
            x += g.width + abstand
        }
        if !aktuell.rahmen.isEmpty { reihen.append(aktuell) }
        return reihen
    }
}

struct DatumWahl: View {
    var titel: String
    @Binding var datum: Date
    var ab: Date
    var body: some View {
        DatePicker(titel, selection: $datum, in: ab..., displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Stil.farbe.himmel)
            .accessibilityLabel("\(titel) wählen")
            .transition(.wechsel)
    }
}

struct BereichWahl: View {
    @Binding var board: String?
    var gruppen: [NeueAufgabeLogik.Gruppe]
    var beschriftung: String
    var body: some View {
        Menu {
            Button("Ohne Bereich") { board = nil }
            ForEach(gruppen) { g in
                Section(g.bereichName ?? "Weitere") {
                    ForEach(g.projekte) { p in Button(p.name) { board = p.id } }
                }
            }
        } label: {
            HStack(spacing: Stil.abstand.xs) {
                Text(beschriftung).schrift(board == nil ? .zeile : .zeileWichtig).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(Stil.symbol(.klein))
            }
            .foregroundStyle(board == nil ? Stil.tinte.zweit : Stil.tinte.voll)
            .padding(.horizontal, Stil.abstand.m)
            .padding(.vertical, Stil.abstand.s)
            .background(RoundedRectangle(cornerRadius: Stil.radius.klein, style: .continuous)
                .fill(board == nil ? Stil.tinte.flaeche : Stil.tinte.flaecheStark))
            .padding(.vertical, Stil.abstand.xs)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Bereich und Projekt")
        .accessibilityValue(beschriftung)
        .accessibilityIdentifier("neueAufgabe.bereich")
    }
}
