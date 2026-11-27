import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob, faelligeWirkungenJob } from "../src/arbeitsdienst/jobs.ts";
import { unklarePruefen } from "../src/ausgang/ausgang.ts";
import { ereignisse, fragen, kinder, laeufe } from "../src/register/lesen.ts";
import { frageBeantworten, frageZuruecknehmen, uebergang, wertSetzen } from "../src/register/schreiben.ts";
import { zustellenJob } from "../src/pforte/zustellen.ts";
import { auftragVonAntonio, jaNeinFrage, ladePlugin, spaeter, um } from "./aufbau.ts";

const ANRUF = "hermes__place_call";
const MAIL = "mcp__zoho-mail__zoho_mail_send_mail";

async function imLauf(p: ReturnType<typeof ladePlugin>) {
  um("09:00");
  const a = auftragVonAntonio(p.db, "Testanruf auf meine Nummer");
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  return { a, sitzung: String(laeufe(p.db, a)[0].sitzung) };
}

const freigabe = (p: ReturnType<typeof ladePlugin>, art = "freigabe") => fragen(p.db, "offen").find((f) => f.art === art);

test("PF05 a) unbekannte Nummer, auch über die Shell: 0 Anrufe, Frage nach der Stufe; e) gesperrtes Werkzeug, Löschen, Force-Push, Schlüssel: 0 und Befund", async () => {
  const p = ladePlugin();
  const { sitzung } = await imLauf(p);
  assert.ok(p.aufruf(sitzung, ANRUF, { to: "+49 170 9999999" })?.block);
  assert.ok(p.aufruf(sitzung, ANRUF, { to: "+49 170 9999999" })?.block);
  assert.ok(p.aufruf(sitzung, "exec", { command: `node bin/hermes-mcp.mjs call place_call '{"to":"+49 170 9999999","objective":"x"}'` })?.block);
  assert.ok(p.aufruf(sitzung, "exec", { command: "node bin/hermes-mcp.mjs call place_call '{}'" })?.block);
  assert.equal(p.aufruf(sitzung, "exec", { command: "node bin/hermes-mcp.mjs call list_calls" }), undefined);
  assert.ok(p.aufruf(sitzung, "exec", { command: "curl -X POST https://api.telegram.org/bot1/sendMessage" })?.block);
  for (const command of ["trash alt.md", "git push --force origin bau/x", "find . -name x -delete", "git reset --hard HEAD~3", "cat ~/.ssh/id_ed25519", "cat /home/ubuntu/.env"]) {
    assert.ok(p.aufruf(sitzung, "exec", { command })?.block, command);
  }
  assert.ok(p.aufruf(sitzung, "read", { path: "/home/ubuntu/.openclaw/credentials/x.json" })?.block);
  assert.equal(p.aufruf(sitzung, "exec", { command: "git status && cat .env.beispiel.md" }), undefined);
  assert.equal(fragen(p.db, "offen").filter((f) => f.art === "stufe_festlegen").length, 1);
  assert.ok(p.aufruf(sitzung, "whatsapp_send", { to: "+491701" })?.block);
  assert.ok(ereignisse(p.db, { art: "befund" }).some((b) => String(b.satz).startsWith("whatsapp_send")));
  assert.equal(ereignisse(p.db, { art: "ausgang.gestartet" }).length, 0);
});

test("PF05 b) Ja und Rückgängig: 0; c) Ja von zwei Geräten und Neustart in der Frist: genau 1; f) Absturz: unklar, kein zweiter", async () => {
  const p = ladePlugin();
  const { sitzung } = await imLauf(p);
  wertSetzen(p.db, "kontakt:+491701111111", "kurz_fragen", "antonio");
  const anruf = { to: "+49 170 1111111" };
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
  const mail = { toAddress: "buero@notar-beispiel.de", content: "Termin zur Beurkundung" };
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
  const anruf = { to: "+491701111111", text: "Ich komme zehn Minuten später" };
  assert.ok(p.aufruf("agent:seneca:main", ANRUF, anruf)?.block);
  assert.equal(fragen(p.db, "offen").length, 0);
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.equal(p.aufruf("agent:seneca:main", ANRUF, anruf), undefined);
});

