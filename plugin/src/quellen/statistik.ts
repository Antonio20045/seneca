import { eintraegeSeit, ereignisse, termineAm, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { lebensbereich, letzteUhrzeit, regelListe, regelMs, regelText, regelZahl } from "../regeln.ts";

const TAG = ["M", "D", "M", "D", "F", "S", "S"];
const KURZ = ["MO", "DI", "MI", "DO", "FR", "SA", "SO"];
const MINUTEN = { 15: "eine Viertelstunde", 30: "eine halbe Stunde", 45: "eine Dreiviertelstunde", 60: "eine Stunde" } as Record<number, string>;
const MON = ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"], WORT = ["null", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"];
const WDH = { 5: "Fünfer", 6: "Sechser", 8: "Achter", 10: "Zehner", 12: "Zwölfer" } as Record<number, string>;
const TEILE: [number, string][] = [[1 / 4, "ein Viertel"], [1 / 3, "ein Drittel"], [2 / 5, "zwei Fünftel"], [1 / 2, "die Hälfte"], [3 / 5, "drei Fünftel"], [2 / 3, "zwei Drittel"], [3 / 4, "drei Viertel"], [1, "alles"]];

type Eintrag = { id: string; art: string; zeit: number; w: Record<string, unknown> };

const zahl = (n: number, stellen = 0) => n.toLocaleString("de-DE", { minimumFractionDigits: stellen, maximumFractionDigits: stellen });
const zwei = (n: number) => String(Math.floor(n)).padStart(2, "0");
const dauer = (s: number) => s >= 3600 ? `${Math.floor(s / 3600)}:${zwei((s % 3600) / 60)}:${zwei(Math.round(s % 60))}` : `${Math.floor(s / 60)}:${zwei(Math.round(s % 60))}`;
const datum = (t: number, f: Intl.DateTimeFormatOptions) => new Date(t).toLocaleDateString("de-DE", f);
const lesen = (e: Zeile): Eintrag => ({ id: String(e.id), art: String(e.art), zeit: Number(e.zeit), w: JSON.parse(String(e.werte)) });
const ziel = (db: Register, art: string, bis = Infinity) => Number(JSON.parse(String(ereignisse(db, { art: "wert.gesetzt", schluessel: `ziel:${art}` }).find((e) => Number(e.zeit) < bis)?.daten ?? "{}")).wert ?? 0);
const tagVon = (t: number) => letzteUhrzeit(regelText("tag_grenze"), t);
const kgText = (n: number) => zahl(n, n % 1 ? 1 : 0), kurz = (t: number) => `${KURZ[(new Date(t).getDay() + 6) % 7]} ${new Date(t).getDate()}. ${MON[new Date(t).getMonth()]}`;
const stunden = (m: number) => `${Math.floor(m / 60)}:${zwei(m % 60)}`;
const minus = (n: number) => (n > 0 ? "+" : "") + zahl(n, 1).replace("-", "−"), gross = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const alle = (db: Register, art: string) => eintraegeSeit(db, 0).map(lesen).filter((x) => x.art === art);
const km = (e: Eintrag[]) => e.filter((x) => x.art === "lauf").reduce((s, x) => s + Number(x.w.km ?? 0), 0);

function wochenBeginn(jetzt: number): number {
  const heute = letzteUhrzeit(regelText("tag_grenze"), jetzt);
  return heute - ((new Date(heute).getDay() + 6) % 7) * regelMs("ein_tag_tage");
}

function karte(e: Eintrag[], art: string[], montag: number, heute: number, w = (_: Eintrag) => 1, voll = 1) {
  return TAG.map((t, i) => {
    const von = montag + i * regelMs("ein_tag_tage");
    const s = e.filter((x) => art.includes(x.art) && x.zeit >= von && x.zeit < von + regelMs("ein_tag_tage")).map(w), wert = art[0] === "gewicht" ? s.at(-1) : s.reduce((a, b) => a + b, 0);
    return { t, zustand: s.length ? "da" : von <= heute ? "leer" : "kommt", heute: von === heute, wert: s.length ? wert : null, hoehe: s.length ? Math.min(1, Number(wert) / voll) : null };
  });
}

