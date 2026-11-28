import { ereignisse, fragen, hole, termineAm, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { letzteUhrzeit, msAusMinuten, naechsteUhrzeit, regelText, regelZahl } from "../regeln.ts";
import { anzeigeName } from "../team.ts";
import { istFokus } from "./planen.ts";
import { istSport } from "./kalender.ts";
import { uhrzeit, ZAHLWORT } from "./heute.ts";

export const GERAET: Record<string, string> = { iphone: "am iPhone", mac: "am Mac", uhr: "an der Uhr", gespraech: "im Gespräch" };
const PARTIZIP: Record<string, string> = { Freigeben: "freigegeben", Senden: "gesendet", Anrufen: "angerufen" };
const SENDET: Record<string, [string, string, string]> = { nachricht: ["schickt es", "", "senden"], anruf: ["ruft", " an", "anrufen"], einladung: ["lädt", " ein", "einladen"] };
const ART: Record<string, [string, string, string]> = { text: ["ein", "Text", "Texte"], test: ["ein", "Test", "Tests"], hoerprobe: ["eine", "Hörprobe", "Hörproben"], bau: ["ein", "Bau", "Bauten"] };

type Option = { wert: string; text: string; folge: string; titel?: string; preis?: string; einheit?: string; knopf?: string };

export function fensterStart(jetzt: number): number {
  const heute = letzteUhrzeit(regelText("fenster"), jetzt);
  return jetzt < heute + msAusMinuten(regelZahl("fenster_dauer_min")) ? heute : naechsteUhrzeit(regelText("fenster"), jetzt);
}

function zahl(n: number, [artikel, eins, viele]: [string, string, string]): string {
  return n === 1 ? `${artikel} ${eins}` : `${ZAHLWORT[n] ?? n} ${viele}`;
}

const gross = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

export function optionenSicht(f: Zeile): { optionen: Option[]; folge: string | null } {
  const optionen = (JSON.parse(String(f.optionen)) as Option[]).map((o) => {
    const verb = SENDET[String(f.wirkung_aussen)]?.[2];
    return { ...o, knopf: o.titel && verb ? `${o.titel.split(" · ")[0]} ${verb}` : o.text, quittung: o.titel?.split(" · ")[0] ?? gross(PARTIZIP[o.text] ?? o.text) };
  });
  const sendet = SENDET[String(f.wirkung_aussen)];
  const s = regelZahl("rueckgaengig_s");
  return { optionen, folge: sendet ? `${anzeigeName(String(f.von))} ${sendet[0]} nach ${ZAHLWORT[s] ?? s} Sekunden${sendet[1]}, in deinem Namen.` : null };
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
  const pruefung = db.prepare("SELECT ergebnis, geaendert FROM auftrag WHERE eltern_id = ? AND arbeitsart = 'pruefen' AND zustand = 'erledigt' ORDER BY geaendert DESC").get(String(a.id));
  const urteil = JSON.parse(String(pruefung?.ergebnis ?? "null"))?.satz;
  const { kursiv, transkript, geaendert, vorher, vorher_s, unterschied, dateien, folge, ergebnis } = e;
  return { id: a.id, titel: a.titel, projekt: a.projekt ?? a.bereich, art: e.art ?? null, satz: [e.satz, urteil && `Prüfer: ${urteil}`].filter(Boolean).join(" ") || null,
    hoerprobe_s: e.hoerprobe_s ?? null, beleg: e.links?.[0] ?? null, an: anzeigeName(String(a.verantwortlich)), art_name: ART[e.art]?.[1] ?? null,
    pruefer: urteil ?? null, geprueft: pruefung?.geaendert ?? null, kursiv, transkript, geaendert, vorher, vorher_s, unterschied, dateien, folge, ergebnis };
}

function zaehlen<T>(liste: T[], schluessel: (x: T) => string): [string, number][] {
  return [...liste.reduce((m, x) => m.set(schluessel(x), (m.get(schluessel(x)) ?? 0) + 1), new Map<string, number>())];
}

export function buendelFortschritt(db: Register, offen: Zeile[], jetzt: number) {
  const seit = fensterStart(jetzt);
  const handlungen = ereignisse(db, { art: "handlung", seit: Math.min(seit, jetzt) })
    .map((e) => ({ ...(JSON.parse(String(e.daten)) as { art: string; ziel: string; ergebnis: string }), zeit: Number(e.zeit) }))
    .filter((d) => d.ergebnis === "angenommen" && (d.art === "abnahme.passt" || d.art === "abnahme.nachbessern")).reverse();
  const fertig = [...new Map(handlungen.map((d) => [d.ziel, d])).values()].map((d) => ({ art: d.art, a: hole(db, "auftrag", d.ziel) }));
  const sortiert = [...offen].sort((x, y) => Number(x.naechster_anlass ?? 0) - Number(y.naechster_anlass ?? 0));
  const liste = sortiert.map((a) => abnahmeSicht(db, a));
  const rest = liste.slice(1);
  const arten = (l: { art: string | null }[]) => Object.keys(ART).map((k) => [k, l.filter((r) => r.art === k).length] as const).filter(([, n]) => n).map(([k, n]) => zahl(n, ART[k]));
  const gesamt = fertig.length + offen.length;
  const alle = [...fertig.map((f) => ({ a: f.a, zustand: f.art === "abnahme.passt" ? "passt" : "zurueck" })), ...sortiert.map((a) => ({ a, zustand: "offen" }))];
  const projekte = [...new Set(alle.map(({ a }) => String(a.projekt ?? a.bereich)))];
  const aus = projekte.length > 1 ? `${projekte.slice(0, -1).join(", ")} und ${projekte.at(-1)}` : projekte[0];
  const wort = (n: number) => ZAHLWORT[n] ?? String(n);
  const minuten = (n: number) => Math.max(1, Math.round((n * regelZahl("buendel_abnahme_s")) / 60));
  const dauer = handlungen.length ? Math.max(1, Math.round((handlungen.at(-1)!.zeit - handlungen[0].zeit) / 60000)) : 0;
  const s = regelZahl("rueckgaengig_s");
  return { abnahmen: liste, fortschritt: {
    titel: gesamt ? `${gesamt} ${gesamt === 1 ? "Abnahme" : "Abnahmen"}${aus ? ` aus ${aus}` : ""}` : null,
    fertig: fertig.length, gesamt, rest_min: Math.round((offen.length * regelZahl("buendel_abnahme_s")) / 60),
    passt: fertig.filter((f) => f.art === "abnahme.passt").map((f) => String(f.a.titel)),
    zurueck: fertig.filter((f) => f.art === "abnahme.nachbessern").map((f) => `${f.a.titel} geht an ${anzeigeName(String(f.a.verantwortlich))} zurück`),
    danach: rest.length ? `Danach noch ${rest.length}${arten(rest).length ? `: ${arten(rest).join(", ")}` : ""}.` : null,
    liste: alle.map(({ a, zustand }) => ({ id: a.id, titel: a.titel, zustand, unter: [a.projekt ?? a.bereich, ART[JSON.parse(String(a.ergebnis ?? "null"))?.art]?.[1],
      zustand === "zurueck" ? `an ${anzeigeName(String(a.verantwortlich))}` : null].filter(Boolean).join(" · ") })),
    anzahl: gesamt ? `${gross(wort(gesamt))} ${gesamt === 1 ? "Abnahme" : "Abnahmen"}` : null,
    zaehlung: zaehlen(alle, ({ a }) => String(a.projekt ?? a.bereich)).map(([p, n]) => `${p} ${n}`).join(" · "),
    start: gesamt ? [`${gross(wort(gesamt))} ${gesamt === 1 ? "Abnahme" : "Abnahmen"},`, `etwa ${minuten(gesamt) === 1 ? "eine Minute" : `${wort(minuten(gesamt))} Minuten`}.`] : null,
    arten: arten(alle.map(({ a }) => ({ art: JSON.parse(String(a.ergebnis ?? "null"))?.art ?? null }))).join(" · "),
    pause: gesamt ? [`Pause bei ${fertig.length + 1}`, `von ${gesamt}.`] : null,
    pause_satz: `Das Fenster bleibt bis ${uhrzeit(seit + msAusMinuten(regelZahl("fenster_dauer_min")))} offen. Danach wandert der Rest ins Fenster von morgen.`,
    abschluss: !offen.length && fertig.length ? [`${gross(wort(gesamt))} durch,`, dauer === 1 ? "in einer Minute." : `in ${wort(dauer)} Minuten.`] : null,
    rueckgaengig: `${gross(wort(s))} Sekunden Rückgängig, dann die nächste.`,
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
  const um = naechster ? `Um ${uhrzeit(naechster.start)} ${sport ? naechster.titel.split(" · ")[0] : naechster.titel}` : "";
  return {
    satz: teile.length ? [`${teile.join(", ")}.`, arbeit.length ? `Danach ${arbeit[0].titel} um ${uhrzeit(arbeit[0].start)}.` : "Dann ist der Tag frei."]
      : ["Nichts zu entscheiden.", "Der Tag gehört dir."],
    fenster: start, fenster_bis: ende,
    heute: fragen(db, "beantwortet").filter((f) => Number(f.antwort_um) >= tagBeginn).sort((a, b) => Number(a.antwort_um) - Number(b.antwort_um)).map((f) => entschiedenSicht(db, f)),
    danach: ["Nichts mehr bis morgen.", naechster ? `${um}${sport ? ", Seneca schweigt." : "."}` : ""].filter(Boolean).join(" "),
    danach_kurz: ["Nichts mehr bis morgen.", naechster ? `${um}.` : ""].filter(Boolean).join(" "),
  };
}
