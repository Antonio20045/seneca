import Foundation

struct StatKmSample: Equatable {
    var von: Date
    var bis: Date
    var meter: Double
}

struct StatKm: Equatable, Codable {
    var label: String
    var sekunden: Double
    var meter: Double
    var pace: Double { meter > 0 ? sekunden * 1000 / meter : 0 }
    var voll: Bool { meter >= 999.5 }
}

struct StatLauf: Equatable, Identifiable, Codable {
    var id: String
    var start: Date
    var dauer: Double
    var meter: Double
    var kcal: Double? = nil
    var aufstieg: Double? = nil
    var pulsMittel: Double? = nil
    var pulsMax: Double? = nil
    var quelle: String = ""
    var kmZeiten: [StatKm]? = nil

    var km: Double { meter / 1000 }
    var pace: Double { km > 0 ? dauer / km : 0 }
}

enum StatLaufRechnen {
    static func kmZeiten(_ samples: [StatKmSample]) -> [StatKm]? {
        let s = samples.filter { $0.meter > 0 && $0.bis >= $0.von }.sorted { $0.von < $1.von }
        guard s.count >= 2, let erster = s.first, let letzter = s.last else { return nil }
        let t0 = erster.von
        var ergebnis: [StatKm] = []
        var summe = 0.0
        var naechster = 1000.0
        var letzteMarke = 0.0
        for sample in s {
            let dauer = sample.bis.timeIntervalSince(sample.von)
            let startRel = sample.von.timeIntervalSince(t0)
            var verbraucht = 0.0
            while summe + (sample.meter - verbraucht) >= naechster - 1e-6 {
                verbraucht += naechster - summe
                let t = startRel + dauer * (verbraucht / sample.meter)
                ergebnis.append(StatKm(label: "\(ergebnis.count + 1)", sekunden: t - letzteMarke, meter: 1000))
                letzteMarke = t
                summe = naechster
                naechster += 1000
            }
            summe += sample.meter - verbraucht
        }
        let rest = summe - Double(ergebnis.count) * 1000
        if rest >= 100 {
            let ende = letzter.bis.timeIntervalSince(t0)
            let zehntel = min(9, Int((rest / 100).rounded()))
            ergebnis.append(StatKm(label: ",\(zehntel)", sekunden: max(1, ende - letzteMarke), meter: rest))
        }
        return ergebnis.isEmpty ? nil : ergebnis
    }
}

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
    static let aktuelleVersion = 2
    static let fensterTage = 400

    var version = StatHealthStand.aktuelleVersion
    var laeufe: [String: StatLauf] = [:]
    var fertig: Set<String> = []
    var gewichte: [String: StatGewichtProbe] = [:]
    var ankerLauf: Data?
    var ankerGewicht: Data?
    var aktualisiert: Date?
    var gemeldet: Set<String> = []
    var spurGemeldet: Set<String>? = nil

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

    var zuMelden: [(id: String, art: String, werte: [String: JSONWert])] {
        let l = laeufe.values.filter { fertig.contains($0.id) && !gemeldet.contains($0.id) }.map { l in
            var w: [String: JSONWert] = ["km": .zahl((l.km * 100).rounded() / 100), "dauer_s": .zahl(l.dauer.rounded()), "quelle": .text(l.quelle)]
            if let a = l.aufstieg { w["hm"] = .zahl(a.rounded()) }
            if let p = l.pulsMittel { w["puls"] = .zahl(p.rounded()) }
            if let k = l.kmZeiten?.filter(\.voll), !k.isEmpty { w["km_s"] = .liste(k.map { .zahl($0.sekunden.rounded()) }) }
            return (id: l.id, art: "lauf", werte: w)
        }
        let g = gewichte.filter { !gemeldet.contains($0.key) }.map { (id: $0.key, art: "gewicht", werte: ["kg": JSONWert.zahl(($0.value.kg * 10).rounded() / 10)]) }
        return l + g
    }

    var offeneSpuren: [String] {
        laeufe.values.filter { gemeldet.contains($0.id) && !(spurGemeldet ?? []).contains($0.id) }.sorted { $0.start > $1.start }.map(\.id)
    }

    var offeneDetails: [String] {
        laeufe.values.filter { !fertig.contains($0.id) }.sorted { $0.start > $1.start }.map(\.id)
    }

    func braucht(_ grund: StatHealthGrund, jetzt: Date) -> Bool {
        guard let a = aktualisiert else { return true }
        if !offeneDetails.isEmpty || !offeneSpuren.isEmpty || a > jetzt { return true }
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
