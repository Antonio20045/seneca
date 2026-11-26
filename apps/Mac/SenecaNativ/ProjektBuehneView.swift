import SwiftUI

struct PrognoseDiagramm: View {
    var e: Prognose.Ergebnis

    private var fristFarbe: Color {
        switch e.urteil {
        case .passtNicht: return Farbe.koralle
        case .knapp: return Farbe.bernstein
        default: return Farbe.ink3
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let links: CGFloat = 8, rechts: CGFloat = 8, oben: CGFloat = 20, unten: CGFloat = 22
            let x0 = e.start
            var x1 = max(e.heute, e.fertigAm ?? e.heute, e.frist ?? e.heute)
            if x1 <= x0 { x1 = x0 + Prognose.tag }
            let gesamt = Double(max(e.gesamt, 1))
            func x(_ t: Double) -> CGFloat { links + CGFloat((t - x0) / (x1 - x0)) * (size.width - links - rechts) }
            func y(_ n: Double) -> CGFloat { oben + (1 - CGFloat(n / gesamt)) * (size.height - oben - unten) }
            let strich = StrokeStyle(lineWidth: 1, dash: [4, 4])

            var oberKante = Path(); oberKante.move(to: CGPoint(x: links, y: y(gesamt))); oberKante.addLine(to: CGPoint(x: size.width - rechts, y: y(gesamt)))
            ctx.stroke(oberKante, with: .color(Farbe.ink4), style: strich)
            ctx.draw(Text("\(e.gesamt) Aufgaben").font(Schrift.grotesk(10.5)).foregroundStyle(Farbe.ink3), at: CGPoint(x: links, y: y(gesamt) - 8), anchor: .leading)

            if let f = e.frist, f >= x0 {
                var l = Path(); l.move(to: CGPoint(x: x(f), y: oben - 4)); l.addLine(to: CGPoint(x: x(f), y: size.height - unten))
                ctx.stroke(l, with: .color(fristFarbe), style: StrokeStyle(lineWidth: 1.5))
                ctx.draw(Text("Frist \(Menschlich.datumKurz(f))").font(Schrift.grotesk(10.5)).foregroundStyle(fristFarbe),
                         at: CGPoint(x: min(x(f), size.width - rechts), y: size.height - 8), anchor: x(f) > size.width - 70 ? .trailing : .center)
            }

            if e.zustand == .berechnet, let fa = e.fertigAm, let jetzt = e.reihe.last {
                var h = Path(); h.move(to: CGPoint(x: x(e.heute), y: y(Double(jetzt.fertig)))); h.addLine(to: CGPoint(x: x(fa), y: y(gesamt)))
                ctx.stroke(h, with: .color(Farbe.himmel), style: strich)
            }

            var treppe = Path()
            for (i, pt) in e.reihe.enumerated() {
                let p = CGPoint(x: x(pt.tag), y: y(Double(pt.fertig)))
                if i == 0 { treppe.move(to: p) } else {
                    treppe.addLine(to: CGPoint(x: p.x, y: y(Double(e.reihe[i - 1].fertig))))
                    treppe.addLine(to: p)
                }
            }
            ctx.stroke(treppe, with: .color(Farbe.ink1), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let l = e.reihe.last {
                let p = CGPoint(x: x(e.heute), y: y(Double(l.fertig)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(Farbe.ink1))
            }
            ctx.draw(Text(Menschlich.datumKurz(e.start)).font(Schrift.grotesk(10.5)).foregroundStyle(Farbe.ink3), at: CGPoint(x: links, y: size.height - 8), anchor: .leading)
            ctx.draw(Text("heute").font(Schrift.grotesk(10.5)).foregroundStyle(Farbe.ink2), at: CGPoint(x: x(e.heute), y: size.height - 8), anchor: .center)
        }
        .aspectRatio(560.0 / 150.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diagramm: erledigte Aufgaben der letzten vierzehn Tage")
        .accessibilityIdentifier("prognose-diagramm")
    }
}

struct VeraltetMarke: View {
    var hinweis: String
    var body: some View {
        Text("veraltet").font(Schrift.grotesk(12, .medium)).foregroundStyle(Farbe.bernstein)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Farbe.bernstein.opacity(0.45), lineWidth: 1))
            .help(hinweis)
            .accessibilityLabel("veraltet")
    }
}

struct ProjektBuehneView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var rand: CGFloat

