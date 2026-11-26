import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob } from "../src/arbeitsdienst/jobs.ts";
import { ereignisse, hole, laeufe } from "../src/register/lesen.ts";
import { wertSetzen } from "../src/register/schreiben.ts";
import { ladePlugin, spaeter, um } from "./aufbau.ts";

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
});

test("PF01 nie „du“, wenn es nicht Antonio war", async () => {
  const p = ladePlugin();
  um("22:50");
  p.nachricht("agent:seneca:main", "m9", WORTLAUT, false);
  const r = await p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", { art: "auftrag", nachricht_kennung: "m9", wortlaut: WORTLAUT, an: "produkt", ziel: "x", abnahme: "y" });
  assert.match(String(r.fehler), /Antonios Nachricht/);
});
