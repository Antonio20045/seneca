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
  const klein = rel.toLowerCase();
  const unter = (p: string) => klein === p.toLowerCase() || klein.startsWith(`${p.toLowerCase()}/`);
  const schreiben = unter(`_arbeit/${a.agent}`) || m.befugnisse.ablage_schreiben.some(unter);
  const darf = schreiben || (eintrag[1] === "lesen" && [...m.bereich, ...regelListe("ablage_alle_lesen")].some(unter));
  return darf ? undefined : { block: true, blockReason: `${a.agent} darf ${rel} nicht ${eintrag[1] === "lesen" ? "lesen" : "schreiben"} (Mandat).` };
}
