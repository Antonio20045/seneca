import Foundation

struct AufgabenMeldung: Equatable, Codable {
    var id: String
    var aufgabe: String
    var zustand: String
    var titel: String
    var text: String
    var erzeugt: Date
}

struct AufgabenMeldeMerker: Equatable, Codable {
    var begonnen = false
    var gemeldet: [String] = []
    var offen: [AufgabenMeldung] = []
}

enum AufgabenMeldungen {
    static let sammelAb = 4
    static let hoechstAlter: TimeInterval = 24 * 3600
    static let offenVerfall: TimeInterval = 24 * 3600
    static let merkGroesse = 600

    static func ruhezeit(_ jetzt: Date, kalender: Calendar = .current) -> Bool {
        let h = kalender.component(.hour, from: jetzt)
        return h >= 22 || h < 7
    }

    static func meldbar(_ z: AufgabenZustand) -> Bool { z == .fertig || z == .abgebrochen || z == .haengt || z == .brauchtDich }

    static func meldung(_ a: Aufgabe, jetzt: Date) -> AufgabenMeldung? {
        let titel: String, text: String
        switch a.zustand {
        case .fertig: titel = "Fertig: " + a.titel; text = a.ergebnis ?? a.hinweis ?? "Der Auftrag ist geliefert."
        case .abgebrochen: titel = "Abgebrochen: " + a.titel; text = a.grund ?? "Es wurde kein Grund angegeben."
        case .haengt: titel = "Hängt: " + a.titel; text = a.grund ?? "Der Auftrag steht und braucht einen Blick."
        case .brauchtDich: titel = "Frage zu " + a.titel; text = a.grund ?? "Es wartet eine Frage auf dich."
        case .wartet, .laeuft: return nil
        }
        return AufgabenMeldung(id: a.id + "|" + a.zustand.rawValue, aufgabe: a.id, zustand: a.zustand.rawValue,
                               titel: Menschlich.kuerzen(titel, 90), text: Menschlich.kuerzen(text, 160), erzeugt: jetzt)
    }

    static func pruefe(_ liste: AufgabenListe, merker: inout AufgabenMeldeMerker, jetzt: Date, meldenAn: Bool = true, kalender: Calendar = .current) -> [AufgabenMeldung] {
        let erster = !merker.begonnen
        merker.begonnen = true
        let verlassen = Set(liste.aufgaben.filter { $0.vonAntonio }.flatMap { a -> [String] in
            [AufgabenZustand.haengt, .brauchtDich].filter { $0 != a.zustand }.map { a.id + "|" + $0.rawValue }
        })
        merker.gemeldet.removeAll { verlassen.contains($0) }
        var bekannt = Set(merker.gemeldet)
        var neu: [AufgabenMeldung] = []
        for a in liste.aufgaben where a.vonAntonio && meldbar(a.zustand) {
            guard let m = meldung(a, jetzt: jetzt), !bekannt.contains(m.id) else { continue }
            bekannt.insert(m.id)
            merker.gemeldet.append(m.id)
            if erster { continue }
            if a.zustand.erledigt, let ab = a.abschluss, jetzt.timeIntervalSince(ab) > hoechstAlter { continue }
            neu.append(m)
        }
        if merker.gemeldet.count > merkGroesse { merker.gemeldet.removeFirst(merker.gemeldet.count - merkGroesse) }
        if meldenAn { merker.offen.append(contentsOf: neu) }
        return faellige(liste, merker: &merker, jetzt: jetzt, meldenAn: meldenAn, kalender: kalender)
    }

    static func faellige(_ liste: AufgabenListe, merker: inout AufgabenMeldeMerker, jetzt: Date, meldenAn: Bool = true, kalender: Calendar = .current) -> [AufgabenMeldung] {
        guard meldenAn else { merker.offen = []; return [] }
        merker.offen.removeAll { jetzt.timeIntervalSince($0.erzeugt) > offenVerfall }
        guard !ruhezeit(jetzt, kalender: kalender), !merker.offen.isEmpty else { return [] }
        let gelten = merker.offen.filter { m in
            guard m.zustand == AufgabenZustand.haengt.rawValue || m.zustand == AufgabenZustand.brauchtDich.rawValue else { return true }
            return liste.aufgabe(m.aufgabe)?.zustand.rawValue == m.zustand
        }
        merker.offen = []
        return zusammen(gelten)
    }

    static func zusammen(_ ms: [AufgabenMeldung]) -> [AufgabenMeldung] {
        var aus: [AufgabenMeldung] = []
        for z in AufgabenZustand.allCases {
            let gruppe = ms.filter { $0.zustand == z.rawValue }
            guard !gruppe.isEmpty else { continue }
            if gruppe.count < sammelAb { aus.append(contentsOf: gruppe); continue }
            let n = gruppe.count
            let titel: String, text: String
            switch z {
            case .fertig: titel = "Fertig"; text = "\(n) Aufträge sind fertig."
            case .abgebrochen: titel = "Abgebrochen"; text = "\(n) Aufträge wurden abgebrochen."
            case .haengt: titel = "Hängt"; text = "\(n) Aufträge hängen."
            case .brauchtDich: titel = "Fragen"; text = "\(n) Aufträge haben eine Frage an dich."
            case .wartet, .laeuft: continue
            }
            aus.append(AufgabenMeldung(id: "sammel|" + (gruppe.first?.id ?? ""), aufgabe: "", zustand: z.rawValue, titel: titel, text: text, erzeugt: gruppe[0].erzeugt))
        }
        return aus
    }
}

struct GesehenRegel: Equatable {
    static let mindestSekunden: TimeInterval = 3

    private(set) var seit: Date?
    private(set) var bekannt: Set<String> = []

    mutating func zeigt(_ ids: Set<String>, jetzt: Date) {
        guard !ids.isEmpty else { return }
        if seit == nil || !ids.isSubset(of: bekannt) { seit = jetzt }
        bekannt = ids
    }

    mutating func verlassen(jetzt: Date) -> Bool {
        defer { seit = nil; bekannt = [] }
        guard let s = seit else { return false }
        return jetzt.timeIntervalSince(s) >= Self.mindestSekunden
    }

    mutating func wiederSichtbar(jetzt: Date) { if !bekannt.isEmpty { seit = jetzt } }
}

extension BoardSicht {
    var nurFragenSatz: String { Self.nurFragenSatz(fragen) }
    static func nurFragenSatz(_ fragen: Int) -> String {
        fragen > 0 ? ListenText.anzahl(fragen, "Frage", "Fragen") + (fragen == 1 ? " wartet" : " warten") + " auf dich" : ""
    }
}

extension AufgabenListe {
    var laeuftInsgesamt: Int { offeneArbeit().filter { $0.zustand == .laeuft }.count }
}
