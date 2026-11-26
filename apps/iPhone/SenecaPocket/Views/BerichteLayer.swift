import SwiftUI

@MainActor
final class BerichteModel: ObservableObject {
    enum Tab { case aufgaben, berichte }
    @Published var tab: Tab = .aufgaben
    @Published private(set) var laeufe: [String: [BerichtLauf]] = [:]
    @Published private(set) var laedt = false
    private var geladen: Date?

    func laden(store: SenecaStore, jetzt: Date, neu: Bool = false) async {
        if laedt { return }
        if !neu, let g = geladen, jetzt.timeIntervalSince(g) < 120 { return }
        laedt = true
        defer { laedt = false }
        let jobs = store.today?.jobs ?? []
        #if DEBUG
        if store.demo { laeufe = BerichteDemo.laeufe(jobs: jobs, jetzt: jetzt); geladen = jetzt; return }
        #endif
        guard store.isConnected else { return }
        for job in BerichteLogik.berichtJobs(jobs, jetzt: jetzt) {
            if let antwort = try? await store.rufe("auftrag.laeufe", params: ["id": job.id, "limit": 30], timeout: 8) {
                laeufe[job.id] = BerichteLogik.laeufe(antwort)
            }
        }
        geladen = jetzt
    }

    func eintraege(store: SenecaStore, jetzt: Date) -> [BerichtEintrag] {
        let input = NeedsInput(now: jetzt, calendar: .current, snapshot: store.today, localSeen: store.localSeen)
        return BerichteLogik.eintraege(jobs: store.today?.jobs ?? [], laeufe: laeufe, input: input)
    }
}

struct BerichteListeView: View {
    var now: Date
    var allowTap: () -> Bool
    @EnvironmentObject private var store: SenecaStore
    @EnvironmentObject private var berichte: BerichteModel
    @Environment(\.appActions) private var actions

    var body: some View {
        let tage = BerichteLogik.nachTag(BerichteLogik.zusammengefasst(berichte.eintraege(store: store, jetzt: now)), jetzt: now)
        VStack(alignment: .leading, spacing: 0) {
            if tage.isEmpty {
                if berichte.laedt { LadeZeile("Die Berichte werden geholt …") }
                else { LeerSatz("In den letzten 30 Tagen ist kein Bericht gekommen.") }
            }
            ForEach(Array(tage.enumerated()), id: \.element.titel) { i, tag in
                AbschnittKopf(tag.titel, oben: i > 0)
                ForEach(Array(tag.gruppen.enumerated()), id: \.element.id) { j, g in
                    zeile(g, letzte: j == tag.gruppen.count - 1)
                }
            }
        }
        .accessibilityIdentifier("berichte.liste")
    }

    private func zeile(_ g: BerichtGruppe, letzte: Bool) -> some View {
        let b = g.neuester
        var unter = b.absender.isEmpty ? b.name : b.absender
        if g.anzahl > 1 { unter += " · \(g.anzahl)× gleich" }
        return Zeile(vorn: .punkt(g.gelesen ? .clear : Stil.farbe.himmel),
                     titel: b.erster,
                     unter: unter,
                     hinten: .text(BerichteLogik.zeile(b.zeit, jetzt: now)),
                     betont: !g.gelesen,
                     linie: !letzte) {
            guard allowTap() else { return }
            Self.oeffnen(g, now: now, store: store, actions: actions)
        }
        .accessibilityValue(g.gelesen ? "gelesen" : "ungelesen")
        .accessibilityIdentifier("berichte.zeile")
    }

    static func oeffnen(_ g: BerichtGruppe, now: Date, store: SenecaStore, actions: AppActions) {
        let b = g.neuester
        actions.openReading(ReadingDocument(id: "bericht-\(b.id)", kicker: "Bericht · \(BerichteLogik.wann(b.zeit, jetzt: now))",
                                            title: b.name, body: b.text, bewertung: BerichteLogik.bewertung(b)))
        store.markSeen(g.ids)
    }
}

#if DEBUG
enum BerichteDemo {
    static func laeufe(jobs: [AgentJob], jetzt: Date) -> [String: [BerichtLauf]] {
        let cal = Calendar.current
        let zeiten: [String: (Int, Int)] = ["b": (7, 30), "c": (8, 30), "f": (18, 30), "g": (19, 0)]
        var out: [String: [BerichtLauf]] = [:]
        for job in jobs {
            guard let (h, min) = zeiten[job.id] else { continue }
            out[job.id] = (0..<9).compactMap { tage in
                guard let tag = cal.date(byAdding: .day, value: -tage, to: jetzt),
                      let t = cal.date(bySettingHour: h, minute: min, second: 0, of: tag), t <= jetzt else { return nil }
                return BerichtLauf(runAtMs: t.timeIntervalSince1970 * 1000, summary: text(job.id, tage: tage))
            }
        }
        return out
    }

    private static func text(_ id: String, tage: Int) -> String {
        switch id {
        case "b": return "Guten Morgen. Heute stehen der Termin um 10 Uhr, die Entscheidung zu Instagram und der Rückruf bei Daniel an.\n\n- 10:00 Wochenbesprechung\n- Entscheidung offen: Instagram\n- Rückruf Daniel (Comspot)"
        case "c": return "Bei CALL-E hat sich nichts Wesentliches geändert. Die Preisseite ist unverändert, neue Funktionen gibt es nicht."
        case "f": return "Sundartha steht gut da: Hermes läuft stabil, zwei Aufgaben sind offen.\n\n- Hermes-Test bestanden\n- Marketingtext wartet auf dich"
        default:
            return """
            Ein ruhiger, guter Tag. Vier von fünf Aufgaben sind erledigt.

            ```seneca
            {"titel":"Der Tag in Zahlen","marke":{"text":"Gut gelaufen","ton":"ok"},
             "zahlen":[{"label":"Aufgaben","wert":"4 von 5","ton":"ok"},{"label":"Gelaufen","wert":"4,6 km","detail":"5:40 pro km"},{"label":"Gelesen","wert":"45 Min"}],
             "fortschritt":{"wert":4,"von":5,"text":"Aufgaben heute"},
             "diagramm":{"art":"balken","einheit":"Aufgaben pro Tag","punkte":[{"label":"Mo","wert":3},{"label":"Di","wert":5},{"label":"Mi","wert":2},{"label":"Do","wert":4},{"label":"Fr","wert":4}]},
             "punkte":[{"text":"Hermes-Test bestanden","ton":"ok","meta":"Sundartha"},{"text":"Rechnung Comspot wartet auf Freigabe","ton":"warn","meta":"bis Freitag"}],
             "aktionen":[{"label":"Morgen planen","prompt":"Plane meinen morgigen Tag."}]}
            ```

            Morgen früh startet die Wochenbesprechung um 10 Uhr.
            """
        }
    }
}
#endif
