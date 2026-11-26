import { ereignisse, fragen, hole, uhr, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { ereignis, uebergang } from "../register/schreiben.ts";
import { naechsteUhrzeit, regelMs, regelUhrzeitNach, regelZahl } from "../regeln.ts";
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

function entscheide(db: Register, f: Zeile, jetzt: number): Entscheidung {
  const fenster = regelUhrzeitNach("fenster", jetzt);
  const heuteEnde = naechsteUhrzeit("00:00", jetzt);
  const fristHeute = f.frist !== null && Number(f.frist) < heuteEnde;
  const a = hole(db, "auftrag", String(f.auftrag_id));
  const durchbruch = fristHeute && a.zustand === "wartet" && jetzt - Number(a.geaendert) > regelMs("durchbruch_h");
  const eilig = (f.frist !== null && Number(f.frist) < fenster) || durchbruch;
  const r = ruhe(db, jetzt);
  const durchsicht = [`aussen:${f.wirkung_aussen}`, `frist:${f.frist ?? "keine"}`, `ruhe:${r?.grund ?? "keine"}`];
  if (r && !(durchbruch && r.durchbruch)) return { was: "zurueckgehalten", grund: r.grund, durchsicht };
  if (!eilig) return { was: "leise", grund: "keine Folge vor dem Fenster", durchsicht };
  const geraet = aktiv(db, "praesenz:mac", jetzt) ? "mac" : aktiv(db, "praesenz:iphone", jetzt) ? "iphone" : uhrTauglich(f) && aktiv(db, "uhr_am_arm", jetzt) ? "uhr" : "iphone";
  return { was: "zugestellt", geraet, grund: durchbruch ? `Durchbruch: Frist heute, blockiert seit über ${regelZahl("durchbruch_h")} Std.` : "Folge vor dem Fenster", durchsicht };
}

function mitteilungErlaubt(db: Register, f: Zeile, jetzt: number): boolean {
  const unterwegs = fragen(db, "offen").some((o) => o.id !== f.id && letzte(db, o)?.was === "zugestellt");
  const zuletzt = ereignisse(db, { art: "zustellung", seit: jetzt - regelMs("push_abstand_min") }).some((e) => JSON.parse(String(e.daten)).was === "zugestellt");
  const fristHeute = f.frist !== null && Number(f.frist) < naechsteUhrzeit("00:00", jetzt);
  return !unterwegs && (!zuletzt || fristHeute);
}

export function zustellenJob(db: Register): void {
  const jetzt = uhr.jetzt();
  for (const f of fragen(db, "offen")) {
    const a = hole(db, "auftrag", String(f.auftrag_id));
    if (f.frist !== null && Number(f.frist) < jetzt) {
      uebergang(db, "frage", String(f.id), "abgelaufen", "frist", { grund: "Die Frist ist vorbei, ohne Antwort." });
      if (a.zustand === "wartet") uebergang(db, "auftrag", String(a.id), "bereit", "frist", { naechster_anlass: jetzt });
      continue;
    }
    const vorher = letzte(db, f);
    if (vorher && vorher.was !== "zurueckgehalten") continue;
    const e = entscheide(db, f, jetzt);
    if (vorher?.was === e.was || (e.was === "zugestellt" && !mitteilungErlaubt(db, f, jetzt))) continue;
    ereignis(db, { art: "zustellung", frage_id: String(f.id), auftrag_id: String(a.id), geraet: e.geraet, daten: { was: e.was, grund: e.grund, durchsicht: e.durchsicht } });
  }
}
