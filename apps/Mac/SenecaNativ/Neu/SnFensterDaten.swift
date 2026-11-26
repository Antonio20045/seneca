import SwiftUI

struct SnOption: Equatable {
    let name: String
    let fakten: String
    let vorteil: String
    let nachteil: String
    let knopf: String
    var schluessel = ""
    var beschreibung = ""
}

struct SnEntscheidung: Equatable {
    let frist: String
    let frage: String
    let kontext: String
    let hintergrund: String
    let optionen: [SnOption]
    let empfehlung: Int
    let empfehlungText: String
    let danach: String
}

struct SnFormular: Equatable {
    let projekt: String
    var aktualisiert: String
    var warum: String?
    var auftrag: String?
    var stand: String?
    var ergebnis: String?
    var braucht: String?
    var weiter: String?
    var frist: String?
    var erwartet: String?
    var ergebnisDatei: String?
    var ohnePrioritaet = false
}

struct SnBriefing: Equatable {
    let agentId: String
    let meta: String
    let titel: String
    let ziel: String
    let wissen: [String]
    let fragen: [String]
    let unterlagen: [String]
}

@MainActor
protocol SnFensterQuelle {
    func entscheidung(aufgabe id: String) -> SnEntscheidung?
    func formular(aufgabe id: String) -> SnFormular?
    func briefing(termin: SnTermin) -> SnBriefing?
    func entscheide(aufgabe id: String, option: Int)
}

extension SnFensterQuelle {
    func entscheide(aufgabe id: String, option: Int) {}
}

struct BeispielFenster: SnFensterQuelle {
    func entscheidung(aufgabe id: String) -> SnEntscheidung? { Self.entscheidungen[id] }
    func formular(aufgabe id: String) -> SnFormular? { Self.formulare[id] }
    func briefing(termin: SnTermin) -> SnBriefing? { termin.hatBriefing ? Self.briefing : nil }

    static let entscheidungen: [String: SnEntscheidung] = [
        "lief": SnEntscheidung(
            frist: "Entscheidung bis heute 17:00",
            frage: "Lieferant A oder B für Projekt Alpha?",
            kontext: "Für die erste Lieferung an den Kunden brauchen wir einen Lieferanten für die Bauteile. Solange er nicht feststeht, kann Mara den Liefervertrag nicht aufsetzen, und die Lieferung am 18. November ist nicht zu halten.",
            hintergrund: "Drei Lieferanten wurden angefragt. C liefert nicht vor Dezember und ist raus. A und B haben Angebote geschickt, B zusätzlich eine Probelieferung, die pünktlich und vollständig war.",
            optionen: [
                SnOption(name: "Lieferant A", fakten: "12.400 € · liefert 2. Dezember", vorteil: "1.000 € günstiger", nachteil: "Kommt zwei Wochen nach der Frist, die Abnahme am 25. November platzt.", knopf: "Lieferant A nehmen"),
                SnOption(name: "Lieferant B", fakten: "13.400 € · liefert 16. November", vorteil: "Hält die Frist mit zwei Tagen Puffer, Probelieferung war einwandfrei.", nachteil: "1.000 € teurer, bleibt aber unter dem Budget.", knopf: "Lieferant B nehmen"),
            ],
            empfehlung: 1,
            empfehlungText: "Mara empfiehlt B. Die Mehrkosten sind kleiner als der Schaden, wenn die Abnahme verschoben werden muss.",
            danach: "Mara bestellt noch heute und legt dir den Vertrag morgen zur Unterschrift vor."),
        "mail": SnEntscheidung(
            frist: "Freigabe bis heute 16:00",
            frage: "Onboarding-Mail an die zehn Testkunden freigeben?",
            kontext: "Ab Mittwoch probieren die Testkunden Hermes aus. Die Mail ist ihr Startpunkt: Sie erklärt, wie man Hermes die erste Nummer anrufen lässt, und enthält den Link zur Testnummer.",
            hintergrund: "Tim hat die Mail nach den Fragen aus den ersten Testanrufen geschrieben. Sie hat drei Absätze und folgt eurer Vorlage. Jonas hat die Liste der Testkunden gestern bestätigt.",
            optionen: [
                SnOption(name: "Heute verschicken", fakten: "an 10 Testkunden, 16:00", vorteil: "Zwei Tage Vorlauf vor dem Start.", nachteil: "Du hast die Mail selbst noch nicht gelesen.", knopf: "Freigeben"),
                SnOption(name: "Erst selbst lesen", fakten: "Versand morgen", vorteil: "Du kannst Ton und Inhalt noch anpassen.", nachteil: "Die Kunden haben nur einen Tag Vorlauf.", knopf: "Mail zuerst lesen"),
            ],
            empfehlung: 0,
            empfehlungText: "Tim empfiehlt, heute zu verschicken, weil zwei Tage Vorlauf die Absagen senken.",
            danach: "Tim verschickt um 16 Uhr und meldet dir morgen, wer geantwortet hat."),
        "sauger": SnEntscheidung(
            frist: "Angebot gilt bis Donnerstag",
            frage: "Neuen Staubsauger kaufen?",
            kontext: "Der alte Staubsauger verliert deutlich an Saugkraft, der Akku hält nur noch acht Minuten. Jonas hat nach Ersatz gesucht.",
            hintergrund: "Verglichen wurden vier Akku-Modelle bis 250 €. Das empfohlene hat in zwei Tests mit „gut“ abgeschnitten und ist leiser als das alte.",
            optionen: [
                SnOption(name: "Kaufen", fakten: "179 € · Lieferung Mittwoch", vorteil: "Hält laut Tests 45 Minuten, beutellos.", nachteil: "179 € Ausgabe diesen Monat.", knopf: "Für 179 € kaufen"),
                SnOption(name: "Nicht jetzt", fakten: "Erinnerung im Dezember", vorteil: "Kein Geld ausgegeben.", nachteil: "Der alte hält vermutlich nicht mehr lange.", knopf: "Im Dezember wieder fragen"),
            ],
            empfehlung: 0,
            empfehlungText: "Jonas empfiehlt zu kaufen, weil der Preis gerade 40 € unter dem üblichen liegt.",
            danach: "Jonas bestellt heute, geliefert wird am Mittwoch."),
    ]

