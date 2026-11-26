import SwiftUI

@MainActor private func bereichsNamen(_ store: OverviewStore) -> BereicheUebersicht.Namen {
    let areas = store.daten.bereiche?.areas ?? []
    return BereicheUebersicht.Namen(bereichName: { agent in
        areas.first { $0.leader == agent || $0.specialists.contains(agent) }.map { $0.name.isEmpty ? $0.id : $0.name } ?? ""
    })
}

private struct RuhigerSatz: View {
    var text: String
    var kennung: String
    var body: some View {
        Text(text).font(Schrift.serif(20, kursiv: true)).foregroundStyle(Farbe.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(kennung)
    }
}

struct BereicheView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var rand: CGFloat

    init(modell: AppModell, rand: CGFloat) {
        self.modell = modell
        self.store = modell.uebersicht
        self.rand = rand
    }

    private var verlaufAn: Bool { modell.route.q["ansicht"] == "verlauf" }

    var body: some View {
        let bereiche = store.daten.bereiche?.areas ?? []
        let zeilen = BereicheUebersicht.listenZeilen(bereiche: bereiche, projekte: store.projekte)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(BereicheUebersicht.kopfzeile(zeilen: bereiche.count, geladen: store.daten.geladen))
                    .font(Schrift.serif(30)).foregroundStyle(Farbe.ink1)
                    .accessibilityIdentifier("bereiche-kopf")
                Spacer(minLength: 8)
            }
            HStack(spacing: 4) {
                ReiterKnopf(titel: "Bereiche", aktiv: !verlaufAn, kennung: "reiter-bereiche") { modell.gehe(Route(.bereiche, q: modell.route.q.filter { $0.key == "bereich" })) }
                ReiterKnopf(titel: "Verlauf", aktiv: verlaufAn, kennung: "reiter-verlauf") { modell.gehe(Route(.bereiche, q: ["ansicht": "verlauf"])) }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Farbe.linie2).frame(height: 1) }
            .padding(.top, 16)
            Group {
                if verlaufAn {
                    TatenVerlaufView(modell: modell, store: store)
                } else if zeilen.isEmpty {
                    RuhigerSatz(text: "Es gibt noch keine Bereiche. Sobald Seneca einen anlegt, erscheint er hier mit seinen Projekten.", kennung: "bereiche-leer")
                        .padding(.top, 28)
                } else {
                    BereicheListeUndProjekte(modell: modell, store: store, bereiche: bereiche, zeilen: zeilen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, rand).padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("seite-bereiche")
    }
}

private struct BereicheListeUndProjekte: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var bereiche: [Area]
    var zeilen: [BereicheUebersicht.ListenZeile]

    private var gewaehlt: String { BereicheUebersicht.wahl([modell.route.q["bereich"] ?? ""], zeilen: zeilen) }

    private func fragen(_ id: String, _ projekte: [HeuteLogik.ProjektInfo]) -> Int {
        id == BereicheUebersicht.ohneBereich
            ? projekte.reduce(0) { $0 + $1.ents.filter { !$0.ruhend }.count }
            : store.entscheidungen.filter { $0.bereichId == id && !$0.ruhend }.count
    }

    var body: some View {
        let alle = store.projekte
        HStack(alignment: .top, spacing: 28) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(zeilen.enumerated()), id: \.element.id) { i, z in
                        BereichsKarte(modell: modell, store: store, zeile: z, aktiv: z.id == gewaehlt,
                                      fragen: fragen(z.id, BereicheUebersicht.projekteVon(z.id, bereiche: bereiche, projekte: alle)))
                            .bkRein(i)
                    }
                }
                .padding(.vertical, 22)
            }
            .frame(width: 340)
            ScrollView {
                BereichProjekte(modell: modell, store: store, bereiche: bereiche, zeile: zeilen.first { $0.id == gewaehlt })
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: alle.map(\.id)) { await store.ladePlaene(alle) }
    }
}

