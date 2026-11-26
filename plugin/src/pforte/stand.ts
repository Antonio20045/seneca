import { aktiveLaeufe, auftraege, ereignisse, faelligeWirkungen, fragen, hole, revision, todos, uhr, wert, werte, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { letzteUhrzeit, naechsteUhrzeit, regelMs, regelText, regelUhrzeitNach, regelZahl } from "../regeln.ts";
import { mitarbeiter } from "../team.ts";

const SCHEMA = 1;

export function ruhe(db: Register, jetzt: number): { grund: string; bis: number; durchbruch: boolean } | undefined {
  const nachtBis = naechsteUhrzeit(regelText("nachtruhe_bis"), jetzt);
  if (naechsteUhrzeit(regelText("nachtruhe_von"), jetzt) > nachtBis) return { grund: "nacht", bis: nachtBis, durchbruch: false };
  const a = wert(db, "aktivitaet");
  if (!a || a.wert === "leer" || (a.gueltig_bis ?? Infinity) <= jetzt) return undefined;
  return { grund: a.wert, bis: a.gueltig_bis ?? Infinity, durchbruch: !regelText("ruhe_ohne_durchbruch").split(",").includes(a.wert) };
}

function vertagt(db: Register, f: Zeile, jetzt: number): boolean {
  const v = ereignisse(db, { art: "frage.vertagt", frage_id: String(f.id), grenze: 1 })[0];
  return !!v && JSON.parse(String(v.daten)).bis > jetzt;
}

function haengtDaran(db: Register, f: Zeile): number {
  return auftraege(db, ["wartet"]).filter((a) => a.wartet_auf === `frage:${f.id}` || a.wartet_auf === `auftrag:${f.auftrag_id}`).length;
}

function zaehlt(db: Register, f: Zeile, jetzt: number): boolean {
  if (f.art === "vorschlag" || vertagt(db, f, jetzt)) return false;
  return haengtDaran(db, f) > 0 || f.frist !== null || f.wirkung_aussen !== "keine";
}

function rang(db: Register, f: Zeile, jetzt: number): number {
  const morgenEnde = naechsteUhrzeit("00:00", naechsteUhrzeit("00:00", jetzt));
  const weitere = auftraege(db, ["wartet"]).filter((a) => a.wartet_auf === `auftrag:${f.auftrag_id}`).length;
  return (weitere ? 3 : 0) + (f.frist !== null && Number(f.frist) < morgenEnde ? 2 : 0) + (jetzt - Number(f.gestellt) > regelMs("lange_wartend_h") ? 1 : 0);
}

function brauchtDich(db: Register, jetzt: number): Zeile[] {
  return [...fragen(db, "offen"), ...faelligeWirkungen(db, Infinity)]
    .filter((f) => zaehlt(db, f, jetzt))
    .sort((a, b) => rang(db, b, jetzt) - rang(db, a, jetzt) || Number(a.gestellt) - Number(b.gestellt))
    .slice(0, regelZahl("braucht_dich_max"));
}

export function uhrTauglich(f: Zeile): boolean {
  return f.art === "ja_nein" && f.wirkung_aussen === "keine";
}

function frageSicht(db: Register, f: Zeile) {
  return {
    id: f.id, text: f.text, von: f.von, seit: f.gestellt, art: f.art, wirkung_aussen: f.wirkung_aussen, optionen: JSON.parse(String(f.optionen)),
    empfehlung: f.empfehlung, kontext: { worum: f.was_passiert_ist, wenn_nicht: f.wenn_nichts }, frist: f.frist, wirkt_ab: f.wirkt_ab,
    zustellung: ereignisse(db, { art: "zustellung", frage_id: String(f.id) }).map((e) => ({ geraet: e.geraet, zeit: e.zeit, ...JSON.parse(String(e.daten)) })),
    antwort: f.antwort ? { wahl: f.antwort, geraet: f.antwort_geraet, zeit: f.antwort_um } : null,
  };
}

function team(db: Register, jetzt: number) {
  const laeufe = aktiveLaeufe(db);
  return mitarbeiter().map((name) => {
    const l = laeufe.find((x) => x.mitarbeiter === name);
    const r = wert(db, `ruht:${name}`);
    const ruht = r?.wert === "ja" && (r.gueltig_bis ?? Infinity) > jetzt;
    return { name, zustand: l ? (l.zustand === "haengt" ? "hängt" : "arbeitet") : ruht ? "ruht" : "frei", satz: l?.letzter_schritt ?? null, seit: l?.gestartet ?? null };
  });
}

export function stand(db: Register, eingabe: { geraet: string; revision?: number }, jetzt: number) {
  const rev = revision(db);
  if (eingabe.revision === rev) return { schema: SCHEMA, revision: rev, jetzt, unveraendert: true };
  const braucht = brauchtDich(db, jetzt);
  const tagBeginn = letzteUhrzeit(regelText("tag_grenze"), jetzt);
  const inhalt = {
    schema: SCHEMA, revision: rev, jetzt, erzeugt: jetzt, geraet: eingabe.geraet, tag_beginn: tagBeginn,
    regeln: { rueckgaengig_s: regelZahl("rueckgaengig_s"), rueckgaengig_vo_s: regelZahl("rueckgaengig_vo_s"), uhr_abfrage_min: regelZahl("uhr_abfrage_min"),
      gespraech_haengt_hinweis_min: regelZahl("gespraech_haengt_hinweis_min"), gespraech_haengt_stopp_min: regelZahl("gespraech_haengt_stopp_min") },
    zaehler: { braucht: braucht.length },
    ruhe: ruhe(db, jetzt) ?? null,
    braucht_dich: braucht.map((f) => frageSicht(db, f)),
    buendel: {
      fenster: regelUhrzeitNach("fenster", jetzt),
      abnahmen: auftraege(db, ["wartet_auf_abnahme"]).filter((a) => a.auftraggeber === "antonio").map((a) => ({ id: a.id, titel: a.titel, ergebnis: JSON.parse(String(a.ergebnis ?? "null")) })),
      fragen: fragen(db, "offen").filter((f) => !braucht.some((b) => b.id === f.id)).map((f) => frageSicht(db, f)),
    },
    team: team(db, jetzt),
    heute_erledigt: auftraege(db, ["erledigt"]).filter((a) => Number(a.geaendert) >= tagBeginn).map((a) => ({ id: a.id, titel: a.titel, ergebnis: JSON.parse(String(a.ergebnis ?? "null")) })),
    todos: todos(db, "offen").map((t) => ({ id: t.id, titel: t.titel, tag: t.tag, bis_wann: t.bis_wann, wichtig: !!t.wichtig, revision: t.revision })),
    hinweise: [...werte(db, "hinweis:").values()].filter(Boolean),
  };
  if (JSON.stringify(inhalt).length > regelZahl("stand_max_kb") * 1024) throw new Error("Stand zu gross");
  return inhalt;
}

export function lesenWerkzeug(db: Register, was: string, id?: string): string {
  const jetzt = uhr.jetzt();
  if (was === "auftrag" && id) {
    const a = hole(db, "auftrag", id);
    return `„${a.titel}“ ist ${a.zustand}. Stand: ${a.letzter_stand || "noch nichts"}. Nächster Schritt: ${a.naechster_schritt || "offen"}.`;
  }
  if (was === "team") return team(db, jetzt).map((t) => `${t.name}: ${t.zustand}${t.satz ? `, ${t.satz}` : ""}`).join("\n");
  if (was === "fragen") return brauchtDich(db, jetzt).map((f) => `${f.id}: ${f.text}`).join("\n") || "Nichts braucht Antonio gerade.";
  const praefix = { profil: "profil:", fakten: "fakt:", kontakt: "kontakt:" }[was];
  if (!praefix) throw new Error(`seneca_lesen kennt ${was} nicht.`);
  return [...werte(db, praefix)].map(([k, v]) => `${k}: ${v}`).join("\n") || "Nichts hinterlegt.";
}
