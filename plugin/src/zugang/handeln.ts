import { auftraege, hole, laeufe, laufZurSitzung, revision, spaeterBis, termineAm, uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import {
  anzeigeEntfernen, anzeigeGesehen, auftragAnlegen, auftragSetzen, ereignis, eintragAendern, eintragSetzen, korrekturZuruecknehmen, frageBeantworten, frageVertagen, frageZuruecknehmen, handlung, todoSetzen, uebergang, wertSetzen,
} from "../register/schreiben.ts";
import { regelMs, regelText, regelZahl } from "../regeln.ts";

type Handlung = { kennung: string; geraet: string; art: string; ziel?: string; wert?: unknown; zeit_geraet?: number; gesehen_revision?: number };
type Wert = Record<string, unknown>;

const ja = (f: (db: Register, h: Handlung) => unknown) => (db: Register, h: Handlung) => (f(db, h), "angenommen");
const auftrag = (nach: string, felder: (h: Handlung) => Record<string, number> = () => ({})) => ja((db, h) => {
  uebergang(db, "auftrag", String(h.ziel), nach, h.art, felder(h));
  if (typeof h.wert === "string" && h.wert) ereignis(db, { art: "entscheidung", auftrag_id: String(h.ziel), geraet: h.geraet, schluessel: h.kennung, satz: h.wert, daten: { text: h.wert, art: h.art } });
});
const todo = (aktion: "anlegen" | "aendern" | "erledigt" | "verschieben" | "loeschen" | "wiederherstellen") => (db: Register, h: Handlung) =>
  todoSetzen(db, { aktion, id: h.ziel, felder: (h.wert ?? {}) as Record<string, string | number | null>, gesehen_revision: h.gesehen_revision, geraet: h.geraet }).ergebnis === "ueberholt" ? "ueberholt" : "angenommen";

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


const eintrag = (a: (h: Handlung) => { werte?: object; zustand?: string }) => ja((db, h) => eintragAendern(db, String(h.ziel), a(h), h.geraet));

const setze = (schluessel: (h: Handlung) => string, dauer?: () => number) => ja((db, h) => {
  const w = h.wert as Wert | string;
  wertSetzen(db, schluessel(h), typeof w === "string" ? w : String(w?.wert ?? "ja"), h.geraet, dauer ? uhr.jetzt() + dauer() : (typeof w === "object" ? (w?.bis as number | undefined) : undefined));
});

function wegSetzen(db: Register, uid: string, w: Wert, geraet: string): void {
  wertSetzen(db, `wegzeit:${uid}`, String(Math.round(Number(w.weg_min))), geraet);
  wertSetzen(db, `entfernung:${uid}`, String(Math.round(Number(w.entfernung_m))), geraet);
  if (w.art) wertSetzen(db, `wegart:${uid}`, String(w.art), geraet);
}

const uhrzeit = (t: number) => new Date(t).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });

function terminVerschieben(db: Register, kennung: string, uid: string, w: Wert): string {
  const [start, ende] = [Number(w.start), Number(w.ende)];
  const t = termineAm(db, start).find((x) => x.uid === uid) ?? termineAm(db, uhr.jetzt()).find((x) => x.uid === uid);
  if (!t) return "abgelehnt:termin_unbekannt";
  if (!t.teilnehmer.length) {
    wertSetzen(db, `kalender:schreiben:${kennung}`, JSON.stringify({ aktion: "verschieben", uid, titel: w.titel ?? t.titel, ort: w.ort, start, ende }), "antonio");
    return "angenommen";
  }
  const wortlaut = `Termin „${t.titel}“ auf ${uhrzeit(start)} verschieben. Erst die anderen fragen, dann verschieben.`;
  auftragAnlegen(db, { art: "system", wortlaut, wortlaut_quelle: `handlung:${kennung}`, titel: `${t.titel} auf ${uhrzeit(start)}`.slice(0, regelZahl("titel_zeichen")),
    ziel: `${t.titel} liegt um ${uhrzeit(start)}`, abnahme: "Zusage der anderen und Termin verschoben", abnahme_durch: "beleg", pruefer_noetig: false,
    verantwortlich: regelText("dauerauftraege_von"), auftraggeber: "antonio", quelle: "du", bereich: "Privat", arbeitsart: "steuern" });
  return "angenommen";
}

