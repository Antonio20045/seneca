import { hole, laeufe, revision, spaeterBis, uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import {
  anzeigeSetzen, auftragSetzen, ereignis, eintragSetzen, korrekturZuruecknehmen, frageBeantworten, frageVertagen, frageZuruecknehmen, handlung, todoSetzen, uebergang, wertSetzen,
} from "../register/schreiben.ts";
import { regelMs } from "../regeln.ts";

type Handlung = { kennung: string; geraet: string; art: string; ziel?: string; wert?: unknown; zeit_geraet?: number; gesehen_revision?: number };
type Wert = Record<string, unknown>;

function antwort(db: Register, h: Handlung): string {
  const w = (h.wert ?? {}) as Wert;
  const jetzt = uhr.jetzt();
  if (w.wahl === "spaeter") {
    frageVertagen(db, String(h.ziel), spaeterBis(db, String(h.ziel), jetzt), h.geraet);
    return "angenommen";
  }
  const alt = jetzt - (h.zeit_geraet ?? jetzt) > regelMs("antwort_max_alter_min");
  if (alt && hole(db, "frage", String(h.ziel)).wirkung_aussen !== "keine") return "abgelehnt:zu_alt_neu_fragen";
  const r = frageBeantworten(db, { frage_id: String(h.ziel), antwort: String(w.wahl), geraet: h.geraet, kennung: h.kennung, lokal: !!w.lokal, inhalt_hash: w.inhalt_hash as string | undefined });
  if (r.ergebnis === "schon_beantwortet") return `schon_beantwortet:${r.wahl},${r.geraet},${r.um}`;
  return r.ergebnis === "abgelehnt" ? `abgelehnt:${r.grund}` : "angenommen";
}

function rueckgaengig(db: Register, h: Handlung): string {
  const ziel = String(h.ziel);
  if (db.prepare("SELECT 1 FROM frage WHERE id = ?").get(ziel)) return frageZuruecknehmen(db, ziel) === "angenommen" ? "angenommen" : "abgelehnt:zu_spaet";
  const a = hole(db, "auftrag", ziel);
  if (a.zustand !== "bereit" || laeufe(db, ziel).length || uhr.jetzt() - Number(a.erstellt) > regelMs("rueckgaengig_s")) return "abgelehnt:zu_spaet";
  uebergang(db, "auftrag", ziel, "verworfen", "rueckgaengig");
  return "angenommen";
}

function auftrag(nach: string, felder: (h: Handlung) => Record<string, number> = () => ({})) {
  return (db: Register, h: Handlung) => {
    uebergang(db, "auftrag", String(h.ziel), nach, h.art, felder(h));
    if (typeof h.wert === "string" && h.wert) ereignis(db, { art: "entscheidung", auftrag_id: String(h.ziel), geraet: h.geraet, satz: h.wert, daten: { text: h.wert } });
    return "angenommen";
  };
}

function todo(aktion: "anlegen" | "aendern" | "erledigt" | "verschieben" | "loeschen" | "wiederherstellen") {
  return (db: Register, h: Handlung) => {
    const r = todoSetzen(db, { aktion, id: h.ziel, felder: (h.wert ?? {}) as Record<string, string | number | null>, gesehen_revision: h.gesehen_revision, geraet: h.geraet });
    return r.ergebnis === "ueberholt" ? "ueberholt" : "angenommen";
  };
}

function setze(schluessel: (h: Handlung) => string, dauer?: () => number) {
  return (db: Register, h: Handlung) => {
    const w = h.wert as Wert | string;
    const wert = typeof w === "string" ? w : String(w?.wert ?? "ja");
    wertSetzen(db, schluessel(h), wert, h.geraet, dauer ? uhr.jetzt() + dauer() : (typeof w === "object" ? (w?.bis as number | undefined) : undefined));
    return "angenommen";
  };
}

const ARTEN: Record<string, (db: Register, h: Handlung) => string> = {
  "frage.antwort": antwort,
  "frage.gesehen": (db, h) => {
    ereignis(db, { art: "zustellung", frage_id: h.ziel, geraet: h.geraet, daten: { was: "gesehen" } });
    return "angenommen";
  },
  rueckgaengig,
  "abnahme.passt": auftrag("erledigt"),
  "abnahme.nachbessern": auftrag("bereit", () => ({ naechster_anlass: uhr.jetzt() })),
  "abnahme.ueberspringen": (db, h) => {
    auftragSetzen(db, String(h.ziel), { naechster_anlass: uhr.jetzt() }, "Im Bündel übersprungen.");
    return "angenommen";
  },
  "auftrag.verwerfen": auftrag("verworfen"),
  "auftrag.anhalten": auftrag("geparkt"),
  "auftrag.fortsetzen": auftrag("bereit", () => ({ naechster_anlass: uhr.jetzt() })),
  "kostenrahmen.erhoehen": (db, h) => {
    auftragSetzen(db, String(h.ziel), { kostenrahmen_cent: Number(h.wert) }, "Rahmen von Antonio gesetzt.");
    return "angenommen";
  },
  "todo.anlegen": todo("anlegen"),
  "todo.aendern": todo("aendern"),
  "todo.erledigt": todo("erledigt"),
  "todo.verschieben": todo("verschieben"),
  "todo.loeschen": todo("loeschen"),
  "todo.wiederherstellen": todo("wiederherstellen"),
  "eintrag.neu": (db, h) => {
    const w = h.wert as Wert;
    return eintragSetzen(db, { art: String(w.art), werte: w.werte as object, zeit: h.zeit_geraet ?? uhr.jetzt(), quelle: h.geraet, handlung_kennung: h.kennung }) === "doppelt" ? "doppelt" : "angenommen";
  },
  "geraet.aktivitaet": setze(() => "aktivitaet"),
  praesenz: setze((h) => `praesenz:${h.geraet}`, () => regelMs("praesenz_gilt_min")),
  "push.token": setze((h) => `push:${h.geraet}`),
  "geraet.sperren": setze((h) => `uhr:${h.ziel}`),
  "geraet.uhr_koppeln": setze(() => "kopplung:fenster", () => regelMs("kopplung_fenster_min")),
  "geraet.uhr_bestaetigen": (db, h) => {
    const w = wert(db, `kopplung:${h.ziel}`);
    const k = w && (w.gueltig_bis ?? 0) > uhr.jetzt() ? JSON.parse(w.wert) : undefined;
    if (!k || k.zahl !== String(h.wert)) return "abgelehnt:zahl_passt_nicht";
    wertSetzen(db, `kopplung:${h.ziel}`, JSON.stringify({ ...k, bestaetigt: true }), h.geraet, w?.gueltig_bis);
    return "angenommen";
  },
  "eingang.datei": (db, h) => eingang(db, h, "teilen"),
  "eingang.meeting": (db, h) => eingang(db, h, "meeting"),
  "eingang.sensor": (db, h) => eingang(db, h, "sensor"),
  "lernen.zuruecknehmen": (db, h) => korrekturZuruecknehmen(db, Number(h.ziel)),
  "anzeige.weg": (db, h) => {
    const a = hole(db, "anzeige", String(h.ziel));
    anzeigeSetzen(db, { id: String(a.id), projekt: String(a.projekt), art: String(a.art), titel: String(a.titel), werte: JSON.parse(String(a.werte)), besitzer: h.geraet, zustand: "entfernt" });
    return "angenommen";
  },
};

function eingang(db: Register, h: Handlung, quelle: string): string {
  ereignis(db, { art: "eingang", geraet: h.geraet, schluessel: h.kennung, daten: { quelle, verweis: h.wert } });
  return "angenommen";
}

export function handeln(db: Register, h: Handlung): { ergebnis: string; revision: number } {
  const art = ARTEN[h.art];
  if (!art) return { ergebnis: "abgelehnt:unbekannte_art", revision: revision(db) };
  try {
    return { ergebnis: handlung(db, { kennung: h.kennung, geraet: h.geraet, art: h.art, ziel: h.ziel }, () => art(db, h)), revision: revision(db) };
  } catch (fehler) {
    return { ergebnis: `abgelehnt:${(fehler as Error).message}`, revision: revision(db) };
  }
}
