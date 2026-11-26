import { createHmac, timingSafeEqual } from "node:crypto";
import { hole, uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { auftragSetzen, ereignis, uebergang } from "../register/schreiben.ts";

export function githubEingang(db: Register, roh: Buffer, kopf: Record<string, string | string[] | undefined>, schluessel: string | undefined): number {
  const erwartet = schluessel ? `sha256=${createHmac("sha256", schluessel).update(roh).digest("hex")}` : "";
  const signatur = String(kopf["x-hub-signature-256"] ?? "");
  if (!schluessel || signatur.length !== erwartet.length || !timingSafeEqual(Buffer.from(signatur), Buffer.from(erwartet))) return 401;
  const d = JSON.parse(roh.toString("utf8")) as { repository?: { full_name?: string }; pull_request?: { number?: number }; check_suite?: { pull_requests?: { number: number }[] } };
  const nr = d.pull_request?.number ?? d.check_suite?.pull_requests?.[0]?.number;
  const verweis = `${d.repository?.full_name}#${nr}`;
  ereignis(db, { art: "eingang", schluessel: String(kopf["x-github-delivery"] ?? verweis), daten: { quelle: "github", verweis, ereignis: kopf["x-github-event"] } });
  const auftragId = wert(db, `github:${verweis}`)?.wert;
  if (auftragId) {
    const a = hole(db, "auftrag", auftragId);
    if (a.zustand === "wartet") uebergang(db, "auftrag", auftragId, "bereit", "eingang", { naechster_anlass: uhr.jetzt() });
    else if (a.zustand === "bereit") auftragSetzen(db, auftragId, { naechster_anlass: uhr.jetzt(), anlass: "eingang" }, `GitHub: ${verweis}`);
  }
  return 204;
}
