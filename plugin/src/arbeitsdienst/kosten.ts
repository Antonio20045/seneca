import { kostenSeit, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { letzteUhrzeit, regelText, regelZahl } from "../regeln.ts";
import type { Mandat } from "../team.ts";

export function wochenbeginn(t: number, wochen = 0): number {
  const d = new Date(letzteUhrzeit(regelText("tag_grenze"), t));
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7) + wochen * 7);
  return d.getTime();
}

export function kostenCent(tokensEin: number, tokensAus: number): number {
  return Math.round((tokensEin * regelZahl("preis_ein_cent_je_mio_tokens") + tokensAus * regelZahl("preis_aus_cent_je_mio_tokens")) / 1e6);
}

export function euro(cent: number): string {
  return `${(cent / 100).toFixed(2).replace(".", ",")} €`;
}

export function rahmen(db: Register, a: Zeile, m: Mandat, jetzt: number): "frei" | "auftrag" | "woche" {
  if (a.quelle === "dauerauftrag" || a.quelle === "eigene_idee") {
    const woche = wochenbeginn(jetzt);
    const summe = kostenSeit(db, woche, { mitarbeiter: String(a.verantwortlich), quelle: "dauerauftrag" }) + kostenSeit(db, woche, { mitarbeiter: String(a.verantwortlich), quelle: "eigene_idee" });
    return summe >= m.budget.eigene_auftraege_woche_cent ? "woche" : "frei";
  }
  return kostenSeit(db, 0, { auftrag_id: String(a.id) }) >= Number(a.kostenrahmen_cent) ? "auftrag" : "frei";
}

export function wocheSchonGefragt(db: Register, mitarbeiter: string, jetzt: number): boolean {
  return wert(db, `rahmen_woche:${mitarbeiter}`)?.wert === String(wochenbeginn(jetzt));
}
