import SwiftUI

enum BoardSpalte: String, CaseIterable, Identifiable {
    case naechstes, arbeit, pruefen, fertig

    var id: String { rawValue }
    var titel: String {
        switch self {
        case .naechstes: return "Als Nächstes"
        case .arbeit: return "In Arbeit"
        case .pruefen: return "Prüfen"
        case .fertig: return "Fertig"
        }
    }
    var hinweis: String? { self == .pruefen ? "liegt bei dir" : nil }
    var ziel: String {
        switch self {
        case .naechstes: return "todo"
        case .arbeit: return "running"
        case .pruefen: return "review"
        case .fertig: return "done"
        }
    }
    private var stati: Set<String> {
        switch self {
        case .naechstes: return ["backlog", "triage", "todo", "ready", "scheduled"]
        case .arbeit: return ["running", "blocked"]
        case .pruefen: return ["review"]
        case .fertig: return ["done"]
        }
    }
    func enthaelt(_ status: String) -> Bool { stati.contains(status) }
    static func von(status: String) -> BoardSpalte { allCases.first { $0.enthaelt(status) } ?? .naechstes }
}

@MainActor
enum BoardAktion {
    @discardableResult
    static func lasse(_ store: OverviewStore, kartenId: String, in spalte: BoardSpalte) async -> Bool {
        guard let c = store.aktuell(kartenId), !spalte.enthaelt(c.status) else { return false }
        await store.verschiebeMitHinweis(c, nach: spalte.ziel, spalte: spalte.titel)
        return true
    }
}

private func kartenName(_ c: OvKarte) -> String { Menschlich.klartext(c.title) }

func kartenMarken(_ c: OvKarte, jetzt: Double) -> (teile: [String], ueberfaellig: Bool) {
    let heute = Menschlich.tagStart(jetzt)
    let frist = Menschlich.fristVon(c.labels), plan = Menschlich.planVon(c.labels)
    let offen = c.status != "done"
    let ueber = frist.map { $0 < heute } == true && offen
    var t: [String] = []
    if c.status == "blocked" { t.append("blockiert") } else if c.status == "running" { t.append("läuft") } else if c.status == "review" { t.append("zur Prüfung") }
    if c.priority == "urgent" { t.append("Dringend") } else if c.priority == "high" { t.append("Hoch") }
    if let f = frist, offen { t.append("\(ueber ? "überfällig seit" : "bis") \(Menschlich.datumKurz(f))") }
    if let p = plan, p <= heute, frist == nil, offen { t.append("heute") }
    if offen, c.status != "running" {
        let seit = Menschlich.tageZwischen(PM.letzteBewegung(c), jetzt)
        if seit >= 3 { t.append("liegt seit \(seit) Tagen") }
    }
    return (t, ueber)
}

