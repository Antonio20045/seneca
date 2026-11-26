import assert from "node:assert/strict";
import { test } from "node:test";
import { ruhe, uhrStand } from "../src/pforte/stand.ts";
import { ereignisse } from "../src/register/lesen.ts";
import { wertSetzen } from "../src/register/schreiben.ts";
import { schluesselHash, uhrAbgleich, uhrAbholen, uhrKoppeln } from "../src/zugang/uhr.ts";
import { auftragVonAntonio, jaNeinFrage, ladePlugin, um } from "./aufbau.ts";

test("PF08 Uhr allein: 14 Sätze, zweimal gesendet, genau 14 Einträge; Außen-Frage nur als Hinweis; gesperrt abgewiesen", () => {
  const p = ladePlugin();
  const t = um("07:30");
  wertSetzen(p.db, "uhr:uhr1", schluesselHash("geheim-uhr1"), "iphone");
  jaNeinFrage(p.db, auftragVonAntonio(p.db, "Angebot senden"), "Angebot an Kunden senden?", { wirkung_aussen: "mail", frist: um("12:00") });
  um("08:30");
  const saetze = Array.from({ length: 14 }, (_, i) => ({ id: `s${i}`, t: Math.floor(t / 1000) + i, a: "eintrag.neu", p: { k: "satz", u: "kniebeuge", kg: 60, w: 8, n: i + 1 }, lokal: true }));
  const kopf = { authorization: "Bearer geheim-uhr1" };
  const senden = (h: typeof saetze) => uhrAbgleich(p.db, Buffer.from(JSON.stringify({ v: 1, g: "uhr1", r: 0, h, zs: "training", k: { bb: [64, Math.floor(t / 1000) + 3600], st: 20, sc: 4000 } })), kopf, (j) => uhrStand(p.db, j));
  for (const stapel of [saetze.slice(0, 7), saetze.slice(7), saetze.slice(0, 7), saetze.slice(7)]) assert.equal(senden(stapel).status, 200);
  const antwort = senden([]).inhalt as { s: { q: unknown; h: string; reg: { q: number } } };
  const eintraege = p.db.prepare("SELECT werte FROM eintrag ORDER BY zeit").all().map((z) => JSON.parse(String(z.werte)).n);
  assert.deepEqual(eintraege, Array.from({ length: 14 }, (_, i) => i + 1));
  assert.equal(antwort.s.q, null);
  assert.match(antwort.s.h, /am Mac/);
  assert.equal(antwort.s.reg.q, 500);
  assert.equal(ereignisse(p.db, { art: "wert.gesetzt", schluessel: "aktivitaet" }).length, 1);
  assert.deepEqual((p.methode("seneca.stand", { geraet: "mac" }) as { koerper: unknown }).koerper, { body_battery: 64, zeit: (Math.floor(t / 1000) + 3600) * 1000, stress: 20, schritte: 4000, morgens: 64, titel: "Body Battery nach dem Training", hinweis: null });
  p.methode("seneca.handeln", { kennung: "sp1", geraet: "iphone", art: "geraet.sperren", ziel: "uhr1", wert: "gesperrt" });
  assert.equal(senden(saetze).status, 401);
});

test("PF08 Koppeln mit Zahlenvergleich: Schlüssel nur nach Bestätigung, genau einmal", () => {
  const p = ladePlugin();
  um("09:00");
  const json = (o: object) => Buffer.from(JSON.stringify(o));
  assert.equal(uhrKoppeln(p.db, json({ g: "uhr2" })).status, 403);
  p.methode("seneca.handeln", { kennung: "k1", geraet: "iphone", art: "geraet.uhr_koppeln" });
  const k = uhrKoppeln(p.db, json({ g: "uhr2" })).inhalt as { zahl: string; abholen: string };
  assert.match(k.zahl, /^\d{4}$/);
  assert.deepEqual((p.methode("seneca.stand", { geraet: "iphone" }) as { kopplung: object[] }).kopplung, [{ geraet: "uhr2", zahl: k.zahl }]);
  assert.equal(uhrAbholen(p.db, json({ g: "uhr2", abholen: k.abholen })).status, 403);
  assert.match((p.methode("seneca.handeln", { kennung: "k2", geraet: "iphone", art: "geraet.uhr_bestaetigen", ziel: "uhr2", wert: "0000x" }) as { ergebnis: string }).ergebnis, /zahl_passt_nicht/);
  p.methode("seneca.handeln", { kennung: "k3", geraet: "iphone", art: "geraet.uhr_bestaetigen", ziel: "uhr2", wert: k.zahl });
  const a = uhrAbholen(p.db, json({ g: "uhr2", abholen: k.abholen }));
  assert.equal(a.status, 200);
  assert.equal(uhrAbholen(p.db, json({ g: "uhr2", abholen: k.abholen })).status, 403);
  const schluessel = (a.inhalt as { schluessel: string }).schluessel;
  const abgleich = uhrAbgleich(p.db, json({ v: 1, g: "uhr2", r: 0, h: [] }), { authorization: `Bearer ${schluessel}` }, (j) => uhrStand(p.db, j));
  assert.equal(abgleich.status, 200);
});

test("PF08 Frage an der Uhr: Herkunft und Später-Zeit im Stand, am iPhone schon beantwortet meldet Wahl, Gerät, Zeit", () => {
  const p = ladePlugin();
  const frist = um("18:00", "2026-11-28");
  um("13:40");
  wertSetzen(p.db, "uhr:uhr3", schluesselHash("geheim-uhr3"), "iphone");
  const frage = jaNeinFrage(p.db, auftragVonAntonio(p.db, "Instagram"), "Soll Hermes mit Instagram anfangen?", { frist });
  const senden = (h: object[]) => uhrAbgleich(p.db, Buffer.from(JSON.stringify({ v: 1, g: "uhr3", r: 0, h })), { authorization: "Bearer geheim-uhr3" }, (j) => uhrStand(p.db, j)).inhalt as { q: string[][]; s: { q: { id: string; v: string; s: number; sb: number } } };
  const stand = senden([]).s.q;
  assert.equal(stand.id, frage);
  assert.equal(typeof stand.v, "string");
  assert.equal(stand.sb, new Date("2026-11-27T16:00:00").getTime() / 1000);
  assert.ok(stand.sb > stand.s);
  const am = um("13:49");
  p.methode("seneca.handeln", { kennung: "a1", geraet: "iphone", art: "frage.antwort", ziel: frage, wert: { wahl: "ja" } });
  um("13:51");
  assert.deepEqual(senden([{ id: "u1", t: Math.floor(am / 1000) + 60, a: "frage.antwort", p: { f: frage, w: "nein" } }]).q, [["u1", `sb:ja,iphone,${am}`]]);
});

test("PF08 Lauf-Ruhe: Trail-Datenfeld hält Seneca still, die App im Hintergrund hebt das nicht auf, nach 12 Min ohne Meldung endet sie", () => {
  const p = ladePlugin();
  um("10:00");
  wertSetzen(p.db, "uhr:uhr4", schluesselHash("geheim-uhr4"), "iphone");
  const senden = (zs: string) => uhrAbgleich(p.db, Buffer.from(JSON.stringify({ v: 1, g: "uhr4", r: -1, h: [], zs })), { authorization: "Bearer geheim-uhr4" }, (j) => uhrStand(p.db, j)).inhalt as { s?: object };
  assert.equal(senden("trail").s, undefined);
  um("10:04");
  senden("leer");
  assert.equal(ruhe(p.db, um("10:05"))?.grund, "trail");
  assert.equal(ruhe(p.db, um("10:13")), undefined);
});
