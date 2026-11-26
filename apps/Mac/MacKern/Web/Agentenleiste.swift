import Foundation

enum Agentenleiste {
    static let maxKugeln = 5
    static let fensterTage = 14.0
    static let halbwertTage = 3.0
    static let wahlGewicht = 5.0
    static let tagMs = 86_400_000.0

    struct Zaehlung: Equatable, Codable {
        var nachrichten: [String: [Double]] = [:]
        var wahlen: [String: [Double]] = [:]

        func bereinigt(jetzt: Double) -> Zaehlung {
            let seit = jetzt - fensterTage * tagMs
            func k(_ d: [String: [Double]]) -> [String: [Double]] { d.compactMapValues { let l = $0.filter { $0 >= seit }; return l.isEmpty ? nil : l } }
            return Zaehlung(nachrichten: k(nachrichten), wahlen: k(wahlen))
        }
    }

    static func gewicht(zeit: Double, jetzt: Double) -> Double {
        let alter = max(0, (jetzt - zeit) / tagMs)
        return alter > fensterTage ? 0 : pow(0.5, alter / halbwertTage)
    }

    static func punkte(_ z: Zaehlung, id: String, jetzt: Double) -> Double {
        (z.nachrichten[id] ?? []).reduce(0) { $0 + gewicht(zeit: $1, jetzt: jetzt) }
            + (z.wahlen[id] ?? []).reduce(0) { $0 + wahlGewicht * gewicht(zeit: $1, jetzt: jetzt) }
    }

    static func kandidaten(_ ov: OvDaten) -> [Person] {
        let p = Gegenueber.personenVon(ov)
        return p.bereiche.flatMap(\.leute).filter { aktiv($0, ov) }
    }

    static func aktiv(_ x: Person, _ ov: OvDaten) -> Bool {
        if Gegenueber.mitarbeiterIds(ov).contains(x.id) { return true }
        guard let z = ov.rows.first(where: { $0.key == x.key }) else { return true }
        return !z.archiviert && !z.imHintergrund
    }

    static func auswahl(kandidaten: [Person], arbeitend: Set<String>, zaehlung: Zaehlung, jetzt: Double) -> [Person] {
        var gesehen = Set<String>()
        let einmalig = kandidaten.filter { gesehen.insert($0.id).inserted }
        let bewertet = einmalig.enumerated().map { (i: $0.offset, p: $0.element, s: punkte(zaehlung, id: $0.element.id, jetzt: jetzt)) }
        let (a, b) = (bewertet.filter { arbeitend.contains($0.p.id) }, bewertet.filter { !arbeitend.contains($0.p.id) && $0.s > 0 })
        func ordnung(_ x: (i: Int, p: Person, s: Double), _ y: (i: Int, p: Person, s: Double)) -> Bool { x.s != y.s ? x.s > y.s : x.i < y.i }
        return Array((a.sorted(by: ordnung) + b.sorted(by: ordnung)).prefix(maxKugeln).map(\.p))
    }

    struct Gruppe: Equatable, Identifiable {
        var id: String
        var titel: String
        var leute: [Person]
    }

