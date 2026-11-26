import { hole, letztesTraining, termineAm, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { regelListe, regelMs, regelZahl } from "../regeln.ts";
import { istFokus } from "./planen.ts";

const ZAHLWORT = ["", "eine", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"];
const STUNDE = ["zwölf", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf"];

type Termin = ReturnType<typeof termineAm>[number];

const uhrzeit = (t: number) => new Date(t).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });

function stundeAlsWort(t: number): string {
  const d = new Date(t);
  return d.getMinutes() === 0 ? STUNDE[d.getHours() % 12] : uhrzeit(t);
}

function dauerAlsWort(min: number): string {
  const [n, einheit] = min >= 60 && min % 60 === 0 ? [min / 60, ["Stunde", "Stunden"]] : [min, ["Minute", "Minuten"]];
  return `${ZAHLWORT[n] ?? n} ${n === 1 ? einheit[0] : einheit[1]}`;
}

function artikel(titel: string): [string, string] {
  if (titel.includes(" ")) return [titel, "das"];
  if (/(ung|heit|keit|schaft|e)$/.test(titel)) return [`die ${titel}`, "sie"];
  if (/(chen|ment|um)$/.test(titel)) return [`das ${titel}`, "es"];
  return [`der ${titel}`, "er"];
}

function kurzName(titel: string): string {
  return regelListe("anruf_worte").some((w) => titel.toLowerCase().includes(w)) ? "Ein Anruf" : titel;
}

function dann(a: Termin, b: Termin): string {
  if (b.start - a.ende < regelMs("satz_ruhe_ab_min")) return `dann ${artikel(b.titel)[0]}.`;
  const wort = b.titel.split(" ")[0];
  return `dann Ruhe bis ${artikel(wort)[1] === "sie" ? "zur" : "zum"} ${wort}.`;
}

export function heute(db: Register, ruhe: { grund: string; bis: number } | undefined, jetzt: number) {
  const ab = ruhe?.grund === "fokus" ? ruhe.bis : jetzt;
  const [a, b] = termineAm(db, jetzt).filter((t: Termin) => !t.ganztag && t.start >= ab && !istFokus(t));
  if (ruhe?.grund === "fokus") {
    const vor = `Fokus bis ${stundeAlsWort(ruhe.bis)}.`;
    if (!a) return { satz: [vor, "Danach ist der Tag frei."], satz_folge: [vor, "Danach ist der Tag frei."] };
    const [erster, pronomen] = artikel(a.titel);
    const min = Math.round((a.ende - a.start) / regelMs("eine_minute_min"));
    return {
      satz: [vor, `Danach zuerst ${erster}, ${pronomen} dauert ${dauerAlsWort(min)}.`],
      satz_folge: [vor, b ? `Danach zuerst ${erster}, dann ${artikel(b.titel)[0]}.` : `Danach ${erster}.`],
    };
  }
  const satz = a ? [`${kurzName(a.titel)},`, b ? dann(a, b) : "danach Ruhe."] : ["Heute steht", "nichts mehr an."];
  return { satz, satz_folge: satz };
}

export function projektVon(db: Register, auftragId: unknown): string | null {
  if (!auftragId) return null;
  const a = hole(db, "auftrag", String(auftragId));
  return (a.projekt ?? a.bereich ?? null) as string | null;
}

export function restMin(db: Register, l: Zeile, jetzt: number): number | null {
  const schaetzung = hole(db, "auftrag", String(l.auftrag_id)).schaetzung_min;
  if (schaetzung === null || schaetzung === undefined) return null;
  return Math.max(0, Math.ceil((Number(l.gestartet) + Number(schaetzung) * regelMs("eine_minute_min") - jetzt) / regelMs("eine_minute_min")));
}

export function buendelText(abnahmen: Zeile[], fragen: number) {
  const n = abnahmen.length;
  const minuten = Math.round((n * regelZahl("buendel_abnahme_s")) / 60 + fragen * regelZahl("buendel_frage_min"));
  const projekte = [...new Set(abnahmen.map((a) => a.projekt ?? a.bereich).filter(Boolean))];
  const aus = projekte.length ? ` aus ${projekte.length > 1 ? `${projekte.slice(0, -1).join(", ")} und ${projekte.at(-1)}` : projekte[0]}` : "";
  const teile = [fragen ? `${fragen} ${fragen === 1 ? "Frage" : "Fragen"}` : "", n ? `${n} ${n === 1 ? "Abnahme" : "Abnahmen"}` : ""].filter(Boolean).join(" und ");
  if (!teile) return { dauer_min: 0, satz: null, kurz: null };
  return { dauer_min: minuten, satz: `${teile}${aus}, etwa ${minuten} Minuten.`, kurz: `${teile}, etwa ${minuten} Min` };
}

export function koerper(db: Register, tagBeginn: number, ruhe: { grund: string; bis: number } | undefined) {
  const k = JSON.parse(wert(db, "koerper")?.wert ?? "null");
  const s = JSON.parse(wert(db, "koerper:schlaf")?.wert ?? "null");
  const schlaf = s && s.bis >= tagBeginn ? s : null;
  if (!schlaf && (!k || k.zeit < tagBeginn)) return null;
  if (!k || k.zeit < tagBeginn) return { body_battery: null, schlaf };
  const morgens = JSON.parse(wert(db, "koerper:morgens")?.wert ?? "null");
  const training = letztesTraining(db, tagBeginn);
  return {
    ...k, morgens: morgens && morgens.zeit >= tagBeginn ? morgens.body_battery : null,
    titel: `Body Battery${training !== undefined && training < k.zeit ? " nach dem Training" : ""}`,
    hinweis: ruhe?.grund === "fokus" && k.body_battery >= regelZahl("koerper_schwer_ab")
      ? `Gute Zeit für Schweres bis ${stundeAlsWort(ruhe.bis)}. Danach legt Seneca dir Leichtes hin.` : null,
    schlaf,
  };
}