export function woche(db: Register, jetzt: number) {
  const montag = wochenBeginn(jetzt), heute = letzteUhrzeit(regelText("tag_grenze"), jetzt), sonntag = montag + 6 * regelMs("ein_tag_tage");
  const e = eintraegeSeit(db, montag).map(lesen);
  const heuteE = e.filter((x) => x.zeit >= heute);
  const lauf = km(e), lauZiel = ziel(db, "laufen_km"), lesMin = e.filter((x) => x.art === "lesen").reduce((s, x) => s + Number(x.w.m ?? 0), 0);
  const lesHeute = heuteE.filter((x) => x.art === "lesen").reduce((s, x) => s + Number(x.w.m ?? 0), 0), lesZiel = ziel(db, "lesen_min");
  const kraftTage = karte(e, ["satz", "training"], montag, heute).filter((t) => t.zustand === "da").length, kraftZiel = ziel(db, "kraft_mal");
  const gewicht = e.filter((x) => x.art === "gewicht");
  const zuletzt = [...e].reverse().find((x) => x.art === "lesen" && x.w.b), buch = zuletzt?.w.b, lesWert = `${Math.floor(lesMin / 60)}:${zwei(lesMin % 60)}`;
  const sport = termineAm(db, jetzt).find((t) => !t.ganztag && t.start > jetzt && regelListe("sport_worte").some((w) => t.titel.toLowerCase().includes(w.toLowerCase())));
  const letzter = sport && eintraegeSeit(db, 0).map(lesen).reverse().find((x) => x.art === "lauf" && x.w.name === sport.titel);
  const schafft = lauZiel && lauf < lauZiel && letzter && lauf + Number(letzter.w.km ?? 0) >= lauZiel;
  const gut = [lauZiel && lauf >= lauZiel / 2, kraftZiel && kraftTage >= kraftZiel / 2, lesZiel && lesMin >= (lesZiel * 7) / 2].filter(Boolean).length >= 2;
  return {
    kopf: `Woche ${kalenderwoche(montag)} · ${datum(montag, { day: "numeric" })}. bis ${datum(sonntag, { day: "numeric", month: "long" })}`,
    satz: [gut ? "Eine gute Woche." : "Eine ruhige Woche.", schafft ? `Mit dem ${sport.titel} heute Abend ist das Laufziel geschafft.` : lauZiel && lauf >= lauZiel ? "Das Laufziel ist geschafft." : ""].filter(Boolean),
    karten: [
      { art: "laufen", titel: "Laufen", wert: zahl(lauf, 1), einheit: "KM", tage: karte(e, ["lauf"], montag, heute, (x) => Number(x.w.km ?? 0), regelZahl("stat_balken_km")), anteil: lauZiel ? lauf / lauZiel : null, rechts: lauZiel ? `VON ${zahl(lauZiel)} KM` : "", knopf: "+" },
      { art: "lesen", titel: "Lesen", buch, wert: lesWert, einheit: "STD",
        unter: [zuletzt?.w.s && zuletzt.w.von ? `SEITE ${zuletzt.w.s} VON ${zuletzt.w.von}` : "", `DIESE WOCHE ${lesWert} STD`].filter(Boolean).join(" · "), tage: karte(e, ["lesen"], montag, heute, (x) => Number(x.w.m ?? 0), regelZahl("stat_balken_min")),
        anteil: lesZiel ? lesHeute / lesZiel : null, rechts: lesZiel ? `HEUTE ${lesHeute} VON ${lesZiel}` : "", knopf: lesZiel ? `+ ${lesZiel}` : "+" },
      { art: "kraft", titel: "Krafttraining", wert: String(kraftTage), einheit: kraftZiel ? `VON ${kraftZiel}` : "MAL", tage: karte(e, ["satz", "training"], montag, heute, (x) => Number(x.art === "satz"), regelZahl("stat_balken_saetze")),
        anteil: kraftZiel ? kraftTage / kraftZiel : null, rechts: `${heuteE.filter((x) => x.art === "satz").length} SÄTZE HEUTE`, knopf: "Starten" },
      gewicht.length ? { art: "gewicht", titel: "Gewicht", wert: zahl(Number(gewicht.at(-1)?.w.kg), 1), einheit: "KG", tage: karte(e, ["gewicht"], montag, heute, (x) => Number(x.w.kg)), anteil: null,
        rechts: `${zahl(Number(gewicht.at(-1)?.w.kg) - Number(gewicht[0].w.kg), 1).replace("-", "−")} SEIT ${KURZ[(new Date(gewicht[0].zeit).getDay() + 6) % 7]}`, knopf: "+" } : null,
    ].map((k) => k && { ...k, bereich: lebensbereich(k.titel) }).filter(Boolean),
    hinweis: lesZiel && lesHeute < lesZiel ? `Für Wachstum steht heute noch Lesen an.${sport ? ` Nach dem ${sport.titel} passt ${MINUTEN[lesZiel - lesHeute] ?? `${lesZiel - lesHeute} Minuten`}.` : ""}` : null,
  };
}

