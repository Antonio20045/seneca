import type { SQLInputValue, SQLOutputValue } from "node:sqlite";
import type { Register } from "./schema.ts";
import { regelMs, regelUhrzeitNach } from "../regeln.ts";

export type Zeile = Record<string, SQLOutputValue>;
export type Tabelle = "auftrag" | "lauf" | "frage" | "todo" | "eintrag" | "anzeige";

export const uhr = { jetzt: (): number => Date.now() };

const AKTIV = "('startet','laeuft','haengt')";

function alle(db: Register, sql: string, ...p: SQLInputValue[]): Zeile[] {
  return db.prepare(sql).all(...p);
}

export function hole(db: Register, tabelle: Tabelle, id: string): Zeile {
  const z = db.prepare(`SELECT * FROM ${tabelle} WHERE id = ?`).get(id);
  if (!z) throw new Error(`${tabelle} ${id} fehlt`);
  return z;
}

export function revision(db: Register): number {
  return Number(db.prepare("SELECT COALESCE(MAX(nr), 0) AS r FROM ereignis").get()?.r);
}

export function offeneFrage(db: Register, auftragId: string): Zeile | undefined {
  return alle(db, "SELECT * FROM frage WHERE auftrag_id = ? AND zustand = 'offen'", auftragId)[0];
}

export function fragen(db: Register, zustand: string): Zeile[] {
  return alle(db, "SELECT * FROM frage WHERE zustand = ? ORDER BY gestellt", zustand);
}

export function kinder(db: Register, elternId: string): Zeile[] {
  return alle(db, "SELECT * FROM auftrag WHERE eltern_id = ?", elternId);
}

export function auftraege(db: Register, zustaende: string[]): Zeile[] {
  return alle(db, `SELECT * FROM auftrag WHERE zustand IN (${zustaende.map(() => "?").join(",")}) ORDER BY erstellt`, ...zustaende);
}

export function faelligeAuftraege(db: Register, jetzt: number): Zeile[] {
  return alle(db, "SELECT * FROM auftrag WHERE zustand IN ('bereit','wartet','wartet_auf_abnahme') AND naechster_anlass <= ? ORDER BY naechster_anlass", jetzt);
}

export function aktiveLaeufe(db: Register): Zeile[] {
  return alle(db, `SELECT * FROM lauf WHERE zustand IN ${AKTIV} ORDER BY gestartet`);
}

export function beendeteLaeufe(db: Register, mitarbeiter: string, seit: number): Zeile[] {
  return alle(db, `SELECT lauf.*, auftrag.titel FROM lauf JOIN auftrag ON auftrag.id = lauf.auftrag_id WHERE mitarbeiter = ? AND lauf.zustand NOT IN ${AKTIV} AND beendet_um >= ? ORDER BY beendet_um DESC`, mitarbeiter, seit);
}

export function laeufeSeit(db: Register, mitarbeiter: string, seit: number): Zeile[] {
  return alle(db, "SELECT * FROM lauf WHERE mitarbeiter = ? AND gestartet >= ? ORDER BY gestartet", mitarbeiter, seit);
}

export function anzeigen(db: Register, besitzer: string): Zeile[] {
  return alle(db, "SELECT * FROM anzeige WHERE besitzer = ? AND zustand != 'entfernt'", besitzer);
}

export function laeufe(db: Register, auftragId: string): Zeile[] {
  return alle(db, "SELECT * FROM lauf WHERE auftrag_id = ? ORDER BY gestartet", auftragId);
}

export function laufZurSitzung(db: Register, sitzung: string): Zeile | undefined {
  return alle(db, "SELECT * FROM lauf WHERE sitzung = ? ORDER BY gestartet DESC", sitzung)[0];
}

export function wert(db: Register, schluessel: string): { wert: string; gueltig_bis?: number } | undefined {
  const z = db.prepare("SELECT daten FROM ereignis WHERE art = 'wert.gesetzt' AND schluessel = ? ORDER BY nr DESC LIMIT 1").get(schluessel);
  return z ? JSON.parse(String(z.daten)) : undefined;
}

export function werte(db: Register, praefix: string): Map<string, string> {
  const zeilen = alle(db, "SELECT schluessel, daten FROM ereignis WHERE art = 'wert.gesetzt' AND schluessel LIKE ? ORDER BY nr", `${praefix}%`);
  return new Map(zeilen.map((z) => [String(z.schluessel), JSON.parse(String(z.daten)).wert]));
}

export function ereignisse(db: Register, f: { art?: string; auftrag_id?: string; frage_id?: string; schluessel?: string; lauf_id?: string; seit?: number; nach?: number; grenze?: number }): Zeile[] {
  const bed = (["art", "auftrag_id", "frage_id", "schluessel", "lauf_id"] as const).filter((k) => f[k] !== undefined);
  const p: SQLInputValue[] = bed.map((k) => f[k] ?? null);
  return alle(db, `SELECT * FROM ereignis WHERE ${[...bed.map((k) => `${k} = ?`), "zeit >= ?", "nr > ?"].join(" AND ")} ORDER BY nr DESC LIMIT ?`, ...p, f.seit ?? 0, f.nach ?? 0, f.grenze ?? -1);
}

