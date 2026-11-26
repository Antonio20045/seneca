import Foundation

struct StatGewichtProbe: Codable, Equatable {
    var start: Date
    var kg: Double
}

struct StatLaufDetails: Equatable {
    var kmZeiten: [StatKm]?
    var pulsMittel: Double?
    var pulsMax: Double?
}

enum StatHealthGrund {
    case vordergrund
    case statistikOffen

    var maxAlter: TimeInterval {
        switch self {
        case .vordergrund: return 30
        case .statistikOffen: return 10 * 60
        }
    }
}

struct StatHealthStand: Codable, Equatable {
    static let aktuelleVersion = 1
    static let fensterTage = 400

    var version = StatHealthStand.aktuelleVersion
    var laeufe: [String: StatLauf] = [:]
    var fertig: Set<String> = []
    var gewichte: [String: StatGewichtProbe] = [:]
    var ankerLauf: Data?
    var ankerGewicht: Data?
    var aktualisiert: Date?

    mutating func uebernehmen(laeufe neu: [StatLauf], geloescht: [String], anker: Data?, seit: Date) {
        let hatteDaten = !laeufe.isEmpty
        for l in neu where laeufe[l.id] == nil && l.start >= seit { laeufe[l.id] = l }
        for id in geloescht { laeufe[id] = nil; fertig.remove(id) }
        for (id, l) in laeufe where l.start < seit { laeufe[id] = nil; fertig.remove(id) }
        fertig = fertig.filter { laeufe[$0] != nil }
        if hatteDaten || !neu.isEmpty || !geloescht.isEmpty { ankerLauf = anker }
    }

    mutating func uebernehmen(gewichte neu: [String: StatGewichtProbe], geloescht: [String], anker: Data?, seit: Date) {
        let hatteDaten = !gewichte.isEmpty
        for (id, p) in neu where p.start >= seit { gewichte[id] = p }
        for id in geloescht { gewichte[id] = nil }
        for (id, p) in gewichte where p.start < seit { gewichte[id] = nil }
        if hatteDaten || !neu.isEmpty || !geloescht.isEmpty { ankerGewicht = anker }
    }

    mutating func uebernehmen(details: [String: StatLaufDetails]) {
        for (id, d) in details {
            guard var l = laeufe[id] else { continue }
            l.kmZeiten = d.kmZeiten
            l.pulsMittel = d.pulsMittel
            l.pulsMax = d.pulsMax
            laeufe[id] = l
            fertig.insert(id)
        }
    }

    var offeneDetails: [String] {
        laeufe.values.filter { !fertig.contains($0.id) }.sorted { $0.start > $1.start }.map(\.id)
    }

    var laeufeSortiert: [StatLauf] { laeufe.values.sorted { $0.start < $1.start } }

    var gewichtProTag: [String: Double] {
        var proTag: [String: Double] = [:]
        for (_, p) in gewichte.sorted(by: { ($0.value.start, $0.key) < ($1.value.start, $1.key) }) {
            proTag[StatKalender.schluessel(p.start)] = p.kg
        }
        return proTag
    }

    func braucht(_ grund: StatHealthGrund, jetzt: Date) -> Bool {
        guard let a = aktualisiert else { return true }
        if !offeneDetails.isEmpty || a > jetzt { return true }
        return jetzt.timeIntervalSince(a) >= grund.maxAlter
    }

    static var standarddatei: URL {
        let ordner = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return ordner.appendingPathComponent("StatHealth.json")
    }

    static func laden(von url: URL) -> StatHealthStand {
        guard let daten = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(StatHealthStand.self, from: daten),
              s.version == aktuelleVersion else { return StatHealthStand() }
        return s
    }

    func speichern(nach url: URL) {
        guard let daten = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? daten.write(to: url, options: .atomic)
    }
}
