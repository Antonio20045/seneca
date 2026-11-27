import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { Register } from "../register/schema.ts";
import { befund, ereignis, wertSetzen } from "../register/schreiben.ts";
import { regelMs, regelText } from "../regeln.ts";
import { anzeigeName, mandat, mitarbeiter, ordner } from "../team.ts";

type Befehl = (argv: string[], ms: number) => Promise<{ code: number | null; stderr: string }>;
export type Eingabe = { aktion: string; name: string; rolle?: string; mandat?: string; ruht?: boolean; bis?: number };

const DATEIEN = ["rolle.md", "mandat"];
export async function mitarbeiterVerwalten(db: Register, befehl: Befehl, p: Eingabe): Promise<string> {
  const { aktion, name } = p, repo = dirname(ordner()), ws = join(homedir(), ".openclaw", "team", name), ort = join(ordner(), name), seneca = join(ordner(), regelText("dauerauftraege_von"), "mandat");
  if (!/^[a-z][a-z0-9-]{1,30}$/.test(name)) throw new Error("Der Name besteht aus kleinen Buchstaben, Ziffern und Bindestrichen.");
  if (mitarbeiter().includes(name) === (aktion === "anlegen")) throw new Error(`${name} ${aktion === "anlegen" ? "gibt es schon" : "gibt es nicht"}.`);
  if (aktion !== "aendern" && [regelText("dauerauftraege_von"), regelText("pruefer")].includes(name)) throw new Error(`${name} bleibt.`);
  const gateway = async (methode: string, params: object) => {
    const r = await befehl([regelText("openclaw_befehl"), "gateway", "call", methode, "--json", "--params", JSON.stringify(params)], regelMs("takt_job_haengt_s"));
    if (r.code !== 0) throw new Error(`${methode}: ${r.stderr.slice(0, 200)}`);
  };
  const befugt = (neu: (liste: string[]) => string[]) => writeFileSync(seneca, readFileSync(seneca, "utf8").replace(/(unterauftrag_an: \[)([^\]]*)\]/, (_, a, l) => `${a}${neu(l.split(/,\s*/).filter(Boolean)).join(", ")}]`));
  if (aktion === "ruhen") return wertSetzen(db, `ruht:${name}`, p.ruht === false ? "nein" : "ja", "seneca", p.bis), `${anzeigeName(name)} ${p.ruht === false ? "arbeitet wieder" : "ruht"}.`;
  if (aktion === "loeschen") {
    if (db.prepare("SELECT 1 FROM auftrag WHERE verantwortlich = ? AND zustand NOT IN ('erledigt', 'verworfen')").get(name)) throw new Error(`${name} hat noch offene Aufträge.`);
    await gateway("agents.delete", { agentId: name, deleteFiles: true });
    rmSync(ort, { recursive: true, force: true });
    befugt((l) => l.filter((x) => x !== name));
  } else if (aktion === "anlegen" || aktion === "aendern") {
    const alt = DATEIEN.map((f) => (existsSync(join(ort, f)) ? readFileSync(join(ort, f), "utf8") : null)), neu = [p.rolle, p.mandat];
    if (aktion === "anlegen" && neu.some((t) => !t)) throw new Error("Zum Anlegen gehören rolle und mandat.");
    if ((p.rolle ?? "# ").split("\n").length > 60 || !(p.rolle ?? "# ").startsWith("# ")) throw new Error("Die Rolle beginnt mit „# Name“ und hat höchstens 60 Zeilen.");
    const zurueck = () => (DATEIEN.forEach((f, i) => (alt[i] === null ? rmSync(join(ort, f), { force: true }) : writeFileSync(join(ort, f), alt[i]))), aktion === "anlegen" && rmSync(ort, { recursive: true, force: true }));
    mkdirSync(ort, { recursive: true });
    neu.forEach((t, i) => t && writeFileSync(join(ort, DATEIEN[i]), t));
    try {
      mandat(name);
      if (aktion === "anlegen") {
        await gateway("agents.create", { name, agentId: name, workspace: ws });
        readdirSync(ws).filter((f) => f.endsWith(".md")).forEach((f) => rmSync(join(ws, f)));
        writeFileSync(join(ws, "AGENTS.md"), `# ${name}\n\nDeine Rolle, dein Mandat und dein Auftrag stehen im Seneca-Kontext jedes Laufs. Regeln stehen nur dort und in deinen Skills.\n`);
      }
    } catch (fehler) {
      zurueck();
      throw fehler;
    }
    if (aktion === "anlegen") befugt((l) => [...l, name]);
  }
  ereignis(db, { art: "team.geaendert", wer: "seneca", schluessel: name, satz: aktion });
  befehl(["sh", join(repo, "plugin", "nachzug.sh"), repo, name, aktion], regelMs("mitarbeiter_nachzug_s")).then((r) => r.code !== 0 && befund(db, { art: "fehler", satz: `Mitarbeiter ${name}: Nachzug ins Repo scheitert: ${r.stderr.slice(0, 200)}` }));
  return aktion === "loeschen" ? `${name} ist gelöscht.` : `${anzeigeName(name)} ist ${aktion === "anlegen" ? "da, Antonio spricht ihn links im Team an" : "geändert"}.`;
}
