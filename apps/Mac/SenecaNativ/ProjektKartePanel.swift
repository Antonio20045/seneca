import SwiftUI

@MainActor
enum KartenAktion {
    static let statusName: [String: String] = ["backlog": "Backlog", "triage": "Einzuordnen", "todo": "Zu tun", "ready": "Bereit", "scheduled": "Geplant",
                                               "running": "In Arbeit", "review": "Prüfung", "blocked": "Blockiert", "done": "Erledigt"]
    static let prioName: [(String, String)] = [("urgent", "Dringend"), ("high", "Hoch"), ("normal", "Normal"), ("low", "Niedrig")]
    static let beweisText: [String: String] = ["passed": "bestanden", "failed": "fehlgeschlagen", "skipped": "übersprungen", "unknown": "ungeprüft"]

    static func speichereNotiz(_ store: OverviewStore, _ id: String, _ text: String) async throws { try await store.aendere(id, patch: ["notes": text]) }

    static func setzeLabel(_ store: OverviewStore, _ id: String, praefix: String, wert: String?) async throws {
        guard let c = store.aktuell(id) else { return }
        try await store.aendere(id, patch: ["labels": Menschlich.labelsMit(c.labels, praefix, wert: wert)])
    }

    static func uebergib(_ store: OverviewStore, _ id: String, agent: String?) async -> Bool { await store.starteKarte(id, agent: agent) }
}

struct ProjektKartePanel: View {
    var kartenId: String
    @EnvironmentObject private var store: OverviewStore
    @EnvironmentObject private var modell: AppModell

    @State private var titel = ""
    @State private var notiz = ""
    @State private var bearbeiteNotiz = false
    @State private var kommentar = ""
    @State private var agent = ""
    @State private var beschaeftigt = ""
    @State private var fehler = ""

    private var karte: OvKarte? { store.aktuell(kartenId) }