function kalenderwoche(t: number): number {
  const d = new Date(t); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
  const w1 = new Date(d.getFullYear(), 0, 4);
  return 1 + Math.round(((d.getTime() - w1.getTime()) / regelMs("ein_tag_tage") - 3 + ((w1.getDay() + 6) % 7)) / 7);
}

export function lauf(db: Register, id?: string) {
  const alle = eintraegeSeit(db, 0).map(lesen).filter((x) => x.art === "lauf");
  const l = id ? alle.find((x) => x.id === id) : alle.at(-1); if (!l) return null;
  const sp = id ? eintraegeSeit(db, l.zeit - 120_000).filter((e) => e.art === "laufspur" && Math.abs(Number(e.zeit) - l.zeit) < 120_000).sort((a, b) => Number(a.quelle === "garmin") - Number(b.quelle === "garmin")).at(-1) : undefined, spur = sp ? JSON.parse(String(sp.werte)) : null;
  const w = l.w, s = (w.km_s as number[] | undefined) ?? [], name = String(w.name ?? "Lauf");
  const lo = Math.min(...s), hi = Math.max(...s), best = s.indexOf(lo);
  const frueher = alle.filter((x) => x.zeit < l.zeit && x.w.name === w.name && ((x.w.km_s as number[] | undefined) ?? []).length);
  const schneller = frueher.reverse().findIndex((x) => Math.min(...(x.w.km_s as number[])) <= lo);
  const seit = schneller === -1 ? null : frueher[schneller].zeit;
  const wo = km(eintraegeSeit(db, wochenBeginn(l.zeit)).map(lesen).filter((x) => x.zeit <= l.zeit + 1)), z = ziel(db, "laufen_km", wochenBeginn(l.zeit) + 7 * regelMs("ein_tag_tage"));
  return {
    id: l.id, spur, kopf: `LAUFEN · ${datum(l.zeit, { weekday: "long" }).toUpperCase()}, ${new Date(l.zeit).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" })}`,
    satz: [`${w.titel ?? name}.`, s.length > 2 && best === s.length - 1 ? "Der letzte Kilometer war dein schnellster." : s.length > 2 && best === 0 ? "Der erste Kilometer war dein schnellster." : ""].filter(Boolean),
    werte: [[`${zahl(Number(w.km), 1)} km`, "Strecke"], [dauer(Number(w.dauer_s)), "Zeit"], [dauer(Number(w.dauer_s) / Number(w.km)), "pro km"],
      w.hm ? [`${zahl(Number(w.hm))} m`, "bergauf"] : null, w.puls ? [zahl(Number(w.puls)), "Puls Ø"] : null, w.zone ? [String(w.zone), "meist"] : null].filter(Boolean),
    km: s.map((x, i) => ({ nr: i + 1, zeit: dauer(x), anteil: hi > lo ? 0.94 - 0.72 * (x - lo) / (hi - lo) : 0.94, schnellste: i === best })),
    bestwert: s.length && frueher.length && schneller !== 0 ? `Schnellster ${name}-Kilometer ${seit ? `seit ${datum(seit, { month: "long" })}` : "bisher"}: ${dauer(lo)}` : null,
    woche: z ? `Damit ${zahl(wo, 1)} km diese Woche, ${wo >= z ? `das Ziel von ${zahl(z)} km ist geschafft` : `noch ${zahl(z - wo, 1)} km bis zum Ziel von ${zahl(z)} km`}.` : null,
  };
}

