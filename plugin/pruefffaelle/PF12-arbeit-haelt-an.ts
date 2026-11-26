import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { knotenJob, signiere } from "../src/arbeitsdienst/rechenknoten.ts";
import { faelligeAuftraegeJob, faelligeWirkungenJob, laeufePruefenJob, pflegenJob } from "../src/arbeitsdienst/jobs.ts";
import { auftraege, ereignisse, fragen, hole, laeufe } from "../src/register/lesen.ts";
import { frageBeantworten, wertSetzen } from "../src/register/schreiben.ts";
import { auftragVonAntonio, ladePlugin, regelnMit, spaeter, um } from "./aufbau.ts";

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

test("PF12 Anstupsen: Folgezug im laufenden Lauf; ohne Schritt danach einmal neu, geht Steuern nicht, sofort neu", async () => {
  for (const geht of [true, false]) {
    const p = ladePlugin();
    um("09:00");
    const a = auftragVonAntonio(p.db, "Lange Recherche");
    spaeter(6000);
    await faelligeAuftraegeJob(p.db, p.starte);
    const gestupst: string[] = [];
    const stupse = async (sitzung: string, text: string) => (gestupst.push(`${sitzung}: ${text}`), geht);
    um("09:40");
    await laeufePruefenJob(p.db, stupse);
    const f = fragen(p.db, "offen").find((x) => x.von === "arbeitsdienst:haengt");
    assert.ok(f);
    frageBeantworten(p.db, { frage_id: String(f.id), antwort: "anstupsen", geraet: "iphone", kennung: `s-${geht}` });
    spaeter(10000);
    faelligeWirkungenJob(p.db);
    await laeufePruefenJob(p.db, stupse);
    assert.equal(gestupst.length, 1);
    assert.equal(laeufe(p.db, a)[0].zustand === "abgebrochen", !geht);
    if (!geht) continue;
    um("09:45");
    await laeufePruefenJob(p.db, stupse);
    assert.notEqual(laeufe(p.db, a)[0].zustand, "abgebrochen");
    assert.equal(fragen(p.db, "offen").filter((x) => x.von === "arbeitsdienst:haengt").length, 0);
    um("09:52");
    await laeufePruefenJob(p.db, stupse);
    assert.equal(laeufe(p.db, a)[0].zustand, "abgebrochen");
    assert.equal(gestupst.length, 1);
  }
});

test("PF12 Rechenknoten: AWS-Signatur nach Vorgabe, Start nur bei Bedarf, Stopp nach Leerlauf, ohne Zugang still aus", async () => {
  const beispiel = signiere({ zugang: "AKIDEXAMPLE", geheimnis: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY" },
    { host: "iam.amazonaws.com", region: "us-east-1", dienst: "iam", zeit: Date.UTC(2015, 7, 30, 12, 36), query: { Action: "ListUsers", Version: "2010-05-08" } });
  assert.match(beispiel.kopf.authorization, /Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7$/);
  const aufrufe: string[] = [];
  const aws = createServer((req, res) => (aufrufe.push(new URL(String(req.url), "http://x").searchParams.get("Action") ?? ""), res.end("<ok/>")));
  await new Promise<void>((fertig) => aws.listen(0, "127.0.0.1", fertig));
  const zurueck = regelnMit({ rechenknoten_aws_url: `http://127.0.0.1:${(aws.address() as AddressInfo).port}/` });
  const p = ladePlugin();
  const zugang = { zugang: "AKIDTEST", geheimnis: "geheim-test" };
  const keine = async () => [];
  um("09:00");
  await knotenJob(p.db, zugang, keine);
  assert.deepEqual(aufrufe, []);
  const a = auftragVonAntonio(p.db, "Formular im Browser ausfüllen", { arbeitsart: "browser" });
  spaeter(6000);
  await knotenJob(p.db, {}, keine);
  assert.deepEqual(aufrufe, []);
  await knotenJob(p.db, zugang, keine);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.deepEqual(aufrufe, ["StartInstances"]);
  assert.equal(p.starts.length, 0);
  await knotenJob(p.db, zugang, async () => [{ name: "rechenknoten", ollama: false }]);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(laeufe(p.db, a)[0].ort, "rechenknoten");
  assert.match(p.starts[0].message, /exec host=rechenknoten/);
  p.ende(String(laeufe(p.db, a)[0].sitzung), 100);
  p.methode("seneca.handeln", { kennung: "v1", geraet: "iphone", art: "auftrag.verwerfen", ziel: a });
  um("09:20");
  await knotenJob(p.db, zugang, keine);
  assert.deepEqual(aufrufe, ["StartInstances"]);
  um("09:45");
  await knotenJob(p.db, zugang, keine);
  await knotenJob(p.db, zugang, keine);
  assert.deepEqual(aufrufe, ["StartInstances", "StopInstances"]);
  zurueck();
  aws.close();
});
