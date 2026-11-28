import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, utimesSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { knotenJob, signiere } from "../src/arbeitsdienst/rechenknoten.ts";
import { faelligeAuftraegeJob, faelligeWirkungenJob, laeufePruefenJob, pflegenJob } from "../src/arbeitsdienst/jobs.ts";
import { auftraege, ereignisse, fragen, hole, laeufe, uhr, wert } from "../src/register/lesen.ts";
import { auftragSetzen, frageBeantworten, uebergang, wertSetzen } from "../src/register/schreiben.ts";
import { auftragVonAntonio, jaNeinFrage, ladePlugin, nurWach, regelnMit, spaeter, um } from "./aufbau.ts";

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

test("PF12 Start zweimal gleich abgelehnt: Befund und eine Frage statt Schleife, Neu versuchen startet sofort", async () => {
  const p = ladePlugin();
  um("09:00");
  const a = auftragVonAntonio(p.db, "Rundgang Engineer", { verantwortlich: "engineer" });
  let versuche = 0;
  const abgelehnt = async () => {
    versuche++;
    throw new Error("Agent engineer deletion is in progress; new work is unavailable.");
  };
  for (const t of ["09:01", "09:03", "09:10", "10:00", "12:00", "20:00"]) {
    um(t);
    await faelligeAuftraegeJob(p.db, abgelehnt);
  }
  assert.equal(versuche, 2);
  assert.equal(hole(p.db, "auftrag", a).zustand, "wartet");
  assert.equal(ereignisse(p.db, { art: "befund", auftrag_id: a }).filter((e) => /zweimal gleich/.test(String(e.satz))).length, 1);
  const frage = fragen(p.db, "offen").filter((f) => f.auftrag_id === a);
  assert.equal(frage.length, 1);
  frageBeantworten(p.db, { frage_id: String(frage[0].id), antwort: "weiter", geraet: "iphone", kennung: "k1" });
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(p.starts.length, 1);
  assert.equal(hole(p.db, "auftrag", a).zustand, "laeuft");
  assert.match(p.kontext(p.starts[0].sessionKey) ?? "", /# Bauregeln/);
});

test("PF12 Startfrage räumt sich selbst weg, sobald derselbe Mitarbeiter wieder starten kann, ohne Extra-Lauf", async () => {
  const p = ladePlugin();
  um("09:00");
  const a = auftragVonAntonio(p.db, "Staging-Probe", { verantwortlich: "engineer" });
  const abgelehnt = async () => {
    throw new Error("plugin seneca does not uniquely own subagent tool");
  };
  for (const t of ["09:01", "09:03", "09:10"]) {
    um(t);
    await faelligeAuftraegeJob(p.db, abgelehnt);
  }
  const frage = String(fragen(p.db, "offen").find((f) => f.auftrag_id === a)?.id);
  auftragVonAntonio(p.db, "Andere Sache", { verantwortlich: "engineer" });
  um("09:20");
  await faelligeAuftraegeJob(p.db, p.starte);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(hole(p.db, "frage", frage).zustand, "zurueckgezogen");
  assert.equal(hole(p.db, "auftrag", a).zustand, "bereit");
  assert.equal(p.starts.length, 1);
});

test("PF12 Aufwachen zum Nachfassen zieht Antonios Frage nicht zurück, Verwerfen schon", () => {
  const p = ladePlugin();
  um("09:00");
  const a = auftragVonAntonio(p.db, "Staging-Name klären");
  const f = jaNeinFrage(p.db, a, "Staging-Name festlegen?");
  uebergang(p.db, "auftrag", a, "wartet", "frage", { wartet_auf: `frage:${f}`, folge: "Ruht.", naechster_anlass: uhr.jetzt() });
  uebergang(p.db, "auftrag", a, "bereit", "nachfassen", { naechster_anlass: uhr.jetzt() });
  assert.equal(hole(p.db, "frage", f).zustand, "offen");
  uebergang(p.db, "auftrag", a, "verworfen", "antonio");
  assert.equal(hole(p.db, "frage", f).zustand, "zurueckgezogen");
});

test("PF12 Abo am echten Limit: genau ein Satz, kein Lauf, der sicher scheitert", async () => {
  const p = ladePlugin();
  um("09:00");
  const id = auftragVonAntonio(p.db, "Etwas bauen");
  spaeter(6000);
  for (let i = 0; i < 3; i++) {
    await faelligeAuftraegeJob(p.db, p.starte);
    p.haken("agent_end", { messages: [], success: false, error: "All models failed (2): anthropic/claude-sonnet-5-5: You've hit your weekly limit · resets Dec 1, 6am (Europe/Berlin) (rate_limit)" }, { sessionKey: p.starts[i].sessionKey });
    if (i === 0) assert.match(String(wert(p.db, "hinweis:abos")?.wert), /^Abo antonio bis Di\.?, 06:00 aufgebraucht, Läufe nutzen jetzt sundartha\.$/);
    spaeter(5 * 60000);
  }
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(p.starts.length, 3);
  assert.deepEqual(laeufe(p.db, id).map((l) => [l.abo, l.grund]), ["antonio", "sundartha", "regius"].map((a) => [`anthropic:${a}`, "Abo am Limit"]));
  assert.equal(wert(p.db, "abo_pause:anthropic:regius")?.gueltig_bis, new Date("2026-12-01T06:00").getTime());
  assert.deepEqual((p.methode("seneca.stand", { geraet: "mac" }) as { hinweise: string[] }).hinweise.filter((h) => h.startsWith("Abo")), [String(wert(p.db, "hinweis:abos")?.wert)]);
  assert.match(String(wert(p.db, "hinweis:abos")?.wert), /^Abo antonio bis Di\.?, 06:00 aufgebraucht, Läufe warten\.$/);
});

test("PF12 Dauerauftrag läuft 10 Tage ohne Rahmen-Frage", async () => {
  const p = ladePlugin();
  um("07:00", "2026-11-30");
  nurWach(p.db, "produkt");
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

const abbruch = async () => ({ code: 0, stderr: "" });
const stupseNie = async () => false;

test("PF12 Anstupsen von selbst: still seit 30 min wird gestupst, ohne Schritt danach beendet und neu angesetzt, geht Steuern nicht, sofort; Werkzeuge zählen als Schritt", async () => {
  for (const geht of [true, false]) {
    const p = ladePlugin();
    um("09:00");
    const a = auftragVonAntonio(p.db, "Lange Recherche");
    spaeter(6000);
    await faelligeAuftraegeJob(p.db, p.starte);
    const sitzung = String(laeufe(p.db, a)[0].sitzung);
    const gestupst: string[] = [], befehle: string[][] = [];
    const stupse = async (s: string, text: string) => (gestupst.push(`${s}: ${text}`), geht);
    const abbruchMerken = async (argv: string[]) => (befehle.push(argv), { code: 0, stderr: "" });
    um("09:25");
    p.haken("after_tool_call", { toolName: "exec", params: { command: "gh pr checks 1" }, toolCallId: `w-${geht}`, durationMs: 5 }, { sessionKey: sitzung });
    um("09:45");
    await laeufePruefenJob(p.db, stupse, abbruchMerken);
    assert.deepEqual([gestupst.length, laeufe(p.db, a)[0].zustand], [0, "haengt"]);
    um("09:56");
    await laeufePruefenJob(p.db, stupse, abbruchMerken);
    assert.equal(fragen(p.db, "offen").filter((x) => x.von === "arbeitsdienst:haengt").length, 0);
    assert.equal(gestupst.length, 1);
    assert.equal(laeufe(p.db, a)[0].zustand === "abgebrochen", !geht);
    if (geht) {
      um("10:01");
      await laeufePruefenJob(p.db, stupse, abbruchMerken);
      assert.notEqual(laeufe(p.db, a)[0].zustand, "abgebrochen");
      um("10:07");
      await laeufePruefenJob(p.db, stupse, abbruchMerken);
      assert.equal(gestupst.length, 1);
    }
    assert.deepEqual([laeufe(p.db, a)[0].zustand, hole(p.db, "auftrag", a).zustand], ["abgebrochen", "bereit"]);
    assert.deepEqual(befehle.map((b) => [b[3], JSON.parse(b[6]).sessionKey]), [["chat.abort", sitzung]]);
  }
});

test("PF12 Auftrag verworfen oder geparkt, Stopp von außen: Lauf bricht ab und steht abgebrochen im Register, keine Hängt-Frage", async () => {
  for (const art of ["auftrag.verwerfen", "auftrag.anhalten"]) {
    const p = ladePlugin();
    um("09:00");
    const a = auftragVonAntonio(p.db, "Probe");
    spaeter(6000);
    await faelligeAuftraegeJob(p.db, p.starte);
    const sitzung = String(laeufe(p.db, a)[0].sitzung);
    p.methode("seneca.handeln", { kennung: art, geraet: "iphone", art, ziel: a });
    const befehle: string[][] = [];
    um("09:01");
    await laeufePruefenJob(p.db, stupseNie, async (argv) => (befehle.push(argv), { code: 0, stderr: "" }));
    assert.deepEqual(befehle.map((b) => b.slice(1, 4).concat(JSON.parse(b[6]).sessionKey)), [["gateway", "call", "chat.abort", sitzung]]);
    assert.equal(laeufe(p.db, a)[0].zustand, "abgebrochen");
    assert.equal(laeufe(p.db, a)[0].grund, art === "auftrag.verwerfen" ? "Auftrag verworfen" : "Auftrag geparkt");
    um("10:00");
    await laeufePruefenJob(p.db, stupseNie, abbruch);
    assert.equal(fragen(p.db, "offen").length, 0);
    assert.equal(befehle.length, 1);
  }
  const p = ladePlugin();
  um("09:00");
  const a = auftragVonAntonio(p.db, "Probe 2");
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  const sitzung = String(laeufe(p.db, a)[0].sitzung);
  p.haken("run_stopped", { source: "client", sessions: [{ agentId: "produkt", sessionKey: sitzung }], runIds: ["run-1"] }, {});
  assert.deepEqual([laeufe(p.db, a)[0].zustand, laeufe(p.db, a)[0].grund, hole(p.db, "auftrag", a).zustand], ["abgebrochen", "gestoppt", "geparkt"]);
  p.ende(sitzung);
  assert.equal(laeufe(p.db, a)[0].grund, "gestoppt");
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

test("PF12 Arbeitsdateien verfallen nach Frist, verknüpfte bleiben; Sicherung einmal am Tag", async () => {
  const ablage = mkdtempSync(join(tmpdir(), "ablage-"));
  const passwort = join(ablage, "passwort");
  writeFileSync(passwort, "x");
  const zurueck = regelnMit({ ablage_pfad: ablage, sicherung_passwort: passwort });
  const p = ladePlugin();
  um("09:00", "2026-12-10");
  const datei = (rel: string, alt: boolean) => {
    mkdirSync(dirname(join(ablage, rel)), { recursive: true });
    writeFileSync(join(ablage, rel), rel);
    const zeit = new Date(alt ? "2026-12-02" : "2026-12-09");
    utimesSync(join(ablage, rel), zeit, zeit);
  };
  datei("_arbeit/produkt/tmp/roh.txt", true);
  datei("_arbeit/produkt/ergebnis.md", true);
  datei("_arbeit/produkt/neu.txt", false);
  datei("sundartha/alt.md", true);
  const a = auftragVonAntonio(p.db, "Etwas bauen");
  auftragSetzen(p.db, a, { ergebnis: "Siehe _arbeit/produkt/ergebnis.md" });
  const befehle: string[][] = [];
  const befehl = async (argv: string[]) => (befehle.push(argv), { code: 0, stderr: "" });
  await pflegenJob(p.db, join(ablage, "sicherung"), befehl);
  assert.deepEqual(["_arbeit/produkt/tmp/roh.txt", "_arbeit/produkt/ergebnis.md", "_arbeit/produkt/neu.txt", "sundartha/alt.md"].map((r) => existsSync(join(ablage, r))), [false, true, true, true]);
  assert.equal(existsSync(join(ablage, "_arbeit/produkt/tmp")), false);
  assert.deepEqual(befehle.map((b) => b.includes("restic") ? b[5] : b[1]), ["backup", "backup", "forget"]);
  assert.ok(befehle[1].some((x) => x.endsWith(".sqlite")));
  spaeter(3600000);
  await pflegenJob(p.db, join(ablage, "sicherung"), befehl);
  assert.equal(befehle.length, 3);
  um("09:00", "2026-12-11");
  await assert.rejects(pflegenJob(p.db, join(ablage, "sicherung"), async () => ({ code: 1, stderr: "kaputt" })), /kaputt/);
  zurueck();
});
