import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob, faelligeWirkungenJob, pflegenJob } from "../src/arbeitsdienst/jobs.ts";
import { auftraege, ereignisse, fragen, hole, laeufe } from "../src/register/lesen.ts";
import { wertSetzen } from "../src/register/schreiben.ts";
import { auftragVonAntonio, ladePlugin, spaeter, um } from "./aufbau.ts";

test("PF12 ruhender Mitarbeiter wird nie geweckt und wacht nach dem Ende von selbst auf", async () => {
  const p = ladePlugin();
  um("09:00");
  const bis = um("12:00");
  um("09:00");
  wertSetzen(p.db, "ruht:produkt", "ja", "seneca", bis);
  const a = auftragVonAntonio(p.db, "Telco-Radar soll nichts machen");
  for (const t of ["09:01", "09:30", "10:00", "11:59"]) {
    um(t);
    await faelligeAuftraegeJob(p.db, p.starte);
  }
  assert.equal(p.starts.length, 0);
  um("12:00");
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(p.starts.length, 1);
  assert.equal(hole(p.db, "auftrag", a).zustand, "laeuft");
});

test("PF12 Rahmen überschritten: genau eine Frage, nur dieser Auftrag hält", async () => {
  const p = ladePlugin();
  um("09:00");
  const teuer = auftragVonAntonio(p.db, "Teure Recherche");
  const billig = auftragVonAntonio(p.db, "Kleine Sache");
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  for (const [a, tokens] of [[teuer, 40000], [billig, 0]] as const) {
    const sitzung = String(laeufe(p.db, a)[0].sitzung);
    await p.werkzeug("seneca_fortschreiben", sitzung, "produkt", { letzter_stand: "halb", naechster_schritt: "weiter", ergebnis: "weiter" });
    p.ende(sitzung, tokens);
  }
  await faelligeAuftraegeJob(p.db, p.starte);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(fragen(p.db, "offen").filter((f) => f.auftrag_id === teuer).length, 1);
  assert.match(String(fragen(p.db, "offen")[0].text), /0,50 €/);
  assert.equal(laeufe(p.db, teuer).length, 1);
  assert.equal(hole(p.db, "auftrag", teuer).zustand, "wartet");
  assert.equal(hole(p.db, "auftrag", billig).zustand, "laeuft");
});

test("PF12 alle Abos am Limit: 0 Läufe und genau ein Satz", async () => {
  const p = ladePlugin();
  um("09:00");
  for (const abo of ["anthropic:antonio", "anthropic:sundartha", "anthropic:regius"]) wertSetzen(p.db, `abo_pause:${abo}`, "ja", "test", um("23:00"));
  um("09:00");
  auftragVonAntonio(p.db, "Etwas bauen");
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(p.starts.length, 0);
  assert.equal(ereignisse(p.db, { art: "wert.gesetzt", schluessel: "hinweis:abos" }).length, 1);
  assert.deepEqual((p.methode("seneca.stand", { geraet: "mac" }) as { hinweise: string[] }).hinweise.length, 1);
});

test("PF12 Dauerauftrag läuft 10 Tage ohne Rahmen-Frage", async () => {
  const p = ladePlugin();
  um("07:00", "2026-11-30");
  wertSetzen(p.db, "ruht:seneca", "ja", "test");
  pflegenJob(p.db, `${process.env.TMPDIR ?? "/tmp"}/seneca-pf12-sicherung`);
  const rundgang = auftraege(p.db, ["bereit"]).find((a) => a.verantwortlich === "produkt" && a.arbeitsart === "rundgang");
  assert.ok(rundgang);
  for (let tag = 0; tag < 10; tag++) {
    um("09:00", `2026-12-${String(tag + 1).padStart(2, "0")}`);
    await faelligeAuftraegeJob(p.db, p.starte);
    const l = laeufe(p.db, String(rundgang.id)).at(-1);
    assert.equal(l?.zustand, "laeuft");
    await p.werkzeug("seneca_fortschreiben", String(l?.sitzung), "produkt", { letzter_stand: "Rundgang", naechster_schritt: "morgen", ergebnis: "weiter" });
    p.ende(String(l?.sitzung), 26000);
    faelligeWirkungenJob(p.db);
  }
  assert.equal(laeufe(p.db, String(rundgang.id)).length, 10);
  assert.equal(fragen(p.db, "offen").length, 0);
});