export function wiederholungenSeit(db: Register, seit: number): number {
  return ereignisse(db, { art: "korrektur", seit }).filter((e) => JSON.parse(String(e.daten)).wiederholung && !zurueckgenommen(db, Number(e.nr))).length;
}

export function zurueckgenommen(db: Register, nr: number): boolean {
  return !!db.prepare("SELECT 1 FROM ereignis WHERE art = 'korrektur.zurueckgenommen' AND json_extract(daten, '$.korrektur_nr') = ?").get(nr);
}

export function vorschlagDaten(db: Register, auftragId: string): { herkunft?: string; wirkung?: Record<string, unknown> } {
  return JSON.parse(String(ereignisse(db, { art: "auftrag.angelegt", auftrag_id: auftragId, grenze: 1 })[0]?.daten ?? "{}"));
}

export function vorschlaege(db: Register, herkunft: string): Zeile[] {
  return alle(db, `SELECT a.erstellt, a.zustand, a.titel FROM auftrag a JOIN ereignis e ON e.auftrag_id = a.id AND e.art = 'auftrag.angelegt'
    WHERE a.quelle = 'vorschlag' AND json_extract(e.daten, '$.herkunft') = ? ORDER BY a.erstellt`, herkunft);
}

export function kostenSeit(db: Register, seit: number, f: { mitarbeiter?: string; quelle?: string; auftrag_id?: string }): number {
  const z = db.prepare(`SELECT COALESCE(SUM(l.kosten_cent), 0) AS k FROM lauf l JOIN auftrag a ON a.id = l.auftrag_id
    WHERE l.gestartet >= ? AND (? IS NULL OR l.mitarbeiter = ?) AND (? IS NULL OR a.quelle = ?) AND (? IS NULL OR l.auftrag_id = ?)`)
    .get(seit, f.mitarbeiter ?? null, f.mitarbeiter ?? null, f.quelle ?? null, f.quelle ?? null, f.auftrag_id ?? null, f.auftrag_id ?? null);
  return Number(z?.k);
}

export function tokensJeAbo(db: Register, seit: number): Map<string, number> {
  const zeilen = alle(db, "SELECT abo, SUM(tokens_ein + tokens_aus) AS t FROM lauf WHERE gestartet >= ? AND abo IS NOT NULL GROUP BY abo", seit);
  return new Map(zeilen.map((z) => [String(z.abo), Number(z.t)]));
}

export function todos(db: Register, zustand: string): Zeile[] {
  return alle(db, "SELECT * FROM todo WHERE zustand = ? ORDER BY wichtig DESC, bis_wann", zustand);
}

export function naechsteFaelligkeit(db: Register): number | undefined {
  const z = db.prepare(`SELECT MIN(t) AS t FROM (SELECT MIN(naechster_anlass) AS t FROM auftrag WHERE zustand IN ('bereit','wartet','wartet_auf_abnahme')
    UNION ALL SELECT MIN(wirkt_ab) FROM frage WHERE zustand = 'beantwortet' AND id NOT IN (SELECT frage_id FROM ereignis WHERE art = 'frage.wirkt'))`).get();
  return z?.t === null || z?.t === undefined ? undefined : Number(z.t);
}

export function faelligeWirkungen(db: Register, jetzt: number): Zeile[] {
  return alle(db, "SELECT * FROM frage WHERE zustand = 'beantwortet' AND wirkt_ab <= ? AND id NOT IN (SELECT frage_id FROM ereignis WHERE art = 'frage.wirkt' AND frage_id IS NOT NULL)", jetzt);
}

export function kalenderTag(t: number): string {
  const d = new Date(t);
  return `kalender:${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function spaeterBis(db: Register, frageId: string, jetzt: number): number {
  const fenster = regelUhrzeitNach("fenster", jetzt);
  const frist = hole(db, "frage", frageId).frist;
  return frist !== null && Number(frist) - regelMs("spaeter_vor_frist_min") < fenster ? Number(frist) - regelMs("spaeter_vor_frist_min") : fenster;
}

export function termineAm(db: Register, t: number): { uid: string; start: number; ende: number; titel: string; ort?: string; teilnehmer: string[]; ganztag: boolean; kalender?: string }[] {
  return JSON.parse(wert(db, kalenderTag(t))?.wert ?? "[]");
}

export function letztesTraining(db: Register, seit: number): number | undefined {
  const z = db.prepare("SELECT MAX(zeit) AS zeit FROM eintrag WHERE art IN ('satz', 'training') AND zeit >= ?").get(seit);
  return z?.zeit === null || z?.zeit === undefined ? undefined : Number(z.zeit);
}
