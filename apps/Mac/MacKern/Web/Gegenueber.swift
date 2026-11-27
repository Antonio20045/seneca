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

enum Gegenueber {
    static func homeKey(_ ov: OvDaten) -> String { "agent:\(ov.defaultAgent):main" }

    static func personen(_ team: [SenecaStand.Mitglied], _ ov: OvDaten) -> (seneca: Person, alle: [Person]) {
        let sName = team.first { $0.id == ov.defaultAgent }?.name ?? ov.label(ov.defaultAgent)
        let seneca = Person(id: ov.defaultAgent, wer: sName.isEmpty || sName == ov.defaultAgent ? "Seneca" : sName, rolle: "Stabschef", bereich: "", bereichName: "")
        let leute = team.compactMap { m -> Person? in
            guard let id = m.id, id != ov.defaultAgent else { return nil }
            return Person(id: id, wer: m.name, rolle: m.satz ?? "", bereich: "", bereichName: "")
        }
        return (seneca, [seneca] + leute)
    }

    static func passt(_ p: Person, _ q: String) -> Bool {
        "\(p.wer) \(p.rolle) \(p.id)".lowercased().contains(q)
    }
}

enum MenueTaste: Equatable { case runter, hoch, rechts, links, enter, escape, anfang }

@MainActor
final class GegenueberModell: ObservableObject {
    static var zielKey: String { "seneca-nativ.ziel" + MacPfade.profil.endung }

    @Published private(set) var ziel: ChatZiel?

    let uebersicht: OverviewStore
    let chat: ChatService
    var team: () -> [SenecaStand.Mitglied] = { [] }
    private let defaults: UserDefaults

    init(uebersicht: OverviewStore, chat: ChatService, defaults: UserDefaults = .standard) {
        self.uebersicht = uebersicht
        self.chat = chat
        self.defaults = defaults
        if let s = defaults.string(forKey: Self.zielKey), let z = try? JSONDecoder().decode(ChatZiel.self, from: Data(s.utf8)) { ziel = z }
    }

    var ov: OvDaten { uebersicht.daten }

    var aktuellerKey: String { ziel?.key ?? Gegenueber.homeKey(ov) }
    var aktuellerAgent: String { ziel?.agentId ?? ov.defaultAgent }

    var name: String {
        if let z = ziel { return personen.alle.first { $0.id == z.agentId }?.wer ?? z.name }
        return personen.seneca.wer
    }

    static func partner(fuer z: ChatZiel?, name: String) -> ChatPartner {
        guard let z else { return .seneca }
        return ChatPartner(id: z.key, kopfName: name, nominativ: name, dativ: name, platzhalter: "Schreib \(name)", festerSchluessel: z.key)
    }

    var partner: ChatPartner { Self.partner(fuer: ziel, name: name) }

    func stelleWiederHer() { chat.waehle(partner) }

    func oeffneChat(key: String, agentId: String, bereich: String? = nil) {
        let neu: ChatZiel? = key == Gegenueber.homeKey(ov) ? nil : ChatZiel(key: key, agentId: agentId, bereich: nil,
                                                                              name: personen.alle.first { $0.id == agentId }?.wer ?? ov.label(agentId))
        setzeZiel(neu)
        chat.waehle(partner)
    }

    private func setzeZiel(_ z: ChatZiel?) {
        ziel = z
        if let z, let d = try? JSONEncoder().encode(z) { defaults.set(String(decoding: d, as: UTF8.self), forKey: Self.zielKey) } else { defaults.removeObject(forKey: Self.zielKey) }
    }

    func pruefeBereich() {
        guard let z = ziel, !team().isEmpty, !team().contains(where: { $0.id == z.agentId }) else { return }
        setzeZiel(nil)
        chat.waehle(partner)
    }

    var personen: (seneca: Person, alle: [Person]) { Gegenueber.personen(team(), ov) }

    func waehle(_ p: Person) {
        if p.key != aktuellerKey { oeffneChat(key: p.key, agentId: p.id) }
    }
}
