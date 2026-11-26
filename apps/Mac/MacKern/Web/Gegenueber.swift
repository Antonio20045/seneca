import Foundation

struct ChatZiel: Equatable, Codable {
    var key: String
    var agentId: String
    var bereich: String?
    var name: String
}

struct Person: Equatable, Identifiable {
    var id: String
    var wer: String
    var rolle: String
    var bereich: String
    var bereichName: String
    var sitzung: String = ""
    var key: String { sitzung.isEmpty ? "agent:\(id):main" : sitzung }
}

struct BereichMitLeuten: Equatable, Identifiable {
    var id: String
    var name: String
    var em: String
    var leute: [Person]
}

struct Ziel: Equatable, Identifiable {
    var id: String
    var key: String
    var agentId: String
    var wer: String
    var em: String
    var unter: String
    var fehlt: Bool
}

enum Gegenueber {
    static let maxLeute = 10
    static let immerHelfer: Set<String> = ["claude", "engineer", "researcher", "pruefer"]

    static func homeKey(_ ov: OvDaten) -> String { "agent:\(ov.defaultAgent):main" }

    static func leiterVon(_ ov: OvDaten, _ agentId: String?) -> Area? {
        guard let agentId, !agentId.isEmpty, agentId != ov.defaultAgent else { return nil }
        return ov.bereiche?.areas.first { $0.leader == agentId }
    }

    static func bereichVon(_ ov: OvDaten, _ id: String?) -> Area? {
        guard let id, !id.isEmpty else { return nil }
        return ov.bereiche?.areas.first { $0.id == id }
    }

