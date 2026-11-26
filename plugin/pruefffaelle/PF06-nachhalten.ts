import assert from "node:assert/strict";
import { test } from "node:test";
import { hole } from "../src/register/lesen.ts";
import { laufAnlegen, uebergang } from "../src/register/schreiben.ts";
import { auftragVonAntonio, frischesRegister, um } from "./aufbau.ts";

test("PF06 wartet nur mit Folge und Nachfasszeit", () => {
  const db = frischesRegister();
  const t = um("10:00");
  const auftrag = auftragVonAntonio(db, "Frag Nora nach den Zahlen");
  laufAnlegen(db, { auftrag_id: auftrag, mitarbeiter: "produkt", anlass: "neu", art: "werkzeug", ort: "server", stufe: "sonnet", modell: "m" });
  assert.throws(() => uebergang(db, "auftrag", auftrag, "wartet", "fortschreibung", { wartet_auf: "extern:nora" }), /folge, naechster_anlass/);
  assert.equal(hole(db, "auftrag", auftrag).zustand, "laeuft");
  uebergang(db, "auftrag", auftrag, "wartet", "fortschreibung", { wartet_auf: "extern:nora", folge: "Zahlen fehlen am Freitag", naechster_anlass: t + 3600000 });
  assert.equal(hole(db, "auftrag", auftrag).zustand, "wartet");
  assert.throws(() => uebergang(db, "auftrag", auftrag, "erledigt", "falsch"), /nicht erlaubt/);
});
