import { anzeigen, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { anzeigeEntfernen, anzeigeSetzen } from "../register/schreiben.ts";
import { regelZahl } from "../regeln.ts";
import { anzeigeName } from "../team.ts";

const PRUEFE: Record<string, (w: Record<string, unknown>, db: Register) => unknown> = {
  kennzahl: (w) => w.wert != null,
  tabelle: (w) => Array.isArray(w.spalten) && Array.isArray(w.zeilen),
  verweis: (w, db) => statistiken(db).some((s) => s.id === w.statistik),
};
const statistiken = (db: Register): { id: string }[] => JSON.parse(wert(db, "statistik:kennzahlen")?.wert ?? "null")?.statistiken ?? [];
const projektVon = (sitzung: string) => `gespraech:${sitzung}`;

export const imGespraech = (art: unknown) => String(art) in PRUEFE;

export function gespraechAnzeigeSetzen(db: Register, k: { sitzung: string; agent: string }, p: { id?: string; anzeigenart: string; titel: string; werte: Record<string, unknown>; zustand?: string }): string {
  if (p.zustand !== "entfernt" && !PRUEFE[p.anzeigenart](p.werte, db)) throw new Error(`Die Werte passen nicht zur Art ${p.anzeigenart}.`);
  const alt = anzeigen(db, undefined, projektVon(k.sitzung)).filter((z) => z.id !== p.id).sort((a, b) => Number(a.stand) - Number(b.stand));
  if (alt.length >= regelZahl("anzeigen_max_je_projekt")) anzeigeEntfernen(db, String(alt[0].id), k.agent);
  return anzeigeSetzen(db, { id: p.id, projekt: projektVon(k.sitzung), art: p.anzeigenart, titel: p.titel, werte: p.werte, besitzer: k.agent, zustand: p.zustand });
}

export const gespraechAnzeigen = (db: Register, sitzung: string) => ({
  anzeigen: anzeigen(db, undefined, projektVon(sitzung)).map((z) => {
    const w = JSON.parse(String(z.werte)), verlauf: number[] = w.verlauf ?? [];
    const eigene = z.art === "verweis" ? statistiken(db).find((s) => s.id === w.statistik) : z.art === "kennzahl"
      ? { id: z.id, titel: z.titel, von: z.besitzer, grund: w.grund, diagramm: verlauf.length > 1 ? w.diagramm ?? "balken" : "zahl", einheit: w.einheit, ziel: w.ziel, punkte: verlauf.map((v, i) => [String(i), v]), wert: Number(w.wert) } : undefined;
    return { id: z.id, art: z.art, titel: z.titel, von: anzeigeName(String(z.besitzer)), grund: w.grund ?? null, eigene, spalten: w.spalten?.map(String), zeilen: w.zeilen?.map((r: unknown[]) => r.map(String)) };
  }),
});
