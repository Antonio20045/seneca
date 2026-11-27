import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { basename, extname, resolve, sep } from "node:path";
import { regelListe, regelText, regelZahl } from "../regeln.ts";

export function dateiVorschau(roh: string): Record<string, string> {
  const ablage = realpathSync(regelText("ablage_pfad"));
  const ziel = resolve(ablage, roh.replace(/^(~|\/Users\/[^/]+|\/home\/[^/]+)\/Ablage\//, ""));
  const echt = existsSync(ziel) ? realpathSync(ziel) : "";
  if (!echt.startsWith(ablage + sep) || echt.startsWith(resolve(ablage, "_sicherung") + sep) || !statSync(echt).isFile()) return { hinweis: "Die Datei gibt es in der Ablage nicht." };
  const name = basename(echt), endung = extname(name).slice(1).toLowerCase(), pfad = echt.slice(ablage.length + 1), art = ["md", "html"].includes(endung) ? endung : regelListe("datei_text_endungen").includes(endung) ? "text" : endung;
  if (statSync(echt).size > regelZahl("datei_vorschau_max_kb") * 1024) return { name, pfad, art, hinweis: "Die Datei ist zu groß für die Vorschau." };
  const inhalt = readFileSync(echt);
  return ["md", "html", "text"].includes(art) ? { name, pfad, art, inhalt: inhalt.toString("utf8") } : { name, pfad, art, data: `data:application/octet-stream;base64,${inhalt.toString("base64")}` };
}
