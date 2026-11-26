import { tokensJeAbo, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { regelListe, regelZahl } from "../regeln.ts";
import { wochenbeginn } from "./kosten.ts";

export function aboReihenfolge(db: Register, jetzt: number): string[] {
  const verbraucht = tokensJeAbo(db, wochenbeginn(jetzt));
  const rest = (abo: string) => Number(wert(db, `abo_limit:${abo}`)?.wert ?? regelZahl("abo_limit_start_tokens")) - (verbraucht.get(abo) ?? 0);
  const pausiert = (abo: string) => (wert(db, `abo_pause:${abo}`)?.gueltig_bis ?? 0) > jetzt;
  return regelListe("abos").filter((a) => !pausiert(a)).sort((a, b) => rest(b) - rest(a));
}