test("PF05 g2) Auftrag steckt fest: genau ein Anruf an Antonios eigene Nummer, nie nachts", async () => {
  for (const [zeit, erwartet] of [["13:00", 1], ["23:00", 0]] as const) {
    const p = ladePlugin();
    const [frist, nachfassen] = [um("23:50"), um("23:59")];
    um("08:00");
    wertSetzen(p.db, "profil:telefon", "+49 170 5550000", "antonio");
    const a = auftragVonAntonio(p.db, "Vertrag heute einreichen");
    const f = jaNeinFrage(p.db, a, "Vertrag so einreichen?", { frist });
    uebergang(p.db, "auftrag", a, "wartet", "frage", { wartet_auf: `frage:${f}`, folge: "Frist verpasst", naechster_anlass: nachfassen });
    um(zeit);
    await zustellenJob(p.db);
    await zustellenJob(p.db);
    const anruf = kinder(p.db, a).filter((k) => k.arbeitsart === "anruf_antonio");
    assert.equal(anruf.length, erwartet);
    if (!erwartet) continue;
    await faelligeAuftraegeJob(p.db, p.starte);
    const sitzung = String(laeufe(p.db, String(anruf[0].id))[0].sitzung);
    assert.equal(p.aufruf(sitzung, ANRUF, { to: "+491705550000" }, "x1"), undefined);
    assert.ok(p.aufruf(sitzung, ANRUF, { to: "+491705550000" }, "x2")?.block);
    assert.ok(p.aufruf(sitzung, ANRUF, { to: "+491709999999" })?.block);
  }
});

test("PF05 h) Anruf-Auftrag von tagsüber: nicht nachts, nicht im Schlaf, danach genau einmal", async () => {
  const p = ladePlugin();
  um("13:00");
  wertSetzen(p.db, "profil:telefon", "+49 170 5550000", "antonio");
  const a = auftragVonAntonio(p.db, "Ruf Antonio an", { arbeitsart: "anruf_antonio" });
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  const sitzung = String(laeufe(p.db, a)[0].sitzung);
  um("23:30");
  assert.ok(p.aufruf(sitzung, ANRUF, { to: "+491705550000" })?.block);
  const wach = um("15:00");
  um("14:00");
  wertSetzen(p.db, "aktivitaet", "schlaf", "uhr", wach);
  assert.ok(p.aufruf(sitzung, ANRUF, { to: "+491705550000" })?.block);
  um("16:00");
  assert.ok(p.aufruf(sitzung, MAIL, { toAddress: "nora@example.org", content: "x" })?.block);
  assert.equal(p.aufruf(sitzung, ANRUF, { to: "+491705550000" }), undefined);
  assert.ok(p.aufruf(sitzung, ANRUF, { to: "+491705550000" })?.block);
  assert.equal(ereignisse(p.db, { art: "ausgang.gestartet" }).length, 1);
});

