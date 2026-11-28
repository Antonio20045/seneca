import { auftraege, eintraegeSeit, ereignisse, fragen, todos, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { regelMs, regelText, regelZahl } from "../regeln.ts";
import { anzeigeName } from "../team.ts";

const ANZAHL = ["Nichts", "Eine Sache", "Zwei Sachen", "Drei Sachen", "Vier Sachen", "Fünf Sachen"];
const SENECA = ["briefing", "rueckblick"];
const ZAHLEN: [string, string, string][] = [["satz", "anzahl", "SÄTZE"], ["lesen", "m", "MIN LESEN"]];

type Lauf = { satz: string; um: number; beleg: string | null; neu: string[] };

function laeufe(db: Register, a: Zeile): Lauf[] {
  return ereignisse(db, { art: "fortschreibung", auftrag_id: String(a.id), grenze: regelZahl("berichte_laeufe") }).map((e) => ({
    satz: String(e.satz), um: Number(e.zeit), beleg: e.beleg ? String(e.beleg) : null,
    neu: ereignisse(db, { art: "befund", lauf_id: String(e.lauf_id) }).filter((b) => JSON.parse(String(b.daten)).art === "teilergebnis").reverse().map((b) => String(b.satz)),
  }));
}

function eigener(db: Register, arbeitsart: string): Lauf | undefined {
  const a = auftraege(db, ["bereit", "laeuft", "wartet"]).find((x) => x.quelle === "dauerauftrag" && x.arbeitsart === arbeitsart && x.verantwortlich === regelText("dauerauftraege_von"));
  return a ? laeufe(db, a)[0] : undefined;
}

export function berichte(db: Register, tagBeginn: number, jetzt: number) {
  const liste = auftraege(db, ["bereit", "laeuft", "wartet"])
    .filter((a) => a.quelle === "dauerauftrag" && a.arbeitsart !== "rundgang" && !SENECA.includes(String(a.arbeitsart)))
    .map((a) => ({ a, l: laeufe(db, a) })).filter(({ l }) => l.length);
  const neu = liste.filter(({ l }) => l[0].neu.length).map(({ a, l }) => ({ id: a.id, kopf: [a.titel, a.verantwortlich === regelText("dauerauftraege_von") ? null : a.projekt ?? a.bereich].filter(Boolean).join(" · "), um: l[0].um,
    text: l[0].neu.join(" "), beleg: l[0].beleg, wer: a.verantwortlich, wer_name: anzeigeName(String(a.verantwortlich)) }));
  const gleich = liste.filter(({ l }) => !l[0].neu.length).map(({ a, l }) => {
    const bis = l.findIndex((x) => x.neu.length);
    const seit = l[bis === -1 ? l.length - 1 : bis - 1].um;
    return { id: a.id, text: l[0].satz, seit_tage: Math.max(1, Math.round((jetzt - seit) / regelMs("ein_tag_tage"))) };
  });
  const briefing = eigener(db, "briefing");
  const gestern = eigener(db, "rueckblick");
  return {
    satz: [`${ANZAHL[neu.length] ?? `${neu.length} Sachen`} ${neu.length < 2 ? "ist" : "sind"} neu.`, gleich.length ? `Alles ${neu.length ? "andere " : ""}läuft wie gestern.` : ""].filter(Boolean),
    neu, unveraendert: gleich,
    seneca: briefing && briefing.um >= tagBeginn ? { kopf: "Morgen-Briefing", um: briefing.um, text: briefing.satz,
      gestern: gestern && gestern.um < tagBeginn ? gestern.satz.split(/(?<=[.!?])\s+/)[0] : null } : null,
  };
}

function zahl(n: number, stellen = 0): string {
  return n.toLocaleString("de-DE", { minimumFractionDigits: stellen, maximumFractionDigits: stellen });
}

export function tagesZahlen(db: Register, tagBeginn: number) {
  const heute = eintraegeSeit(db, tagBeginn).map((e) => ({ art: String(e.art), w: JSON.parse(String(e.werte)) }));
  const laeufe = heute.filter((e) => e.art === "lauf");
  const namen = [...new Set(laeufe.map((e) => String(e.w.name ?? "Laufen")))];
  const erledigt = ereignisse(db, { art: "todo.erledigt", seit: tagBeginn }).filter((e) => todos(db, "erledigt").some((t) => t.id === e.schluessel)).length + auftraege(db, ["erledigt"]).filter((x) => Number(x.geaendert) >= tagBeginn).length;
  return [
    laeufe.length ? { wert: zahl(laeufe.reduce((s, e) => s + Number(e.w.km ?? 0), 0), 1), name: `KM ${(namen.length === 1 ? namen[0] : "Laufen").toUpperCase()}` } : null,
    ...ZAHLEN.map(([art, feld, name]) => {
      const e = heute.filter((x) => x.art === art);
      return e.length ? { wert: zahl(feld === "anzahl" ? e.length : e.reduce((s, x) => s + Number(x.w[feld] ?? 0), 0)), name } : null;
    }),
    { wert: zahl(erledigt), name: "ERLEDIGT" },
  ].filter(Boolean);
}

export function rueckblick(db: Register, tagBeginn: number) {
  const r = eigener(db, "rueckblick");
  if (!r || r.um < tagBeginn) return null;
  const a = auftraege(db, ["bereit", "laeuft", "wartet"]).find((x) => x.quelle === "dauerauftrag" && x.arbeitsart === "rueckblick");
  const f = fragen(db, "offen").find((x) => x.auftrag_id === a?.id);
  return { um: r.um, saetze: r.satz.split(/(?<=[.!?])\s+/), frage: f ? { id: f.id, optionen: JSON.parse(String(f.optionen)) } : null, zahlen: tagesZahlen(db, tagBeginn) };
}
