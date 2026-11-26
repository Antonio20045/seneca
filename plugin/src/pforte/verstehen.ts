import { termineAm, todos } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { regelMs, regelText, regelZahl } from "../regeln.ts";

const TAGE = ["sonntag", "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag"];
const TAG_GROSS = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];

function tagVon(klein: string, jetzt: number): Date | undefined {
  const heute = new Date(jetzt); heute.setHours(0, 0, 0, 0);
  const plus = (n: number) => new Date(heute.getFullYear(), heute.getMonth(), heute.getDate() + n);
  if (klein.includes("übermorgen")) return plus(2);
  if (klein.includes("morgen")) return plus(1);
  if (klein.includes("heute")) return heute;
  const i = TAGE.findIndex((t) => klein.includes(t));
  return i < 0 ? undefined : plus((i - heute.getDay() + 7) % 7 || 7);
}

function terminZu(db: Register, tag: Date | undefined, klein: string, wort: string) {
  const ziel = new RegExp(`${wort} (?:dem|der|den) (\\S+)`).exec(klein)?.[1];
  return ziel && tag ? termineAm(db, tag.getTime()).find((t) => !t.ganztag && t.titel.toLowerCase().includes(ziel.replace(/[.,]$/, ""))) : undefined;
}

export function verstehen(db: Register, satz: string, jetzt: number) {
  const klein = satz.toLowerCase();
  const tag = tagVon(klein, jetzt);
  const uhr = /um (\d{1,2})(?::(\d{2}))?|(\d{1,2})(?::(\d{2}))? uhr/.exec(klein);
  const dauer = /(\d+)\s*(min|minuten|std|stunden?)\b/.exec(klein);
  const alle = [...todos(db, "offen"), ...todos(db, "erledigt")];
  const bereich = [...new Set(alle.map((t) => String(t.bereich ?? "")).filter(Boolean))].find((b) => klein.includes(b.toLowerCase()));
  const worte = klein.split(/[^a-zäöüß]+/).filter((w) => w.length >= regelZahl("verstehen_wort_min"));
  const aehnlich = alle.find((t) => t.dauer_min && worte.some((w) => String(t.titel).toLowerCase().includes(w)));
  const vor = terminZu(db, tag, klein, "vor");
  const tagesTermine = tag ? termineAm(db, tag.getTime()).filter((t) => !t.ganztag) : [];
  const nach = terminZu(db, tag, klein, "nach") ?? (vor && !uhr ? tagesTermine.filter((t) => t.ende <= vor.start).at(-1) : undefined);
  const minuten = dauer ? Number(dauer[1]) * (dauer[2].startsWith("s") ? regelZahl("eine_stunde_min") : 1) : Number(aehnlich?.dauer_min ?? regelZahl("todo_dauer_standard_min"));
  const von = tag && uhr ? new Date(tag).setHours(Number(uhr[1] ?? uhr[3]), Number(uhr[2] ?? uhr[4] ?? 0)) : nach?.ende ?? (vor ? vor.start - minuten * regelMs("eine_minute_min") : null);
  const erkannt = !!(tag || dauer || bereich || vor || nach || /jeden tag|täglich/.test(klein));
  const zeit = von ? new Date(von) : undefined;
  const wann = tag && [tag.getTime() === tagVon("heute", jetzt)?.getTime() ? "heute" : tag.getTime() === tagVon("morgen", jetzt)?.getTime() ? "morgen" : TAG_GROSS[tag.getDay()],
    zeit && `um ${zeit.getHours()}${zeit.getMinutes() ? `:${String(zeit.getMinutes()).padStart(2, "0")}` : ""}`].filter(Boolean).join(" ");
  return {
    erkannt, titel: erkannt && satz.includes(",") ? satz.slice(0, satz.indexOf(",")).trim() : satz.trim(),
    tag: tag ? `${tag.getFullYear()}-${String(tag.getMonth() + 1).padStart(2, "0")}-${String(tag.getDate()).padStart(2, "0")}` : null,
    von, bis: vor?.start ?? null, dauer_min: minuten, geschaetzt: [...(dauer ? [] : ["dauer"]), ...(bereich ? [] : ["bereich"])],
    bereich: bereich ?? String(aehnlich?.bereich ?? regelText("bereich_standard")), wiederkehrend: /jeden tag|täglich/.test(klein) ? "taeglich" : null,
    hinweis: `Du bekommst es ${wann ? `${wann} ` : ""}auf die Uhr${nach ? `, nach dem ${nach.titel.split(" ")[0]}` : ""}.`,
  };
}
