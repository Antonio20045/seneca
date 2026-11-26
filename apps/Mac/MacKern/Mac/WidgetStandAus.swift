import Foundation

extension WidgetStand {
    @MainActor static func aus(_ s: OverviewStore, fuerDich: [FuerDichZeile]?, laeuft: [LaeuftZeile]?, jetzt: Date = Date()) -> WidgetStand? {
        guard let fuerDich, let laeuft else { return nil }
        var w = aus(s, jetzt: jetzt)
        w.braucht = fuerDich.count
        w.laeuft = laeuft.count
        w.satz = FuerDich.lageSatz(fuerDich.count)
        w.fragen = fuerDich.map { FuerDich.titel($0) }.filter { !$0.isEmpty }.prefix(WidgetSpeicher.fragenMax).map { Menschlich.kuerzen($0, 90) }
        return w
    }

    @MainActor static func aus(_ s: OverviewStore, jetzt: Date = Date()) -> WidgetStand {
        let m = MenueStand.aus(s)
        let fragen = s.entscheidungenSicht.filter { !$0.ruhend }.prefix(WidgetSpeicher.fragenMax)
            .map { Menschlich.kuerzen(Menschlich.klartext($0.frage), 90) }
        let termin = m.termin.map { t in
            WidgetStand.Termin(titel: t.titel, start: Date(timeIntervalSince1970: t.start / 1000), ende: Date(timeIntervalSince1970: t.ende / 1000),
                               ort: s.daten.kalender?.termine.first { $0.titel == t.titel && $0.start == t.start }?.ort.flatMap { $0.isEmpty ? nil : $0 })
        }
        return WidgetStand(satz: HeuteLogik.lageSatz(m.braucht), braucht: m.braucht, laeuft: m.laeuft, ungelesen: m.ungelesen,
                           fragen: Array(fragen), termin: termin, geschrieben: jetzt)
    }
}
