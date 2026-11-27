import Foundation

typealias OvRufe = (_ fn: String, _ params: [String: Any], _ timeout: Double) async throws -> [String: Any]

struct OvAusstehend: Identifiable, Equatable {
    var id: String
    var e: OvEntscheidung
    var wahl: Entscheiden.Wahl
    var ab: Double
    var idem: String
    var laeuft = false
    var toast: UUID?
}

struct PlanStand: Equatable {
    var inhalt: Plan.Inhalt?
    var kurz: Plan.Kurz?
    var geaendertAm: Double?
    var vorhanden: Bool
    var geladen: Double
}

struct OvToast: Identifiable, Equatable {
    let id: UUID
    var text: String
    var aktion: String?
    var dauer: Double
    static func == (a: OvToast, b: OvToast) -> Bool { a.id == b.id && a.text == b.text && a.aktion == b.aktion }
}

@MainActor
final class OverviewStore: ObservableObject {
    nonisolated static let rueckgaengigSekunden: Double = 10
    nonisolated static let takt: Double = 15

    @Published private(set) var daten = OvDaten() { didSet { arbeitetStand = nil } }
    @Published private(set) var jetzt: Double { didSet { arbeitetStand = nil } }
    @Published private(set) var toasts: [OvToast] = []
    @Published private(set) var weg: Set<String> = []
    @Published private(set) var plaene: [String: PlanStand] = [:]
    @Published private(set) var ausstehend: [OvAusstehend] = []
    @Published private(set) var entWeg: Set<String> = []
    @Published private(set) var lokalSpaeter: [String: Double] = [:]

    @Published private(set) var berichtRoh: [BerichteWeb.Roh] = []
    @Published private(set) var berichteFertig = false
    private var berichtSignatur = ""
    private var teamGelesen: Double = 0

    private var rufe: OvRufe
    private var verbunden: () -> Bool
    private let uhr: () -> Double
    private var aktionen: [UUID: () async -> Void] = [:]
    private var tickTask: Task<Void, Never>?
    private var ticks = 0
    private var versteckteTakte = 0
    var fensterSichtbar: @MainActor () -> Bool = { true }
    var toastDauer: Double = 5
    var ausblendPause: Double = 0.28
    var entscheidungsFenster: Double = OverviewStore.rueckgaengigSekunden
    var entscheidungsZeitgeber = true