    var body: some View {
        Group {
            if let c = karte { inhalt(c) } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aufgabe nicht gefunden").font(Schrift.serif(22)).foregroundStyle(Farbe.ink1)
                    Text("Die Karte gibt es nicht mehr, oder sie wurde archiviert.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { if let c = karte { titel = c.title; notiz = c.notes ?? "" } }
        .onChange(of: karte?.updatedAt) { _, _ in
            if let c = karte, !bearbeiteNotiz { titel = c.title; notiz = c.notes ?? "" }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("karten-panel")
    }

    private func laufe(_ was: String, _ tu: @escaping () async throws -> Void) {
        beschaeftigt = was; fehler = ""
        Task {
            do { try await tu() } catch { fehler = OverviewStore.schreibFehlertext(error) }
            beschaeftigt = ""
        }
    }

    private func inhalt(_ c: OvKarte) -> some View {
        let projekt = store.projekte.first { $0.id == c.boardId }
        let dialog = HeuteLogik.istEntscheidung(c)
        let sichtbareLabels = c.labels.filter { Muster.passt($0, #"^(plan|frist|entscheidung|class|budget|origin|ideenlauf)(:|$)"#) == false }
        return VStack(alignment: .leading, spacing: 16) {
            Text((projekt?.name ?? c.boardId) + (dialog ? " · Entscheidung" : "")).font(Schrift.grotesk(11.5, .medium)).tracking(1).textCase(.uppercase).foregroundStyle(Farbe.ink3)
            TextField("", text: $titel, axis: .vertical)
                .textFieldStyle(.plain).font(Schrift.serif(26)).foregroundStyle(Farbe.ink1)
                .onSubmit { if !titel.trimmingCharacters(in: .whitespaces).isEmpty, titel != c.title { laufe("titel") { try await store.aendere(c.id, patch: ["title": titel.trimmingCharacters(in: .whitespaces)]) } } }
                .accessibilityLabel("Titel").accessibilityIdentifier("karte-titel")
            felder(c)
            if !sichtbareLabels.isEmpty {
                FlussZeile(abstand: 6) {
                    ForEach(sichtbareLabels, id: \.self) { l in
                        Text(l.hasPrefix("wartet-auf-") ? "wartet auf " + l.dropFirst(11) : l).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink2)
                            .padding(.horizontal, 9).padding(.vertical, 3).background(Farbe.pille, in: Capsule())
                    }
                }
                .accessibilityIdentifier("karte-labels")
            }
            if !fehler.isEmpty {
                Text(fehler).font(Schrift.grotesk(13)).foregroundStyle(Farbe.koralle)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Farbe.warnFlaeche, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Farbe.warnKante, lineWidth: 1))
                    .accessibilityIdentifier("karte-fehler")
            }
            notizBlock(c)
            if !c.nachweise.isEmpty { nachweise(c) }
            kommentare(c)
            if !dialog, c.status != "done" { uebergabe(c) }
            if !c.events.isEmpty { verlauf(c) }
            fuss(c, projekt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func felder(_ c: OvKarte) -> some View {
        let stati = ["backlog", "todo", "running", "review", "blocked", "done"] + (["triage", "ready", "scheduled"].contains(c.status) ? [c.status] : [])
        let agenten = store.daten.agents
        return VStack(alignment: .leading, spacing: 10) {
            zeile("Status") {
                Picker("Status", selection: Binding(get: { c.status }, set: { s in
                    guard s != c.status else { return }
                    laufe("status") { _ = try await store.verschiebe(c, nach: s) }
                })) { ForEach(stati, id: \.self) { Text(KartenAktion.statusName[$0] ?? $0).tag($0) } }
                    .labelsHidden().disabled(!beschaeftigt.isEmpty).accessibilityIdentifier("karte-status")
            }
            zeile("Zuständig") {
                Picker("Zuständig", selection: Binding(get: { c.agentId ?? "" }, set: { a in
                    guard a != (c.agentId ?? "") else { return }
                    laufe("agent") { try await store.aendere(c.id, patch: ["agentId": a.isEmpty ? NSNull() : a]) }
                })) {
                    Text("Du").tag("")
                    ForEach(agenten, id: \.id) { a in Text("\(store.daten.label(a.id).isEmpty ? a.id : store.daten.label(a.id)) (KI)").tag(a.id) }
                }
                .labelsHidden().disabled(!beschaeftigt.isEmpty || c.status == "running").accessibilityIdentifier("karte-zustaendig")
            }
            zeile("Priorität") {
                Picker("Priorität", selection: Binding(get: { c.priority ?? "normal" }, set: { pr in
                    guard pr != (c.priority ?? "normal") else { return }
                    laufe("prio") { try await store.aendere(c.id, patch: ["priority": pr]) }
                })) { ForEach(KartenAktion.prioName, id: \.0) { Text($0.1).tag($0.0) } }
                    .labelsHidden().disabled(!beschaeftigt.isEmpty).accessibilityIdentifier("karte-prio")
            }
            zeile("Für den Tag") { TagFeld(wert: Menschlich.planVon(c.labels), kennung: "karte-plan", aus: !beschaeftigt.isEmpty) { iso in
                laufe("plan") { try await KartenAktion.setzeLabel(store, c.id, praefix: "plan", wert: iso) } } }
            zeile("Frist") { TagFeld(wert: Menschlich.fristVon(c.labels), kennung: "karte-frist", aus: !beschaeftigt.isEmpty) { iso in
                laufe("frist") { try await KartenAktion.setzeLabel(store, c.id, praefix: "frist", wert: iso) } } }
        }
    }

    private func zeile<I: View>(_ t: String, @ViewBuilder _ inhalt: () -> I) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(t).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).frame(width: 84, alignment: .leading)
            inhalt()
            Spacer(minLength: 0)
        }
    }

    private func block<I: View>(_ t: String, zahl: Int = 0, @ViewBuilder rechts: () -> some View = { EmptyView() }, @ViewBuilder _ inhalt: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Abschnittstitel(text: t)
                if zahl > 0 { Text("\(zahl)").font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.ink3) }
                Spacer(minLength: 0)
                rechts()
            }
            inhalt()
        }
    }

    private func notizBlock(_ c: OvKarte) -> some View {
        block("Notiz", rechts: {
            if !bearbeiteNotiz {
                Button { notiz = c.notes ?? ""; bearbeiteNotiz = true } label: { Label("Bearbeiten", systemImage: "pencil") }
                    .buttonStyle(.plain).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.himmel).accessibilityIdentifier("notiz-bearbeiten")
            }
        }) {
            if bearbeiteNotiz {
                TextEditor(text: $notiz)
                    .font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1).scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(8).background(Farbe.feld, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Notiz").accessibilityIdentifier("notiz-feld")
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Abbrechen") { bearbeiteNotiz = false; notiz = c.notes ?? "" }.buttonStyle(KartenKnopfStil(leise: true))
                    Button("Speichern") {
                        let t = notiz
                        laufe("notes") { try await KartenAktion.speichereNotiz(store, c.id, t); bearbeiteNotiz = false }
                    }
                    .buttonStyle(NebenKnopfStil()).disabled(beschaeftigt == "notes").accessibilityIdentifier("notiz-speichern")
                }
            } else if let n = c.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SenecaTextView(text: n, live: false).accessibilityIdentifier("notiz-text")
            } else {
                Text("Noch keine Notiz. Schreib hinein, was das Ergebnis sein soll und woran man es erkennt.")
                    .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
            }
        }
    }

    private func nachweise(_ c: OvKarte) -> some View {
        block("Nachweise") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(c.nachweise, id: \.id) { x in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(x.status == "passed" ? Farbe.gruen : x.status == "failed" ? Farbe.koralle : Farbe.ink4).frame(width: 7, height: 7)
                        Text((x.label ?? "Nachweis") + (x.note.map { " · \($0)" } ?? "")).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink)
                        Spacer(minLength: 0)
                        Text(KartenAktion.beweisText[x.status] ?? x.status).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
                    }
                }
            }
        }
    }

    private func kommentare(_ c: OvKarte) -> some View {
        let alle = c.kommentare.sorted { $0.createdAt < $1.createdAt }
        return block("Kommentare", zahl: alle.count) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(alle.suffix(6).enumerated()), id: \.offset) { _, k in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.body).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink)
                        Text((k.author.map { $0 + " · " } ?? "") + Menschlich.vorText(k.createdAt, jetzt: store.jetzt)).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
                    }
                }
                if alle.count > 6 { Text("\(alle.count - 6) ältere Kommentare ausgeblendet.").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3) }
                HStack(spacing: 8) {
                    TextField("", text: $kommentar, prompt: Text("Kommentar schreiben …").foregroundStyle(Farbe.ink4))
                        .textFieldStyle(.plain).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink1)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Farbe.feld, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onSubmit { sende(c) }
                        .accessibilityLabel("Kommentar").accessibilityIdentifier("kommentar-feld")
                    Button("Senden") { sende(c) }.buttonStyle(NebenKnopfStil())
                        .disabled(kommentar.trimmingCharacters(in: .whitespaces).isEmpty || beschaeftigt == "komm").accessibilityIdentifier("kommentar-senden")
                }
            }
        }
    }

    private func sende(_ c: OvKarte) {
        let t = kommentar
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        beschaeftigt = "komm"
        Task { if await store.kommentiere(c.id, text: t) { kommentar = "" }; beschaeftigt = "" }
    }

    private func uebergabe(_ c: OvKarte) -> some View {
        let agenten = store.daten.agents.filter { $0.id != c.agentId }
        return block("Übergeben") {
            VStack(alignment: .leading, spacing: 8) {
                Text((c.agentId.map { "\(store.daten.label($0)) ist zuständig." } ?? "Die Aufgabe liegt bei dir.") + " Ein Agent bekommt den Auftrag aus der Notiz.")
                    .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                HStack(spacing: 10) {
                    if c.agentId == nil {
                        Picker("Agent", selection: $agent) {
                            Text("Agent wählen …").tag("")
                            ForEach(agenten, id: \.id) { Text(store.daten.label($0.id).isEmpty ? $0.id : store.daten.label($0.id)).tag($0.id) }
                        }
                        .labelsHidden().fixedSize().accessibilityIdentifier("uebergabe-agent")
                    }
                    Button(beschaeftigt == "start" ? "Übergebe …" : "An Agent übergeben") {
                        let a = agent
                        beschaeftigt = "start"; fehler = ""
                        Task { _ = await KartenAktion.uebergib(store, c.id, agent: a.isEmpty ? nil : a); beschaeftigt = "" }
                    }
                    .buttonStyle(NebenKnopfStil())
                    .disabled(!beschaeftigt.isEmpty || (c.agentId == nil && agent.isEmpty) || c.status == "running")
                    .accessibilityIdentifier("uebergabe-knopf")
                }
            }
        }
    }

    private func verlauf(_ c: OvKarte) -> some View {
        block("Verlauf") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(c.events.sorted { $0.at > $1.at }.prefix(8).enumerated()), id: \.offset) { _, e in
                    HStack {
                        Text(e.art == "created" ? "Angelegt" : e.nachStatus.map { "Nach „\(KartenAktion.statusName[$0] ?? $0)“ verschoben" } ?? "Geändert")
                            .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
                        Spacer(minLength: 0)
                        Text(Menschlich.vorText(e.at, jetzt: store.jetzt)).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
                    }
                }
            }
        }
    }

    private func fuss(_ c: OvKarte, _ p: HeuteLogik.ProjektInfo?) -> some View {
        let leiterName = p?.bereich?.leaderName ?? "Seneca"
        let vorlage = "Zur Aufgabe „\(Menschlich.klartext(c.title))“: "
        return VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Farbe.linie2)
            Button { modell.sprichMit(agentId: p?.leiter, bereichId: p?.bereichId, vorlage: vorlage) } label: {
                Label("Mit \(leiterName) darüber sprechen", systemImage: "bubble.left")
            }
            .buttonStyle(NebenKnopfStil()).accessibilityIdentifier("karte-sprechen")
            if c.sessionKey != nil, let a = c.agentId {
                Button("Mit \(store.daten.label(a)) sprechen") { modell.sprichMit(agentId: a, vorlage: vorlage) }
                    .buttonStyle(.plain).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.himmel)
            }
        }
    }
}

struct TagFeld: View {
    var wert: Double?
    var kennung: String
    var aus: Bool
    var setze: (String?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let w = wert {
                DatePicker("", selection: Binding(get: { Date(timeIntervalSince1970: w / 1000) }, set: { d in
                    let iso = Menschlich.isoTag(d.timeIntervalSince1970 * 1000)
                    if iso != Menschlich.isoTag(w) { setze(iso) }
                }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).disabled(aus).accessibilityIdentifier(kennung)
                Button { setze(nil) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Farbe.ink4) }
                    .buttonStyle(.plain).disabled(aus).help("Entfernen").accessibilityLabel("Entfernen")
            } else {
                Button("Festlegen") { setze(Menschlich.isoTag(Date().timeIntervalSince1970 * 1000)) }
                    .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.himmel).disabled(aus)
                    .accessibilityIdentifier(kennung + "-festlegen")
            }
        }
    }
}
