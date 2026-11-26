import SwiftUI

enum SnZustand { case imPlan, achtung, gefaehrdet, ruht }

enum SnMeilensteinStand { case erledigt, aktuell, offen, verspaetet }

enum SnPhasenStand { case erledigt, jetzt, verspaetet, folgt }

struct SnMeilenstein: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let datum: String
    let stand: SnMeilensteinStand
}

struct SnRisiko: Identifiable, Equatable {
    var id: String { titel }
    let titel: String
    let wirkung: String
    let massnahme: String
}

struct SnKriterium: Identifiable, Equatable {
    var id: String { text }
    let text: String
    let erfuellt: Bool
}

struct SnPhase: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let von: Double
    let bis: Double
    let stand: SnPhasenStand
}

struct SnProjekt: Identifiable, Equatable {
    let id: String
    let name: String
    let kurz: String
    let bereich: String
    let rest: String
    let meta: String
    let agentId: String
    let zustand: SnZustand
    let zustandText: String
    let ziel: String
    let kriterien: [SnKriterium]
    let stand: (von: String, wann: String, text: String)?
    let meilensteine: [SnMeilenstein]
    let risiken: [SnRisiko]
    let phasen: [SnPhase]
    let zeitSatz: String

    static func == (a: SnProjekt, b: SnProjekt) -> Bool { a.id == b.id && a.name == b.name }
}

struct SnZeitachse: Equatable {
    let wochen: [String]
    let heute: Double
    let heuteWoche: Int
}

@MainActor
protocol SnProjekteQuelle {
    var projekte: [SnProjekt] { get }
    var zeitachse: SnZeitachse { get }
}

extension BeispielDaten: SnProjekteQuelle {
    var zeitachse: SnZeitachse {
        SnZeitachse(wochen: ["12.10.", "19.10.", "26.10.", "2.11.", "9.11.", "16.11.", "23.11.", "30.11.", "7.12.", "14.12."], heute: 28, heuteWoche: 4)
    }

