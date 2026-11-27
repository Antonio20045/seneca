import Foundation

public struct SenecaStand: Codable, Equatable, Sendable {
    public struct Zaehler: Codable, Equatable, Sendable { public var braucht: Int }
    public struct Ruhe: Codable, Equatable, Sendable { public var grund: String; public var bis: Double?; public var durchbruch: Bool }
    public struct Option: Codable, Equatable, Sendable {
        public var wert: String?; public var text: String?; public var folge: String?
        public var titel: String?; public var preis: String?; public var einheit: String?; public var knopf: String?; public var quittung: String?
    }
    public struct Kontext: Codable, Equatable, Sendable { public var worum: String?; public var wenn_nicht: String? }
    public struct Zustellung: Codable, Equatable, Sendable { public var geraet: String?; public var zeit: Double?; public var was: String?; public var bis: Double?; public var grund: String? }
    public struct Antwort: Codable, Equatable, Sendable { public var wahl: String; public var geraet: String?; public var zeit: Double? }
    public struct Punkt: Codable, Equatable, Sendable { public var text: String; public var fertig: Bool }
    public struct Bericht: Codable, Equatable, Sendable { public var satz: String; public var text: String; public var beleg: String? }
    public struct Frage: Codable, Equatable, Sendable, Identifiable {
        public var checkliste: [Punkt]?; public var bericht: Bericht?
        public var id: String
        public var text: String
        public var von: String?
        public var projekt: String?
        public var seit: Double?
        public var art: String?
        public var wirkung_aussen: String?
        public var optionen: [Option]?
        public var folge: String?
        public var empfehlung: String?
        public var kontext: Kontext?
        public var frist: Double?
        public var wirkt_ab: Double?
        public var zustellung: [Zustellung]?
        public var antwort: Antwort?
        public var kurz: String?; public var zeit: String?; public var mitteilung: Mitteilung?; public var spaeter_bis: Double?; public var zurueckgehalten: String?
        public var grund: String?; public var lage: String?; public var rueckfragen: [String]?; public var haengt: [Haengt]?; public var davor: [Zuletzt]?; public var zusatz: String?
        public struct Haengt: Codable, Equatable, Sendable { public var um: Double; public var text: String }
    }
    public struct Vorbei: Codable, Equatable, Sendable, Identifiable { public var id: String; public var text: String; public var zustand: String; public var frist: Double?; public var satz: String? }
    public struct Mitteilung: Codable, Equatable, Sendable { public var titel: String; public var text: String }
    public struct Abnahme: Codable, Equatable, Sendable, Identifiable {
        public var id: String; public var titel: String; public var projekt: String?
        public var art: String?; public var satz: String?; public var hoerprobe_s: Double?; public var an: String?; public var beleg: String?
        public var art_name: String?; public var pruefer: String?; public var geprueft: Double?; public var kursiv: String?; public var transkript: String?
        public var geaendert: String?; public var vorher: String?; public var vorher_s: Double?; public var unterschied: [String]?; public var dateien: Int?
        public var folge: String?; public var ergebnis: String?
    }
    public struct BuendelZeile: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String; public var zustand: String; public var unter: String? }
    public struct Fortschritt: Codable, Equatable, Sendable {
        public var titel: String?; public var fertig: Int; public var gesamt: Int; public var rest_min: Double?
        public var passt: [String]?; public var zurueck: [String]?; public var danach: String?
        public var liste: [BuendelZeile]?; public var anzahl: String?; public var zaehlung: String?; public var start: [String]?; public var arten: String?
        public var pause: [String]?; public var pause_satz: String?; public var abschluss: [String]?; public var rueckgaengig: String?
    }
    public struct Buendel: Codable, Equatable, Sendable {
        public var fenster: Double?; public var abnahmen: [Abnahme]?; public var fragen: [Frage]?
        public var dauer_min: Double?; public var satz: String?; public var kurz: String?; public var fortschritt: Fortschritt?
    }
    public struct Phase: Codable, Equatable, Sendable { public var name: String; public var zustand: String }
    public struct ProjektZeile: Codable, Equatable, Sendable { public var art: String; public var id: String; public var text: String; public var wer: String?; public var rechts: String? }
    public struct Projekt: Codable, Equatable, Sendable, Identifiable {
        public var name: String; public var bereich: String?; public var untertitel: String?; public var worum: String?; public var satz: String?; public var phasen: [Phase]?
        public var zustand: String; public var frist: Double?; public var rechts: [String]?; public var zeilen: [ProjektZeile]?
        public var id: String { name }
    }
    public struct Projekte: Codable, Equatable, Sendable { public var kopf: String?; public var satz: [String]?; public var liste: [Projekt]?; public var ruhen: String? }
    public struct Entschieden: Codable, Equatable, Sendable { public var zeit: Double?; public var titel: String; public var unter: String? }
    public struct Entscheiden: Codable, Equatable, Sendable {
        public var satz: [String]?; public var fenster: Double?; public var fenster_bis: Double?
        public var heute: [Entschieden]?; public var danach: String?; public var danach_kurz: String?
    }
    public struct Zuletzt: Codable, Equatable, Sendable { public var satz: String?; public var um: Double?; public var frage_id: String?; public var art: String? }
    public struct Mitglied: Codable, Equatable, Sendable {
        public var id: String?; public var name: String; public var zustand: String; public var satz: String?; public var seit: Double?
        public var projekt: String?; public var rest_min: Double?; public var zuletzt: Zuletzt?
        public var auftrag_id: String?; public var schritte: [Zuletzt]?; public var ruht_seit: Double?; public var titel: String?
        public var arbeit: Arbeit?; public var teil: Teil?; public var ruecklauf: Zuletzt?
        public struct Teil: Codable, Equatable, Sendable { public var satz: String; public var um: Double; public var beleg: String? }
    }
    public struct Werkzeug: Codable, Equatable, Sendable { public var um: Double; public var werkzeug: String?; public var satz: String?; public var ms: Double? }
    public struct Arbeit: Codable, Equatable, Sendable {
        public var kopf: [String?]?; public var von: String?; public var erteilt: Double?; public var anteil: Double?; public var minuten: String?; public var schritt: String?
        public var naechstes: [String?]?; public var wartet: [String]?; public var heute: [Zuletzt]?; public var protokoll: [Werkzeug]?; public var zahlen: [String]?; public var dateien: [String]?
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
    public struct Erledigt: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String; public var wer: String?; public var pruefer: Bool?; public var min: Double?; public var kosten_cent: Double? }
    public struct Notiz: Codable, Equatable, Sendable { public var satz: String; public var um: Double }
    public struct Termin: Codable, Equatable, Sendable, Identifiable {
        public var uid: String
        public var start: Double
        public var ende: Double
        public var titel: String
        public var ort: String?
        public var teilnehmer: [String]?
        public var ganztag: Bool?
        public var art: String?
        public var weg: String?
        public var ankunft: Double?; public var weg_min: Double?
        public var kalender: String?; public var kalender_quelle: String?; public var bereich: String?; public var mit: [String]?; public var entfernung_m: Double?
        public var notiz: Notiz?; public var bescheid: String?; public var meeting: Meeting?
        public var id: String { uid }
    }
    public struct Meeting: Codable, Equatable, Sendable {
        public struct Du: Codable, Equatable, Sendable, Identifiable { public var id: String; public var text: String }
        public struct Angebot: Codable, Equatable, Sendable, Identifiable {
            public var id: String; public var text: String; public var wer: String; public var arbeitsart: String; public var bereich: String; public var quelle: String; public var genommen: Bool
        }
        public var grund: String; public var phase: String; public var du: [Du]; public var seneca: [Angebot]
    }
    public struct TerminDetail: Codable, Equatable, Sendable {
        public var datum: String; public var ort: String?; public var mit: String?; public var kalender: String?; public var notiz: String?
        public var da: Double?; public var da_satz: String?; public var weg: String?; public var km: String?; public var los: String?; public var seneca: Notiz?
    }
    public struct KalBlock: Codable, Equatable, Sendable, Identifiable {
        public var id: String; public var titel: String; public var unter: String?; public var start: Double; public var ende: Double; public var art: String; public var bereich: String?
        public var laeuft: Bool?; public var frage_id: String?; public var uid: String?; public var teile: [String]?; public var detail: TerminDetail?; public var andere: [Double]?
    }
    public struct KalMarke: Codable, Equatable, Sendable { public var titel: String; public var zeit: Double }
    public struct KalTag: Codable, Equatable, Sendable { public var tag: Double; public var bb: Double?; public var ganztag: [String]; public var bloecke: [KalBlock]; public var marken: [KalMarke] }
    public struct KalWoche: Codable, Equatable, Sendable { public var von: Double; public var titel: String; public var unter: String }
    public struct KalPlant: Codable, Equatable, Sendable {
        public var id: String; public var titel: String; public var text: String; public var knopf: String?; public var uid: String; public var start: Double?; public var ende: Double?
    }
    public struct Wochenplan: Codable, Equatable, Sendable {
        public var wochen: [KalWoche]; public var tage: [KalTag]; public var plant: KalPlant?; public var kalender: [String]; public var standard: String; public var tag_von: Double; public var tag_bis: Double
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
        public var anhang: String?; public var verschoben: Int?; public var grund: Grund?
        public struct Grund: Codable, Equatable, Sendable { public var vorher: Double; public var satz: String }
    }
    public struct Aufgaben: Codable, Equatable, Sendable {
        public struct Gruppe: Codable, Equatable, Sendable { public var titel: String; public var zeit: String; public var ids: [String] }
        public struct Fertig: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String; public var bereich: String?; public var von: String?; public var um: Double?; public var satz: String? }
        public struct Taeglich: Codable, Equatable, Sendable, Identifiable { public var id: String; public var titel: String; public var erledigt: Bool; public var ab: String?; public var dauer_min: Double? }
        public struct Zaehler: Codable, Equatable, Sendable { public var morgen: Int; public var woche: Int; public var ohne_tag: Int }
        public var satz: [String]?; public var gruppe: Gruppe?; public var heute: [String]?; public var erledigt: [Fertig]?
        public var jeden_tag: [Taeglich]?; public var zaehler: Zaehler?
    }
    public struct Kopplung: Codable, Equatable, Sendable { public var geraet: String; public var zahl: String; public var modell: String?; public var bestaetigt: Bool? }
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

    public var vorbei: [Vorbei]?
    public var team_kopf: [String]?
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
    public var eben_beantwortet: [Frage]?
    public struct TodoVorschlag: Codable, Equatable, Sendable { public var titel: String; public var bereich: String?; public var um: Double }
    public var todo_vorschlag: TodoVorschlag?
    public var buendel: Buendel?
    public var entscheiden: Entscheiden?
    public var projekte: Projekte?
    public var team: [Mitglied]?
    public var heute_erledigt: [Erledigt]?
    public var auftraege_neu: [AuftragNeu]?
    public var termine: [Termin]?
    public var wochenplan: Wochenplan?
    public var verlauf: Verlauf?
    public struct Verlauf: Codable, Equatable, Sendable { public var quittungen: [Quittung]?; public var zeilen: [Vermerk]? }
    public struct Vermerk: Codable, Equatable, Sendable, Identifiable { public var zeit: Double; public var satz: String; public var unter: String; public var id: String { "\(zeit)" + satz } }
    public struct Zuruecklegen: Codable, Equatable, Sendable { public var uid: String; public var start: Double; public var ende: Double; public var ab: Double; public var bis: Double }
    public struct Quittung: Codable, Equatable, Sendable {
        public var sitzung: String; public var von: Double; public var bis: Double; public var teile: [String]; public var ergebnis: [String]; public var raus: String?; public var zuruecklegen: Zuruecklegen?
    }
    public var todos: [Todo]?
    public var aufgaben: Aufgaben?
    public var kalender: Kalender?
    public var berichte: Berichte?; public var rueckblick: Rueckblick?
    public var hinweise: [String]?
    public var kopplung: [Kopplung]?
    public var uhr_gekoppelt: Bool?
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
    public struct Tag: Codable, Equatable, Sendable { public var t: String; public var zustand: String; public var heute: Bool; public var wert: Double?; public var hoehe: Double? }
    public struct Karte: Codable, Equatable, Sendable, Identifiable {
        public var art: String; public var titel: String; public var bereich: String?; public var buch: String?; public var unter: String?; public var wert: String; public var einheit: String
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
    public struct Kennzahlen: Codable, Equatable, Sendable {
        public struct Lauf: Codable, Equatable, Sendable {
            public var km: [Double]; public var lang: [Double]; public var tage: [Int]; public var trendKm: Double?; public var serie: [String: Int]?
            public var laengster: [JSONWert]?; public var schnellsterKm: [JSONWert]?; public var aufbau: [[JSONWert]]
            enum CodingKeys: String, CodingKey { case km, lang, tage, serie, laengster, aufbau, trendKm = "trend_km", schnellsterKm = "schnellster_km" }
        }
        public struct Kraft: Codable, Equatable, Sendable {
            public var tage: [Int]; public var volumen: [String: Double]; public var bestwerte: [String: [JSONWert]]
            enum CodingKeys: String, CodingKey { case tage, bestwerte, volumen = "volumen_4w" }
        }
        public struct Koerper: Codable, Equatable, Sendable { public var nacht: [[JSONWert]]; public var tag: [[JSONWert]]; public var gewicht: [[JSONWert]] }
        public struct Eigene: Codable, Equatable, Sendable, Identifiable {
            public var id: String; public var titel: String; public var von: String?; public var grund: String?; public var diagramm: String?; public var einheit: String?
            public var ziel: Double?; public var punkte: [[JSONWert]]?; public var wert: Double?; public var fehler: String?; public var grau: Bool?
        }
        public var wochen: [String]; public var lauf: Lauf; public var kraft: Kraft; public var koerper: Koerper; public var statistiken: [Eigene]
    }
    public var woche: Woche; public var lauf: Lauf?; public var tag: TagSicht?; public var monat: Raster?; public var jahr: Raster?; public var uebung: Uebung?; public var buch: Buch?
    public var kennzahlen: Kennzahlen?
}
