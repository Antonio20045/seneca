import assert from "node:assert/strict";
import { test } from "node:test";
import { auftraege, hole, laeufe } from "../src/register/lesen.ts";
import { auftragVonAntonio, jaNeinFrage, ladePlugin, um } from "./aufbau.ts";

const ALLE = ["vorgeschlagen", "geparkt", "bereit", "laeuft", "wartet", "wartet_auf_abnahme", "erledigt", "verworfen"];

test("PF02 Sachfrage und „Ja“ legen keinen Auftrag an", async () => {
  const p = ladePlugin();
  um("10:00");
  const auftrag = auftragVonAntonio(p.db, "Instagram-Konto für Hermes anlegen");
  const frage = jaNeinFrage(p.db, auftrag, "Instagram-Konto anlegen?");
  const vorher = auftraege(p.db, ALLE).length;
  p.nachricht("agent:seneca:main", "m1", "Wie weit ist das Angebot?");
  assert.equal(auftraege(p.db, ALLE).length, vorher);
  p.nachricht("agent:seneca:main", "m2", "Ja");
  const r = await p.werkzeug("seneca_frage", "agent:seneca:main", "seneca", { art: "antwort", frage_id: frage, antwort: "ja", nachricht_kennung: "m2" });
  assert.equal(r.ergebnis, "angenommen");
  assert.equal(hole(p.db, "frage", frage).zustand, "beantwortet");
  const versuch = await p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", { art: "auftrag", nachricht_kennung: "m2", wortlaut: "Ja", an: "produkt", ziel: "x", abnahme: "y" });
  assert.match(String(versuch.fehler), /schon eine Antwort/);
  const nochmal = await p.werkzeug("seneca_frage", "agent:seneca:main", "seneca", { art: "antwort", frage_id: frage, antwort: "nein", nachricht_kennung: "m2" });
  assert.equal(nochmal.ergebnis, "schon_beantwortet");
  assert.equal(auftraege(p.db, ALLE).length, vorher);
  assert.equal(laeufe(p.db, auftrag).length, 0);
});
