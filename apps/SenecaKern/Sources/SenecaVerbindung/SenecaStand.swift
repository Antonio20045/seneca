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
        public var projekt: String?
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
        public var kurz: String?; public var zeit: String?; public var mitteilung: Mitteilung?
    }
    public struct Mitteilung: Codable, Equatable, Sendable { public var titel: String; public var text: String }
    public struct Abnahme: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String; public var projekt: String? }
    public struct Buendel: Codable, Equatable, Sendable {
        public var fenster: Double?; public var abnahmen: [Abnahme]?; public var fragen: [Frage]?
        public var dauer_min: Double?; public var satz: String?; public var kurz: String?
    }
    public struct Zuletzt: Codable, Equatable, Sendable { public var satz: String?; public var um: Double? }
    public struct Mitglied: Codable, Equatable, Sendable {
        public var name: String; public var zustand: String; public var satz: String?; public var seit: Double?
        public var projekt: String?; public var rest_min: Double?; public var zuletzt: Zuletzt?
        public var auftrag_id: String?; public var schritte: [Zuletzt]?; public var ruht_seit: Double?; public var titel: String?
    }
    public struct AuftragNeu: Codable, Equatable, Sendable, Identifiable {
        public var id: String; public var titel: String; public var ziel: String?; public var wer: String; public var pruefer: Bool?
        public var erteilt: Double; public var bis: Double?; public var dauer_min: Double?; public var danach: String?
    }
    public struct Heute: Codable, Equatable, Sendable { public var satz: [String]?; public var satz_folge: [String]? }
    public struct Schlaf: Codable, Equatable, Sendable { public var minuten: Double; public var bis: Double }
    public struct Koerper: Codable, Equatable, Sendable {
        public var body_battery: Double?; public var zeit: Double?; public var stress: Double?; public var schritte: Double?
        public var morgens: Double?; public var titel: String?; public var hinweis: String?; public var schlaf: Schlaf?
    }
    public struct Erledigt: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String }
    public struct Notiz: Codable, Equatable, Sendable { public var satz: String; public var um: Double? }
    public struct Termin: Codable, Equatable, Sendable, Identifiable {
        public var uid: String
        public var start: Double
        public var ende: Double
        public var titel: String
        public var ort: String?
        public var teilnehmer: [String]?
        public var ganztag: Bool?
        public var art: String?
        public var ankunft: Double?; public var weg_min: Double?
        public var kalender: String?; public var kalender_quelle: String?; public var mit: [String]?; public var entfernung_m: Double?
        public var notiz: Notiz?; public var bescheid: String?
        public var id: String { uid }
    }
    public struct Kalender: Codable, Equatable, Sendable {
        public struct Eintrag: Codable, Equatable, Sendable {
            public var uid: String?; public var von: Double?; public var bis: Double?; public var titel: String?; public var unter: String?
            public var art: String; public var jetzt: Bool?; public var text: String?
        }
        public struct Block: Codable, Equatable, Sendable { public var von: Double; public var bis: Double; public var art: String }
        public struct Tag: Codable, Equatable, Sendable { public var datum: Double; public var kurz: String; public var nr: Int; public var bloecke: [Block]; public var text: String; public var warnung: Bool }
        public struct Woche: Codable, Equatable, Sendable { public var kopf: String; public var satz: [String]; public var tage: [Tag] }
        public var satz: [String]?; public var eintraege: [Eintrag]?; public var hinweis: String?; public var woche: Woche?
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
        public var geschaetzt: String?; public var geplant_bis: Double?; public var oeffnet: String?; public var notiz: String?
        public var anhang: String?; public var verschoben: Int?
    }
    public struct Aufgaben: Codable, Equatable, Sendable {
        public struct Gruppe: Codable, Equatable, Sendable { public var titel: String; public var zeit: String; public var ids: [String] }
        public struct Fertig: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String; public var bereich: String?; public var von: String?; public var um: Double?; public var satz: String? }
        public struct Taeglich: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String; public var erledigt: Bool }
        public struct Zaehler: Codable, Equatable, Sendable { public var morgen: Int; public var woche: Int; public var ohne_tag: Int }
        public var satz: [String]?; public var gruppe: Gruppe?; public var heute: [String]?; public var erledigt: [Fertig]?
        public var jeden_tag: [Taeglich]?; public var zaehler: Zaehler?
    }
    public struct Kopplung: Codable, Equatable, Sendable { public var geraet: String; public var zahl: String }
    public struct Berichte: Codable, Equatable, Sendable {
        public struct Neu: Codable, Equatable, Sendable, Identifiable { public var id: String; public var kopf: String; public var um: Double; public var text: String; public var beleg: String?; public var wer: String; public var wer_name: String }
        public struct Gleich: Codable, Equatable, Sendable, Identifiable { public var id: String; public var text: String; public var seit_tage: Int }
        public struct Seneca: Codable, Equatable, Sendable { public var kopf: String; public var um: Double; public var text: String; public var gestern: String? }
        public var satz: [String]; public var neu: [Neu]; public var unveraendert: [Gleich]; public var seneca: Seneca?
    }
    public struct Rueckblick: Codable, Equatable, Sendable {
        public struct Frage: Codable, Equatable, Sendable { public var id: String; public var optionen: [Option] }
        public struct Zahl: Codable, Equatable, Sendable { public var wert: String; public var name: String }
        public var um: Double; public var saetze: [String]; public var frage: Frage?; public var zahlen: [Zahl]
    }

    public var schema: Int
    public var revision: Int
    public var jetzt: Double
    public var erzeugt: Double?
    public var unveraendert: Bool?
    public var tag_beginn: Double?
    public var regeln: [String: Double]?
    public var zaehler: Zaehler?
    public var ruhe: Ruhe?
    public var heute: Heute?
    public var koerper: Koerper?
    public var braucht_dich: [Frage]?
    public var buendel: Buendel?
    public var team: [Mitglied]?
    public var heute_erledigt: [Erledigt]?
    public var auftraege_neu: [AuftragNeu]?
    public var termine: [Termin]?
    public var todos: [Todo]?
    public var aufgaben: Aufgaben?
    public var kalender: Kalender?
    public var berichte: Berichte?; public var rueckblick: Rueckblick?
    public var hinweise: [String]?
    public var kopplung: [Kopplung]?
    public var wartet: String?
}