test("PF05 k) Unteragent und Nachricht an Kollegen: nie an Ruhende, nur laut Mandat, Lauf im Register", async () => {
  const p = ladePlugin();
  const { a, sitzung } = await imLauf(p);
  wertSetzen(p.db, "ruht:telcoradar", "ja", "antonio");
  assert.equal(p.aufruf(sitzung, "sessions_spawn", { agentId: "engineer", task: "x" }), undefined);
  assert.equal(p.aufruf(sitzung, "sessions_spawn", { task: "x" }), undefined);
  assert.ok(p.aufruf(sitzung, "sessions_spawn", { agentId: "branding", task: "x" })?.block);
  assert.ok(p.aufruf("agent:seneca:main", "sessions_spawn", { agentId: "telcoradar", task: "x" }, "s1", "seneca")?.block);
  assert.ok(p.aufruf("agent:seneca:main", "mcp__openclaw__sessions_send", { sessionKey: "agent:telcoradar:main", message: "x" }, "s2", "seneca")?.block);
  assert.ok(p.aufruf("agent:telcoradar:main", "sessions_spawn", { task: "x" }, "s3", "telcoradar")?.block);
  p.haken("subagent_spawned", { childSessionKey: "agent:engineer:subagent:k1", agentId: "engineer", mode: "run", runId: "r1" }, { requesterSessionKey: sitzung });
  p.ende("agent:engineer:subagent:k1", 50);
  assert.equal(ereignisse(p.db, { art: "unteragent" })[0].auftrag_id, a);
  assert.equal(ereignisse(p.db, { art: "unteragent.ende", schluessel: "agent:engineer:subagent:k1" }).length, 1);
});

test("PF05 i) Ablage: Mitarbeiter schreibt nur in seinem Bereich und _arbeit/<name>, Privat liest nur Seneca", async () => {
  const p = ladePlugin();
  const { sitzung } = await imLauf(p);
  assert.match(p.kontext(sitzung) ?? "", /schreiben Sundartha, _arbeit\/produkt\. Zwischendateien nur in _arbeit\/produkt\//);
  const pfad = (rel: string) => ({ path: `/home/ubuntu/Ablage/${rel}` });
  assert.equal(p.aufruf("s", "write", pfad("Sundartha/Hermes/plan.md"), "w1", "produkt"), undefined);
  assert.ok(p.aufruf("s", "write", pfad("Vodafone/x.md"), "w2", "produkt")?.block);
  assert.ok(p.aufruf("s", "read", pfad("Privat/tagebuch.md"), "r1", "produkt")?.block);
  assert.equal(p.aufruf("s", "read", pfad("Privat/tagebuch.md"), "r2", "seneca"), undefined);
  assert.equal(p.aufruf("s", "write", pfad("sundartha/website/text.md"), "w3", "produkt"), undefined);
  assert.equal(p.aufruf("s", "write", pfad("_arbeit/engineer/roh.txt"), "w4", "engineer"), undefined);
  assert.ok(p.aufruf("s", "write", pfad("_arbeit/produkt/roh.txt"), "w5", "engineer")?.block);
  assert.ok(p.aufruf("s", "write", pfad("_wissen/notiz.md"), "w6", "engineer")?.block);
  assert.equal(p.aufruf("s", "read", pfad("_wissen/notiz.md"), "r3", "engineer"), undefined);
});

test("PF05 j) Live nur mit ausführlichem Ja; Gateway-Neustart nur im Bauablauf mit Ja", async () => {
  const p = ladePlugin();
  const { sitzung } = await imLauf(p);
  const merge = { command: "gh pr merge 17 --squash" };
  assert.equal(p.aufruf(sitzung, "exec", { command: "git push -u origin bau/x" }), undefined);
  assert.ok(p.aufruf(sitzung, "exec", merge)?.block);
  const f = freigabe(p, "ausfuehrliches_ja");
  frageBeantworten(p.db, { frage_id: String(f?.id), antwort: "ja", geraet: "mac", kennung: "m1", inhalt_hash: String(f?.inhalt_hash) });
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.equal(p.aufruf(sitzung, "exec", merge), undefined);
  assert.ok(p.aufruf(sitzung, "exec", { command: "systemctl --user restart openclaw-gateway" })?.block);
  assert.ok(p.aufruf(sitzung, "gateway", { action: "restart" })?.block);
  assert.ok(p.aufruf(sitzung, "exec", { command: "openclaw update --yes" })?.block);
  assert.equal(freigabe(p, "ausfuehrliches_ja"), undefined);
  assert.ok(p.aufruf(sitzung, "exec", { command: "openclaw gateway restart" }, "g1", "engineer")?.block);
  assert.ok(freigabe(p, "ausfuehrliches_ja"));
});