    init(rufe: @escaping OvRufe = { _, _, _ in throw SenecaError.offline }, verbunden: @escaping () -> Bool = { true },
         uhr: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 }) {
        self.rufe = rufe
        self.verbunden = verbunden
        self.uhr = uhr
        self.jetzt = uhr()
    }

    func verdrahte(rufe: @escaping OvRufe, verbunden: @escaping () -> Bool) {
        self.rufe = rufe
        self.verbunden = verbunden
    }

    var entscheidungen: [OvEntscheidung] { daten.entRoh ?? [] }
    var entscheidungenSicht: [OvEntscheidung] { Entscheiden.alle(entscheidungen, lokalSpaeter: lokalSpaeter, weg: entWeg, jetzt: jetzt) }
    var projekte: [HeuteLogik.ProjektInfo] { HeuteLogik.projektInfos(daten, entscheidungen, jetzt: jetzt) }
    var echteProjekte: [HeuteLogik.ProjektInfo] { HeuteLogik.projektInfos(daten, entscheidungen, jetzt: jetzt, nurEchte: true) }
    var brauchtDich: Int { Zahlen.brauchtDichZahl(entscheidungen) }
    private var arbeitetStand: Zahlen.ArbeitetGerade?
    var arbeitet: Zahlen.ArbeitetGerade {
        if let a = arbeitetStand { return a }
        let a = Zahlen.arbeitetGerade(daten, jetzt: jetzt)
        arbeitetStand = a
        return a
    }
    var todos: HeuteLogik.Todos { HeuteLogik.todos(daten.cards, jetzt: jetzt) }
    var berichte: BerichteWeb.Stand { BerichteWeb.stand(roh: berichtRoh, fertig: berichteFertig, ov: daten, jetzt: jetzt) }
    var bereicheNamen: [(id: String, name: String)] { (daten.bereiche?.areas ?? []).map { ($0.id, $0.name) } }

    var heuteTodos: [HeuteLogik.TodoZeile] {
        let infos = HeuteLogik.projekte(daten).map { ($0.id, daten.pm.projekte[$0.id]?.faellig) }
        return HeuteLogik.tagesTodos(daten.cards, projekte: infos, projektName: { HeuteLogik.boardName(self.daten, $0.boardId) },
                                     tag0: Menschlich.tagStart(jetzt), jetzt: jetzt).filter { !weg.contains($0.card.id) }
    }

    var heuteZeilen: [HeuteLogik.Zeile] {
        let t0 = Menschlich.tagStart(jetzt)
        let todos = heuteTodos.compactMap { z in z.min.map { HeuteLogik.TodoEin(id: z.id, titel: z.titel, min: $0, bis: z.bis, hinweis: z.fertigWenn) } }
        return HeuteLogik.tagesZeilen(tag0: t0, jetzt: jetzt, termine: daten.kalender?.termine ?? [],
                                      laeufe: HeuteLogik.laeufeFuerTag(daten, tag0: t0, jetzt: jetzt), todos: todos)
    }

    var bisherHeute: HeuteLogik.Bisher {
        let t0 = Menschlich.tagStart(jetzt)
        return HeuteLogik.bisherHeute(zeilen: heuteZeilen, laeufe: HeuteLogik.laeufeFuerTag(daten, tag0: t0, jetzt: jetzt), jetzt: jetzt)
    }

    var laeuftN: Int { arbeitet.n }

    func uhrAnstossen() { jetzt = uhr() }

    private func stelleUhr() {
        let n = uhr()
        if abs(n - jetzt) >= 20_000 { jetzt = n }
    }

    private func setze(_ d: OvDaten) {
        var d = d
        if let l = d.liste { d.cards = Self.mitAgentAusListe(d.cards, l) }
        if d != daten { daten = d }
    }

    func setzeListe(_ l: ArbeitsListe?) {
        let sicht = l.map { ListenAuszug(agent: $0.agentJeKarte, laufend: $0.laufendeKarten.map { $0.id + "|" + $0.agent }) }
        if sicht == listenAuszug, (l == nil) == (daten.liste == nil) { return }
        listenAuszug = sicht
        var d = daten
        d.liste = l
        setze(d)
    }

    private struct ListenAuszug: Equatable { var agent: [String: String]; var laufend: [String] }
    private var listenAuszug: ListenAuszug?

    static func mitAgentAusListe(_ karten: [OvKarte], _ l: ArbeitsListe) -> [OvKarte] {
        let agent = l.agentJeKarte
        guard !agent.isEmpty else { return karten }
        return karten.map { c in
            guard let a = agent[c.id], c.agentId != a else { return c }
            var n = c; n.agentId = a; return n
        }
    }

    private func lies(_ fn: String, _ p: [String: Any] = [:]) async -> [String: Any]? {
        return try? await rufe(fn, p, 20)
    }

    func aktualisiere() async {
        guard verbunden() else { return }
        async let wb = lies("workboard.cards.list")
        async let cron = lies("cron.list")
        async let ag = lies("agents.list")
        async let kal = lies("seneca.kalender")
        async let ges = lies("seneca.gesehen")
        async let ber = lies("seneca.bereiche")
        async let str = lies("seneca.projekte")
        async let ent = lies("seneca.entscheidungen")
        let w = await wb, c = await cron, a = await ag, k = await kal
        let g = await ges, b = await ber, s = await str, e = await ent
        let neueKarten = await w.asyncMap { await self.karten(aus: $0) }
        stelleUhr()
        var d = daten
        if let s, let pm = OvProjektOrdnung(json: s) { d.pm = pm }
        if let g, let m = g["gesehen"] as? [String: Any] { d.gesehen = m.compactMapValues { ($0 as? NSNumber)?.doubleValue } }
        if let b { d.bereiche = SenecaPayloadParser.areas(b); d.unterabteilungen = Self.unterabteilungen(b) } else if d.bereiche == nil { d.bereiche = AreaRegistry() }
        if let neueKarten {
            if let neu = neueKarten.karten { d.cards = neu }
            if let bl = neueKarten.boards { d.boards = bl }
            d.workboardFehler = false
        } else { d.workboardFehler = true }
        if let c { d.jobs = (c["jobs"] as? [[String: Any]] ?? []).compactMap(OvAuftrag.init(json:)) }
        if let a {
            d.agents = (a["agents"] as? [[String: Any]] ?? []).compactMap(OvAgent.init(json:))
            d.defaultAgent = a["defaultId"] as? String ?? Hauptagent.id
        }
        if let k { d.kalender = OvKalender(json: k) } else { d.kalender = OvKalender(ok: false, fehlt: true) }
        d.entRoh = e.flatMap { $0["entscheidungen"] as? [[String: Any]] }.map { OvEntscheidung.liste(json: $0, pm: d.pm.projekte, jetzt: jetzt) }
        d.geladen = true
        setze(d)
        await ladeBerichte()
    }

    func ladeBerichte(erzwingen: Bool = false) async {
        guard verbunden(), daten.geladen else { return }
        let sig = BerichteWeb.signatur(daten.jobs)
        if !erzwingen && berichteFertig && sig == berichtSignatur { return }
        berichtSignatur = sig
        let standard = daten.defaultAgent
        var out: [BerichteWeb.Roh] = []
        for j in daten.jobs where BerichteWeb.istMelder(j) {
            guard let l = await lies("cron.runs", ["id": j.id, "limit": 60]) else { continue }
            let key = BerichteWeb.chatSchluessel(erster: (l["entries"] as? [[String: Any]])?.first?["sessionKey"] as? String, job: j, standard: standard)
            let v = await lies("chat.history", ["sessionKey": key, "agentId": BerichteWeb.berichtAgent(j, standard: standard), "limit": 200])
            if let r = BerichteWeb.rohAus(job: j, laeufe: l, verlauf: v, standard: standard) { out.append(r) }
        }
        berichtRoh = out
        berichteFertig = true
    }

    func starteAuftrag(_ id: String) async throws {
        _ = try await rufe("cron.run", ["id": id, "mode": "force"], 30)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await self?.aktualisiere()
        }
    }

    static func unterabteilungen(_ antwort: [String: Any]) -> [String: [OvUnterabteilung]] {
        func t(_ v: Any?, _ max: Int = 120) -> String { (v as? String).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max)) } ?? "" }
        var out: [String: [OvUnterabteilung]] = [:]
        for b in antwort["bereiche"] as? [[String: Any]] ?? [] {
            let id = t(b["id"], 64)
            guard !id.isEmpty, let l = b["unterabteilungen"] as? [[String: Any]] else { continue }
            out[id] = l.compactMap { u in
                let uid = t(u["id"], 64)
                return uid.isEmpty ? nil : OvUnterabteilung(id: uid, name: t(u["name"]).isEmpty ? uid : t(u["name"]), agent: t(u["agent"], 64))
            }
        }
        return out
    }

    func passeSitzungAn(_ key: String, _ aendere: (inout OvSitzung) -> Void) {
        guard let i = daten.rows.firstIndex(where: { $0.key == key }) else { return }
        var z = daten.rows[i]
        aendere(&z)
        daten.rows[i] = z
    }

    private struct Roh: @unchecked Sendable { let w: [String: Any] }
    private var zerlegt: AnyObject?

    private func karten(aus w: [String: Any]) async -> (karten: [OvKarte]?, boards: [OvBoard]?) {
        let quelle = w["cards"] as AnyObject
        if let z = zerlegt, z === quelle, !daten.cards.isEmpty { return (nil, nil) }
        let roh = Roh(w: w)
        let r = await Task.detached(priority: .userInitiated) { () -> ([OvKarte], [OvBoard]?) in
            ((roh.w["cards"] as? [[String: Any]] ?? []).compactMap(OvKarte.init(json:)).filter { !$0.archiviert },
             (roh.w["boards"] as? [[String: Any]])?.compactMap(OvBoard.init(json:)))
        }.value
        zerlegt = quelle
        return r
    }

    func aktualisiereKarten() async {
        guard verbunden(), let w = await lies("workboard.cards.list") else { return }
        let k = await karten(aus: w)
        var d = daten
        if let neu = k.karten { d.cards = neu }
        if let bl = k.boards { d.boards = bl }
        setze(d)
        stelleUhr()
    }

    func entscheide(_ e: OvEntscheidung, _ w: Entscheiden.Wahl) {
        if entWeg.contains(e.id) { return }
        var a = OvAusstehend(id: e.id, e: e, wahl: w, ab: uhr() + entscheidungsFenster * 1000, idem: UUID().uuidString.lowercased())
        entWeg.insert(e.id)
        a.toast = hinweis("Entschieden: \(Menschlich.kuerzen(Entscheiden.wahlText(e, w), 70))", aktion: "Rückgängig", dauer: entscheidungsFenster) { [weak self] in
            self?.nimmZurueck(e.id)
        }
        ausstehend.append(a)
        if entscheidungsZeitgeber {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.entscheidungsFenster ?? 10) * 1_000_000_000) + 200_000_000)
                await self?.faelligeAusfuehren()
            }
        }
    }

    @discardableResult
    func nimmZurueck(_ id: String) -> Bool {
        guard let i = ausstehend.firstIndex(where: { $0.id == id }), uhr() < ausstehend[i].ab else { return false }
        if let t = ausstehend[i].toast { schliesse(t) }
        ausstehend.remove(at: i)
        entWeg.remove(id)
        return true
    }

    func faelligeAusfuehren() async {
        let nun = uhr()
        for a in ausstehend where nun >= a.ab && !a.laeuft {
            if let i = ausstehend.firstIndex(where: { $0.id == a.id }) { ausstehend[i].laeuft = true }
            await fuehreEntscheidungAus(a)
        }
    }

    private func fuehreEntscheidungAus(_ a: OvAusstehend) async {
        defer {
            ausstehend.removeAll { $0.id == a.id }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.entWeg.remove(a.id)
            }
        }
        if let t = a.toast { schliesse(t) }
        var antwort: [String: Any] = [:]
        do {
            var p: [String: Any] = ["id": a.e.id, "wahl": a.wahl.wahl ?? NSNull(), "erwartet": a.e.updatedAt]
            if let t = a.wahl.text, !t.isEmpty { p["text"] = t }
            if let n = a.wahl.notiz, !n.isEmpty { p["notiz"] = n }
            antwort = try await rufe("seneca.entscheidung.treffen", p, 20)
        } catch {
            entWeg.remove(a.e.id)
            let t = Self.fehlertext(error).lowercased()
            if t.contains("conflict") || t.contains("konflikt") {
                await aktualisiere()
                hinweis("Die Entscheidung wurde inzwischen geändert oder ist schon erledigt. Die Liste ist neu geladen.")
            } else {
                hinweis("Konnte nicht speichern: \(Self.fehlertext(error))")
            }
            return
        }
        let key = zielSitzung(a.e, antwort["leiterSession"])
        let leiter = Gegenueber.leiterVon(daten, key.agent)
        do {
            _ = try await rufe("chat.send", ["sessionKey": key.key, "agentId": key.agent,
                                               "message": (antwort["nachricht"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Entscheiden.nachrichtAnLeiter(a.e, a.wahl),
                                               "idempotencyKey": a.idem], 60)
            let wer = Gegenueber.bereichVon(daten, a.e.bereichId)?.leaderName ?? leiter?.leaderName ?? "Seneca"
            hinweis("Entschieden: \(a.wahl.wahl ?? "anders"). \(wer) setzt es um.")
        } catch {
            let wer = (antwort["leiterName"] as? String) ?? key.agent
            hinweis("Entschieden und gespeichert, aber die Nachricht an \(wer) ging nicht raus: \(Self.fehlertext(error))")
        }
        await aktualisiere()
    }

    func zielSitzung(_ e: OvEntscheidung, _ session: Any?) -> (key: String, agent: String) {
        let k = (session as? String) ?? ((session as? [String: Any])?["key"] as? String) ?? ((session as? [String: Any])?["sessionKey"] as? String) ?? e.leiterSession
        if let k, let a = k.treffer(#"^agent:([^:]+):"#)?[1] { return (k, a) }
        let leiter = e.leiter ?? Gegenueber.bereichVon(daten, e.bereichId)?.leader ?? daten.defaultAgent
        return ("agent:\(leiter):main", leiter)
    }

    func aktualisiereSitzungen() async {
        guard verbunden(), let r = await lies("sessions.list", ["limit": 200, "configuredAgentsOnly": true, "includeDerivedTitles": true]) else { return }
        var d = daten
        d.rows = (r["sessions"] as? [[String: Any]] ?? []).compactMap(OvSitzung.init(json:))
        if let v = r["defaults"] as? [String: Any] { d.sitzungsStandard = OvSitzungsStandard(json: v) }
        setze(d)
        stelleUhr()
    }

    func starte() async {
        guard verbunden() else { return }
        _ = await lies("sessions.subscribe")
        await aktualisiere()
        await aktualisiereSitzungen()
    }

    func takteEinmal() async {
        ticks += 1
        stelleUhr()
        guard verbunden() else { return }
        if ticks % 4 == 0 { await aktualisiere() } else if daten.cards.contains(where: { $0.status == "running" }) { await aktualisiereKarten() }
        await aktualisiereSitzungen()
    }

    func startTakt(sekunden: Double = OverviewStore.takt) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(sekunden * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if !self.fensterSichtbar() {
                    self.versteckteTakte += 1
                    if self.versteckteTakte % 4 != 0 { continue }
                }
                await self.takteEinmal()
            }
        }
    }

    func stopTakt() { tickTask?.cancel(); tickTask = nil }

    private func karte(_ r: [String: Any]) -> OvKarte? { (r["card"] as? [String: Any]).flatMap(OvKarte.init(json:)) }

    func verschiebe(_ c: OvKarte, nach status: String) async throws -> OvKarte? {
        if let i = daten.cards.firstIndex(where: { $0.id == c.id }) { daten.cards[i].status = status; daten.cards[i].updatedAt = uhr() }
        do {
            var p: [String: Any] = ["id": c.id, "status": status]
            if let u = c.updatedAt { p["expectedUpdatedAt"] = u }
            let r = try await rufe("workboard.cards.move", p, 20)
            await aktualisiereKarten()
            return karte(r)
        } catch { await aktualisiereKarten(); throw error }
    }

    @discardableResult
    func todoAnlegen(_ roh: String) async throws -> HeuteLogik.Erkannt? {
        let e = HeuteLogik.notizAuswerten(roh, bereicheNamen)
        if e.titel.isEmpty { return nil }
        let label = "plan:\(Menschlich.isoTag(jetzt))" + (e.min.map { String(format: "T%02d:%02d", $0 / 60, $0 % 60) } ?? "")
        var p: [String: Any] = ["title": e.titel, "boardId": "privat", "status": "todo", "idempotencyKey": UUID().uuidString.lowercased()]
        if e.hoch { p["priority"] = "high" }
        do {
            let r = try await rufe("workboard.cards.create", p, 20)
            if let c = karte(r) {
                var labels = c.labels.filter { !$0.hasPrefix("plan:") && !$0.hasPrefix("bereich:") }
                labels.append(label)
                if let b = e.bereichId { labels.append("bereich:\(b)") }
                var patch: [String: Any] = ["labels": labels]
                if e.hoch && c.priority != "high" { patch["priority"] = "high" }
                var q: [String: Any] = ["id": c.id, "patch": patch]
                if let u = c.updatedAt { q["expectedUpdatedAt"] = u }
                _ = try await rufe("workboard.cards.update", q, 20)
            }
        } catch {
            hinweis("Konnte nicht eintragen: \(Self.fehlertext(error))")
            await aktualisiere()
            throw error
        }
        await aktualisiere()
        return e
    }

    func abhaken(_ c: OvKarte) async {
        let vorher = c.status
        weg.insert(c.id)
        if ausblendPause > 0 { try? await Task.sleep(nanoseconds: UInt64(ausblendPause * 1_000_000_000)) }
        do {
            let neu = try await verschiebe(c, nach: "done")
            weg.remove(c.id)
            let zurueck = vorher == "done" ? "todo" : vorher
            hinweis("Erledigt.", aktion: "Rückgängig", dauer: Self.rueckgaengigSekunden) { [weak self] in
                guard let self else { return }
                do { _ = try await self.verschiebe(neu ?? { var x = c; x.status = "done"; return x }(), nach: zurueck) }
                catch { self.hinweis("Ging nicht: \(Self.fehlertext(error))") }
            }
        } catch {
            weg.remove(c.id)
            hinweis("Konnte nicht abhaken: \(Self.fehlertext(error))")
        }
    }

    func aktuell(_ id: String) -> OvKarte? { daten.cards.first { $0.id == id } }

    static func schreibFehlertext(_ e: Error) -> String {
        let t = fehlertext(e)
        let k = t.lowercased()
        if k.contains("sandbox") { return "Der Start ist blockiert: Für diesen Agenten fehlt eine geeignete Sandbox. Es wurde kein Lauf gestartet." }
        if k.contains("expectedupdatedat") || k.contains("conflict") || k.contains("stale") { return "Die Aufgabe wurde inzwischen geändert. Die Liste ist neu geladen." }
        return t
    }

    func verschiebeMitHinweis(_ c: OvKarte, nach status: String, spalte: String) async {
        let vorher = c.status
        if vorher == status { return }
        do {
            let neu = try await verschiebe(aktuell(c.id) ?? c, nach: status)
            hinweis("„\(Menschlich.kuerzen(c.title, 40))“ nach \(spalte).", aktion: "Rückgängig", dauer: Self.rueckgaengigSekunden) { [weak self] in
                guard let self else { return }
                do { _ = try await self.verschiebe(self.aktuell(c.id) ?? neu ?? c, nach: vorher) }
                catch { self.hinweis("Ging nicht: \(Self.schreibFehlertext(error))") }
            }
        } catch { hinweis("Konnte nicht verschieben: \(Self.schreibFehlertext(error))") }
    }

    @discardableResult
    func aendere(_ id: String, patch: [String: Any]) async throws -> OvKarte? {
        var p: [String: Any] = ["id": id, "patch": patch]
        if let u = aktuell(id)?.updatedAt { p["expectedUpdatedAt"] = u }
        do {
            let r = try await rufe("workboard.cards.update", p, 20)
            await aktualisiereKarten()
            return karte(r) ?? aktuell(id)
        } catch { await aktualisiereKarten(); throw error }
    }

    @discardableResult
    func legeKarteAn(titel: String, boardId: String) async -> OvKarte? {
        let t = titel.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let p: [String: Any] = ["title": t, "boardId": boardId, "status": "todo", "idempotencyKey": UUID().uuidString.lowercased()]
        do {
            let r = try await rufe("workboard.cards.create", p, 20)
            await aktualisiereKarten()
            return karte(r)
        } catch { hinweis("Konnte nicht anlegen: \(Self.schreibFehlertext(error))"); return nil }
    }

    @discardableResult

    func kommentiere(_ id: String, text: String) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        do { _ = try await rufe("workboard.cards.comment", ["id": id, "body": t], 20); await aktualisiereKarten(); return true }
        catch { hinweis("Konnte nicht kommentieren: \(Self.schreibFehlertext(error))"); return false }
    }

    func starteKarte(_ id: String, agent: String?) async -> Bool {
        do {
            if let agent, !agent.isEmpty, aktuell(id)?.agentId != agent { try await aendere(id, patch: ["agentId": agent]) }
            guard let w = await lies("workboard.cards.list"),
                  let c = (w["cards"] as? [[String: Any]] ?? []).compactMap(OvKarte.init(json:)).first(where: { $0.id == id }), !c.archiviert
            else { throw SenecaError.message("Die Aufgabe gibt es nicht mehr.") }
            if let bekannt = aktuell(id)?.updatedAt, let neu = c.updatedAt, bekannt != neu {
                await aktualisiereKarten()
                throw SenecaError.message("stale")
            }
            if (c.agentId ?? "").isEmpty { throw SenecaError.message("Wähle zuerst einen Agenten aus.") }
            if (c.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SenecaError.message("Schreib zuerst in die Notiz, was das Ergebnis sein soll. Der Agent braucht einen Auftrag.")
            }
            if !["todo", "backlog", "ready"].contains(c.status) { throw SenecaError.message("Die Aufgabe ist schon in Arbeit.") }
            _ = try await rufe("workboard.cards.start", ["id": id], 60)
            await aktualisiereKarten()
            hinweis("Der Agent hat den Auftrag übernommen.")
            return true
        } catch {
            hinweis(Self.schreibFehlertext(error))
            return false
        }
    }

    func legeProjektAn(name: String, bereichId: String, ziel: String, faelligMs: Double?, meilensteine: [OvMeilenstein] = []) async -> String? {
        let id = "projekt-\(UUID().uuidString.lowercased())"
        var felder: [String: Any] = ["bereichId": bereichId, "name": name, "abteilung": "", "ziel": ziel, "status": "laeuft"]
        felder["faellig"] = faelligMs ?? NSNull()
        if !meilensteine.isEmpty { felder["meilensteine"] = meilensteine.map { ["name": $0.name, "erreicht": $0.erreicht] } }
        return await speichereProjekt(id, felder: felder) ? id : nil
    }

    func speichereProjekt(_ boardId: String, felder: [String: Any]) async -> Bool {
        do {
            let r = try await rufe("seneca.projekte.speichern", ["boardId": boardId, "felder": felder, "expectedRevision": daten.pm.revision], 20)
            if let pm = OvProjektOrdnung(json: r) { daten.pm = pm }
            else if let s = await lies("seneca.projekte"), let pm = OvProjektOrdnung(json: s) { daten.pm = pm }
            return true
        } catch { hinweis("Konnte nicht speichern: \(Self.schreibFehlertext(error))"); return false }
    }

    func ladePlan(bereichId: String?, boardId: String) async {
        let r = try? await rufe("seneca.datei", Plan.anfrageParameter(bereichId: bereichId, boardId: boardId), 20)
        let md = r?["inhalt"] as? String
        plaene[boardId] = PlanStand(inhalt: md.flatMap(Plan.aus), kurz: md.map(Plan.kurz), geaendertAm: (r?["geaendertAm"] as? NSNumber)?.doubleValue, vorhanden: md != nil, geladen: uhr())
    }

    func leseDatei(_ pfad: String) async -> String? {
        let r = try? await rufe("seneca.datei", ["pfad": pfad], 20)
        return r?["inhalt"] as? String
    }

    func ladePlaene(_ ps: [HeuteLogik.ProjektInfo], maxAlter: Double = 90_000) async {
        for p in ps {
            if let s = plaene[p.id], uhr() - s.geladen < maxAlter { continue }
            await ladePlan(bereichId: p.bereichId.isEmpty ? nil : p.bereichId, boardId: p.id)
        }
    }

    func markiere(_ ids: [String]) async {
        if ids.isEmpty { return }
        for i in ids { daten.gesehen[i] = uhr() }
        if let r = try? await rufe("seneca.gesehen.setzen", ["ids": ids], 20), let m = r["gesehen"] as? [String: Any] {
            daten.gesehen = m.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
    }

    static func fehlertext(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

    @discardableResult
    func hinweis(_ text: String, aktion: String? = nil, dauer: Double? = nil, tu: (() async -> Void)? = nil) -> UUID {
        let t = OvToast(id: UUID(), text: text, aktion: aktion, dauer: dauer ?? toastDauer)
        toasts.append(t)
        if let tu { aktionen[t.id] = tu }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(t.dauer * 1_000_000_000))
            self?.schliesse(t.id)
        }
        return t.id
    }

    func schliesse(_ id: UUID) {
        toasts.removeAll { $0.id == id }
        aktionen[id] = nil
    }

    func fuehreAus(_ id: UUID) async {
        guard let tu = aktionen[id] else { return }
        schliesse(id)
        await tu()
    }
}

private extension Optional {
    func asyncMap<U>(_ f: (Wrapped) async -> U) async -> U? {
        guard let w = self else { return nil }
        return await f(w)
    }
}
