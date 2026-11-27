import { aktiveLaeufe, ereignisse, hole, kinder, kostenSeit, laeufe, laufZurSitzung, uhr, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import {
  auftragAnlegen, auftragSetzen, befund, ereignis, fortschreibung, frageBeantworten, frageStellen, laufAnlegen, laufEnde, laufSchritt, schritt, uebergang, vorschlagAnlegen, wertSetzen, type NeueFrage,
} from "../register/schreiben.ts";
import { naechsteUhrzeit, regelListe, regelMs, regelText, regelUhrzeitNach, regelZahl } from "../regeln.ts";
import { bauregeln, mandat, rolle } from "../team.ts";
import { aboReihenfolge, limitMerken } from "./abo.ts";
import { euro, kostenCent, rahmen, wochenbeginn, wocheSchonGefragt } from "./kosten.ts";
import { waehle } from "./modell.ts";
import { knoten } from "./rechenknoten.ts";
import { nachfassen, rundgangSicht, rundgangVorbereiten } from "./rundgang.ts";

export type Starter = (p: { sessionKey: string; message: string; model: string; idempotencyKey: string; werkzeuge: string[]; abos: string[] }) => Promise<{ runId: string }>;
type SkillLeser = (mitarbeiter: string, arbeitsart: string) => string | undefined;
type Nachricht = { kennung: string; text: string; vonAntonio: boolean };

const AKTIV = ["startet", "laeuft", "haengt"];
const nachrichten = new Map<string, Nachricht>();
type Verlaufszeile = { role?: string; content?: string | { text?: string }[]; idempotencyKey?: string; provenance?: { kind?: string }; __openclaw?: { transport?: { clients?: { mode?: string }[] } } };

export function merkeNachricht(sitzung: string, verlauf: unknown[]): void {
  const m = verlauf.at(-1) as Verlaufszeile | undefined;
  const text = typeof m?.content === "string" ? m.content : (m?.content ?? []).map((b) => b.text ?? "").join("");
  if (m?.role !== "user" || !m.idempotencyKey) nachrichten.delete(sitzung);
  else nachrichten.set(sitzung, { kennung: m.idempotencyKey, text, vonAntonio: m.provenance?.kind === "external_user" && !!m.__openclaw?.transport?.clients?.some((c) => c.mode === "ui") });
}

export const nachrichtVon = (sitzung: string): Nachricht | undefined => nachrichten.get(sitzung);
const antonios = (sitzung: string, kennung?: string) => [nachrichten.get(sitzung)].find((n) => n?.vonAntonio && (!kennung || n.kennung === kennung));

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

function startFrage(db: Register, a: Zeile, grund: string): void {
  const id = String(a.id);
  befund(db, { art: "fehler", auftrag_id: id, satz: `${a.verantwortlich} startet nicht, zweimal gleich abgelehnt. ${grund}` });
  const frage = frageStellen(db, {
    auftrag_id: id, von: "arbeitsdienst:start", art: "auswahl", text: `${a.verantwortlich} kann „${a.titel}“ nicht starten. Neu versuchen?`,
    was_passiert_ist: `Der Start wurde zweimal gleich abgelehnt. ${grund}`, wenn_nichts: `Seneca versucht es in ${regelText("start_nachfassen_h")} Stunden noch einmal.`,
    empfehlung: "Erst die Ursache beheben, dann neu versuchen.",
    optionen: [{ wert: "weiter", text: "Neu versuchen", folge: "Der Auftrag startet sofort." }, { wert: "anhalten", text: "Anhalten", folge: "Der Auftrag wird geparkt." }],
  });
  uebergang(db, "auftrag", id, "wartet", "start_abgelehnt", { wartet_auf: `frage:${frage}`, folge: "Der Auftrag ruht bis zur Antwort.", naechster_anlass: uhr.jetzt() + regelMs("start_nachfassen_h") });
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
  if (!abos.length) return "abos";
  const { stufe, modell, ort, lokal } = waehle(a, m);
  const verbunden = knoten(db);
  const name = regelText("rechenknoten_name");
  if (ort === "mac" || (ort === "rechenknoten" && !verbunden.some((k) => k.name === name))) return "ort";
  const ollama = lokal && verbunden.some((k) => k.ollama);
  const zusatz = [ollama ? " Textarbeit über node_inference (discover, dann run) auf dem lokalen Modell." : "", ort === "rechenknoten" ? ` Schwere Befehle mit exec host=${name}.` : ""].join("");
  const laufId = laufAnlegen(db, { auftrag_id: String(a.id), mitarbeiter: wer, anlass: String(a.anlass ?? "neu"), art: "werkzeug", ort, stufe, modell, abo: abos[0] });
  const lauf = hole(db, "lauf", laufId);
  if (a.arbeitsart === "rundgang") rundgangVorbereiten(db, a, jetzt);
  try {
    const { runId } = await starte({
      sessionKey: String(lauf.sitzung), message: `Arbeite am Auftrag „${a.titel}“. Der Auftrag steht oben im Kontext.${zusatz}`, model: modell, idempotencyKey: laufId, werkzeuge: ollama ? ["node_inference"] : [], abos,
    });
    laufSchritt(db, laufId, "angenommen", { run_id: runId });
  } catch (fehler) {
    const grund = limitMerken(db, abos[0], String(fehler), uhr.jetzt()) ? "Abo am Limit" : `Start abgelehnt: ${String(fehler)}`;
    const wieder = grund !== "Abo am Limit" && laeufe(db, String(a.id)).at(-2)?.grund === grund;
    laufEnde(db, laufId, "abgebrochen", { grund });
    if (wieder) startFrage(db, hole(db, "auftrag", String(a.id)), grund);
    else zurueckMitWartezeit(db, hole(db, "auftrag", String(a.id)), "start_abgelehnt");
  }
  return "gestartet";
}

const zeit = (t: number): string => new Date(t).toTimeString().slice(0, 5);

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
    [bauregeln(wer), true],
    [`Ablage ${regelText("ablage_pfad")}: lesen ${[...m.bereich, ...regelListe("ablage_alle_lesen")].join(", ")}; schreiben ${[...m.befugnisse.ablage_schreiben, `_arbeit/${wer}`].join(", ")}. Zwischendateien nur in _arbeit/${wer}/; dort löscht Seneca sie nach ${regelText("arbeitsdateien_tage")} Tagen, außer ihr Pfad steht im Ergebnis oder Beleg.`, true],
    [skill(wer, String(a.arbeitsart)) ?? "", true],
    [(m.kontext[String(a.arbeitsart)] ?? []).map((s) => `${s}: ${wert(db, s)?.wert ?? "nicht hinterlegt"}`).join("\n"), false],
    [`Auftrag von ${a.auftraggeber}, Quelle ${a.wortlaut_quelle}, ${new Date(Number(a.erstellt)).toLocaleString("de-DE")}. Wortlaut:\n${a.wortlaut}`, true],
    [`Ziel: ${a.ziel}\nAbnahme: ${a.abnahme} (durch ${a.abnahme_durch})${a.pruefer_noetig ? "\nPrüfer nötig." : ""}`, false],
    [`Letzter Stand: ${a.letzter_stand || "noch nichts"}\nNächster Schritt: ${a.naechster_schritt || "offen"}${a.schritt_nr ? `\nPunkt ${a.schritt_nr} von ${a.schritt_gesamt}` : ""}`, false],
    [anlassSatz(db, a), false],
    [a.arbeitsart === "rundgang" ? rundgangSicht(db, a, uhr.jetzt()) : "", true],
    [eltern ? `Elternauftrag: ${String(eltern.wortlaut).slice(0, regelZahl("kontext_eltern_zeichen"))}\nZiel: ${eltern.ziel}` : "", false],
    [[...ereignisse(db, { art: "befund", auftrag_id: String(a.id), grenze: regelZahl("kontext_befunde") }), ...ereignisse(db, { art: "entscheidung", auftrag_id: String(a.id), grenze: regelZahl("kontext_befunde") })]
      .sort((x, y) => Number(y.nr) - Number(x.nr)).slice(0, regelZahl("kontext_befunde"))
      .map((b) => b.art === "befund" ? `Befund: ${b.satz}` : `Antonio (${b.geraet}, Kennung ${b.schluessel}): „${b.satz}“. Gilt das über diesen Auftrag hinaus, rufe seneca_lernen mit dieser Kennung auf.`).join("\n"), true],
    [`Kosten: ${euro(verbraucht)} von ${euro(Number(a.kostenrahmen_cent))}. Stufe ${l.stufe}.`, false],
  ];
  const liste = teile.filter(([t]) => t);
  const kuerzbar = () => liste.filter(([, fest]) => !fest).reduce((n, [t]) => n + t.length, 0);
  for (let i = liste.length - 1; i >= 0 && kuerzbar() > regelZahl("kontext_zeichen"); i--) if (!liste[i][1]) liste.splice(i, 1);
  return liste.map(([t]) => t).join("\n\n");
}

