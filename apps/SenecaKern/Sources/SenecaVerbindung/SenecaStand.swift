import Foundation

public struct SenecaStand: Codable, Equatable, Sendable {
    public struct Zaehler: Codable, Equatable, Sendable { public var braucht: Int }
    public struct Ruhe: Codable, Equatable, Sendable { public var grund: String; public var bis: Double?; public var durchbruch: Bool }
    public struct Option: Codable, Equatable, Sendable { public var wert: String?; public var text: String?; public var folge: String? }
    public struct Kontext: Codable, Equatable, Sendable { public var worum: String?; public var wenn_nicht: String? }
    public struct Zustellung: Codable, Equatable, Sendable { public var geraet: String?; public var zeit: Double?; public var was: String?; public var bis: Double?; public var grund: String? }
    public struct Antwort: Codable, Equatable, Sendable { public var wahl: String; public var geraet: String?; public var zeit: Double? }
    public struct Frage: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var text: String
        public var von: String?
        public var seit: Double?
        public var art: String?
        public var wirkung_aussen: String?
        public var optionen: [Option]?
        public var empfehlung: String?
        public var kontext: Kontext?
        public var frist: Double?
        public var wirkt_ab: Double?
        public var zustellung: [Zustellung]?
        public var antwort: Antwort?
    }
    public struct Abnahme: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String }
    public struct Buendel: Codable, Equatable, Sendable { public var fenster: Double?; public var abnahmen: [Abnahme]?; public var fragen: [Frage]? }
    public struct Mitglied: Codable, Equatable, Sendable { public var name: String; public var zustand: String; public var satz: String?; public var seit: Double? }
    public struct Erledigt: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String }
    public struct Termin: Codable, Equatable, Sendable, Identifiable {
        public var uid: String
        public var start: Double
        public var ende: Double
        public var titel: String
        public var ort: String?
        public var teilnehmer: [String]?
        public var ganztag: Bool?
        public var art: String?
        public var id: String { uid }
    }
    public struct Todo: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var titel: String
        public var bereich: String?
        public var tag: String?
        public var bis_wann: Double?
        public var dauer_min: Double?
        public var geplant_von: Double?
        public var wiederkehrend: String?
        public var wichtig: Bool?
        public var revision: Int?
    }
    public struct Kopplung: Codable, Equatable, Sendable { public var geraet: String; public var zahl: String }

    public var schema: Int
    public var revision: Int
    public var jetzt: Double
    public var erzeugt: Double?
    public var unveraendert: Bool?
    public var tag_beginn: Double?
    public var regeln: [String: Double]?
    public var zaehler: Zaehler?
    public var ruhe: Ruhe?
    public var braucht_dich: [Frage]?
    public var buendel: Buendel?
    public var team: [Mitglied]?
    public var heute_erledigt: [Erledigt]?
    public var termine: [Termin]?
    public var todos: [Todo]?
    public var hinweise: [String]?
    public var kopplung: [Kopplung]?
}

@MainActor
public final class StandSpeicher {
    public static let schemaErwartet = 1

    public private(set) var stand: SenecaStand?
    public private(set) var passtNicht = false
    public var aufNeu: ((SenecaStand) -> Void)?
    public var aufPasstNicht: (() -> Void)?

    private let datei: URL?
    private var laeuft = false
    private var nochmal = false

    public init(datei: URL?) {
        self.datei = datei
        if let datei, let roh = try? Data(contentsOf: datei), let s = try? JSONDecoder().decode(SenecaStand.self, from: roh), s.schema == Self.schemaErwartet { stand = s }
    }

    public var revision: Int { stand?.revision ?? 0 }

    @discardableResult
    public func uebernehme(_ roh: Data) -> Bool {
        guard let neu = try? JSONDecoder().decode(SenecaStand.self, from: roh) else { return false }
        guard neu.schema == Self.schemaErwartet else {
            if !passtNicht { passtNicht = true; aufPasstNicht?() }
            return false
        }
        passtNicht = false
        guard neu.unveraendert != true, neu.revision > revision else { return false }
        stand = neu
        if let datei { try? roh.write(to: datei, options: .atomic) }
        aufNeu?(neu)
        return true
    }

    public func ereignis(revision: Int, holen: @escaping () async -> Data?) {
        guard revision > self.revision else { return }
        abrufen(holen)
    }

    public func abrufen(_ holen: @escaping () async -> Data?) {
        guard !laeuft else { nochmal = true; return }
        laeuft = true
        Task {
            repeat {
                nochmal = false
                if let roh = await holen() { uebernehme(roh) }
            } while nochmal
            laeuft = false
        }
    }
}
