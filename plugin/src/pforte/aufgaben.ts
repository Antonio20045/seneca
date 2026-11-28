import { ereignisse, termineAm, todos, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { naechsteUhrzeit, regelMs, regelText } from "../regeln.ts";
import { stundeAlsWort, uhrzeit, zumWort } from "./heute.ts";
import { belegtAm, einplanen, istFokus, luecken } from "./planen.ts";

export const ZAHL = ["Nichts", "Eine", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht", "Neun", "Zehn", "Elf", "Zwölf"];

const datum = (t: number) => { const d = new Date(t); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };

function erledigt(db: Register, id: unknown): { um: number; satz: string | null } {
  const e = ereignisse(db, { art: "todo.erledigt", schluessel: String(id), grenze: 1 })[0];
  return { um: e ? Number(e.zeit) : 0, satz: e?.satz ? String(e.satz) : null };
}

export function passtNicht(plaene: { geplant_von: number | null }[]): string {
  const rest = plaene.filter((p) => !p.geplant_von).length;
  return rest ? `Für ${ZAHL[rest]?.toLowerCase() ?? rest} reicht die Zeit heute nicht.` : "Seneca hat sie über den Tag verteilt.";
}

export function wann(t: Zeile, tagBeginn: number): "heute" | "morgen" | "woche" | "ohne_tag" | "spaeter" {
  const tag = regelMs("ein_tag_tage");
  const am = t.tag ? String(t.tag) : t.bis_wann ? datum(Number(t.bis_wann)) : null;
  if (!am) return "ohne_tag";
  if (am <= datum(tagBeginn)) return "heute";
  if (am === datum(tagBeginn + tag)) return "morgen";
  const montag = tagBeginn + ((8 - new Date(tagBeginn).getDay()) % 7 || 7) * tag;
  return am < datum(montag) ? "woche" : "spaeter";
}

function bisWort(db: Register, ab: number, jetzt: number): string {
  const fenster = naechsteUhrzeit(regelText("fenster"), jetzt);
  const t = termineAm(db, jetzt).find((x) => !x.ganztag && !istFokus(x) && x.start >= ab && x.ende - x.start >= regelMs("aufgaben_block_min"));
  return t && t.start < fenster ? `${zumWort(t.titel)} um ${stundeAlsWort(t.start)}` : `zum Entscheiden um ${stundeAlsWort(fenster)}`;
}

export function aufgaben(db: Register, ruhe: { grund: string; bis: number } | undefined, tagBeginn: number, jetzt: number) {
  const offen = todos(db, "offen").filter((t) => !t.wiederkehrend);
  const heute = offen.filter((t) => wann(t, tagBeginn) === "heute");
  const geplant = heute.filter((t) => t.geplant_von).sort((a, b) => Number(a.geplant_von) - Number(b.geplant_von));
  const ab = ruhe?.grund === "fokus" ? ruhe.bis : jetzt;
  const l = geplant[0] && luecken(belegtAm(db, jetzt).filter((b) => b.bis - b.von >= regelMs("aufgaben_block_min")), ab, naechsteUhrzeit(regelText("plan_bis"), ab))
    .find((x) => x.von <= Number(geplant[0].geplant_von) && Number(geplant[0].geplant_von) < x.bis);
  const drin = l ? heute.filter((t) => Number(t.geplant_von) >= l.von && Number(t.geplant_von) < l.bis) : [];
  const nachFokus = !!l && ruhe?.grund === "fokus" && l.von === ruhe.bis;
  const naechster = l && termineAm(db, jetzt).find((x) => !x.ganztag && x.start >= l.bis);
  const weg = naechster && naechster.start === l?.bis ? Number(wert(db, `wegzeit:${naechster.uid}`)?.wert ?? 0) * regelMs("eine_minute_min") : 0;
  const akzent = !heute.length ? `Bis ${bisWort(db, ab, jetzt)} gehört die Zeit dir.`
    : drin.length === heute.length && naechster ? `Alle passen ${nachFokus ? "zwischen Fokus und" : "bis"} ${nachFokus ? naechster.titel.split(" ")[0] : zumWort(naechster.titel)}.`
    : passtNicht(einplanen(db, heute, jetzt));
  const taeglich = [...todos(db, "offen"), ...todos(db, "erledigt")].filter((t) => t.wiederkehrend);
  const zaehle = (w: string) => offen.filter((t) => wann(t, tagBeginn) === w).length;
  return {
    satz: [heute.length ? `${ZAHL[heute.length] ?? heute.length} für heute.` : "Nichts offen.", akzent],
    gruppe: l ? { titel: nachFokus ? "NACH DEM FOKUS" : "HEUTE", zeit: `${uhrzeit(l.von)} BIS ${uhrzeit(l.bis - weg)}`, ids: drin.map((t) => t.id) } : null,
    heute: heute.map((t) => t.id),
    erledigt: todos(db, "erledigt").filter((t) => !t.wiederkehrend).map((t) => ({ id: t.id, titel: t.titel, bereich: t.bereich, von: t.erledigt_von, ...erledigt(db, t.id) }))
      .filter((t) => t.um >= tagBeginn),
    jeden_tag: taeglich.map((t) => ({ id: t.id, titel: t.titel, erledigt: erledigt(db, t.id).um >= tagBeginn, ab: String(t.notiz ?? "").match(/ab (\d\d:\d\d)/)?.[1] ?? null, dauer_min: t.dauer_min })),
    zaehler: { morgen: zaehle("morgen"), woche: zaehle("woche"), ohne_tag: zaehle("ohne_tag") },
  };
}
