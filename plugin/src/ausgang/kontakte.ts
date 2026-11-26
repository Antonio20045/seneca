import { wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";

export function normalisiere(empfaenger: string): string {
  const e = empfaenger.trim().toLowerCase();
  if (e.includes("@")) return e;
  const ziffern = e.replace(/[^\d+]/g, "");
  return ziffern.startsWith("00") ? `+${ziffern.slice(2)}` : ziffern;
}

export function stufe(db: Register, empfaenger: string): string | undefined {
  const n = normalisiere(empfaenger);
  return wert(db, `kontakt:${n}`)?.wert ?? (n.includes("@") ? wert(db, `kontakt:org:@${n.split("@")[1]}`)?.wert : undefined);
}
