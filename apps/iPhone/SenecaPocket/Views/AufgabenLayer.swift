import SwiftUI

struct AufgabenLayer: View {
    var m: Metrics
    var now: Date
    var back: () -> Void
    var allowTap: () -> Bool = { true }
    var griff = false

    @EnvironmentObject private var store: SenecaStore
    @EnvironmentObject private var berichte: BerichteModel
    @Environment(\.appActions) private var appActions

    private enum Rueck: Equatable {
        case erledigt(id: String, titel: String)
        case geloescht(TodoUndo)
        var satz: String {
            switch self {
            case .erledigt(_, let titel): "„\(titel)“ ist erledigt."
            case .geloescht(let u): "„\(AufgabenLogic.anzeigeTitel(u.task.title))“ ist gelöscht."
            }
        }
    }

    @State private var halten: Set<String> = []
    @State private var rueck: Rueck?
    @State private var rueckMarke = UUID()
    @State private var offen: SenecaTask?
    @State private var neu = false

    private var liste: [AufgabenLogic.AbschnittListe] {
        AufgabenLogic.abschnitte(store.aufgaben, jetzt: now, behalten: halten, .current)
    }

    private var heuteHatErledigtes: Bool {
        AufgabenLogic.heutigeAufgaben(store.aufgaben, jetzt: now, .current).contains { $0.isDone }
    }

    private var stand: String? {
        guard let sync = store.lastSync, now.timeIntervalSince(sync) > 600 else { return nil }
        return "Stand von \(DayLogic.hm(sync, .current)), der Mac antwortet gerade nicht."
    }

    private var berichtGruppen: [BerichtGruppe] {
        BerichteLogik.zusammengefasst(berichte.eintraege(store: store, jetzt: now))
    }

    var body: some View {
        Seite(zurueck: "Heute", beimZurueck: back) {
            if berichte.tab == .aufgaben {
                aufgabenInhalt.transition(.wechsel)
            } else {
                BerichteListeView(now: now, allowTap: allowTap).transition(.wechsel)
            }
        }
        .reiter {
            ReiterLeiste(auswahl: $berichte.tab, optionen: [
                .init(.aufgaben, "Aufgaben"),
                .init(.berichte, "Berichte", zahl: BerichteLogik.ungelesen(berichtGruppen)),
            ])
        }
        .scrollDisabled(griff)
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .overlay(alignment: .bottom) { rueckLeiste }
        .senecaBlatt(item: $offen, groesse: .halb, fertig: true) { t in
            AufgabeBlatt(aufgabeId: t.id, jetzt: now, abhaken: { abhaken(t) }, geloescht: { zeigeRueck(.geloescht($0)) })
        }
        .background { Color.clear.neueAufgabeBlatt(isPresented: $neu, jetzt: { now }) }
        .task { await berichte.laden(store: store, jetzt: now) }
        .onChange(of: berichte.tab) { _, tab in
            if tab == .berichte { Task { await berichte.laden(store: store, jetzt: now) } }
        }
        .onAppear(perform: demoStart)
        .onDisappear { berichte.tab = .aufgaben }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { back() }
        .accessibilityAction(named: "Zurück zu heute") { back() }
    }

    @ViewBuilder private var aufgabenInhalt: some View {
        let abschnitte = liste
        if let stand { HinweisZeile(stand, art: .offline) }
        neuZeile
        if abschnitte.isEmpty, store.today != nil {
            LeerSatz("Gerade steht nichts an.")
        }
        ForEach(abschnitte, id: \.abschnitt) { s in
            AbschnittKopf(s.abschnitt.titel, zahl: s.aufgaben.isEmpty ? nil : s.aufgaben.count)
                .accessibilityIdentifier("aufgaben.abschnitt." + s.abschnitt.rawValue)
            if s.aufgaben.isEmpty {
                Text(heuteHatErledigtes ? "Für heute ist alles erledigt." : "Für heute ist nichts eingeplant.")
                    .schrift(.text)
                    .foregroundStyle(Stil.tinte.zweit)
                    .padding(.vertical, Stil.abstand.m)
            }
            ForEach(Array(s.aufgaben.enumerated()), id: \.element.id) { i, t in
                zeile(t, s.abschnitt, letzte: i == s.aufgaben.count - 1)
                    .transition(.opacity)
            }
        }
    }

