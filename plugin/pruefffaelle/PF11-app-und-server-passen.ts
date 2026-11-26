import assert from "node:assert/strict";
import { test } from "node:test";
import { eintragSetzen } from "../src/register/schreiben.ts";
import { regelZahl } from "../src/regeln.ts";
import { ladePlugin, um } from "./aufbau.ts";

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
