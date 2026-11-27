import { randomBytes } from "node:crypto";
import type { SQLInputValue } from "node:sqlite";
import { letzteUhrzeit, regelMs, regelText, regelZahl } from "../regeln.ts";
import { hole, kinder, offeneFrage, revision, uhr, zurueckgenommen, type Tabelle, type Zeile } from "./lesen.ts";
import type { Register } from "./schema.ts";
import { NEBENWIRKUNGEN, NEU, PFLICHT_BEI, UEBERGAENGE } from "./uebergaenge.ts";

type Maschine = keyof typeof UEBERGAENGE;
type Felder = Record<string, SQLInputValue>;
type Ereignis = {
  art: string; wer?: string; geraet?: string; auftrag_id?: string; frage_id?: string; lauf_id?: string;
  schluessel?: string; daten?: unknown; satz?: string; beleg?: string;
};
type Option = { wert: string; text: string; folge: string; titel?: string; preis?: string; einheit?: string };

function neueId(): string {
  return uhr.jetzt().toString(36).padStart(9, "0") + randomBytes(4).toString("hex");
}

export function schritt<T>(db: Register, f: () => T): T {
  if (db.isTransaction) return f();
  db.exec("BEGIN IMMEDIATE");
  let fertig = false;
  try {
    const r = f();
    db.exec("COMMIT");
    fertig = true;
    return r;
  } finally {
    if (!fertig) db.exec("ROLLBACK");
  }
}

