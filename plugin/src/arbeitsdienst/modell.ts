import type { Zeile } from "../register/lesen.ts";
import { regelText } from "../regeln.ts";
import type { Mandat, Ort, Stufe } from "../team.ts";

const MODELL: Record<Exclude<Stufe, "lokal">, () => string> = {
  haiku: () => regelText("modell_haiku"),
  sonnet: () => regelText("modell_sonnet"),
  opus: () => regelText("modell_opus"),
  fable: () => regelText("modell_fable"),
};

export function waehle(a: Zeile, m: Mandat): { stufe: Exclude<Stufe, "lokal">; modell: string; ort: Ort; lokal: boolean } {
  const eintrag = m.modellstufen.arbeitsarten[String(a.arbeitsart)] ?? m.modellstufen.standard;
  const gewuenscht = (a.stufe_fest ?? (typeof eintrag === "string" ? eintrag : eintrag.stufe)) as Stufe;
  const ort = typeof eintrag === "string" ? "server" : eintrag.ort;
  const stufe = gewuenscht === "lokal" ? "haiku" : gewuenscht === "fable" && !a.fable_ja ? "opus" : gewuenscht;
  return { stufe, modell: MODELL[stufe](), ort, lokal: gewuenscht === "lokal" };
}
