import { mkdirSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { uhr } from "./lesen.ts";
import type { Register } from "./schema.ts";

export function sichern(db: Register, ordner: string): string[] {
  mkdirSync(ordner, { recursive: true, mode: 0o700 });
  const d = new Date(uhr.jetzt());
  const ziele = [join(ordner, `register-stunde-${d.getHours()}.sqlite`), join(ordner, `register-tag-${d.getDay()}.sqlite`)];
  for (const ziel of ziele) {
    rmSync(`${ziel}.neu`, { force: true });
    db.prepare("VACUUM INTO ?").run(`${ziel}.neu`);
    renameSync(`${ziel}.neu`, ziel);
  }
  return ziele;
}
