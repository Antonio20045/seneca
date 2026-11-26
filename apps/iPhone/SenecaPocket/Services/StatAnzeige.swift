import Foundation

enum StatZeitraum: String, CaseIterable, Identifiable {
    case heute, woche, monat, jahr
    var id: String { rawValue }
    var name: String {
        switch self { case .heute: return "Heute"; case .woche: return "Woche"; case .monat: return "Monat"; case .jahr: return "Jahr" }
    }
    var naechster: StatZeitraum? {
        switch self { case .heute: return .woche; case .woche: return .monat; case .monat: return .jahr; case .jahr: return nil }
    }
    var vorheriger: StatZeitraum? {
        switch self { case .heute: return nil; case .woche: return .heute; case .monat: return .woche; case .jahr: return .monat }
    }
}

enum StatSeite: String, Identifiable {
    case laufen, buecher, training, kraft
    var id: String { rawValue }
}

enum StatBlatt: String, Identifiable {
    case lesen
    var id: String { rawValue }
}

struct StatDetail: Equatable {
    var text: String
    var leise = false
}

struct StatWert: Equatable {
    var wert: String
    var name: String
}

struct StatBalken: Equatable {
    var tag: String
    var text: String?
    var anteil: Double
    var da: Bool
    var heute: Bool
}

struct StatTagesbalken: Equatable {
    var balken: [StatBalken]
    var leerKreis: Bool
}

struct StatPunkt: Equatable {
    var tag: String
    var an: Bool
    var heute: Bool
}

struct StatFortschritt: Equatable {
    var anteil: Double
    var links: String
    var rechts: String?
}

struct StatZelle: Equatable {
    var tag: Int?
    var stufe: Int
    var zukunft: Bool
}

struct StatJahresRaster: Equatable {
    var spalten: Int
    var felder: [[Int]]
}

struct StatLinie: Equatable {
    var werte: [Double]
    var xs: [Double] = []
    var links: String
    var rechts: String
    var kleinerIstBesser = false
}

struct StatUebungZeile: Equatable {
    var name: String
    var werte: [Double]
    var text: String
}

struct StatXY: Equatable {
    var x: Double
    var y: Double
}

struct StatGewichtDiagramm: Equatable {
    var punkte: [StatXY]
    var trend: [StatXY]
    var links: String? = nil
    var rechts: String? = nil
    var hoehe: Double = 110
}

struct StatMonatsBalken: Equatable {
    var werte: [Double]
    var namen: [String]
    var hervor: Int?
    var aktuell: Int?
    var beschreibung = "Kilometer pro Monat"
}

struct StatBuchBalken: Equatable {
    var titel: String
    var dauer: String
    var von: Double
    var bis: Double
    var offen: Bool
}

struct StatZeitZeile: Equatable {
    var zeit: String
    var text: String
}

struct StatKmZeile: Equatable {
    var label: String
    var zeit: String
    var laenge: Double
    var rang: Int
    var ton: Double
}

struct StatLaufKarte: Equatable {
    var uhrzeit: String
    var werte: [StatWert]
    var kmZeilen: [StatKmZeile]
    var satz: String?
}

enum StatVisual: Equatable {
    case laufKarte(StatLaufKarte)
    case tagesbalken(StatTagesbalken)
    case trainingPunkte([StatPunkt])
    case fortschritt(StatFortschritt)
    case monatsRaster(beschriftung: String, [StatZelle])
    case jahresRaster(StatJahresRaster)
    case linie(beschriftung: String?, StatLinie)
    case uebungen([StatUebungZeile])
    case gewicht(StatGewichtDiagramm)
    case monatsBalken(StatMonatsBalken)
    case buecher([StatBuchBalken])
    case zeitZeilen([StatZeitZeile])
    case jahresAchse
}

struct StatAbschnitt: Equatable, Identifiable {
    var id: String
    var label: String
    var titel: String?
    var visuals: [StatVisual] = []
    var details: [StatDetail] = []
    var ziel: StatSeite? = nil
    var plus: StatBlatt? = nil
    var aktion: String? = nil
}

struct StatInhalt: Equatable {
    var kopf: String
    var titel: String?
    var abschnitte: [StatAbschnitt]
    var kannZurueck = false
    var kannVor = false
}