private struct BereichsKarte: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var zeile: BereicheUebersicht.ListenZeile
    var aktiv: Bool
    var fragen: Int
    @State private var darueber = false

    var body: some View {
        let satz = BereicheUebersicht.kurzSatz(zeile.bereich?.summary.lines ?? [])
        let karten = store.projekte.filter { $0.bereichId == zeile.id }.flatMap(\.aufgaben)
        let frische = zeile.bereich.map {
            Frische.kurzstand(geaendertAm: $0.summary.changedAt, letzteKartenaenderung: karten.compactMap(\.updatedAt).max() ?? 0, jetzt: store.jetzt)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(zeile.name).font(Schrift.grotesk(16.5, .medium)).foregroundStyle(Farbe.ink1).lineLimit(1)
            if zeile.bereich == nil {
                Text("Projekte, die zu keinem Bereich gehören.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
            } else if satz.isEmpty {
                Text("Noch kein Kurzstand.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
            } else {
                Text(satz).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).lineLimit(3).multilineTextAlignment(.leading)
            }
            HStack(spacing: 10) {
                if let f = frische {
                    Text(f.text).foregroundStyle(f.veraltet ? Farbe.bernstein : Farbe.ink3)
                        .accessibilityIdentifier("bereich-frische-\(zeile.id)")
                }
                if fragen > 0 {
                    Text(BereicheUebersicht.frageText(fragen)).foregroundStyle(Farbe.bernstein)
                        .accessibilityIdentifier("bereich-fragen-\(zeile.id)")
                }
            }
            .font(Schrift.grotesk(12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(aktiv ? Farbe.himmelFlaeche : (darueber ? Farbe.flaeche2 : Farbe.flaeche), in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(aktiv ? Farbe.himmel.opacity(0.4) : Farbe.linie2, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { modell.gehe(Route(.bereiche, q: ["bereich": zeile.id])) }
        .onTapGesture(count: 2) { if zeile.bereich != nil { modell.gehe(Route(.bereich, id: zeile.id)) } }
        .onHover { darueber = $0 }
        .animation(Kurve.ease(), value: aktiv)
        .animation(Kurve.ease(), value: darueber)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("bereich-\(zeile.id)")
    }
}

struct BereichProjekte: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var bereiche: [Area]
    var zeile: BereicheUebersicht.ListenZeile?

    var body: some View {
        if let z = zeile {
            let liste = BereicheUebersicht.projekteVon(z.id, bereiche: bereiche, projekte: store.projekte)
            let vorrat = liste.filter { PM.istVorrat($0) }
            let echte = liste.filter { !PM.istVorrat($0) }
            let offen = echte.first { !$0.offenA.isEmpty }?.id
            VStack(alignment: .leading, spacing: 12) {
                Text("\(z.name) · \(echte.count) \(echte.count == 1 ? "Projekt" : "Projekte"), \(vorrat.count) Vorrat")
                    .font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.ink3)
                    .accessibilityIdentifier("bereich-projekte-kopf")
                if liste.isEmpty {
                    RuhigerSatz(text: "In diesem Bereich läuft noch kein Projekt.", kennung: "bereich-ohne-projekt")
                }
                ForEach(echte, id: \.id) { p in
                    BereichsProjektZeile(modell: modell, store: store, p: p, aufgeklappt: p.id == offen)
                }
                ForEach(vorrat, id: \.id) { p in VorratZeile(modell: modell, p: p) }
                HStack(spacing: 10) {
                    if let b = z.bereich, !b.leader.isEmpty {
                        Button("Mit \(b.leaderName.isEmpty ? b.leader : b.leaderName) sprechen") {
                            modell.oeffneChat(key: "agent:\(b.leader):main", agentId: b.leader, bereich: b.id)
                        }
                        .buttonStyle(KartenKnopfStil(haupt: true))
                        .accessibilityIdentifier("bereich-sprechen")
                        Button("Bericht des Bereichs") { modell.gehe(Route(.bereich, id: b.id)) }
                            .buttonStyle(KartenKnopfStil(leise: true))
                            .accessibilityIdentifier("bereich-buehne")
                    }
                }
                .padding(.top, 8)
            }
            .id(z.id)
            .seiteEin()
        } else {
            RuhigerSatz(text: "Wähle links einen Bereich.", kennung: "bereich-waehlen")
        }
    }
}

private struct BereichsProjektZeile: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var p: HeuteLogik.ProjektInfo
    var aufgeklappt: Bool
    @State private var darueber = false

    var body: some View {
        let plan = store.plaene[p.id]?.kurz
        let ziel = (plan?.ziel ?? p.ziel).trimmingCharacters(in: .whitespacesAndNewlines)
        let frist = PM.fristMs(p, plan: plan)
        let weiter = plan?.naechster ?? p.naechster.map { Menschlich.klartext($0.title) } ?? ""
        let fragen = p.ents.filter { !$0.ruhend }.count
        Button { modell.oeffneProjekt(p.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    GesundheitsPunkt(g: p.health, grund: p.grund)
                    Text(p.name).font(Schrift.grotesk(16.5, .medium)).foregroundStyle(Farbe.ink1).lineLimit(1)
                    Spacer(minLength: 8)
                    if !aufgeklappt {
                        Text("\(p.offenA.count) offen").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                    }
                }
                if aufgeklappt {
                    ProjektBalken(fertig: p.fertigA.count, alle: p.aufgaben.count).padding(.vertical, 2)
                    Text("\(p.fertigA.count) von \(p.aufgaben.count) Aufgaben · \(frist.map { "Frist \(Menschlich.datumKurz($0))" } ?? "ohne Frist") · Aufgabenboard")
                        .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                    zeile("Ziel", ziel.isEmpty ? "noch keines" : ziel)
                    zeile("Zuständig", PM.werDran(p, label: { store.daten.label($0) }))
                    zeile("Als Nächstes", weiter.isEmpty ? "nichts geplant" : Menschlich.kuerzen(weiter, 90))
                    zeile("Von dir", fragen > 0 ? BereicheUebersicht.frageText(fragen) : "nichts offen")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13).padding(.horizontal, 16)
            .background(darueber ? Farbe.flaeche2 : Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(Farbe.linie2, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(Kurve.ease(), value: darueber)
        }
        .buttonStyle(.plain)
        .onHover { darueber = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bereich-projekt-\(p.id)")
    }

    private func zeile(_ titel: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titel).foregroundStyle(Farbe.ink3).frame(width: 84, alignment: .leading)
            Text(text).foregroundStyle(Farbe.ink).lineLimit(2).multilineTextAlignment(.leading)
        }
        .font(Schrift.grotesk(13))
    }
}

private struct VorratZeile: View {
    @ObservedObject var modell: AppModell
    var p: HeuteLogik.ProjektInfo

    var body: some View {
        let fragen = p.ents.filter { !$0.ruhend }.count
        Button { modell.oeffneProjekt(p.id) } label: {
            HStack(spacing: 10) {
                Text("Vorrat").font(Schrift.grotesk(11, .medium)).tracking(1.1).foregroundStyle(Farbe.ink3)
                Text(p.name).font(Schrift.grotesk(15, .medium)).foregroundStyle(Farbe.ink2).lineLimit(1)
                Text(p.offenA.isEmpty ? "nichts offen" : "\(p.offenA.count) offen").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                if fragen > 0 { Text(BereicheUebersicht.frageText(fragen)).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.bernstein) }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vorrat-\(p.id)")
    }
}

struct TatenVerlaufView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    @State private var anzahl = BereicheUebersicht.verlaufSeite

    var body: some View {
        let ov = store.daten
        let bereiche = ov.bereiche?.areas ?? []
        let alle = BereicheUebersicht.verlauf(
            cards: ov.cards, jobs: ov.jobs, label: { ov.label($0) },
            projekte: store.projekte.map { (id: $0.id, bereichId: $0.bereichId) },
            bereiche: bereiche.map { (id: $0.id, name: $0.name) },
            jetzt: store.jetzt, namen: bereichsNamen(store))
        let gruppen = BereicheUebersicht.verlaufGruppen(alle, anzahl: anzahl)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if alle.isEmpty {
                    RuhigerSatz(text: "Noch nichts getan. Sobald die Agenten arbeiten, steht es hier.", kennung: "verlauf-leer").padding(.top, 28)
                }
                ForEach(gruppen, id: \.gruppe) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        Abschnittstitel(text: g.gruppe.rawValue)
                        ForEach(g.zeilen) { z in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: z.art == .karte ? "checkmark.circle" : "clock").font(.system(size: 12)).foregroundStyle(Farbe.ink3).frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(z.satz).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink).multilineTextAlignment(.leading)
                                    Text("\(z.bereich) · \(z.zeitText)").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 9).padding(.horizontal, 14)
                            .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
                            .accessibilityIdentifier("verlauf-\(z.key)")
                        }
                    }
                    .padding(.top, 22)
                }
                if alle.count > anzahl {
                    Button("mehr") { withAnimation(Kurve.ease()) { anzahl += BereicheUebersicht.verlaufSeite } }
                        .buttonStyle(KartenKnopfStil(leise: true)).padding(.top, 18)
                        .accessibilityIdentifier("verlauf-mehr")
                }
            }
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .seiteEin()
        .accessibilityIdentifier("verlauf-liste")
    }
}

