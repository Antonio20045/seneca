import Foundation

struct ChatEintrag: Equatable {
    var key: String
    var agentId: String
    var titel: String
    var haupt: Bool
    var zuletzt: Double
    var aktiv: Bool
}

enum SucheAktion: Equatable {
    case chat(key: String, agentId: String, bereich: String?)
    case projekt(id: String, karte: String?)
    case entscheidung(id: String)
    case seite(Route)
    case neuerChat
    case modellwahl
}

struct SucheTreffer: Identifiable, Equatable {
    var id: Int
    var gruppe: String
    var em: String
    var text: String
    var nebenbei: String
    var aktion: SucheAktion
}

enum Suche {
    private static let laerm = #":(cron|subagent|spawn|acp|eval|e\d+-|test|probe)"#

    static func chats(_ ov: OvDaten) -> [ChatEintrag] {
        func titel(_ s: OvSitzung) -> String { [s.label, s.derivedTitle, s.displayName].compactMap { $0 }.first { !$0.isEmpty }?.jsTrim ?? "" }
        func ok(_ s: OvSitzung) -> Bool {
            if s.archiviert || s.imHintergrund || Gegenueber.istHelfer(ov, s.agentId) { return false }
            let haupt = HeuteLogik.istHauptschluessel(s.key)
            if ["spawn", "cron", "internal"].contains(s.erzeugtDurch ?? "") { return haupt }
            if s.key.passt(laerm, "i") && !haupt { return false }
            let t = titel(s)
            if !haupt && (t.isEmpty || t.passt(#"^\[|^(main|None)$|^(eval|probe|bau:|e1-test)"#, "i")) { return false }
            return true
        }
        var liste: [ChatEintrag] = ov.rows.filter(ok).map { s in
            let haupt = HeuteLogik.istHauptschluessel(s.key)
            let t = titel(s).ersetze(#"^[\p{Extended_Pictographic}\x{FE0F}\x{200D}\s]+"#, "").ersetze(#"^[^—]+—\s*"#, "")
            return ChatEintrag(key: s.key, agentId: s.agentId ?? "", titel: haupt ? "Hauptchat" : (t.isEmpty ? "Chat" : t), haupt: haupt,
                               zuletzt: s.letzteAktion ?? s.updatedAt ?? 0, aktiv: s.live)
        }
        for a in ov.agents where !Gegenueber.istHelfer(ov, a.id) && !liste.contains(where: { $0.key == "agent:\(a.id):main" }) {
            liste.append(ChatEintrag(key: "agent:\(a.id):main", agentId: a.id, titel: "Hauptchat", haupt: true, zuletzt: 0, aktiv: false))
        }
        func rang(_ c: ChatEintrag) -> (Int, Int) { (c.agentId == ov.defaultAgent && c.haupt ? 0 : 1, c.haupt ? 0 : 1) }
        return liste.enumerated().sorted { a, b in
            let x = rang(a.element), y = rang(b.element)
            if x != y { return x < y }
            if a.element.zuletzt != b.element.zuletzt { return a.element.zuletzt > b.element.zuletzt }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func treffer(_ ov: OvDaten, entscheidungen: [OvEntscheidung] = [], eingabe: String, aktuellerKey: String, aktuellerAgent: String,
                        modellVon: (_ key: String, _ agentId: String) -> String = { _, _ in "" }) -> [SucheTreffer] {
        let s = eingabe.lowercased().jsTrim
        var r: [(g: String, em: String, tx: String, sm: String, a: SucheAktion)] = []
        func hat(_ t: String) -> Bool { t.lowercased().contains(s) }
        let ziele = Gegenueber.zieleVon(ov)
        for z in ziele {
            let b = Gegenueber.bereichVon(ov, z.id)
            if s.isEmpty || hat("\(z.wer) \(b?.name ?? "seneca stabschef") \(b?.id ?? "") bereich leiter") {
                let sm = [z.key == aktuellerKey ? "offen" : "", b.map { "Bereich \($0.name)" } ?? "", modellVon(z.key, z.agentId)].filter { !$0.isEmpty }.joined(separator: " · ")
                r.append(("Bereiche", z.em, "Mit \(z.wer) sprechen", sm, .chat(key: z.key, agentId: z.agentId, bereich: z.id)))
            }
        }
        let alleChats = chats(ov)
        for c in alleChats {
            if Gegenueber.istBereichsChat(c.key, ov) { continue }
            let wer = ov.label(c.agentId)
            if s.isEmpty ? c.haupt : hat("\(wer) \(c.titel)") {
                let em = ov.emoji(c.agentId)
                let sm = [c.key == aktuellerKey ? "offen" : (c.aktiv ? "arbeitet" : ""), modellVon(c.key, c.agentId)].filter { !$0.isEmpty }.joined(separator: " · ")
                r.append(("Chats", em.isEmpty ? "◦" : em, "\(wer) · \(c.titel)", sm, .chat(key: c.key, agentId: c.agentId, bereich: nil)))
            }
        }
        if !s.isEmpty {
            let bekannt = Set(ziele.map(\.id) + alleChats.map(\.agentId))
            for ag in ov.agents where !bekannt.contains(ag.id) && hat("\(ov.label(ag.id)) \(ag.id)") {
                let em = ov.emoji(ag.id)
                r.append(("Chats", em.isEmpty ? "◦" : em, "Mit \(ov.label(ag.id)) sprechen", "noch kein Gespräch", .chat(key: "agent:\(ag.id):main", agentId: ag.id, bereich: nil)))
            }
        }
        for p in HeuteLogik.projekte(ov) where s.isEmpty || hat("\(p.name) \(p.kontext)") {
            r.append(("Projekte", "◦", p.name + (p.kontext.isEmpty ? "" : " · \(p.kontext)"), "\(p.offen) offen", .projekt(id: p.id, karte: nil)))
        }
        if !s.isEmpty {
            for e in entscheidungen where hat("\(e.frage) \(HeuteLogik.boardName(ov, e.boardId))") {
                r.append(("Entscheidungen", "◇", e.frage, HeuteLogik.boardName(ov, e.boardId), .entscheidung(id: e.id)))
            }
            for c in ov.cards where c.title.lowercased().contains(s) || Menschlich.klartext(c.title).lowercased().contains(s) {
                r.append(("Aufgaben", c.status == "done" ? "✓" : "○", Menschlich.klartext(c.title), HeuteLogik.boardName(ov, c.boardId), .projekt(id: c.boardId, karte: c.id)))
            }
        }
        let wen = ov.label(aktuellerAgent)
        let aktionen: [(String, String, String, String, SucheAktion)] = [
            ("Aktionen", "+", "Neuer Chat mit \(wen.isEmpty ? "Seneca" : wen)", "", .neuerChat),
            ("Aktionen", "◇", "Modell für diesen Chat wählen", "", .modellwahl),
            ("Seiten", "→", "Heute", "g h", .seite(Route(.heute))),
            ("Seiten", "→", "Entscheidungen", "g e", .seite(Route(.entscheidungen))),
            ("Seiten", "→", "Projekte", "g p", .seite(Route(.projekte))),
            ("Seiten", "→", "Kalender", "g k", .seite(Route(.kalender))),
            ("Seiten", "→", "Chat", "c", .seite(Route(.chat))),
        ]
        for a in aktionen where s.isEmpty || hat(a.2) { r.append(a) }
        return r.enumerated().map { SucheTreffer(id: $0.offset, gruppe: $0.element.g, em: $0.element.em, text: $0.element.tx, nebenbei: $0.element.sm, aktion: $0.element.a) }
    }
}

@MainActor
final class SucheModell: ObservableObject {
    @Published private(set) var offen = false
    @Published var eingabe = "" { didSet { if eingabe != oldValue { auswahl = 0; rechne() } } }
    @Published private(set) var treffer: [SucheTreffer] = []
    @Published private(set) var auswahl = 0

    let uebersicht: OverviewStore
    let modelle: ModellStore
    let gegenueber: GegenueberModell
    var fuehreAus: (SucheAktion) -> Void = { _ in }

    init(uebersicht: OverviewStore, modelle: ModellStore, gegenueber: GegenueberModell) {
        self.uebersicht = uebersicht
        self.modelle = modelle
        self.gegenueber = gegenueber
    }

    func rechne() {
        guard offen else { treffer = []; return }
        let m = modelle
        treffer = Suche.treffer(uebersicht.daten, entscheidungen: uebersicht.entscheidungen, eingabe: eingabe, aktuellerKey: gegenueber.aktuellerKey,
                                aktuellerAgent: gegenueber.aktuellerAgent) { key, agent in
            guard let s = m.stand(fuer: key, agentId: agent) else { return "" }
            return Modelle.kurzName(s.name) + (s.konto.art == .key ? " · API-Key" : "")
        }
    }

    func auf() {
        eingabe = ""
        auswahl = 0
        offen = true
        rechne()
        Task { [uebersicht] in await uebersicht.aktualisiere() }
    }

    func zu() { offen = false; treffer = [] }
    func umschalten() { offen ? zu() : auf() }

    func aktualisiere() {
        guard offen else { return }
        rechne()
        auswahl = min(auswahl, max(0, treffer.count - 1))
    }

    func waehle(_ i: Int) {
        guard i >= 0, i < treffer.count else { return }
        let a = treffer[i].aktion
        zu()
        fuehreAus(a)
    }

    func setzeAuswahl(_ i: Int) { if i != auswahl { auswahl = i } }

    func taste(_ t: MenueTaste) {
        switch t {
        case .runter: auswahl = min(auswahl + 1, treffer.count - 1)
        case .hoch: auswahl = max(auswahl - 1, 0)
        case .enter: waehle(auswahl)
        case .escape: zu()
        default: break
        }
    }

    static let keineTreffer = "Nichts gefunden."
}
