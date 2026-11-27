import { ereignisse, fragen, hole, termineAm, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { letzteUhrzeit, msAusMinuten, naechsteUhrzeit, regelText, regelZahl } from "../regeln.ts";
import { anzeigeName } from "../team.ts";
import { istFokus } from "./planen.ts";
import { istSport } from "./kalender.ts";
import { uhrzeit, ZAHLWORT } from "./heute.ts";

const GERAET: Record<string, string> = { iphone: "am iPhone", mac: "am Mac", uhr: "an der Uhr", gespraech: "im Gespräch" };
const PARTIZIP: Record<string, string> = { Freigeben: "freigegeben", Senden: "gesendet", Anrufen: "angerufen" };
const SENDET: Record<string, [string, string]> = { nachricht: ["schickt es", "senden"], anruf: ["ruft an", "anrufen"], einladung: ["lädt ein", "einladen"] };
const ART: Record<string, [string, string, string]> = { text: ["ein", "Text", "Texte"], test: ["ein", "Test", "Tests"], hoerprobe: ["eine", "Hörprobe", "Hörproben"], bau: ["ein", "Bau", "Bauten"] };

type Option = { wert: string; text: string; folge: string; titel?: string; preis?: string; einheit?: string; knopf?: string };

export function fensterStart(jetzt: number): number {
  const heute = letzteUhrzeit(regelText("fenster"), jetzt);
  return jetzt < heute + msAusMinuten(regelZahl("fenster_dauer_min")) ? heute : naechsteUhrzeit(regelText("fenster"), jetzt);
}

function zahl(n: number, [artikel, eins, viele]: [string, string, string]): string {
  return n === 1 ? `${artikel} ${eins}` : `${ZAHLWORT[n] ?? n} ${viele}`;
}

function gross(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function optionenSicht(f: Zeile): { optionen: Option[]; folge: string | null } {
  const optionen = (JSON.parse(String(f.optionen)) as Option[]).map((o) => {
    const verb = SENDET[String(f.wirkung_aussen)]?.[1];
    return { ...o, knopf: o.titel && verb ? `${o.titel.split(" · ")[0]} ${verb}` : o.text };
  });
  const sendet = SENDET[String(f.wirkung_aussen)]?.[0];
  const s = regelZahl("rueckgaengig_s");
  return { optionen, folge: sendet ? `${anzeigeName(String(f.von))} ${sendet} nach ${ZAHLWORT[s] ?? s} Sekunden, in deinem Namen.` : null };
}

function entschiedenSicht(db: Register, f: Zeile) {
  const a = hole(db, "auftrag", String(f.auftrag_id));
  const o = (JSON.parse(String(f.optionen)) as Option[]).find((x) => x.wert === f.antwort);
  const text = o?.text ?? String(f.antwort);
  const titel = PARTIZIP[text] ? `${a.titel} ${PARTIZIP[text]}` : `${a.titel}: ${text}`;
  const wer = anzeigeName(String(a.verantwortlich));
  const folge = a.zustand === "erledigt" ? `${["pruefen", "test"].includes(String(a.arbeitsart)) ? "bestanden" : "fertig"} um ${uhrzeit(Number(a.geaendert))}`
    : a.zustand === "laeuft" ? `${wer} arbeitet daran` : a.zustand === "verworfen" ? "verworfen" : `${wer} plant es`;
  return { zeit: f.antwort_um, titel, unter: [GERAET[String(f.antwort_geraet)], folge].filter(Boolean).join(" · ") };
}

function abnahmeSicht(db: Register, a: Zeile) {
  const e = JSON.parse(String(a.ergebnis ?? "null")) ?? {};
  const pruefung = db.prepare("SELECT ergebnis FROM auftrag WHERE eltern_id = ? AND arbeitsart = 'pruefen' AND zustand = 'erledigt' ORDER BY geaendert DESC").get(String(a.id));
  const urteil = JSON.parse(String(pruefung?.ergebnis ?? "null"))?.satz;
  return { id: a.id, titel: a.titel, projekt: a.projekt ?? a.bereich, art: e.art ?? null, satz: [e.satz, urteil && `Prüfer: ${urteil}`].filter(Boolean).join(" ") || null,
    hoerprobe_s: e.hoerprobe_s ?? null, beleg: e.links?.[0] ?? null, an: anzeigeName(String(a.verantwortlich)) };
}

export function buendelFortschritt(db: Register, offen: Zeile[], jetzt: number) {
  const seit = fensterStart(jetzt);
  const handlungen = ereignisse(db, { art: "handlung", seit: Math.min(seit, jetzt) })
    .map((e) => JSON.parse(String(e.daten)) as { art: string; ziel: string; ergebnis: string })
    .filter((d) => d.ergebnis === "angenommen" && (d.art === "abnahme.passt" || d.art === "abnahme.nachbessern")).reverse();
  const fertig = [...new Map(handlungen.map((d) => [d.ziel, d])).values()].map((d) => ({ art: d.art, a: hole(db, "auftrag", d.ziel) }));
  const sortiert = [...offen].sort((x, y) => Number(x.naechster_anlass ?? 0) - Number(y.naechster_anlass ?? 0));
  const liste = sortiert.map((a) => abnahmeSicht(db, a));
  const rest = liste.slice(1);
  const arten = Object.keys(ART).map((k) => [k, rest.filter((r) => r.art === k).length] as const).filter(([, n]) => n);
  const gesamt = fertig.length + offen.length;
  const projekte = [...new Set([...fertig.map((f) => f.a), ...offen].map((a) => String(a.projekt ?? a.bereich)))];
  const aus = projekte.length > 1 ? `${projekte.slice(0, -1).join(", ")} und ${projekte.at(-1)}` : projekte[0];
  return { abnahmen: liste, fortschritt: {
    titel: gesamt ? `${gesamt} ${gesamt === 1 ? "Abnahme" : "Abnahmen"}${aus ? ` aus ${aus}` : ""}` : null,
    fertig: fertig.length, gesamt, rest_min: Math.round((offen.length * regelZahl("buendel_abnahme_s")) / 60),
    passt: fertig.filter((f) => f.art === "abnahme.passt").map((f) => String(f.a.titel)),
    zurueck: fertig.filter((f) => f.art === "abnahme.nachbessern").map((f) => `${f.a.titel} geht an ${anzeigeName(String(f.a.verantwortlich))} zurück`),
    danach: rest.length ? `Danach noch ${rest.length}${arten.length ? `: ${arten.map(([k, n]) => zahl(n, ART[k])).join(", ")}` : ""}.` : null,
  } };
}

export function entscheiden(db: Register, offeneFragen: number, buendel: boolean, tagBeginn: number, jetzt: number) {
  const start = fensterStart(jetzt);
  const ende = start + msAusMinuten(regelZahl("fenster_dauer_min"));
  const spaeter = termineAm(db, jetzt).filter((t) => !t.ganztag && !istFokus(t) && t.start >= Math.max(jetzt, ende));
  const arbeit = spaeter.filter((t) => !istSport(t.titel));
  const teile = [offeneFragen ? gross(zahl(offeneFragen, ["eine", "Frage", "Fragen"])) : "", buendel ? (offeneFragen ? "ein Bündel" : "Ein Bündel") : ""].filter(Boolean);
  const naechster = spaeter[0];
  const sport = naechster && istSport(naechster.titel);
  return {
    satz: teile.length ? [`${teile.join(", ")}.`, arbeit.length ? `Danach ${arbeit[0].titel} um ${uhrzeit(arbeit[0].start)}.` : "Dann ist der Tag frei."]
      : ["Nichts zu entscheiden.", "Der Tag gehört dir."],
    fenster: start, fenster_bis: ende,
    heute: fragen(db, "beantwortet").filter((f) => Number(f.antwort_um) >= tagBeginn).sort((a, b) => Number(a.antwort_um) - Number(b.antwort_um)).map((f) => entschiedenSicht(db, f)),
    danach: ["Nichts mehr bis morgen.", naechster ? `Um ${uhrzeit(naechster.start)} ${sport ? naechster.titel.split(" · ")[0] : naechster.titel}${sport ? ", Seneca schweigt." : "."}` : ""].filter(Boolean).join(" "),
  };
}