    init(modell: AppModell, rand: CGFloat) {
        self.modell = modell
        self.store = modell.uebersicht
        self.rand = rand
    }

    @State private var zielBearbeiten = false
    @State private var zielText = ""
    @State private var einordnen = false
    @State private var bereichWahl = ""
    @State private var abteilungWahl = ""
    @State private var stand: String?
    @State private var standGeladen = false

    static func ohneFertigWenn(_ t: String) -> String {
        let r = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = Muster.erster(r, #"^fertig,?\s+wenn\s+"#, gross: true), let k = m[0] else { return r }
        return String(r.dropFirst(k.count))
    }

    private var projektId: String { modell.route.id ?? "" }
    private var tab: String { modell.route.tab ?? "board" }
    private var kartenId: String? { modell.route.q["karte"].flatMap { $0.isEmpty ? nil : $0 } }
    private var reiter: String { ["entscheidungen", "nachweise", "verlauf", "notizen"].contains(tab) ? tab : "aufgaben" }

    var body: some View {
        if let p = store.projekte.first(where: { $0.id == projektId }) {
            buehne(p)
                .task(id: projektId) { await store.ladePlaene([p], maxAlter: 20_000) }
                .task(id: kartenId ?? "") { zeigeKarte(kartenId, in: p) }
                .onDisappear { if modell.ansichten.zeigtProjektKarte { modell.ansichten.schliesse() } }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nicht gefunden").font(Schrift.serif(26)).foregroundStyle(Farbe.ink1)
                Text("Dieses Projekt gibt es nicht (mehr).").font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink2)
                Button("Alle Bereiche") { modell.gehe(.bereiche) }.buttonStyle(NebenKnopfStil()).accessibilityIdentifier("buehne-alle-bereiche")
            }
            .padding(.horizontal, rand).padding(.top, 30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("seite-projekt-fehlt")
        }
    }

    private func zeigeKarte(_ id: String?, in p: HeuteLogik.ProjektInfo) {
        let a = modell.ansichten
        if let id {
            let titel = store.aktuell(id)?.title ?? "Aufgabe"
            if case .projektKarte(let alt, _)? = a.panel, alt == id { return }
            a.ersetze(.projektKarte(id: id, titel: titel))
        } else if a.zeigtProjektKarte { a.schliesse() }
    }