export type AuftragEingabe = {
  art: "auftrag" | "unterauftrag" | "vorschlag" | "idee" | "eigener" | "nachfassen" | "abnahme" | "verwerfen" | "fortsetzen";
  nachricht_kennung?: string; wortlaut?: string; titel?: string; ziel?: string; abnahme?: string; abnahme_durch?: string; pruefer_noetig?: boolean;
  an?: string; bereich?: string; projekt?: string; frist?: number; arbeitsart?: string; schaetzung_min?: number; eltern_id?: string;
  auftrag_id?: string; urteil?: "passt" | "nachbessern"; satz?: string; herkunft?: string; termin?: { titel: string; start: number; ende: number; ort?: string };
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
  if (p.art === "fortsetzen") {
    if (!antonios(ctx.sitzung, p.nachricht_kennung)) throw new Error("Fortsetzen nur auf Antonios Nachricht in diesem Gespräch.");
    uebergang(db, "auftrag", String(p.auftrag_id), "bereit", "auftrag.fortsetzen", { naechster_anlass: uhr.jetzt() });
    return { auftrag_id: String(p.auftrag_id), satz: "Der Auftrag läuft wieder an." };
  }
  if (p.art === "nachfassen") return { auftrag_id: String(p.auftrag_id), satz: nachfassen(db, laufender(db, ctx.sitzung), ctx.agent, String(p.auftrag_id), String(p.satz)) };
  if (p.art === "eigener" && hole(db, "auftrag", String(laufender(db, ctx.sitzung).auftrag_id)).arbeitsart !== "rundgang") throw new Error("Eigene Aufträge entstehen im Rundgang.");
  const n = antonios(ctx.sitzung, p.nachricht_kennung);
  const lauf = p.art === "auftrag" ? undefined : laufZurSitzung(db, ctx.sitzung);
  if (p.art === "auftrag" && !n) throw new Error("Ein Auftrag entsteht nur aus Antonios Nachricht in diesem Gespräch.");
  if (p.art === "unterauftrag") {
    const eltern = hole(db, "auftrag", String(p.eltern_id));
    if (laufender(db, ctx.sitzung).auftrag_id !== eltern.id) throw new Error("Unteraufträge vergibt nur der Lauf des Elternauftrags.");
    if (!mandat(ctx.agent).befugnisse.unterauftrag_an.includes(String(p.an))) throw new Error(`Unterauftrag an ${p.an} ist im Mandat nicht erlaubt.`);
  }
  const verantwortlich = p.art === "eigener" ? ctx.agent : p.an ?? ctx.agent;
  const felder = {
    wortlaut: String(p.wortlaut), wortlaut_quelle: n?.kennung ?? `lauf:${lauf?.id ?? ctx.sitzung}`, titel: p.titel ?? String(p.wortlaut).slice(0, regelZahl("titel_zeichen")),
    ziel: String(p.ziel), abnahme: String(p.abnahme), abnahme_durch: p.abnahme_durch ?? (p.art === "eigener" ? "beleg" : "antonio"), pruefer_noetig: !!p.pruefer_noetig, verantwortlich,
    auftraggeber: p.art === "auftrag" ? "antonio" : ctx.agent, bereich: p.bereich ?? mandat(verantwortlich).bereich[0], projekt: p.projekt, frist: p.frist,
    arbeitsart: p.arbeitsart ?? "standard", schaetzung_min: p.schaetzung_min, eltern_id: p.eltern_id,
  };
  if (p.art === "vorschlag") {
    if (p.termin && wert(db, `vorschlag:lassen:${new Date(p.termin.start).getDay()}:${p.termin.titel}`)) throw new Error("Antonio will diesen Vorschlag an diesem Wochentag nicht mehr.");
    const id = vorschlagAnlegen(db, { ...felder, herkunft: p.herkunft ?? `mitarbeiter:${ctx.agent}`, frage: { text: `${felder.titel}?`, was_passiert_ist: felder.wortlaut, empfehlung: felder.ziel, frist: p.frist }, wirkung: p.termin ? { termin: p.termin } : undefined });
    return { auftrag_id: id, satz: "Vorschlag liegt bei Antonio." };
  }
  const { id, kostenrahmen_cent } = auftragAnlegen(db, {
    ...felder, art: p.art, quelle: { auftrag: "du", unterauftrag: "kollege", idee: "eigene_idee", eigener: "eigene_idee" }[p.art],
    nachricht: n && p.art === "auftrag" ? { kennung: n.kennung, text: n.text } : undefined,
  }, { sitzung: ctx.sitzung });
  const satz = p.schaetzung_min ? `Notiert. ${verantwortlich} kümmert sich, etwa ${euro(kostenrahmen_cent)}.` : `Notiert. ${verantwortlich} kümmert sich, Rahmen ${euro(kostenrahmen_cent)}.`;
  return { auftrag_id: id, satz };
}