function bewegung(e: Eintrag[]) {
  const m = new Map<number, number>(); for (const x of e) if (["lauf", "satz", "training"].includes(x.art)) m.set(tagVon(x.zeit), (m.get(tagVon(x.zeit)) ?? 0) | (x.art !== "lauf" ? 2 : Number(x.w.km) >= regelZahl("stat_lang_km") ? 3 : 1));
  return (t: number) => [0, 1, 1, 2][m.get(tagVon(t)) ?? 0];
}

function summen(e: Eintrag[], seit: (t: number) => string) {
  const l = e.filter((x) => x.art === "lauf"), les = e.filter((x) => x.art === "lesen"), g = e.filter((x) => x.art === "gewicht");
  const buecher = new Set(les.map((x) => x.w.b).filter(Boolean)).size; return [[zahl(km(e)), "KM", `Laufen, ${l.length} ${l.length === 1 ? "Lauf" : "Läufe"}`],
    [String(new Set(e.filter((x) => x.art === "satz" || x.art === "training").map((x) => tagVon(x.zeit))).size), "MAL", "Krafttraining"],
    [zahl(les.reduce((s, x) => s + Number(x.w.m ?? 0), 0) / 60), "STD", `Lesen, ${buecher} ${buecher === 1 ? "Buch" : "Bücher"}`],
    g.length > 1 ? [minus(Number(g.at(-1)?.w.kg) - Number(g[0].w.kg)), "KG", `Gewicht seit ${seit(g[0].zeit)}`] : null].filter(Boolean);
}

function guteWochen(e: Eintrag[], bis: number) {
  const tage = bewegung(e), ziel = regelZahl("stat_gute_woche_mal"), w: [number, boolean][] = [];
  for (let m = wochenBeginn(bis) - 7 * regelMs("ein_tag_tage"); m >= (e[0]?.zeit ?? bis); m -= 7 * regelMs("ein_tag_tage"))
    w.unshift([m, Array.from({ length: 7 }, (_, i) => tage(m + i * regelMs("ein_tag_tage") + 1)).filter(Boolean).length >= ziel]);
  const bruch = w.findLastIndex((x, i) => i > 0 && !x[1] && !w[i - 1][1]), ab = w.findIndex((x, i) => i > bruch && x[1]);
  if (ab === -1 || w.length - ab < 8) return ""; const jz = ["dem Winter", "dem Frühling", "dem Sommer", "dem Herbst"][Math.floor(((new Date(w[ab][0]).getMonth() + 1) % 12) / 3)];
  return `Seit ${jz} ${w.slice(ab).every((x) => x[1]) ? "" : "fast "}jede Woche ${WORT[ziel] ?? ziel} Trainings.`;
}