    private func buehne(_ p: HeuteLogik.ProjektInfo) -> some View {
        GeometryReader { g in
            let breit = g.size.width >= 820
            if breit {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { links(p).padding(.leading, rand).padding(.trailing, 26).padding(.vertical, 24) }
                        .frame(width: g.size.width * 0.42)
                    ScrollView { rechts(p).padding(.leading, 26).padding(.trailing, min(rand, 40)).padding(.vertical, 24) }
                        .overlay(alignment: .leading) { Rectangle().fill(Farbe.linie2).frame(width: 1) }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) { links(p); rechts(p) }
                        .padding(.horizontal, rand).padding(.vertical, 24)
                }
            }
        }
        .accessibilityIdentifier("seite-projekt")
    }

    private func leiterName(_ p: HeuteLogik.ProjektInfo) -> String {
        let n = p.bereich?.leaderName ?? ""
        return n.isEmpty ? (p.leiter.map { store.daten.label($0) } ?? "") : n
    }

    private func sprich(_ p: HeuteLogik.ProjektInfo, _ vorlage: String) {
        modell.sprichMit(agentId: p.leiter ?? p.projekt.agent, bereichId: p.bereichId.isEmpty ? nil : p.bereichId, vorlage: vorlage)
    }

    private func abschnitt<I: View>(_ titel: String, kennung: String, @ViewBuilder rechts: () -> some View = { EmptyView() }, @ViewBuilder _ inhalt: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(titel).font(Schrift.serif(22)).foregroundStyle(Farbe.ink1)
                rechts()
                Spacer(minLength: 0)
            }
            inhalt()
        }
        .padding(.top, 26)
        .accessibilityIdentifier(kennung)
    }

    private func links(_ p: HeuteLogik.ProjektInfo) -> some View {
        let ps = store.plaene[p.id]
        let plan = ps?.inhalt
        let fr = Frische.plan(geaendertAm: ps?.geaendertAm, offen: p.offenA.count, jetzt: store.jetzt)
        let ziel = (ps?.kurz?.ziel ?? p.ziel).trimmingCharacters(in: .whitespacesAndNewlines)
        let ergebnis = Prognose.berechne(p.aufgaben.map(Prognose.Karte.init), jetzt: store.jetzt, frist: PM.fristMs(p, plan: ps?.kurz))
        let frist = PM.fristMs(p, plan: ps?.kurz)
        let leiter = leiterName(p)
        let planVeraltet = ps?.vorhanden == true && fr.veraltet
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GesundheitsPunkt(g: p.health, grund: p.grund)
                Text(([p.bereich?.name, p.name].compactMap { $0 }.filter { !$0.isEmpty }.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }.joined(separator: " · ")) + (leiter.isEmpty ? "" : " · zuständig \(leiter)"))
                    .font(Schrift.grotesk(12.5, .medium)).tracking(0.6).foregroundStyle(Farbe.ink3).lineLimit(2)
                Spacer(minLength: 0)
            }
            Text(p.name).font(Schrift.serif(34)).foregroundStyle(Farbe.ink1).padding(.top, 8).accessibilityIdentifier("buehne-name")
            if !leiter.isEmpty {
                Button("Mit \(leiter) sprechen") { sprich(p, "Zum Projekt „\(p.name)“: ") }
                    .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.himmel).padding(.top, 4)
                    .accessibilityIdentifier("buehne-sprechen")
            }
            zielBlock(p, ziel: ziel, leiter: leiter)
            if let fw = plan?.fertig, !fw.isEmpty {
                Text("Fertig, wenn \(Self.ohneFertigWenn(fw))").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2).padding(.top, 8)
            }
            FlussZeile(abstand: 10) {
                if let f = frist {
                    let ueber = f < Menschlich.tagStart(store.jetzt)
                    Text("Frist \(Menschlich.datumLang(f))").foregroundStyle(ueber ? Farbe.koralle : Farbe.ink2).accessibilityIdentifier("buehne-frist")
                    if planVeraltet { VeraltetMarke(hinweis: "Der Plan wurde zuletzt \(fr.text.lowercased()). Die Frist stammt aus dem Plan und kann überholt sein.").accessibilityIdentifier("frist-veraltet") }
                } else {
                    Text("ohne Frist").foregroundStyle(Farbe.ink3).accessibilityIdentifier("buehne-frist")
                }
                if let b = plan?.budget, !b.isEmpty { Text("Budget \(b)").foregroundStyle(Farbe.ink3) }
            }
            .font(Schrift.grotesk(14)).padding(.top, 10)

            prognose(p, ergebnis, veraltet: planVeraltet, fr: fr)
            etappen(p, ps, plan: plan, fr: fr)
            risiko(p, ergebnis)
            vonDir(p)
            geradePassiert(p)
            einordnung(p)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zielBlock(_ p: HeuteLogik.ProjektInfo, ziel: String, leiter: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if zielBearbeiten {
                TextEditor(text: $zielText).font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink1).scrollContentBackground(.hidden)
                    .frame(minHeight: 70).padding(8).background(Farbe.feld, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Ziel").accessibilityIdentifier("ziel-feld")
                HStack(spacing: 8) {
                    Button("Speichern") { speichereZiel(p) }.buttonStyle(NebenKnopfStil()).accessibilityIdentifier("ziel-speichern")
                    Button("Abbrechen") { zielBearbeiten = false }.buttonStyle(KartenKnopfStil(leise: true))
                }
            } else if ziel.isEmpty {
                HStack(spacing: 6) {
                    Text("Ziel fehlt noch.").foregroundStyle(Farbe.ink3)
                    Button("Selbst festlegen") { zielText = ""; zielBearbeiten = true }.buttonStyle(.plain).foregroundStyle(Farbe.himmel)
                        .accessibilityIdentifier("ziel-selbst")
                    if !leiter.isEmpty {
                        Text("·").foregroundStyle(Farbe.ink4)
                        Button("Mit \(leiter) festlegen") { sprich(p, "Lass uns das Ziel für das Projekt „\(p.name)“ festlegen.") }.buttonStyle(.plain).foregroundStyle(Farbe.himmel)
                    }
                }
                .font(Schrift.grotesk(14))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ziel).font(Schrift.serif(20)).foregroundStyle(Farbe.ink).accessibilityIdentifier("buehne-ziel")
                    Button { zielText = ziel; zielBearbeiten = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain).foregroundStyle(Farbe.ink3).help("Ziel ändern").accessibilityLabel("Ziel ändern")
                }
            }
        }
        .padding(.top, 14)
    }

    private func speichereZiel(_ p: HeuteLogik.ProjektInfo) {
        let t = zielText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await store.speichereProjekt(p.id, felder: ["bereichId": p.bereichId, "abteilung": p.abteilung, "ziel": t]) {
                zielBearbeiten = false
                _ = store.hinweis("Ziel gespeichert")
            }
        }
    }

    private func prognose(_ p: HeuteLogik.ProjektInfo, _ e: Prognose.Ergebnis, veraltet: Bool, fr: Frische.Stand) -> some View {
        abschnitt("Prognose", kennung: "buehne-prognose", rechts: {
            if veraltet { VeraltetMarke(hinweis: "Die Frist, mit der gerechnet wird, steht in einem Plan, der \(fr.text.lowercased()) ist.").accessibilityIdentifier("prognose-veraltet") }
        }) {
            if e.zustand == .berechnet || e.erledigt14 > 0 { PrognoseDiagramm(e: e) }
            Text(Prognose.satz(e)).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2).accessibilityIdentifier("prognose-satz")
            if let z = p.aufgaben.compactMap({ $0.updatedAt }).max() {
                Text("Karten zuletzt geändert \(Menschlich.vorText(z, jetzt: store.jetzt))").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            }
        }
    }

    private func etappen(_ p: HeuteLogik.ProjektInfo, _ ps: PlanStand?, plan: Plan.Inhalt?, fr: Frische.Stand) -> some View {
        abschnitt("Etappen", kennung: "buehne-etappen", rechts: {
            if ps?.vorhanden == true {
                Text(fr.text).font(Schrift.grotesk(13)).foregroundStyle(fr.veraltet ? Farbe.bernstein : Farbe.ink3).accessibilityIdentifier("etappen-frische")
            }
        }) {
            if ps == nil {
                Text("Lade den Plan …").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3)
            } else if let plan {
                if plan.freigabe == .offen {
                    HStack(spacing: 10) {
                        Text("Der Plan wartet auf deine Freigabe.").foregroundStyle(Farbe.bernstein)
                        Button("Plan freigeben") { sprich(p, "Plan für \(p.name) ist freigegeben.") }.buttonStyle(NebenKnopfStil())
                            .accessibilityIdentifier("plan-freigeben")
                    }.font(Schrift.grotesk(14))
                } else if plan.freigabe == .erteilt {
                    Text("Plan ist freigegeben.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.gruen)
                }
                ForEach(Array(plan.teile.enumerated()), id: \.offset) { _, t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(Schrift.grotesk(15, .medium)).foregroundStyle(Farbe.ink1)
                        Text(([t.zustandText] + (t.wer.map { [$0] } ?? []) + (t.fertigWenn.map { ["fertig, wenn \(Self.ohneFertigWenn($0))"] } ?? [])).joined(separator: " · "))
                            .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                    }
                }
                if let s = plan.stand, !s.isEmpty { Text(s).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2) }
                let bloecke = p.offenA.filter { Menschlich.planVon($0.labels).map { $0 >= Menschlich.tagStart(store.jetzt) } ?? false }
                    .sorted { (Menschlich.planVon($0.labels) ?? 0) < (Menschlich.planVon($1.labels) ?? 0) }.prefix(4)
                if !bloecke.isEmpty {
                    Abschnittstitel(text: "Deine nächsten Blöcke").padding(.top, 6)
                    ForEach(Array(bloecke), id: \.id) { c in
                        Button { modell.oeffneProjekt(p.id, karte: c.id, tab: modell.route.tab ?? "board") } label: {
                            Text("\(Menschlich.tagText(Menschlich.planVon(c.labels) ?? 0, jetzt: store.jetzt)) · \(c.title)").font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink)
                        }.buttonStyle(.plain)
                    }
                }
                if !plan.offen.isEmpty {
                    Abschnittstitel(text: "Noch offen").padding(.top, 6)
                    ForEach(plan.offen, id: \.self) { o in Text("· \(o)").font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2) }
                }
            } else {
                Text("Noch kein Plan.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3)
                let leiter = leiterName(p)
                if !leiter.isEmpty {
                    let pfad = Plan.anfrage(bereichId: p.bereichId.isEmpty ? nil : p.bereichId, boardId: p.id).pfad
                    Button("\(leiter) um einen Plan bitten") {
                        sprich(p, "Bitte erstelle einen Plan für das Projekt „\(p.name)“: Etappen mit Zuständigem und „fertig, wenn …“, Frist und Budget. Lege ihn als Codeblock seneca-plan in \(pfad) ab.")
                    }.buttonStyle(NebenKnopfStil()).accessibilityIdentifier("plan-bitten")
                }
            }
        }
    }

    private func risiko(_ p: HeuteLogik.ProjektInfo, _ e: Prognose.Ergebnis) -> some View {
        let r = PM.projektRisiken(p, rows: store.daten.rows, jobs: store.daten.jobs, jetzt: store.jetzt, prognose: e)
        return abschnitt("Risiko", kennung: "buehne-risiko") {
            if r.isEmpty {
                Text("In den Daten ist nichts Auffälliges: keine fehlgeschlagenen Läufe, keine Blockade, keine Aufgabe ohne Bewegung.")
                    .font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3)
            } else {
                ForEach(Array(r.enumerated()), id: \.offset) { _, x in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(x.stufe == .hoch ? Farbe.koralle : Farbe.bernstein).frame(width: 7, height: 7)
                        Text(x.text).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink)
                    }
                }
            }
        }
    }

    private func vonDir(_ p: HeuteLogik.ProjektInfo) -> some View {
        abschnitt("Von dir", kennung: "buehne-von-dir") {
            if p.ents.isEmpty && p.pruefung.isEmpty {
                Text("Nichts, was gerade auf dich wartet.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3)
            }
            ForEach(p.ents, id: \.id) { e in
                VStack(alignment: .leading, spacing: 6) {
                    Text(e.frage).font(Schrift.grotesk(14.5, .medium)).foregroundStyle(Farbe.ink1)
                    FlussZeile(abstand: 6) {
                        ForEach(e.optionen, id: \.key) { o in
                            Button(o.titel) { store.entscheide(e, Entscheiden.Wahl(wahl: o.key)) }.buttonStyle(NebenKnopfStil())
                        }
                    }
                }
            }
            ForEach(p.pruefung, id: \.id) { c in
                HStack(spacing: 10) {
                    Text("„\(Menschlich.kuerzen(Menschlich.klartext(c.title), 60))“ wartet auf deine Prüfung.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink)
                    Spacer(minLength: 0)
                    Button("Prüfen") { modell.oeffneProjekt(p.id, karte: c.id, tab: modell.route.tab ?? "board") }.buttonStyle(NebenKnopfStil())
                        .accessibilityIdentifier("pruefen-\(c.id)")
                }
            }
        }
    }

    private func geradePassiert(_ p: HeuteLogik.ProjektInfo) -> some View {
        let l = p.offenA.filter { $0.status == "running" }
        return Group {
            if !l.isEmpty {
                abschnitt("Gerade passiert", kennung: "buehne-gerade") {
                    ForEach(l, id: \.id) { c in
                        let wer = c.agentId.map { store.daten.label($0) }
                        let seit = PM.statusSeit(c, "running").map { " · \(Menschlich.seitText($0, jetzt: store.jetzt))" } ?? ""
                        Text(wer.map { "\($0) arbeitet an „\(c.title)“" } .map { $0 + seit } ?? "Du bearbeitest „\(c.title)“" + seit)
                            .font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink)
                    }
                }
            }
        }
    }

    private func einordnung(_ p: HeuteLogik.ProjektInfo) -> some View {
        let bereiche = store.bereicheNamen
        return VStack(alignment: .leading, spacing: 8) {
            Button { bereichWahl = p.bereichId; abteilungWahl = p.abteilung; einordnen.toggle() } label: {
                Text("Einordnung ändern").font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.himmel)
            }.buttonStyle(.plain).accessibilityIdentifier("einordnung-aendern")
            if einordnen {
                HStack(spacing: 10) {
                    Picker("Bereich", selection: $bereichWahl) {
                        Text("Ohne Bereich").tag("")
                        ForEach(bereiche, id: \.id) { Text($0.name).tag($0.id) }
                    }.labelsHidden().fixedSize()
                    TextField("", text: $abteilungWahl, prompt: Text("Abteilung").foregroundStyle(Farbe.ink4))
                        .textFieldStyle(.plain).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink1)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Farbe.feld, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button("Speichern") {
                        Task {
                            if await store.speichereProjekt(p.id, felder: ["bereichId": bereichWahl, "abteilung": abteilungWahl, "ziel": p.ziel]) {
                                einordnen = false; _ = store.hinweis("Einordnung gespeichert")
                            }
                        }
                    }.buttonStyle(NebenKnopfStil())
                }
            }
        }
        .padding(.top, 26)
    }

    private func rechts(_ p: HeuteLogik.ProjektInfo) -> some View {
        let ents = store.daten.cards.filter { $0.boardId == p.id && !$0.archiviert && HeuteLogik.istEntscheidung($0) }
        let mitBeleg = p.aufgaben.filter { !$0.nachweise.isEmpty }
        let letzte = p.aufgaben.compactMap { $0.updatedAt }.max()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ReiterKnopf(titel: "Aufgaben", aktiv: reiter == "aufgaben", kennung: "reiter-aufgaben") { waehle("board") }
                ReiterKnopf(titel: "Entscheidungen", aktiv: reiter == "entscheidungen", anzahl: p.ents.count, kennung: "reiter-entscheidungen") { waehle("entscheidungen") }
                ReiterKnopf(titel: "Nachweise", aktiv: reiter == "nachweise", kennung: "reiter-nachweise") { waehle("nachweise") }
                ReiterKnopf(titel: "Verlauf", aktiv: reiter == "verlauf", kennung: "reiter-verlauf") { waehle("verlauf") }
                ReiterKnopf(titel: "Notizen", aktiv: reiter == "notizen", kennung: "reiter-notizen") { waehle("notizen") }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Farbe.linie2).frame(height: 1) }
            switch reiter {
            case "entscheidungen": entscheidungenTab(p, karten: ents)
            case "nachweise": nachweiseTab(p, karten: mitBeleg)
            case "verlauf": verlaufTab(p)
            case "notizen": notizenTab(p)
            default:
                HStack(spacing: 12) {
                    Picker("Ansicht", selection: Binding(get: { tab == "liste" ? "liste" : "board" }, set: { waehle($0) })) {
                        Text("Board").tag("board"); Text("Liste").tag("liste")
                    }.labelsHidden().pickerStyle(.segmented).fixedSize().accessibilityIdentifier("ansicht-umschalter")
                    Spacer(minLength: 0)
                    if let l = letzte { Text("letzte Änderung \(Menschlich.vorText(l, jetzt: store.jetzt))").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3) }
                }
                if tab == "liste" { KartenListeView(modell: modell, store: store, p: p, offeneKarte: kartenId) }
                else { BoardView(modell: modell, store: store, p: p, offeneKarte: kartenId) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func waehle(_ t: String) {
        var q = modell.route.q
        if t != "board" && t != "liste" { q["karte"] = nil }
        modell.gehe(Route(.projekt, id: projektId, tab: t, q: q))
    }

    private func leer(_ t: String) -> some View { Text(t).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3) }

    private func entscheidungenTab(_ p: HeuteLogik.ProjektInfo, karten: [OvKarte]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if p.ents.isEmpty && karten.isEmpty { leer("Keine Entscheidungen in diesem Projekt.") }
            ForEach(p.ents, id: \.id) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.frage).font(Schrift.grotesk(15, .medium)).foregroundStyle(Farbe.ink1)
                    if let k = e.kurz { Text(k).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2) }
                    Text("offen seit \(Menschlich.vorText(e.gestelltAm, jetzt: store.jetzt))").font(Schrift.grotesk(12)).foregroundStyle(Farbe.bernstein)
                }
            }
            let erledigt = karten.filter { $0.status == "done" }
            if !erledigt.isEmpty {
                Abschnittstitel(text: "Entschieden")
                ForEach(erledigt, id: \.id) { c in Text(Menschlich.klartext(c.title)).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2) }
            }
        }
        .accessibilityIdentifier("tab-entscheidungen")
    }

    private func nachweiseTab(_ p: HeuteLogik.ProjektInfo, karten: [OvKarte]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if karten.isEmpty { leer("Noch keine Nachweise. Sie erscheinen hier, sobald ein Agent an einer Aufgabe Belege ablegt (Tests, Links, Notizen).") }
            ForEach(karten, id: \.id) { c in
                VStack(alignment: .leading, spacing: 5) {
                    Button { modell.oeffneProjekt(p.id, karte: c.id, tab: "nachweise") } label: {
                        Text(Menschlich.klartext(c.title)).font(Schrift.grotesk(15, .medium)).foregroundStyle(Farbe.ink1)
                    }.buttonStyle(.plain)
                    ForEach(c.nachweise, id: \.id) { x in
                        HStack(spacing: 8) {
                            Circle().fill(x.status == "passed" ? Farbe.gruen : x.status == "failed" ? Farbe.koralle : Farbe.ink4).frame(width: 7, height: 7)
                            Text((x.label ?? "Nachweis") + (x.note.map { " · \($0)" } ?? "")).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
                            Spacer(minLength: 0)
                            Text(KartenAktion.beweisText[x.status] ?? x.status).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("tab-nachweise")
    }

    private struct Eintrag { var at: Double; var text: String; var karte: String }

    private func verlaufTab(_ p: HeuteLogik.ProjektInfo) -> some View {
        var l: [Eintrag] = []
        for c in p.aufgaben {
            let t = Menschlich.klartext(c.title)
            for e in c.events where e.art != "diagnostic" {
                let was = e.art == "created" ? "angelegt" : e.nachStatus.map { "nach „\(KartenAktion.statusName[$0] ?? $0)“ verschoben" } ?? "geändert"
                l.append(Eintrag(at: e.at, text: "„\(t)“ \(was)", karte: c.id))
            }
            for k in c.kommentare { l.append(Eintrag(at: k.createdAt, text: "Kommentar zu „\(t)“: \(Menschlich.kuerzen(k.body, 80))", karte: c.id)) }
        }
        let sortiert = l.sorted { $0.at > $1.at }.prefix(60)
        var gruppen: [(tag: String, liste: [Eintrag])] = []
        for e in sortiert {
            let t = Menschlich.datumLang(e.at)
            if gruppen.last?.tag == t { gruppen[gruppen.count - 1].liste.append(e) } else { gruppen.append((t, [e])) }
        }
        return VStack(alignment: .leading, spacing: 14) {
            if gruppen.isEmpty { leer("Noch kein Verlauf.") }
            ForEach(Array(gruppen.enumerated()), id: \.offset) { _, g in
                VStack(alignment: .leading, spacing: 6) {
                    Abschnittstitel(text: g.tag)
                    ForEach(Array(g.liste.enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Menschlich.hhmm(e.at)).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).monospacedDigit().frame(width: 40, alignment: .leading)
                            Button { modell.oeffneProjekt(p.id, karte: e.karte, tab: "verlauf") } label: {
                                Text(e.text).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2).multilineTextAlignment(.leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("tab-verlauf")
    }

    private func notizenTab(_ p: HeuteLogik.ProjektInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if p.bereichId.isEmpty {
                leer("Dieses Projekt gehört zu keinem Bereich, also gibt es keine Bereichsnotizen.")
            } else if !standGeladen {
                leer("Lade die Notizen …")
            } else if let s = stand, !s.isEmpty {
                Text("Bereichsnotizen (nur lesen)").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
                SenecaTextView(text: s, live: false)
            } else {
                leer("Für diesen Bereich liegen noch keine Notizen vor.")
            }
        }
        .task(id: p.bereichId) {
            standGeladen = false; stand = nil
            if !p.bereichId.isEmpty {
                stand = await store.leseDatei("~/Bereiche/\(p.bereichId)/STAND.md")
                if stand == nil { stand = await store.leseDatei("~/Bereiche/\(p.bereichId)/BEREICH.md") }
            }
            standGeladen = true
        }
        .accessibilityIdentifier("tab-notizen")
    }
}
