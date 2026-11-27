import { ereignisse, termineAm, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { regelMs } from "../regeln.ts";
import { uhrzeit } from "./heute.ts";

type Zurueck = { uid: string; start: number; ende: number };
type Teil = { teil: string; ergebnis?: string; name?: string; raus?: boolean; zurueck?: Zurueck | null };

const ankunft = (db: Register, name: string, jetzt: number) => termineAm(db, jetzt).map((t) => t.titel.includes(name) && wert(db, `ankunft:${t.uid}`)?.wert).find(Boolean);

function haelt(db: Register, z: Zurueck, ab: number, jetzt: number) {
  const bis = Math.min(z.start, ab + regelMs("zuruecklegen_min"));
  const belegt = termineAm(db, z.start).some((t) => t.uid !== z.uid && t.start < z.ende && t.ende > z.start);
  return bis > jetzt && !belegt && !wert(db, `zurueckgelegt:${z.uid}`) ? { ...z, ab, bis } : null;
}

export function verlauf(db: Register, tagBeginn: number, jetzt: number) {
  const gruppen: { sitzung: string; von: number; bis: number; teile: string[]; ergebnis: string[]; raus: string | null; zurueck?: Zurueck }[] = [];
  for (const e of ereignisse(db, { art: "quittung", seit: tagBeginn }).reverse()) {
    const d = JSON.parse(String(e.daten)) as Teil;
    let g = gruppen.find((x) => x.sitzung === e.schluessel && Number(e.zeit) - x.bis <= regelMs("quittung_buendel_min"));
    if (!g) gruppen.push(g = { sitzung: String(e.schluessel), von: Number(e.zeit), bis: Number(e.zeit), teile: [], ergebnis: [], raus: null });
    const da = d.name && ankunft(db, d.name, jetzt);
    g.bis = Number(e.zeit);
    g.teile.push(d.teil);
    if (d.ergebnis || da) g.ergebnis.push(d.ergebnis ?? `${d.name} · du bist ${uhrzeit(Number(da))} da`);
    if (d.raus) g.raus = `Die ${d.teil} ist schon raus.`;
    if (d.zurueck) g.zurueck = d.zurueck;
  }
  return { quittungen: gruppen.map(({ zurueck, ...g }) => ({ ...g, zuruecklegen: zurueck ? haelt(db, zurueck, g.bis, jetzt) : null })) };
}