    static func istBereichsChat(_ key: String, _ ov: OvDaten) -> Bool {
        guard let m = key.treffer(#"^agent:([^:]+):main$"#), let a = m[1] else { return false }
        return a == ov.defaultAgent || leiterVon(ov, a) != nil
    }

    static func istHelfer(_ ov: OvDaten, _ agentId: String?) -> Bool {
        let id = agentId ?? ""
        if id.isEmpty || leiterVon(ov, id) != nil { return false }
        let b = ov.bereiche
        return immerHelfer.contains(id) || id.hasPrefix("sp-") || (b?.shared.contains(id) ?? false) || (b?.areas.contains { $0.specialists.contains(id) } ?? false)
    }

    static func zieleVon(_ ov: OvDaten) -> [Ziel] {
        let home = homeKey(ov)
        let name = ov.label(ov.defaultAgent)
        var liste = [Ziel(id: "seneca", key: home, agentId: ov.defaultAgent, wer: name.isEmpty ? "Seneca" : name,
                          em: ov.emoji(ov.defaultAgent).isEmpty ? "🏛️" : ov.emoji(ov.defaultAgent), unter: "Stabschef, sieht alle Bereiche", fehlt: false)]
        for b in ov.bereiche?.areas ?? [] {
            for m in b.mitarbeiter {
                liste.append(Ziel(id: m.id, key: m.sitzung.isEmpty ? "agent:\(m.id):main" : m.sitzung, agentId: m.id, wer: m.name, em: b.emoji.isEmpty ? "◦" : b.emoji,
                                  unter: m.zustaendig.isEmpty ? b.name : m.zustaendig, fehlt: !ov.agents.isEmpty && ov.agent(m.id) == nil))
            }
            guard b.mitarbeiter.isEmpty, b.leader != ov.defaultAgent else { continue }
            liste.append(Ziel(id: b.id, key: "agent:\(b.leader):main", agentId: b.leader, wer: b.leaderName, em: b.emoji.isEmpty ? "◦" : b.emoji,
                              unter: b.summary.lines.first.flatMap { $0.isEmpty ? nil : $0 } ?? "Zuständig für den Bereich \(b.name)",
                              fehlt: !ov.agents.isEmpty && ov.agent(b.leader) == nil))
        }
        return liste
    }

    static func personenVon(_ ov: OvDaten) -> (seneca: Person, bereiche: [BereichMitLeuten], alle: [Person]) {
        let sName = ov.label(ov.defaultAgent)
        let seneca = Person(id: ov.defaultAgent, wer: sName.isEmpty ? "Seneca" : sName, rolle: "Stabschef", bereich: "", bereichName: "")
        func da(_ id: String) -> Bool { ov.agents.isEmpty || ov.agent(id) != nil }
        var gesehen: Set<String> = [ov.defaultAgent]
        var bereiche: [BereichMitLeuten] = []
        for b in ov.bereiche?.areas ?? [] {
            var leute: [Person] = []
            if !b.mitarbeiter.isEmpty {
                for m in b.mitarbeiter where !gesehen.contains(m.id) {
                    gesehen.insert(m.id)
                    leute.append(Person(id: m.id, wer: m.name, rolle: m.zustaendig, bereich: b.id, bereichName: b.name, sitzung: m.sitzung))
                }
                bereiche.append(BereichMitLeuten(id: b.id, name: b.name, em: b.emoji.isEmpty ? "◦" : b.emoji, leute: leute))
                continue
            }
            func add(_ id: String, _ wer: String, _ rolle: String) {
                guard !gesehen.contains(id) else { return }
                gesehen.insert(id)
                leute.append(Person(id: id, wer: wer, rolle: rolle, bereich: b.id, bereichName: b.name))
            }
            if !istLeitung(ov, b.leader) { add(b.leader, b.leaderName, "Zuständig für \(b.name)") }
            for u in ov.unterabteilungen[b.id] ?? [] where !u.agent.isEmpty && da(u.agent) && !istLeitung(ov, u.agent) {
                let l = ov.label(u.agent)
                add(u.agent, verstaendlich(l.isEmpty ? u.name : l), "Führt die Abteilung \(u.name)")
            }
            for sp in b.specialists where !(ov.label(sp).isEmpty ? sp : ov.label(sp)).passt(#"^test\b"#, "i") && da(sp) && ov.agent(sp) != nil && !istLeitung(ov, sp) {
                let l = ov.label(sp)
                let name = verstaendlich(l.isEmpty ? sp : l)
                add(sp, name, "Arbeitet an \(name)")
            }
            bereiche.append(BereichMitLeuten(id: b.id, name: b.name, em: b.emoji.isEmpty ? "◦" : b.emoji, leute: leute))
        }
        return (seneca, bereiche, [seneca] + bereiche.flatMap { $0.leute })
    }

    static func mitarbeiterIds(_ ov: OvDaten) -> Set<String> { Set((ov.bereiche?.areas ?? []).flatMap { $0.mitarbeiter.map(\.id) }) }

    static let fruehereLeitung: Set<String> = ["sundartha", "powerbi", "openclaw-leiter"]
    static func istLeitung(_ ov: OvDaten, _ id: String) -> Bool {
        if id == ov.defaultAgent || mitarbeiterIds(ov).contains(id) { return false }
        if fruehereLeitung.contains(id) || id.hasSuffix("-leiter") { return true }
        let l = ov.label(id).lowercased()
        return l.contains("leiter") || l.contains("abgeschaltet")
    }

    static func verstaendlich(_ name: String) -> String {
        var n = name
        for endung in ["-Spezialist", "-Spezialistin", " Spezialist", "-Manager", "-Agent"] where n.hasSuffix(endung) && n.count > endung.count + 1 { n = String(n.dropLast(endung.count)) }
        return n
    }

    static func passt(_ p: Person, _ q: String) -> Bool {
        "\(p.wer) \(p.rolle) \(p.bereichName) \(p.id)".lowercased().contains(q)
    }
}

enum MenueTaste: Equatable { case runter, hoch, rechts, links, enter, escape, anfang }

enum MenueZeile: Equatable {
    case person(Person)
    case bereich(BereichMitLeuten)
}

struct MenueAuswahl: Equatable { var spalte = 1; var i = 0 }

@MainActor
final class GegenueberModell: ObservableObject {
    static var zielKey: String { "seneca-nativ.ziel" + MacPfade.profil.endung }
    static var zuletztKey: String { "seneca-nativ.zuletzt" + MacPfade.profil.endung }