export function werkzeugFrage(db: Register, sitzung: string, f: NeueFrage): string {
  const l = f.auftrag_id ? undefined : laufender(db, sitzung);
  const a = l && hole(db, "auftrag", String(l.auftrag_id));
  if (!l || !a || a.quelle !== "dauerauftrag") return frageStellen(db, { ...f, auftrag_id: f.auftrag_id ?? String(a?.id) });
  return schritt(db, () => {
    const { id } = auftragAnlegen(db, { art: "eigener", quelle: "eigene_idee", wortlaut: f.text, wortlaut_quelle: `lauf:${l.id}`, titel: f.kurz ?? f.text.slice(0, regelZahl("titel_zeichen")), ziel: f.empfehlung,
      abnahme: "Antonio hat geantwortet, der nächste Schritt ist getan.", abnahme_durch: "beleg", pruefer_noetig: false, verantwortlich: f.von, auftraggeber: f.von, bereich: mandat(f.von).bereich[0], arbeitsart: "standard" });
    const frage = frageStellen(db, { ...f, auftrag_id: id });
    uebergang(db, "auftrag", id, "wartet", "frage", { wartet_auf: `frage:${frage}`, folge: f.wenn_nichts, naechster_anlass: uhr.jetzt() + regelMs("lange_wartend_h") });
    return frage;
  });
}