const ARTEN: Record<string, (db: Register, h: Handlung) => string> = {
  "frage.antwort": antwort,
  "frage.gesehen": ja((db, h) => ereignis(db, { art: "zustellung", frage_id: h.ziel, geraet: h.geraet, daten: { was: "gesehen" } })),
  rueckgaengig,
  "abnahme.passt": auftrag("erledigt"),
  "abnahme.nachbessern": auftrag("bereit", () => ({ naechster_anlass: uhr.jetzt() })),
  "abnahme.ueberspringen": ja((db, h) => auftragSetzen(db, String(h.ziel), { naechster_anlass: uhr.jetzt() }, "Im Bündel übersprungen.")),
  "auftrag.verwerfen": auftrag("verworfen"),
  "auftrag.anhalten": auftrag("geparkt"),
  "auftrag.fortsetzen": auftrag("bereit", () => ({ naechster_anlass: uhr.jetzt() })),
  "kostenrahmen.erhoehen": ja((db, h) => auftragSetzen(db, String(h.ziel), { kostenrahmen_cent: Number(h.wert) }, "Rahmen von Antonio gesetzt.")),
  "todo.anlegen": todo("anlegen"),
  "todo.aendern": todo("aendern"),
  "todo.erledigt": todo("erledigt"),
  "todo.verschieben": todo("verschieben"),
  "todo.loeschen": todo("loeschen"),
  "todo.wiederherstellen": todo("wiederherstellen"),
  "eintrag.neu": (db, h) => {
    const w = h.wert as Wert;
    const zurueck = (w.werte as Wert | undefined)?.tag === "gestern" ? regelMs("ein_tag_tage") : 0;
    return eintragSetzen(db, { art: String(w.art), werte: w.werte as object, zeit: (typeof w.zeit === "number" ? w.zeit : h.zeit_geraet ?? uhr.jetzt()) - zurueck, quelle: h.geraet, handlung_kennung: h.kennung }) === "doppelt" ? "doppelt" : "angenommen";
  },
  "eintrag.aendern": eintrag((h) => ({ werte: h.wert as object })),
  "eintrag.loeschen": eintrag(() => ({ zustand: "geloescht" })),
  "eintrag.wiederherstellen": eintrag(() => ({ zustand: "gueltig" })),
  "ziel.setzen": setze((h) => `ziel:${h.ziel}`),
  "todo.vorschlag_weg": setze(() => "todo_vorschlag", () => 0),
  "termin.anlegen": (db, h) => {
    const w = h.wert as Wert;
    if (!w?.titel || !Number.isFinite(Number(w.start)) || !(Number(w.ende) > Number(w.start))) return "abgelehnt:termin_unvollstaendig";
    const uid = `${h.kennung}-${h.geraet}`;
    wertSetzen(db, `kalender:schreiben:${h.kennung}`, JSON.stringify({ aktion: "anlegen", uid, titel: w.titel, start: Number(w.start), ende: Number(w.ende), ort: w.ort || undefined, kalender: w.kalender }), h.geraet);
    if (w.weg) wegSetzen(db, uid, w.weg as Wert, h.geraet);
    return "angenommen";
  },
  "termin.verschieben": (db, h) => terminVerschieben(db, h.kennung, String(h.ziel), (h.wert as Wert) ?? {}),
  "termin.weg": ja((db, h) => wegSetzen(db, String(h.ziel), h.wert as Wert, h.geraet)),
  "termin.zuruecklegen": (db, h) => (wertSetzen(db, `zurueckgelegt:${h.ziel}`, "ja", h.geraet), terminVerschieben(db, h.kennung, String(h.ziel), h.wert as Wert)),
  "vorschlag.anders": (db, h) => (wertSetzen(db, `vorschlag:zeit:${h.ziel}`, String(Number((h.wert as Wert)?.start)), h.geraet), antwort(db, { ...h, wert: { wahl: "ja" } })),
  "kalender.lassen": setze((h) => `kalender:lassen:${h.ziel}`),
  "geraet.aktivitaet": (db, h) => setze(() => "aktivitaet")(db, h) && setze(() => "uhr:starten", () => regelMs("uhr_starten_min"))(db, h),
  koerper: (db, h) => {
    const w = h.wert as Wert;
    if (!Number.isFinite(Number(w?.schlaf_min)) || !Number.isFinite(Number(w?.bis))) return "abgelehnt:schlaf_fehlt";
    wertSetzen(db, "koerper:schlaf", JSON.stringify({ minuten: Number(w.schlaf_min), bis: Number(w.bis) }), h.geraet);
    return "angenommen";
  },
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
  "auftrag.anlegen": (db, h) => {
    const w = (h.wert ?? {}) as Wert, text = String(w.text ?? ""), quelle = String(w.quelle || h.kennung);
    if (auftraege(db, ["bereit", "laeuft", "wartet", "erledigt"]).some((a) => a.wortlaut_quelle === quelle)) return "angenommen";
    auftragAnlegen(db, { art: "auftrag", wortlaut: text, wortlaut_quelle: quelle, titel: text.slice(0, 60), ziel: "Ergebnis mit Beleg", abnahme: "Beleg liegt vor",
      abnahme_durch: "antonio", pruefer_noetig: false, verantwortlich: String(w.wer), auftraggeber: "antonio", quelle: "meeting", bereich: String(w.bereich || "Seneca"),
      arbeitsart: String(w.arbeitsart || (w.wer === "pruefer" ? "pruefen" : "bauen")), nachricht: { kennung: h.kennung, text } });
    return "angenommen";
  },
  "eingang.sensor": (db, h) => eingang(db, h, "sensor"),
  "lernen.zuruecknehmen": (db, h) => korrekturZuruecknehmen(db, Number(h.ziel)),
  "gespraech.neu": (db, h) => /^agent:[a-z0-9_-]+:[^\s]+$/.test(String(h.ziel)) ? ja((d, x) => wertSetzen(d, `gespraech:neu:${x.kennung}`, String(x.ziel), x.geraet))(db, h) : "abgelehnt:sitzung_unbekannt",
  "anzeige.weg": ja((db, h) => anzeigeEntfernen(db, String(h.ziel), h.geraet)),
  "anzeige.angesehen": ja((db, h) => anzeigeGesehen(db, String(h.ziel))),
};

