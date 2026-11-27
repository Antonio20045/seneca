import { eintraegeSeit, termineAm, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { letzteUhrzeit, regelListe, regelMs, regelText } from "../regeln.ts";

const TAG = ["M", "D", "M", "D", "F", "S", "S"];
const KURZ = ["MO", "DI", "MI", "DO", "FR", "SA", "SO"];
const MINUTEN = { 15: "eine Viertelstunde", 30: "eine halbe Stunde", 45: "eine Dreiviertelstunde", 60: "eine Stunde" } as Record<number, string>;

type Eintrag = { id: string; art: string; zeit: number; w: Record<string, unknown> };

const zahl = (n: number, stellen = 0) => n.toLocaleString("de-DE", { minimumFractionDigits: stellen, maximumFractionDigits: stellen });
const zwei = (n: number) => String(Math.floor(n)).padStart(2, "0");
const dauer = (s: number) => s >= 3600 ? `${Math.floor(s / 3600)}:${zwei((s % 3600) / 60)}:${zwei(Math.round(s % 60))}` : `${Math.floor(s / 60)}:${zwei(Math.round(s % 60))}`;
const datum = (t: number, f: Intl.DateTimeFormatOptions) => new Date(t).toLocaleDateString("de-DE", f);
const lesen = (e: Zeile): Eintrag => ({ id: String(e.id), art: String(e.art), zeit: Number(e.zeit), w: JSON.parse(String(e.werte)) });
const ziel = (db: Register, art: string) => Number(wert(db, `ziel:${art}`)?.wert ?? 0);
const km = (e: Eintrag[]) => e.filter((x) => x.art === "lauf").reduce((s, x) => s + Number(x.w.km ?? 0), 0);

function wochenBeginn(jetzt: number): number {
  const heute = letzteUhrzeit(regelText("tag_grenze"), jetzt);
  return heute - ((new Date(heute).getDay() + 6) % 7) * regelMs("ein_tag_tage");
}

function karte(e: Eintrag[], art: string[], montag: number, heute: number) {
  return TAG.map((t, i) => {
    const von = montag + i * regelMs("ein_tag_tage");
    const da = e.some((x) => art.includes(x.art) && x.zeit >= von && x.zeit < von + regelMs("ein_tag_tage"));
    return { t, zustand: da ? "da" : von <= heute ? "leer" : "kommt", heute: von === heute };
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
      { art: "laufen", titel: "Laufen", wert: zahl(lauf, 1), einheit: "KM", tage: karte(e, ["lauf"], montag, heute), anteil: lauZiel ? lauf / lauZiel : null, rechts: lauZiel ? `VON ${zahl(lauZiel)} KM` : "", knopf: "+" },
      { art: "lesen", titel: "Lesen", buch, wert: lesWert, einheit: "STD",
        unter: [zuletzt?.w.s && zuletzt.w.von ? `SEITE ${zuletzt.w.s} VON ${zuletzt.w.von}` : "", `DIESE WOCHE ${lesWert} STD`].filter(Boolean).join(" · "), tage: karte(e, ["lesen"], montag, heute),
        anteil: lesZiel ? lesHeute / lesZiel : null, rechts: lesZiel ? `HEUTE ${lesHeute} VON ${lesZiel}` : "", knopf: lesZiel ? `+ ${lesZiel}` : "+" },
      { art: "kraft", titel: "Krafttraining", wert: String(kraftTage), einheit: kraftZiel ? `VON ${kraftZiel}` : "MAL", tage: karte(e, ["satz", "training"], montag, heute),
        anteil: kraftZiel ? kraftTage / kraftZiel : null, rechts: `${heuteE.filter((x) => x.art === "satz").length} SÄTZE HEUTE`, knopf: "Starten" },
      gewicht.length ? { art: "gewicht", titel: "Gewicht", wert: zahl(Number(gewicht.at(-1)?.w.kg), 1), einheit: "KG", tage: karte(e, ["gewicht"], montag, heute), anteil: null,
        rechts: `${zahl(Number(gewicht.at(-1)?.w.kg) - Number(gewicht[0].w.kg), 1).replace("-", "−")} SEIT ${KURZ[(new Date(gewicht[0].zeit).getDay() + 6) % 7]}`, knopf: "+" } : null,
    ].filter(Boolean),
    hinweis: lesZiel && lesHeute < lesZiel ? `Lesen fehlt heute noch.${sport ? ` Nach dem ${sport.titel} passt ${MINUTEN[lesZiel - lesHeute] ?? `${lesZiel - lesHeute} Minuten`}.` : ""}` : null,
  };
}

function kalenderwoche(t: number): number {
  const d = new Date(t); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
  const w1 = new Date(d.getFullYear(), 0, 4);
  return 1 + Math.round(((d.getTime() - w1.getTime()) / regelMs("ein_tag_tage") - 3 + ((w1.getDay() + 6) % 7)) / 7);
}

export function lauf(db: Register, id?: string) {
  const alle = eintraegeSeit(db, 0).map(lesen).filter((x) => x.art === "lauf");
  const l = id ? alle.find((x) => x.id === id) : alle.at(-1);
  if (!l) return null;
  const w = l.w, s = (w.km_s as number[] | undefined) ?? [], name = String(w.name ?? "Lauf");
  const lo = Math.min(...s), hi = Math.max(...s), best = s.indexOf(lo);
  const frueher = alle.filter((x) => x.zeit < l.zeit && x.w.name === w.name && ((x.w.km_s as number[] | undefined) ?? []).length);
  const schneller = frueher.reverse().findIndex((x) => Math.min(...(x.w.km_s as number[])) <= lo);
  const seit = schneller === -1 ? null : frueher[schneller].zeit;
  const wo = km(eintraegeSeit(db, wochenBeginn(l.zeit)).map(lesen).filter((x) => x.zeit <= l.zeit + 1)), z = ziel(db, "laufen_km");
  return {
    id: l.id, kopf: `LAUFEN · ${datum(l.zeit, { weekday: "long" }).toUpperCase()}, ${new Date(l.zeit).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" })}`,
    satz: [`${w.titel ?? name}.`, s.length > 2 && best === s.length - 1 ? "Der letzte Kilometer war dein schnellster." : s.length > 2 && best === 0 ? "Der erste Kilometer war dein schnellster." : ""].filter(Boolean),
    werte: [[`${zahl(Number(w.km), 1)} km`, "Strecke"], [dauer(Number(w.dauer_s)), "Zeit"], [dauer(Number(w.dauer_s) / Number(w.km)), "pro km"],
      w.hm ? [`${zahl(Number(w.hm))} m`, "bergauf"] : null, w.puls ? [zahl(Number(w.puls)), "Puls Ø"] : null, w.zone ? [String(w.zone), "meist"] : null].filter(Boolean),
    km: s.map((x, i) => ({ nr: i + 1, zeit: dauer(x), anteil: hi > lo ? 0.94 - 0.72 * (x - lo) / (hi - lo) : 0.94, schnellste: i === best })),
    bestwert: s.length && frueher.length && schneller !== 0 ? `Schnellster ${name}-Kilometer ${seit ? `seit ${datum(seit, { month: "long" })}` : "bisher"}: ${dauer(lo)}` : null,
    woche: z ? `Damit ${zahl(wo, 1)} km diese Woche, ${wo >= z ? `das Ziel von ${zahl(z)} km ist geschafft` : `noch ${zahl(z - wo, 1)} km bis zum Ziel von ${zahl(z)} km`}.` : null,
  };
}