export function ereignis(db: Register, e: Ereignis, einmal = false): number {
  const daten = e.daten === undefined ? null : JSON.stringify(e.daten);
  if (daten && daten.length > regelZahl("ereignis_daten_max_bytes")) throw new Error(`ereignis ${e.art}: daten zu gross`);
  const r = db.prepare(`INSERT ${einmal ? "OR IGNORE " : ""}INTO ereignis (zeit, art, wer, geraet, auftrag_id, frage_id, lauf_id, schluessel, daten, satz, beleg)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(uhr.jetzt(), e.art, e.wer ?? null, e.geraet ?? null, e.auftrag_id ?? null,
    e.frage_id ?? null, e.lauf_id ?? null, e.schluessel ?? null, daten, e.satz ?? null, e.beleg ?? null);
  return r.changes ? Number(r.lastInsertRowid) : 0;
}

function regel(art: Maschine, von: string, nach: string) {
  const r = UEBERGAENGE[art].find((u) => u.nach === nach && (u.von as readonly string[]).includes(von));
  if (!r) throw new Error(`Übergang nicht erlaubt: ${art} ${von} → ${nach}`);
  return r;
}

function pflicht(nr: string, nach: string, z: Felder): void {
  const fehlt = (PFLICHT_BEI[nach as keyof typeof PFLICHT_BEI] ?? []).filter((f) => z[f] === null || z[f] === undefined || z[f] === "");
  if (fehlt.length) throw new Error(`${nr}: ${fehlt.join(", ")} fehlt`);
}

function einfuegen(db: Register, tabelle: Tabelle, z: Felder): void {
  const k = Object.keys(z);
  db.prepare(`INSERT INTO ${tabelle} (${k.join(", ")}) VALUES (${k.map(() => "?").join(", ")})`).run(...Object.values(z));
}

function setzen(db: Register, tabelle: Tabelle, id: string, z: Felder): void {
  const k = Object.keys(z);
  db.prepare(`UPDATE ${tabelle} SET ${k.map((x) => `${x} = ?`).join(", ")} WHERE id = ?`).run(...Object.values(z), id);
}

const WIRKUNG: Record<string, (db: Register, id: string, nach: string) => void> = {
  frage_zurueckziehen: (db, id, nach) => {
    const f = offeneFrage(db, id);
    if (f) uebergang(db, "frage", String(f.id), "zurueckgezogen", "auftrag", { grund: `Der Auftrag ist jetzt ${nach}.` });
  },
  eltern_wecken: (db, id) => {
    const e = hole(db, "auftrag", id).eltern_id;
    if (e && hole(db, "auftrag", String(e)).zustand === "wartet") uebergang(db, "auftrag", String(e), "bereit", "kind_fertig", { naechster_anlass: uhr.jetzt() });
  },
  kinder_verwerfen: (db, id) => {
    for (const k of kinder(db, id)) {
      if (!["erledigt", "verworfen"].includes(String(k.zustand))) uebergang(db, "auftrag", String(k.id), "verworfen", "eltern_verworfen");
    }
  },
};

export function uebergang(db: Register, art: Maschine, id: string, nach: string, anlass: string, felder: Felder = {}): void {
  schritt(db, () => {
    const alt = hole(db, art, id);
    const von = String(alt.zustand);
    const r = regel(art, von, nach);
    pflicht(r.nr, nach, felder);
    const extra: Felder = art === "auftrag" ? { geaendert: uhr.jetzt(), anlass } : {};
    setzen(db, art, id, { ...felder, ...extra, zustand: nach });
    const bezug = art === "auftrag" ? id : alt.auftrag_id ? String(alt.auftrag_id) : undefined;
    ereignis(db, { art: "uebergang", auftrag_id: bezug, frage_id: art === "frage" ? id : undefined, lauf_id: art === "lauf" ? id : undefined,
      schluessel: art === "todo" ? id : undefined, daten: { art, von, nach, anlass, nr: r.nr } });
    for (const n of NEBENWIRKUNGEN) {
      if (n.art === art && (n.von === von || n.von === "*") && (n.nach === nach || n.nach === "*")) WIRKUNG[n.wirkung](db, id, nach);
    }
  });
}

export type NeuerAuftrag = {
  art: "auftrag" | "unterauftrag" | "vorschlag" | "idee" | "dauerauftrag" | "system" | "eigener";
  wortlaut: string; wortlaut_quelle: string; titel: string; ziel: string; abnahme: string; abnahme_durch: string;
  pruefer_noetig: boolean; verantwortlich: string; auftraggeber: string; quelle: string; bereich: string; arbeitsart: string;
  eltern_id?: string; projekt?: string; schaetzung_min?: number; frist?: number; naechster_anlass?: number;
  nachricht?: { kennung: string; text: string };
};

const START = { auftrag: "bereit", unterauftrag: "bereit", dauerauftrag: "bereit", system: "bereit", eigener: "bereit", vorschlag: "vorgeschlagen", idee: "geparkt" };

function verbrauchtAls(db: Register, kennung: string): string | undefined {
  const z = db.prepare("SELECT art FROM ereignis WHERE schluessel = ? AND art IN ('auftrag.angelegt', 'nachricht.verbraucht') LIMIT 1").get(kennung);
  return z ? (z.art === "auftrag.angelegt" ? "auftrag" : "antwort") : undefined;
}

export function auftragAnlegen(db: Register, a: NeuerAuftrag, zusatz: object = {}): { id: string; kostenrahmen_cent: number } {
  return schritt(db, () => {
    const fehlt = (["wortlaut", "ziel", "abnahme", "verantwortlich", "arbeitsart", "bereich"] as const).filter((f) => !a[f]);
    if (fehlt.length) throw new Error(`Auftrag: ${fehlt.join(", ")} fehlt`);
    if (a.art === "auftrag" && !a.nachricht?.text.includes(a.wortlaut)) throw new Error("Der Wortlaut steht so nicht in der Nachricht.");
    if (a.nachricht && verbrauchtAls(db, a.nachricht.kennung) === "antwort") throw new Error("Diese Nachricht war schon eine Antwort.");
    if (a.art === "unterauftrag" && !a.eltern_id) throw new Error("Unterauftrag braucht eltern_id.");
    const zustand = START[a.art];
    regel("auftrag", NEU, zustand);
    const id = neueId();
    const t = uhr.jetzt();
    const rahmen = a.schaetzung_min ? Math.round(a.schaetzung_min * regelZahl("cent_je_minute")) : regelZahl("kostenrahmen_standard_cent");
    const { art, nachricht, pruefer_noetig, ...rest } = a;
    einfuegen(db, "auftrag", {
      ...rest, eltern_id: a.eltern_id ?? null, projekt: a.projekt ?? null, schaetzung_min: a.schaetzung_min ?? null, frist: a.frist ?? null,
      id, zustand, pruefer_noetig: pruefer_noetig ? 1 : 0, kostenrahmen_cent: rahmen, anlass: "neu", erstellt: t, geaendert: t,
      naechster_anlass: a.naechster_anlass ?? (zustand === "bereit" ? t + regelMs("rueckgaengig_s") : null),
    });
    ereignis(db, { art: "auftrag.angelegt", wer: a.auftraggeber, auftrag_id: id, schluessel: nachricht?.kennung, satz: a.titel,
      daten: { art, quelle: a.quelle, eltern_id: a.eltern_id, zustand, ...zusatz } });
    return { id, kostenrahmen_cent: rahmen };
  });
}

export function auftragSetzen(db: Register, id: string, felder: Felder, satz?: string): void {
  if ("zustand" in felder) throw new Error("Zustand nur über uebergang()");
  schritt(db, () => {
    setzen(db, "auftrag", id, { ...felder, geaendert: uhr.jetzt() });
    ereignis(db, { art: "auftrag.geaendert", auftrag_id: id, daten: felder, satz });
  });
}

export type Wirkung = { todo?: Felder; wert?: { schluessel: string; wert: string }; parken?: string; fortsetzen?: string[]; anzeige_weg?: string; termin?: { titel: string; start: number; ende: number; ort?: string } };
type NeuerVorschlag = Omit<NeuerAuftrag, "art" | "quelle"> & { herkunft: string; frage: { text: string; was_passiert_ist: string; empfehlung: string; frist?: number; ja?: string }; wirkung?: Wirkung };

export function vorschlagAnlegen(db: Register, v: NeuerVorschlag): string {
  return schritt(db, () => {
    const { herkunft, frage: { ja, ...frage }, wirkung, ...a } = v;
    const frist = frage.frist ?? (wirkung?.termin ? letzteUhrzeit(regelText("vorschlag_verfaellt_uhr"), new Date(wirkung.termin.start).setHours(0, 0, 0, 0)) : undefined);
    const { id } = auftragAnlegen(db, { ...a, art: "vorschlag", quelle: "vorschlag" }, { herkunft, wirkung });
    frageStellen(db, {
      auftrag_id: id, von: a.auftraggeber, art: "vorschlag", ...frage, frist, wenn_nichts: "Der Vorschlag verfällt.",
      optionen: [{ wert: "ja", text: ja ?? "Ja", folge: wirkung ? "Seneca übernimmt das so." : "Daraus wird ein Auftrag." }, { wert: "nein", text: "Nein", folge: "Der Vorschlag wird verworfen." }],
    });
    return id;
  });
}

export type NeueFrage = {
  auftrag_id: string; von: string; text: string; was_passiert_ist: string; wenn_nichts: string; empfehlung: string;
  art: string; optionen: Option[]; roh?: string; wirkung_aussen?: string; ausgang_schluessel?: string; inhalt_hash?: string; frist?: number; kurz?: string; zeit_fuer?: string; mehr?: Record<string, unknown>;
};

export function frageStellen(db: Register, { kurz, zeit_fuer, mehr, ...f }: NeueFrage): string {
  return schritt(db, () => {
    const fehlt = (["text", "was_passiert_ist", "wenn_nichts", "empfehlung", "art"] as const).filter((k) => !f[k]);
    if (fehlt.length || !f.optionen.length || f.optionen.some((o) => !o.folge)) throw new Error(`Frage unvollständig: ${[...fehlt, "optionen mit folge"].join(", ")}`);
    regel("frage", NEU, "offen");
    hole(db, "auftrag", f.auftrag_id);
    const id = neueId();
    const alt = offeneFrage(db, f.auftrag_id);
    if (alt) uebergang(db, "frage", String(alt.id), "ersetzt", "neue Frage", { ersetzt_durch: id });
    const optionen = f.optionen.some((o) => o.wert === "spaeter") ? f.optionen : [...f.optionen, { wert: "spaeter", text: "Später", folge: f.wenn_nichts }];
    einfuegen(db, "frage", {
      ...f, roh: f.roh ?? null, wirkung_aussen: f.wirkung_aussen ?? "keine", ausgang_schluessel: f.ausgang_schluessel ?? null,
      inhalt_hash: f.inhalt_hash ?? null, frist: f.frist ?? null, id, optionen: JSON.stringify(optionen), zustand: "offen", gestellt: uhr.jetzt(),
    });
    ereignis(db, { art: "frage.gestellt", wer: f.von, auftrag_id: f.auftrag_id, frage_id: id, satz: f.text, daten: { art: f.art, wirkung_aussen: f.wirkung_aussen ?? "keine", kurz, zeit_fuer, ...mehr } });
    return id;
  });
}

export type Antwort = { frage_id: string; antwort: string; geraet: string; kennung: string; lokal?: boolean; inhalt_hash?: string; nachricht_kennung?: string };
type AntwortErgebnis = { ergebnis: "angenommen" } | { ergebnis: "schon_beantwortet"; wahl: string; geraet: string; um: number } | { ergebnis: "abgelehnt"; grund: string };

export function frageBeantworten(db: Register, a: Antwort): AntwortErgebnis {
  return schritt(db, () => {
    const f = hole(db, "frage", a.frage_id);
    if (f.zustand === "beantwortet") return { ergebnis: "schon_beantwortet", wahl: String(f.antwort), geraet: String(f.antwort_geraet), um: Number(f.antwort_um) };
    if (f.zustand !== "offen") return { ergebnis: "abgelehnt", grund: String(f.zustand) };
    if (!(JSON.parse(String(f.optionen)) as Option[]).some((o) => o.wert === a.antwort)) return { ergebnis: "abgelehnt", grund: "unbekannte_wahl" };
    if (f.art === "ausfuehrliches_ja" && a.antwort === "ja" && (!["mac", "iphone"].includes(a.geraet) || a.inhalt_hash !== f.inhalt_hash)) {
      return { ergebnis: "abgelehnt", grund: "nur_mit_ganzem_inhalt" };
    }
    if (a.nachricht_kennung) {
      if (verbrauchtAls(db, a.nachricht_kennung)) return { ergebnis: "abgelehnt", grund: "nachricht_schon_verbraucht" };
      ereignis(db, { art: "nachricht.verbraucht", schluessel: a.nachricht_kennung, frage_id: a.frage_id, daten: { als: "antwort" } });
    }
    const t = uhr.jetzt();
    uebergang(db, "frage", a.frage_id, "beantwortet", "antwort", {
      antwort: a.antwort, antwort_geraet: a.geraet, antwort_um: t, antwort_kennung: a.kennung, wirkt_ab: a.lokal ? t : t + regelMs("rueckgaengig_s"),
    });
    return { ergebnis: "angenommen" };
  });
}

export function frageZuruecknehmen(db: Register, frageId: string): "angenommen" | "zu_spaet" {
  return schritt(db, () => {
    const f = hole(db, "frage", frageId);
    if (f.zustand !== "beantwortet" || uhr.jetzt() >= Number(f.wirkt_ab) || hatWirkung(db, frageId)) return "zu_spaet";
    uebergang(db, "frage", frageId, "offen", "rueckgaengig", { antwort: null, antwort_geraet: null, antwort_um: null, antwort_kennung: null, wirkt_ab: null });
    return "angenommen";
  });
}

function hatWirkung(db: Register, frageId: string): boolean {
  return !!db.prepare("SELECT 1 FROM ereignis WHERE art = 'frage.wirkt' AND frage_id = ?").get(frageId);
}

export function frageVertagen(db: Register, frageId: string, bis: number, geraet: string): void {
  const f = hole(db, "frage", frageId);
  if (f.zustand !== "offen") throw new Error(`Frage ist ${f.zustand}.`);
  ereignis(db, { art: "frage.vertagt", frage_id: frageId, auftrag_id: String(f.auftrag_id), geraet, daten: { bis } });
}

export function frageWirkt(db: Register, frageId: string): boolean {
  return schritt(db, () => {
    if (hatWirkung(db, frageId)) return false;
    const f = hole(db, "frage", frageId);
    ereignis(db, { art: "frage.wirkt", frage_id: frageId, auftrag_id: String(f.auftrag_id), daten: { antwort: f.antwort } });
    return true;
  });
}

export function handlung(db: Register, h: { kennung: string; geraet: string; art: string; ziel?: string }, wirkung: () => string): string {
  return schritt(db, () => {
    if (db.prepare("SELECT 1 FROM ereignis WHERE art = 'handlung' AND schluessel = ?").get(h.kennung)) return "doppelt";
    const ergebnis = wirkung();
    ereignis(db, { art: "handlung", geraet: h.geraet, schluessel: h.kennung, daten: { art: h.art, ziel: h.ziel, ergebnis } });
    return ergebnis;
  });
}

export function wertSetzen(db: Register, schluessel: string, wert: string, wer: string, gueltigBis?: number): number {
  return ereignis(db, { art: "wert.gesetzt", wer, schluessel, daten: { wert, gueltig_bis: gueltigBis } });
}

export function befund(db: Register, b: { art: string; satz: string; auftrag_id?: string; lauf_id?: string; beleg?: string; daten?: object }): number {
  return ereignis(db, { art: "befund", auftrag_id: b.auftrag_id, lauf_id: b.lauf_id, satz: b.satz, beleg: b.beleg, daten: { art: b.art, ...b.daten } });
}

type NeuerLauf = { auftrag_id: string; mitarbeiter: string; anlass: string; art: string; ort: string; stufe: string; modell: string; abo?: string };

export function laufAnlegen(db: Register, l: NeuerLauf): string {
  return schritt(db, () => {
    regel("lauf", NEU, "startet");
    uebergang(db, "auftrag", l.auftrag_id, "laeuft", l.anlass);
    const id = neueId();
    const t = uhr.jetzt();
    einfuegen(db, "lauf", { ...l, abo: l.abo ?? null, id, zustand: "startet", sitzung: `agent:${l.mitarbeiter}:subagent:lauf-${id}`, gestartet: t, letzter_schritt_um: t });
    ereignis(db, { art: "lauf.start", auftrag_id: l.auftrag_id, lauf_id: id, daten: { stufe: l.stufe, modell: l.modell, abo: l.abo, ort: l.ort } });
    return id;
  });
}

export function laufSchritt(db: Register, id: string, satz: string, felder: Felder = {}): void {
  schritt(db, () => {
    const l = hole(db, "lauf", id);
    const t = uhr.jetzt();
    if (l.zustand === "startet") uebergang(db, "lauf", id, "laeuft", "erster Schritt");
    if (l.zustand === "haengt") uebergang(db, "lauf", id, "laeuft", "neuer Schritt");
    setzen(db, "lauf", id, { ...felder, letzter_schritt_um: t, letzter_schritt: satz });
    if (t - Number(l.letzter_schritt_um) >= regelMs("lauf_schritt_abstand_s")) ereignis(db, { art: "lauf.schritt", lauf_id: id, auftrag_id: String(l.auftrag_id), satz });
  });
}

export function laufEnde(db: Register, id: string, nach: "beendet" | "abgebrochen", e: { grund?: string; tokens_ein?: number; tokens_aus?: number; kosten_cent?: number; abo?: string }): void {
  schritt(db, () => {
    const l = hole(db, "lauf", id);
    uebergang(db, "lauf", id, nach, e.grund ?? "ende", {
      beendet_um: uhr.jetzt(), grund: e.grund ?? null, tokens_ein: e.tokens_ein ?? 0, tokens_aus: e.tokens_aus ?? 0, kosten_cent: e.kosten_cent ?? 0, abo: e.abo ?? l.abo,
    });
    ereignis(db, { art: "lauf.ende", lauf_id: id, auftrag_id: String(l.auftrag_id), satz: e.grund, daten: { tokens: (e.tokens_ein ?? 0) + (e.tokens_aus ?? 0), kosten_cent: e.kosten_cent ?? 0 } });
  });
}

export function fortschreibung(db: Register, laufId: string, f: { letzter_stand: string; naechster_schritt: string; schritt_nr?: number; schritt_gesamt?: number; beleg?: string }): Zeile {
  return schritt(db, () => {
    const l = hole(db, "lauf", laufId);
    const auftragId = String(l.auftrag_id);
    setzen(db, "lauf", laufId, { fortgeschrieben: 1 });
    setzen(db, "auftrag", auftragId, { letzter_stand: f.letzter_stand, naechster_schritt: f.naechster_schritt, schritt_nr: f.schritt_nr ?? null,
      schritt_gesamt: f.schritt_gesamt ?? null, geaendert: uhr.jetzt() });
    ereignis(db, { art: "fortschreibung", lauf_id: laufId, auftrag_id: auftragId, beleg: f.beleg, satz: f.letzter_stand, daten: f });
    return hole(db, "auftrag", auftragId);
  });
}

export type TodoAktion = { aktion: "anlegen" | "aendern" | "erledigt" | "verschieben" | "loeschen" | "wiederherstellen"; id?: string; felder?: Felder; gesehen_revision?: number; geraet: string; satz?: string };

const ZIEL_JE_AKTION = { erledigt: "erledigt", loeschen: "geloescht", wiederherstellen: "offen" } as const;

export function todoSetzen(db: Register, a: TodoAktion): { id: string; ergebnis: "angenommen" | "ueberholt"; hinweis?: string } {
  return schritt(db, () => {
    if (a.aktion === "anlegen") {
      regel("todo", NEU, "offen");
      const id = neueId();
      einfuegen(db, "todo", { herkunft: a.geraet, ...a.felder, id, zustand: "offen", revision: revision(db) + 1 });
      ereignis(db, { art: "todo.geaendert", geraet: a.geraet, schluessel: id, daten: { aktion: a.aktion } });
      return { id, ergebnis: "angenommen" };
    }
    const id = String(a.id);
    const alt = hole(db, "todo", id);
    if (a.aktion in ZIEL_JE_AKTION) {
      const nach = ZIEL_JE_AKTION[a.aktion as keyof typeof ZIEL_JE_AKTION];
      if (alt.zustand !== nach) uebergang(db, "todo", id, nach, a.aktion, nach === "erledigt" ? { erledigt_von: a.geraet, revision: revision(db) + 1 } : { revision: revision(db) + 1 });
      else if (nach === "erledigt" && alt.wiederkehrend) setzen(db, "todo", id, { erledigt_von: a.geraet, revision: revision(db) + 1 });
      if (nach === "erledigt") ereignis(db, { art: "todo.erledigt", geraet: a.geraet, schluessel: id, satz: a.satz });
      return { id, ergebnis: "angenommen" };
    }
    if (alt.zustand === "erledigt") return { id, ergebnis: "ueberholt", hinweis: "Schon erledigt. Abhaken gewinnt." };
    const verdraengt = Number(alt.revision) > (a.gesehen_revision ?? Infinity);
    if (verdraengt) ereignis(db, { art: "bearbeitung.verdraengt", geraet: a.geraet, schluessel: id, daten: { fassung: alt, geraet: a.geraet } });
    const mehr: Felder = a.aktion === "verschieben" ? { verschoben_anzahl: Number(alt.verschoben_anzahl) + 1 } : {};
    setzen(db, "todo", id, { ...a.felder, ...mehr, revision: revision(db) + 1 });
    ereignis(db, { art: "todo.geaendert", geraet: a.geraet, schluessel: id, daten: { aktion: a.aktion } });
    return { id, ergebnis: "angenommen", hinweis: verdraengt ? "Woanders geändert, die andere Fassung steht im Verlauf." : undefined };
  });
}

export function eintragSetzen(db: Register, e: { art: string; werte: object; zeit: number; quelle: string; handlung_kennung?: string; verweis?: string }): string {
  return schritt(db, () => {
    const id = neueId();
    const r = db.prepare("INSERT OR IGNORE INTO eintrag (id, art, werte, zeit, quelle, handlung_kennung, verweis, zustand) VALUES (?, ?, ?, ?, ?, ?, ?, 'gueltig')")
      .run(id, e.art, JSON.stringify(e.werte), e.zeit, e.quelle, e.handlung_kennung ?? null, e.verweis ?? null);
    if (!r.changes) return "doppelt";
    ereignis(db, { art: "eintrag.geaendert", schluessel: id, geraet: e.quelle, daten: { art: e.art } });
    return id;
  });
}

export function eintragAendern(db: Register, id: string, a: { werte?: object; zustand?: string }, geraet: string): void {
  schritt(db, () => {
    const alt = hole(db, "eintrag", id);
    setzen(db, "eintrag", id, a.werte ? { werte: JSON.stringify({ ...JSON.parse(String(alt.werte)), ...a.werte }) } : { zustand: a.zustand ?? "gueltig" });
    ereignis(db, { art: "eintrag.geaendert", schluessel: id, geraet, daten: { art: alt.art } });
  });
}

export function anzeigeSetzen(db: Register, a: { id?: string; projekt: string; art: string; titel: string; werte: object; besitzer: string; beantwortet?: string; zustand?: string }): string {
  return schritt(db, () => {
    const id = a.id ?? neueId();
    const aktiv = Number(db.prepare("SELECT COUNT(*) AS n FROM anzeige WHERE projekt = ? AND zustand = 'aktiv' AND id != ?").get(a.projekt, id)?.n);
    const zustand = a.zustand ?? "aktiv";
    if (zustand === "aktiv" && aktiv >= regelZahl("anzeigen_max_je_projekt")) throw new Error(`Höchstens ${regelZahl("anzeigen_max_je_projekt")} Anzeigen je Projekt.`);
    db.prepare(`INSERT INTO anzeige (id, projekt, art, titel, werte, beantwortet, besitzer, stand, zustand) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET titel = excluded.titel, werte = excluded.werte, stand = excluded.stand, zustand = excluded.zustand`)
      .run(id, a.projekt, a.art, a.titel, JSON.stringify(a.werte), a.beantwortet ?? null, a.besitzer, uhr.jetzt(), zustand);
    ereignis(db, { art: "anzeige.geaendert", schluessel: id, wer: a.besitzer, daten: { anzeige_id: id, was: zustand } });
    return id;
  });
}

export function anzeigeEntfernen(db: Register, id: string, wer: string): void {
  const a = hole(db, "anzeige", id);
  anzeigeSetzen(db, { id, projekt: String(a.projekt), art: String(a.art), titel: String(a.titel), werte: JSON.parse(String(a.werte)), besitzer: wer, zustand: "entfernt" });
}

export function korrekturZuruecknehmen(db: Register, nr: number): string {
  return schritt(db, () => {
    const e = db.prepare("SELECT * FROM ereignis WHERE nr = ? AND art = 'korrektur'").get(nr);
    if (!e) throw new Error(`Korrektur ${nr} fehlt`);
    if (zurueckgenommen(db, nr)) return "abgelehnt:schon_zurueckgenommen";
    const k = JSON.parse(String(e.daten));
    const sperre = k.ort === "sperre" ? hole(db, "auftrag", String(k.nachher)) : undefined;
    if (k.ort === "profil" || k.ort === "fakt") wertSetzen(db, String(k.schluessel), k.vorher ?? "", "lernen");
    if (sperre && !["erledigt", "verworfen"].includes(String(sperre.zustand))) uebergang(db, "auftrag", String(sperre.id), "verworfen", "korrektur zurückgenommen");
    const umkehr = k.ort === "skill" ? `Skill „${k.ziel}“ zurückdrehen: „${k.nachher}“ wieder durch „${k.vorher}“ ersetzen.`
      : sperre?.zustand === "erledigt" ? `Sperre „${k.kern}“ aus dem Ausgang wieder entfernen, mit Prüffall.` : undefined;
    if (umkehr) {
      auftragAnlegen(db, {
        art: "system", wortlaut: umkehr, wortlaut_quelle: `korrektur:${nr}`, titel: umkehr.slice(0, regelZahl("titel_zeichen")),
        ziel: "Der alte Stand gilt wieder", abnahme: k.ort === "skill" ? "skill_workshop meldet die Änderung" : "Prüffall zeigt den alten Stand", abnahme_durch: "beleg", pruefer_noetig: k.ort !== "skill",
        verantwortlich: k.ort === "skill" ? String(e.wer ?? "seneca") : String(sperre?.verantwortlich), auftraggeber: "antonio", quelle: "du", bereich: "Privat", arbeitsart: k.ort === "skill" ? "skill" : "bauen",
      });
    }
    ereignis(db, { art: "korrektur.zurueckgenommen", schluessel: String(e.schluessel), daten: { korrektur_nr: nr } });
    return "angenommen";
  });
}
