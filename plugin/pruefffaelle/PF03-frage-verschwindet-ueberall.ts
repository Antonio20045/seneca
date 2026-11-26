import assert from "node:assert/strict";
import { test } from "node:test";
import { fragen, hole, revision } from "../src/register/lesen.ts";
import { frageBeantworten, handlung, uebergang } from "../src/register/schreiben.ts";
import { auftragVonAntonio, frischesRegister, jaNeinFrage, spaeter, um } from "./aufbau.ts";

test("PF03 Uhr zuerst, iPhone zwei Sekunden später: genau eine Antwort wirkt", () => {
  const db = frischesRegister();
  um("13:50");
  const frage = jaNeinFrage(db, auftragVonAntonio(db, "Instagram-Konto anlegen"), "Instagram anlegen?");
  const vorher = revision(db);
  const uhrAntwort = () => frageBeantworten(db, { frage_id: frage, antwort: "ja", geraet: "uhr", kennung: "u1", lokal: true }).ergebnis;
  assert.equal(handlung(db, { kennung: "u1", geraet: "uhr", art: "frage.antwort", ziel: frage }, uhrAntwort), "angenommen");
  assert.equal(handlung(db, { kennung: "u1", geraet: "uhr", art: "frage.antwort", ziel: frage }, uhrAntwort), "doppelt");
  spaeter(2000);
  const zweite = frageBeantworten(db, { frage_id: frage, antwort: "nein", geraet: "iphone", kennung: "i1" });
  assert.deepEqual(zweite, { ergebnis: "schon_beantwortet", wahl: "ja", geraet: "uhr", um: um("13:50") });
  assert.equal(hole(db, "frage", frage).antwort, "ja");
  assert.ok(revision(db) > vorher);
  assert.equal(fragen(db, "offen").length, 0);
});

test("PF03 Frage eines erledigten Auftrags bleibt nicht offen", () => {
  const db = frischesRegister();
  um("09:00");
  const auftrag = auftragVonAntonio(db, "Angebot schreiben");
  const frage = jaNeinFrage(db, auftrag, "Angebot so senden?");
  const neue = jaNeinFrage(db, auftrag, "Angebot mit Rabatt senden?");
  assert.equal(hole(db, "frage", frage).zustand, "ersetzt");
  uebergang(db, "auftrag", auftrag, "verworfen", "auftrag.verwerfen");
  assert.equal(hole(db, "frage", neue).zustand, "zurueckgezogen");
  assert.ok(String(hole(db, "frage", neue).grund).length > 0);
});
