import { aktiveLaeufe, auftraege, kostenSeit, ereignisse, faelligeWirkungen, fragen, hole, kinder, beendeteLaeufe, revision, spaeterBis, termineAm, todos, uhr, wert, werte, wiederholungenSeit, zurueckgenommen, type Zeile } from "../register/lesen.ts";
import { istFokus } from "./planen.ts";
import { aufgaben } from "./aufgaben.ts";
import { berichte, rueckblick, tagesZahlen } from "./berichte.ts";
import { erinnernUm, istSport, kalender, terminSicht } from "./kalender.ts";
import { buendelText, heute, koerper, projektVon, restMin, stundeAlsWort, ungefaehr, uhrzeit, ZAHLWORT } from "./heute.ts";
import { projekte } from "./projekte.ts";
import { weg, wochenplan } from "./wochenplan.ts";
import { verlauf } from "./verlauf.ts";
import { buendelFortschritt, entscheiden, fensterStart, optionenSicht } from "./entscheiden.ts";
import type { Register } from "../register/schema.ts";
import { appRegeln, letzteUhrzeit, msAusMinuten, naechsteUhrzeit, regelMs, regelText, regelZahl, sekundenAusMs } from "../regeln.ts";
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

function frageSicht(db: Register, f: Zeile, jetzt: number) {
  const g = JSON.parse(String(ereignisse(db, { art: "frage.gestellt", frage_id: String(f.id), grenze: 1 })[0]?.daten ?? "{}"));
  const bis = g.zeit_fuer ? erinnernUm(db, jetzt) : undefined;
  const zst = ereignisse(db, { art: "zustellung", frage_id: String(f.id) }).map((e) => ({ geraet: e.geraet, zeit: Number(e.zeit), ...JSON.parse(String(e.daten)) }));
  const halt = zst.find((z) => z.was === "zurueckgehalten"), frei = halt && zst.findLast((z) => z.zeit > halt.zeit && z.was !== "zurueckgehalten");
  return {
    id: f.id, text: f.text, kurz: g.kurz ?? null, zeit: bis ? `Bis ${new Date(bis).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" })} hast du Zeit für ${g.zeit_fuer}.` : null, von: anzeigeName(String(f.von)), projekt: projektVon(db, f.auftrag_id), seit: f.gestellt, art: f.art, wirkung_aussen: f.wirkung_aussen, ...optionenSicht(f),
    empfehlung: f.empfehlung, kontext: { worum: f.was_passiert_ist, wenn_nicht: f.wenn_nichts }, frist: f.frist, wirkt_ab: f.wirkt_ab, spaeter_bis: spaeterBis(db, String(f.id), jetzt),
    zustellung: zst, rueckfragen: g.rueckfragen ?? [], zurueckgehalten: frei ? `Bis ${stundeAlsWort(frei.zeit)} zurückgehalten${halt.grund === "fokus" ? ", weil du im Fokus warst" : ""}.` : null,
    antwort: f.antwort ? { wahl: f.antwort, geraet: f.antwort_geraet, zeit: f.antwort_um } : null, ...bericht(db, String(f.auftrag_id)),
    grund: g.grund ?? null, lage: g.lage ?? null, zusatz: g.zusatz ?? null, haengt: g.haengt ?? [],
    davor: heuteSaetze(db, String(f.von), letzteUhrzeit(regelText("tag_grenze"), jetzt)).slice(-regelZahl("mehr_davor")),
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
    const teil = l && ereignisse(db, { art: "befund", auftrag_id: String(l.auftrag_id) }).find((e) => JSON.parse(String(e.daten)).art === "teilergebnis");
    const pruef = l && kinder(db, String(l.auftrag_id)).filter((k) => k.arbeitsart === "pruefen" && k.zustand === "erledigt").sort((x, y) => Number(y.geaendert) - Number(x.geaendert))[0];
    const urteil = JSON.parse(String(pruef?.ergebnis ?? "{}"));
    return { name, zustand: l ? (l.zustand === "haengt" ? "hängt" : "arbeitet") : ruht ? "ruht" : "frei", satz: l?.letzter_schritt ?? null, seit: l?.gestartet ?? null,
      projekt: l ? projektVon(db, l.auftrag_id) : null, rest_min: l ? restMin(db, l, jetzt) : null,
      zuletzt: zuletzt ? { satz: zuletzt.letzter_schritt ?? zuletzt.titel, um: zuletzt.beendet_um } : null, auftrag_id: l?.auftrag_id ?? null, titel: l ? hole(db, "auftrag", String(l.auftrag_id))?.titel ?? null : null,
      schritte: l ? ereignisse(db, { art: "lauf.schritt", auftrag_id: String(l.auftrag_id), seit: Number(l.gestartet), grenze: regelZahl("team_schritte") }).reverse().map((e) => ({ um: e.zeit, satz: e.satz })) : [],
      ruht_seit: ruht ? ereignisse(db, { art: "wert.gesetzt", schluessel: `ruht:${name}`, grenze: 1 })[0]?.zeit ?? null : null,
      arbeit: l ? arbeitSicht(db, l, name, tagBeginn, jetzt) : null,
      teil: teil ? { satz: teil.satz, um: teil.zeit, beleg: teil.beleg ?? null } : null, ruecklauf: urteil.urteil === "nachbessern" ? { satz: `${anzeigeName(regelText("pruefer"))}: ${urteil.satz}`, um: pruef?.geaendert } : null };
  });
}

