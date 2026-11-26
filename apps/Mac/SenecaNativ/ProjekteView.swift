import SwiftUI

struct GesundheitsPunkt: View {
    var g: HeuteLogik.Gesundheit
    var grund: String = ""
    var groesse: CGFloat = 9

    static func farbe(_ g: HeuteLogik.Gesundheit) -> Color {
        switch g {
        case .gruen: return Farbe.gruen
        case .gelb: return Farbe.bernstein
        case .rot: return Farbe.koralle
        case .grau: return Farbe.ink4
        }
    }

    var body: some View {
        Circle().fill(Self.farbe(g)).frame(width: groesse, height: groesse)
            .help(PM.gesundText[g].map { grund.isEmpty ? $0 : "\($0): \(grund)" } ?? grund)
            .accessibilityLabel(PM.gesundText[g] ?? "")
    }
}

struct ProjektBalken: View {
    var fertig: Int
    var alle: Int
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.075))
                    Capsule().fill(Farbe.himmel).frame(width: g.size.width * (alle > 0 ? Double(fertig) / Double(alle) : 0))
                }
            }
            .frame(height: 6)
            .animation(Kurve.ease(0.6), value: fertig)
            Text(alle > 0 ? "\(fertig) von \(alle)" : "keine Karten")
                .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).monospacedDigit().fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fertig) von \(alle) Karten erledigt")
    }
}

struct ReiterKnopf: View {
    var titel: String
    var aktiv: Bool
    var anzahl: Int = 0
    var kennung: String
    var tu: () -> Void
    var body: some View {
        Button(action: tu) {
            HStack(spacing: 6) {
                Text(titel)
                if anzahl > 0 {
                    Text("\(anzahl)").font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.aufWeiss)
                        .padding(.horizontal, 7).padding(.vertical, 1).background(Farbe.bernstein, in: Capsule())
                }
            }
            .font(Schrift.grotesk(14, aktiv ? .medium : .regular))
            .lineLimit(1).fixedSize()
            .foregroundStyle(aktiv ? Farbe.ink1 : Farbe.ink3)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .overlay(alignment: .bottom) { Rectangle().fill(aktiv ? Farbe.himmel : Color.clear).frame(height: 2) }
            .contentShape(Rectangle())
            .animation(Kurve.ease(), value: aktiv)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(aktiv ? .isSelected : [])
        .accessibilityIdentifier(kennung)
    }
}

