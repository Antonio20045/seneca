import { aktiveLaeufe, auftraege, ereignisse, faelligeWirkungen, fragen, hole, beendeteLaeufe, revision, spaeterBis, termineAm, todos, uhr, wert, werte, zurueckgenommen, type Zeile } from "../register/lesen.ts";
import { istFokus } from "./planen.ts";
import { buendelText, heute, koerper, projektVon, restMin } from "./heute.ts";
import { projekte } from "./projekte.ts";
import { weg, wochenplan } from "./wochenplan.ts";
import { verlauf } from "./verlauf.ts";
import { buendelFortschritt, entscheiden, fensterStart, istSport, optionenSicht } from "./entscheiden.ts";
import type { Register } from "../register/schema.ts";
import { letzteUhrzeit, msAusMinuten, naechsteUhrzeit, regelMs, regelText, regelZahl, sekundenAusMs } from "../regeln.ts";
import { anzeigeName, mitarbeiter } from "../team.ts";

const SCHEMA = 1;

export function ruhe(db: Register, jetzt: number): { grund: string; bis: number; durchbruch: boolean } | undefined {
  const nachtBis = naechsteUhrzeit(regelText("nachtruhe_bis"), jetzt);
  if (naechsteUhrzeit(regelText("nachtruhe_von"), jetzt) > nachtBis) return { grund: "nacht", bis: nachtBis, durchbruch: false };
  const a = wert(db, "aktivitaet");
  const fokus = termineAm(db, jetzt).find((t) => !t.ganztag && t.start <= jetzt && t.ende > jetzt && istFokus(t));
  if ((!a || a.wert === "leer" || (a.gueltig_bis ?? Infinity) <= jetzt) && fokus) return { grund: "fokus", bis: fokus.ende, durchbruch: true };
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
  return (f.art === "ja_nein" || f.art === "vorschlag") && f.wirkung_aussen === "keine";
}

function vorschlagAnUhr(db: Register): Zeile | undefined {
  return fragen(db, "offen").find((f) => f.art === "vorschlag" && ereignisse(db, { art: "zustellung", frage_id: String(f.id), grenze: 1 }).some((e) => e.geraet === "uhr"));
}

function frageSicht(db: Register, f: Zeile) {
  return {
    id: f.id, text: f.text, von: anzeigeName(String(f.von)), projekt: projektVon(db, f.auftrag_id), seit: f.gestellt, art: f.art, wirkung_aussen: f.wirkung_aussen, ...optionenSicht(f),
    empfehlung: f.empfehlung, kontext: { worum: f.was_passiert_ist, wenn_nicht: f.wenn_nichts }, frist: f.frist, wirkt_ab: f.wirkt_ab,
    zustellung: ereignisse(db, { art: "zustellung", frage_id: String(f.id) }).map((e) => ({ geraet: e.geraet, zeit: e.zeit, ...JSON.parse(String(e.daten)) })),
    antwort: f.antwort ? { wahl: f.antwort, geraet: f.antwort_geraet, zeit: f.antwort_um } : null, ...bericht(db, String(f.auftrag_id)),
  };
}

function bericht(db: Register, auftrag: string) {
  const f = JSON.parse(String(ereignisse(db, { art: "fortschreibung", auftrag_id: auftrag, grenze: 1 })[0]?.daten ?? "{}"));
  const n = ereignisse(db, { art: "lauf.schritt", auftrag_id: auftrag }).length;
  return { checkliste: f.checkliste ?? null, bericht: f.letzter_stand ? { satz: [`${n} Schritte`, f.bericht].filter(Boolean).join(" · "), text: f.letzter_stand, beleg: f.beleg ?? null } : null };
}

function team(db: Register, jetzt: number) {
  const laeufe = aktiveLaeufe(db);
  const tagBeginn = letzteUhrzeit(regelText("tag_grenze"), jetzt);
  return mitarbeiter().map((name) => {
    const l = laeufe.find((x) => x.mitarbeiter === name);
    const r = wert(db, `ruht:${name}`);
    const ruht = r?.wert === "ja" && (r.gueltig_bis ?? Infinity) > jetzt;
    const zuletzt = l ? undefined : beendeteLaeufe(db, name, tagBeginn)[0];
    return { name, zustand: l ? (l.zustand === "haengt" ? "hängt" : "arbeitet") : ruht ? "ruht" : "frei", satz: l?.letzter_schritt ?? null, seit: l?.gestartet ?? null,
      projekt: l ? projektVon(db, l.auftrag_id) : null, rest_min: l ? restMin(db, l, jetzt) : null,
      zuletzt: zuletzt ? { satz: zuletzt.letzter_schritt ?? zuletzt.titel, um: zuletzt.beendet_um } : null,
      ruht_seit: ruht ? ereignisse(db, { art: "wert.gesetzt", schluessel: `ruht:${name}`, grenze: 1 })[0]?.zeit ?? null : null };
  });
}