export function werkzeugAntwort(db: Register, sitzung: string, frageId: string, antwort: string, kennung?: string) {
  const n = antonios(sitzung, kennung);
  if (!n) throw new Error("Eine Antwort trägt nur Antonios Nachricht ein.");
  return frageBeantworten(db, { frage_id: frageId, antwort, geraet: "gespraech", kennung: n.kennung, nachricht_kennung: n.kennung });
}

export function werkzeugProtokoll(db: Register, sitzung: string, werkzeug: string, params: Record<string, unknown>, ms?: number): void {
  const l = laufZurSitzung(db, sitzung);
  if (!l || !AKTIV.includes(String(l.zustand))) return;
  const kurz = String(Object.values(params ?? {}).find((v) => typeof v === "string") ?? "").split("\n")[0];
  ereignis(db, { art: "lauf.werkzeug", lauf_id: String(l.id), auftrag_id: String(l.auftrag_id), satz: kurz.slice(0, regelZahl("titel_zeichen")), daten: { werkzeug, ms: ms ?? null } });
}

export function fragenZurueckziehen(db: Register, id: string, von: string, satz: string): { zustand: string } {
  if (hole(db, "frage", id).von !== von) throw new Error("Nur wer fragt, zieht die Frage zurück.");
  uebergang(db, "frage", id, "zurueckgezogen", "von", { grund: satz });
  return { zustand: "zurueckgezogen" };
}

