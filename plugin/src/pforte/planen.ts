import { termineAm, todos, uhr, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { todoSetzen, wertSetzen } from "../register/schreiben.ts";
import { wann, ZAHL } from "./aufgaben.ts";
import { stundeAlsWort, zumWort } from "./heute.ts";
import { letzteUhrzeit, naechsteUhrzeit, regelListe, regelMs, regelText, regelZahl } from "../regeln.ts";

type Block = { von: number; bis: number };

const uhrzeit = (t: number) => new Date(t).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });

export function istFokus(t: { titel: string; teilnehmer: string[] }): boolean {
  return t.teilnehmer.length > 0 || regelListe("fokus_worte").some((w) => t.titel.toLowerCase().includes(w.toLowerCase()));
}

export function belegtAm(db: Register, tag: number): Block[] {
  const fenster = naechsteUhrzeit(regelText("fenster"), tag);
  return [...termineAm(db, tag).filter((t) => !t.ganztag).map((t) => ({ von: t.start, bis: t.ende })), { von: fenster, bis: fenster + regelMs("fenster_dauer_min") }];
}

export function luecken(belegt: Block[], von: number, bis: number): Block[] {
  const frei: Block[] = [];
  let ab = von;
  for (const b of [...belegt].sort((x, y) => x.von - y.von)) {
    if (b.von > ab) frei.push({ von: ab, bis: Math.min(b.von, bis) });
    ab = Math.max(ab, b.bis);
  }
  if (ab < bis) frei.push({ von: ab, bis });
  return frei.filter((l) => l.bis > l.von);
}

function losHinweis(db: Register, jetzt: number): string {
  const t = termineAm(db, jetzt).find((x) => x.ort && !x.ganztag && x.start > jetzt && x.start - jetzt <= regelMs("wegzeit_vorlauf_min"));
  if (!t) return "";
  const ankunft = Number(wert(db, `ankunft:${t.uid}`)?.wert ?? t.start - regelMs("ankunft_puffer_min"));
  const weg = wert(db, `wegzeit:${t.uid}`)?.wert;
  const los = weg ? ` · los um ${uhrzeit(ankunft - Number(weg) * regelMs("eine_minute_min"))}` : "";
  return `${t.titel} in ${t.ort}: an um ${uhrzeit(ankunft)}${los}`;
}

function grund(db: Register, alt: number, neu: number, jetzt: number): string {
  const t = termineAm(db, alt).find((x) => !x.ganztag && x.start > alt);
  const rest = t ? Math.max(0, Math.round((t.start - Math.max(jetzt, alt)) / regelMs("eine_minute_min"))) : 0;
  const vor = t ? ` Vor ${zumWort(t.titel).replace(/^zu(m|r) /, (_, e) => (e === "m" ? "dem " : "der "))} bleiben nur noch ${ZAHL[rest]?.toLowerCase() ?? rest} Minuten.` : "";
  return `Verschoben auf ${stundeAlsWort(neu)}.${vor}`;
}

export function einplanen(db: Register, liste: Zeile[], jetzt: number): { geplant_von: number | null; geplant_bis: number | null }[] {
  const ende = naechsteUhrzeit(regelText("plan_bis"), jetzt);
  const beginn = Math.max(jetzt, naechsteUhrzeit(regelText("plan_von"), ende - regelMs("ein_tag_tage")));
  const belegt = belegtAm(db, beginn);
  return liste.map((t) => {
    const dauer = Number(t.dauer_min ?? regelZahl("todo_dauer_standard_min")) * regelMs("eine_minute_min");
    const l = luecken(belegt, beginn, ende).find((x) => x.bis - x.von >= dauer * regelZahl("luecke_faktor"));
    if (l) belegt.push({ von: l.von, bis: l.von + dauer });
    return l ? { geplant_von: l.von, geplant_bis: l.von + dauer } : { geplant_von: null, geplant_bis: null };
  });
}

export function planenJob(db: Register): void {
  const jetzt = uhr.jetzt();
  const ende = naechsteUhrzeit(regelText("plan_bis"), jetzt);
  const liste = todos(db, "offen").filter((x) => !x.wiederkehrend && wann(x, letzteUhrzeit(regelText("tag_grenze"), jetzt)) === "heute");
  const plaene = einplanen(db, liste, jetzt);
  for (const [i, t] of liste.entries()) {
    const plan = plaene[i];
    if (t.geplant_von && plan.geplant_von && plan.geplant_von > Number(t.geplant_von)) wertSetzen(db, `todo_grund:${t.id}`, JSON.stringify({ vorher: Number(t.geplant_von), satz: grund(db, Number(t.geplant_von), plan.geplant_von, jetzt) }), "planen", ende);
    if (t.geplant_von !== plan.geplant_von || t.geplant_bis !== plan.geplant_bis) todoSetzen(db, { aktion: "aendern", id: String(t.id), felder: plan, geraet: "planen" });
  }
  const hinweis = losHinweis(db, jetzt);
  if ((wert(db, "hinweis:los")?.wert ?? "") !== hinweis) wertSetzen(db, "hinweis:los", hinweis, "planen");
}
