import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob, faelligeWirkungenJob } from "../src/arbeitsdienst/jobs.ts";
import { unklarePruefen } from "../src/ausgang/ausgang.ts";
import { ereignisse, fragen, laeufe } from "../src/register/lesen.ts";
import { frageBeantworten, frageZuruecknehmen, wertSetzen } from "../src/register/schreiben.ts";
import { auftragVonAntonio, ladePlugin, spaeter, um } from "./aufbau.ts";

const ANRUF = "mcp__telefon__anruf";
const MAIL = "mcp__zoho-mail__send_mail";

async function imLauf(p: ReturnType<typeof ladePlugin>) {
  um("09:00");
  const a = auftragVonAntonio(p.db, "Testanruf auf meine Nummer");
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  return { a, sitzung: String(laeufe(p.db, a)[0].sitzung) };
}

const freigabe = (p: ReturnType<typeof ladePlugin>, art = "freigabe") => fragen(p.db, "offen").find((f) => f.art === art);

test("PF05 a) unbekannte Nummer: 0 Anrufe, Frage nach der Stufe; e) gesperrtes Werkzeug: 0 und Befund", async () => {
  const p = ladePlugin();
  const { sitzung } = await imLauf(p);
  assert.ok(p.aufruf(sitzung, ANRUF, { nummer: "+49 170 9999999" })?.block);
  assert.ok(p.aufruf(sitzung, ANRUF, { nummer: "+49 170 9999999" })?.block);
  assert.equal(fragen(p.db, "offen").filter((f) => f.art === "stufe_festlegen").length, 1);
  assert.ok(p.aufruf(sitzung, "whatsapp_send", { to: "+491701" })?.block);
  assert.ok(ereignisse(p.db, { art: "befund" }).some((b) => String(b.satz).startsWith("whatsapp_send")));
  assert.equal(ereignisse(p.db, { art: "ausgang.gestartet" }).length, 0);
});

test("PF05 b) Ja und Rückgängig: 0; c) Ja von zwei Geräten und Neustart in der Frist: genau 1; f) Absturz: unklar, kein zweiter", async () => {
  const p = ladePlugin();
  const { sitzung } = await imLauf(p);
  wertSetzen(p.db, "kontakt:+491701111111", "kurz_fragen", "antonio");
  const anruf = { nummer: "+49 170 1111111" };
  assert.ok(p.aufruf(sitzung, ANRUF, anruf)?.block);
  const f = String(freigabe(p)?.id);
  frageBeantworten(p.db, { frage_id: f, antwort: "ja", geraet: "iphone", kennung: "k1" });
  assert.equal(frageZuruecknehmen(p.db, f), "angenommen");
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.ok(p.aufruf(sitzung, ANRUF, anruf)?.block);
  frageBeantworten(p.db, { frage_id: f, antwort: "ja", geraet: "iphone", kennung: "k2" });
  assert.equal(frageBeantworten(p.db, { frage_id: f, antwort: "ja", geraet: "mac", kennung: "k3" }).ergebnis, "schon_beantwortet");
  const neu = ladePlugin(p.ordner);
  spaeter(6000);
  faelligeWirkungenJob(neu.db);
  assert.equal(neu.aufruf(sitzung, ANRUF, anruf, "c1"), undefined);
  assert.ok(neu.aufruf(sitzung, ANRUF, anruf, "c2")?.block);
  const nachAbsturz = ladePlugin(p.ordner);
  unklarePruefen(nachAbsturz.db);
  assert.ok(fragen(nachAbsturz.db, "offen").some((x) => String(x.text).includes("vielleicht")));
  assert.ok(nachAbsturz.aufruf(sitzung, ANRUF, anruf)?.block);
  assert.equal(ereignisse(nachAbsturz.db, { art: "ausgang.gestartet" }).length, 1);
});

test("PF05 d) Notar: Uhr-Ja 0, ausführliches Ja 1", async () => {
  const p = ladePlugin();
  const { sitzung } = await imLauf(p);
  wertSetzen(p.db, "kontakt:org:@notar-beispiel.de", "ausfuehrlich", "antonio");
  const mail = { to: "buero@notar-beispiel.de", text: "Termin zur Beurkundung" };
  assert.ok(p.aufruf(sitzung, MAIL, mail)?.block);
  const f = freigabe(p, "ausfuehrliches_ja");
  assert.equal(frageBeantworten(p.db, { frage_id: String(f?.id), antwort: "ja", geraet: "uhr", kennung: "u1", lokal: true }).ergebnis, "abgelehnt");
  frageBeantworten(p.db, { frage_id: String(f?.id), antwort: "ja", geraet: "mac", kennung: "m1", inhalt_hash: String(f?.inhalt_hash) });
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.equal(p.aufruf(sitzung, MAIL, mail), undefined);
  assert.equal(ereignisse(p.db, { art: "ausgang.gestartet" }).length, 1);
});

test("PF05 g) Antonios eigener Befehl mit Empfänger und Wortlaut: ohne Frage, mit 5 s Rückgängig", () => {
  const p = ladePlugin();
  um("12:30");
  wertSetzen(p.db, "kontakt:+491701111111", "kurz_fragen", "antonio");
  p.nachricht("agent:seneca:main", "m7", "Ruf +491701111111 an und sag: Ich komme zehn Minuten später");
  const anruf = { nummer: "+491701111111", text: "Ich komme zehn Minuten später" };
  assert.ok(p.aufruf("agent:seneca:main", ANRUF, anruf)?.block);
  assert.equal(fragen(p.db, "offen").length, 0);
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.equal(p.aufruf("agent:seneca:main", ANRUF, anruf), undefined);
});
