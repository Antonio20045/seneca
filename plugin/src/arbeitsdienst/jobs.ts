import { statfsSync } from "node:fs";
import { aktiveLaeufe, auftraege, faelligeAuftraege, faelligeWirkungen, hole, naechsteFaelligkeit, offeneFrage, uhr, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { sichern } from "../register/sichern.ts";
import { auftragAnlegen, auftragSetzen, befund, frageStellen, frageWirkt, laufEnde, uebergang, wertSetzen } from "../register/schreiben.ts";
import { regelMs, regelText, regelUhrzeitNach, regelZahl } from "../regeln.ts";
import { mandat, mitarbeiter } from "../team.ts";
import { naechsterTermin, starteLauf, zurueckMitWartezeit, type Starter } from "./lauf.ts";

async function starteOderBefund(db: Register, a: Zeile, starte: Starter): Promise<void> {
  try {
    await starteLauf(db, a, starte);
  } catch (fehler) {
    befund(db, { art: "fehler", auftrag_id: String(a.id), satz: `Start nicht möglich: ${(fehler as Error).message}` });
    zurueckMitWartezeit(db, hole(db, "auftrag", String(a.id)), "start_fehler");
  }
}

export async function faelligeAuftraegeJob(db: Register, starte: Starter): Promise<number | undefined> {
  const jetzt = uhr.jetzt();
  for (const a of faelligeAuftraege(db, jetzt)) {
    const id = String(a.id);
    if (a.zustand === "bereit") await starteOderBefund(db, a, starte);
    else if (a.zustand === "wartet") uebergang(db, "auftrag", id, "bereit", "nachfassen", { naechster_anlass: jetzt });
    else auftragSetzen(db, id, { naechster_anlass: regelUhrzeitNach("fenster", jetzt) }, "Abnahme rutscht ins nächste Fenster.");
  }
  return naechsteFaelligkeit(db);
}

function wirkung(db: Register, f: Zeile, a: Zeile, jetzt: number): void {
  const id = String(a.id);
  const antwort = String(f.antwort);
  if (antwort === "spaeter") return;
  if (f.art === "stufe_festlegen") wertSetzen(db, `kontakt:${f.ausgang_schluessel}`, antwort, "antonio");
  if (f.art === "vorschlag" && a.zustand === "vorgeschlagen") {
    uebergang(db, "auftrag", id, antwort === "ja" ? "bereit" : "verworfen", "vorschlag", antwort === "ja" ? { naechster_anlass: jetzt } : {});
    return;
  }
  if (f.von === "arbeitsdienst:kostenrahmen" && antwort === "weiter") auftragSetzen(db, id, { kostenrahmen_cent: Number(a.kostenrahmen_cent) * 2 }, "Rahmen erhöht.");
  const anhalten = antwort === "anhalten" && ["arbeitsdienst:kostenrahmen", "arbeitsdienst:haengt"].includes(String(f.von));
  if (f.von === "arbeitsdienst:haengt") {
    const lauf = aktiveLaeufe(db).find((l) => l.auftrag_id === id);
    if (lauf) laufEnde(db, String(lauf.id), "abgebrochen", { grund: anhalten ? "angehalten" : "angestupst, startet neu" });
    if (!anhalten && a.zustand === "laeuft") zurueckMitWartezeit(db, a, "wiederaufnahme");
  }
  const jetztA = hole(db, "auftrag", id);
  if (anhalten && ["bereit", "laeuft", "wartet"].includes(String(jetztA.zustand))) return uebergang(db, "auftrag", id, "geparkt", "anhalten");
  if (jetztA.zustand === "wartet") {
    uebergang(db, "auftrag", id, "bereit", ["freigabe", "ausfuehrliches_ja"].includes(String(f.art)) ? "freigabe" : "antwort", { naechster_anlass: jetzt });
  }
}

export function faelligeWirkungenJob(db: Register): number | undefined {
  const jetzt = uhr.jetzt();
  for (const f of faelligeWirkungen(db, jetzt)) {
    if (frageWirkt(db, String(f.id))) wirkung(db, f, hole(db, "auftrag", String(f.auftrag_id)), jetzt);
  }
  return naechsteFaelligkeit(db);
}

export function laeufePruefenJob(db: Register): void {
  const jetzt = uhr.jetzt();
  for (const l of aktiveLaeufe(db)) {
    const still = jetzt - Number(l.letzter_schritt_um);
    const auftragId = String(l.auftrag_id);
    if (l.zustand === "laeuft" && still > regelMs("haengt_leise_min")) uebergang(db, "lauf", String(l.id), "haengt", "kein Schritt");
    if (still > regelMs("haengt_frage_min") && !offeneFrage(db, auftragId)) {
      frageStellen(db, {
        auftrag_id: auftragId, von: "arbeitsdienst:haengt", art: "auswahl", text: `${l.mitarbeiter} hängt seit ${new Date(Number(l.letzter_schritt_um)).toTimeString().slice(0, 5)}. Was tun?`,
        was_passiert_ist: `Letzter Schritt: ${l.letzter_schritt ?? "keiner"}.`, wenn_nichts: "Der Lauf hängt weiter.", empfehlung: "Anstupsen",
        optionen: [{ wert: "anstupsen", text: "Anstupsen", folge: "Der Lauf startet neu am letzten Stand." }, { wert: "anhalten", text: "Anhalten", folge: "Der Auftrag wird geparkt." }],
      });
    }
  }
}

export function nachNeustart(db: Register): void {
  for (const l of aktiveLaeufe(db)) {
    laufEnde(db, String(l.id), "abgebrochen", { grund: "Neustart des Gateways" });
    befund(db, { art: "fehler", auftrag_id: String(l.auftrag_id), lauf_id: String(l.id), satz: "Der Lauf endete durch einen Neustart des Gateways." });
    zurueckMitWartezeit(db, hole(db, "auftrag", String(l.auftrag_id)), "wiederaufnahme");
  }
}

const DAUERAUFTRAEGE: Record<string, string> = {
  morgenbericht: "Morgenbericht: je Auftrag des Vortags Stand, Beleg und was fehlt.",
  rueckblick: "Rückblick am Abend: Erledigtes, Wiederholungen, Bestwerte, was gefehlt hat.",
  briefing: "Briefing: Tagesplan mit Energie und Terminen.",
};

function dauerauftrag(db: Register, wer: string, arbeitsart: string, wortlaut: string): void {
  const da = auftraege(db, ["vorgeschlagen", "geparkt", "bereit", "laeuft", "wartet", "wartet_auf_abnahme"])
    .some((a) => a.quelle === "dauerauftrag" && a.verantwortlich === wer && a.arbeitsart === arbeitsart);
  if (da) return;
  auftragAnlegen(db, {
    art: "dauerauftrag", wortlaut, wortlaut_quelle: "mandat", titel: wortlaut.split(":")[0], ziel: wortlaut, abnahme: "Fortschreibung mit Beleg", abnahme_durch: "beleg",
    pruefer_noetig: false, verantwortlich: wer, auftraggeber: wer, quelle: "dauerauftrag", bereich: mandat(wer).bereich[0], arbeitsart,
    naechster_anlass: naechsterTermin({ arbeitsart, verantwortlich: wer }, uhr.jetzt()),
  });
}

export function pflegenJob(db: Register, sicherungsOrdner: string): void {
  sichern(db, sicherungsOrdner);
  const frei = statfsSync(sicherungsOrdner);
  if (frei.bavail * frei.bsize < regelZahl("platte_frei_min_mb") * 1e6) befund(db, { art: "risiko", satz: "Die Platte des Servers ist fast voll." });
  for (const wer of mitarbeiter()) {
    if (mandat(wer).rundgang.length) dauerauftrag(db, wer, "rundgang", "Rundgang: Signale des Mandats lesen, eigene Aufträge mit Nutzen anlegen, Anzeigen aufräumen.");
  }
  for (const [art, wortlaut] of Object.entries(DAUERAUFTRAEGE)) dauerauftrag(db, regelText("dauerauftraege_von"), art, wortlaut);
}
