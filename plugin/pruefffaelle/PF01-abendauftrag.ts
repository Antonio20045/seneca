import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob, pflegenJob } from "../src/arbeitsdienst/jobs.ts";
import { auftraege, ereignisse, hole, laeufe } from "../src/register/lesen.ts";
import { auftragSetzen, wertSetzen } from "../src/register/schreiben.ts";
import { uhr } from "../src/register/lesen.ts";
import { zustellenJob } from "../src/pforte/zustellen.ts";
import { ladePlugin, nurWach, spaeter, um } from "./aufbau.ts";

const WORTLAUT = "Verschaff dir einen Überblick und setz um, was fehlt";

test("PF01 Abendauftrag: Wortlaut in jedem Lauf, Teil 2 ohne Eingabe, ohne Stand nie fertig", async () => {
  const p = ladePlugin();
  um("22:43");
  wertSetzen(p.db, "abo_limit:anthropic:sundartha", "90000000", "test");
  p.nachricht("agent:seneca:main", "m1", `Hey Seneca. ${WORTLAUT}. Danke!`);
  const r = await p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", {
    art: "auftrag", nachricht_kennung: "m1", wortlaut: WORTLAUT, an: "produkt", ziel: "Fehlendes umgesetzt", abnahme: "Liste mit Belegen", schaetzung_min: 60,
  });
  assert.match(r.satz, /1,20 €/);
  const id = r.auftrag_id;
  assert.equal(hole(p.db, "auftrag", id).quelle, "du");
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(p.starts.length, 1);
  const erster = laeufe(p.db, id)[0];
  assert.equal(erster.abo, "anthropic:sundartha");
  assert.ok(p.kontext(p.starts[0].sessionKey)?.includes(WORTLAUT));
  p.ende(p.starts[0].sessionKey);
  assert.equal(hole(p.db, "lauf", String(erster.id)).zustand, "abgebrochen");
  assert.equal(hole(p.db, "auftrag", id).zustand, "bereit");
  assert.equal(ereignisse(p.db, { art: "befund", auftrag_id: id }).length, 1);
  spaeter(61000);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(p.starts.length, 2);
  assert.notEqual(p.starts[1].sessionKey, p.starts[0].sessionKey);
  const k2 = p.kontext(p.starts[1].sessionKey) ?? "";
  assert.ok(k2.includes(WORTLAUT) && k2.includes("ohne Fortschreibung"));
  await p.werkzeug("seneca_fortschreiben", p.starts[1].sessionKey, "produkt", { letzter_stand: "Teil 1 fertig", naechster_schritt: "Teil 2", ergebnis: "weiter", schritt_nr: 1, schritt_gesamt: 2 });
  p.ende(p.starts[1].sessionKey);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(p.starts.length, 3);
  assert.ok(p.kontext(p.starts[2].sessionKey)?.includes(WORTLAUT));
  await p.werkzeug("seneca_fortschreiben", p.starts[2].sessionKey, "produkt", { letzter_stand: "Alles umgesetzt", naechster_schritt: "Abnahme", ergebnis: "fertig", beleg: "PR #12" });
  p.ende(p.starts[2].sessionKey);
  assert.equal(hole(p.db, "auftrag", id).zustand, "wartet_auf_abnahme");
  assert.ok(laeufe(p.db, id).every((l) => l.anlass));
  const zeilen: string[][] = [];
  const poste = async (sitzung: string, text: string) => (zeilen.push([sitzung, text]), "posted");
  await zustellenJob(p.db, undefined, poste);
  await zustellenJob(p.db, undefined, poste);
  assert.equal(zeilen.length, 1);
  assert.equal(zeilen[0][0], "agent:seneca:main");
  assert.match(zeilen[0][1], new RegExp(`fertig mit „${WORTLAUT}“: Alles umgesetzt\nBeleg: PR #12 · Auftrag ${id} · unter Entscheiden`));
});

test("PF01 nie „du“, wenn es nicht Antonio war", async () => {
  const p = ladePlugin();
  um("22:50");
  p.nachricht("agent:seneca:main", "m9", WORTLAUT, false);
  const r = await p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", { art: "auftrag", nachricht_kennung: "m9", wortlaut: WORTLAUT, an: "produkt", ziel: "x", abnahme: "y" });
  assert.match(String(r.fehler), /Antonios Nachricht/);
});

test("PF01 Briefing und Rückblick: Daten aus dem Register, Text in Berichte und Heute", async () => {
  const p = ladePlugin();
  um("05:00");
  pflegenJob(p.db, p.ordner);
  nurWach(p.db, "seneca");
  const todo = (felder: object) => p.werkzeug("seneca_todo", "agent:seneca:main", "seneca", { aktion: "anlegen", felder });
  await todo({ titel: "Steuerberater anrufen", bereich: "Privat", tag: "2026-11-20" });
  await todo({ titel: "Lesen", bereich: "Privat", wiederkehrend: "taeglich" });
  const sitzung = async (arbeitsart: string) => {
    const a = auftraege(p.db, ["bereit"]).find((x) => x.arbeitsart === arbeitsart);
    for (const x of auftraege(p.db, ["bereit"])) auftragSetzen(p.db, String(x.id), { naechster_anlass: uhr.jetzt() + (x.id === a?.id ? 0 : 86400000) }, "PF01");
    await faelligeAuftraegeJob(p.db, p.starte);
    return String(laeufe(p.db, String(a?.id))[0].sitzung);
  };
  um("06:40");
  const lauf = await sitzung("briefing");
  const tag = JSON.parse(String(await p.werkzeug("seneca_lesen", lauf, "seneca", { was: "tag" })));
  assert.deepEqual(tag.satz, ["Ein To-do.", "Der Rest des Tages gehört dir."]);
  assert.deepEqual(tag.todos.map((t: { titel: string; ueberfaellig: boolean }) => [t.titel, t.ueberfaellig]), [["Steuerberater anrufen", true]]);
  assert.deepEqual(tag.jeden_tag, ["Lesen"]);
  const text = "Guten Morgen. Ein freier Tag, der Steuerberater ist seit einer Woche überfällig.";
  await p.werkzeug("seneca_fortschreiben", lauf, "seneca", { letzter_stand: text, naechster_schritt: "Morgen 06:40", ergebnis: "fertig", beleg: `seneca_lesen tag, Revision ${tag.revision}` });
  p.ende(lauf);
  const s = p.methode("seneca.stand", { geraet: "iphone" }) as { berichte: { satz: string[]; seneca: { text: string } }; rueckblick: unknown };
  assert.equal(s.berichte.seneca.text, text);
  assert.deepEqual(s.berichte.satz, ["Nichts ist neu."]);
  assert.equal(s.rueckblick, null);
  um("21:30");
  const abend = await sitzung("rueckblick");
  await p.werkzeug("seneca_fortschreiben", abend, "seneca", { letzter_stand: "Ein ruhiger Tag. Über Nacht läuft nichts. Morgen zuerst: der Steuerberater.", naechster_schritt: "Morgen 21:30", ergebnis: "fertig", beleg: "seneca_lesen tag" });
  p.ende(abend);
  const r = (p.methode("seneca.stand", { geraet: "iphone" }) as { rueckblick: { saetze: string[] } }).rueckblick;
  assert.deepEqual(r.saetze, ["Ein ruhiger Tag.", "Über Nacht läuft nichts.", "Morgen zuerst: der Steuerberater."]);
});
