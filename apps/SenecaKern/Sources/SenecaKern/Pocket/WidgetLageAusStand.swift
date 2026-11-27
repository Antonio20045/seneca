import Foundation

extension WidgetLogik {
    static func faelle(_ s: SenecaStand) -> [(String, Date, WidgetLage?)] {
        let tag = Date(timeIntervalSince1970: s.jetzt / 1000)
        let at = { (h: Int, m: Int) in Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: tag)! }
        let basis = lage(s)
        return [
            ("RUHIG · 14:05", at(14, 5), { var l = basis; l.stand = at(14, 4); l.fragen = []; l.wartend = 1; return l }()),
            ("FOKUS · 10:08", at(10, 8), { var l = basis; l.stand = at(10, 8); return l }()),
            ("FRAGE · 11:00", at(11, 0), { var l = basis; l.stand = at(11, 0); l.fokusBis = at(11, 0); return l }()),
            ("Alter Stand · 10:41".uppercased(), at(10, 41), { var l = basis; l.stand = at(10, 2); return l }()),
        ]
    }

    static func lage(_ s: SenecaStand) -> WidgetLage {
        let d = { (ms: Double?) in ms.map { Date(timeIntervalSince1970: $0 / 1000) } }
        let termine = (s.kalender?.eintraege ?? []).compactMap { e -> WidgetLage.Termin? in
            guard let von = d(e.von), let bis = d(e.bis), let t = e.titel else { return nil }
            return WidgetLage.Termin(titel: t, unter: e.unter.map { $0.components(separatedBy: " · ").filter { !$0.hasSuffix(" Min") && !$0.hasSuffix(" Std") }.joined(separator: " · ") }, von: von, bis: bis, art: e.art)
        }
        let fokus = (s.termine ?? []).first { $0.art == "fokus" && $0.ende > s.jetzt && $0.start <= s.jetzt }
        let m = s.team?.first { $0.zustand == "arbeitet" }
        return WidgetLage(stand: Date(timeIntervalSince1970: s.jetzt / 1000), termine: termine, fokusVon: d(fokus?.start), fokusBis: d(fokus?.ende),
                          danach: s.heute?.satz?.dropFirst().first.map { $0.components(separatedBy: ",").first.map { $0.hasSuffix(".") ? $0 : $0 + "." } ?? $0 },
                          fragen: (s.braucht_dich ?? []).map { .init(kurz: $0.kurz ?? $0.text, text: $0.text, von: $0.von ?? "Seneca", seit: d($0.seit), frist: d($0.frist)) },
                          wartend: s.buendel?.fragen?.count ?? 0,
                          team: m.map { "\($0.name)" + ($0.rest_min.map { " · noch \(Int($0)) Min" } ?? "") },
                          bodyBattery: s.koerper?.body_battery.map { Int($0) },
                          satz: s.heute?.satz?.joined(separator: " "),
                          teamZeile: s.team.map { t in "Team: \(t.filter { $0.zustand == "arbeitet" }.count) von \(t.count) arbeitet" },
                          teamSatz: m.map { [$0.name, $0.satz].compactMap { $0 }.joined(separator: " ") + ($0.rest_min.map { " · \(Int($0)) Min" } ?? "") })
    }
}
