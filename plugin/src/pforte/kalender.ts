import { ereignisse, termineAm, todos, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { lebensbereich, naechsteUhrzeit, regelListe, regelMs, regelText } from "../regeln.ts";
import { stundeAlsWort, uhrzeit } from "./heute.ts";
import { istFokus } from "./planen.ts";

const ZAHL = ["Keine", "Ein", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht"];
const MAL = ["", "einmal", "zweimal", "dreimal", "viermal"];
export const TAG = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
export const MONAT = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];

type Termin = ReturnType<typeof termineAm>[number];

export const istSport = (titel: string): boolean => regelListe("sport_worte").some((w) => titel.toLowerCase().includes(w.toLowerCase()));

export const art = (t: Termin): string => istFokus(t) ? "fokus" : istSport(t.titel) ? "bewegung" : "termin";

const kurz = (titel: string): string => titel.split(/ mit | · /)[0];

function unter(db: Register, t: Termin): string {
  const ankunft = wert(db, `ankunft:${t.uid}`)?.wert;
  if (art(t) === "fokus") return "Seneca hält alles zurück";
  return [t.ort, ankunft ? `du bist ${uhrzeit(Number(ankunft))} da` : `${Math.round((t.ende - t.start) / regelMs("eine_minute_min"))} Min`].filter(Boolean).join(" · ");
}

export function kalender(db: Register, ruhe: { grund: string; bis: number } | undefined, buendel: { kurz: string | null }, gruppe: { zeit: string; ids: unknown[] } | null, jetzt: number) {
  const tag = termineAm(db, jetzt).filter((t) => !t.ganztag);
  const fenster = naechsteUhrzeit(regelText("fenster"), naechsteUhrzeit("00:00", jetzt) - regelMs("ein_tag_tage"));
  const geplant = todos(db, "offen").filter((t) => t.geplant_von && Number(t.geplant_von) >= jetzt - regelMs("ein_tag_tage") && Number(t.geplant_von) < naechsteUhrzeit("00:00", jetzt));
  const bloecke = [
    ...tag.map((t) => ({ uid: t.uid, von: t.start, bis: t.ende, titel: art(t) === "fokus" ? `Fokus bis ${uhrzeit(t.ende)}` : t.titel, unter: unter(db, t), art: art(t) })),
    ...(geplant.length ? [{ uid: null, von: Math.min(...geplant.map((t) => Number(t.geplant_von))), bis: Math.max(...geplant.map((t) => Number(t.geplant_bis ?? t.geplant_von))), titel: "To-dos", unter: "", art: "todos" }] : []),
    ...(buendel.kurz ? [{ uid: null, von: fenster, bis: fenster + regelMs("fenster_dauer_min"), titel: "Entscheiden", unter: buendel.kurz, art: "fenster" }] : []),
  ].sort((a, b) => a.von - b.von).map((b) => b.art === "todos" ? { ...b, unter: `von Seneca geblockt · ${Math.round((b.bis - b.von) / regelMs("eine_minute_min"))} Min` } : b);
  const eintraege = bloecke.flatMap((b, i) => {
    const n = bloecke[i + 1];
    const zeile = { ...b, jetzt: b.von <= jetzt && b.bis > jetzt };
    if (!n || n.von - b.bis < regelMs("aufgaben_block_min")) return [zeile];
    const passt = gruppe && gruppe.zeit.startsWith(uhrzeit(b.bis)) ? ` · deine ${gruppe.ids.length} To-dos passen hier` : "";
    return [zeile, { art: "frei", text: `frei bis ${gruppe && passt ? gruppe.zeit.slice(-5) : uhrzeit(n.von)}${passt}` }];
  });
  const termine = tag.filter((t) => art(t) === "termin").length, sport = tag.filter((t) => art(t) === "bewegung").length;
  const vor = `${termine ? `${ZAHL[termine] ?? termine} ${termine === 1 ? "Termin" : "Termine"}` : "Keine Termine"}${sport ? `, ${MAL[sport] ?? `${sport}-mal`} Sport` : ""}.`;
  const los = losTermin(db, jetzt);
  return {
    satz: [vor, ruhe?.grund === "fokus" ? `Bis ${stundeAlsWort(ruhe.bis)} hält Seneca dir frei.` : termine ? "Dazwischen ist Luft." : "Der Tag gehört dir."],
    eintraege,
    hinweis: los ? `Zum ${kurz(String(los.ort)).split(" ")[0]} sind es ${wert(db, `wegzeit:${los.uid}`)?.wert} Minuten zu Fuß. Ich erinnere dich um ${uhrzeit(Number(erinnernUm(db, jetzt)))}.` : null,
    woche: woche(db, jetzt),
  };
}

function losTermin(db: Register, jetzt: number): Termin | undefined {
  return termineAm(db, jetzt).find((t) => !t.ganztag && t.ort && t.start > jetzt && wert(db, `wegzeit:${t.uid}`));
}

export function erinnernUm(db: Register, jetzt: number): number | undefined {
  const t = losTermin(db, jetzt);
  return t && Number(wert(db, `ankunft:${t.uid}`)?.wert ?? t.start) - Number(wert(db, `wegzeit:${t.uid}`)?.wert) * regelMs("eine_minute_min") - regelMs("los_erinnern_min");
}

export function terminSicht(db: Register, t: Termin) {
  const n = ereignisse(db, { art: "wert.gesetzt", schluessel: `termin_notiz:${t.uid}`, grenze: 1 })[0];
  const mit = t.teilnehmer.length ? t.teilnehmer : t.titel.split(" mit ").slice(1);
  return { ...t, art: art(t), mit, ankunft: Number(wert(db, `ankunft:${t.uid}`)?.wert ?? 0) || null, weg_min: Number(wert(db, `wegzeit:${t.uid}`)?.wert ?? 0) || null,
    entfernung_m: Number(wert(db, `entfernung:${t.uid}`)?.wert ?? 0) || null, kalender_quelle: t.kalender ? regelText("kalender_quelle") : null, bereich: lebensbereich(`${t.titel} ${t.kalender ?? ""}`),
    notiz: n ? { satz: JSON.parse(String(n.daten)).wert, um: n.zeit } : null,
    bescheid: n && mit.length ? `${mit.join(", ")} ${mit.length === 1 ? "weiß" : "wissen"} Bescheid, seit ${uhrzeit(Number(n.zeit))}` : null };
}

function woche(db: Register, jetzt: number) {
  const d = new Date(jetzt);
  const montag = new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((d.getDay() + 6) % 7)).getTime();
  const tage = [0, 1, 2, 3, 4, 5, 6].map((i) => {
    const t = new Date(montag); t.setDate(t.getDate() + i);
    const liste = termineAm(db, t.getTime()).filter((x) => !x.ganztag);
    const doppelt = liste.find((a) => liste.some((b) => b !== a && b.start < a.ende && a.start < b.ende && art(a) === "termin" && art(b) === "termin"));
    return { datum: t.getTime(), kurz: TAG[t.getDay()].slice(0, 2).toUpperCase(), nr: t.getDate(), termine: liste.filter((x) => art(x) === "termin").length,
      bloecke: liste.map((x) => ({ von: x.start, bis: x.ende, art: art(x) })),
      text: doppelt ? `Zwei Termine gleichzeitig um ${new Date(doppelt.start).getHours()} Uhr` : liste.map((x) => kurz(x.titel)).join(", "), warnung: !!doppelt };
  });
  const ende = new Date(tage[6].datum);
  const voll = tage.filter((t) => t.datum >= montag && t.datum + regelMs("ein_tag_tage") > jetzt).sort((a, b) => b.termine - a.termine)[0];
  const wochenende = tage.slice(5).flatMap((t) => termineAm(db, t.datum).filter((x) => art(x) === "termin"));
  return {
    kopf: `Woche ${kalenderwoche(jetzt)} · ${new Date(montag).getDate()}. bis ${ende.getDate()}. ${MONAT[ende.getMonth()]}`,
    satz: [voll?.termine ? `${TAG[new Date(voll.datum).getDay()]} braucht dich.` : "Eine ruhige Woche.", wochenende.length ? `Am Wochenende nur ${wochenende.length === 1 ? `der ${kurz(wochenende[0].titel).split(" ")[0]}` : `${wochenende.length} Termine`}.` : "Das Wochenende ist frei."],
    tage,
  };
}

export function kalenderwoche(t: number): number {
  const d = new Date(t); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
  const w1 = new Date(d.getFullYear(), 0, 4);
  return 1 + Math.round(((d.getTime() - w1.getTime()) / regelMs("ein_tag_tage") - 3 + ((w1.getDay() + 6) % 7)) / 7);
}
