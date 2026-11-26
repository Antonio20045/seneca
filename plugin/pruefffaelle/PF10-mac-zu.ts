import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob } from "../src/arbeitsdienst/jobs.ts";
import { ereignisse, laeufe } from "../src/register/lesen.ts";
import { auftragVonAntonio, ladePlugin, spaeter, um } from "./aufbau.ts";

test("PF10 Mac zu: Textarbeit mit Stufe lokal läuft auf Haiku am Server, kein Doppellauf, kein Befund „Mac nicht erreichbar“", async () => {
  const p = ladePlugin();
  um("23:10");
  const a = auftragVonAntonio(p.db, "Fasse das Meeting zusammen", { verantwortlich: "seneca", arbeitsart: "zusammenfassen" });
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  await faelligeAuftraegeJob(p.db, p.starte);
  const l = laeufe(p.db, a);
  assert.equal(l.length, 1);
  assert.equal(l[0].stufe, "haiku");
  assert.equal(l[0].ort, "server");
  assert.match(p.starts[0].model, /haiku/);
  assert.ok(!ereignisse(p.db, { art: "befund" }).some((b) => String(b.satz).includes("Mac")));
});