export function jahr(db: Register, jetzt: number) {
  const j = new Date(jetzt).getFullYear(), e = eintraegeSeit(db, new Date(j, 0, 1).getTime()).map(lesen), tage = bewegung(e), heute = tagVon(jetzt);
  const raster = Array.from({ length: 12 }, (_, m) => Array.from({ length: new Date(j, m + 1, 0).getDate() }, (_, d) => {
    const t = new Date(j, m, d + 1, 12).getTime(); return tagVon(t) > heute ? " " : tagVon(t) === heute ? `h${tage(t)}` : String(tage(t));
  }));
  const l = e.filter((x) => x.art === "lauf").sort((a, b) => Number(b.w.km) - Number(a.w.km))[0], les = e.filter((x) => x.art === "lesen").sort((a, b) => Number(b.w.m) - Number(a.w.m))[0];
  const saetze = e.filter((x) => x.art === "satz" && x.w.u), u = [...new Set(saetze.map((x) => x.w.u))].sort((a, b) => saetze.filter((x) => x.w.u === b).length - saetze.filter((x) => x.w.u === a).length)[0];
  const best = saetze.filter((x) => x.w.u === u).sort((a, b) => Number(b.w.kg) - Number(a.w.kg) || Number(b.w.w) - Number(a.w.w) || a.zeit - b.zeit)[0];
  const tageImJahr = new Set(e.filter((x) => ["lauf", "satz", "training"].includes(x.art)).map((x) => tagVon(x.zeit))).size; return {
    kopf: `Bis ${datum(jetzt, { weekday: "long", day: "numeric", month: "long" })}`, raster,
    satz: [tageImJahr / Math.max(1, (jetzt - new Date(j, 0, 1).getTime()) / (7 * regelMs("ein_tag_tage"))) >= 2 ? "Ein bewegtes Jahr." : "Ein ruhiges Jahr.", guteWochen(e, jetzt)].filter(Boolean),
    zahlen: summen(e, (t) => datum(t, { month: "long" })),
    bestwerte: [l ? ["Längster Lauf", `${zahl(Number(l.w.km), 1)} km`, `${new Date(l.zeit).getDate()}. ${MON[new Date(l.zeit).getMonth()]}`] : null,
      best ? [String(u), `${kgText(Number(best.w.kg))} kg × ${best.w.w}`, `${new Date(best.zeit).getDate()}. ${MON[new Date(best.zeit).getMonth()]}`] : null,
      les ? ["Am Stück gelesen", Number(les.w.m) >= 60 ? `${stunden(Number(les.w.m))} Std` : `${les.w.m} Min`, `${new Date(les.zeit).getDate()}. ${MON[new Date(les.zeit).getMonth()]}`] : null].filter(Boolean),
  };
}

export function monat(db: Register, jetzt: number) {
  const d = new Date(jetzt), von = new Date(d.getFullYear(), d.getMonth(), 1).getTime(), e = eintraegeSeit(db, von).map(lesen), tage = bewegung(e), heute = tagVon(jetzt);
  const raster: string[][] = []; for (let m = wochenBeginn(von + regelMs("ein_tag_tage")); new Date(m).getMonth() === d.getMonth() || m < von; m += 7 * regelMs("ein_tag_tage"))
    raster.push(Array.from({ length: 7 }, (_, i) => { const t = m + i * regelMs("ein_tag_tage") + 1; return new Date(t).getMonth() !== d.getMonth() ? "" : t > heute + regelMs("ein_tag_tage") ? " " : tagVon(t) === heute ? `h${tage(t)}` : String(tage(t)); }));
  const n = new Set(e.filter((x) => ["lauf", "satz", "training"].includes(x.art)).map((x) => tagVon(x.zeit))).size; return { kopf: `${gross(datum(jetzt, { month: "long" }))} ${d.getFullYear()} · bis ${datum(jetzt, { day: "numeric" })}.`, raster,
    satz: [`${n >= d.getDate() / 3.5 ? "Ein bewegter" : "Ein ruhiger"} ${datum(jetzt, { month: "long" })}.`, `${gross(WORT[n] ?? String(n))} ${n === 1 ? "Tag" : "Tage"} mit Training.`],
    zahlen: summen(e, (t) => `dem ${datum(t, { day: "numeric" })}.`) };
}

export function tag(db: Register, jetzt: number) {
  const e = eintraegeSeit(db, tagVon(jetzt)).map(lesen), zeit = (t: number) => new Date(t).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" }),
    uebungen = [...new Set(e.filter((x) => x.art === "satz").map((x) => String(x.w.u ?? "Satz")))];
  const zeilen = [...e.filter((x) => ["lauf", "lesen", "gewicht", "training"].includes(x.art)).map((x) => ({ id: x.id, zeit: x.zeit, titel: x.art === "lauf" ? String(x.w.titel ?? "Lauf") : x.art === "lesen" ? String(x.w.b ?? "Lesen") : x.art === "gewicht" ? "Gewicht" : "Krafttraining",
      wert: x.art === "lauf" ? `${zahl(Number(x.w.km), 1)} km` : x.art === "lesen" ? `${x.w.m} Min` : x.art === "gewicht" ? `${zahl(Number(x.w.kg), 1)} kg` : `${x.w.s ?? ""} Sätze` })),
    ...uebungen.map((u) => { const s = e.filter((x) => x.art === "satz" && String(x.w.u ?? "Satz") === u); return { zeit: s[0].zeit, titel: u, wert: `${s.length} ${s.length === 1 ? "Satz" : "Sätze"}` }; })]
    .sort((a, b) => a.zeit - b.zeit).map((z) => [zeit(z.zeit), z.titel, z.wert, "id" in z ? z.id : ""]);
  return { kopf: datum(jetzt, { weekday: "long", day: "numeric", month: "long" }), satz: [zeilen.length ? `Heute ${WORT[zeilen.length] ?? zeilen.length} ${zeilen.length === 1 ? "Eintrag" : "Einträge"}.` : "Heute noch nichts eingetragen."], zeilen };
}

