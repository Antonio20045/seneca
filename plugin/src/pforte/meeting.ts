import { auftraege, termineAm, uhr } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { lebensbereich, regelListe, regelMs, regelText, regelZahl } from "../regeln.ts";
import { mandat } from "../team.ts";

type Termin = ReturnType<typeof termineAm>[number] & { namen?: string[]; notiz?: string };

function grundFuer(t: Termin): string | undefined {
  const gewollt = !t.ganztag && !regelListe("fokus_worte").some((w) => t.titel.toLowerCase().includes(w.toLowerCase())) && t.kalender !== regelText("kalender_seneca") && !t.uid.endsWith("-seneca");
  if (!gewollt) return undefined;
  if (new RegExp(regelText("meeting_link"), "i").test(`${t.ort ?? ""} ${t.notiz ?? ""}`)) return "Videolink";
  if (lebensbereich(t.titel) === "soziales") return undefined;
  if (t.teilnehmer.length >= regelZahl("meeting_teilnehmer_min")) return "Teilnehmer";
  return new RegExp(`\\b(${regelListe("meeting_worte").join("|")})\\b`, "i").test(t.titel) || /\bmit [A-ZÄÖÜ]/.test(t.titel) ? "Titel" : undefined;
}

function angebot(t: Termin, id: string, wer: string, arbeitsart: string, text: string) {
  return { id, text, wer, arbeitsart, bereich: mandat(wer).bereich[0], quelle: `meeting:${t.uid}:${id}` };
}

export function meetingVon(db: Register, t: Termin) {
  const grund = grundFuer(t), jetzt = uhr.jetzt();
  if (!grund) return null;
  const phase = t.ende <= jetzt ? "danach" : t.start <= jetzt ? "laeuft" : "vorher";
  const genommen = new Set(auftraege(db, ["bereit", "laeuft", "wartet", "erledigt"]).map((x) => x.wortlaut_quelle));
  const titel = t.titel.slice(0, regelZahl("meeting_zeichen")), mit = t.namen?.join(", ") || titel;
  const seneca = (phase === "vorher" ? [angebot(t, "vorbereiten", regelText("meeting_recherche_von"), "recherche", `Hintergrund zu ${mit} recherchieren`)]
    : phase === "danach" && jetzt - t.ende < regelMs("meeting_nachher_h") ? [angebot(t, "nachfassen", regelText("dauerauftraege_von"), "standard", `Nachfass-Entwurf zu „${titel}“ schreiben`)] : [])
    .map((a) => ({ ...a, genommen: genommen.has(a.quelle) }));
  const du = phase === "vorher" ? [...(t.notiz?.trim() ? [{ id: "lesen", text: `Einladung und Unterlagen zu „${titel}“ lesen` }] : []), { id: "ziel", text: `Ziel und Fragen für „${titel}“ in einem Satz notieren` }]
    : phase === "danach" ? [{ id: "zusagen", text: `Zusagen aus „${titel}“ als To-dos notieren` }] : [];
  return { grund, phase, du, seneca };
}
