import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob, pflegenJob } from "../src/arbeitsdienst/jobs.ts";
import { auftraege, fragen, hole, laeufe } from "../src/register/lesen.ts";
import { anzeigeSetzen, auftragSetzen, ereignis, frageBeantworten, frageVertagen, laufAnlegen, laufEnde, laufSchritt, uebergang, wertSetzen } from "../src/register/schreiben.ts";
import { auftragVonAntonio, frischesRegister, jaNeinFrage, ladePlugin, nurWach, um } from "./aufbau.ts";

test("PF06 wartet nur mit Folge und Nachfasszeit", () => {
  const db = frischesRegister();
  const t = um("10:00");
  const auftrag = auftragVonAntonio(db, "Frag Nora nach den Zahlen");
  laufAnlegen(db, { auftrag_id: auftrag, mitarbeiter: "produkt", anlass: "neu", art: "werkzeug", ort: "server", stufe: "sonnet", modell: "m" });
  assert.throws(() => uebergang(db, "auftrag", auftrag, "wartet", "fortschreibung", { wartet_auf: "extern:nora" }), /folge, naechster_anlass/);
  assert.equal(hole(db, "auftrag", auftrag).zustand, "laeuft");
  uebergang(db, "auftrag", auftrag, "wartet", "fortschreibung", { wartet_auf: "extern:nora", folge: "Zahlen fehlen am Freitag", naechster_anlass: t + 3600000 });
  assert.equal(hole(db, "auftrag", auftrag).zustand, "wartet");
  assert.throws(() => uebergang(db, "auftrag", auftrag, "erledigt", "falsch"), /nicht erlaubt/);
});

test("PF06 Rundgang findet Feststeckendes, fasst nach, schlägt Regeln vor und legt einen eigenen Auftrag an", async () => {
  const p = ladePlugin();
  um("10:00", "2026-11-01");
  const anzeige = anzeigeSetzen(p.db, { projekt: "Hermes", art: "zahl", titel: "Testanrufe", werte: { zahl: 3 }, besitzer: "seneca" });
  const t = um("10:00", "2026-11-24");
  const nora = auftragVonAntonio(p.db, "Frag Nora nach den Zahlen");
  const lauf = laufAnlegen(p.db, { auftrag_id: nora, mitarbeiter: "produkt", anlass: "neu", art: "werkzeug", ort: "server", stufe: "sonnet", modell: "m" });
  uebergang(p.db, "auftrag", nora, "wartet", "fortschreibung", { wartet_auf: "extern:nora", folge: "Zahlen fehlen", naechster_anlass: t + 864000000 });
  laufSchritt(p.db, lauf, "frag Nora");
  laufEnde(p.db, lauf, "beendet", {});
  const website = auftragVonAntonio(p.db, "Prüf die Website");
  auftragSetzen(p.db, website, { fehlversuche: 3, naechster_anlass: t + 864000000 });
  const insta = auftragVonAntonio(p.db, "Instagram starten");
  const f = jaNeinFrage(p.db, insta, "Mit Instagram anfangen?");
  for (let i = 0; i < 3; i++) frageVertagen(p.db, f, t, "iphone");
  const mail = auftragVonAntonio(p.db, "Mails an Nora");
  for (let i = 0; i < 3; i++) {
    const g = jaNeinFrage(p.db, mail, `Mail ${i} an Nora freigeben?`, { art: "freigabe" });
    ereignis(p.db, { art: "ausgang.vorgemerkt", frage_id: g, schluessel: `k${i}`, daten: { stufe: "kurz_fragen", empfaenger: ["nora@example.org"] } });
    frageBeantworten(p.db, { frage_id: g, antwort: "ja", geraet: "iphone", kennung: `j${i}` });
  }
  wertSetzen(p.db, "kontakt:nora@example.org", "kurz_fragen", "antonio");
  um("08:20", "2026-11-27");
  pflegenJob(p.db, p.ordner);
  um("08:30", "2026-11-27");
  nurWach(p.db, "seneca");
  await faelligeAuftraegeJob(p.db, p.starte);
  const rundgang = auftraege(p.db, ["laeuft"]).find((a) => a.arbeitsart === "rundgang" && a.verantwortlich === "seneca");
  assert.ok(rundgang);
  const sitzung = String(laeufe(p.db, String(rundgang.id))[0].sitzung);
  const k = String(p.kontext(sitzung));
  assert.match(k, new RegExp(`${nora} .*wartet seit 2 Tagen auf extern:nora`));
  assert.match(k, new RegExp(`${website} .*startet nicht, 3 Versuche`));
  assert.match(k, /3-mal vertagt/);
  const vorschlaege = fragen(p.db, "offen").filter((x) => x.art === "vorschlag").map((x) => String(x.text));
  assert.deepEqual(vorschlaege.sort(), ["Kann „Testanrufe“ weg?", "Nachrichten an nora@example.org künftig ohne Frage?", "„Instagram starten“ parken?"]);
  assert.equal(hole(p.db, "anzeige", anzeige).zustand, "grau");
  const nach = (id: string) => p.werkzeug("seneca_auftrag", sitzung, "seneca", { art: "nachfassen", auftrag_id: id, satz: "Nora hat sich nicht gemeldet. Erinnere sie heute." });
  await nach(nora);
  assert.equal(hole(p.db, "auftrag", nora).zustand, "bereit");
  assert.match(String((await nach(nora)).satz), /Schon nachgefasst/);
  await nach(website);
  assert.equal(Number(hole(p.db, "auftrag", website).fehlversuche), 0);
  assert.match(String((await p.werkzeug("seneca_auftrag", "agent:seneca:main", "seneca", { art: "nachfassen", auftrag_id: nora, satz: "x" })).fehler), /laufenden Seneca-Lauf/);
  const eigen = await p.werkzeug("seneca_auftrag", sitzung, "seneca", { art: "eigener", wortlaut: "Statusfragen zählen", ziel: "Anzeige zeigt Statusfragen je Woche", abnahme: "Anzeige gesetzt" });
  assert.equal(hole(p.db, "auftrag", eigen.auftrag_id).quelle, "eigene_idee");
  assert.equal(hole(p.db, "auftrag", eigen.auftrag_id).zustand, "bereit");
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.equal(fragen(p.db, "offen").filter((x) => x.art === "vorschlag").length, 3);
});
