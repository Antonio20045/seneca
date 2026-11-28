import { ereignisse, uhr, wert, wiederholungenSeit, zurueckgenommen } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { auftragAnlegen, befund, ereignis, wertSetzen } from "../register/schreiben.ts";
import { regelListe, regelMs, regelText, regelZahl } from "../regeln.ts";

type Nachricht = { kennung: string; text: string; vonAntonio: boolean };
export type Korrektur = {
  nachricht_kennung?: string; wortlaut: string; ort: "skill" | "profil" | "sperre" | "fakt"; ziel: string; kern: string;
  aenderung: { skill?: string; alt?: string; neu?: string; schluessel?: string; wert?: string }; wiederholung_von?: number;
};
type Frueher = { nr: number; ort: string; ziel: string; kern: string; nachher: string | null; wortlaut?: string };

function auftrag(db: Register, n: Nachricht, k: Korrektur, an: string, titel: string, ziel: string): string {
  return auftragAnlegen(db, {
    art: "auftrag", wortlaut: k.wortlaut, wortlaut_quelle: n.kennung, titel, ziel, abnahme: "Prüffall zeigt die Änderung", abnahme_durch: "antonio",
    pruefer_noetig: true, verantwortlich: an, auftraggeber: "antonio", quelle: "du", bereich: "Sundartha", arbeitsart: "bauen", nachricht: n,
  }).id;
}

function vonAntonio(db: Register, n: Nachricht | undefined, k: Korrektur): Nachricht {
  if (n?.vonAntonio && (!k.nachricht_kennung || n.kennung === k.nachricht_kennung) && n.text.includes(k.wortlaut)) return n;
  const e = k.nachricht_kennung ? ereignisse(db, { art: "entscheidung", schluessel: k.nachricht_kennung, grenze: 1 })[0] : undefined;
  if (e && String(e.satz).includes(k.wortlaut)) return { kennung: String(k.nachricht_kennung), text: String(e.satz), vonAntonio: true };
  throw new Error("Eine Korrektur braucht Antonios Nachricht oder seinen Satz beim Nachbessern, mit diesem Wortlaut.");
}

function worte(text: string): Set<string> {
  return new Set(text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= regelZahl("lernen_wort_ab_zeichen")));
}

function aehnlichste(frueher: Frueher[], k: Korrektur): Frueher[] {
  const meine = worte(`${k.kern} ${k.wortlaut} ${k.ziel}`);
  const punkte = (f: Frueher) => [...worte(`${f.kern} ${f.wortlaut ?? ""} ${f.ziel}`)].filter((w) => meine.has(w)).length;
  return frueher.filter((f) => punkte(f) > 0).sort((a, b) => punkte(b) - punkte(a) || b.nr - a.nr).slice(0, regelZahl("lernen_aehnliche"));
}

export function korrigieren(db: Register, agent: string, nachricht: Nachricht | undefined, k: Korrektur): { zeile: string; korrektur_nr: number; aehnliche: string[]; wiederholungen_woche: number } {
  const n = vonAntonio(db, nachricht, k);
  const frueher: Frueher[] = ereignisse(db, { art: "korrektur" }).filter((e) => !zurueckgenommen(db, Number(e.nr))).map((e) => ({ nr: Number(e.nr), ...JSON.parse(String(e.daten)) }));
  const aehnlich = aehnlichste(frueher, k);
  let vorher: string | null = null;
  let nachher: string | null = null;
  let gleich = false;
  if (k.ort === "profil" || k.ort === "fakt") {
    const schluessel = String(k.aenderung.schluessel);
    if (!schluessel.startsWith(`${k.ort}:`)) throw new Error(`Schlüssel muss mit ${k.ort}: beginnen.`);
    vorher = wert(db, schluessel)?.wert ?? null;
    nachher = String(k.aenderung.wert);
    gleich = vorher === nachher;
    if (!gleich) wertSetzen(db, schluessel, nachher, "lernen");
  }
  if (k.ort === "skill") {
    vorher = k.aenderung.alt ?? null;
    nachher = k.aenderung.neu ?? null;
    if ((nachher ?? "").split("\n").length > (vorher ?? "").split("\n").length + 1) throw new Error("Ein Skill wächst je Korrektur höchstens um eine Zeile.");
    gleich = frueher.some((f) => f.ort === "skill" && f.ziel === k.ziel && f.nachher === nachher);
  }
  if (k.ort === "sperre") nachher = auftrag(db, n, k, regelText("bausystem"), `Sperre im Ausgang: ${k.kern}`, `Sperre „${k.kern}“ im Ausgang, mit Prüffall`);
  const gesagt = regelListe("wiederholung_worte").some((w) => k.wortlaut.toLowerCase().includes(w.replace(/_/g, " ")));
  const wiederholung = gleich || gesagt || k.wiederholung_von !== undefined;
  if (gesagt && !aehnlich.length) befund(db, { art: "fehler", satz: `Gesagt, aber nie gelernt: „${k.wortlaut}“` });
  const zeile = `Gelernt: ${k.ort === "skill" ? `Skill „${k.ziel}“` : k.ziel}: ${k.kern}.`;
  const nr = ereignis(db, { art: "korrektur", wer: agent, schluessel: k.ziel, satz: zeile,
    daten: { ort: k.ort, ziel: k.ziel, schluessel: k.aenderung.schluessel, vorher, nachher, kern: k.kern, wortlaut: k.wortlaut.slice(0, regelZahl("titel_zeichen")), wiederholung, wiederholung_von: k.wiederholung_von } });
  if (wiederholung) auftrag(db, n, k, k.ort === "skill" ? agent : regelText("dauerauftraege_von"), `Wiederholung untersuchen: ${k.kern}`, "Ursache gefunden, damit Antonio es nicht noch einmal sagen muss");
  return { zeile, korrektur_nr: nr, aehnliche: aehnlich.map((f) => `${f.nr}: ${f.kern}`), wiederholungen_woche: wiederholungenSeit(db, uhr.jetzt() - regelMs("woche_tage")) };
}
