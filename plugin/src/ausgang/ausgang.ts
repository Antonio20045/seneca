import { createHash } from "node:crypto";
import { auftraege, ereignisse, fragen, hole, laufZurSitzung, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { auftragAnlegen, befund, ereignis, frageBeantworten, frageStellen } from "../register/schreiben.ts";
import { regelListe, regelText } from "../regeln.ts";
import { mandat } from "../team.ts";
import { normalisiere, stufe } from "./kontakte.ts";

type Aufruf = { werkzeug: string; params: Record<string, unknown>; sitzung: string; agent: string; aufrufId?: string };
type Daten = { kanal: string; empfaenger: string[]; stufe: string; werkzeug: string };
type Nachricht = { kennung: string; text: string; vonAntonio: boolean };
type Urteil = { block: true; blockReason: string } | undefined;

const STRENGE = ["frei", "kurz_fragen", "ausfuehrlich"];
const WORT: Record<string, string> = { anruf: "Anruf", live: "Live schalten", gateway: "Gateway-Neustart" };
const gestartet = new Map<string, string>();

function trifft(eintrag: string, a: Aufruf): boolean {
  const trenner = eintrag.indexOf("~");
  const werkzeug = trenner < 0 ? eintrag : eintrag.slice(0, trenner);
  if (!werkzeug.split("|").includes(a.werkzeug)) return false;
  const muster = eintrag.slice(trenner + 1);
  const gross = muster.startsWith("(?i)");
  const ziel = String(a.params.command ?? a.params.path ?? a.params.file_path ?? "");
  return trenner < 0 || new RegExp(gross ? muster.slice(4) : muster, gross ? "i" : "").test(ziel);
}

function gesperrt(a: Aufruf): boolean {
  return regelListe("aussen_gesperrt").some((e) => trifft(e, a));
}

function aussenWerkzeug(a: Aufruf): { kanal: string; freiwillig: boolean; roh: unknown } | undefined {
  const z = regelListe("aussen_werkzeuge").map((e) => e.split("/")).find(([w]) => trifft(w, a));
  if (!z) return undefined;
  const feld = z[2].replace("?", "");
  const roh = z[0].includes("~") ? String(a.params.command).match(new RegExp(`"${feld}"\\s*:\\s*"([^"]+)"`))?.[1] : a.params[feld];
  return { kanal: z[1], freiwillig: z[2].endsWith("?"), roh };
}

function liveArt(a: Aufruf): string | undefined {
  const befehl = [a.werkzeug, a.params.command, a.params.action].filter((x) => typeof x === "string").join(" ");
  if (new RegExp(regelText("gateway_muster")).test(befehl)) return "gateway";
  return new RegExp(regelText("live_muster")).test(befehl) ? "live" : undefined;
}

function sperre(db: Register, a: Aufruf, satz: string, auftragId?: string): Urteil {
  befund(db, { art: "gesperrt", auftrag_id: auftragId, satz: `${a.werkzeug}: ${satz}` });
  return { block: true, blockReason: satz };
}

function bezug(db: Register, a: Aufruf): string {
  const l = laufZurSitzung(db, a.sitzung);
  if (l && ["startet", "laeuft", "haengt"].includes(String(l.zustand))) return String(l.auftrag_id);
  const da = auftraege(db, ["geparkt"]).find((x) => x.arbeitsart === "aussenkontakt" && x.wortlaut_quelle === a.sitzung);
  if (da) return String(da.id);
  return auftragAnlegen(db, {
    art: "idee", wortlaut: `Außenkontakt aus dem Gespräch ${a.sitzung}`, wortlaut_quelle: a.sitzung, titel: `${a.werkzeug} aus dem Gespräch`, ziel: "Außenkontakt nach Freigabe",
    abnahme: "Ergebnis des Werkzeugs", abnahme_durch: "beleg", pruefer_noetig: false, verantwortlich: regelText("dauerauftraege_von"), auftraggeber: "antonio",
    quelle: "du", bereich: "Privat", arbeitsart: "aussenkontakt",
  }).id;
}

function freigabeGilt(db: Register, schluessel: string): "ja" | "wartet" | "nein" {
  const f = [...fragen(db, "beantwortet"), ...fragen(db, "offen")].find((x) => x.ausgang_schluessel === schluessel);
  if (!f) return "nein";
  if (f.zustand === "offen") return "wartet";
  const wirkt = ereignisse(db, { art: "frage.wirkt", frage_id: String(f.id), grenze: 1 }).length > 0;
  return f.antwort === "ja" && wirkt ? "ja" : f.antwort === "ja" ? "wartet" : "nein";
}

function starten(db: Register, a: Aufruf, schluessel: string, daten: object): Urteil {
  if (!ereignis(db, { art: "ausgang.gestartet", schluessel, daten }, true)) return { block: true, blockReason: "Schon ausgeführt. Nichts geht doppelt hinaus." };
  if (a.aufrufId) gestartet.set(a.aufrufId, schluessel);
  return undefined;
}

function vorWerkzeug(db: Register, a: Aufruf, n?: Nachricht): Urteil {
  if (gesperrt(a)) return sperre(db, a, "Dieses Werkzeug ist gesperrt.");
  const live = liveArt(a);
  if (live === "gateway" && a.agent !== regelText("bausystem")) return sperre(db, a, "Kein Agent startet das Gateway neu. Nur der Bauablauf mit Antonios Ja.");
  if (live === "gateway" || (live && mandat(a.agent).befugnisse.live_nur_mit_ja)) return freigeben(db, a, bezug(db, a), { kanal: live, empfaenger: [], stufe: "ausfuehrlich", werkzeug: a.werkzeug }, n);
  const w = aussenWerkzeug(a);
  if (!w) return undefined;
  const empfaenger = (Array.isArray(w.roh) ? w.roh : [w.roh]).filter((e): e is string => typeof e === "string" && e.length > 0).map(normalisiere);
  if (!empfaenger.length) return w.freiwillig ? undefined : sperre(db, a, "Empfänger nicht erkennbar.");
  const auftragId = bezug(db, a);
  const eigene = wert(db, "profil:telefon")?.wert;
  if (hole(db, "auftrag", auftragId).arbeitsart === "anruf_antonio" && eigene && empfaenger.every((e) => e === normalisiere(eigene))) {
    return starten(db, a, `anruf_antonio:${auftragId}`, { kanal: w.kanal, empfaenger, stufe: "eigene_nummer", werkzeug: a.werkzeug });
  }
  const stufen = empfaenger.map((e) => stufe(db, e));
  const unbekannt = empfaenger[stufen.indexOf(undefined)];
  if (unbekannt) {
    if (!fragen(db, "offen").some((f) => f.art === "stufe_festlegen" && f.ausgang_schluessel === unbekannt)) {
      frageStellen(db, {
        auftrag_id: auftragId, von: "ausgang", art: "stufe_festlegen", text: `Wer ist ${unbekannt}?`, ausgang_schluessel: unbekannt, wirkung_aussen: w.kanal,
        was_passiert_ist: `${a.werkzeug} soll ${unbekannt} erreichen. Der Kontakt hat noch keine Stufe.`, wenn_nichts: "Es geht nichts hinaus.", empfehlung: "kurz fragen",
        optionen: STRENGE.map((s) => ({ wert: s, text: s.replace("_", " "), folge: s === "frei" ? "Geht künftig ohne Frage hinaus." : "Vor jedem Kontakt kommt eine Frage." })),
      });
    }
    return sperre(db, a, `Unbekannter Empfänger ${unbekannt}: erst die Stufe festlegen. Nichts wurde gesendet.`, auftragId);
  }
  const strengste = STRENGE[Math.max(...stufen.map((s) => STRENGE.indexOf(String(s))))];
  return freigeben(db, a, auftragId, { kanal: w.kanal, empfaenger, stufe: strengste, werkzeug: a.werkzeug }, n);
}

function freigeben(db: Register, a: Aufruf, auftragId: string, daten: Daten, n?: Nachricht): Urteil {
  const inhalt = JSON.stringify(Object.fromEntries(Object.entries(a.params).sort()));
  const schluessel = createHash("sha256").update([auftragId, daten.kanal, daten.empfaenger.join(","), inhalt].join("|")).digest("hex");
  if (daten.stufe === "frei") return starten(db, a, schluessel, daten);
  const freigabe = freigabeGilt(db, schluessel);
  if (freigabe === "ja") return starten(db, a, schluessel, daten);
  if (freigabe === "wartet") return { block: true, blockReason: "Freigabe ist angefragt. Schreibe fort; nach der Freigabe startet dich der Arbeitsdienst neu." };
  const ausfuehrlich = daten.stufe === "ausfuehrlich";
  const ziel = daten.empfaenger.length ? `an ${daten.empfaenger.join(", ")}` : `über ${a.werkzeug}`;
  const frage = frageStellen(db, {
    auftrag_id: auftragId, von: "ausgang", art: ausfuehrlich ? "ausfuehrliches_ja" : "freigabe", wirkung_aussen: daten.kanal, ausgang_schluessel: schluessel,
    inhalt_hash: ausfuehrlich ? createHash("sha256").update(inhalt).digest("hex") : undefined, roh: inhalt,
    text: `${WORT[daten.kanal] ?? "Nachricht"} ${ziel} freigeben?`, was_passiert_ist: String(hole(db, "auftrag", auftragId).letzter_stand || hole(db, "auftrag", auftragId).titel),
    wenn_nichts: "Es geht nichts hinaus.", empfehlung: "Freigeben, wenn der Inhalt stimmt.",
    optionen: [{ wert: "ja", text: "Freigeben", folge: "Geht nach 5 Sekunden hinaus." }, { wert: "nein", text: "Nicht senden", folge: "Es geht nichts hinaus." }],
  });
  ereignis(db, { art: "ausgang.vorgemerkt", auftrag_id: auftragId, frage_id: frage, schluessel, daten });
  const eigenerBefehl = n?.vonAntonio && !ausfuehrlich && daten.empfaenger.some((e) => n.text.toLowerCase().includes(e)) && Object.values(a.params).some((v) => typeof v === "string" && v.length > 3 && n.text.includes(v));
  if (eigenerBefehl && n) frageBeantworten(db, { frage_id: frage, antwort: "ja", geraet: "gespraech", kennung: n.kennung });
  return { block: true, blockReason: eigenerBefehl ? "Dein Befehl gilt als Freigabe. In 5 Sekunden noch einmal aufrufen, dann geht es hinaus." : "Freigabe ist angefragt. Schreibe fort; nach der Freigabe startet dich der Arbeitsdienst neu." };
}

export function pruefeAufruf(db: Register, a: Aufruf, n?: Nachricht): Urteil {
  try {
    return vorWerkzeug(db, a, n);
  } catch (fehler) {
    const betroffen = aussenWerkzeug(a) || gesperrt(a) || liveArt(a);
    return betroffen ? { block: true, blockReason: `Ausgang gesperrt wegen Fehler: ${(fehler as Error).message}` } : undefined;
  }
}

export function nachWerkzeug(db: Register, aufrufId: string | undefined, fehler?: string): void {
  const schluessel = aufrufId ? gestartet.get(aufrufId) : undefined;
  if (!schluessel || !aufrufId) return;
  gestartet.delete(aufrufId);
  ereignis(db, { art: "ausgang.ergebnis", schluessel, daten: { ergebnis: fehler ? "fehlgeschlagen" : "ok", rueckmeldung: fehler ?? null } });
}

export function unklarePruefen(db: Register): void {
  const fertig = new Set(ereignisse(db, { art: "ausgang.ergebnis" }).map((e) => e.schluessel));
  for (const e of ereignisse(db, { art: "ausgang.gestartet" }).filter((x) => !fertig.has(x.schluessel))) {
    const d = JSON.parse(String(e.daten));
    ereignis(db, { art: "ausgang.ergebnis", schluessel: String(e.schluessel), daten: { ergebnis: "unklar" } });
    const v = ereignisse(db, { art: "ausgang.vorgemerkt", schluessel: String(e.schluessel), grenze: 1 })[0];
    const auftragId = v?.auftrag_id ? String(v.auftrag_id) : undefined;
    if (!auftragId) {
      befund(db, { art: "risiko", satz: `${d.werkzeug} an ${d.empfaenger.join(", ")} wurde vielleicht ausgeführt. Bitte prüfen.` });
      continue;
    }
    frageStellen(db, {
      auftrag_id: auftragId, von: "ausgang", art: "ja_nein", wirkung_aussen: "keine", text: `${d.werkzeug} an ${d.empfaenger.join(", ")} wurde vielleicht ausgeführt. Bitte prüfen.`,
      was_passiert_ist: "Der Server ist zwischen Start und Ergebnis ausgefallen.", wenn_nichts: "Es wird nichts wiederholt.", empfehlung: "Beim Empfänger nachsehen.",
      optionen: [{ wert: "ja", text: "Ist angekommen", folge: "Erledigt." }, { wert: "nein", text: "Ist nicht angekommen", folge: "Der Auftrag fragt neu." }],
    });
  }
}