function buendel(db: Register, braucht: Zeile[], jetzt: number) {
  const abnahmen = auftraege(db, ["wartet_auf_abnahme"]).filter((a) => a.auftraggeber === "antonio");
  const offen = fragen(db, "offen").filter((f) => !braucht.some((b) => b.id === f.id));
  return {
    fenster: fensterStart(jetzt), ...buendelText(abnahmen, offen.length), ...buendelFortschritt(db, abnahmen, jetzt),
    fragen: offen.map((f) => frageSicht(db, f)),
  };
}

export function stand(db: Register, eingabe: { geraet: string; revision?: number }, jetzt: number) {
  const rev = revision(db);
  if (eingabe.revision === rev) return { schema: SCHEMA, revision: rev, jetzt, unveraendert: true };
  const braucht = brauchtDich(db, jetzt);
  const tagBeginn = letzteUhrzeit(regelText("tag_grenze"), jetzt);
  const b = buendel(db, braucht, jetzt);
  const inhalt = {
    schema: SCHEMA, revision: rev, jetzt, erzeugt: jetzt, geraet: eingabe.geraet, tag_beginn: tagBeginn,
    regeln: { rueckgaengig_s: regelZahl("rueckgaengig_s"), rueckgaengig_vo_s: regelZahl("rueckgaengig_vo_s"), uhr_abfrage_min: regelZahl("uhr_abfrage_min"),
      gespraech_haengt_hinweis_min: regelZahl("gespraech_haengt_hinweis_min"), gespraech_haengt_stopp_min: regelZahl("gespraech_haengt_stopp_min"),
      verbinden_start_s: regelZahl("verbinden_start_s"), verbinden_max_s: regelZahl("verbinden_max_s"),
      anmeldefehler_max: regelZahl("anmeldefehler_max"), getrennt_nach_s: regelZahl("getrennt_nach_s"), fenster_dauer_min: regelZahl("fenster_dauer_min"),
      kal_raster_min: regelZahl("kal_raster_min"), kal_raster_fein_min: regelZahl("kal_raster_fein_min"), wegzeit_vorlauf_min: regelZahl("wegzeit_vorlauf_min"),
      weg_neu_min: regelZahl("weg_neu_min"), weg_zu_fuss_bis_min: regelZahl("weg_zu_fuss_bis_min"), weg_erinnern_vor_min: regelZahl("weg_erinnern_vor_min"),
      kal_bb_gut_ab: regelZahl("kal_bb_gut_ab") },
    zaehler: { braucht: braucht.length },
    ruhe: ruhe(db, jetzt) ?? null,
    heute: heute(db, ruhe(db, jetzt), jetzt),
    koerper: koerper(db, tagBeginn, ruhe(db, jetzt)),
    braucht_dich: braucht.map((f) => frageSicht(db, f)),
    buendel: b,
    projekte: projekte(db, jetzt, ruhe(db, jetzt)?.grund === "fokus"),
    entscheiden: entscheiden(db, braucht.length + b.fragen.length, b.abnahmen.length > 0, tagBeginn, jetzt),
    team: team(db, jetzt).map((t) => ({ ...t, id: t.name, name: anzeigeName(t.name) })),
    gelernt: ereignisse(db, { art: "korrektur", seit: tagBeginn }).filter((e) => !zurueckgenommen(db, Number(e.nr))).map((e) => ({ nr: e.nr, zeile: e.satz, zeit: e.zeit })),
    heute_erledigt: auftraege(db, ["erledigt"]).filter((a) => Number(a.geaendert) >= tagBeginn).map((a) => ({ id: a.id, titel: a.titel, ergebnis: JSON.parse(String(a.ergebnis ?? "null")) })),
    termine: termineAm(db, jetzt).map((t) => ({ ...t, art: istFokus(t) ? "fokus" : istSport(t.titel) ? "bewegung" : "termin", weg: weg(db, t).kurz })),
    wochenplan: wochenplan(db, jetzt),
    verlauf: verlauf(db, tagBeginn, jetzt),
    todos: todos(db, "offen").map((t) => ({ id: t.id, titel: t.titel, bereich: t.bereich, tag: t.tag, bis_wann: t.bis_wann, dauer_min: t.dauer_min,
      geplant_von: t.geplant_von, wiederkehrend: t.wiederkehrend, wichtig: !!t.wichtig, revision: t.revision })),
    hinweise: [...werte(db, "hinweis:").values()].filter(Boolean),
    kopplung: [...werte(db, "kopplung:")].filter(([k]) => k !== "kopplung:fenster").map(([k, v]) => ({ geraet: k.slice("kopplung:".length), ...JSON.parse(v) }))
      .filter((k) => !k.bestaetigt).map((k) => ({ geraet: k.geraet, zahl: k.zahl })),
  };
  if (JSON.stringify(inhalt).length > regelZahl("stand_max_kb") * 1024) throw new Error("Stand zu gross");
  return inhalt;
}

