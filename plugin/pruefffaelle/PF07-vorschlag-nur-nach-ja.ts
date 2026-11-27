import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob, faelligeWirkungenJob } from "../src/arbeitsdienst/jobs.ts";
import { uhrStand } from "../src/pforte/stand.ts";
import { zustellenJob } from "../src/pforte/zustellen.ts";
import { eingangJob } from "../src/quellen/eingang.ts";
import { auftraege, ereignisse, fragen, hole, laeufe, offeneFrage, todos, uhr, wert } from "../src/register/lesen.ts";
import { frageBeantworten, vorschlagAnlegen, wertSetzen } from "../src/register/schreiben.ts";
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

test("PF07 Sensor, WhatsApp und Regel: nur sichere Vorschläge, ja/nein an der Uhr, Ja wirkt, Nein und Frist verwerfen, Quote je Quelle", async () => {
  const p = ladePlugin();
  const t = um("10:00");
  const sensor = (k: string, w: object) => p.methode("seneca.handeln", { kennung: k, geraet: "mac", art: "eingang.sensor", wert: w });
  const rechnung = { art: "vorschlag", text: "Rechnung der Telekom ablegen", app: "Mail", titel: "Ihre Rechnung" };
  sensor("s1", { ...rechnung, sicherheit: 0.5 });
  sensor("s2", { ...rechnung, sicherheit: 0.9 });
  sensor("s3", { ...rechnung, sicherheit: 0.95 });
  sensor("s4", { art: "spur", app: "Xcode", titel: "Sensor.swift", von: t - 1200000, bis: t });
  sensor("s5", { art: "spur", app: "Finder", titel: "Downloads", von: t - 60000, bis: t });
  p.methode("seneca.handeln", { kennung: "m1", geraet: "mac", art: "eingang.meeting", wert: "Ablage/Meetings/jonas.md" });
  eingangJob(p.db);
  eingangJob(p.db);
  const ausSensor = fragen(p.db, "offen").filter((f) => f.art === "vorschlag");
  assert.equal(ausSensor.length, 1);
  assert.equal(p.db.prepare("SELECT COUNT(*) AS n FROM eintrag WHERE art = 'tagesspur'").get()?.n, 1);
  assert.ok(auftraege(p.db, ["bereit"]).some((a) => a.verantwortlich === "seneca" && a.titel === "Meeting auswerten"));
  frageBeantworten(p.db, { frage_id: String(ausSensor[0].id), antwort: "nein", geraet: "mac", kennung: "n1" });
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.equal(hole(p.db, "auftrag", String(ausSensor[0].auftrag_id)).zustand, "verworfen");

  const regel = vorschlagAnlegen(p.db, {
    wortlaut: "Dreimal Ja zu Mails an Nora", wortlaut_quelle: "rundgang:kontakt", titel: "Mails an Nora ohne Frage", ziel: "Nora frei", abnahme: "Wert gesetzt", abnahme_durch: "beleg",
    pruefer_noetig: false, verantwortlich: "seneca", auftraggeber: "seneca", bereich: "Privat", arbeitsart: "regel", herkunft: "rundgang",
    frage: { text: "Mails an Nora künftig ohne Frage?", was_passiert_ist: "Du hast dreimal Ja gesagt.", empfehlung: "Ja" }, wirkung: { wert: { schluessel: "kontakt:nora@example.org", wert: "frei" } },
  });
  frageBeantworten(p.db, { frage_id: String(offeneFrage(p.db, regel)?.id), antwort: "ja", geraet: "iphone", kennung: "j1" });
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.equal(wert(p.db, "kontakt:nora@example.org")?.wert, "frei");
  assert.equal(hole(p.db, "auftrag", regel).zustand, "erledigt");

  um("10:00", "2026-12-14");
  wertSetzen(p.db, "uhr_am_arm", "ja", "test", uhr.jetzt() + 600000);
  const vorschlag = (herkunft: string, titel: string) => p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", {
    art: "vorschlag", herkunft, wortlaut: titel, titel, ziel: "Antwort an Nora", abnahme: "Mail an Nora", an: "seneca", frist: uhr.jetzt() + 7200000,
  });
  const wa = await vorschlag("whatsapp", "Nora heute 18 Uhr zusagen");
  await zustellenJob(p.db);
  const q = uhrStand(p.db, uhr.jetzt()).q as { id: string } | null;
  assert.equal(q?.id, offeneFrage(p.db, wa.auftrag_id)?.id);
  assert.equal((p.methode("seneca.handeln", { kennung: "u1", geraet: "uhr", art: "frage.antwort", ziel: q?.id, wert: { wahl: "ja", lokal: true } }) as { ergebnis: string }).ergebnis, "angenommen");
  faelligeWirkungenJob(p.db);
  assert.equal(hole(p.db, "auftrag", wa.auftrag_id).zustand, "bereit");
  const leise = await vorschlag("sensor", "Telekom anrufen");
  await zustellenJob(p.db);
  assert.equal(JSON.parse(String(ereignisse(p.db, { art: "zustellung", frage_id: String(offeneFrage(p.db, leise.auftrag_id)?.id) })[0].daten)).was, "leise");
  spaeter(7300000);
  await zustellenJob(p.db);
  assert.equal(hole(p.db, "auftrag", leise.auftrag_id).zustand, "verworfen");
});

test("PF07 Geparkte Aufträge: Ja auf den Sammel-Vorschlag nimmt alle auf, einzeln nur auf Antonios Nachricht", async () => {
  const p = ladePlugin();
  um("10:00");
  const geparkt = ["Idee A", "Idee B", "Idee C"].map((w) => auftragVonAntonio(p.db, w, { art: "idee" }));
  const v = vorschlagAnlegen(p.db, { wortlaut: "Alte Aufträge", wortlaut_quelle: "umzug", titel: "3 alte Aufträge – welche wieder aufnehmen", ziel: "Antonio entscheidet", abnahme: "Antwort", abnahme_durch: "beleg",
    pruefer_noetig: false, verantwortlich: "seneca", auftraggeber: "seneca", bereich: "Privat", arbeitsart: "mechanisch", herkunft: "umzug",
    frage: { text: "3 alte Aufträge – welche wieder aufnehmen?", was_passiert_ist: "Idee A, Idee B, Idee C", empfehlung: "Alle", ja: "Alle 3" }, wirkung: { fortsetzen: geparkt.slice(0, 2) } });
  p.nachricht("agent:seneca:main", "m9", "Nimm Idee C wieder auf");
  assert.match((await p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", { art: "fortsetzen", auftrag_id: geparkt[2], nachricht_kennung: "m8" })).fehler, /Antonios Nachricht/);
  await p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", { art: "fortsetzen", auftrag_id: geparkt[2], nachricht_kennung: "m9" });
  frageBeantworten(p.db, { frage_id: String(offeneFrage(p.db, v)?.id), antwort: "ja", geraet: "mac", kennung: "m1" });
  spaeter(6000);
  faelligeWirkungenJob(p.db);
  assert.deepEqual(geparkt.map((id) => hole(p.db, "auftrag", id).zustand), ["bereit", "bereit", "bereit"]);
  assert.equal(hole(p.db, "auftrag", v).zustand, "erledigt");
});
