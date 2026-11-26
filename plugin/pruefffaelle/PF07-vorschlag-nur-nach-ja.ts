import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob, faelligeWirkungenJob } from "../src/arbeitsdienst/jobs.ts";
import { auftraege, ereignisse, fragen, laeufe, todos } from "../src/register/lesen.ts";
import { frageBeantworten } from "../src/register/schreiben.ts";
import { auftragVonAntonio, ladePlugin, spaeter, um } from "./aufbau.ts";

test("PF07 Meeting-Zusage wird erst nach Ja ein Auftrag; WhatsApp nur gelesen", async () => {
  const p = ladePlugin();
  um("15:00");
  p.methode("seneca.handeln", { kennung: "h1", geraet: "mac", art: "eingang.meeting", wert: "Ablage/Meetings/call-nora.md" });
  p.empfangen("whatsapp", "wa1", "+491709876543");
  const eingang = auftragVonAntonio(p.db, "Eingang sortieren", { verantwortlich: "seneca" });
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  const sitzung = String(laeufe(p.db, eingang)[0].sitzung);
  const vorherAuftraege = auftraege(p.db, ["bereit", "laeuft", "wartet"]).length;
  const r = await p.werkzeug("seneca_auftrag", sitzung, "seneca", {
    art: "vorschlag", wortlaut: "Nora: Zahlen bis Freitag", titel: "Zugesagt: Zahlen bis Freitag. Nachhalten", ziel: "Zahlen von Nora liegen vor", abnahme: "Zahlen im Ordner", an: "seneca",
  });
  assert.equal(auftraege(p.db, ["bereit", "laeuft", "wartet"]).length, vorherAuftraege);
  assert.equal(todos(p.db, "offen").length, 0);
  const vorschlag = fragen(p.db, "offen").find((f) => f.art === "vorschlag");
  assert.ok(vorschlag);
  frageBeantworten(p.db, { frage_id: String(vorschlag.id), antwort: "ja", geraet: "uhr", kennung: "u1", lokal: true });
  faelligeWirkungenJob(p.db);
  assert.equal(auftraege(p.db, ["bereit"]).filter((a) => a.id === r.auftrag_id).length, 1);
  assert.equal(ereignisse(p.db, { art: "eingang" }).length, 2);
  assert.ok(!JSON.stringify(ereignisse(p.db, { art: "eingang" })).includes("geheim"));
  assert.ok(p.aufruf(sitzung, "mcp__whatsapp__send_message", { to: "+491709876543" })?.block);
});