export type Fortschreibung = {
  letzter_stand: string; naechster_schritt: string; ergebnis: "weiter" | "wartet" | "fertig"; beleg?: string; wartet_auf?: string; folge?: string;
  nachfass_um?: number; schritt_nr?: number; schritt_gesamt?: number; befunde?: string[]; stufe?: "hoch"; abnahme_art?: string; hoerprobe_s?: number; abnahme?: Record<string, unknown>;
  checkliste?: { text: string; fertig: boolean }[]; bericht?: string;
};

export function werkzeugFortschreiben(db: Register, sitzung: string, p: Fortschreibung): { zustand: string } {
  const l = laufender(db, sitzung);
  if (p.ergebnis === "wartet" && !(p.wartet_auf && p.folge && p.nachfass_um)) throw new Error("wartet braucht wartet_auf, Folge und Nachfasszeit.");
  if (p.ergebnis === "fertig" && !p.beleg) throw new Error("fertig braucht einen Beleg.");
  for (const satz of p.befunde ?? []) befund(db, { art: "teilergebnis", satz, auftrag_id: String(l.auftrag_id), lauf_id: String(l.id), beleg: p.beleg });
  if (p.stufe === "hoch") auftragSetzen(db, String(l.auftrag_id), { stufe_fest: "opus" }, "Lauf bittet um höhere Stufe.");
  fortschreibung(db, String(l.id), p);
  return { zustand: "notiert" };
}

export function agentEnde(db: Register, sitzung: string, letzteAntwort: string, tokens: { ein: number; aus: number; cent?: number }): void {
  const l = laufZurSitzung(db, sitzung);
  if (!l || !AKTIV.includes(String(l.zustand))) return;
  const a = hole(db, "auftrag", String(l.auftrag_id));
  const jetzt = uhr.jetzt();
  const verbrauch = { tokens_ein: tokens.ein, tokens_aus: tokens.aus, kosten_cent: tokens.cent ?? kostenCent(tokens.ein, tokens.aus) };
  if (!l.fortgeschrieben) {
    laufEnde(db, String(l.id), "abgebrochen", { grund: limitMerken(db, String(l.abo ?? ""), letzteAntwort, jetzt) ? "Abo am Limit" : "ohne Stand", ...verbrauch });
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
  const ergebnis = JSON.stringify({ satz: f.letzter_stand, links: [f.beleg], art: f.abnahme_art, hoerprobe_s: f.hoerprobe_s, ...f.abnahme });
  const geprueft = kinder(db, id).some((k) => k.arbeitsart === "pruefen" && k.zustand === "erledigt" && JSON.parse(String(k.ergebnis ?? "{}")).urteil !== "nachbessern");
  if (a.pruefer_noetig && !geprueft) {
    const kind = auftragAnlegen(db, {
      art: "unterauftrag", eltern_id: id, wortlaut: `Prüfe: ${f.letzter_stand} Beleg: ${f.beleg}`, wortlaut_quelle: `lauf:${l.id}`, titel: `Prüfung: ${a.titel}`,
      ziel: `Prüfen, ob „${a.ziel}“ erfüllt ist.`, abnahme: "Urteil passt oder Mängelliste", abnahme_durch: "beleg", pruefer_noetig: false,
      verantwortlich: regelText("pruefer"), auftraggeber: String(a.verantwortlich), quelle: "kollege", bereich: String(a.bereich), arbeitsart: "pruefen",
    });
    return uebergang(db, "auftrag", id, "wartet", "pruefung", { wartet_auf: `auftrag:${kind.id}`, folge: "Ohne Prüfung keine Abnahme.", naechster_anlass: jetzt + regelMs("pruefung_nachfassen_h") });
  }
  if (a.abnahme_durch === "beleg") return uebergang(db, "auftrag", id, "erledigt", "fertig", { ergebnis });
  uebergang(db, "auftrag", id, "wartet_auf_abnahme", "fertig", { ergebnis, naechster_anlass: regelUhrzeitNach("fenster", jetzt) });
}
