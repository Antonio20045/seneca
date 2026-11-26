export const NEU = "neu";

export const UEBERGAENGE = {
  auftrag: [
    { nr: "A1", von: [NEU], nach: "bereit", ausloeser: "seneca_auftrag" },
    { nr: "A1r", von: ["bereit"], nach: "verworfen", ausloeser: "rueckgaengig" },
    { nr: "A2", von: [NEU], nach: "vorgeschlagen", ausloeser: "seneca_auftrag vorschlag" },
    { nr: "A3", von: [NEU], nach: "geparkt", ausloeser: "seneca_auftrag idee" },
    { nr: "A3a", von: ["bereit", "laeuft", "wartet"], nach: "geparkt", ausloeser: "auftrag.anhalten" },
    { nr: "A3b", von: ["geparkt"], nach: "bereit", ausloeser: "auftrag.fortsetzen" },
    { nr: "A4", von: ["vorgeschlagen"], nach: "bereit", ausloeser: "Ja auf Vorschlag" },
    { nr: "A5", von: ["vorgeschlagen"], nach: "erledigt", ausloeser: "Ja auf Vorschlag mit To-do" },
    { nr: "A6", von: ["vorgeschlagen"], nach: "verworfen", ausloeser: "Nein auf Vorschlag" },
    { nr: "A8", von: ["bereit"], nach: "laeuft", ausloeser: "starteLauf" },
    { nr: "A9", von: ["wartet"], nach: "bereit", ausloeser: "Anlass" },
    { nr: "A10", von: ["laeuft"], nach: "bereit", ausloeser: "Lauf endet weiter oder abgebrochen" },
    { nr: "A12", von: ["laeuft", "bereit"], nach: "wartet", ausloeser: "Fortschreibung wartet, Rahmen erreicht, Pruefung" },
    { nr: "A14", von: ["laeuft"], nach: "wartet_auf_abnahme", ausloeser: "fertig mit Beleg" },
    { nr: "A15", von: ["laeuft"], nach: "erledigt", ausloeser: "fertig, Abnahme durch Beleg" },
    { nr: "A16", von: ["wartet_auf_abnahme"], nach: "erledigt", ausloeser: "abnahme.passt" },
    { nr: "A17", von: ["wartet_auf_abnahme", "erledigt"], nach: "bereit", ausloeser: "abnahme.nachbessern" },
    { nr: "A19", von: ["vorgeschlagen", "geparkt", "bereit", "laeuft", "wartet", "wartet_auf_abnahme"], nach: "verworfen", ausloeser: "auftrag.verwerfen" },
  ],
  lauf: [
    { nr: "L1", von: [NEU], nach: "startet", ausloeser: "starteLauf" },
    { nr: "L2", von: ["startet"], nach: "laeuft", ausloeser: "OpenClaw nimmt an" },
    { nr: "L3", von: ["startet"], nach: "abgebrochen", ausloeser: "Annahme abgelehnt" },
    { nr: "L4", von: ["laeuft"], nach: "haengt", ausloeser: "Takt: kein Schritt" },
    { nr: "L5", von: ["haengt"], nach: "laeuft", ausloeser: "neuer Schritt" },
    { nr: "L6", von: ["laeuft", "haengt"], nach: "beendet", ausloeser: "agent_end mit Fortschreibung" },
    { nr: "L7", von: ["laeuft", "haengt"], nach: "abgebrochen", ausloeser: "ohne Stand, Fehler, Stopp, Neustart" },
  ],
  frage: [
    { nr: "F1", von: [NEU], nach: "offen", ausloeser: "seneca_frage oder Systemfrage" },
    { nr: "F2", von: ["offen"], nach: "beantwortet", ausloeser: "erste Antwort" },
    { nr: "F3", von: ["beantwortet"], nach: "offen", ausloeser: "rueckgaengig vor wirkt_ab" },
    { nr: "F4", von: ["offen"], nach: "ersetzt", ausloeser: "neue Frage am Auftrag" },
    { nr: "F5", von: ["offen"], nach: "zurueckgezogen", ausloeser: "Auftrag verlaesst wartet oder endet" },
    { nr: "F6", von: ["offen"], nach: "abgelaufen", ausloeser: "Frist vorbei" },
  ],
  todo: [
    { nr: "T1", von: [NEU], nach: "offen", ausloeser: "todo.anlegen" },
    { nr: "T2", von: ["offen"], nach: "erledigt", ausloeser: "todo.erledigt" },
    { nr: "T3", von: ["offen", "erledigt"], nach: "geloescht", ausloeser: "todo.loeschen" },
    { nr: "T4", von: ["geloescht", "erledigt"], nach: "offen", ausloeser: "todo.wiederherstellen" },
  ],
} as const;

export const PFLICHT_BEI = {
  wartet: ["wartet_auf", "folge", "naechster_anlass"],
  wartet_auf_abnahme: ["naechster_anlass"],
  beantwortet: ["antwort", "antwort_geraet", "wirkt_ab"],
  zurueckgezogen: ["grund"],
  abgelaufen: ["grund"],
  ersetzt: ["ersetzt_durch"],
} as const;

export const NEBENWIRKUNGEN = [
  { art: "auftrag", von: "wartet", nach: "*", wirkung: "frage_zurueckziehen" },
  { art: "auftrag", von: "*", nach: "erledigt", wirkung: "frage_zurueckziehen" },
  { art: "auftrag", von: "*", nach: "verworfen", wirkung: "frage_zurueckziehen" },
  { art: "auftrag", von: "*", nach: "erledigt", wirkung: "eltern_wecken" },
  { art: "auftrag", von: "*", nach: "verworfen", wirkung: "kinder_verwerfen" },
] as const;
