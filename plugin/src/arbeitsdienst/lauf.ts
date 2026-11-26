import { aktiveLaeufe, ereignisse, hole, kinder, kostenSeit, laufZurSitzung, uhr, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import {
  auftragAnlegen, auftragSetzen, befund, fortschreibung, frageBeantworten, frageStellen, laufAnlegen, laufEnde, laufSchritt, uebergang, wertSetzen,
} from "../register/schreiben.ts";
import { naechsteUhrzeit, regelMs, regelText, regelUhrzeitNach, regelZahl } from "../regeln.ts";
import { mandat, rolle } from "../team.ts";
import { aboReihenfolge } from "./abo.ts";
import { euro, kostenCent, rahmen, wochenbeginn, wocheSchonGefragt } from "./kosten.ts";
import { waehle } from "./modell.ts";

export type Starter = (p: { sessionKey: string; message: string; model: string; idempotencyKey: string }) => Promise<{ runId: string }>;
type SkillLeser = (mitarbeiter: string, arbeitsart: string) => string | undefined;
type Nachricht = { kennung: string; text: string; vonAntonio: boolean };

const AKTIV = ["startet", "laeuft", "haengt"];
const nachrichten = new Map<string, Nachricht>();
const ABO_HINWEIS = "Alle Abos sind aufgebraucht. Die Arbeit ruht, bis eines wieder frei ist.";

export function merkeNachricht(sitzung: string, n: Nachricht): void {
  nachrichten.set(sitzung, n);
}

export function nachrichtVon(sitzung: string): Nachricht | undefined {
  return nachrichten.get(sitzung);
}

export function naechsterTermin(a: Zeile, jetzt: number): number {
  const zeiten: Record<string, () => string[]> = {
    rundgang: () => mandat(String(a.verantwortlich)).rundgang,
    morgenbericht: () => [regelText("morgenbericht_um")],
    rueckblick: () => [regelText("rueckblick_um")],
    briefing: () => [regelText("briefing_um")],
  };
  return Math.min(...zeiten[String(a.arbeitsart)]().map((z) => naechsteUhrzeit(z, jetzt)));
}

export function zurueckMitWartezeit(db: Register, a: Zeile, anlass: string): void {
  const n = Number(a.fehlversuche) + 1;
  const warten = Math.min(regelMs("lauf_wiederholen_start_min") * 2 ** (n - 1), regelMs("lauf_wiederholen_max_h"));
  const felder = { naechster_anlass: uhr.jetzt() + warten, fehlversuche: n };
  if (a.zustand === "bereit") auftragSetzen(db, String(a.id), felder, `Neuer Versuch nach ${anlass}.`);
  else uebergang(db, "auftrag", String(a.id), "bereit", anlass, felder);
}

function rahmenFrage(db: Register, a: Zeile, art: "auftrag" | "woche", jetzt: number): string {
  const wer = String(a.verantwortlich);
  const id = String(a.id);
  if (art === "woche" && wocheSchonGefragt(db, wer, jetzt)) {
    auftragSetzen(db, id, { naechster_anlass: wochenbeginn(jetzt, 1) }, "Wochenbudget erreicht.");
    return "rahmen";
  }
  const verbraucht = kostenSeit(db, art === "woche" ? wochenbeginn(jetzt) : 0, art === "woche" ? { mitarbeiter: wer } : { auftrag_id: id });
  const neu = Number(a.kostenrahmen_cent) * 2;
  const frage = frageStellen(db, {
    auftrag_id: id, von: "arbeitsdienst:kostenrahmen", art: "auswahl",
    text: art === "woche" ? `Das Wochenbudget von ${wer} ist erreicht. Weitermachen?` : `Rahmen von ${euro(Number(a.kostenrahmen_cent))} erreicht. Weitermachen bis ${euro(neu)}?`,
    was_passiert_ist: `„${a.titel}“ hat bisher ${euro(verbraucht)} gekostet.`, wenn_nichts: "Der Auftrag ruht, bis du antwortest.",
    empfehlung: "Weitermachen, wenn das Ergebnis dir das wert ist.",
    optionen: [{ wert: "weiter", text: `Weiter bis ${euro(neu)}`, folge: "Die Arbeit geht weiter." }, { wert: "anhalten", text: "Anhalten", folge: "Der Auftrag wird geparkt." }],
  });
  uebergang(db, "auftrag", id, "wartet", "kostenrahmen", { wartet_auf: `frage:${frage}`, folge: "Der Auftrag ruht.", naechster_anlass: jetzt + regelMs("rahmen_nachfassen_h") });
  if (art === "woche") wertSetzen(db, `rahmen_woche:${wer}`, String(wochenbeginn(jetzt)), "arbeitsdienst");
  return "rahmen";
}

export async function starteLauf(db: Register, a: Zeile, starte: Starter): Promise<string> {
  const jetzt = uhr.jetzt();
  const wer = String(a.verantwortlich);
  const ruht = wert(db, `ruht:${wer}`);
  if (ruht?.wert === "ja" && (ruht.gueltig_bis ?? Infinity) > jetzt) {
    auftragSetzen(db, String(a.id), { naechster_anlass: Math.min(ruht.gueltig_bis ?? Infinity, jetzt + regelMs("ruht_pruefen_h")) }, `${wer} ruht.`);
    return "ruht";
  }
  const m = mandat(wer);
  const r = rahmen(db, a, m, jetzt);
  if (r !== "frei") return rahmenFrage(db, a, r, jetzt);
  if (aktiveLaeufe(db).length >= regelZahl("parallel_max")) return "voll";
  const abos = aboReihenfolge(db, jetzt);
  const hinweis = wert(db, "hinweis:abos")?.wert ?? "";
  if (!abos.length) {
    if (hinweis !== ABO_HINWEIS) wertSetzen(db, "hinweis:abos", ABO_HINWEIS, "arbeitsdienst");
    return "abos";
  }
  if (hinweis) wertSetzen(db, "hinweis:abos", "", "arbeitsdienst");
  const { stufe, modell, ort } = waehle(a, m);
  if (ort !== "server") return "ort";
  const laufId = laufAnlegen(db, { auftrag_id: String(a.id), mitarbeiter: wer, anlass: String(a.anlass ?? "neu"), art: "werkzeug", ort, stufe, modell, abo: abos[0] });
  const lauf = hole(db, "lauf", laufId);
  try {
    const { runId } = await starte({ sessionKey: String(lauf.sitzung), message: `Arbeite am Auftrag „${a.titel}“. Der Auftrag steht oben im Kontext.`, model: modell, idempotencyKey: laufId });
    laufSchritt(db, laufId, "angenommen", { run_id: runId });
  } catch (fehler) {
    laufEnde(db, laufId, "abgebrochen", { grund: `Start abgelehnt: ${String(fehler)}` });
    zurueckMitWartezeit(db, hole(db, "auftrag", String(a.id)), "start_abgelehnt");
  }
  return "gestartet";
}

function zeit(t: number): string {
  return new Date(t).toTimeString().slice(0, 5);
}

function anlassSatz(db: Register, a: Zeile): string {
  const wirkt = ereignisse(db, { art: "frage.wirkt", auftrag_id: String(a.id), grenze: 1 })[0];
  if (!wirkt || !["antwort", "freigabe"].includes(String(a.anlass))) return `Anlass: ${a.anlass}.`;
  const f = hole(db, "frage", String(wirkt.frage_id));
  return `Anlass: Antwort auf deine Frage ${zeit(Number(f.gestellt))} „${f.text}“: ${f.antwort}, ${zeit(Number(f.antwort_um))} am Gerät ${f.antwort_geraet}.`;
}

export function kontext(db: Register, sitzung: string, skill: SkillLeser): string | undefined {
  const l = laufZurSitzung(db, sitzung);
  if (!l || !AKTIV.includes(String(l.zustand))) return undefined;
  const wer = String(l.mitarbeiter);
  const a = hole(db, "auftrag", String(l.auftrag_id));
  const m = mandat(wer);
  const eltern = a.eltern_id ? hole(db, "auftrag", String(a.eltern_id)) : undefined;
  const verbraucht = kostenSeit(db, 0, { auftrag_id: String(a.id) });
  const teile: [string, boolean][] = [
    [`Seneca-Lauf ${l.id}. Am Ende rufst du seneca_fortschreiben auf: letzter Stand, Beleg, nächster Schritt, Ergebnis weiter, wartet oder fertig.`, true],
    [`${rolle(wer)}\nBefugnisse: Unteraufträge an ${m.befugnisse.unterauftrag_an.join(", ")}; Werkzeuge ${m.befugnisse.werkzeuge.join(", ")}; Zugänge ${m.zugaenge.join(", ")}.`, false],
    [skill(wer, String(a.arbeitsart)) ?? "", true],
    [(m.kontext[String(a.arbeitsart)] ?? []).map((s) => `${s}: ${wert(db, s)?.wert ?? "nicht hinterlegt"}`).join("\n"), false],
    [`Auftrag von ${a.auftraggeber}, Quelle ${a.wortlaut_quelle}, ${new Date(Number(a.erstellt)).toLocaleString("de-DE")}. Wortlaut:\n${a.wortlaut}`, true],
    [`Ziel: ${a.ziel}\nAbnahme: ${a.abnahme} (durch ${a.abnahme_durch})${a.pruefer_noetig ? "\nPrüfer nötig." : ""}`, false],
    [`Letzter Stand: ${a.letzter_stand || "noch nichts"}\nNächster Schritt: ${a.naechster_schritt || "offen"}${a.schritt_nr ? `\nPunkt ${a.schritt_nr} von ${a.schritt_gesamt}` : ""}`, false],
    [anlassSatz(db, a), false],
    [eltern ? `Elternauftrag: ${String(eltern.wortlaut).slice(0, regelZahl("kontext_eltern_zeichen"))}\nZiel: ${eltern.ziel}` : "", false],
    [ereignisse(db, { art: "befund", auftrag_id: String(a.id), grenze: regelZahl("kontext_befunde") }).map((b) => `Befund: ${b.satz}`).join("\n"), false],
    [`Kosten: ${euro(verbraucht)} von ${euro(Number(a.kostenrahmen_cent))}. Stufe ${l.stufe}.`, false],
  ];
  const liste = teile.filter(([t]) => t);
  const kuerzbar = () => liste.filter(([, fest]) => !fest).reduce((n, [t]) => n + t.length, 0);
  for (let i = liste.length - 1; i >= 0 && kuerzbar() > regelZahl("kontext_zeichen"); i--) if (!liste[i][1]) liste.splice(i, 1);
  return liste.map(([t]) => t).join("\n\n");
}

export type AuftragEingabe = {
  art: "auftrag" | "unterauftrag" | "vorschlag" | "idee" | "abnahme" | "verwerfen";
  nachricht_kennung?: string; wortlaut?: string; titel?: string; ziel?: string; abnahme?: string; abnahme_durch?: string; pruefer_noetig?: boolean;
  an?: string; bereich?: string; projekt?: string; frist?: number; arbeitsart?: string; schaetzung_min?: number; eltern_id?: string;
  auftrag_id?: string; urteil?: "passt" | "nachbessern"; satz?: string;
};

function laufender(db: Register, sitzung: string): Zeile {
  const l = laufZurSitzung(db, sitzung);
  if (!l || !AKTIV.includes(String(l.zustand))) throw new Error("Das geht nur in einem laufenden Seneca-Lauf.");
  return l;
}

export function werkzeugAuftrag(db: Register, ctx: { sitzung: string; agent: string }, p: AuftragEingabe): { auftrag_id: string; satz: string } {
  if (p.art === "abnahme" || p.art === "verwerfen") {
    const a = hole(db, "auftrag", String(p.auftrag_id));
    if (laufender(db, ctx.sitzung).mitarbeiter !== a.auftraggeber) throw new Error("Nur der Auftraggeber nimmt ab oder verwirft.");
    const nach = p.art === "verwerfen" ? "verworfen" : p.urteil === "passt" ? "erledigt" : "bereit";
    uebergang(db, "auftrag", String(a.id), nach, p.art === "verwerfen" ? "verwerfen" : `abnahme.${p.urteil}`, nach === "bereit" ? { naechster_anlass: uhr.jetzt() } : {});
    if (p.satz) befund(db, { art: "teilergebnis", auftrag_id: String(a.id), satz: p.satz });
    return { auftrag_id: String(a.id), satz: `Auftrag ist jetzt ${nach}.` };
  }
  const n = nachrichten.get(ctx.sitzung);
  const lauf = p.art === "auftrag" ? undefined : laufZurSitzung(db, ctx.sitzung);
  if (p.art === "auftrag" && (!n?.vonAntonio || n.kennung !== p.nachricht_kennung)) throw new Error("Ein Auftrag entsteht nur aus Antonios Nachricht in diesem Gespräch.");
  if (p.art === "unterauftrag") {
    const eltern = hole(db, "auftrag", String(p.eltern_id));
    if (laufender(db, ctx.sitzung).auftrag_id !== eltern.id) throw new Error("Unteraufträge vergibt nur der Lauf des Elternauftrags.");
    if (!mandat(ctx.agent).befugnisse.unterauftrag_an.includes(String(p.an))) throw new Error(`Unterauftrag an ${p.an} ist im Mandat nicht erlaubt.`);
  }
  const verantwortlich = p.an ?? ctx.agent;
  const { id, kostenrahmen_cent } = auftragAnlegen(db, {
    art: p.art, wortlaut: String(p.wortlaut), wortlaut_quelle: p.nachricht_kennung ?? `lauf:${lauf?.id ?? ctx.sitzung}`, titel: p.titel ?? String(p.wortlaut).slice(0, regelZahl("titel_zeichen")),
    ziel: String(p.ziel), abnahme: String(p.abnahme), abnahme_durch: p.abnahme_durch ?? "antonio", pruefer_noetig: !!p.pruefer_noetig, verantwortlich,
    auftraggeber: p.art === "auftrag" ? "antonio" : ctx.agent, quelle: { auftrag: "du", unterauftrag: "kollege", vorschlag: "vorschlag", idee: "eigene_idee" }[p.art],
    bereich: p.bereich ?? mandat(verantwortlich).bereich[0], projekt: p.projekt, frist: p.frist, arbeitsart: p.arbeitsart ?? "standard",
    schaetzung_min: p.schaetzung_min, eltern_id: p.eltern_id, nachricht: n && p.art === "auftrag" ? { kennung: n.kennung, text: n.text } : undefined,
  });
  if (p.art === "vorschlag") {
    frageStellen(db, {
      auftrag_id: id, von: ctx.agent, art: "vorschlag", text: `${p.titel ?? p.wortlaut}?`, was_passiert_ist: String(p.wortlaut), wenn_nichts: "Der Vorschlag verfällt.",
      empfehlung: String(p.ziel), optionen: [{ wert: "ja", text: "Ja", folge: "Daraus wird ein Auftrag." }, { wert: "nein", text: "Nein", folge: "Der Vorschlag wird verworfen." }],
    });
  }
  const satz = p.schaetzung_min ? `Notiert. ${verantwortlich} kümmert sich, etwa ${euro(kostenrahmen_cent)}.` : `Notiert. ${verantwortlich} kümmert sich, Rahmen ${euro(kostenrahmen_cent)}.`;
  return { auftrag_id: id, satz };
}

export function werkzeugAntwort(db: Register, sitzung: string, frageId: string, antwort: string, kennung: string) {
  const n = nachrichten.get(sitzung);
  if (!n?.vonAntonio || n.kennung !== kennung) throw new Error("Eine Antwort trägt nur Antonios Nachricht ein.");
  return frageBeantworten(db, { frage_id: frageId, antwort, geraet: "gespraech", kennung, nachricht_kennung: kennung });
}

export type Fortschreibung = {
  letzter_stand: string; naechster_schritt: string; ergebnis: "weiter" | "wartet" | "fertig"; beleg?: string; wartet_auf?: string; folge?: string;
  nachfass_um?: number; schritt_nr?: number; schritt_gesamt?: number; befunde?: string[]; stufe?: "hoch";
};

export function werkzeugFortschreiben(db: Register, sitzung: string, p: Fortschreibung): { zustand: string } {
  const l = laufender(db, sitzung);
  if (p.ergebnis === "wartet" && !(p.wartet_auf && p.folge && p.nachfass_um)) throw new Error("wartet braucht wartet_auf, Folge und Nachfasszeit.");
  if (p.ergebnis === "fertig" && !p.beleg) throw new Error("fertig braucht einen Beleg.");
  for (const satz of p.befunde ?? []) befund(db, { art: "teilergebnis", satz, auftrag_id: String(l.auftrag_id), lauf_id: String(l.id) });
  if (p.stufe === "hoch") auftragSetzen(db, String(l.auftrag_id), { stufe_fest: "opus" }, "Lauf bittet um höhere Stufe.");
  fortschreibung(db, String(l.id), p);
  return { zustand: "notiert" };
}

export function agentEnde(db: Register, sitzung: string, letzteAntwort: string, tokens: { ein: number; aus: number }): void {
  const l = laufZurSitzung(db, sitzung);
  if (!l || !AKTIV.includes(String(l.zustand))) return;
  const a = hole(db, "auftrag", String(l.auftrag_id));
  const jetzt = uhr.jetzt();
  const verbrauch = { tokens_ein: tokens.ein, tokens_aus: tokens.aus, kosten_cent: kostenCent(tokens.ein, tokens.aus) };
  if (!l.fortgeschrieben) {
    laufEnde(db, String(l.id), "abgebrochen", { grund: "ohne Stand", ...verbrauch });
    befund(db, { art: "ohne_stand", auftrag_id: String(a.id), lauf_id: String(l.id), satz: "Der Lauf endete ohne Fortschreibung.", daten: { letzte_antwort: letzteAntwort.slice(0, regelZahl("befund_antwort_zeichen")) } });
    zurueckMitWartezeit(db, a, "ohne_stand");
    return;
  }
  laufEnde(db, String(l.id), "beendet", verbrauch);
  const f = JSON.parse(String(ereignisse(db, { art: "fortschreibung", auftrag_id: String(a.id), grenze: 1 })[0].daten)) as Fortschreibung;
  const id = String(a.id);
  if (a.quelle === "dauerauftrag") return uebergang(db, "auftrag", id, "bereit", "termin", { naechster_anlass: naechsterTermin(a, jetzt), fehlversuche: 0 });
  if (f.ergebnis === "weiter") return uebergang(db, "auftrag", id, "bereit", "weiter", { naechster_anlass: jetzt, fehlversuche: 0 });
  if (f.ergebnis === "wartet") return uebergang(db, "auftrag", id, "wartet", "fortschreibung", { wartet_auf: f.wartet_auf ?? null, folge: f.folge ?? null, naechster_anlass: f.nachfass_um ?? null });
  const ergebnis = JSON.stringify({ satz: f.letzter_stand, links: [f.beleg] });
  const geprueft = kinder(db, id).some((k) => k.arbeitsart === "pruefen" && k.zustand === "erledigt");
  if (a.pruefer_noetig && !geprueft) {
    const kind = auftragAnlegen(db, {
      art: "unterauftrag", eltern_id: id, wortlaut: `Prüfe: ${f.letzter_stand} Beleg: ${f.beleg}`, wortlaut_quelle: `lauf:${l.id}`, titel: `Prüfung: ${a.titel}`,
      ziel: `Prüfen, ob „${a.ziel}“ erfüllt ist.`, abnahme: "Urteil passt oder Mängelliste", abnahme_durch: "auftraggeber", pruefer_noetig: false,
      verantwortlich: regelText("pruefer"), auftraggeber: String(a.verantwortlich), quelle: "kollege", bereich: String(a.bereich), arbeitsart: "pruefen",
    });
    return uebergang(db, "auftrag", id, "wartet", "pruefung", { wartet_auf: `auftrag:${kind.id}`, folge: "Ohne Prüfung keine Abnahme.", naechster_anlass: jetzt + regelMs("pruefung_nachfassen_h") });
  }
  if (a.abnahme_durch === "beleg") return uebergang(db, "auftrag", id, "erledigt", "fertig", { ergebnis });
  uebergang(db, "auftrag", id, "wartet_auf_abnahme", "fertig", { ergebnis, naechster_anlass: regelUhrzeitNach("fenster", jetzt) });
}
