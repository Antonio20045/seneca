import { ereignisse, uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { auftragAnlegen, befund, ereignis, wertSetzen } from "../register/schreiben.ts";
import { regelListe, regelMs, regelText } from "../regeln.ts";

type Nachricht = { kennung: string; text: string; vonAntonio: boolean };
export type Korrektur = {
  nachricht_kennung: string; wortlaut: string; ort: "skill" | "profil" | "sperre" | "fakt"; ziel: string; kern: string;
  aenderung: { skill?: string; alt?: string; neu?: string; schluessel?: string; wert?: string }; wiederholung_von?: number;
};

function auftrag(db: Register, n: Nachricht, k: Korrektur, an: string, titel: string, ziel: string): string {
  return auftragAnlegen(db, {
    art: "auftrag", wortlaut: k.wortlaut, wortlaut_quelle: n.kennung, titel, ziel, abnahme: "Prüffall zeigt die Änderung", abnahme_durch: "antonio",
    pruefer_noetig: true, verantwortlich: an, auftraggeber: "antonio", quelle: "du", bereich: "Sundartha", arbeitsart: "bauen", nachricht: n,
  }).id;
}

export function korrigieren(db: Register, agent: string, n: Nachricht | undefined, k: Korrektur): { zeile: string; korrektur_nr: number; aehnliche: string[]; wiederholungen_woche: number } {
  if (!n?.vonAntonio || n.kennung !== k.nachricht_kennung || !n.text.includes(k.wortlaut)) throw new Error("Eine Korrektur braucht Antonios Nachricht mit diesem Wortlaut.");
  const frueher = ereignisse(db, { art: "korrektur" }).map((e) => ({ nr: Number(e.nr), ...JSON.parse(String(e.daten)) }));
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
    gleich = frueher.some((f) => f.ort === "skill" && f.ziel === k.ziel && f.nachher === nachher);
  }
  if (k.ort === "sperre") nachher = auftrag(db, n, k, regelText("bausystem"), `Sperre im Ausgang: ${k.kern}`, `Sperre „${k.kern}“ im Ausgang, mit Prüffall`);
  const worte = regelListe("wiederholung_worte").some((w) => k.wortlaut.toLowerCase().includes(w.replace(/_/g, " ")));
  const wiederholung = gleich || worte || k.wiederholung_von !== undefined;
  if (worte && !frueher.length) befund(db, { art: "fehler", satz: `Gesagt, aber nie gelernt: „${k.wortlaut}“` });
  const nr = ereignis(db, { art: "korrektur", wer: agent, schluessel: k.ziel, satz: k.kern, daten: { ort: k.ort, ziel: k.ziel, schluessel: k.aenderung.schluessel, vorher, nachher, kern: k.kern, wiederholung, wiederholung_von: k.wiederholung_von } });
  if (wiederholung) auftrag(db, n, k, regelText("dauerauftraege_von"), `Wiederholung untersuchen: ${k.kern}`, "Ursache gefunden, damit Antonio es nicht noch einmal sagen muss");
  return {
    zeile: `Gelernt: ${k.ort === "skill" ? `Skill „${k.ziel}“` : k.ziel}: ${k.kern}.`, korrektur_nr: nr,
    aehnliche: frueher.filter((f) => f.ort === k.ort).slice(-5).map((f) => `${f.nr}: ${f.kern}`),
    wiederholungen_woche: wiederholungen(db, uhr.jetzt() - regelMs("woche_tage")),
  };
}

function wiederholungen(db: Register, seit: number): number {
  return ereignisse(db, { art: "korrektur", seit }).filter((e) => JSON.parse(String(e.daten)).wiederholung).length;
}