function arbeitSicht(db: Register, l: Zeile, name: string, tagBeginn: number, jetzt: number) {
  const a = hole(db, "auftrag", String(l.auftrag_id));
  const daten = (e: Zeile) => JSON.parse(String(e.daten ?? "{}"));
  const werkzeuge = ereignisse(db, { art: "lauf.werkzeug", lauf_id: String(l.id) }).reverse();
  const schritte = ereignisse(db, { art: "lauf.schritt", lauf_id: String(l.id) });
  const offen = fragen(db, "offen").filter((f) => f.auftrag_id === a.id).length;
  const dauer = Math.max(0, Math.round((jetzt - Number(a.erstellt)) / 60000));
  const w = (n: number) => ZAHLWORT[n] || String(n);
  const gross = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);
  const cent = (c: number) => `${(c / 100).toFixed(2).replace(".", ",")} €`;
  const danach = auftraege(db, ["bereit"]).find((x) => x.verantwortlich === name && x.id !== a.id);
  const rest = restMin(db, l, jetzt);
  return {
    kopf: [`${anzeigeName(name)} ${l.letzter_schritt ?? "arbeitet"}.`, rest ? `In etwa ${w(rest)} ${rest === 1 ? "Minute" : "Minuten"} ${a.pruefer_noetig ? `geht es an ${anzeigeName(regelText("pruefer"))}` : "ist es fertig"}.` : null],
    von: a.auftraggeber === "antonio" ? "dir" : anzeigeName(String(a.auftraggeber)), erteilt: a.erstellt,
    anteil: a.schaetzung_min ? Math.min(1, dauer / Number(a.schaetzung_min)) : null,
    minuten: a.schaetzung_min ? `${w(dauer)} von etwa ${w(Number(a.schaetzung_min))} Minuten` : `${w(dauer)} Minuten`,
    schritt: `Schritt ${w(schritte.length)} · seit ${uhrzeit(Number(schritte[0]?.zeit ?? l.gestartet))}`,
    naechstes: [daten(ereignisse(db, { art: "fortschreibung", auftrag_id: String(a.id), grenze: 1 })[0] ?? {}).naechster_schritt ?? null, danach ? `danach ${danach.titel}` : "danach nichts geplant"],
    wartet: offen ? ["Auf dich.", `${gross(w(offen))} ${offen === 1 ? "Frage" : "Fragen"} offen`] : ["Nichts. Kommt ohne dich weiter.", "keine Frage offen"],
    heute: heuteSaetze(db, name, tagBeginn),
    protokoll: werkzeuge.slice(-regelZahl("team_protokoll")).map((e) => ({ um: e.zeit, werkzeug: daten(e).werkzeug, satz: e.satz, ms: daten(e).ms })),
    zahlen: [`${dauer} Min Dauer`, `${schritte.length} Schritte`, `${(Number(l.tokens_ein ?? 0) + Number(l.tokens_aus ?? 0)).toLocaleString("de-DE").replace(/\./g, " ")} Tokens`,
      `${cent(Number(l.kosten_cent ?? 0))} von ${cent(Number(a.kostenrahmen_cent))}`],
    dateien: [...new Set(werkzeuge.filter((e) => /write|edit/i.test(daten(e).werkzeug)).map((e) => String(e.satz).split("/").at(-1)))],
  };
}