struct BereichBuehneView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var rand: CGFloat
    @State private var stand: String?
    @State private var geladen = false

    init(modell: AppModell, rand: CGFloat) {
        self.modell = modell
        self.store = modell.uebersicht
        self.rand = rand
    }

    private var id: String { modell.route.id ?? "" }

    var body: some View {
        let bereiche = store.daten.bereiche?.areas ?? []
        let b = bereiche.first { $0.id == id }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { modell.gehe(Route(.bereiche, q: ["bereich": id])) } label: { Text("← Bereiche") }
                    .buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                    .accessibilityIdentifier("buehne-zurueck")
                if let b {
                    inhalt(b, bereiche)
                } else {
                    RuhigerSatz(text: store.daten.geladen ? "Diesen Bereich gibt es nicht." : "Lädt …", kennung: "bereich-buehne-leer")
                }
            }
            .padding(.horizontal, rand).padding(.top, 30).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: id) {
            stand = nil; geladen = false
            stand = await store.leseDatei("~/Bereiche/\(id)/STAND.md")
            geladen = true
        }
        .accessibilityIdentifier("seite-bereich")
    }

    @ViewBuilder private func inhalt(_ b: Area, _ bereiche: [Area]) -> some View {
        let name = b.name.isEmpty ? b.id : b.name
        let zahlen = BereicheUebersicht.ProjektZahl.self
        let projekte = store.projekte
        let st = BereicheUebersicht.bereichsStand(jobs: store.daten.jobs, bereiche: [b], projekte: projekte.map(zahlen.init), jetzt: store.jetzt, namen: bereichsNamen(store)).first
        let karten = projekte.filter { $0.bereichId == b.id }.flatMap(\.aufgaben)
        let frische = Frische.kurzstand(geaendertAm: b.summary.changedAt, letzteKartenaenderung: karten.compactMap(\.updatedAt).max() ?? 0, jetzt: store.jetzt)
        let satz = BereicheUebersicht.kurzSatz(b.summary.lines)
        Text(name).font(Schrift.serif(34)).foregroundStyle(Farbe.ink1).accessibilityIdentifier("bereich-name")
        Text(satz.isEmpty ? "Noch kein Kurzstand." : satz).font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink2).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 14) {
            Text(frische.text).foregroundStyle(frische.veraltet ? Farbe.bernstein : Farbe.ink3)
            if let st, st.lauf > 0 { Text("Letzter Lauf \(st.laufZeit): \(st.laufSatz)").foregroundStyle(Farbe.ink3) }
            if let st, st.offen != nil { Text("\(st.offenText), \(st.fertigText)").foregroundStyle(Farbe.ink3) }
        }
        .font(Schrift.grotesk(12.5))
        Abschnittstitel(text: "Bericht von \(b.leaderName.isEmpty ? "Seneca" : b.leaderName)").padding(.top, 14)
        if let stand, !stand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SenecaTextView(text: stand, live: false)
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Farbe.papier, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
                .accessibilityIdentifier("bereich-bericht")
        } else {
            RuhigerSatz(text: geladen ? "Für diesen Bereich gibt es noch keinen Bericht." : "Lädt …", kennung: "bereich-bericht-leer")
        }
        let echte = store.echteProjekte.filter { $0.bereichId == b.id }
        if !echte.isEmpty {
            Abschnittstitel(text: "Zeitleiste der Projekte").padding(.top, 14)
            ProjektZeitleiste(projekte: echte, plaene: store.plaene, jetzt: store.jetzt) { modell.oeffneProjekt($0) }
        }
        Abschnittstitel(text: "Projekte").padding(.top, 14)
        BereichProjekte(modell: modell, store: store, bereiche: bereiche, zeile: BereicheUebersicht.listenZeilen(bereiche: bereiche, projekte: projekte).first { $0.id == b.id })
    }
}

