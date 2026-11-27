import { aktiveLaeufe, anzeigen, auftraege, ereignisse, fragen, hole, laeufe, laeufeSeit, ruht, uhr, wert, wiederholungenSeit, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { anzeigeSetzen, auftragSetzen, befund, uebergang, vorschlagAnlegen, wertSetzen, type Wirkung } from "../register/schreiben.ts";
import { regelMs, regelText, regelZahl } from "../regeln.ts";
import { mandat, mitarbeiter } from "../team.ts";
import { euro, wochenbeginn } from "./kosten.ts";

const OFFEN = ["vorgeschlagen", "geparkt", "bereit", "laeuft", "wartet", "wartet_auf_abnahme"];

function seneca(wer: string): boolean {
  return wer === regelText("dauerauftraege_von");
}

function meine(db: Register, wer: string): Zeile[] {
  return auftraege(db, OFFEN).filter((a) => a.quelle !== "dauerauftrag" && (seneca(wer) || a.verantwortlich === wer || a.auftraggeber === wer));
}

function tage(ms: number): number {
  return Math.floor(ms / regelMs("ein_tag_tage"));
}

function feststeckt(db: Register, a: Zeile, jetzt: number): string | undefined {
  const alt = jetzt - Number(a.geaendert) > regelMs("rundgang_alt_tage");
  const frage = String(a.wartet_auf ?? "").startsWith("frage:") ? hole(db, "frage", String(a.wartet_auf).slice("frage:".length)) : undefined;
  const lauf = aktiveLaeufe(db).find((l) => l.auftrag_id === a.id);
  if (a.frist !== null && Number(a.frist) < jetzt && a.zustand !== "geparkt") return `Frist seit ${tage(jetzt - Number(a.frist))} Tagen vorbei`;
  if (a.zustand === "bereit" && Number(a.fehlversuche) >= regelZahl("rundgang_fehlversuche")) return `startet nicht, ${a.fehlversuche} Versuche`;
  if (a.zustand === "bereit" && ruht(db, String(a.verantwortlich), jetzt)) return `liegt, weil ${a.verantwortlich} ruht`;
  if (lauf?.zustand === "haengt") return `hängt seit ${new Date(Number(lauf.letzter_schritt_um)).toTimeString().slice(0, 5)}`;
  if (a.zustand === "wartet" && frage && !["offen", "beantwortet"].includes(String(frage.zustand))) return `wartet auf eine Frage, die ${frage.zustand} ist`;
  if (a.zustand === "wartet" && alt) return `wartet seit ${tage(jetzt - Number(a.geaendert))} Tagen auf ${a.wartet_auf}`;
  if (a.zustand === "wartet_auf_abnahme" && alt) return `Abnahme liegt seit ${tage(jetzt - Number(a.geaendert))} Tagen`;
  return undefined;
}

function vertagt(db: Register, f: Zeile): number {
  return ereignisse(db, { art: "frage.vertagt", frage_id: String(f.id) }).length;
}

export function rundgangSicht(db: Register, a: Zeile, jetzt: number): string {
  const wer = String(a.verantwortlich);
  const vorher = laeufe(db, String(a.id)).at(-2);
  const seit = vorher ? Number(vorher.gestartet) : jetzt - regelMs("ein_tag_tage");
  const m = mandat(wer);
  const zeilen: string[] = [`Rundgang von ${wer}. Seit ${new Date(seit).toLocaleString("de-DE")}:`];
  const fest = meine(db, wer).map((x) => [x, feststeckt(db, x, jetzt)] as const).filter(([, g]) => g);
  zeilen.push(`Feststeckend (${fest.length}):`, ...fest.map(([x, g]) => `- ${x.id} „${x.titel}“ (${x.verantwortlich}, ${x.zustand}): ${g}`));
  const lange = fragen(db, "offen").filter((f) => jetzt - Number(f.gestellt) > regelMs("lange_wartend_h") && meine(db, wer).some((x) => x.id === f.auftrag_id));
  zeilen.push(...lange.map((f) => `- Frage ${f.id} am Auftrag ${f.auftrag_id} „${f.text}“ wartet seit ${tage(jetzt - Number(f.gestellt))} Tagen, ${vertagt(db, f)}-mal vertagt`));
  if (m.signale.length) zeilen.push("Signale deines Mandats:", ...m.signale.map((s) => `- ${s.quelle}: ${s.was}`));
  if (m.ziele.length) zeilen.push("Ziele deines Mandats (als Anzeige zahl setzen, bei Abweichung eigener Auftrag):", ...m.ziele.map((z) => `- ${z.kennzahl} ${z.ziel}`));
  const woche = wochenbeginn(jetzt);
  if (seneca(wer)) {
    zeilen.push("Team:", ...mitarbeiter().map((n) => {
      const neu = laeufeSeit(db, n, seit);
      const kosten = laeufeSeit(db, n, woche).reduce((s, l) => s + Number(l.kosten_cent), 0);
      return `- ${n}: ${ruht(db, n, jetzt) ? "ruht" : `Läufe ${neu.length}`}, ${neu.filter((l) => l.grund === "ohne Stand").length} ohne Stand, diese Woche ${euro(kosten)}`;
    }));
    const eingang = ereignisse(db, { art: "eingang", seit }).map((e) => JSON.parse(String(e.daten)));
    if (eingang.length) zeilen.push(`Eingänge (${eingang.length}), gebündelt auswerten; Zusagen und Bitten werden Vorschläge:`, ...eingang.slice(0, regelZahl("rundgang_eingaenge")).map((e) => `- ${e.quelle}: ${JSON.stringify(e.verweis)}`));
    const geparkt = auftraege(db, ["geparkt"]);
    if (geparkt.length && (!vorher || Number(vorher.gestartet) < woche)) zeilen.push("Geparkte Ideen (einmal je Woche durchsehen):", ...geparkt.map((x) => `- ${x.id} „${x.titel}“`));
    const wdh = wiederholungenSeit(db, woche);
    if (wdh) zeilen.push(`Wiederholungen diese Woche: ${wdh}.`);
  }
  const aehnlich = new Map<string, number>();
  for (const x of auftraege(db, [...OFFEN, "erledigt"]).filter((x) => x.quelle === "du" && x.verantwortlich === wer && jetzt - Number(x.erstellt) < regelMs("rundgang_aehnlich_tage"))) {
    aehnlich.set(String(x.arbeitsart), (aehnlich.get(String(x.arbeitsart)) ?? 0) + 1);
  }
  const skill = [...aehnlich].filter(([, n]) => n >= regelZahl("rundgang_muster_anzahl")).map(([art]) => art);
  if (skill.length) zeilen.push(`Ab dem dritten ähnlichen Auftrag: prüfe, ob ein Skill fehlt (höchstens eine Seite): ${skill.join(", ")}.`);
  zeilen.push("So handelst du: Folgezug mit seneca_auftrag art nachfassen (auftrag_id, satz). Braucht es Antonio: seneca_frage mit Kontext und Empfehlung; ohne auftrag_id wird daraus ein eigener Auftrag, der auf seine Antwort wartet. "
    + "Eigener Auftrag mit prüfbarem Nutzen: seneca_auftrag art eigener (zählt gegen dein Wochenbudget). Was in Antonios Namen etwas anlegt: art vorschlag mit herkunft.");
  return zeilen.slice(0, regelZahl("rundgang_zeilen")).join("\n");
}

function einmal(db: Register, muster: string, wer: string, vorschlag: () => void): void {
  if (wert(db, `muster:${muster}`)) return;
  vorschlag();
  wertSetzen(db, `muster:${muster}`, "vorgeschlagen", wer);
}

function regel(db: Register, wer: string, titel: string, warum: string, wirkung: Wirkung): void {
  vorschlagAnlegen(db, {
    wortlaut: warum, wortlaut_quelle: `rundgang:${wer}`, titel, ziel: titel, abnahme: "Wirkt nach Ja", abnahme_durch: "beleg", pruefer_noetig: false,
    verantwortlich: wer, auftraggeber: wer, bereich: mandat(wer).bereich[0], arbeitsart: "regel", herkunft: "rundgang",
    frage: { text: `${titel}?`, was_passiert_ist: warum, empfehlung: "Ja, wenn das so stimmt." }, wirkung,
  });
}

export function rundgangVorbereiten(db: Register, a: Zeile, jetzt: number): void {
  const wer = String(a.verantwortlich);
  for (const z of anzeigen(db, wer)) {
    if (z.zustand === "aktiv" && jetzt - Number(z.stand) > regelMs("anzeige_veraltet_tage")) {
      anzeigeSetzen(db, { id: String(z.id), projekt: String(z.projekt), art: String(z.art), titel: String(z.titel), werte: JSON.parse(String(z.werte)), besitzer: wer, zustand: "grau" });
    }
    if (jetzt - Number(z.zuletzt_angesehen ?? z.stand) > regelMs("anzeige_ungesehen_tage")) {
      einmal(db, `anzeige:${z.id}`, wer, () => regel(db, wer, `Kann „${z.titel}“ weg`, `Die Anzeige „${z.titel}“ hat seit ${tage(jetzt - Number(z.zuletzt_angesehen ?? z.stand))} Tagen niemand angesehen.`, { anzeige_weg: String(z.id) }));
    }
  }
  if (!seneca(wer)) return;
  for (const f of fragen(db, "offen").filter((f) => f.art !== "vorschlag" && vertagt(db, f) >= regelZahl("rundgang_muster_anzahl"))) {
    const x = hole(db, "auftrag", String(f.auftrag_id));
    einmal(db, `parken:${x.id}`, wer, () => regel(db, wer, `„${x.titel}“ parken`, `Die Frage „${f.text}“ hast du ${vertagt(db, f)}-mal auf später gelegt.`, { parken: String(x.id) }));
  }
  const freigaben = new Map<string, string[]>();
  for (const v of ereignisse(db, { art: "ausgang.vorgemerkt" })) {
    const d = JSON.parse(String(v.daten));
    const f = v.frage_id ? hole(db, "frage", String(v.frage_id)) : undefined;
    if (d.stufe === "kurz_fragen" && d.empfaenger.length === 1 && f?.zustand === "beantwortet") freigaben.set(d.empfaenger[0], [...(freigaben.get(d.empfaenger[0]) ?? []), String(f.antwort)]);
  }
  for (const [e, antworten] of freigaben) {
    if (antworten.length < regelZahl("rundgang_muster_anzahl") || antworten.some((x) => x !== "ja") || wert(db, `kontakt:${e}`)?.wert !== "kurz_fragen") continue;
    einmal(db, `kontakt:${e}`, wer, () => regel(db, wer, `Nachrichten an ${e} künftig ohne Frage`, `Du hast ${antworten.length}-mal Ja gesagt, nie Nein.`, { wert: { schluessel: `kontakt:${e}`, wert: "frei" } }));
  }
}

export function nachfassen(db: Register, l: Zeile, agent: string, id: string, satz: string): string {
  if (hole(db, "auftrag", String(l.auftrag_id)).arbeitsart !== "rundgang") throw new Error("Nachfassen geht nur im Rundgang.");
  const a = hole(db, "auftrag", id);
  if (!seneca(agent) && a.verantwortlich !== agent && a.auftraggeber !== agent) throw new Error("Nachfassen nur bei eigenen Aufträgen; Seneca fasst bei allen nach.");
  if (ereignisse(db, { art: "befund", auftrag_id: id, lauf_id: String(l.id) }).length) return "Schon nachgefasst in diesem Rundgang.";
  const lauf = aktiveLaeufe(db).find((x) => x.auftrag_id === id);
  if (!lauf && !["wartet", "bereit"].includes(String(a.zustand))) throw new Error(`Der Auftrag ist ${a.zustand}; ein Folgezug hilft hier nicht. Frag Antonio oder schlag etwas vor.`);
  befund(db, { art: "nachgefasst", auftrag_id: id, lauf_id: String(l.id), satz: `Rundgang von ${agent}: ${satz}` });
  if (lauf) {
    wertSetzen(db, `anstupsen:${lauf.id}`, "offen", agent);
    return "Folgezug geht in den laufenden Lauf.";
  }
  if (a.zustand === "wartet") uebergang(db, "auftrag", id, "bereit", "rundgang", { naechster_anlass: uhr.jetzt() });
  else auftragSetzen(db, id, { naechster_anlass: uhr.jetzt(), fehlversuche: 0 }, "Rundgang fasst nach.");
  return "Der Auftrag ist wieder dran; dein Satz steht in seinem Kontext.";
}