function heuteSaetze(db: Register, name: string, tagBeginn: number) {
  const mein = (e: Zeile) => !!e.auftrag_id && hole(db, "auftrag", String(e.auftrag_id))?.verantwortlich === name;
  return [...ereignisse(db, { art: "fortschreibung", seit: tagBeginn }), ...ereignisse(db, { art: "frage.gestellt", seit: tagBeginn })].filter(mein).sort((x, y) => Number(x.zeit) - Number(y.zeit))
    .map((e) => ({ um: e.zeit, frage_id: e.frage_id, satz: e.art === "fortschreibung" ? JSON.parse(String(e.daten ?? "{}")).letzter_stand : gefragt(JSON.parse(String(e.daten ?? "{}")).kurz, String(hole(db, "frage", String(e.frage_id)).text)) }));
}

function gefragt(kurz: string | undefined, text: string) {
  const w = kurz?.replace("?", "").split(" ")[0];
  return w ? `Dich nach ${/(ung|heit|keit|schaft|e)$/.test(w) ? "der" : "dem"} ${w} gefragt.` : `Dich gefragt: ${text}`;
}

function buendel(db: Register, braucht: Zeile[], jetzt: number) {
  const abnahmen = auftraege(db, ["wartet_auf_abnahme"]).filter((a) => a.auftraggeber === "antonio");
  const offen = fragen(db, "offen").filter((f) => !braucht.some((b) => b.id === f.id));
  return {
    fenster: fensterStart(jetzt), ...buendelText(abnahmen, offen.length), ...buendelFortschritt(db, abnahmen, jetzt),
    fragen: offen.map((f) => frageSicht(db, f, jetzt)),
  };
}

const ANZAHL = ["Keine", "Eine", "Zwei", "Drei", "Vier", "Fünf"];

function mitteilung(db: Register, f: Zeile, weitere: number) {
  const [z, vorher] = ereignisse(db, { art: "zustellung", frage_id: String(f.id), grenze: 2 }).map((e) => ({ geraet: e.geraet, ...JSON.parse(String(e.daten)) }));
  if (z?.geraet !== "iphone" || z.was !== "zugestellt") return null;
  const g = JSON.parse(String(ereignisse(db, { art: "frage.gestellt", frage_id: String(f.id), grenze: 1 })[0]?.daten ?? "{}"));
  const o = (JSON.parse(String(f.optionen)) as { wert: string; folge: string }[]).find((x) => x.wert === f.empfehlung) ?? JSON.parse(String(f.optionen))[0];
  return { titel: `${vorher?.was === "zurueckgehalten" && vorher.grund === "fokus" ? "Fokus vorbei · " : ""}${g.kurz ?? f.text}`,
    text: `${o.folge}${weitere ? ` Dazu ${weitere === 1 ? "wartet eine weitere Frage" : `warten ${ANZAHL[weitere]?.toLowerCase() ?? weitere} weitere Fragen`}.` : ""}` };
}

