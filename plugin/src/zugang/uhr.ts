import { createHash, randomBytes, randomInt } from "node:crypto";
import { revision, uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { wertSetzen } from "../register/schreiben.ts";
import { letzteUhrzeit, msAusSekunden, regelMs, regelText, regelZahl } from "../regeln.ts";
import { handeln } from "./handeln.ts";

type UhrStand = (jetzt: number) => { q: { id: unknown } | null };
type Koerper = { bb?: [number, number]; st?: number; sc?: number };
type Anfrage = { v?: number; g?: string; r?: number; zs?: string; k?: Koerper; h?: { id: string; t: number; a: string; p?: Record<string, unknown>; lokal?: boolean }[] };
export type Antwort = { status: number; inhalt: object; kopf?: Record<string, string> };

const anfragen = new Map<string, number[]>();
const LAUF = "trail";

const ZUORDNUNG: Record<string, (p: Record<string, unknown>) => { ziel?: string; wert?: unknown }> = {
  "eintrag.neu": (p) => ({ wert: { art: p.k, werte: p } }),
  "todo.anlegen": (p) => ({ wert: { titel: p.x, herkunft: "uhr" } }),
  "todo.erledigt": (p) => ({ ziel: String(p.z) }),
  "frage.antwort": (p) => ({ ziel: String(p.f), wert: { wahl: p.w, lokal: true } }),
};

function kurz(e: string): string {
  if (e === "angenommen") return "ok";
  if (e === "doppelt") return "schon";
  if (e === "ueberholt") return "ub";
  return e.startsWith("schon_beantwortet:") ? `sb:${e.slice("schon_beantwortet:".length)}` : `nein:${e.replace("abgelehnt:", "")}`;
}

function beantwortet(db: Register, frageId: string): boolean {
  return db.prepare("SELECT 1 FROM frage WHERE id = ? AND zustand = 'beantwortet'").get(frageId) !== undefined;
}

export function schluesselHash(schluessel: string): string {
  return createHash("sha256").update(schluessel).digest("hex");
}

type Kopplung = { zahl: string; abholen: string; bestaetigt: boolean; abgeholt?: boolean };

function begrenzt(schluessel: string, grenze: number): boolean {
  const jetzt = uhr.jetzt();
  const zeiten = (anfragen.get(schluessel) ?? []).filter((t) => t > jetzt - regelMs("uhr_anfragen_fenster_h"));
  anfragen.set(schluessel, [...zeiten, jetzt]);
  return zeiten.length >= grenze;
}

export function uhrKoppeln(db: Register, roh: Buffer): Antwort {
  const d = JSON.parse(roh.toString("utf8")) as Anfrage & { m?: string };
  const g = String(d.g ?? "");
  const fenster = wert(db, "kopplung:fenster");
  if (begrenzt("koppeln", regelZahl("kopplung_anfragen_je_std"))) return { status: 429, inhalt: { f: "zu viele" } };
  if (!g || fenster?.wert !== "ja" || (fenster.gueltig_bis ?? 0) <= uhr.jetzt()) return { status: 403, inhalt: { f: "Kein Kopplungsfenster offen" } };
  const zahl = String(randomInt(0, 10000)).padStart(4, "0");
  const abholen = randomBytes(16).toString("hex");
  wertSetzen(db, `kopplung:${g}`, JSON.stringify({ zahl, abholen: schluesselHash(abholen), bestaetigt: false, modell: d.m?.slice(0, regelZahl("kopplung_modell_zeichen")) }), "uhr", fenster.gueltig_bis);
  return { status: 200, inhalt: { zahl, abholen } };
}

export function uhrAbholen(db: Register, roh: Buffer): Antwort {
  const d = JSON.parse(roh.toString("utf8")) as { g?: string; abholen?: string };
  const w = wert(db, `kopplung:${d.g}`);
  const k = w && (w.gueltig_bis ?? 0) > uhr.jetzt() ? (JSON.parse(w.wert) as Kopplung) : undefined;
  if (begrenzt("abholen", regelZahl("kopplung_anfragen_je_std")) || !k?.bestaetigt || k.abgeholt || k.abholen !== schluesselHash(String(d.abholen))) {
    return { status: 403, inhalt: { f: "nicht bestätigt" } };
  }
  const schluessel = randomBytes(32).toString("base64url");
  wertSetzen(db, `uhr:${d.g}`, schluesselHash(schluessel), "uhr");
  wertSetzen(db, `kopplung:${d.g}`, JSON.stringify({ ...k, abgeholt: true }), "uhr", uhr.jetzt());
  return { status: 200, inhalt: { schluessel } };
}

export function uhrAbgleich(db: Register, roh: Buffer, kopf: Record<string, string | string[] | undefined>, uhrStand: UhrStand): Antwort {
  const d = JSON.parse(roh.toString("utf8")) as Anfrage;
  const geraet = String(d.g);
  const gespeichert = wert(db, `uhr:${geraet}`)?.wert;
  const token = String(kopf.authorization ?? "").replace(/^Bearer /, "");
  if (!gespeichert || gespeichert === "gesperrt" || schluesselHash(token) !== gespeichert) return { status: 401, inhalt: { f: gespeichert === "gesperrt" ? "gesperrt" : "unbekannt" } };
  if (d.v !== regelZahl("uhr_protokoll")) return { status: 426, inhalt: { f: "Uhr-App zu alt" } };
  const jetzt = uhr.jetzt();
  if (begrenzt(geraet, regelZahl("uhr_anfragen_je_std"))) return { status: 429, inhalt: { f: "zu viele" }, kopf: { "retry-after": String(regelMs("uhr_anfragen_fenster_h") / msAusSekunden(1)) } };
  if ((d.h ?? []).length > regelZahl("uhr_handlungen_max")) return { status: 413, inhalt: { f: "zu viele Handlungen" } };
  const fuerUhr = uhrStand(jetzt).q?.id;
  const q = (d.h ?? []).map((h) => {
    const z = ZUORDNUNG[h.a]?.(h.p ?? {});
    if (!z) return [h.id, "nein:unbekannte_art"];
    if (h.a === "frage.antwort" && z.ziel !== fuerUhr && !beantwortet(db, String(z.ziel))) return [h.id, "nein:nicht_fuer_uhr"];
    return [h.id, kurz(handeln(db, { kennung: h.id, geraet: "uhr", art: h.a, zeit_geraet: msAusSekunden(h.t), ...z }).ergebnis)];
  });
  const nach = (d.h ?? []).filter((h, i) => h.a === "eintrag.neu" && h.p?.k === "satz" && q[i][1] === "ok" && jetzt - msAusSekunden(h.t) > regelMs("uhr_nachgereicht_min")).length;
  if (nach >= regelZahl("uhr_nachgereicht_ab")) wertSetzen(db, "hinweis:uhr", `${nach} Sätze aus dem Training übernommen`, "uhr", jetzt + regelMs("uhr_hinweis_min"));
  const amArm = wert(db, "uhr_am_arm");
  if ((amArm?.gueltig_bis ?? 0) <= jetzt) wertSetzen(db, "uhr_am_arm", "ja", "uhr", jetzt + regelMs("uhr_verbunden_min"));
  aktivitaetSetzen(db, d.zs, jetzt);
  koerperSetzen(db, d.k);
  const r = revision(db);
  return { status: 200, inhalt: d.r === r || d.zs === LAUF ? { q, r, u: 1 } : { q, r, s: uhrStand(jetzt) } };
}

function aktivitaetSetzen(db: Register, zs: string | undefined, jetzt: number): void {
  const a = wert(db, "aktivitaet");
  const laeuft = a?.wert === LAUF && (a.gueltig_bis ?? 0) > jetzt;
  if (!zs || (laeuft && zs === "leer") || (a?.wert === zs && zs !== LAUF)) return;
  wertSetzen(db, "aktivitaet", zs, "uhr", zs === LAUF ? jetzt + regelMs("uhr_lauf_ruhe_min") : undefined);
}

function koerperSetzen(db: Register, k: Koerper | undefined): void {
  if (!k?.bb) return;
  const neu = JSON.stringify({ body_battery: k.bb[0], zeit: msAusSekunden(k.bb[1]), stress: k.st ?? null, schritte: k.sc ?? null });
  if (wert(db, "koerper")?.wert === neu) return;
  const morgens = JSON.parse(wert(db, "koerper:morgens")?.wert ?? "{\"zeit\":0}");
  if (morgens.zeit < letzteUhrzeit(regelText("tag_grenze"), msAusSekunden(k.bb[1]))) wertSetzen(db, "koerper:morgens", JSON.stringify({ body_battery: k.bb[0], zeit: msAusSekunden(k.bb[1]) }), "uhr");
  wertSetzen(db, "koerper", neu, "uhr");
}