    @Published private(set) var ziel: ChatZiel?
    @Published private(set) var offen = false
    @Published var filter = "" { didSet { if filter != oldValue { sel = MenueAuswahl() } } }
    @Published private(set) var sel = MenueAuswahl()
    @Published private(set) var bereichOffen = ""
    var oeffneSuche: () -> Void = {}

    let uebersicht: OverviewStore
    let chat: ChatService
    let leiste: AgentenLeiste
    private let defaults: UserDefaults

    init(uebersicht: OverviewStore, chat: ChatService, defaults: UserDefaults = .standard) {
        self.uebersicht = uebersicht
        self.chat = chat
        self.defaults = defaults
        leiste = AgentenLeiste(defaults: defaults)
        if let s = defaults.string(forKey: Self.zielKey), let z = try? JSONDecoder().decode(ChatZiel.self, from: Data(s.utf8)) { ziel = z }
    }

    var ov: OvDaten { uebersicht.daten }

    var aktuellerKey: String { ziel?.key ?? Gegenueber.homeKey(ov) }
    var aktuellerAgent: String { ziel?.agentId ?? ov.defaultAgent }

    var name: String {
        let n = ov.label(aktuellerAgent)
        if let z = ziel { return (n.isEmpty || n == z.agentId) ? z.name : n }
        return n.isEmpty ? "Seneca" : n
    }

    static func partner(fuer z: ChatZiel?, name: String) -> ChatPartner {
        guard let z else { return .seneca }
        return ChatPartner(id: z.key, kopfName: name, nominativ: name, dativ: name, platzhalter: "Schreib \(name)", festerSchluessel: z.key)
    }

    var partner: ChatPartner { Self.partner(fuer: ziel, name: name) }

    func stelleWiederHer() { chat.waehle(partner) }

    func oeffneChat(key: String, agentId: String, bereich: String? = nil) {
        let b = bereich ?? (key == "agent:\(agentId):main" ? Gegenueber.leiterVon(ov, agentId)?.id : nil)
        let neu: ChatZiel? = key == Gegenueber.homeKey(ov) ? nil : ChatZiel(key: key, agentId: agentId, bereich: (b == nil || b == "seneca") ? nil : b, name: {
            let n = ov.label(agentId); return n.isEmpty ? agentId : n
        }())
        setzeZiel(neu)
        merkeZuletzt(agentId)
        chat.waehle(partner)
    }

    private func setzeZiel(_ z: ChatZiel?) {
        ziel = z
        if let z, let d = try? JSONEncoder().encode(z) { defaults.set(String(decoding: d, as: UTF8.self), forKey: Self.zielKey) } else { defaults.removeObject(forKey: Self.zielKey) }
    }

    func oeffneChat(key: String, agentId: String) { oeffneChat(key: key, agentId: agentId, bereich: nil) }

    func merkeZuletzt(_ agentId: String) {
        guard !agentId.isEmpty, agentId != ov.defaultAgent else { return }
        let alt = defaults.stringArray(forKey: Self.zuletztKey) ?? []
        defaults.set(Array(([agentId] + alt.filter { $0 != agentId }).prefix(5)), forKey: Self.zuletztKey)
    }

    var zuletztIds: [String] { defaults.stringArray(forKey: Self.zuletztKey) ?? [] }

    func pruefeBereich() {
        guard let z = ziel else { return }
        let d = ov
        if Gegenueber.istLeitung(d, z.agentId) { setzeZiel(nil); chat.waehle(partner); return }
        if z.bereich == nil {
            if !d.agents.isEmpty && d.agent(z.agentId) == nil { setzeZiel(nil); chat.waehle(partner) }
            return
        }
        guard let reg = d.bereiche, reg.state == "ok" || reg.state == "fehlt" else { return }
        if let b = Gegenueber.bereichVon(d, z.bereich), b.leader == z.agentId { return }
        setzeZiel(nil)
        chat.waehle(partner)
        let n = d.label(d.defaultAgent)
        uebersicht.hinweis("Den Bereich gibt es nicht mehr. Du sprichst wieder mit \(n.isEmpty ? "Seneca" : n).")
    }

