import Foundation

enum StromDrossel {
    static let textAbstand: TimeInterval = 0.08

    enum Entscheidung: Equatable {
        case sofort
        case halten(in: TimeInterval)
    }

    private struct Kern: Equatable {
        var key: String
        var frage: String
        var phase: ChatLive.Phase
        var taetigkeit: String?
        var start: Date
    }

    private static func kerne(_ stände: [ChatLive]) -> [Kern] {
        stände.map { Kern(key: $0.sessionKey, frage: $0.question, phase: $0.phase, taetigkeit: $0.activity, start: $0.startedAt) }
            .sorted { ($0.key, $0.start) < ($1.key, $1.start) }
    }

    static func nurTextGewachsen(alt: [ChatLive], neu: [ChatLive]) -> Bool {
        guard alt.count == neu.count, kerne(alt) == kerne(neu) else { return false }
        let a = alt.sorted { ($0.sessionKey, $0.startedAt) < ($1.sessionKey, $1.startedAt) }
        let n = neu.sorted { ($0.sessionKey, $0.startedAt) < ($1.sessionKey, $1.startedAt) }
        var gewachsen = false
        for (x, y) in zip(a, n) {
            if x.text == y.text { continue }
            guard y.text.hasPrefix(x.text) else { return false }
            gewachsen = true
        }
        return gewachsen
    }

    static func entscheide(alt: [ChatLive], neu: [ChatLive], zuletzt: Date?, jetzt: Date = Date(),
                           abstand: TimeInterval = textAbstand) -> Entscheidung {
        guard nurTextGewachsen(alt: alt, neu: neu), let zuletzt else { return .sofort }
        let seit = jetzt.timeIntervalSince(zuletzt)
        guard seit < abstand else { return .sofort }
        return .halten(in: abstand - seit)
    }
}
