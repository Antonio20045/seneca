import Foundation

struct MenueStand: Equatable {
    var braucht: Int
    var laeuft: Int
    var ungelesen: Int
    var termin: NaechsterTermin?
    var bekannt = true

    struct NaechsterTermin: Equatable {
        var titel: String
        var start: Double
        var ende: Double
        var jetzt: Bool
        var wann: String
    }

    static func naechsterTermin(_ termine: [OvTermin], jetzt: Double) -> NaechsterTermin? {
        guard let t = termine.filter({ !$0.ganztags && $0.ende > jetzt }).min(by: { ($0.start, $0.ende) < ($1.start, $1.ende) }) else { return nil }
        let laeuft = t.start <= jetzt
        let wann: String
        if laeuft { wann = "Jetzt bis \(Menschlich.hhmm(t.ende))" }
        else {
            let tag = Menschlich.tagText(t.start, jetzt: jetzt)
            wann = (tag == "heute" ? "" : tag + " ") + Menschlich.hhmm(t.start)
        }
        return NaechsterTermin(titel: t.titel, start: t.start, ende: t.ende, jetzt: laeuft, wann: wann)
    }

    @MainActor static func aus(_ s: OverviewStore, fuerDich: [FuerDichZeile]?, laeuft: [LaeuftZeile]?) -> MenueStand {
        MenueStand(braucht: fuerDich?.count ?? 0, laeuft: laeuft?.count ?? 0, ungelesen: s.berichte.ungelesen,
                   termin: naechsterTermin(s.daten.kalender?.termine ?? [], jetzt: s.jetzt), bekannt: fuerDich != nil && laeuft != nil)
    }

    @MainActor static func aus(_ s: OverviewStore, fragen: Int?, laeuft: Int?) -> MenueStand {
        MenueStand(braucht: fragen ?? 0, laeuft: laeuft ?? 0, ungelesen: s.berichte.ungelesen,
                   termin: naechsterTermin(s.daten.kalender?.termine ?? [], jetzt: s.jetzt), bekannt: fragen != nil && laeuft != nil)
    }

    @MainActor static func aus(_ s: OverviewStore) -> MenueStand {
        MenueStand(braucht: s.brauchtDich, laeuft: s.laeuftN, ungelesen: s.berichte.ungelesen,
                   termin: naechsterTermin(s.daten.kalender?.termine ?? [], jetzt: s.jetzt))
    }
}

enum DockZahl {
    static func text(_ n: Int) -> String? { n <= 0 ? nil : (n > 99 ? "99+" : String(n)) }
}
