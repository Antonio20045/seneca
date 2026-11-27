import Foundation
import Combine
import WidgetKit

@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var sink: AnyCancellable?
    private var letzte: WidgetLage?

    func attach(_ store: SenecaStore) {
        guard sink == nil else { return }
        sink = store.$stand.compactMap { $0 }
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] s in
                self?.schreiben(WidgetBridge.lage(s))
                TeilenEingang.teamMerken((s.team ?? []).map { [$0.name, "\(ChatTafelLogik.punkt($0, s))"] })
            }
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
                          fragen: (s.braucht_dich ?? []).map { .init(kurz: $0.kurz ?? $0.text, von: $0.von ?? "Seneca", seit: d($0.seit), frist: d($0.frist)) },
                          wartend: s.buendel?.fragen?.count ?? 0,
                          team: m.map { "\($0.name)" + ($0.rest_min.map { " · noch \(Int($0)) Min" } ?? "") },
                          bodyBattery: s.koerper?.body_battery.map { Int($0) })
    }

    private func schreiben(_ l: WidgetLage) {
        WidgetStore.write(l)
        let anders = letzte.map { var a = $0; a.stand = l.stand; return a != l } ?? true
        letzte = l
        if anders { WidgetCenter.shared.reloadAllTimelines() }
    }
}
