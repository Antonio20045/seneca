import { anzeigen, eintraegeSeit, ereignisse, uhr, wert, werte } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { auftragAnlegen, ereignis, wertSetzen } from "../register/schreiben.ts";
import { regelListe, regelMs, regelZahl } from "../regeln.ts";
import { mandat, mitarbeiter } from "../team.ts";

export type Anlass = { art: "frage" | "ziel" | "luecke" | "sicht"; thema?: string; satz?: string; an?: string };

function anstossen(db: Register, an: string, thema: string, wortlaut: string, ziel: string): string | undefined {
  if (!mitarbeiter().includes(an)) throw new Error(`${an} ist kein Mitarbeiter.`);
  if (wert(db, `statistik:offen:${thema}`)) return undefined;
  const { id } = auftragAnlegen(db, {
    art: "eigener", quelle: "eigene_idee", wortlaut, wortlaut_quelle: `statistik:${thema}`, titel: `Statistik: ${thema}`.slice(0, regelZahl("titel_zeichen")), ziel,
    abnahme: "Statistik angelegt oder angepasst, oder ein Satz, warum keine nötig ist", abnahme_durch: "beleg", pruefer_noetig: false,
    verantwortlich: an, auftraggeber: an, bereich: mandat(an).bereich[0], arbeitsart: "statistik_anlegen",
  });
  wertSetzen(db, `statistik:offen:${thema}`, id, an, uhr.jetzt() + regelMs("statistik_anlass_tage"));
  return id;
}

function sicht(db: Register): string {
  const fragen = Map.groupBy(ereignisse(db, { art: "statistik.frage", seit: uhr.jetzt() - regelMs("statistik_anlass_tage") }), (e) => String(e.schluessel));
  return [
    "Ziele:", ...[...werte(db, "statistik:ziel:")].map(([k, v]) => `- ${k.slice("statistik:ziel:".length)}: ${v}`),
    "Statistiken:", ...anzeigen(db).map((z) => `- ${z.id} „${z.titel}“ (${z.projekt}, von ${z.besitzer}, ${z.zustand}): ${JSON.parse(String(z.werte)).grund ?? "ohne Grund"}; angesehen ${z.zuletzt_angesehen ? new Date(Number(z.zuletzt_angesehen)).toLocaleDateString("de-DE") : "nie"}`),
    "Standfragen:", ...[...fragen].map(([t, l]) => `- ${t}: ${l.length}-mal, zuletzt „${l[0].satz}“${wert(db, `statistik:offen:${t}`) ? ", Auftrag läuft" : ""}`),
  ].join("\n");
}

export function statistikAnlass(db: Register, agent: string, p: Anlass): { satz: string; auftrag_id?: string } {
  if (p.art === "sicht") return { satz: sicht(db) };
  const thema = String(p.thema ?? "").trim().toLowerCase(), an = p.an ?? agent, satz = String(p.satz ?? "");
  if (!thema || !satz) throw new Error("thema und satz fehlen.");
  if (p.art === "frage") {
    const vorher = ereignisse(db, { art: "statistik.frage", schluessel: thema, seit: uhr.jetzt() - regelMs("statistik_anlass_tage"), grenze: 1 })[0];
    ereignis(db, { art: "statistik.frage", wer: agent, schluessel: thema, satz });
    if (!vorher) return { satz: "Gemerkt. Fragt Antonio das noch einmal, entsteht der Auftrag für eine Statistik." };
    const id = anstossen(db, an, thema, `Antonio fragt zum zweiten Mal nach „${thema}“: „${satz}“ (vorher: „${vorher.satz}“).`, `Eine Statistik beantwortet „${satz}“ auf einen Blick`);
    return { satz: id ? "Sag Antonio in einem Satz: Ich lege dir dafür eine Statistik an." : "Der Auftrag für diese Statistik läuft schon.", auftrag_id: id };
  }
  if (p.art === "ziel" && wert(db, `statistik:ziel:${thema}`)?.wert === satz) return { satz: "Dieses Ziel kenne ich schon." };
  if (p.art === "ziel") wertSetzen(db, `statistik:ziel:${thema}`, satz, agent);
  const id = anstossen(db, an, thema, p.art === "ziel" ? `Ziel neu oder geändert: „${satz}“.` : `Rundgang: ${satz}`, p.art === "ziel" ? "Eine Statistik zeigt den Fortschritt zu diesem Ziel" : "Die Lücke ist geschlossen oder die Statistik ist weg");
  return { satz: id ? `Auftrag an ${an} liegt an.` : "Der Auftrag dazu läuft schon.", auftrag_id: id };
}

export function anlaesseJob(db: Register): void {
  const erst = !wert(db, "statistik:datenarten");
  const bekannt = new Set<string>(JSON.parse(wert(db, "statistik:datenarten")?.wert ?? "[]"));
  const zustaendig = new Map(regelListe("statistik_datenarten").map((x) => x.split(":") as [string, string]));
  const neu = [...new Set(eintraegeSeit(db, 0).map((e) => `${e.art}:${e.quelle}`))].filter((k) => !bekannt.has(k) && zustaendig.has(k.split(":")[0]));
  for (const k of neu) if (!erst) anstossen(db, String(zustaendig.get(k.split(":")[0])), `daten ${k}`, `Erstmals kommen Daten der Art ${k} an.`, "Geprüft, ob eine Statistik dazu fehlt; wenn ja, angelegt");
  if (neu.length || erst) wertSetzen(db, "statistik:datenarten", JSON.stringify([...bekannt, ...neu]), "seneca");
  for (const wer of mitarbeiter()) for (const z of mandat(wer).ziele) {
    const thema = `${wer} ${z.kennzahl}`, satz = `${z.kennzahl} ${z.ziel}`;
    if (wert(db, `statistik:ziel:${thema}`)?.wert === satz) continue;
    wertSetzen(db, `statistik:ziel:${thema}`, satz, wer);
    if (!erst) anstossen(db, wer, thema, `Ziel im Mandat neu oder geändert: „${satz}“.`, "Eine Statistik zeigt den Fortschritt zu diesem Ziel");
  }
}