struct ProjektZeitleiste: View {
    var projekte: [HeuteLogik.ProjektInfo]
    var plaene: [String: PlanStand]
    var jetzt: Double
    var oeffne: (String) -> Void

    private static let tag: Double = 86_400_000
    private static let vorlauf: Double = 1 * 7 * tag
    private static let fenster: Double = 12 * 7 * tag

    private var fensterStart: Double { jetzt - Self.vorlauf }
    private var heuteAnteil: Double { Self.vorlauf / Self.fenster }

    private func frist(_ p: HeuteLogik.ProjektInfo) -> Double? { PM.fristMs(p, plan: plaene[p.id]?.kurz) }

    private func anteil(_ p: HeuteLogik.ProjektInfo) -> Double? {
        guard let f = frist(p), p.health != .grau || !p.aufgaben.isEmpty else { return nil }
        let d = f - fensterStart
        return min(max(d / Self.fenster, heuteAnteil + 0.02), 1)
    }

    private var wochenstriche: [(anteil: Double, monat: String?)] {
        let cal = Calendar.current
        var letzterMonat = -1
        var ergebnis: [(Double, String?)] = []
        for i in 0...12 {
            let ms = fensterStart + Double(i) * 7 * Self.tag
            let a = Double(i) * 7 * Self.tag / Self.fenster
            let monat = cal.component(.month, from: Date(timeIntervalSince1970: ms / 1000))
            var beschriftung: String?
            if monat != letzterMonat { beschriftung = Self.monatsName(ms); letzterMonat = monat }
            ergebnis.append((a, beschriftung))
        }
        return ergebnis
    }