export function uebung(db: Register, jetzt: number, name?: string) {
  const s = alle(db, "satz").filter((x) => x.w.u && x.w.kg != null), u = name ?? s.at(-1)?.w.u;
  if (!u) return null; const tage = [...Map.groupBy(s.filter((x) => x.w.u === u), (x) => tagVon(x.zeit)).values()].map((ss) => {
    const kg = Math.max(...ss.map((x) => Number(x.w.kg))); return { zeit: ss[0].zeit, kg, w: ss.filter((x) => Number(x.w.kg) === kg).map((x) => Number(x.w.w)) };
  });
  const voll = (t: (typeof tage)[number]) => t.w.length >= 3 && t.w.every((w) => w === t.w[0]) && t.w[0] >= regelZahl("kraft_volle_wdh") ? `${WORT[t.w.length]} volle ${WDH[t.w[0]] ?? `${t.w[0]}er`}` : "";
  const woche = (m: number) => tage.filter((t) => t.zeit >= m && t.zeit < m + 7 * regelMs("ein_tag_tage")).sort((a, b) => b.kg - a.kg || Math.max(...b.w) - Math.max(...a.w))[0];
  const wochen = Array.from({ length: 52 }, (_, i) => wochenBeginn(jetzt) - (51 - i) * 7 * regelMs("ein_tag_tage")).map((m) => { const b = woche(m); return { w: `W${kalenderwoche(m)}`, kg: b?.kg ?? null, wdh: b ? Math.max(...b.w) : null, monat: MON[new Date(m + 3 * regelMs("ein_tag_tage")).getMonth()] }; });
  const acht = wochen.slice(-8).filter((w) => w.kg != null), erste = wochen.findIndex((w, i) => i >= 44 && w.kg != null), diff = Number(acht.at(-1)?.kg) - Number(acht[0]?.kg), kilo = Math.abs(diff) <= 12 && diff % 0.5 === 0 ? `${diff % 1 ? (Math.floor(Math.abs(diff)) === 1 ? "ein" : WORT[Math.floor(Math.abs(diff))]) + "einhalb" : WORT[Math.abs(diff)]} Kilo` : `${kgText(Math.abs(diff))} Kilo`;
  const l = tage.at(-1), vorschlag = l && voll(l); return {
    titel: `${u}.`, wochen, satz: acht.length > 1 && diff ? `Seit ${datum(wochenBeginn(jetzt) - (51 - erste) * 7 * regelMs("ein_tag_tage") + 3 * regelMs("ein_tag_tage"), { month: "long" })} ${kilo} ${diff > 0 ? "mehr" : "weniger"}.` : "",
    zeilen: tage.slice(-4).reverse().map((t) => { const neu = tage.some((v) => v.zeit < t.zeit) && tage.filter((v) => v.zeit < t.zeit).every((v) => v.kg < t.kg);
      const besser = tage.filter((v) => v.zeit < t.zeit && (v.kg > t.kg || (v.kg === t.kg && Math.max(...v.w) >= Math.max(...t.w)))).at(-1);
      return [tagVon(t.zeit) === tagVon(jetzt) ? `HEUTE ${new Date(t.zeit).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" })}` : kurz(t.zeit), `${kgText(t.kg)} kg × ${t.w.join(" · ")}`,
        neu ? `erstmals ${kgText(t.kg)} kg` : t === l ? [voll(t), besser ? `Bestwert seit ${datum(besser.zeit, { weekday: "long" })}` : ""].filter(Boolean).join(". ") : "", neu];
    }),
    hinweis: vorschlag && l ? `${gross(vorschlag)}. Nächstes Mal ${kgText(l.kg + regelZahl("kraft_schritt_kg"))} kg im ersten Satz? Die Uhr schlägt es dann vor.` : null,
    uhr: l ? [u, u, vorschlag ? l.kg + regelZahl("kraft_schritt_kg") : l.kg, l.w[0]] : null,
  };
}

