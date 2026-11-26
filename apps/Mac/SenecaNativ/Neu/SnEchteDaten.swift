import SwiftUI

private enum SnZeit {
    static func ms(_ d: Date) -> Double { d.timeIntervalSince1970 * 1000 }
    static func datum(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    static func frist(_ s: String) -> (ms: Double, mitUhr: Bool)? {
        guard let g = Muster.erster(s, #"^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?"#),
              let j = g[1].flatMap(Int.init), let m = g[2].flatMap(Int.init), let t = g[3].flatMap(Int.init) else { return nil }
        var c = DateComponents(year: j, month: m, day: t)
        let uhr = g[4].flatMap(Int.init)
        c.hour = uhr ?? 0; c.minute = g[5].flatMap(Int.init) ?? 0
        guard let d = Calendar.current.date(from: c) else { return nil }
        return (ms(d), uhr != nil)
    }

    static func fristText(_ f: (ms: Double, mitUhr: Bool), jetzt: Double, praefix: String) -> String {
        ([praefix, Menschlich.tagText(f.ms, jetzt: jetzt), f.mitUhr ? Menschlich.hhmm(f.ms) : ""]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func wann(_ ms: Double, jetzt: Double) -> String {
        let t = Menschlich.tagText(ms, jetzt: jetzt)
        return t == "heute" || t == "gestern" ? "\(t) um \(Menschlich.hhmm(ms))" : "am \(t)"
    }

    static func seitLaufend(_ ms: Double, jetzt: Double) -> String {
        let min = Int((jetzt - ms) / 60_000)
        if min < 1 { return "gerade gestartet" }
        if min < 60 { return "seit \(min) Min." }
        if min < 12 * 60, Menschlich.tageZwischen(ms, jetzt) == 0 { return "seit \(min / 60) Std." }
        return Menschlich.seitText(ms, jetzt: jetzt)
    }

    static func dauer(_ min: Int) -> String {
        if min <= 0 { return "" }
        if min < 60 { return "\(min) Minuten" }
        let h = min / 60, r = min % 60
        if r == 0 { return h == 1 ? "eine Stunde" : "\(h < HeuteLogik.zahlwort.count ? HeuteLogik.zahlwort[h].lowercased() : String(h)) Stunden" }
        return "\(h) Std. \(r) Min."
    }

    static func titel(_ t: String?, _ max: Int = 90) -> String {
        var s = Menschlich.klartext(t)
        s = s.replacingOccurrences(of: #"^Auftrag an [^:]{1,40}:\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[,\s]*#\d{3,}\b"#, with: "", options: .regularExpression)
        return Menschlich.kuerzen(s.trimmingCharacters(in: .whitespacesAndNewlines), max)
    }

    static func projekt(_ n: String) -> String { n == "default" ? "" : n }
}

@MainActor
final class SnEchteDaten: SenecaDatenQuelle, SnProjekteQuelle {
    let ov: OverviewStore
    private let d: OvDaten
    private let jetzt: Double
    private let ents: [OvEntscheidung]
    let agenten: [SnAgent]
    let aufgaben: [SnAufgabe]
    let termine: [SnTermin]
    let notizen: [SnNotiz] = []
    let istEcht = true
    private let verz: ProjektVerzeichnis
    private static var verzCache: (ProjektVerzeichnis, Date)?

    static func verzeichnis() -> ProjektVerzeichnis {
        if let c = verzCache, Date().timeIntervalSince(c.1) < 30 { return c.0 }
        let v = ProjektVerzeichnis.lade()
        verzCache = (v, Date())
        return v
    }

    private static func lesbar(_ name: String, kennung: String) -> String {
        guard name == kennung, let erster = name.first else { return name }
        return String(erster).uppercased() + name.dropFirst().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    init(ov: OverviewStore) {
        self.ov = ov
        let d = ov.daten, jetzt = ov.jetzt
        self.d = d; self.jetzt = jetzt
        let ents = ov.entscheidungenSicht.filter { !$0.ruhend }
        self.ents = ents
        let verz = Self.verzeichnis()
        self.verz = verz
        func fristPrio(_ ms: Double?) -> Int { (ms ?? .infinity) < Menschlich.addTage(Menschlich.tagStart(jetzt), 1) ? 1 : 0 }
        var liste: [SnAufgabe] = []

        let ausstehendeIds = Set(ov.ausstehend.map(\.id))
        for e in ents + ov.ausstehend.map(\.e) {
            let agent = e.leiter ?? d.defaultAgent
            let projekt = (verz.projekt(imText: [e.frage]) ?? verz.projekt(agent: agent, name: d.label(agent)))?.name ?? ""
            let laeuft = ausstehendeIds.contains(e.id)
            liste.append(SnAufgabe(id: "e:" + e.id, projekt: projekt, agentId: agent, status: laeuft ? .laeuft : .wartetAufDich,
                                   prio: fristPrio(e.frist) == 1 ? 1 : 2, titel: SnZeit.titel(e.frage),
                                   seit: laeuft ? "gerade gestartet" : Menschlich.seitText(e.gestelltAm, jetzt: jetzt),
                                   frist: laeuft ? nil : e.frist.map { "Entscheidung bis " + Menschlich.tagText($0, jetzt: jetzt) }, heuteFertig: false))
        }
        aufgaben = liste

        var ids: [String] = []
        for a in liste where !a.agentId.isEmpty && !ids.contains(a.agentId) { ids.append(a.agentId) }
        agenten = ids.map { id in
            let seneca = id == d.defaultAgent
            let name = seneca ? "Seneca" : Self.lesbar(d.label(id), kennung: id)
            return SnAgent(id: id, name: name, initial: seneca ? "" : String(name.prefix(1)).uppercased())
        }

        let heute0 = Menschlich.tagStart(jetzt), morgen0 = Menschlich.addTage(heute0, 1)
        var gesehen = Set<String>()
        let heutige = ov.kalenderSicht.termine
            .filter { !$0.ganztags && $0.start >= heute0 && $0.start < morgen0 && $0.ende > jetzt && gesehen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
            .prefix(5)
        termine = heutige.enumerated().map { i, t in
            var teile: [String] = []
            if i == 0 {
                let min = Int((t.start - jetzt) / 60_000)
                teile.append(min <= 0 ? "läuft gerade" : min < 60 ? "in \(min) Minuten" : "in \(min / 60) Std.")
            }
            if let o = t.ort, !o.isEmpty { teile.append(o) }
            let dauer = SnZeit.dauer(Int((t.ende - t.start) / 60_000))
            if !dauer.isEmpty { teile.append(dauer) }
            return SnTermin(zeit: Menschlich.hhmm(t.start), titel: t.titel, nebenzeile: teile.joined(separator: " · "), hatBriefing: false)
        }
    }

    lazy var projekte: [SnProjekt] = {
        let reihenfolge: [SnZustand] = [.gefaehrdet, .achtung, .imPlan, .ruht]
        let alle = verz.projekte.map { p -> (SnProjekt, Int) in
            let a = aufgaben.filter { $0.projekt == p.name }
            return (baue(p, aufgaben: a), a.filter { $0.status != .fertig }.count)
        }
        return alle.enumerated().sorted { x, y in
            let ax = (x.element.1 > 0 ? 0 : 1, reihenfolge.firstIndex(of: x.element.0.zustand) ?? 9, x.offset)
            let ay = (y.element.1 > 0 ? 0 : 1, reihenfolge.firstIndex(of: y.element.0.zustand) ?? 9, y.offset)
            return ax < ay
        }.map(\.element.0)
    }()

    private var achsenStart: Double {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let montag = cal.dateInterval(of: .weekOfYear, for: SnZeit.datum(jetzt))?.start ?? SnZeit.datum(Menschlich.tagStart(jetzt))
        return SnZeit.ms(cal.date(byAdding: .day, value: -28, to: montag) ?? montag)
    }

    var zeitachse: SnZeitachse {
        let a0 = achsenStart
        let f = DateFormatter(); f.dateFormat = "d.M."
        let wochen = (0..<10).map { f.string(from: SnZeit.datum(Menschlich.addTage(a0, $0 * 7))) }
        return SnZeitachse(wochen: wochen, heute: (jetzt - a0) / 86_400_000, heuteWoche: 4)
    }

    private func baue(_ p: AblageProjekt, aufgaben a: [SnAufgabe]) -> SnProjekt {
        let offen = a.filter { $0.status != .fertig }
        let dich = offen.filter { $0.status == .wartetAufDich }.count
        let alarm = offen.contains { $0.prio == 1 }
        let zustand: SnZustand, wort: String
        if offen.isEmpty { zustand = .ruht; wort = "Ruht." }
        else if alarm { zustand = .gefaehrdet; wort = "Gefährdet." }
        else if dich > 0 { zustand = .achtung; wort = "Achtung." }
        else { zustand = .imPlan; wort = "Im Plan." }
        let rest = offen.isEmpty ? "" : offen.count == 1 ? "eine offene Aufgabe" : "\(offen.count) offene Aufgaben"
        var grund = ""
        if alarm { grund = "Eine Aufgabe hat Alarm oder eine Frist bis morgen." }
        else if dich > 0 { grund = dich == 1 ? "Eine Aufgabe wartet auf dich." : "\(dich) Aufgaben warten auf dich." }
        return SnProjekt(id: p.id, name: p.name, kurz: p.name, bereich: p.bereichName, rest: rest,
                         meta: p.bereichName, agentId: p.agent.isEmpty ? d.defaultAgent : p.agent,
                         zustand: zustand, zustandText: [wort, grund].filter { !$0.isEmpty }.joined(separator: " "), ziel: p.beschreibung, kriterien: [], stand: nil,
                         meilensteine: [], risiken: [], phasen: [], zeitSatz: "")
    }

    var kalender: SnKalenderDaten {
        var gesehen = Set<String>()
        let t = ov.kalenderSicht.termine.filter { gesehen.insert($0.id).inserted }.map {
            SnKalenderTermin(id: $0.id, titel: $0.titel, start: SnZeit.datum($0.start), ende: SnZeit.datum($0.ende), ganztaegig: $0.ganztags)
        }
        return SnKalenderDaten(jetzt: SnZeit.datum(jetzt), termine: t)
    }

    func lade() async { await ov.ladeKalenderLang() }

    func lege(titel: String, start: Date, ende: Date) async -> Bool {
        guard let k = ov.kalenderSicht.kal?.schreibbar.first ?? ov.daten.kalender?.schreibbar.first else {
            _ = ov.hinweis("Termin nur hier gemerkt: Kein Kalender erlaubt das Eintragen.")
            return false
        }
        do {
            try await ov.terminAnlegen(titel: titel, start: start, ende: ende, kalender: k)
            await ov.ladeKalenderLang()
            return true
        } catch {
            _ = ov.hinweis("Termin ging nicht: \(OverviewStore.fehlertext(error))")
            return false
        }
    }
}

@MainActor
final class SnEchtesFenster: SnFensterQuelle {
    let ov: OverviewStore
    init(ov: OverviewStore) { self.ov = ov }

    private func offen(_ id: String) -> OvEntscheidung? {
        guard id.hasPrefix("e:") else { return nil }
        let k = String(id.dropFirst(2))
        return ov.entscheidungenSicht.first { $0.id == k }
    }

    func entscheidung(aufgabe id: String) -> SnEntscheidung? {
        guard let e = offen(id), !e.optionen.isEmpty else { return nil }
        let jetzt = ov.jetzt
        let kurz = (e.kurz ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let kontext = kurz.isEmpty ? e.kontext : kurz
        let hintergrund = [kurz.isEmpty ? "" : e.kontext, e.risiko ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        let optionen = e.optionen.map {
            SnOption(name: SnZeit.titel($0.titel, 60), fakten: $0.aufwand ?? "", vorteil: $0.wirkung ?? "", nachteil: "", knopf: SnZeit.titel($0.titel, 60),
                     schluessel: $0.key, beschreibung: $0.beschreibung ?? "")
        }
        let vor = Entscheiden.vorwahl(e)
        return SnEntscheidung(frist: e.frist.map { "Entscheidung bis " + Menschlich.tagText($0, jetzt: jetzt) } ?? "", frage: SnZeit.titel(e.frage, 200),
                              kontext: kontext, hintergrund: hintergrund, optionen: optionen,
                              empfehlung: e.optionen.firstIndex { $0.key == vor } ?? 0, empfehlungText: e.empfehlung?.text ?? "", danach: e.folge ?? "")
    }

    func formular(aufgabe id: String) -> SnFormular? {
        let jetzt = ov.jetzt, d = ov.daten
        if id.hasPrefix("e:") {
            let k = String(id.dropFirst(2))
            if let a = ov.ausstehend.first(where: { $0.id == k }) {
                var f = SnFormular(projekt: a.e.projektName, aktualisiert: SnZeit.wann(jetzt, jetzt: jetzt))
                f.auftrag = SnZeit.titel(a.e.frage, 300)
                f.stand = "Du hast entschieden: " + Entscheiden.wahlText(a.e, a.wahl)
                f.weiter = a.e.folge
                return f
            }
            guard let e = offen(id) else { return nil }
            var f = SnFormular(projekt: e.projektName, aktualisiert: SnZeit.wann(e.gestelltAm, jetzt: jetzt))
            f.auftrag = SnZeit.titel(e.frage, 300)
            return f
        }
        if id.hasPrefix("k:"), let c = d.cards.first(where: { "k:" + $0.id == id }) {
            var f = SnFormular(projekt: HeuteLogik.boardName(d, c.boardId), aktualisiert: Self.echteAenderung(c).map { SnZeit.wann($0, jetzt: jetzt) } ?? "")
            f.auftrag = Menschlich.klartext(c.title)
            let notiz = Menschlich.klartext(c.notes)
            if !notiz.isEmpty { f.stand = Menschlich.kuerzen(notiz, 300) }
            f.frist = Menschlich.fristVon(c.labels).map { Menschlich.tagText($0, jetzt: jetzt) }
            f.ohnePrioritaet = true
            return f
        }
        return nil
    }

    private static func echteAenderung(_ c: OvKarte) -> Double? {
        var z: [Double] = [c.createdAt, c.completedAt].compactMap { $0 }
        z += c.kommentare.map(\.createdAt)
        z += c.events.filter { ["created", "moved", "comment_added"].contains($0.art) }.map(\.at)
        return z.max()
    }

    func briefing(termin: SnTermin) -> SnBriefing? { nil }

    func entscheide(aufgabe id: String, option: Int) {
        guard let e = offen(id), option >= 0, option < e.optionen.count else { return }
        ov.entscheide(e, Entscheiden.Wahl(wahl: e.optionen[option].key))
    }
}