struct BoardView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var p: HeuteLogik.ProjektInfo
    var offeneKarte: String?

    @State private var neu = ""
    @State private var fertigOffen = false
    @State private var ueber: BoardSpalte?
    @State private var beschaeftigt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { g in
                let breite = max(156, (g.size.width - 20) / 3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach([BoardSpalte.naechstes, .arbeit, .pruefen]) { s in
                            spalte(s).frame(width: breite)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .frame(height: Self.hoehe(p))
            fertigStreifen
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board")
    }

    private static func hoehe(_ p: HeuteLogik.ProjektInfo) -> CGFloat {
        let n = [BoardSpalte.naechstes, .arbeit, .pruefen].map { s in p.aufgaben.filter { s.enthaelt($0.status) }.count }.max() ?? 0
        return min(520, max(200, CGFloat(n) * 84 + 96))
    }

    private func karten(_ s: BoardSpalte) -> [OvKarte] { PM.sortiereKarten(p.aufgaben.filter { s.enthaelt($0.status) }) }

    private func spalte(_ s: BoardSpalte) -> some View {
        let liste = karten(s)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(s.titel).font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.ink1)
                Text("\(liste.count)").font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.ink3).monospacedDigit()
                if let h = s.hinweis { Text(h).font(Schrift.grotesk(11)).foregroundStyle(Farbe.bernstein).lineLimit(1) }
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(spacing: 8) {
                    if s == .naechstes { neueKarte }
                    ForEach(liste) { c in
                        BoardKarte(store: store, c: c, gewaehlt: offeneKarte == c.id) { modell.oeffneProjekt(p.id, karte: c.id, tab: modell.route.tab ?? "board") }
                            .draggable(c.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    if liste.isEmpty, s != .naechstes {
                        Text(s == .pruefen ? "Nichts zu prüfen." : "Nichts in Arbeit.").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink4)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                }
                .animation(Kurve.ease(), value: liste.map(\.id))
            }
            .scrollIndicators(.never)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ueber == s ? Farbe.himmelFlaeche : Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(ueber == s ? Farbe.himmel.opacity(0.5) : Farbe.linie2, lineWidth: 1))
        .animation(Kurve.ease(), value: ueber == s)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            Task { await BoardAktion.lasse(store, kartenId: id, in: s) }
            return true
        } isTargeted: { an in
            if an { ueber = s } else if ueber == s { ueber = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spalte-\(s.rawValue)")
    }

    private var neueKarte: some View {
        TextField("", text: $neu, prompt: Text("Neue Karte …").foregroundStyle(Farbe.ink4))
            .textFieldStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink1)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Farbe.linie2, lineWidth: 1))
            .disabled(beschaeftigt)
            .onSubmit { legeAn() }
            .accessibilityLabel("Neue Karte").accessibilityIdentifier("neue-karte")
    }

    private func legeAn() {
        let t = neu
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty, !beschaeftigt else { return }
        beschaeftigt = true
        Task {
            if await store.legeKarteAn(titel: t, boardId: p.id) != nil { neu = "" }
            beschaeftigt = false
        }
    }

    private var fertigStreifen: some View {
        let liste = karten(.fertig)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(liste.count) fertig").font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.ink2).monospacedDigit()
                Spacer(minLength: 0)
                if !liste.isEmpty {
                    Button(fertigOffen ? "Einklappen" : "Anzeigen") { withAnimation(Kurve.ease()) { fertigOffen.toggle() } }
                        .buttonStyle(.plain).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.himmel)
                        .accessibilityIdentifier("fertig-umschalten")
                }
            }
            if fertigOffen {
                VStack(spacing: 6) {
                    ForEach(liste) { c in
                        BoardKarte(store: store, c: c, gewaehlt: offeneKarte == c.id) { modell.oeffneProjekt(p.id, karte: c.id, tab: modell.route.tab ?? "board") }
                            .draggable(c.id)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ueber == .fertig ? Farbe.himmelFlaeche : Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(ueber == .fertig ? Farbe.himmel.opacity(0.5) : Farbe.linie2, lineWidth: 1))
        .animation(Kurve.ease(), value: ueber == .fertig)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            Task { await BoardAktion.lasse(store, kartenId: id, in: .fertig) }
            return true
        } isTargeted: { an in
            if an { ueber = .fertig } else if ueber == .fertig { ueber = nil }
        }
        .accessibilityIdentifier("spalte-fertig")
    }
}

struct BoardKarte: View {
    @ObservedObject var store: OverviewStore
    var c: OvKarte
    var gewaehlt: Bool
    var oeffne: () -> Void