export function buch(db: Register, jetzt: number, name?: string) {
  const les = alle(db, "lesen"), b = name ?? [...les].reverse().find((x) => x.w.b)?.w.b;
  if (!b) return null; const e = les.filter((x) => x.w.b === b), mit = e.filter((x) => x.w.s), z = ziel(db, "lesen_min") || 30, l = mit.at(-1), von = Number(l?.w.von ?? 0), s = Number(l?.w.s ?? 0);
  const paare = mit.slice(1).map((x, i) => [Number(x.w.s) - Number(mit[i].w.s), Number(x.w.m)]), tempo = paare.length ? (paare.reduce((a, p) => a + p[0], 0) / paare.reduce((a, p) => a + p[1], 0)) * z : 0;
  const teil = TEILE.reduce((a, t) => (Math.abs(t[0] - s / von) < Math.abs(a[0] - s / von) ? t : a)), woche = eintraegeSeit(db, wochenBeginn(jetzt)).map(lesen).filter((x) => x.art === "lesen");
  const notiz = alle(db, "notiz").filter((x) => x.w.b === b).at(-1), heute = woche.filter((x) => x.zeit >= tagVon(jetzt)).reduce((a, x) => a + Number(x.w.m ?? 0), 0); return {
    titel: `${b}.`, kopf: `LESEN · SEIT ${datum(e[0].zeit, { day: "numeric", month: "long" }).toUpperCase()}`, anteil: von ? s / von : null, seite: von ? `SEITE ${s} VON ${von}` : null, prozent: von ? `${Math.round((100 * s) / von)} %` : null,
    satz: von ? `${Math.abs(teil[0] - s / von) < 0.005 ? "" : teil[0] < s / von ? "Gut " : "Knapp "}${teil[1]} gelesen.`.replace(/^(.)/, (c) => c.toUpperCase()) : "",
    prognose: tempo && von > s ? `Bei ${{ 15: "einer Viertelstunde", 30: "einer halben Stunde", 45: "einer Dreiviertelstunde", 60: "einer Stunde" }[z] ?? `${z} Minuten`} am Tag bist du um den ${datum(tagVon(jetzt) + Math.ceil((von - s) / Math.round(tempo)) * regelMs("ein_tag_tage"), { day: "numeric", month: "long" })} durch.` : null,
    zahlen: [[stunden(woche.reduce((a, x) => a + Number(x.w.m ?? 0), 0)), "STD", "diese Woche"], [String(heute), `VON ${z}`, "heute"], tempo ? [String(Math.round(tempo)), `S. / ${z} MIN`, "dein Tempo"] : null].filter(Boolean),
    zuletzt: e.slice(-2).reverse().map((x) => { const i = mit.indexOf(x); return [kurz(x.zeit), `${x.w.m} Min`, i > 0 ? `Seite ${mit[i - 1].w.s} bis ${x.w.s}` : x.w.s ? `bis Seite ${x.w.s}` : ""]; }),
    uhr: { b, h: heute, z }, notiz: notiz ? { kopf: `DEINE NOTIZ${notiz.w.s ? ` · S. ${notiz.w.s}` : ""} · ${kurz(notiz.zeit)}`, text: String(notiz.w.t) } : null,
  };
}

export function mitBereich(k: { statistiken?: { titel: string; grund?: string; bereich?: string }[] } | null) {
  return k && { ...k, statistiken: (k.statistiken ?? []).map((s) => ({ ...s, bereich: lebensbereich(`${s.titel} ${s.grund ?? ""}`, s.bereich) })) };
}