    static func alle(_ ov: OvDaten, suche: String = "") -> [Gruppe] {
        let q = suche.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let p = Gegenueber.personenVon(ov)
        var gruppen = p.bereiche.map { Gruppe(id: $0.id, titel: $0.name, leute: $0.leute.filter { aktiv($0, ov) }) }
        let bekannt = Set(p.alle.map(\.id))
        let ausListe = !Gegenueber.mitarbeiterIds(ov).isEmpty
        let weitere = ov.agents.compactMap { a -> Person? in
            guard !ausListe, !bekannt.contains(a.id), !Gegenueber.istHelfer(ov, a.id), !Gegenueber.istLeitung(ov, a.id),
                  ov.rows.contains(where: { $0.key == "agent:\(a.id):main" }) else { return nil }
            let l = ov.label(a.id)
            let name = l.isEmpty ? a.id : l
            if name.passt(#"^test\b"#, "i") || a.id.passt(#"(^|-)test($|-)"#, "i") { return nil }
            return Person(id: a.id, wer: name, rolle: "Agent", bereich: "weitere", bereichName: "Weitere")
        }.filter { aktiv($0, ov) }
        gruppen.append(Gruppe(id: "weitere", titel: "Weitere", leute: weitere))
        return gruppen.map { g in
            Gruppe(id: g.id, titel: g.titel, leute: q.isEmpty ? g.leute : g.leute.filter { Gegenueber.passt($0, q) })
        }.filter { !$0.leute.isEmpty }
    }

    nonisolated static func nachrichtenZeiten(_ zeilen: [[String: Any]], seit: Double) -> [Double] {
        func zeit(_ m: [String: Any]) -> Double? {
            if let n = m["timestamp"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
            return nil
        }
        let nah = zeilen.filter { (zeit($0) ?? .infinity) >= seit }
        return Zuege.toItems(nah).compactMap { i -> Double? in
            if case .user(_, _, let ts?, false) = i, ts >= seit { return ts }
            return nil
        }
    }
}

@MainActor
final class AgentenLeiste: ObservableObject {
    static var schluessel: String { "seneca-nativ.leiste" + MacPfade.profil.endung }

    @Published private(set) var zaehlung: Agentenleiste.Zaehlung
    @Published private(set) var rechnet = false
    private let defaults: UserDefaults
    private let uhr: () -> Double
    private var rufe: OvRufe?
    private var gestartet = false

    init(defaults: UserDefaults = .standard, uhr: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 }) {
        self.defaults = defaults
        self.uhr = uhr
        var z = Agentenleiste.Zaehlung()
        if let s = defaults.string(forKey: Self.schluessel), let d = try? JSONDecoder().decode(Agentenleiste.Zaehlung.self, from: Data(s.utf8)) { z = d }
        zaehlung = z.bereinigt(jetzt: uhr())
    }

    func verdrahte(rufe: @escaping OvRufe) { self.rufe = rufe }

    func schreibe(an agentId: String) {
        guard !agentId.isEmpty else { return }
        var z = zaehlung
        z.nachrichten[agentId, default: []].append(uhr())
        setze(z)
    }

    func merkeWahl(_ agentId: String) {
        guard !agentId.isEmpty else { return }
        var z = zaehlung
        z.wahlen[agentId, default: []].append(uhr())
        setze(z)
    }

    func kugeln(_ ov: OvDaten, arbeitend: Set<String>) -> [Person] {
        Agentenleiste.auswahl(kandidaten: Agentenleiste.kandidaten(ov), arbeitend: arbeitend, zaehlung: zaehlung, jetzt: uhr())
    }

    private func setze(_ z: Agentenleiste.Zaehlung) {
        let b = z.bereinigt(jetzt: uhr())
        zaehlung = b
        if let d = try? JSONEncoder().encode(b) { defaults.set(String(decoding: d, as: UTF8.self), forKey: Self.schluessel) }
    }

    func starte(uebersicht: OverviewStore) async {
        guard !gestartet, let rufe else { return }
        gestartet = true
        for _ in 0..<60 where uebersicht.daten.rows.isEmpty || uebersicht.daten.bereiche == nil { try? await Task.sleep(for: .milliseconds(500)) }
        let ov = uebersicht.daten
        let jetzt = uhr()
        let seit = jetzt - Agentenleiste.fensterTage * Agentenleiste.tagMs
        let ziele = Agentenleiste.kandidaten(ov).filter { p in
            guard let z = ov.rows.first(where: { $0.key == p.key }) else { return false }
            return max(z.updatedAt ?? 0, z.letzteAktion ?? 0) >= seit
        }
        rechnet = true
        defer { rechnet = false }
        for p in ziele {
            guard let zeiten = await zaehle(key: p.key, seit: seit, rufe: rufe) else { continue }
            var z = zaehlung
            z.nachrichten[p.id] = zeiten.isEmpty ? nil : zeiten
            setze(z)
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private struct Roh: @unchecked Sendable { let zeilen: [[String: Any]] }

    private func zaehle(key: String, seit: Double, rufe: @escaping OvRufe) async -> [Double]? {
        var alle: [[String: Any]] = []
        var offset: Int?
        for _ in 0..<4 {
            guard let r = try? await rufe("chat.verlauf", ChatSpeicher.parameter(sessionKey: key, offset: offset), 30) else { return alle.isEmpty ? nil : await auswerten(alle, seit: seit) }
            let m = r["messages"] as? [[String: Any]] ?? []
            alle = m + alle
            let aelteste = (m.first?["timestamp"] as? NSNumber)?.doubleValue ?? 0
            guard (r["hasMore"] as? Bool) == true, !m.isEmpty, aelteste >= seit else { break }
            offset = (r["nextOffset"] as? Int) ?? (m.count + (offset ?? 0))
        }
        return await auswerten(alle, seit: seit)
    }

    private func auswerten(_ zeilen: [[String: Any]], seit: Double) async -> [Double] {
        let roh = Roh(zeilen: zeilen)
        return await Task.detached(priority: .utility) { Agentenleiste.nachrichtenZeiten(roh.zeilen, seit: seit) }.value
    }
}