    private static func monatsName(_ ms: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "LLL"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Spacer().frame(width: 150)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        ForEach(Array(wochenstriche.enumerated()), id: \.offset) { _, strich in
                            VStack(spacing: 2) {
                                if let m = strich.monat {
                                    Text(m).font(Schrift.grotesk(10, .medium)).foregroundStyle(Farbe.ink4).fixedSize()
                                }
                                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 6)
                            }
                            .offset(x: g.size.width * strich.anteil - 0.5, y: 0)
                        }
                        Rectangle().fill(Farbe.himmel.opacity(0.8)).frame(width: 1.5)
                            .offset(x: g.size.width * heuteAnteil - 0.75)
                    }
                }
                .frame(height: 20)
                Spacer().frame(width: 9 + 12 + 96)
            }
            .accessibilityIdentifier("zeitleiste-achse")
            ForEach(projekte.sorted { (frist($0) ?? .infinity) < (frist($1) ?? .infinity) }, id: \.id) { p in
                Button { oeffne(p.id) } label: {
                    HStack(spacing: 12) {
                        Text(p.name).font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.ink1)
                            .lineLimit(1).frame(width: 150, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                                Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1).offset(x: g.size.width * heuteAnteil)
                                if let a = anteil(p) {
                                    Capsule().fill(GesundheitsPunkt.farbe(p.health).opacity(0.75))
                                        .frame(width: max(g.size.width * (a - heuteAnteil), 4), height: 5)
                                        .offset(x: g.size.width * heuteAnteil)
                                } else {
                                    Circle().fill(GesundheitsPunkt.farbe(p.health).opacity(0.5)).frame(width: 6, height: 6)
                                        .offset(x: g.size.width * heuteAnteil - 3)
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)
                        GesundheitsPunkt(g: p.health, grund: p.grund)
                        Text(frist(p).map { "bis \(Menschlich.datumKurz($0))" } ?? (p.aufgaben.isEmpty ? "ohne Frist" : "ohne Frist"))
                            .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).frame(width: 96, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("zeitleiste-\(p.id)")
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
        .accessibilityIdentifier("projekt-zeitleiste")
    }
}
