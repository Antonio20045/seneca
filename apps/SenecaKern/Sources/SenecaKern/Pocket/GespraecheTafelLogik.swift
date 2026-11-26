import Foundation

enum GespraecheTafelLogik {
    enum Punkt { case arbeitet, wartet, fertig, ruht }

    struct Zeile: Equatable {
        var text: String
        var hervor = false
    }

    static func fragen(_ s: SenecaStand, von name: String) -> [SenecaStand.Frage] {
        ((s.braucht_dich ?? []) + (s.buendel?.fragen ?? [])).filter { $0.von == name && $0.antwort == nil }
    }

    private static func anzahl(_ n: Int) -> String { n == 1 ? "1 Frage" : "\(n) Fragen" }

    static func mitglied(_ m: SenecaStand.Mitglied, _ s: SenecaStand) -> (punkt: Punkt, zeilen: [Zeile]) {
        let n = fragen(s, von: m.name).count
        switch m.zustand {
        case "arbeitet", "hängt":
            return (.arbeitet, [Zeile(text: (m.satz ?? "arbeitet") + (n > 0 ? " · " : ""))] + (n > 0 ? [Zeile(text: anzahl(n), hervor: true)] : []))
        case "ruht": return (.ruht, [Zeile(text: "ruht")])
        default:
            if n > 0 { return (.wartet, [Zeile(text: "wartet auf dich · \(anzahl(n))", hervor: true)]) }
            if let z = m.zuletzt, let satz = z.satz { return (.fertig, [Zeile(text: "fertig · \(satz)" + (z.um.map { " · \(HeuteTafelLogik.uhr($0))" } ?? ""))]) }
            return (.fertig, [Zeile(text: "frei")])
        }
    }

    static func leiste(_ s: SenecaStand) -> [(m: SenecaStand.Mitglied, punkt: Punkt, zeilen: [Zeile])] {
        let rang: [Punkt] = [.arbeitet, .wartet, .fertig, .ruht]
        return (s.team ?? []).filter { $0.id != Hauptagent.id }.map { m in let z = mitglied(m, s); return (m, z.punkt, z.zeilen) }
            .filter { $0.punkt != .fertig || $0.m.zuletzt != nil }
            .enumerated().sorted { (rang.firstIndex(of: $0.element.punkt) ?? 9, $0.offset) < (rang.firstIndex(of: $1.element.punkt) ?? 9, $1.offset) }.map(\.element)
    }

    static func laufSatz(_ m: SenecaStand.Mitglied) -> String {
        let w = (m.satz ?? "arbeitet").split(separator: " ", maxSplits: 1).map(String.init)
        return "Solange du überlegst, \(w[0]) \(m.name)\(w.count > 1 ? " " + w[1] : "")" + (m.rest_min.map { " · noch etwa \(Int($0)) Min" } ?? "")
    }

    static func seneca(_ s: SenecaStand) -> String? {
        guard let m = s.team?.first(where: { $0.id == Hauptagent.id }) else { return nil }
        if m.zustand == "arbeitet", let satz = m.satz { return satz }
        return m.zuletzt.flatMap { z in z.satz.map { $0 + (z.um.map { " · \(HeuteTafelLogik.uhr($0))" } ?? "") } }
    }

    static func heuteMitSeneca(_ s: SenecaStand) -> [Zeile] {
        var z: [Zeile] = []
        if s.ruhe?.grund == "fokus", let bis = s.ruhe?.bis { z.append(Zeile(text: "Fokus bis \(HeuteTafelLogik.uhr(bis))", hervor: true)) }
        let heute = s.wochenplan?.tage.first { KalenderLogik.gleicherTag($0.tag, s.jetzt) }?.bloecke ?? []
        for b in heute where b.ende > s.jetzt {
            if let da = b.detail?.da { z.append(Zeile(text: "\(HeuteTafelLogik.uhr(da)) bei \(b.detail?.mit ?? b.titel)")) }
            if b.art == "fenster" { z.append(Zeile(text: "\(HeuteTafelLogik.uhr(b.start)) \(b.titel)")) }
        }
        return z
    }

    static func standSatz(_ phasen: [SenecaStand.Phase]) -> String {
        let fertig = phasen.filter { $0.zustand == "fertig" }.map(\.name)
        let jetzt = phasen.first { $0.zustand == "jetzt" }?.name
        let danach = phasen.drop { $0.zustand != "jetzt" }.dropFirst().map(\.name)
        var s = fertig.isEmpty ? "" : fertig.joined(separator: " · ") + " fertig."
        if let jetzt { s += (s.isEmpty ? "" : " ") + "Jetzt \(jetzt)" + (danach.isEmpty ? "." : ", dann \(danach.joined(separator: ", ")).") }
        return s
    }

    static func mitmachen(_ s: SenecaStand, projekt: String) -> [(name: String, was: String, hervor: Bool)] {
        var l: [(String, String, Bool)] = (s.team ?? []).filter { $0.projekt == projekt && $0.id != Hauptagent.id }.map { ($0.name, $0.zustand == "arbeitet" ? "arbeitet" : $0.zustand, false) }
        if ((s.braucht_dich ?? []) + (s.buendel?.fragen ?? [])).contains(where: { $0.projekt == projekt && $0.antwort == nil }) { l.append(("Du", "gibst frei", true)) }
        return l
    }
}
