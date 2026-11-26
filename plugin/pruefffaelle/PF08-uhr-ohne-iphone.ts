import assert from "node:assert/strict";
import { test } from "node:test";
import { uhrStand } from "../src/pforte/stand.ts";
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
  const senden = (h: typeof saetze) => uhrAbgleich(p.db, Buffer.from(JSON.stringify({ v: 1, g: "uhr1", r: 0, h, zs: "training" })), kopf, (j) => uhrStand(p.db, j));
  for (const stapel of [saetze.slice(0, 7), saetze.slice(7), saetze.slice(0, 7), saetze.slice(7)]) assert.equal(senden(stapel).status, 200);
  const antwort = senden([]).inhalt as { s: { q: unknown; h: string; reg: { q: number } } };
  const eintraege = p.db.prepare("SELECT werte FROM eintrag ORDER BY zeit").all().map((z) => JSON.parse(String(z.werte)).n);
  assert.deepEqual(eintraege, Array.from({ length: 14 }, (_, i) => i + 1));
  assert.equal(antwort.s.q, null);
  assert.match(antwort.s.h, /am Mac/);
  assert.equal(antwort.s.reg.q, 500);
  assert.equal(ereignisse(p.db, { art: "wert.gesetzt", schluessel: "aktivitaet" }).length, 1);
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