struct ProjekteView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var rand: CGFloat

    init(modell: AppModell, rand: CGFloat) {
        self.modell = modell
        self.store = modell.uebersicht
        self.rand = rand
    }

    private var filter: String { modell.route.q["bereich"] ?? "" }
    private var wartetAnsicht: Bool { modell.route.q["ansicht"] == "wartet" }
    @State private var neuesProjekt = false

    private func sortiert(_ l: [HeuteLogik.ProjektInfo]) -> [HeuteLogik.ProjektInfo] {
        l.enumerated().sorted { a, b in
            let x = (Self.ordnung(a.element.health), -a.element.projekt.offen, a.offset), y = (Self.ordnung(b.element.health), -b.element.projekt.offen, b.offset)
            return x < y
        }.map(\.element)
    }
    private static func ordnung(_ g: HeuteLogik.Gesundheit) -> Int { [.rot: 0, .gelb: 1, .gruen: 2, .grau: 3][g] ?? 3 }

    var body: some View {
        let alle = store.echteProjekte
        let bereiche = store.daten.bereiche?.areas ?? []
        let sicht = alle.filter { filter.isEmpty ? true : (filter == "weitere" ? $0.bereichId.isEmpty : $0.bereichId == filter) }
        let warten = PM.wartetAufDich(sicht)
        let rot = sicht.filter { $0.health == .rot }.count
        let ohneZiel = sicht.filter { p in ((store.plaene[p.id]?.kurz?.ziel ?? p.ziel).trimmingCharacters(in: .whitespaces)).isEmpty }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                kopf(sicht: sicht, rot: rot, wartet: warten.count)
                if ohneZiel > 0 {
                    Text("\(PM.zahlWort(ohneZiel, gross: true)) \(ohneZiel == 1 ? "Projekt" : "Projekte") ohne Ziel")
                        .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).padding(.top, 6)
                        .accessibilityIdentifier("projekte-ohne-ziel")
                }
                statistik(sicht).padding(.top, 18)
                reiter(wartetN: warten.count).padding(.top, 22)
                if wartetAnsicht {
                    wartetListe(warten).padding(.top, 14)
                } else {
                    ForEach(gruppen(sicht, bereiche), id: \.id) { g in
                        VStack(alignment: .leading, spacing: 10) {
                            Abschnittstitel(text: g.titel)
                            ForEach(g.liste, id: \.id) { p in
                                ProjektZeile(modell: modell, store: store, p: p)
                            }
                        }
                        .padding(.top, 24)
                    }
                }
            }
            .padding(.horizontal, rand).padding(.top, 30).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: sicht.map(\.id)) { await store.ladePlaene(sicht) }
        .accessibilityIdentifier("seite-projekte")
        .sheet(isPresented: $neuesProjekt) { NeuesProjektSheet(modell: modell, store: store) }
    }

    private struct Gruppe { var id: String; var titel: String; var liste: [HeuteLogik.ProjektInfo] }

    private func gruppen(_ sicht: [HeuteLogik.ProjektInfo], _ bereiche: [Area]) -> [Gruppe] {
        var out = bereiche.map { b in Gruppe(id: b.id, titel: b.name, liste: sortiert(sicht.filter { $0.bereichId == b.id })) }
        out.append(Gruppe(id: "weitere", titel: "Weitere Projekte", liste: sortiert(sicht.filter { p in p.bereichId.isEmpty || !bereiche.contains { $0.id == p.bereichId } })))
        return out.filter { !$0.liste.isEmpty }
    }

    private func kopf(sicht: [HeuteLogik.ProjektInfo], rot: Int, wartet: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(PM.kopfsatz(rot: rot, wartet: wartet, projekte: sicht.count))
                .font(Schrift.serif(30)).foregroundStyle(Farbe.ink1).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("projekte-satz")
            Spacer(minLength: 8)
            Button("Neues Projekt") { neuesProjekt = true }
                .buttonStyle(KartenKnopfStil(leise: true))
                .accessibilityIdentifier("projekt-neu")
        }
    }

    private func statistik(_ sicht: [HeuteLogik.ProjektInfo]) -> some View {
        let s = PM.projektStatistik(sicht, jetzt: store.jetzt, label: { store.daten.label($0) })
        let aeltest = s.aeltesteOffenTage.map { $0 == 0 ? "heute" : "\($0) \($0 == 1 ? "Tag" : "Tage")" } ?? "keine Angabe"
        return HStack(alignment: .top, spacing: 12) {
            zahl("\(s.erledigtWoche)", "erledigt diese Woche")
            zahl("\(s.offenGesamt)", "offen gesamt")
            zahl(aeltest, "älteste offene Aufgabe")
            zahl("\(s.ohneVerantwortlichen)", "\(s.ohneVerantwortlichen == 1 ? "Projekt" : "Projekte") ohne Verantwortlichen")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projekte-statistik")
    }

    private func zahl(_ z: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(z).font(Schrift.serif(26)).foregroundStyle(Farbe.ink1).lineLimit(1).minimumScaleFactor(0.7)
            Text(text).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reiter(wartetN: Int) -> some View {
        HStack(spacing: 4) {
            ReiterKnopf(titel: "Alle Projekte", aktiv: !wartetAnsicht, kennung: "reiter-alle") { modell.gehe(Route(.projekte, q: filter.isEmpty ? [:] : ["bereich": filter])) }
            ReiterKnopf(titel: "Wartet auf dich", aktiv: wartetAnsicht, anzahl: wartetN, kennung: "reiter-wartet") {
                modell.gehe(Route(.projekte, q: filter.isEmpty ? ["ansicht": "wartet"] : ["bereich": filter, "ansicht": "wartet"]))
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Farbe.linie2).frame(height: 1) }
    }

    @ViewBuilder private func wartetListe(_ liste: [PM.WartetAufDich]) -> some View {
        if liste.isEmpty {
            Text("Nichts wartet auf dich.").font(Schrift.serif(22, kursiv: true)).foregroundStyle(Farbe.ink2).accessibilityIdentifier("wartet-leer")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(liste, id: \.id) { e in
                    Button { modell.oeffneProjekt(e.projektId) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.titel).font(Schrift.grotesk(14.5, .medium)).foregroundStyle(Farbe.ink1).lineLimit(2).multilineTextAlignment(.leading)
                            HStack(spacing: 8) {
                                Text(e.projektName).foregroundStyle(Farbe.ink2)
                                Text(e.seit.map { "wartet \(Menschlich.seitText($0, jetzt: store.jetzt))" } ?? "Wartezeit unbekannt").foregroundStyle(Farbe.ink3)
                            }
                            .font(Schrift.grotesk(12.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        .background(Farbe.pille, in: RoundedRectangle(cornerRadius: Mass.radiusKlein))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wartet-\(e.id)")
                }
            }
            .accessibilityIdentifier("wartet-liste")
        }
    }
}

struct ProjektZeile: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var p: HeuteLogik.ProjektInfo
    @State private var darueber = false

    var body: some View {
        let plan = store.plaene[p.id]?.kurz
        let ziel = (plan?.ziel ?? p.ziel).trimmingCharacters(in: .whitespacesAndNewlines)
        let frist = PM.fristMs(p, plan: plan)
        let risiko = PM.risikoVon(p, plan: plan, jetzt: store.jetzt)
        let laufend = p.aufgaben.filter { $0.status == "running" }
        let karte = laufend.first ?? p.naechster
        let weiter = plan?.naechster ?? karte.map { Menschlich.klartext($0.title) } ?? ""
        let alle = p.aufgaben.count
        let leiter = p.bereich?.leaderName ?? "Seneca"
        Button { modell.oeffneProjekt(p.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    GesundheitsPunkt(g: p.health, grund: p.grund)
                    Text(p.name).font(Schrift.grotesk(17, .medium)).foregroundStyle(Farbe.ink1).lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        if let r = risiko.r {
                            Circle().fill(r == .bequem ? Farbe.gruen : r == .knapp ? Farbe.bernstein : Farbe.koralle).frame(width: 7, height: 7)
                                .help("\(r.text): \(risiko.grund)")
                        }
                        Text(frist.map { "bis \(Menschlich.datumKurz($0))" } ?? "ohne Frist")
                            .foregroundStyle(frist.map { $0 < Menschlich.tagStart(store.jetzt) } == true ? Farbe.koralle : Farbe.ink3)
                    }
                    .font(Schrift.grotesk(12.5))
                }
                if (p.health == .rot || p.health == .gelb), !p.grund.isEmpty {
                    Text(p.grund).font(Schrift.grotesk(13)).foregroundStyle(p.health == .rot ? Farbe.koralle : Farbe.bernstein)
                        .multilineTextAlignment(.leading)
                }
                if !ziel.isEmpty {
                    Text(ziel).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2).lineLimit(2).multilineTextAlignment(.leading)
                } else {
                    Text("Noch kein Ziel · mit \(leiter) planen").font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink3)
                }
                if !PM.istVorrat(p) { ProjektBalken(fertig: p.fertigA.count, alle: alle).padding(.vertical, 3) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Weiter:").foregroundStyle(Farbe.ink3)
                    Text(weiter.isEmpty ? "Nichts geplant" : Menschlich.kuerzen(weiter, 90)).foregroundStyle(weiter.isEmpty ? Farbe.ink3 : Farbe.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                .font(Schrift.grotesk(13))
                .accessibilityIdentifier("projekt-weiter-\(p.id)")
                Text(PM.werDran(p, label: { store.daten.label($0) })).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(darueber ? Farbe.flaeche2 : Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(Farbe.linie2, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(Kurve.ease(), value: darueber)
        }
        .buttonStyle(.plain)
        .onHover { darueber = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projekt-\(p.id)")
    }
}

struct NeuesProjektSheet: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    @Environment(\.dismiss) private var dismiss

    @State private var bereichId = ""
    @State private var ziel = ""
    @State private var terminAn = false
    @State private var termin = Date()
    @State private var speichert = false
    @State private var vorschlagLaedt = false
    @State private var vorschlag: PlanVorschlag?
    @State private var vorschlagFehler: String?

    private var bereiche: [(id: String, name: String)] { store.bereicheNamen }
    private var bereitFuerVorschlag: Bool { !bereichId.isEmpty && !ziel.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Neues Projekt").font(Schrift.serif(26)).foregroundStyle(Farbe.ink1)
                .accessibilityIdentifier("neu-titel")
            VStack(alignment: .leading, spacing: 6) {
                Text("Bereich").font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.ink3)
                Picker("Bereich", selection: $bereichId) {
                    Text("Bitte wählen").tag("")
                    ForEach(bereiche, id: \.id) { b in Text(b.name.isEmpty ? b.id : b.name).tag(b.id) }
                }
                .labelsHidden()
                .accessibilityIdentifier("neu-bereich")
                .onChange(of: bereichId) { _ in vorschlag = nil; vorschlagFehler = nil }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Ziel (ein Satz)").font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.ink3)
                TextEditor(text: $ziel).font(Schrift.grotesk(14)).frame(height: 64)
                    .padding(6).background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
                    .accessibilityIdentifier("neu-ziel")
                    .onChange(of: ziel) { _ in vorschlag = nil; vorschlagFehler = nil }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Termin setzen", isOn: $terminAn).accessibilityIdentifier("neu-termin-an")
                if terminAn {
                    DatePicker("Termin", selection: $termin, displayedComponents: .date)
                        .labelsHidden().accessibilityIdentifier("neu-termin")
                }
            }
            .font(Schrift.grotesk(13))
            HStack {
                Button(vorschlagLaedt ? "Fragt nach …" : "Plan vorschlagen") { frageVorschlag() }
                    .buttonStyle(NebenKnopfStil())
                    .disabled(!bereitFuerVorschlag || vorschlagLaedt)
                    .accessibilityIdentifier("neu-vorschlagen")
                if vorschlagLaedt { ProgressView().controlSize(.small) }
            }
            if let f = vorschlagFehler {
                Text(f).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.koralle).accessibilityIdentifier("neu-vorschlag-fehler")
            }
            if let v = vorschlag { PlanVorschlagAnsicht(v: v) }
            HStack {
                Spacer()
                Button("Verwerfen") { dismiss() }.buttonStyle(NebenKnopfStil()).accessibilityIdentifier("neu-verwerfen")
                Button("So anlegen") { anlegen() }
                    .buttonStyle(KartenKnopfStil(haupt: true))
                    .disabled(bereichId.isEmpty || ziel.trimmingCharacters(in: .whitespaces).isEmpty || speichert)
                    .accessibilityIdentifier("neu-anlegen")
            }
        }
        .padding(28)
        .frame(width: 440)
    }

    private func frageVorschlag() {
        vorschlagLaedt = true
        vorschlagFehler = nil
        let bereichName = bereiche.first { $0.id == bereichId }?.name ?? bereichId
        let name = ziel.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminText = terminAn ? Menschlich.datumKurz(termin.timeIntervalSince1970 * 1000) : ""
        Task {
            do {
                let klient = try await PlanVorschlagDienst.gemeinsam.klient()
                vorschlag = try await PlanVorschlagAufgabe.erstelle(klient: klient, bereich: bereichName, ziel: name, terminText: terminText)
            } catch {
                vorschlagFehler = "Konnte keinen Plan-Entwurf holen: \(error.localizedDescription)"
            }
            vorschlagLaedt = false
        }
    }

    private func anlegen() {
        speichert = true
        let name = ziel.trimmingCharacters(in: .whitespacesAndNewlines)
        let faellig = terminAn ? termin.timeIntervalSince1970 * 1000 : nil
        let meilensteine = vorschlag?.meilensteine ?? []
        Task {
            let id = await store.legeProjektAn(name: Menschlich.kuerzen(name, 60), bereichId: bereichId, ziel: name, faelligMs: faellig, meilensteine: meilensteine)
            speichert = false
            dismiss()
            guard let id else { return }
            modell.oeffneProjekt(id)
            if let b = store.daten.bereiche?.areas.first(where: { $0.id == bereichId }), !b.leader.isEmpty {
                modell.oeffneChat(key: "agent:\(b.leader):main", agentId: b.leader, bereich: b.id)
                modell.sprichMit(agentId: b.leader, vorlage: "Bitte erstelle einen Plan für das neue Projekt „\(name)“: Etappen mit Zuständigem und „fertig, wenn …“, Frist und Budget. Lege ihn als Codeblock seneca-plan in der PLAN.md ab.")
            }
        }
    }
}