function uhrFrage(db: Register, f: Zeile, jetzt: number) {
  const a = hole(db, "auftrag", String(f.auftrag_id));
  const zeichen = regelZahl("uhr_frage_zeichen");
  return { id: f.id, x: String(f.text).slice(0, zeichen), a: String(a.titel).slice(0, zeichen), v: f.von, k: String(f.was_passiert_ist).slice(0, zeichen), p: a.projekt ?? a.bereich, s: sekundenAusMs(Number(f.gestellt)), sb: sekundenAusMs(spaeterBis(db, String(f.id), jetzt)) };
}

function uhrTeam(db: Register, jetzt: number) {
  const laeufe = aktiveLaeufe(db);
  const offen = fragen(db, "offen");
  const tagBeginn = letzteUhrzeit(regelText("tag_grenze"), jetzt);
  return team(db, jetzt).map((t) => {
    const l = laeufe.find((x) => x.mitarbeiter === t.name);
    const a = l ? hole(db, "auftrag", String(l.auftrag_id)) : undefined;
    const ende = a?.schaetzung_min ? Number(l?.gestartet) + msAusMinuten(Number(a.schaetzung_min)) : a?.frist && Number(a.frist) > jetzt ? Number(a.frist) : null;
    const heute = beendeteLaeufe(db, t.name, tagBeginn);
    const verlauf = heute.slice(0, regelZahl("uhr_verlauf")).map((x) => [x.titel, sekundenAusMs(Number(x.beendet_um))]);
    if (l) return [t.name, t.zustand, t.satz, a?.projekt ?? a?.bereich ?? null, ende === null ? null : sekundenAusMs(ende), verlauf];
    if (offen.some((f) => f.von === t.name)) return [t.name, "wartet", null, null, null, verlauf];
    if (t.zustand === "frei" && heute.length) return [t.name, "fertig", null, null, sekundenAusMs(Number(heute[0].beendet_um)), verlauf];
    return [t.name, t.zustand, null, null, null, verlauf];
  });
}

export function uhrStand(db: Register, jetzt: number) {
  const braucht = brauchtDich(db, jetzt);
  const frage = braucht.find((f) => f.zustand === "offen" && uhrTauglich(f)) ?? vorschlagAnUhr(db);
  const r = ruhe(db, jetzt);
  return {
    t: jetzt, n: braucht.length,
    q: frage ? uhrFrage(db, frage, jetzt) : null,
    h: !frage && braucht.length ? "Wichtige Frage wartet. Lass uns am Mac darüber reden." : null,
    d: todos(db, "offen").slice(0, regelZahl("uhr_todos")).map((t) => [t.id, t.kurz_uhr ?? t.titel, t.bereich, t.dauer_min]),
    tm: uhrTeam(db, jetzt),
    tg: termineAm(db, jetzt).filter((t) => !t.ganztag && t.ende > jetzt).slice(0, regelZahl("uhr_termine"))
      .map((t) => [sekundenAusMs(t.start), sekundenAusMs(t.ende), t.titel, t.ort ?? null, istSport(t.titel) ? "s" : istFokus(t) ? "f" : "t", weg(db, t).los_ms === null ? null : sekundenAusMs(Number(weg(db, t).los_ms))]),
    z: r ? { g: r.grund, b: sekundenAusMs(r.bis) } : null,
    koerper: { schlaf: koerper(db, letzteUhrzeit(regelText("tag_grenze"), jetzt), r)?.schlaf ?? null },
    reg: { u: regelZahl("rueckgaengig_s"), a: regelZahl("uhr_abfrage_min"), q: regelZahl("uhr_warteschlange_max") },
  };
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
