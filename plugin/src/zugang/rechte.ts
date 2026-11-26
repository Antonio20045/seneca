import { relative, resolve } from "node:path";
import { regelListe, regelText } from "../regeln.ts";
import { mandat, mitarbeiter } from "../team.ts";

type Urteil = { block: true; blockReason: string } | undefined;

export function dateiRecht(a: { werkzeug: string; params: Record<string, unknown>; agent: string }): Urteil {
  const eintrag = regelListe("datei_werkzeuge").map((e) => e.split("/")).find(([w]) => w === a.werkzeug);
  if (!eintrag || !mitarbeiter().includes(a.agent)) return undefined;
  const ablage = regelText("ablage_pfad");
  const ziel = resolve(ablage, String(a.params[eintrag[2]] ?? ""));
  const rel = relative(ablage, ziel);
  if (rel.startsWith("..") || rel === "") return undefined;
  const m = mandat(a.agent);
  const darf = eintrag[1] === "lesen" ? m.bereich.includes(rel.split("/")[0]) : m.befugnisse.ablage_schreiben.some((p) => rel === p || rel.startsWith(`${p}/`));
  return darf ? undefined : { block: true, blockReason: `${a.agent} darf ${rel} nicht ${eintrag[1] === "lesen" ? "lesen" : "schreiben"} (Mandat).` };
}