private struct PlanVorschlagAnsicht: View {
    var v: PlanVorschlag
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(v.lokal ? "Agent schlägt vor (lokaler Entwurf, gemma3:12b):" : "Agent schlägt vor:")
                .font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.ink3)
            if !v.meilensteine.isEmpty {
                Text("Meilensteine: \(v.meilensteine.map(\.name).joined(separator: " · "))")
                    .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink1)
            }
            if !v.risiko.isEmpty {
                Text("Risiko-Stand: \(v.risiko)").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
            }
            if !v.pakete.isEmpty {
                Text("Diese Pakete übernimmt er sofort: \(v.pakete.joined(separator: " · "))")
                    .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
            }
        }
        .padding(12)
        .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
        .accessibilityIdentifier("neu-vorschlag")
    }
}

final class PlanVorschlagDienst: @unchecked Sendable {
    static let gemeinsam = PlanVorschlagDienst()
    private let starter = OllamaStarter(prozess: OllamaProzessEcht(), vorgabeModell: "gemma3:12b")

    func klient() async throws -> OllamaKlient {
        switch await starter.sichereBereit() {
        case .bereit(let modell, _): return OllamaKlient.gemeinsam(modell: modell, geladen: await starter.geladenerKontext(modell: modell))
        case .keinModell: throw OllamaFehler(text: "Kein Sprachmodell installiert.")
        case .nichtErreichbar(let grund): throw OllamaFehler(text: grund)
        }
    }
}