function wartetSatz(db: Register, offen: Zeile[]): string | null {
  const von = [...new Set(offen.map((f) => String(f.von)))];
  const viele = von.map((v) => [anzeigeName(v), offen.filter((f) => f.von === v)] as const).sort((a, b) => b[1].length - a[1].length)[0];
  if (!viele) return null;
  const [name, fs] = viele;
  const wo = fs.map((f) => [String(JSON.parse(String(ereignisse(db, { art: "frage.gestellt", frage_id: String(f.id), grenze: 1 })[0]?.daten ?? "{}")).kurz ?? "").replace(/\?$/, ""), f] as const)
    .filter(([k]) => k).sort(([, a], [, b]) => Number(uhrTauglich(b)) - Number(uhrTauglich(a))).map(([k, f]) => uhrTauglich(f) ? `${k} kommt auf die Uhr, sobald du unterwegs bist` : `${k} ins Fenster um ${regelText("fenster").split(" ")[0]}`);
  return `${ANZAHL[fs.length] ?? fs.length} ${fs.length === 1 ? "Frage" : "Fragen"} von ${name} ${fs.length === 1 ? "wartet" : "warten"} noch.${wo.length ? ` ${wo.join(", ")}.` : ""}`;
}

export function stand(db: Register, eingabe: { geraet: string; revision?: number }, jetzt: number) {
  const rev = revision(db);
  if (eingabe.revision === rev) return { schema: SCHEMA, revision: rev, jetzt, unveraendert: true };
  const braucht = brauchtDich(db, jetzt);
  const tagBeginn = letzteUhrzeit(regelText("tag_grenze"), jetzt);
  const b = buendel(db, braucht, jetzt);
  const aufg = aufgaben(db, ruhe(db, jetzt), tagBeginn, jetzt);
  const inhalt = {
    schema: SCHEMA, revision: rev, jetzt, erzeugt: jetzt, geraet: eingabe.geraet, tag_beginn: tagBeginn,
    regeln: appRegeln(),
    zaehler: { braucht: braucht.length },
    wartet: wartetSatz(db, [...braucht, ...fragen(db, "offen").filter((f) => !braucht.some((x) => x.id === f.id))].filter((f) => f.zustand === "offen")),
    ruhe: ruhe(db, jetzt) ?? null,
    heute: heute(db, ruhe(db, jetzt), jetzt),
    koerper: koerper(db, tagBeginn, ruhe(db, jetzt)),
    vorbei: ["abgelaufen", "zurueckgezogen"].flatMap((z) => fragen(db, z)).map((f) => ({ id: f.id, text: f.text, zustand: f.zustand, frist: f.frist, satz: f.grund,
      um: Number(ereignisse(db, { art: "uebergang", frage_id: String(f.id), grenze: 1 })[0]?.zeit) })).filter((f) => f.um >= tagBeginn),
    team_kopf: ["Dein Team,", `um ${ungefaehr(jetzt)}.`],
    braucht_dich: braucht.map((f) => ({ ...frageSicht(db, f, jetzt), mitteilung: mitteilung(db, f, braucht.length - 1) })),
    todo_vorschlag: (wert(db, "todo_vorschlag")?.gueltig_bis ?? 0) > jetzt ? JSON.parse(String(wert(db, "todo_vorschlag")?.wert)) : null,
    eben_beantwortet: fragen(db, "beantwortet").filter((f) => Number(f.antwort_um) > jetzt - regelMs("frage_nachklang_s")).map((f) => frageSicht(db, f, jetzt)),
    buendel: b,
    projekte: projekte(db, jetzt, ruhe(db, jetzt)?.grund === "fokus"),
    entscheiden: entscheiden(db, braucht.length + b.fragen.length, b.abnahmen.length > 0, tagBeginn, jetzt),
    team: team(db, jetzt).map((t) => ({ ...t, id: t.name, name: anzeigeName(t.name) })),
    gelernt: ereignisse(db, { art: "korrektur", seit: tagBeginn }).filter((e) => !zurueckgenommen(db, Number(e.nr))).map((e) => ({ nr: e.nr, zeile: e.satz, zeit: e.zeit })),
    auftraege_neu: auftraege(db, ["bereit", "laeuft", "wartet"]).filter((a) => a.auftraggeber === "antonio" && jetzt - Number(a.erstellt) < regelMs("auftrag_quittung_min"))
      .map((a) => ({ id: a.id, titel: a.titel, ziel: a.ziel, wer: a.verantwortlich, pruefer: !!a.pruefer_noetig, erteilt: a.erstellt,
        bis: a.schaetzung_min ? Number(a.erstellt) + msAusMinuten(Number(a.schaetzung_min)) : null, dauer_min: a.schaetzung_min,
        danach: a.abnahme_durch === "antonio" ? `${a.pruefer_noetig ? "Prüfer schaut drüber, dann kommt es" : "Es kommt"} als Abnahme ins Fenster um ${regelText("fenster").split(" ")[0]}` : "Fertig ohne Abnahme" })),
    heute_erledigt: auftraege(db, ["erledigt"]).filter((a) => Number(a.geaendert) >= tagBeginn).map((a) => ({ id: a.id, titel: a.titel, ergebnis: JSON.parse(String(a.ergebnis ?? "null")),
      wer: anzeigeName(String(a.verantwortlich)), pruefer: !!a.pruefer_noetig, min: Math.round((Number(a.geaendert) - Number(a.erstellt)) / 60000), kosten_cent: kostenSeit(db, 0, { auftrag_id: String(a.id) }) })),
    termine: termineAm(db, jetzt).map((t) => ({ ...terminSicht(db, t), weg: weg(db, t).kurz })),
    wochenplan: wochenplan(db, jetzt),
    verlauf: verlauf(db, tagBeginn, jetzt),
    aufgaben: aufg,
    berichte: berichte(db, tagBeginn, jetzt),
    rueckblick: rueckblick(db, tagBeginn),
    kalender: kalender(db, ruhe(db, jetzt), b, aufg.gruppe, jetzt),
    todos: todos(db, "offen").map((t) => ({ id: t.id, titel: t.titel, bereich: t.bereich,
      tag: t.tag, bis_wann: t.bis_wann, dauer_min: t.dauer_min, geschaetzt: t.geschaetzt, geplant_von: t.geplant_von, geplant_bis: t.geplant_bis, wiederkehrend: t.wiederkehrend,
      wichtig: !!t.wichtig, oeffnet: t.oeffnet, notiz: t.notiz, anhang: t.anhang, verschoben: t.verschoben_anzahl, revision: t.revision,
      grund: ((w) => (w && (w.gueltig_bis ?? 0) > jetzt ? JSON.parse(w.wert) : null))(wert(db, `todo_grund:${t.id}`)) })),
    hinweise: [...werte(db, "hinweis:").keys()].map((k) => wert(db, k)).filter((w) => w?.wert && (w.gueltig_bis ?? Infinity) > jetzt).map((w) => w?.wert),
    kopplung: [...werte(db, "kopplung:").keys()].filter((k) => k !== "kopplung:fenster").map((k) => ({ k, w: wert(db, k) })).filter(({ w }) => w && (w.gueltig_bis ?? Infinity) > jetzt)
      .map(({ k, w }) => ({ geraet: k.slice("kopplung:".length), ...JSON.parse(String(w?.wert)) })).filter((k) => !k.bestaetigt).map((k) => ({ geraet: k.geraet, zahl: k.zahl })),
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
  const r = ruhe(db, jetzt), start = wert(db, "uhr:starten");
  return {
    t: jetzt, n: braucht.length,
    q: frage ? uhrFrage(db, frage, jetzt) : null,
    h: !frage && braucht.length ? "Wichtige Frage wartet. Lass uns am Mac darüber reden." : null,
    d: todos(db, "offen").slice(0, regelZahl("uhr_todos")).map((t) => [t.id, t.kurz_uhr ?? t.titel, t.bereich, t.dauer_min]),
    tm: uhrTeam(db, jetzt),
    tg: termineAm(db, jetzt).filter((t) => !t.ganztag && t.ende > jetzt).slice(0, regelZahl("uhr_termine"))
      .map((t) => [sekundenAusMs(t.start), sekundenAusMs(t.ende), t.titel, t.ort ?? null, istSport(t.titel) ? "s" : istFokus(t) ? "f" : "t", weg(db, t).los_ms === null ? null : sekundenAusMs(Number(weg(db, t).los_ms))]),
    z: r ? { g: r.grund, b: sekundenAusMs(r.bis) } : null,
    st: (start?.gueltig_bis ?? 0) > jetzt ? [start?.wert, sekundenAusMs(Number(start?.gueltig_bis))] : null,
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
  if (was === "tag") return tagSicht(db, jetzt);
  if (was === "team") return team(db, jetzt).map((t) => `${t.name}: ${t.zustand}${t.satz ? `, ${t.satz}` : ""}`).join("\n");
  if (was === "fragen") return brauchtDich(db, jetzt).map((f) => `${f.id}: ${f.text}`).join("\n") || "Nichts braucht Antonio gerade.";
  const praefix = { profil: "profil:", fakten: "fakt:", kontakt: "kontakt:" }[was];
  if (!praefix) throw new Error(`seneca_lesen kennt ${was} nicht.`);
  return [...werte(db, praefix)].map(([k, v]) => `${k}: ${v}`).join("\n") || "Nichts hinterlegt.";
}

const ZEITFELDER = ["jetzt", "start", "ende", "geplant", "zeit", "bis", "von", "um"];

function tagSicht(db: Register, jetzt: number): string {
  const s = stand(db, { geraet: "seneca" }, jetzt) as Exclude<ReturnType<typeof stand>, { unveraendert: boolean }>;
  const gestern = s.tag_beginn - regelMs("ein_tag_tage");
  const zeit = (k: string, v: unknown) => (ZEITFELDER.includes(k) && typeof v === "number" ? new Date(v).toLocaleString("de-DE", { weekday: "short", hour: "2-digit", minute: "2-digit" }) : v);
  return JSON.stringify({
    revision: s.revision, jetzt, satz: s.heute.satz, aufgaben: s.aufgaben.satz, braucht_dich: s.zaehler.braucht, wartet: s.wartet, ruhe: s.ruhe, entscheiden: s.entscheiden.satz, buendel: s.buendel.satz,
    todos: s.todos.filter((t) => !t.wiederkehrend).map((t) => ({ titel: t.titel, bereich: t.bereich, tag: t.tag, ueberfaellig: !!t.tag && String(t.tag) < new Date(s.tag_beginn).toLocaleDateString("sv-SE"), dauer_min: t.dauer_min, geplant: t.geplant_von, wichtig: t.wichtig })),
    jeden_tag: s.aufgaben.jeden_tag?.map((t) => `${t.titel}${t.erledigt ? " (erledigt)" : ""}`), erledigt: [...s.aufgaben.erledigt.map((t) => t.titel), ...s.heute_erledigt.map((a) => `${a.titel} (${a.wer})`)],
    termine: s.termine.map((t) => ({ titel: t.titel, start: t.start, ende: t.ende, ganztag: t.ganztag, ort: t.ort ?? null, mit: t.mit, weg: t.weg })),
    morgen: termineAm(db, s.tag_beginn + regelMs("ein_tag_tage")).map((t) => ({ titel: t.titel, start: t.start, ganztag: t.ganztag })),
    koerper: s.koerper, zahlen_heute: tagesZahlen(db, s.tag_beginn), gelernt: s.gelernt.map((g) => g.zeile), wiederholungen_heute: wiederholungenSeit(db, s.tag_beginn), team: s.team.map((t) => `${t.name}: ${t.zustand}${t.satz ? `, ${t.satz}` : ""}`),
    auftraege_seit_gestern: auftraege(db, ["bereit", "laeuft", "wartet", "wartet_auf_abnahme", "erledigt"]).filter((a) => a.quelle !== "dauerauftrag" && Number(a.geaendert) >= gestern)
      .map((a) => ({ id: a.id, titel: a.titel, zustand: a.zustand, wer: anzeigeName(String(a.verantwortlich)), stand: a.letzter_stand, naechster: a.naechster_schritt, beleg: bericht(db, String(a.id)).bericht?.beleg ?? null })),
  }, zeit);
}
