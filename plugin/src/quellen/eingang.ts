import { auftraege, ereignisse, uhr, wert, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { auftragAnlegen, eintragSetzen, vorschlagAnlegen, wertSetzen } from "../register/schreiben.ts";
import { letzteUhrzeit, msAusMinuten, regelText, regelZahl } from "../regeln.ts";
import { mandat } from "../team.ts";

type Sensor = { art?: string; text?: string; app?: string; titel?: string; sicherheit?: number; von?: number; bis?: number };

function sensor(db: Register, e: Zeile, s: Sensor): void {
  const titel = String(s.titel ?? "").slice(0, regelZahl("sensor_titel_zeichen"));
  if (s.art === "spur") {
    const dauer = Number(s.bis) - Number(s.von);
    if (dauer >= msAusMinuten(regelZahl("sensor_spur_ab_min"))) eintragSetzen(db, { art: "tagesspur", werte: { app: s.app, titel, dauer_min: Math.round(dauer / msAusMinuten(1)) }, zeit: Number(s.von), quelle: "mac", handlung_kennung: String(e.schluessel) });
    return;
  }
  const text = String(s.text ?? "").trim();
  const heute = auftraege(db, ["vorgeschlagen", "bereit", "laeuft", "wartet", "erledigt", "verworfen"])
    .filter((a) => String(a.wortlaut_quelle).startsWith("sensor:") && Number(a.erstellt) >= letzteUhrzeit(regelText("tag_grenze"), uhr.jetzt()));
  if (s.art !== "vorschlag" || !text || Number(s.sicherheit) * 100 < regelZahl("sensor_sicherheit_prozent")) return;
  if (heute.length >= regelZahl("sensor_vorschlaege_je_tag") || heute.some((a) => a.wortlaut === text)) return;
  const wer = regelText("dauerauftraege_von");
  vorschlagAnlegen(db, {
    wortlaut: text, wortlaut_quelle: `sensor:${e.schluessel}`, titel: text.slice(0, regelZahl("titel_zeichen")), ziel: text, abnahme: "Ergebnis mit Beleg", abnahme_durch: "antonio",
    pruefer_noetig: false, verantwortlich: wer, auftraggeber: wer, bereich: mandat(wer).bereich[0], arbeitsart: "standard", herkunft: "sensor",
    frage: { text: `${text}?`, was_passiert_ist: `Du warst in ${s.app}${titel ? `: „${titel}“` : ""}.`, empfehlung: "Ja, wenn dir das Arbeit abnimmt." },
  });
}

function auswerten(db: Register, e: Zeile, quelle: string, verweis: unknown): void {
  const wer = regelText("dauerauftraege_von");
  auftragAnlegen(db, {
    art: "system", wortlaut: `Neuer Eingang (${quelle}): ${JSON.stringify(verweis)}. Ordne ihn in Bereich und Projekt ein. Beschlüsse und Zusagen werden Vorschläge an Antonio.`,
    wortlaut_quelle: `eingang:${e.nr}`, titel: quelle === "meeting" ? "Meeting auswerten" : "Eingang einordnen", ziel: "Eingang eingeordnet, Zusagen als Vorschlag", abnahme: "Fortschreibung mit Beleg",
    abnahme_durch: "beleg", pruefer_noetig: false, verantwortlich: wer, auftraggeber: wer, quelle: "eigene_idee", bereich: mandat(wer).bereich[0], arbeitsart: "eingang", naechster_anlass: uhr.jetzt(),
  });
}

export function eingangJob(db: Register): void {
  const neu = ereignisse(db, { art: "eingang", nach: Number(wert(db, "eingang:bis")?.wert ?? 0) }).reverse();
  for (const e of neu) {
    const { quelle, verweis } = JSON.parse(String(e.daten));
    if (quelle === "sensor") sensor(db, e, (verweis ?? {}) as Sensor);
    if (quelle === "meeting" || quelle === "teilen") auswerten(db, e, quelle, verweis);
  }
  if (neu.length) wertSetzen(db, "eingang:bis", String(neu.at(-1)?.nr), "quellen");
}
