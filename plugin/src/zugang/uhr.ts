import { createHash } from "node:crypto";
import { revision, uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { wertSetzen } from "../register/schreiben.ts";
import { msAusSekunden, regelMs, regelZahl } from "../regeln.ts";
import { handeln } from "./handeln.ts";

type UhrStand = (jetzt: number) => { q: { id: unknown } | null };
type Anfrage = { v?: number; g?: string; r?: number; zs?: string; h?: { id: string; t: number; a: string; p?: Record<string, unknown>; lokal?: boolean }[] };
export type Antwort = { status: number; inhalt: object; kopf?: Record<string, string> };

const anfragen = new Map<string, number[]>();

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

export function schluesselHash(schluessel: string): string {
  return createHash("sha256").update(schluessel).digest("hex");
}

export function uhrAbgleich(db: Register, roh: Buffer, kopf: Record<string, string | string[] | undefined>, uhrStand: UhrStand): Antwort {
  const d = JSON.parse(roh.toString("utf8")) as Anfrage;
  const geraet = String(d.g);
  const gespeichert = wert(db, `uhr:${geraet}`)?.wert;
  const token = String(kopf.authorization ?? "").replace(/^Bearer /, "");
  if (!gespeichert || gespeichert === "gesperrt" || schluesselHash(token) !== gespeichert) return { status: 401, inhalt: { f: gespeichert === "gesperrt" ? "gesperrt" : "unbekannt" } };
  if (d.v !== regelZahl("uhr_protokoll")) return { status: 426, inhalt: { f: "Uhr-App zu alt" } };
  const jetzt = uhr.jetzt();
  const zeiten = (anfragen.get(geraet) ?? []).filter((t) => t > jetzt - regelMs("uhr_anfragen_fenster_h"));
  if (zeiten.length >= regelZahl("uhr_anfragen_je_std")) return { status: 429, inhalt: { f: "zu viele" }, kopf: { "retry-after": String(regelMs("uhr_anfragen_fenster_h") / msAusSekunden(1)) } };
  anfragen.set(geraet, [...zeiten, jetzt]);
  if ((d.h ?? []).length > regelZahl("uhr_handlungen_max")) return { status: 413, inhalt: { f: "zu viele Handlungen" } };
  const fuerUhr = uhrStand(jetzt).q?.id;
  const q = (d.h ?? []).map((h) => {
    const z = ZUORDNUNG[h.a]?.(h.p ?? {});
    if (!z) return [h.id, "nein:unbekannte_art"];
    if (h.a === "frage.antwort" && z.ziel !== fuerUhr) return [h.id, "nein:nicht_fuer_uhr"];
    return [h.id, kurz(handeln(db, { kennung: h.id, geraet: "uhr", art: h.a, zeit_geraet: msAusSekunden(h.t), ...z }).ergebnis)];
  });
  if (d.zs && wert(db, "aktivitaet")?.wert !== d.zs) wertSetzen(db, "aktivitaet", d.zs, "uhr");
  const r = revision(db);
  return { status: 200, inhalt: d.r === r ? { q, r, u: 1 } : { q, r, s: uhrStand(jetzt) } };
}
