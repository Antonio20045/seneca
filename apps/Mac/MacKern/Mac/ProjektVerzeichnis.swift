import Foundation

struct AblageProjekt: Equatable, Identifiable {
    var id: String
    var bereichId: String
    var bereichName: String
    var kurzId: String
    var name: String
    var pfad: String
    var beschreibung: String
    var agent = ""
}

struct ProjektVerzeichnis: Equatable {
    var projekte: [AblageProjekt] = []
    var agentBereich: [String: String] = [:]
    var leiterAgenten: Set<String> = []
    var home = ""

    var istLeer: Bool { projekte.isEmpty }

    static func lade(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ProjektVerzeichnis {
        let ordner = home.appendingPathComponent("Bereiche")
        let yaml = (try? String(contentsOf: ordner.appendingPathComponent("ablage.yaml"), encoding: .utf8)) ?? ""
        let json = try? Data(contentsOf: ordner.appendingPathComponent("bereiche.json"))
        return parse(ablage: yaml, bereiche: json, home: home.path)
    }

    static func parse(ablage: String, bereiche: Data?, home: String) -> ProjektVerzeichnis {
        var v = ProjektVerzeichnis()
        v.home = home
        var inBereiche = false
        var bereichId = "", bereichName = "", projektId = ""
        var aktuell: AblageProjekt?
        func schliesse() { if let a = aktuell, !a.pfad.isEmpty { v.projekte.append(a) }; aktuell = nil }
        func wert(_ s: Substring) -> String {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.count >= 2, let f = t.first, f == t.last, f == "\"" || f == "'" { t = String(t.dropFirst().dropLast()) }
            return t
        }
        for roh in ablage.split(separator: "\n", omittingEmptySubsequences: true) {
            if roh.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            let einzug = roh.prefix { $0 == " " }.count
            let zeile = roh.dropFirst(einzug)
            guard let dp = zeile.firstIndex(of: ":") else { continue }
            let schluessel = String(zeile[..<dp]).trimmingCharacters(in: .whitespaces)
            let rest = zeile[zeile.index(after: dp)...]
            if einzug == 0 { schliesse(); inBereiche = schluessel == "bereiche"; continue }
            guard inBereiche else { continue }
            switch einzug {
            case 2: schliesse(); bereichId = schluessel; bereichName = bereichId; projektId = ""
            case 4:
                if schluessel == "name" { bereichName = wert(rest) }
                if schluessel != "projekte" { continue }
            case 6:
                schliesse(); projektId = schluessel
                aktuell = AblageProjekt(id: bereichId + "/" + projektId, bereichId: bereichId, bereichName: bereichName, kurzId: projektId,
                                        name: "", pfad: "", beschreibung: "")
            case 8:
                guard aktuell != nil, !projektId.isEmpty else { continue }
                if schluessel == "pfad" { aktuell?.pfad = absolut(wert(rest), home: home) }
                if schluessel == "beschreibung" { aktuell?.beschreibung = wert(rest) }
            default: continue
            }
        }
        schliesse()
        let namen = Dictionary(uniqueKeysWithValues: Set(v.projekte.map(\.bereichId)).map { ($0, bereichsname($0, in: ablage)) })
        v.projekte = v.projekte.map { var p = $0; p.bereichName = namen[p.bereichId] ?? p.bereichName; return p }
        v.ergaenze(bereiche: bereiche, home: home)
        v.benenne()
        return v
    }

    private static func bereichsname(_ id: String, in ablage: String) -> String {
        var drin = false
        for zeile in ablage.split(separator: "\n") {
            if zeile.hasPrefix("  \(id):") { drin = true; continue }
            if drin, zeile.hasPrefix("    name:") { return zeile.dropFirst("    name:".count).trimmingCharacters(in: .whitespaces) }
            if drin, zeile.hasPrefix("  "), !zeile.hasPrefix("    ") { drin = false }
        }
        return id
    }

    static func absolut(_ pfad: String, home: String) -> String {
        var p = pfad
        if p == "~" { p = home } else if p.hasPrefix("~/") { p = home + p.dropFirst(1) }
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private mutating func ergaenze(bereiche: Data?, home: String) {
        guard let data = bereiche, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let liste = j["bereiche"] as? [[String: Any]] else { return }
        for b in liste {
            guard let id = b["id"] as? String else { continue }
            if let leiter = b["leiter"] as? String, leiter != "main" { leiterAgenten.insert(leiter) }
            for a in (b["spezialisten"] as? [String] ?? []) + [b["leiter"] as? String].compactMap({ $0 }) where agentBereich[a] == nil && a != "main" {
                agentBereich[a] = id
            }
            for u in b["unterabteilungen"] as? [[String: Any]] ?? [] {
                guard let agent = u["agent"] as? String, !agent.isEmpty else { continue }
                agentBereich[agent] = id
                if let ordner = (u["ordner"] as? String).map({ Self.absolut($0, home: home) }),
                   let i = projekte.firstIndex(where: { $0.pfad == ordner }) {
                    projekte[i].agent = agent
                    if let n = u["name"] as? String, !n.isEmpty { projekte[i].name = n }
                }
            }
        }
    }

    private mutating func benenne() {
        projekte = projekte.map { p in
            var p = p
            if p.name.isEmpty {
                let roh = p.kurzId.replacingOccurrences(of: "-", with: " ")
                let anzeige = roh.prefix(1).uppercased() + roh.dropFirst()
                p.name = p.kurzId == "allgemein" ? "\(p.bereichName) allgemein" : anzeige
            }
            return p
        }
    }

    func projekt(imText texte: [String]) -> AblageProjekt? {
        var best: (AblageProjekt, Int)?
        for p in projekte {
            let tilde = "~" + p.pfad.dropFirst(home.count)
            for variante in p.pfad.hasPrefix(home) ? [p.pfad, tilde] : [p.pfad] {
                guard best == nil || variante.count > best!.1 else { continue }
                if texte.contains(where: { Self.enthaelt($0, variante) }) { best = (p, variante.count) }
            }
        }
        return best?.0
    }

    private static func enthaelt(_ text: String, _ pfad: String) -> Bool {
        var such = text.startIndex..<text.endIndex
        while let r = text.range(of: pfad, range: such) {
            if r.upperBound == text.endIndex { return true }
            let n = text[r.upperBound]
            if !(n.isLetter || n.isNumber || n == "-" || n == "_") { return true }
            such = r.upperBound..<text.endIndex
        }
        return false
    }

    func projekt(agent: String, name: String) -> AblageProjekt? {
        if let p = projekte.first(where: { $0.agent == agent }) { return p }
        guard let bereich = agentBereich[agent] else { return nil }
        func woerter(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init).filter { $0.count >= 4 && $0 != "allgemein" })
        }
        let seine = woerter(name)
        if !seine.isEmpty {
            let treffer = projekte.filter { $0.bereichId == bereich && !woerter($0.kurzId).isDisjoint(with: seine) }
            if treffer.count == 1 { return treffer[0] }
        }
        guard leiterAgenten.contains(agent) else { return nil }
        return projekte.first(where: { $0.bereichId == bereich && $0.kurzId == "allgemein" })
    }

    func projekt(karte c: OvKarte, name: (String) -> String) -> AblageProjekt? {
        if let p = projekt(imText: [c.title, c.notes ?? ""]) { return p }
        if let a = c.agentId, !a.isEmpty { return projekt(agent: a, name: name(a)) }
        return nil
    }
}
