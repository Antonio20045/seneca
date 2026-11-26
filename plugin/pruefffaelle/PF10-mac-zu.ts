import assert from "node:assert/strict";
import { test } from "node:test";
import { faelligeAuftraegeJob } from "../src/arbeitsdienst/jobs.ts";
import { kalenderAbgleich } from "../src/quellen/kalender.ts";
import { planenJob } from "../src/pforte/planen.ts";
import { ereignisse, laeufe, termineAm, todos, wert } from "../src/register/lesen.ts";
import { wertSetzen } from "../src/register/schreiben.ts";
import { auftragVonAntonio, kalenderAttrappe, ladePlugin, regelnMit, spaeter, um } from "./aufbau.ts";

test("PF10 Mac zu: Textarbeit mit Stufe lokal läuft auf Haiku am Server, kein Doppellauf, kein Befund „Mac nicht erreichbar“", async () => {
  const p = ladePlugin();
  um("23:10");
  const a = auftragVonAntonio(p.db, "Fasse das Meeting zusammen", { verantwortlich: "seneca", arbeitsart: "zusammenfassen" });
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  await faelligeAuftraegeJob(p.db, p.starte);
  const l = laeufe(p.db, a);
  assert.equal(l.length, 1);
  assert.equal(l[0].stufe, "haiku");
  assert.equal(l[0].ort, "server");
  assert.match(p.starts[0].model, /haiku/);
  assert.ok(!ereignisse(p.db, { art: "befund" }).some((b) => String(b.satz).includes("Mac")));
  assert.deepEqual(p.starts[0].werkzeuge, []);
  wertSetzen(p.db, "knoten", JSON.stringify([{ name: "mac-studio", ollama: true }]), "arbeitsdienst");
  auftragVonAntonio(p.db, "Fasse das Telefonat zusammen", { verantwortlich: "seneca", arbeitsart: "zusammenfassen" });
  spaeter(6000);
  await faelligeAuftraegeJob(p.db, p.starte);
  assert.deepEqual(p.starts[1].werkzeuge, ["node_inference"]);
  assert.match(p.starts[1].message, /node_inference/);
});

test("PF10 „Verschieb den Zahnarzt“ wirkt ohne Mac; Konflikt wird gemeldet, nicht überschrieben", async () => {
  const morgen = (hhmm: string) => new Date(`2026-11-28T${hhmm}:00`).getTime();
  const ics = (uid: string, titel: string, von: string, bis: string) =>
    `BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:${uid}\r\nSUMMARY:${titel}\r\nDTSTART:${new Date(morgen(von)).toISOString().replace(/[-:]/g, "").slice(0, 15)}Z\r\nDTEND:${new Date(morgen(bis)).toISOString().replace(/[-:]/g, "").slice(0, 15)}Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n`;
  const attrappe = await kalenderAttrappe(new Map([["zahn", ics("zahn", "Zahnarzt", "10:00", "11:00")], ["call", ics("call", "Call Nora", "14:30", "15:00")]]));
  const zurueck = regelnMit({ caldav_url: attrappe.url });
  const zugang = { benutzer: "antonio", passwort: "app-passwort" };
  const p = ladePlugin(undefined, { kalender: zugang });
  um("20:00");
  await kalenderAbgleich(p.db, zugang);
  assert.deepEqual(termineAm(p.db, morgen("00:00")).map((t) => t.titel), ["Zahnarzt", "Call Nora"]);
  const konflikt = await p.werkzeug("seneca_kalender", "agent:seneca:main", "seneca", { aktion: "verschieben", uid: "zahn", start: morgen("14:00"), ende: morgen("15:00") });
  assert.deepEqual(konflikt.konflikte, ["Call Nora"]);
  assert.ok(!attrappe.aufrufe.some((a) => a.startsWith("PUT")));
  const r = await p.werkzeug("seneca_kalender", "agent:seneca:main", "seneca", { aktion: "verschieben", uid: "zahn", start: morgen("16:00"), ende: morgen("17:00") });
  assert.equal(r.ok, true);
  assert.equal(termineAm(p.db, morgen("00:00")).find((t) => t.uid === "zahn")?.start, morgen("16:00"));
  assert.match(String((await p.werkzeug("seneca_kalender", "agent:produkt:main", "produkt", { aktion: "anlegen", start: morgen("18:00") })).fehler), /Nur Seneca/);
  zurueck();
  attrappe.server.close();
});

test("PF10 Tagesplan am Server: To-dos in Lücken (1,5 × Dauer), Fenster bleibt frei, Los-Hinweis mit Ankunft", () => {
  const p = ladePlugin();
  um("08:00");
  const termin = (uid: string, von: string, bis: string, titel: string, ort?: string) => ({ uid, start: um(von), ende: um(bis), titel, ort, teilnehmer: [], ganztag: false });
  wertSetzen(p.db, "kalender:2026-11-27", JSON.stringify([termin("a", "08:00", "09:00", "Training"), termin("b", "09:40", "15:30", "Workshop"), termin("c", "17:00", "21:00", "Essen", "Bergstr. 1")]), "kalender");
  const todo = (titel: string, dauer_min: number) => p.werkzeug("seneca_todo", "agent:seneca:main", "seneca", { aktion: "anlegen", felder: { titel, dauer_min } });
  um("08:00");
  return Promise.all([todo("Mail an Steuerberater", 20), todo("Angebot schreiben", 20), todo("Ablage sortieren", 90)]).then(() => {
    planenJob(p.db);
    const plan = Object.fromEntries(todos(p.db, "offen").map((t) => [t.titel, t.geplant_von]));
    assert.equal(plan["Mail an Steuerberater"], um("09:00"));
    assert.equal(plan["Angebot schreiben"], um("15:30"));
    assert.equal(plan["Ablage sortieren"], null);
    const ankunft = um("17:10");
    um("16:10");
    wertSetzen(p.db, "ankunft:c", String(ankunft), "seneca");
    wertSetzen(p.db, "wegzeit:c", "25", "iphone");
    planenJob(p.db);
    assert.equal(wert(p.db, "hinweis:los")?.wert, "Essen in Bergstr. 1: an um 17:10 · los um 16:45");
  });
});
