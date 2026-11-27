import { readFileSync } from "node:fs";

const EINHEIT_MS: Record<string, number> = { s: 1000, min: 60000, h: 3600000, tage: 86400000 };

function datei(): string {
  return process.env.SENECA_REGELN ?? new URL("../../regeln", import.meta.url).pathname;
}

export function regelText(name: string): string {
  const zeile = readFileSync(datei(), "utf8").split("\n").find((z) => z.split(/\s+/)[0] === name);
  if (!zeile) throw new Error(`regeln: ${name} fehlt`);
  return zeile.trim().split(/\s+/)[1];
}

export function appRegeln(): Record<string, number> {
  return Object.fromEntries(readFileSync(datei(), "utf8").split("\n").map((z) => z.trim().split(/\s+/)).filter((t) => t.includes("app")).map((t) => [t[0], Number(t[1])]));
}

export function regelZahl(name: string): number {
  const wert = Number(regelText(name));
  if (Number.isNaN(wert)) throw new Error(`regeln: ${name} ist keine Zahl`);
  return wert;
}

export function regelMs(name: string): number {
  const faktor = EINHEIT_MS[name.slice(name.lastIndexOf("_") + 1)];
  if (!faktor) throw new Error(`regeln: ${name} hat keine Zeiteinheit`);
  return regelZahl(name) * faktor;
}

export function regelListe(name: string): string[] {
  return regelText(name).split(",");
}

export function naechsteUhrzeit(text: string, jetzt: number): number {
  const [h, m] = text.split(":").map(Number);
  const d = new Date(jetzt);
  d.setHours(h, m, 0, 0);
  if (d.getTime() <= jetzt) d.setDate(d.getDate() + 1);
  return d.getTime();
}

export function regelUhrzeitNach(name: string, jetzt: number): number {
  return naechsteUhrzeit(regelText(name), jetzt);
}

export function letzteUhrzeit(text: string, jetzt: number): number {
  const d = new Date(naechsteUhrzeit(text, jetzt));
  d.setDate(d.getDate() - 1);
  return d.getTime();
}

export function msAusSekunden(sekunden: number): number {
  return sekunden * EINHEIT_MS.s;
}

export function msAusMinuten(minuten: number): number {
  return minuten * EINHEIT_MS.min;
}

export function sekundenAusMs(ms: number): number {
  return Math.floor(ms / EINHEIT_MS.s);
}

export function kalenderSpanne(jetzt: number): { von: number; wochen: number } {
  const d = new Date(jetzt);
  d.setHours(0, 0, 0, 0);
  const heute = d.getTime(), woche = 7 * EINHEIT_MS.tage, monatsEnde = new Date(heute).setMonth(d.getMonth() + 1, 1);
  d.setMonth(d.getMonth() - regelZahl("kal_monate_zurueck"), 1);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  const von = d.getTime();
  return { von, wochen: Math.max(Math.floor((heute - von + EINHEIT_MS.h) / woche) + 1 + regelZahl("kal_wochen_vor"), Math.ceil((monatsEnde - von) / woche)) };
}