public struct Verstanden: Codable, Equatable, Sendable {
    public var erkannt: Bool; public var titel: String; public var tag: String?; public var von: Double?; public var bis: Double?
    public var dauer_min: Int?; public var geschaetzt: [String]?; public var bereich: String?; public var wiederkehrend: String?; public var hinweis: String
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

public struct SenecaStatistik: Codable, Equatable, Sendable {
    public struct Tag: Codable, Equatable, Sendable { public var t: String; public var zustand: String; public var heute: Bool }
    public struct Karte: Codable, Equatable, Sendable, Identifiable {
        public var art: String; public var titel: String; public var buch: String?; public var unter: String?; public var wert: String; public var einheit: String
        public var tage: [Tag]; public var anteil: Double?; public var rechts: String; public var knopf: String
        public var id: String { art }
    }
    public struct Woche: Codable, Equatable, Sendable { public var kopf: String; public var satz: [String]; public var karten: [Karte]; public var hinweis: String? }
    public struct Km: Codable, Equatable, Sendable { public var nr: Int; public var zeit: String; public var anteil: Double; public var schnellste: Bool }
    public struct Lauf: Codable, Equatable, Sendable { public var id: String; public var kopf: String; public var satz: [String]; public var werte: [[String]]; public var km: [Km]; public var bestwert: String?; public var woche: String? }
    public struct Raster: Codable, Equatable, Sendable { public var kopf: String; public var satz: [String]; public var raster: [[String]]; public var zahlen: [[String]]; public var bestwerte: [[String]]? }
    public struct TagSicht: Codable, Equatable, Sendable { public var kopf: String; public var satz: [String]; public var zeilen: [[String]] }
    public struct Punkt: Codable, Equatable, Sendable { public var w: String; public var kg: Double?; public var wdh: Int?; public var monat: String }
    public struct Zeile: Codable, Equatable, Sendable {
        public var links: String; public var wert: String; public var unter: String; public var bestwert: Bool
        public init(from d: Decoder) throws {
            var c = try d.unkeyedContainer()
            links = try c.decode(String.self); wert = try c.decode(String.self); unter = try c.decode(String.self); bestwert = (try? c.decode(Bool.self)) ?? false
        }
        public func encode(to e: Encoder) throws { var c = e.unkeyedContainer(); try c.encode(links); try c.encode(wert); try c.encode(unter); try c.encode(bestwert) }
    }
    public struct Uebung: Codable, Equatable, Sendable { public var titel: String; public var satz: String; public var wochen: [Punkt]; public var zeilen: [Zeile]; public var hinweis: String? }
    public struct Notiz: Codable, Equatable, Sendable { public var kopf: String; public var text: String }
    public struct Buch: Codable, Equatable, Sendable {
        public var titel: String; public var kopf: String; public var anteil: Double?; public var seite: String?; public var prozent: String?; public var satz: String; public var prognose: String?
        public var zahlen: [[String]]; public var zuletzt: [Zeile]; public var notiz: Notiz?
    }
    public var woche: Woche; public var lauf: Lauf?; public var tag: TagSicht?; public var monat: Raster?; public var jahr: Raster?; public var uebung: Uebung?; public var buch: Buch?
}
