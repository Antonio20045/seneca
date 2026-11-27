import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { gespraecheJob } from "../src/arbeitsdienst/jobs.ts";
import { eintragSetzen } from "../src/register/schreiben.ts";
import { regelZahl } from "../src/regeln.ts";
import { ladePlugin, regelnMit, um } from "./aufbau.ts";

test("PF11 große Historie: Stand bleibt klein, trägt Schema und Revision, unveränderte Revision liefert nichts", () => {
  const p = ladePlugin();
  const t = um("06:42");
  for (let i = 0; i < 10000; i++) eintragSetzen(p.db, { art: "satz", werte: { n: i }, zeit: t, quelle: "uhr", handlung_kennung: `h${i}` });
  const stand = p.methode("seneca.stand", { geraet: "iphone" }) as { schema: number; revision: number; jetzt: number };
  assert.ok(JSON.stringify(stand).length < regelZahl("stand_max_kb") * 1024);
  assert.equal(stand.schema, 1);
  assert.equal(stand.jetzt, t);
  assert.deepEqual(p.methode("seneca.stand", { geraet: "iphone", revision: stand.revision }), { schema: 1, revision: stand.revision, jetzt: t, unveraendert: true });
});

test("PF11 Neu beginnen: die App schickt eine Handlung, der Server setzt die Sitzung genau einmal zurück", async () => {
  const p = ladePlugin();
  um("10:00");
  const befehle: string[][] = [];
  const befehl = async (argv: string[]) => (befehle.push(argv), { code: 0, stderr: "" });
  assert.match((p.methode("seneca.handeln", { kennung: "n0", geraet: "mac", art: "gespraech.neu", ziel: "irgendwas; rm" }) as { ergebnis: string }).ergebnis, /sitzung_unbekannt/);
  p.methode("seneca.handeln", { kennung: "n1", geraet: "mac", art: "gespraech.neu", ziel: "agent:engineer:main" });
  await gespraecheJob(p.db, befehl);
  await gespraecheJob(p.db, befehl);
  assert.equal(befehle.length, 1);
  assert.deepEqual(befehle[0].slice(1, 5), ["gateway", "call", "sessions.reset", "--json"]);
  assert.deepEqual(JSON.parse(befehle[0][6]), { key: "agent:engineer:main", reason: "new" });
});

test("PF11 Datei aus dem Gespräch: Vorschau nur aus der Ablage, Text als Inhalt, PDF als Daten, nie außerhalb", () => {
  const p = ladePlugin();
  const ablage = mkdtempSync(join(tmpdir(), "ablage-"));
  mkdirSync(join(ablage, "sundartha"));
  mkdirSync(join(ablage, "_sicherung"));
  writeFileSync(join(ablage, "sundartha/plan.md"), "# Plan");
  writeFileSync(join(ablage, "sundartha/angebot.pdf"), "%PDF-1.4");
  writeFileSync(join(ablage, "_sicherung/geheim.txt"), "x");
  const zurueck = regelnMit({ ablage_pfad: ablage });
  const datei = (pfad: string) => p.methode("seneca.stand", { geraet: "iphone", sicht: "datei", pfad }) as Record<string, string>;
  assert.deepEqual(datei("~/Ablage/sundartha/plan.md"), { name: "plan.md", pfad: "sundartha/plan.md", art: "md", inhalt: "# Plan" });
  assert.equal(datei("/Users/antonio/Ablage/sundartha/plan.md").inhalt, "# Plan");
  assert.match(datei("sundartha/angebot.pdf").data, /^data:application\/octet-stream;base64,JVBERi0xLjQ=$/);
  for (const weg of ["../../etc/passwd", "/etc/hosts", "_sicherung/geheim.txt", "sundartha"]) assert.equal(datei(weg).inhalt, undefined);
  zurueck();
});