const eingang = (db: Register, h: Handlung, quelle: string) => ja((d, x) => ereignis(d, { art: "eingang", geraet: x.geraet, schluessel: x.kennung, daten: { quelle, verweis: x.wert } }))(db, h);

export function handeln(db: Register, h: Handlung): { ergebnis: string; revision: number } {
  const art = ARTEN[h.art];
  if (!art) return { ergebnis: "abgelehnt:unbekannte_art", revision: revision(db) };
  try {
    return { ergebnis: handlung(db, { kennung: h.kennung, geraet: h.geraet, art: h.art, ziel: h.ziel }, () => art(db, h)), revision: revision(db) };
  } catch (fehler) {
    return { ergebnis: `abgelehnt:${(fehler as Error).message}`, revision: revision(db) };
  }
}

const KNOEPFE: Record<string, [string, string]> = { verwerfen: ["auftrag.verwerfen", "verworfen"], anhalten: ["auftrag.anhalten", "geparkt"], fortsetzen: ["auftrag.fortsetzen", "bereit"], erledigt: ["abnahme.passt", "erledigt"] };
export function aufAntoniosWort(db: Register, n: { kennung: string; text: string; vonAntonio: boolean } | undefined, p: { art: string; urteil?: string; auftrag_id?: string; satz?: string; nachricht_kennung?: string }) {
  const art = p.art === "abnahme" && p.urteil === "passt" ? "erledigt" : p.art, ziel = String(p.auftrag_id), titel = () => hole(db, "auftrag", ziel).titel;
  if (!KNOEPFE[art] || !n?.vonAntonio || (p.nachricht_kennung && p.nachricht_kennung !== n.kennung)) return undefined;
  const r = handeln(db, { kennung: `${n.kennung}:${art}:${ziel}`, geraet: "gespraech", art: KNOEPFE[art][0], ziel, wert: p.satz ?? n.text.slice(0, regelZahl("titel_zeichen")) });
  if (r.ergebnis.startsWith("abgelehnt")) throw new Error(`${titel()}: ${r.ergebnis}`);
  return { auftrag_id: ziel, satz: `„${titel()}“ ist jetzt ${KNOEPFE[art][1]}.` };
}

export const nurAntonioTodo = (db: Register, n: { vonAntonio: boolean } | undefined, sitzung: string): void => { if (!["startet", "laeuft", "haengt"].includes(String(laufZurSitzung(db, sitzung)?.zustand)) && (n ? !n.vonAntonio : sitzung.includes(":whatsapp:"))) throw new Error("To-dos legt und hakt nur Antonios eigene Nachricht im Gespräch ab, nicht WhatsApp oder Dritte."); };
