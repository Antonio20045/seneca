import { ereignisse, fragen, kalenderTag, termineAm, todos, vorschlagDaten, wert, werte } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { msAusMinuten, regelListe, regelMs, regelText, regelZahl } from "../regeln.ts";
import { fensterStart, istSport } from "./entscheiden.ts";
import { uhrzeit } from "./heute.ts";

type Termin = ReturnType<typeof termineAm>[number] & { namen?: string[]; notiz?: string; kalender?: string; wartet?: boolean };
type Block = { id: string; titel: string; unter: string | null; start: number; ende: number; art: string; laeuft?: boolean; frage_id?: string; uid?: string; teile?: string[]; detail?: object; andere?: number[] };

const TAG = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
const MONAT = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
const WEG: Record<string, string> = { fuss: "zu Fuß", rad: "mit dem Rad", auto: "mit dem Auto" };

const komma = (n: number) => n.toFixed(1).replace(".", ",");

function tagBeginn(t: number): number {
  const d = new Date(t);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function montag(t: number): number {
  const d = new Date(tagBeginn(t));
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return d.getTime();
}

function plusTage(t: number, n: number): number {
  const d = new Date(t);
  d.setDate(d.getDate() + n);
  return d.getTime();
}

function wochenZwischen(a: number, b: number): number {
  return Math.round((b - a) / (7 * regelMs("ein_tag_h")));
}

function kalenderwoche(t: number): number {
  const donnerstag = new Date(plusTage(montag(t), 3));
  return 1 + wochenZwischen(montag(new Date(donnerstag.getFullYear(), 0, 4).getTime()), montag(t));
}

function wochenKopf(von: number, jetzt: number) {
  const bis = plusTage(von, 6);
  const [a, b] = [new Date(von), new Date(bis)];
  const n = wochenZwischen(montag(jetzt), von);
  const titel = n === 0 ? "Diese Woche" : n === 1 ? "Nächste Woche" : n === -1 ? "Letzte Woche" : n > 0 ? `In ${n} Wochen` : `Vor ${-n} Wochen`;
  const spanne = a.getMonth() === b.getMonth() ? `${a.getDate()}.–${b.getDate()}. ${MONAT[b.getMonth()]}` : `${a.getDate()}. ${MONAT[a.getMonth()]} – ${b.getDate()}. ${MONAT[b.getMonth()]}`;
  return { von, titel, unter: `${spanne} · Woche ${kalenderwoche(von)}` };
}

function kurz(titel: string): string {
  const worte = titel.split(" ");
  return worte.find((w) => !regelListe("anruf_worte").includes(w.toLowerCase())) ?? worte[0];
}

function istSeneca(t: Termin): boolean {
  return t.uid.endsWith("-seneca") || t.kalender === regelText("kalender_seneca") || regelListe("fokus_worte").some((w) => t.titel.toLowerCase().includes(w.toLowerCase()));
}

function eintraege(db: Register, art: string, von: number, bis: number): Record<string, number>[] {
  return db.prepare("SELECT werte FROM eintrag WHERE art = ? AND zeit >= ? AND zeit < ? AND zustand = 'gueltig'").all(art, von, bis).map((z) => JSON.parse(String(z.werte)));
}

function bewegung(db: Register, t: Termin, jetzt: number): [string, string | null] {
  if (t.start > jetzt) return [t.titel, t.ort ?? uhrzeit(t.start)];
  const saetze = eintraege(db, "satz", t.start, t.ende).length;
  const lauf = eintraege(db, "laufen", tagBeginn(t.start), plusTage(tagBeginn(t.start), 1))[0];
  const km = lauf ? Number(lauf.km ?? Number(lauf.m) / 1000) : 0;
  return [saetze ? `${t.titel} · ${saetze} Sätze` : t.titel, km ? `${komma(km)} km` : t.ort ?? uhrzeit(t.start)];
}

function gesetzt(db: Register, schluessel: string): { wert: string; wer: string; zeit: number } | undefined {
  const e = ereignisse(db, { art: "wert.gesetzt", schluessel, grenze: 1 })[0];
  const w = e && JSON.parse(String(e.daten)).wert;
  return w ? { wert: w, wer: String(e.wer), zeit: Number(e.zeit) } : undefined;
}

export function weg(db: Register, t: Termin) {
  const ankunft = gesetzt(db, `ankunft:${t.uid}`);
  const min = Number(wert(db, `wegzeit:${t.uid}`)?.wert ?? 0);
  const w = min ? { min, m: Number(wert(db, `entfernung:${t.uid}`)?.wert ?? 0) || null, art: wert(db, `wegart:${t.uid}`)?.wert ?? "fuss" } : null;
  const da = ankunft ? Number(ankunft.wert) : null;
  const los = w ? (da ?? t.start - regelMs("ankunft_puffer_min")) - msAusMinuten(w.min) : null;
  return {
    da, da_satz: ankunft && ankunft.wer === regelText("dauerauftraege_von") && t.namen?.length ? `${t.namen.join(", ")} weiß Bescheid, seit ${uhrzeit(ankunft.zeit)}` : null,
    weg: w ? `${w.min} Min ${WEG[w.art] ?? WEG.fuss}` : null, km: w?.m ? `${komma(w.m / 1000)} km von hier` : null,
    los: los === null ? null : `los um ${uhrzeit(los)} · Uhr erinnert ${uhrzeit(los - regelMs("weg_erinnern_vor_min"))}`,
    los_ms: los,
    kurz: [da ? `du bist ${uhrzeit(da)} da` : "", w ? `${w.min} Min ${WEG[w.art] ?? WEG.fuss}` : ""].filter(Boolean).join(" · ") || null,
  };
}

function detail(db: Register, t: Termin) {
  const d = new Date(t.start);
  const notiz = gesetzt(db, `termin:${t.uid}`);
  return ohneLeer({
    datum: `${TAG[d.getDay()].slice(0, 2)} ${d.getDate()}. ${MONAT[d.getMonth()].slice(0, 3)} · ${uhrzeit(t.start)} bis ${uhrzeit(t.ende)}`,
    ort: t.ort ?? null, mit: t.namen?.join(", ") || null, kalender: t.kalender ?? null, notiz: t.notiz || null, ...weg(db, t),
    seneca: notiz ? { zeit: notiz.zeit, satz: notiz.wert } : null,
  });
}

function ohneLeer(o: Record<string, unknown>) {
  return Object.fromEntries(Object.entries(o).filter(([, w]) => w !== null && w !== undefined));
}

function offeneSchreibungen(db: Register): { aktion: string; uid: string; titel: string; start: number; ende: number; ort?: string; kalender?: string }[] {
  return [...werte(db, "kalender:schreiben:").values()].filter(Boolean).map((v) => JSON.parse(v));
}

function termineDesTages(db: Register, tag: number): Termin[] {
  const offen = offeneSchreibungen(db);
  const neu = offen.filter((o) => o.aktion === "anlegen" && kalenderTag(o.start) === kalenderTag(tag)).map((o) => ({ ...o, teilnehmer: [], ganztag: false, wartet: true }));
  return [...termineAm(db, tag), ...neu].map((t) => {
    const v = offen.find((o) => o.aktion === "verschieben" && o.uid === t.uid);
    return v ? { ...t, start: v.start, ende: v.ende, wartet: true } : t;
  }).filter((t) => !t.ganztag).sort((a, b) => a.start - b.start);
}

function zugleich(liste: Termin[]): Termin[][] {
  const gruppen: Termin[][] = [];
  for (const t of liste) {
    const g = gruppen.find((x) => x.some((y) => y.start < t.ende && t.start < y.ende));
    if (g) g.push(t);
    else gruppen.push([t]);
  }
  return gruppen;
}

function andere(db: Register, t: { titel: string; start: number; ende: number }, jetzt: number): number[] {
  const liste = termineDesTages(db, t.start);
  const schritt = msAusMinuten(regelZahl("anders_schritt_min"));
  const versuche = Array.from({ length: regelZahl("anders_versuche") }, (_, i) => t.start + (i % 2 ? -1 : 1) * (Math.floor(i / 2) + 1) * schritt);
  return versuche.filter((s) => s > jetzt && frei(liste, { ...t, uid: "", teilnehmer: [], ganztag: false }, s)).slice(0, 3).sort((a, b) => a - b);
}

function vorschlaege(db: Register): { frage: string; termin: { titel: string; start: number; ende: number } }[] {
  return fragen(db, "offen").filter((f) => f.art === "vorschlag")
    .map((f) => ({ frage: String(f.id), termin: (vorschlagDaten(db, String(f.auftrag_id)).wirkung as { termin?: { titel: string; start: number; ende: number } } | undefined)?.termin }))
    .filter((v): v is { frage: string; termin: { titel: string; start: number; ende: number } } => !!v.termin);
}

function bloecke(db: Register, tag: number, jetzt: number): { bloecke: Block[]; marken: { titel: string; zeit: number }[] } {
  const alle = termineDesTages(db, tag);
  const marken = alle.filter((t) => t.ende - t.start <= msAusMinuten(regelZahl("kal_marke_bis_min")) && !istSport(t.titel)).map((t) => ({ titel: t.titel, zeit: t.start }));
  const liste = alle.filter((t) => !marken.some((m) => m.zeit === t.start && m.titel === t.titel));
  const b: Block[] = [];
  for (const g of zugleich(liste.filter((t) => !istSeneca(t) && !istSport(t.titel)))) {
    if (g.length === 1) {
      const t = g[0];
      b.push({ id: t.uid, uid: t.uid, titel: t.titel, unter: t.wartet ? "wird eingetragen" : uhrzeit(t.start), start: t.start, ende: t.ende, art: "termin", detail: detail(db, t) });
    } else b.push({ id: g.map((t) => t.uid).join("+"), titel: g.map((t) => kurz(t.titel)).join(" + "), unter: `${g.length} zugleich`, art: "zugleich", teile: g.map((t) => t.titel),
      start: Math.min(...g.map((t) => t.start)), ende: Math.max(...g.map((t) => t.ende)) });
  }
  for (const t of liste.filter((x) => istSeneca(x))) {
    const laeuft = t.start <= jetzt && t.ende > jetzt;
    b.push({ id: t.uid, uid: t.uid, titel: t.titel, unter: laeuft ? "läuft" : "von Seneca", start: t.start, ende: t.ende, art: "seneca", laeuft, detail: detail(db, t) });
  }
  for (const t of liste.filter((x) => !istSeneca(x) && istSport(x.titel))) {
    const [titel, unter] = bewegung(db, t, jetzt);
    b.push({ id: t.uid, uid: t.uid, titel, unter, start: t.start, ende: t.ende, art: "bewegung", detail: detail(db, t) });
  }
  for (const v of vorschlaege(db).filter((x) => kalenderTag(x.termin.start) === kalenderTag(tag))) {
    const sport = istSport(v.termin.titel);
    b.push({ id: `vorschlag:${v.frage}`, frage_id: v.frage, titel: sport ? `${v.termin.titel}?` : v.termin.titel, unter: sport ? null : "Vorschlag", start: v.termin.start, ende: v.termin.ende, art: sport ? "bewegung_vorschlag" : "vorschlag", andere: andere(db, v.termin, jetzt) });
  }
  const geplant = todos(db, "offen").filter((t) => t.geplant_von !== null && kalenderTag(Number(t.geplant_von)) === kalenderTag(tag))
    .map((t) => ({ von: Number(t.geplant_von), bis: Number(t.geplant_bis ?? t.geplant_von) })).sort((x, y) => x.von - y.von);
  for (const t of geplant) {
    const letzter = b.at(-1);
    if (letzter?.art === "todos" && letzter.ende >= t.von) letzter.ende = Math.max(letzter.ende, t.bis);
    else b.push({ id: `todos:${t.von}`, titel: "To-dos", unter: "von Seneca", start: t.von, ende: t.bis, art: "todos" });
  }
  const fenster = fensterStart(jetzt);
  if (kalenderTag(fenster) === kalenderTag(tag)) b.push({ id: `fenster:${fenster}`, titel: "Entscheiden", unter: null, start: fenster, ende: fenster + msAusMinuten(regelZahl("fenster_dauer_min")), art: "fenster" });
  return { bloecke: b.sort((x, y) => x.start - y.start), marken };
}

function bodyBattery(db: Register, tag: number, jetzt: number): number | null {
  if (kalenderTag(tag) === kalenderTag(jetzt)) return JSON.parse(wert(db, "koerper")?.wert ?? "null")?.body_battery ?? null;
  const z = db.prepare("SELECT daten FROM ereignis WHERE art = 'wert.gesetzt' AND schluessel = 'koerper:morgens' AND zeit >= ? AND zeit < ? ORDER BY nr DESC LIMIT 1").get(tag, plusTage(tag, 1));
  return z ? JSON.parse(JSON.parse(String(z.daten)).wert).body_battery : null;
}

function frei(liste: Termin[], t: Termin, start: number): boolean {
  const ende = start + t.ende - t.start;
  const d = new Date(start);
  const [von, bis] = [regelText("kal_tag_von"), regelText("kal_tag_bis")].map((h) => new Date(start).setHours(Number(h.split(":")[0]), Number(h.split(":")[1]), 0, 0));
  return start >= von && ende <= bis && d.getDate() === new Date(t.start).getDate() && !liste.some((x) => x.uid !== t.uid && x.start < ende && start < x.ende);
}

function plant(db: Register, jetzt: number) {
  for (let tag = tagBeginn(jetzt); tag < plusTage(tagBeginn(jetzt), regelZahl("woche_tage")); tag = plusTage(tag, 1)) {
    const liste = termineDesTages(db, tag).filter((t) => !istSeneca(t) && !istSport(t.titel) && t.ende > jetzt);
    for (const g of zugleich(liste).filter((x) => x.length > 1)) {
      const id = g.map((t) => t.uid).join("+");
      if (wert(db, `kalender:lassen:${id}`)?.wert) continue;
      const weg = [...g].sort((a, b) => a.ende - a.start - (b.ende - b.start))[0];
      const schritt = msAusMinuten(regelZahl("kal_suche_schritt_min"));
      const versuche = Array.from({ length: regelZahl("kal_suche_schritte") }, (_, i) => [weg.start - (i + 1) * schritt, weg.start + (i + 1) * schritt]).flat();
      const neu = versuche.find((s) => s > jetzt && frei(liste, weg, s));
      const gleich = g.every((t) => t.start === g[0].start);
      const namen = g.map((t) => t.titel);
      const wie = `${namen.slice(0, -1).join(", ")} und ${namen.at(-1)} ${gleich ? `liegen ${g.length === 2 ? "beide" : "alle"} um` : "überschneiden sich ab"} ${uhrzeit(Math.max(...g.map((t) => t.start)))}.`;
      return { id, titel: `${TAG[new Date(tag).getDay()]} überschneidet sich`, text: neu ? `${wie} ${kurz(weg.titel)} auf ${uhrzeit(neu)} legen? Dort ist frei.` : wie,
        knopf: neu ? `Auf ${uhrzeit(neu)}` : null, uid: weg.uid, start: neu ?? null, ende: neu ? neu + weg.ende - weg.start : null };
    }
  }
  return null;
}

export function wochenplan(db: Register, jetzt: number) {
  const von = plusTage(montag(jetzt), -7 * regelZahl("kal_wochen_zurueck"));
  const wochen = regelZahl("kal_wochen_zurueck") + 1 + regelZahl("kal_wochen_vor");
  return {
    wochen: Array.from({ length: wochen }, (_, i) => wochenKopf(plusTage(von, 7 * i), jetzt)),
    tage: Array.from({ length: wochen * 7 }, (_, i) => {
      const tag = plusTage(von, i);
      return { tag, bb: bodyBattery(db, tag, jetzt), ganztag: termineAm(db, tag).filter((t) => t.ganztag).map((t) => t.titel), ...bloecke(db, tag, jetzt) };
    }),
    plant: plant(db, jetzt),
    kalender: JSON.parse(wert(db, "kalender:liste")?.wert ?? "[]"),
    standard: regelText("kalender_standard"),
    tag_von: Number(regelText("kal_tag_von").split(":")[0]), tag_bis: Number(regelText("kal_tag_bis").split(":")[0]),
  };
}