    static let formulare: [String: SnFormular] = [
        "lief": SnFormular(projekt: "Projekt Alpha", aktualisiert: "heute um 10:19", auftrag: "Zwei Angebote vergleichen und einen Lieferanten vorschlagen."),
        "mail": SnFormular(projekt: "Hermes Beta", aktualisiert: "gestern um 18:05", auftrag: "Eine Willkommensmail für die Testkunden schreiben."),
        "sauger": SnFormular(projekt: "Flur streichen", aktualisiert: "am Samstag", auftrag: "Ersatz für den alten Staubsauger finden."),
        "vertrag": SnFormular(projekt: "Projekt Alpha", aktualisiert: "gestern um 17:40", auftrag: "Den Vertrag mit dem gewählten Lieferanten aufsetzen.", stand: "Die Vorlage ist fertig, es fehlt nur der Lieferant.", weiter: "Startet von selbst, sobald der Lieferant feststeht.", frist: "11. November"),
        "protokolle": SnFormular(projekt: "Hermes Beta", aktualisiert: "heute um 11:01", auftrag: "Die 38 Testanrufe der letzten Woche auf Abbrüche prüfen.", stand: "24 von 38 durchgesehen, bisher zwei Abbrüche wegen langer Wartemusik.", weiter: "Zusammenfassung mit Vorschlägen bis heute Abend.", frist: "heute"),
        "abnahme": SnFormular(projekt: "Projekt Alpha", aktualisiert: "heute um 11:02", auftrag: "Ein Protokoll für die Abnahme am 25. November entwerfen.", stand: "Die Gliederung steht, die Prüfpunkte aus dem Projektplan sind übernommen.", weiter: "Der Entwurf kommt heute Nachmittag zu dir.", frist: "20. November"),
        "leisten": SnFormular(projekt: "Flur streichen", aktualisiert: "heute um 09:47", auftrag: "Drei Angebote für 14 Meter weiße Bodenleisten einholen.", stand: "Zwei Angebote da, Neuss liegt mit 4,20 € pro Meter vorn.", weiter: "Das dritte Angebot kommt bis morgen, dann ein Vorschlag an dich.", frist: "11. November"),
        "bausatz": SnFormular(projekt: "Gewächshaus", aktualisiert: "heute um 08:15", auftrag: "Wintertaugliche Bausätze bis 3 m² vergleichen.", stand: "Fünf gefunden, zwei mit Doppelstegplatten passen.", weiter: "Vergleich mit Preisen und Heizbedarf bis Freitag.", frist: "13. November"),
        "plan": SnFormular(projekt: "Projekt Alpha", aktualisiert: "heute um 09:12", auftrag: "Den Projektplan auf Lücken und Fristen prüfen.", ergebnis: "Vollständig. Die Lieferung wurde um zwei Tage vorgezogen, damit Puffer bleibt."),
        "seite": SnFormular(projekt: "Hermes Beta", aktualisiert: "heute um 08:30", auftrag: "Vier Textentwürfe für die Website prüfen.", ergebnis: "Zwei kannst du so freigeben, zwei brauchen noch eine Quelle."),
        "farbe": SnFormular(projekt: "Flur streichen", aktualisiert: "heute um 07:50", auftrag: "Zehn Liter der gewählten Farbe bestellen.", ergebnis: "Bestellt, kommt am Donnerstag."),
        "short": SnFormular(projekt: "Projekt Alpha", aktualisiert: "am Freitag", auftrag: "Drei passende Lieferanten finden.", ergebnis: "A und B kamen in die engere Wahl, C liefert nicht vor Dezember."),
    ]

    static let briefing = SnBriefing(
        agentId: "mara",
        meta: "Heute 14:00 bis 14:30 · Teams · vorbereitet von Mara",
        titel: "Call mit Lieferant B",
        ziel: "Den Liefertermin am 16. November schriftlich bestätigen lassen und klären, was bei Verzug passiert.",
        wissen: ["B liefert für 13.400 €, das sind 1.000 € mehr als A.", "Die Probelieferung am 3. November war pünktlich und vollständig.", "Dein Gegenüber ist Herr Kaya aus dem Vertrieb."],
        fragen: ["Können Sie den 16. November schriftlich zusagen?", "Ist eine Teillieferung möglich, falls etwas fehlt?", "Welche Vertragsstrafe gilt bei Verzug?"],
        unterlagen: ["Angebot Lieferant B", "Protokoll der Probelieferung"])
}
