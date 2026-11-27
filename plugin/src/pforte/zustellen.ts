import { ereignisse, fragen, hole, kinder, uhr, vorschlaege, vorschlagDaten, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { auftragAnlegen, ereignis, uebergang } from "../register/schreiben.ts";
import { naechsteUhrzeit, regelMs, regelUhrzeitNach, regelZahl } from "../regeln.ts";
import { anzeigeName } from "../team.ts";
import type { Sender } from "./push.ts";
import { ruhe, uhrTauglich } from "./stand.ts";

type Entscheidung = { was: "zurueckgehalten" | "leise" | "zugestellt"; geraet?: string; grund: string; durchsicht: string[] };

function letzte(db: Register, f: Zeile): Record<string, string> | undefined {
  const e = ereignisse(db, { art: "zustellung", frage_id: String(f.id), grenze: 1 })[0];
  return e ? { ...JSON.parse(String(e.daten)), geraet: String(e.geraet) } : undefined;
}

function aktiv(db: Register, schluessel: string, jetzt: number): boolean {
  const w = wert(db, schluessel);
  return w?.wert === "ja" && (w.gueltig_bis ?? Infinity) > jetzt;
}

function fest(f: Zeile, a: Zeile, jetzt: number): boolean {
  const fristHeute = f.frist !== null && Number(f.frist) < naechsteUhrzeit("00:00", jetzt);
  return fristHeute && a.zustand === "wartet" && jetzt - Number(a.geaendert) > regelMs("durchbruch_h");
}

function entscheide(db: Register, f: Zeile, jetzt: number): Entscheidung {
  const fenster = regelUhrzeitNach("fenster", jetzt);
  const a = hole(db, "auftrag", String(f.auftrag_id));
  const durchbruch = fest(f, a, jetzt);
  const eilig = ((f.frist !== null && Number(f.frist) < fenster) || durchbruch) && !(f.art === "vorschlag" && wenigAngenommen(db, String(f.auftrag_id), jetzt));
  const r = ruhe(db, jetzt);
  const durchsicht = [`aussen:${f.wirkung_aussen}`, `frist:${f.frist ?? "keine"}`, `ruhe:${r?.grund ?? "keine"}`];
  if (r && !(durchbruch && r.durchbruch)) return { was: "zurueckgehalten", grund: r.grund, durchsicht };
  if (!eilig) return { was: "leise", grund: "keine Folge vor dem Fenster", durchsicht };
  const geraet = aktiv(db, "praesenz:mac", jetzt) ? "mac" : aktiv(db, "praesenz:iphone", jetzt) ? "iphone" : uhrTauglich(f) && aktiv(db, "uhr_am_arm", jetzt) ? "uhr" : "iphone";
  return { was: "zugestellt", geraet, grund: durchbruch ? `Durchbruch: Frist heute, blockiert seit über ${regelZahl("durchbruch_h")} Std.` : "Folge vor dem Fenster", durchsicht };
}

function wenigAngenommen(db: Register, auftragId: string, jetzt: number): boolean {
  const alle = vorschlaege(db, String(vorschlagDaten(db, auftragId).herkunft));
  const entschieden = alle.filter((v) => v.zustand !== "vorgeschlagen");
  if (!alle.length || jetzt - Number(alle[0].erstellt) < regelMs("vorschlag_quote_ab_tage") || !entschieden.length) return false;
  return entschieden.filter((v) => v.zustand !== "verworfen").length * 100 < regelZahl("vorschlag_mindestquote_prozent") * entschieden.length;
}

function mitteilungErlaubt(db: Register, f: Zeile, jetzt: number): boolean {
  const unterwegs = fragen(db, "offen").some((o) => o.id !== f.id && letzte(db, o)?.was === "zugestellt");
  const zuletzt = ereignisse(db, { art: "zustellung", seit: jetzt - regelMs("push_abstand_min") }).some((e) => JSON.parse(String(e.daten)).was === "zugestellt");
  const fristHeute = f.frist !== null && Number(f.frist) < naechsteUhrzeit("00:00", jetzt);
  return !unterwegs && (!zuletzt || fristHeute);
}

function anrufWennFest(db: Register, f: Zeile, a: Zeile, jetzt: number): void {
  const r = ruhe(db, jetzt);
  const nummer = wert(db, "profil:telefon")?.wert;
  if (!nummer || !fest(f, a, jetzt) || (r && !r.durchbruch) || kinder(db, String(a.id)).some((k) => k.wortlaut_quelle === `frage:${f.id}`)) return;
  auftragAnlegen(db, {
    art: "system", wortlaut: `Ruf Antonio an (${nummer}) und stell diese Frage: ${f.text} Empfehlung: ${f.empfehlung}`, wortlaut_quelle: `frage:${f.id}`, eltern_id: String(a.id),
    titel: `Anruf bei Antonio: ${a.titel}`, ziel: "Antonio hat die Frage gehört", abnahme: "Anruf ausgeführt", abnahme_durch: "beleg", pruefer_noetig: false,
    verantwortlich: String(a.verantwortlich), auftraggeber: String(a.verantwortlich), quelle: "eigene_idee", bereich: String(a.bereich), arbeitsart: "anruf_antonio", naechster_anlass: jetzt,
  });
}

export async function zustellenJob(db: Register, senden?: Sender): Promise<void> {
  const jetzt = uhr.jetzt();
  for (const f of fragen(db, "offen")) {
    const a = hole(db, "auftrag", String(f.auftrag_id));
    if (f.frist !== null && Number(f.frist) < jetzt) {
      uebergang(db, "frage", String(f.id), "abgelaufen", "frist", { grund: `${anzeigeName(String(f.von))}: ${f.wenn_nichts}` });
      if (a.zustand === "wartet") uebergang(db, "auftrag", String(a.id), "bereit", "frist", { naechster_anlass: jetzt });
      if (a.zustand === "vorgeschlagen") uebergang(db, "auftrag", String(a.id), "verworfen", "abgelaufen");
      continue;
    }
    anrufWennFest(db, f, a, jetzt);
    const vorher = letzte(db, f);
    if (vorher && vorher.was !== "zurueckgehalten") continue;
    const e = entscheide(db, f, jetzt);
    if (vorher?.was === e.was || (e.was === "zugestellt" && !mitteilungErlaubt(db, f, jetzt))) continue;
    ereignis(db, { art: "zustellung", frage_id: String(f.id), auftrag_id: String(a.id), geraet: e.geraet, daten: { was: e.was, grund: e.grund, durchsicht: e.durchsicht } });
    if (senden && e.was === "zugestellt" && e.geraet === "iphone") await senden(db, "iphone", String(f.text), String(f.id));
  }
}
