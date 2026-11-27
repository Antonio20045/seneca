import { tokensJeAbo, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { wertSetzen } from "../register/schreiben.ts";
import { regelListe, regelZahl } from "../regeln.ts";
import { wochenbeginn } from "./kosten.ts";

const LIMIT = /limit\b.{0,40}?resets (?:([A-Z][a-z]{2} \d{1,2}), )?(\d{1,2})(?::(\d\d))?\s*(am|pm)/i;
const pause = (db: Register, abo: string) => wert(db, `abo_pause:${abo}`)?.gueltig_bis ?? 0;

export function aboReihenfolge(db: Register, jetzt: number): string[] {
  const verbraucht = tokensJeAbo(db, wochenbeginn(jetzt));
  const rest = (abo: string) => Number(wert(db, `abo_limit:${abo}`)?.wert ?? regelZahl("abo_limit_start_tokens")) - (verbraucht.get(abo) ?? 0);
  return regelListe("abos").filter((a) => pause(db, a) <= jetzt).sort((a, b) => rest(b) - rest(a));
}

export function limitMerken(db: Register, abo: string, text: string, jetzt: number): boolean {
  const m = LIMIT.exec(text);
  if (!m || !abo) return false;
  const t = new Date(m[1] ? `${m[1]} ${new Date(jetzt).getFullYear()}` : jetzt);
  t.setHours((Number(m[2]) % 12) + (m[4].toLowerCase() === "pm" ? 12 : 0), Number(m[3] ?? 0), 0, 0);
  if (t.getTime() <= jetzt) m[1] ? t.setFullYear(t.getFullYear() + 1) : t.setDate(t.getDate() + 1);
  wertSetzen(db, `abo_pause:${abo}`, "ja", "arbeitsdienst", t.getTime());
  const frei = aboReihenfolge(db, jetzt)[0];
  const [x, bis] = frei ? [abo, t.getTime()] : regelListe("abos").map((a) => [a, pause(db, a)] as const).sort((p, q) => p[1] - q[1])[0];
  const zeit = new Date(bis).toLocaleString("de-DE", { weekday: "short", hour: "2-digit", minute: "2-digit" });
  wertSetzen(db, "hinweis:abos", `Abo ${x.split(":")[1]} bis ${zeit} aufgebraucht, ${frei ? `Läufe nutzen jetzt ${frei.split(":")[1]}` : "Läufe warten"}.`, "arbeitsdienst", bis);
  return true;
}
