import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { faelligeAuftraegeJob } from "../src/arbeitsdienst/jobs.ts";
import { auftraege, ereignisse, laeufe, wert } from "../src/register/lesen.ts";
import { auftragVonAntonio, ladePlugin, spaeter, um } from "./aufbau.ts";

const S = "agent:seneca:main";

test("PF09 Korrektur ändert genau eine Stelle, ist zurücknehmbar, Wiederholung wird gezählt, Skill steht im Start-Kontext", async () => {
  const p = ladePlugin();
  um("10:00");
  const zaehle = () => ereignisse(p.db, { grenze: -1 }).filter((e) => ["wert.gesetzt", "auftrag.angelegt"].includes(String(e.art))).length;
  p.nachricht(S, "m1", "Schick Links immer mit, bitte immer mit Link");
  const vorher = zaehle();
  const r = await p.werkzeug("seneca_lernen", S, "seneca", { nachricht_kennung: "m1", wortlaut: "immer mit Link", ort: "profil", ziel: "Links in Antworten", kern: "immer mit Link", aenderung: { schluessel: "profil:links", wert: "immer" } });
  assert.match(r.zeile, /^Gelernt: /);
  assert.equal(zaehle() - vorher, 1);
  assert.equal(wert(p.db, "profil:links")?.wert, "immer");
  p.methode("seneca.handeln", { kennung: "z1", geraet: "iphone", art: "lernen.zuruecknehmen", ziel: String(r.korrektur_nr) });
  assert.equal(wert(p.db, "profil:links")?.wert, "");
  p.nachricht(S, "m2", "Keine Mails an Kunden nach 20 Uhr");
  const vorSperre = auftraege(p.db, ["bereit"]).length;
  await p.werkzeug("seneca_lernen", S, "seneca", { nachricht_kennung: "m2", wortlaut: "Keine Mails an Kunden nach 20 Uhr", ort: "sperre", ziel: "Ausgang Mail", kern: "keine Kundenmail nach 20 Uhr", aenderung: {} });
  assert.equal(auftraege(p.db, ["bereit"]).length - vorSperre, 1);
  p.nachricht(S, "m3", "Wie oft noch: immer mit Link");
  const w = await p.werkzeug("seneca_lernen", S, "seneca", { nachricht_kennung: "m3", wortlaut: "Wie oft noch: immer mit Link", ort: "skill", ziel: "mail_an_kunden", kern: "immer mit Link", aenderung: { skill: "mail_an_kunden", alt: "Schritt 3: kurz.", neu: "Schritt 3: kurz, immer mit Link." } });
  assert.equal(Number(w.wiederholungen_woche), 1);
  assert.ok(auftraege(p.db, ["bereit"]).some((a) => String(a.titel).startsWith("Wiederholung untersuchen")));
  const arbeitsplatz = mkdtempSync(join(tmpdir(), "seneca-ws-"));
  mkdirSync(join(arbeitsplatz, "skills", "mail_an_kunden"), { recursive: true });
  writeFileSync(join(arbeitsplatz, "skills", "mail_an_kunden", "SKILL.md"), "Schritt 3: kurz, immer mit Link.");
  const a = auftragVonAntonio(p.db, "Mail an Kunden zum Angebot", { arbeitsart: "mail_an_kunden" });
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.ok(p.kontext(String(laeufe(p.db, a)[0].sitzung), arbeitsplatz)?.includes("Schritt 3: kurz, immer mit Link."));
});
