import SwiftUI

enum SnStatus { case wartetAufDich, wartet, laeuft, fertig }

struct SnAgent: Identifiable, Equatable {
    let id: String
    let name: String
    let initial: String
}

struct SnAufgabe: Identifiable, Equatable {
    let id: String
    let projekt: String
    let agentId: String
    let status: SnStatus
    let prio: Int
    let titel: String
    let seit: String
    let frist: String?
    let heuteFertig: Bool
    var stufe: String = ""
    var alarm: Bool = false
}

struct SnTermin: Identifiable, Equatable {
    var id: String { zeit + titel }
    let zeit: String
    let titel: String
    let nebenzeile: String
    let hatBriefing: Bool
}

struct SnNotiz: Identifiable, Equatable, Codable {
    let id: String
    let titel: String
    let meta: String
    let ueberfaellig: Bool
}

@MainActor
protocol SenecaDatenQuelle {
    var agenten: [SnAgent] { get }
    var aufgaben: [SnAufgabe] { get }
    var termine: [SnTermin] { get }
    var notizen: [SnNotiz] { get }
    var istEcht: Bool { get }
    var hinweis: String? { get }
}

extension SenecaDatenQuelle {
    var istEcht: Bool { false }
    var hinweis: String? { nil }
    func agent(_ id: String) -> SnAgent { agenten.first { $0.id == id } ?? SnAgent(id: id, name: id, initial: "") }
}

struct BeispielDaten: SenecaDatenQuelle {
    let agenten = [
        SnAgent(id: "seneca", name: "Seneca", initial: ""),
        SnAgent(id: "mara", name: "Mara", initial: "M"),
        SnAgent(id: "jonas", name: "Jonas", initial: "J"),
        SnAgent(id: "tim", name: "Tim", initial: "T"),
    ]

    let aufgaben = [
        SnAufgabe(id: "lief", projekt: "Alpha", agentId: "mara", status: .wartetAufDich, prio: 1, titel: "Lieferant für Alpha auswählen", seit: "seit 4 Tagen", frist: "Entscheidung bis 17:00", heuteFertig: false),
        SnAufgabe(id: "mail", projekt: "Hermes", agentId: "tim", status: .wartetAufDich, prio: 2, titel: "Onboarding-Mail freigeben", seit: "seit gestern", frist: "Freigabe bis 16:00", heuteFertig: false),
        SnAufgabe(id: "sauger", projekt: "Flur", agentId: "jonas", status: .wartetAufDich, prio: 3, titel: "Neuen Staubsauger kaufen?", seit: "seit Samstag", frist: "Angebot bis Do.", heuteFertig: false),
        SnAufgabe(id: "vertrag", projekt: "Alpha", agentId: "mara", status: .wartet, prio: 2, titel: "Liefervertrag vorbereiten", seit: "wartet auf: Lieferant auswählen", frist: nil, heuteFertig: false),
        SnAufgabe(id: "protokolle", projekt: "Hermes", agentId: "tim", status: .laeuft, prio: 1, titel: "Anrufprotokolle der Testwoche prüfen", seit: "seit 40 Min.", frist: nil, heuteFertig: false),
        SnAufgabe(id: "abnahme", projekt: "Alpha", agentId: "mara", status: .laeuft, prio: 2, titel: "Abnahmeprotokoll entwerfen", seit: "seit 2 Std.", frist: nil, heuteFertig: false),
        SnAufgabe(id: "leisten", projekt: "Flur", agentId: "jonas", status: .laeuft, prio: 3, titel: "Preise für Bodenleisten einholen", seit: "seit gestern", frist: nil, heuteFertig: false),
        SnAufgabe(id: "bausatz", projekt: "Gewächshaus", agentId: "seneca", status: .laeuft, prio: 3, titel: "Gewächshaus-Bausätze vergleichen", seit: "seit 3 Tagen", frist: nil, heuteFertig: false),
        SnAufgabe(id: "plan", projekt: "Alpha", agentId: "mara", status: .fertig, prio: 1, titel: "Projektplan prüfen", seit: "heute 09:12", frist: nil, heuteFertig: true),
        SnAufgabe(id: "seite", projekt: "Hermes", agentId: "tim", status: .fertig, prio: 2, titel: "Entwürfe der Hermes-Seite prüfen", seit: "heute 08:30", frist: nil, heuteFertig: true),
        SnAufgabe(id: "farbe", projekt: "Flur", agentId: "jonas", status: .fertig, prio: 3, titel: "Wandfarbe bestellen", seit: "heute 07:50", frist: nil, heuteFertig: true),
        SnAufgabe(id: "short", projekt: "Alpha", agentId: "mara", status: .fertig, prio: 2, titel: "Lieferanten-Shortlist erstellen", seit: "Freitag", frist: nil, heuteFertig: false),
    ]

