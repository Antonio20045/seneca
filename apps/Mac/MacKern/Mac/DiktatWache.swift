import Foundation

enum DiktatWache {
    enum Phase: Equatable { case ruht, hoert, erkennt, eingefuegt, fehler }

    static func erkennFrist(aufnahmeSekunden: TimeInterval) -> TimeInterval {
        min(180, 20 + max(0, aufnahmeSekunden))
    }

    static let eingefuegtHoechstens: TimeInterval = 5

    static let fehlerHoechstens: TimeInterval = 30

    static let tippenBrichtErkennungNach: TimeInterval = 4

    static let stilleBeendetNach: TimeInterval = 5

    static let hoertSicherheitsgrenze: TimeInterval = 30 * 60

    static let beendetHinweisHoechstens: TimeInterval = 4

    static func zeigeBeendetHinweis(seitAutomatischemEnde: TimeInterval?) -> Bool {
        guard let s = seitAutomatischemEnde else { return false }
        return s >= 0 && s < beendetHinweisHoechstens
    }

    static func blaseSichtbar(phase: Phase, zeigtBeendetHinweis: Bool) -> Bool {
        phase != .ruht || zeigtBeendetHinweis
    }

    static let ichHoereNichtsNach: TimeInterval = 3
    static let ausschlagAb: Float = 0.06

    static func ichHoereNichts(sekundenSeitAusschlag: TimeInterval) -> Bool {
        sekundenSeitAusschlag >= ichHoereNichtsNach
    }

    static func laufzeit(_ sekunden: TimeInterval) -> String {
        let s = max(0, Int(sekunden))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    enum Tippen: Equatable { case nichts, beginne, lasseLos, erkennungAbbrechenUndBeginne }

    static func tippen(phase: Phase, hatAufnahme: Bool, startet: Bool, seit: TimeInterval) -> Tippen {
        if hatAufnahme { return .lasseLos }
        if startet { return .nichts }
        if phase == .erkennt { return seit >= tippenBrichtErkennungNach ? .erkennungAbbrechenUndBeginne : .nichts }
        return .beginne
    }

    enum Urteil: Equatable {
        case ok
        case zuruecksetzen
        case aufnahmeBeenden
        case erkennungHaengt
    }

    static func urteil(phase: Phase, hatAufnahme: Bool, motorLaeuft: Bool, startet: Bool,
                       seit: TimeInterval, erkennFrist: TimeInterval,
                       seitLetztemPuffer: TimeInterval? = nil) -> Urteil {
        switch phase {
        case .ruht:
            return .ok
        case .fehler:
            return seit > fehlerHoechstens ? .zuruecksetzen : .ok
        case .hoert:
            if startet { return .ok }
            if !hatAufnahme { return .zuruecksetzen }
            if !motorLaeuft { return .aufnahmeBeenden }
            if let stille = seitLetztemPuffer, stille > stilleBeendetNach { return .aufnahmeBeenden }
            return seit > hoertSicherheitsgrenze ? .aufnahmeBeenden : .ok
        case .erkennt:
            return seit > erkennFrist ? .erkennungHaengt : .ok
        case .eingefuegt:
            return seit > eingefuegtHoechstens ? .zuruecksetzen : .ok
        }
    }
}
