import { aktiveLaeufe, auftraege, fragen, hole, offeneFrage, werte, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { naechsteUhrzeit, regelMs } from "../regeln.ts";
import { anzeigeName } from "../team.ts";
import { optionenSicht } from "./entscheiden.ts";
import { restMin, ZAHLWORT } from "./heute.ts";

type Phase = { name: string; zustand: "fertig" | "jetzt" | "offen" };
type Projekt = { untertitel?: string; worum?: string; satz?: string; phasen?: Phase[]; start?: number; ruht?: string | boolean; nach?: string };

const datum = (t: number) => new Date(t).toLocaleDateString("de-DE", { day: "numeric", month: "long" });

function projektName(db: Register, auftragId: unknown): string | null {
  return auftragId ? ((hole(db, "auftrag", String(auftragId)).projekt ?? null) as string | null) : null;
}

function sicht(db: Register, name: string, p: Projekt, jetzt: number) {
  const offen = fragen(db, "offen").filter((f) => projektName(db, f.auftrag_id) === name);
  const laeufe = aktiveLaeufe(db).filter((l) => projektName(db, l.auftrag_id) === name);
  const danach = auftraege(db, ["bereit"]).filter((a) => a.projekt === name && !offeneFrage(db, String(a.id))).sort((a, b) => Number(a.naechster_anlass ?? 0) - Number(b.naechster_anlass ?? 0));
  const zustand = offen.length ? "braucht" : laeufe.length ? "laeuft" : "wartet";
  const jetztPhase = p.phasen?.find((x) => x.zustand === "jetzt")?.name;
  const frist = offen.map((f) => f.frist).filter((f): f is number => typeof f === "number").sort()[0];
  const tage = p.start ? Math.round((p.start - naechsteUhrzeit("00:00", jetzt) + regelMs("ein_tag_h")) / regelMs("ein_tag_h")) : null;
  const rechts = zustand === "braucht" && frist ? [] : p.start ? [`Start ${datum(p.start)}`, `noch ${tage} ${tage === 1 ? "Tag" : "Tage"}`]
    : zustand === "wartet" && p.nach ? [`nach ${p.nach}`] : jetztPhase ? [`${jetztPhase} heute`] : [];
  const zeilen = [
    ...offen.map((f) => ({ art: "frage", id: f.id, text: f.text, wer: null, rechts: optionenSicht(f).optionen.find((o) => o.wert === f.empfehlung)?.knopf ?? null })),
    ...laeufe.map((l) => ({ art: "laeuft", id: l.auftrag_id, text: hole(db, "auftrag", String(l.auftrag_id)).titel, wer: `${anzeigeName(String(l.mitarbeiter))} arbeitet`,
      rechts: ((m) => (m === null ? null : `noch ${m} Min`))(restMin(db, l, jetzt)) })),
    ...danach.slice(0, 1).map((a: Zeile) => ({ art: "danach", id: a.id, text: a.titel, wer: `danach, ${anzeigeName(String(a.verantwortlich))}`,
      rechts: Number(a.naechster_anlass ?? Infinity) < naechsteUhrzeit("00:00", jetzt) ? "heute" : null })),
  ];
  return { name, untertitel: p.untertitel ?? null, worum: p.worum ?? null, satz: p.satz ?? null, phasen: p.phasen ?? [], zustand, frist: frist ?? null, rechts, zeilen, start: p.start ?? null };
}

export function projekte(db: Register, jetzt: number, fokus: boolean) {
  const alle = [...werte(db, "projekt:")].map(([k, v]) => [k.slice("projekt:".length), JSON.parse(v) as Projekt] as const);
  const ruhen = alle.filter(([, p]) => p.ruht).map(([n, p]) => (typeof p.ruht === "string" ? `${n} (${p.ruht})` : n));
  const liste = alle.filter(([, p]) => !p.ruht).map(([n, p]) => sicht(db, n, p, jetzt))
    .sort((a, b) => (a.start ?? Infinity) - (b.start ?? Infinity) || a.name.localeCompare(b.name, "de"));
  const n = liste.filter((p) => p.zustand === "braucht").length;
  const wort = n === 1 ? "Eins braucht" : `${(ZAHLWORT[n] ?? String(n)).replace(/^./, (c) => c.toUpperCase())} brauchen`;
  return {
    kopf: `${liste.length} ${liste.length === 1 ? "Projekt" : "Projekte"} in Arbeit${ruhen.length ? ` · ${ruhen.length} ruhen` : ""}`,
    satz: n ? [`${wort} dich${fokus ? " nach dem Fokus" : ""}.`, n < liste.length ? "Der Rest läuft ohne dich." : ""] : ["Keins braucht dich.", "Alles läuft ohne dich."],
    liste, ruhen: ruhen.length ? `Ruhen: ${ruhen.join(" · ")}` : null,
  };
}