    let termine = [
        SnTermin(zeit: "12:30", titel: "Mittag mit Nora", nebenzeile: "in 50 Minuten · Café Lindner", hatBriefing: false),
        SnTermin(zeit: "14:00", titel: "Call mit Lieferant B", nebenzeile: "Teams · 30 Minuten", hatBriefing: true),
        SnTermin(zeit: "15:00", titel: "Zahnarzt", nebenzeile: "45 Minuten", hatBriefing: false),
        SnTermin(zeit: "17:00", titel: "Spaziergang", nebenzeile: "eine Stunde", hatBriefing: false),
    ]

    let notizen = [
        SnNotiz(id: "steuer", titel: "Steuerunterlagen sortieren", meta: "seit 28.10.", ueberfaellig: true),
        SnNotiz(id: "zahn", titel: "Zahnarzttermin bestätigen", meta: "bis 14:00", ueberfaellig: false),
        SnNotiz(id: "lena", titel: "Geschenk für Lena besorgen", meta: "", ueberfaellig: false),
    ]
}

@MainActor
final class NotizblockModell: ObservableObject {
    @Published private(set) var eintraege: [SnNotiz]
    @Published private(set) var erledigt: Set<String> = []
    private let speicher: URL?

    private struct Stand: Codable { var eintraege: [SnNotiz]; var erledigt: [String] }

    init(start: [SnNotiz], speicher: URL? = nil) {
        self.speicher = speicher
        eintraege = start
        if let u = speicher, let d = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(Stand.self, from: d) {
            eintraege = s.eintraege
            erledigt = Set(s.erledigt)
        }
    }

    var fortschritt: Double {
        eintraege.isEmpty ? 0 : Double(eintraege.filter { erledigt.contains($0.id) }.count) / Double(eintraege.count)
    }

    func umschalten(_ id: String) {
        if erledigt.contains(id) { erledigt.remove(id) } else { erledigt.insert(id) }
        sichere()
    }

    func anlegen(_ titel: String) {
        let t = titel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        eintraege.insert(SnNotiz(id: UUID().uuidString, titel: t, meta: "", ueberfaellig: false), at: 0)
        sichere()
    }

    private func sichere() {
        guard let u = speicher, let d = try? JSONEncoder().encode(Stand(eintraege: eintraege, erledigt: Array(erledigt))) else { return }
        try? d.write(to: u, options: .atomic)
    }
}

struct SnSpalte: Identifiable {
    let id: String
    let titel: String
    let eintraege: [SnAufgabe]
    let weitere: Int
}

enum SnHeute {
    static let maximum = 3

    static func spalten(_ aufgaben: [SnAufgabe], maximum: Int = SnHeute.maximum, nurHeuteFertig: Bool = true) -> [SnSpalte] {
        let sichtbar = aufgaben.filter { !nurHeuteFertig || $0.status != .fertig || $0.heuteFertig }
        func nachPrio(_ l: [SnAufgabe]) -> [SnAufgabe] { l.sorted { $0.prio < $1.prio } }
        let gruppen: [(String, String, [SnAufgabe])] = [
            ("wartet", "Wartet", nachPrio(sichtbar.filter { $0.status == .wartetAufDich }) + nachPrio(sichtbar.filter { $0.status == .wartet })),
            ("laeuft", "Läuft", nachPrio(sichtbar.filter { $0.status == .laeuft })),
            ("fertig", "Fertig", nachPrio(sichtbar.filter { $0.status == .fertig })),
        ]
        return gruppen.map { SnSpalte(id: $0.0, titel: $0.1, eintraege: Array($0.2.prefix(maximum)), weitere: max(0, $0.2.count - maximum)) }
    }

    static func satz(entscheidungen n: Int) -> (String, String) {
        switch n {
        case ...0: return ("Alles entschieden, ", "dein Team arbeitet.")
        case 1: return ("Eine Entscheidung wartet ", "noch auf dich.")
        case 2: return ("Zwei Entscheidungen ", "warten auf dich.")
        default: return ("Drei Entscheidungen warten auf dich, ", "die erste bis 17 Uhr.")
        }
    }
}