    var body: some View {
        let m = kartenMarken(c, jetzt: store.jetzt)
        let wer = c.agentId.map { store.daten.label($0).isEmpty ? $0 : store.daten.label($0) } ?? "Du"
        VStack(alignment: .leading, spacing: 4) {
            Text(kartenName(c)).font(Schrift.grotesk(13.5, .medium)).foregroundStyle(c.status == "done" ? Farbe.ink3 : Farbe.ink1)
                .lineLimit(3).multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                if !m.teile.isEmpty {
                    Text(m.teile.joined(separator: " · ")).foregroundStyle(m.ueberfaellig || c.status == "blocked" ? Farbe.koralle : Farbe.ink3)
                }
                Spacer(minLength: 0)
                Text(wer).foregroundStyle(Farbe.ink3)
            }
            .font(Schrift.grotesk(11.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Farbe.papier, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(gewaehlt ? Farbe.himmel : Farbe.linie2, lineWidth: gewaehlt ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: oeffne)
        .animation(Kurve.ease(), value: gewaehlt)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("karte-\(c.id)")
    }
}

struct KartenListeView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var p: HeuteLogik.ProjektInfo
    var offeneKarte: String?

    @State private var doneOffen = false
    @State private var wer = ""
    @State private var neu = ""
    @State private var beschaeftigt = false

    private func name(_ c: OvKarte) -> String { c.agentId.map { store.daten.label($0).isEmpty ? $0 : store.daten.label($0) } ?? "Du" }

    var body: some View {
        let zustaendige = Array(Set(p.aufgaben.map(name))).sorted { $0 == "Du" ? true : ($1 == "Du" ? false : $0.localizedCompare($1) == .orderedAscending) }
        let sicht = p.aufgaben.filter { wer.isEmpty || name($0) == wer }
        let gruppen: [(id: String, titel: String, karten: [OvKarte])] = [
            ("du", "Du", PM.sortiereKarten(sicht.filter { $0.status != "done" && $0.agentId == nil })),
            ("agenten", "Agenten", PM.sortiereKarten(sicht.filter { $0.status != "done" && $0.agentId != nil })),
            ("done", "Erledigt", PM.sortiereKarten(sicht.filter { $0.status == "done" })),
        ]
        VStack(alignment: .leading, spacing: 16) {
            if zustaendige.count > 1 {
                HStack(spacing: 14) {
                    filterKnopf("Alle", wer.isEmpty) { wer = "" }
                    ForEach(zustaendige, id: \.self) { z in filterKnopf(z, wer == z) { wer = wer == z ? "" : z } }
                    Spacer(minLength: 0)
                }
            }
            ForEach(gruppen, id: \.id) { g in
                if !(g.karten.isEmpty && g.id != "du") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Abschnittstitel(text: g.titel)
                            Text("\(g.karten.count)").font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.ink3)
                            if g.id == "done" {
                                Button(doneOffen ? "Einklappen" : "Anzeigen") { withAnimation(Kurve.ease()) { doneOffen.toggle() } }
                                    .buttonStyle(.plain).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.himmel)
                            }
                        }
                        if !(g.id == "done" && !doneOffen) {
                            ForEach(g.karten) { c in zeile(c) }
                            if g.id == "du", g.karten.isEmpty { Text("Nichts, was an dir liegt.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3) }
                        }
                        if g.id == "du" {
                            TextField("", text: $neu, prompt: Text("Neue Karte …").foregroundStyle(Farbe.ink4))
                                .textFieldStyle(.plain).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink1)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .disabled(beschaeftigt).onSubmit { legeAn() }
                                .accessibilityIdentifier("neue-karte-liste")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("karten-liste")
    }

    private func filterKnopf(_ t: String, _ an: Bool, _ tu: @escaping () -> Void) -> some View {
        Button(action: tu) { Text(t).font(Schrift.grotesk(13, an ? .medium : .regular)).foregroundStyle(an ? Farbe.ink1 : Farbe.ink3) }.buttonStyle(.plain)
    }

    private func zeile(_ c: OvKarte) -> some View {
        let m = kartenMarken(c, jetzt: store.jetzt)
        return Button { modell.oeffneProjekt(p.id, karte: c.id, tab: modell.route.tab ?? "liste") } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(kartenName(c)).font(Schrift.grotesk(14)).foregroundStyle(c.status == "done" ? Farbe.ink3 : Farbe.ink1).multilineTextAlignment(.leading)
                if !m.teile.isEmpty { Text(m.teile.joined(separator: " · ")).font(Schrift.grotesk(12)).foregroundStyle(m.ueberfaellig ? Farbe.koralle : Farbe.ink3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(offeneKarte == c.id ? Farbe.himmelFlaeche : Farbe.flaeche, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("karte-\(c.id)")
    }

    private func legeAn() {
        let t = neu
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty, !beschaeftigt else { return }
        beschaeftigt = true
        Task {
            if await store.legeKarteAn(titel: t, boardId: p.id) != nil { neu = "" }
            beschaeftigt = false
        }
    }
}