    private var neuZeile: some View {
        Button {
            guard allowTap() else { return }
            neu = true
        } label: {
            HStack(spacing: Stil.abstand.l) {
                Image(systemName: "plus")
                    .font(Stil.symbol(.klein, gewicht: .medium))
                    .frame(width: 22)
                Text("Neue Aufgabe").schrift(.zeile)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Stil.tinte.zweit)
            .frame(minHeight: Stil.zeilenHoehe)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aufgaben.neu")
    }

    private func zeile(_ t: SenecaTask, _ abschnitt: AufgabenLogic.Abschnitt, letzte: Bool) -> some View {
        Zeile(vorn: .haken(an: t.isDone) { abhaken(t) },
              titel: AufgabenLogic.anzeigeTitel(t.title),
              unter: AufgabenLogic.nebenzeile(t, abschnitt: abschnitt, jetzt: now, .current),
              betont: AufgabenLogic.gewicht(t) == .wichtig && !t.isDone,
              linie: !letzte) {
            guard allowTap() else { return }
            offen = t
        }
        .contextMenu {
            Button("Erledigt", systemImage: "checkmark.circle") { abhaken(t) }
            Button("Löschen", systemImage: "trash", role: .destructive) {
                if let u = store.archiveTask(t.id) { zeigeRueck(.geloescht(u)) }
            }
        }
        .accessibilityIdentifier("aufgabe." + t.id)
    }

    private func abhaken(_ t: SenecaTask) {
        guard allowTap() else { return }
        let id = t.id
        if halten.contains(id) {
            store.toggleTask(id)
            Bewegung.mit(.klein) { _ = halten.remove(id) }
            if case .erledigt(id, _)? = rueck { Bewegung.mit(.wechsel) { rueck = nil } }
            return
        }
        guard !(store.aufgaben.first { $0.id == id }?.isDone ?? false) else { return }
        Bewegung.mit(.klein) {
            store.toggleTask(id)
            _ = halten.insert(id)
        }
        zeigeRueck(.erledigt(id: id, titel: AufgabenLogic.anzeigeTitel(t.title)))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard halten.contains(id) else { return }
            Bewegung.mit(.blatt) { _ = halten.remove(id) }
        }
    }

    private func zeigeRueck(_ r: Rueck) {
        let marke = UUID()
        rueckMarke = marke
        Bewegung.mit(.wechsel) { rueck = r }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : 5))
            guard rueckMarke == marke else { return }
            Bewegung.mit(.wechsel) { rueck = nil }
        }
    }

    private func rueckgaengig() {
        guard let r = rueck else { return }
        Haptik.tipp()
        switch r {
        case .erledigt(let id, _):
            if store.aufgaben.first(where: { $0.id == id })?.isDone == true { store.toggleTask(id) }
            Bewegung.mit(.blatt) { _ = halten.remove(id) }
        case .geloescht(let u):
            Bewegung.mit(.blatt) { store.undoTask(u) }
        }
        rueckMarke = UUID()
        Bewegung.mit(.wechsel) { rueck = nil }
    }

    @ViewBuilder private var rueckLeiste: some View {
        if let rueck {
            HStack(spacing: Stil.abstand.m) {
                Text(rueck.satz)
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.voll)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Rückgängig", action: rueckgaengig)
                    .buttonStyle(TextKnopfStil(stufe: .zeileWichtig))
                    .accessibilityIdentifier("aufgaben.undo")
            }
            .padding(.leading, Stil.abstand.l)
            .padding(.trailing, Stil.abstand.m)
            .background(Capsule().fill(Stil.farbe.grund).overlay(Capsule().fill(Stil.tinte.flaecheStark)))
            .seitenRand()
            .padding(.bottom, Stil.fensterRaender.bottom + Stil.abstand.l)
            .transition(.move(edge: .bottom))
        }
    }

    private func demoStart() {
        #if DEBUG
        guard store.demo else { return }
        let env = ProcessInfo.processInfo.environment
        if env["SENECA_DEMO_NEUE_AUFGABE"] == "1" {
            Task { try? await Task.sleep(for: .seconds(1.0)); neu = true }
        }
        if env["SENECA_DEMO_AUFGABE_BLATT"] == "1" {
            Task { try? await Task.sleep(for: .seconds(1.0)); offen = liste.first?.aufgaben.first }
        }
        if env["SENECA_DEMO_ABHAKEN"] == "1" {
            Task { try? await Task.sleep(for: .seconds(1.5)); if let t = liste.first?.aufgaben.first { abhaken(t) } }
        }
        if let v = env["SENECA_DEMO_BERICHTE"] {
            berichte.tab = .berichte
            if v == "lesen" {
                Task {
                    await berichte.laden(store: store, jetzt: now)
                    try? await Task.sleep(for: .seconds(1.2))
                    if let g = berichtGruppen.first(where: { $0.neuester.text.contains("```seneca") }) {
                        BerichteListeView.oeffnen(g, now: now, store: store, actions: appActions)
                    }
                }
            }
        }
        #endif
    }
}
