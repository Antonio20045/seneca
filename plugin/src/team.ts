import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";

export type Stufe = "lokal" | "haiku" | "sonnet" | "opus" | "fable";
export type Ort = "server" | "mac" | "rechenknoten";

export type Mandat = {
  bereich: string[];
  rundgang: string[];
  befugnisse: { unterauftrag_an: string[]; werkzeuge: string[]; ablage_schreiben: string[]; live_nur_mit_ja: boolean };
  budget: { eigene_auftraege_woche_cent: number };
  modellstufen: { standard: Stufe; arbeitsarten: Record<string, Stufe | { stufe: Stufe; ort: Ort }> };
  kontext: Record<string, string[]>;
  zugaenge: string[];
};

function ordner(): string {
  return process.env.SENECA_TEAM ?? new URL("../../team", import.meta.url).pathname;
}

export function mitarbeiter(): string[] {
  return readdirSync(ordner(), { withFileTypes: true })
    .filter((e) => e.isDirectory() && existsSync(join(ordner(), e.name, "mandat")))
    .map((e) => e.name);
}

export function rolle(name: string): string {
  return readFileSync(join(ordner(), name, "rolle.md"), "utf8");
}

export function mandat(name: string): Mandat {
  const roh = parse(readFileSync(join(ordner(), name, "mandat"), "utf8"));
  const fehlt = ["bereich", "rundgang", "befugnisse", "budget", "modellstufen"].filter((f) => roh?.[f] === undefined);
  if (fehlt.length) throw new Error(`mandat ${name}: ${fehlt.join(", ")} fehlt`);
  return { kontext: {}, zugaenge: [], ...roh };
}
