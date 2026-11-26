import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob } from "../src/arbeitsdienst/jobs.ts";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { kalenderAbgleich } from "../src/quellen/kalender.ts";
import { ereignisse, laeufe, termineAm } from "../src/register/lesen.ts";
import { auftragVonAntonio, kalenderAttrappe, ladePlugin, spaeter, um } from "./aufbau.ts";

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

test("PF10 „Verschieb den Zahnarzt“ wirkt ohne Mac; Konflikt wird gemeldet, nicht überschrieben", async () => {
  const morgen = (hhmm: string) => new Date(`2026-11-28T${hhmm}:00`).getTime();
  const ics = (uid: string, titel: string, von: string, bis: string) =>
    `BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:${uid}\r\nSUMMARY:${titel}\r\nDTSTART:${new Date(morgen(von)).toISOString().replace(/[-:]/g, "").slice(0, 15)}Z\r\nDTEND:${new Date(morgen(bis)).toISOString().replace(/[-:]/g, "").slice(0, 15)}Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n`;
  const attrappe = await kalenderAttrappe(new Map([["zahn", ics("zahn", "Zahnarzt", "10:00", "11:00")], ["call", ics("call", "Call Nora", "14:30", "15:00")]]));
  const kopie = join(mkdtempSync(join(tmpdir(), "regeln-")), "regeln");
  writeFileSync(kopie, readFileSync(new URL("../../regeln", import.meta.url), "utf8").replace(/^caldav_url .*$/m, `caldav_url ${attrappe.url}`));
  process.env.SENECA_REGELN = kopie;
  const zugang = { benutzer: "antonio", passwort: "app-passwort" };
  const p = ladePlugin(undefined, { kalender: zugang });
  um("20:00");
  await kalenderAbgleich(p.db, zugang);
  assert.deepEqual(termineAm(p.db, morgen("00:00")).map((t) => t.titel), ["Zahnarzt", "Call Nora"]);
  const konflikt = await p.werkzeug("seneca_kalender", "agent:seneca:main", "seneca", { aktion: "verschieben", uid: "zahn", start: morgen("14:00"), ende: morgen("15:00") });
  assert.deepEqual(konflikt.konflikte, ["Call Nora"]);
  assert.ok(!attrappe.aufrufe.some((a) => a.startsWith("PUT")));
  const r = await p.werkzeug("seneca_kalender", "agent:seneca:main", "seneca", { aktion: "verschieben", uid: "zahn", start: morgen("16:00"), ende: morgen("17:00") });
  assert.equal(r.ok, true);
  assert.equal(termineAm(p.db, morgen("00:00")).find((t) => t.uid === "zahn")?.start, morgen("16:00"));
  assert.match(String((await p.werkzeug("seneca_kalender", "agent:produkt:main", "produkt", { aktion: "anlegen", start: morgen("18:00") })).fehler), /Nur Seneca/);
  delete process.env.SENECA_REGELN;
  attrappe.server.close();
});