    var projekte: [SnProjekt] {
        [
            SnProjekt(
                id: "alpha", name: "Projekt Alpha", kurz: "Alpha", bereich: "Arbeit", rest: "noch 16 Tage",
                meta: "Arbeit · Frist 25. November, noch 16 Tage", agentId: "mara", zustand: .gefaehrdet,
                zustandText: "Gefährdet. Der Lieferant ist noch nicht gewählt, damit wackelt die Lieferung am 18. November.",
                ziel: "Die erste Lieferung ist beim Kunden und abgenommen, bevor das Quartal endet.",
                kriterien: [
                    SnKriterium(text: "Lieferung vollständig bis 18. November", erfuellt: false),
                    SnKriterium(text: "Abnahmeprotokoll vom Kunden unterschrieben", erfuellt: false),
                    SnKriterium(text: "Kosten unter 15.000 €", erfuellt: true),
                ],
                stand: (von: "Mara", wann: "Freitag", text: "Der Projektplan ist geprüft und die Shortlist steht. Offen ist nur die Wahl des Lieferanten, davon hängen Vertrag und Bestellung ab. Nächste Woche: Vertrag, Bestellung, Abnahmeprotokoll."),
                meilensteine: [
                    SnMeilenstein(name: "Plan steht", datum: "12. Okt.", stand: .erledigt),
                    SnMeilenstein(name: "Lieferant gewählt", datum: "heute", stand: .verspaetet),
                    SnMeilenstein(name: "Vertrag unterschrieben", datum: "11. Nov.", stand: .offen),
                    SnMeilenstein(name: "Lieferung", datum: "18. Nov.", stand: .offen),
                    SnMeilenstein(name: "Abnahme", datum: "25. Nov.", stand: .offen),
                ],
                risiken: [
                    SnRisiko(titel: "Lieferung kommt zu spät", wirkung: "hoch", massnahme: "Lieferant B wählen, der zwei Tage Puffer lässt."),
                    SnRisiko(titel: "Kunde am 25. nicht erreichbar", wirkung: "mittel", massnahme: "Termin diese Woche schriftlich bestätigen lassen."),
                ],
                phasen: [
                    SnPhase(name: "Planung", von: 0, bis: 10, stand: .erledigt),
                    SnPhase(name: "Lieferanten finden", von: 10, bis: 28, stand: .verspaetet),
                    SnPhase(name: "Vertrag", von: 28, bis: 30, stand: .folgt),
                    SnPhase(name: "Bestellung und Lieferung", von: 30, bis: 37, stand: .folgt),
                    SnPhase(name: "Abnahme", von: 37, bis: 44, stand: .folgt),
                ],
                zeitSatz: "Die Lieferantensuche ist eine Woche über Plan, der Puffer bis zur Abnahme schrumpft auf zwei Tage."),
            SnProjekt(
                id: "hermes", name: "Hermes Beta", kurz: "Hermes", bereich: "Sundartha", rest: "noch 36 Tage",
                meta: "Sundartha · Frist 15. Dezember, noch 36 Tage", agentId: "tim", zustand: .imPlan,
                zustandText: "Im Plan. Staging läuft stabil, das Onboarding der Testkunden beginnt Mittwoch.",
                ziel: "Zehn Testkunden lassen Hermes für sich telefonieren, ohne dass jemand eingreifen muss.",
                kriterien: [
                    SnKriterium(text: "Zehn Testkunden haben mindestens einen Anruf geführt", erfuellt: false),
                    SnKriterium(text: "Weniger als 5 % abgebrochene Anrufe", erfuellt: false),
                    SnKriterium(text: "Staging zwei Wochen ohne Ausfall", erfuellt: true),
                ],
                stand: (von: "Tim", wann: "heute", text: "Die Website-Entwürfe sind geprüft, die Onboarding-Mail wartet auf deine Freigabe. In den Testanrufen gab es zwei Abbrüche wegen langer Wartemusik, ich prüfe gerade die restlichen Protokolle."),
                meilensteine: [
                    SnMeilenstein(name: "Staging stabil", datum: "2. Nov.", stand: .erledigt),
                    SnMeilenstein(name: "Onboarding", datum: "11. Nov.", stand: .aktuell),
                    SnMeilenstein(name: "Fünf Kunden aktiv", datum: "1. Dez.", stand: .offen),
                    SnMeilenstein(name: "Zehn Kunden aktiv", datum: "15. Dez.", stand: .offen),
                ],
                risiken: [
                    SnRisiko(titel: "Abbrüche bei Wartemusik", wirkung: "mittel", massnahme: "Tim baut eine Erkennung für Warteschleifen."),
                    SnRisiko(titel: "Testkunden springen ab", wirkung: "mittel", massnahme: "Zwei Ersatzkunden auf der Liste halten."),
                ],
                phasen: [
                    SnPhase(name: "Staging", von: 7, bis: 21, stand: .erledigt),
                    SnPhase(name: "Website und Mail", von: 21, bis: 30, stand: .jetzt),
                    SnPhase(name: "Onboarding", von: 30, bis: 37, stand: .folgt),
                    SnPhase(name: "Testphase", von: 37, bis: 64, stand: .folgt),
                ],
                zeitSatz: "Alles im Plan. Die Testphase beginnt in elf Tagen."),
            SnProjekt(
                id: "flur", name: "Flur streichen", kurz: "Flur", bereich: "Zuhause", rest: "bis Ende Nov.",
                meta: "Zuhause · Frist Ende November", agentId: "jonas", zustand: .imPlan,
                zustandText: "Im Plan. Die Farbe ist bestellt, die Bodenleisten fehlen noch.",
                ziel: "Der Flur ist hell gestrichen und hat neue weiße Bodenleisten.",
                kriterien: [
                    SnKriterium(text: "Wände zweimal gestrichen", erfuellt: false),
                    SnKriterium(text: "Leisten montiert", erfuellt: false),
                    SnKriterium(text: "Unter 400 € geblieben", erfuellt: true),
                ],
                stand: (von: "Jonas", wann: "heute", text: "Die Wandfarbe kommt Donnerstag. Für die Leisten liegen zwei von drei Angeboten vor. Gestrichen wird am Samstag, dafür müsstest du den Tag freihalten."),
                meilensteine: [
                    SnMeilenstein(name: "Farbe gewählt", datum: "2. Nov.", stand: .erledigt),
                    SnMeilenstein(name: "Material da", datum: "12. Nov.", stand: .aktuell),
                    SnMeilenstein(name: "Gestrichen", datum: "14. Nov.", stand: .offen),
                    SnMeilenstein(name: "Leisten dran", datum: "21. Nov.", stand: .offen),
                ],
                risiken: [SnRisiko(titel: "Farbe kommt später", wirkung: "niedrig", massnahme: "Samstag notfalls um eine Woche schieben.")],
                phasen: [
                    SnPhase(name: "Farbe wählen", von: 18, bis: 21, stand: .erledigt),
                    SnPhase(name: "Material besorgen", von: 21, bis: 31, stand: .jetzt),
                    SnPhase(name: "Streichen", von: 33, bis: 34, stand: .folgt),
                    SnPhase(name: "Leisten", von: 34, bis: 40, stand: .folgt),
                ],
                zeitSatz: "Im Plan, solange die Farbe am Donnerstag kommt."),
            SnProjekt(
                id: "gewaechshaus", name: "Gewächshaus", kurz: "Gewächshaus", bereich: "Privat", rest: "bis Januar",
                meta: "Privat · Frist 31. Januar", agentId: "seneca", zustand: .ruht,
                zustandText: "Ruht bis Dezember. Seneca vergleicht nebenbei Bausätze.",
                ziel: "Ein wintertaugliches Gewächshaus im Garten, das Licht und Wasser selbst regelt.",
                kriterien: [
                    SnKriterium(text: "Standort und Größe festgelegt", erfuellt: false),
                    SnKriterium(text: "Bausatz bestellt", erfuellt: false),
                    SnKriterium(text: "Bewässerung läuft automatisch", erfuellt: false),
                ],
                stand: (von: "Seneca", wann: "heute", text: "Fünf Bausätze gefunden, zwei mit Doppelstegplatten sind wintertauglich. Bis Freitag kommt ein Vergleich mit Preisen und Heizbedarf."),
                meilensteine: [
                    SnMeilenstein(name: "Idee", datum: "Sept.", stand: .erledigt),
                    SnMeilenstein(name: "Planung", datum: "Dez.", stand: .aktuell),
                    SnMeilenstein(name: "Bauen", datum: "Jan.", stand: .offen),
                ],
                risiken: [],
                phasen: [
                    SnPhase(name: "Bausätze vergleichen", von: 25, bis: 32, stand: .jetzt),
                    SnPhase(name: "Planung", von: 32, bis: 56, stand: .folgt),
                ],
                zeitSatz: "Kein Zeitdruck, die Planung beginnt im Dezember."),
        ]
    }
}