    var personen: (seneca: Person, bereiche: [BereichMitLeuten], alle: [Person]) { Gegenueber.personenVon(ov) }
    var q: String { filter.jsTrim.lowercased() }

    var zuletzt: [Person] {
        let p = personen
        return zuletztIds.compactMap { id in p.alle.first { $0.id == id } }.filter { $0.id != p.seneca.id }.prefix(3).map { $0 }
    }

    var treffer: [Person] { q.isEmpty ? [] : Array(personen.alle.filter { Gegenueber.passt($0, q) }.prefix(9)) }

    var spalte1: [MenueZeile] {
        let p = personen
        return [.person(p.seneca)] + zuletzt.map { .person($0) } + p.bereiche.map { .bereich($0) }
    }

    var offenerBereich: BereichMitLeuten? { personen.bereiche.first { $0.id == bereichOffen } }
    var spalte2: [Person] { Array((offenerBereich?.leute ?? []).prefix(Gegenueber.maxLeute)) }
    var ohneBereiche: Bool { ov.bereiche != nil && personen.bereiche.isEmpty }
    var nSuche: Int { q.isEmpty ? spalte1.count : treffer.count }

    func auf() {
        filter = ""
        bereichOffen = ""
        sel = MenueAuswahl()
        offen = true
        Task { [uebersicht] in await uebersicht.aktualisiere() }
    }

    func zu() { offen = false }
    func umschalten() { offen ? zu() : auf() }

    func waehle(_ p: Person) {
        zu()
        if p.key != aktuellerKey {
            let istSeneca = p.id == ov.defaultAgent
            oeffneChat(key: p.key, agentId: p.id, bereich: istSeneca ? "seneca" : Gegenueber.leiterVon(ov, p.id)?.id)
        }
    }

    func setzeAuswahl(spalte: Int, i: Int) { sel = MenueAuswahl(spalte: spalte, i: i) }
    func zeigeBereich(_ id: String) { bereichOffen = id }

    func bestaetige() {
        let s = sel
        if !q.isEmpty {
            let t = treffer
            if s.i < t.count { waehle(t[s.i]) } else { zu(); oeffneSuche() }
            return
        }
        if s.spalte == 2 { if s.i < spalte2.count { waehle(spalte2[s.i]) }; return }
        let z = spalte1
        guard s.i < z.count else { zu(); oeffneSuche(); return }
        switch z[s.i] {
        case .person(let p): waehle(p)
        case .bereich(let b): zeigeBereich(b.id); sel = MenueAuswahl(spalte: 2, i: 0)
        }
    }

    func taste(_ t: MenueTaste) {
        let n = nSuche + 1
        func setzeZeile(_ i: Int) {
            sel = MenueAuswahl(spalte: 1, i: i)
            if q.isEmpty, i < spalte1.count, case .bereich(let b) = spalte1[i] { zeigeBereich(b.id) }
        }
        switch t {
        case .runter:
            if sel.spalte == 2 { sel = MenueAuswahl(spalte: 2, i: min(sel.i + 1, max(0, spalte2.count - 1))) } else { setzeZeile((sel.i + 1) % n) }
        case .hoch:
            if sel.spalte == 2 { sel = MenueAuswahl(spalte: 2, i: max(0, sel.i - 1)) } else { setzeZeile((sel.i - 1 + n) % n) }
        case .rechts:
            if q.isEmpty, sel.spalte == 1, sel.i < spalte1.count, case .bereich = spalte1[sel.i] { sel = MenueAuswahl(spalte: 2, i: 0) }
        case .links:
            if q.isEmpty, sel.spalte == 2 { sel = MenueAuswahl(spalte: 1, i: sel.i) }
        case .anfang: sel = MenueAuswahl()
        case .enter: bestaetige()
        case .escape: zu()
        }
    }
}
