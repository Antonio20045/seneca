import { createHash, createHmac } from "node:crypto";
import { aktiveLaeufe, auftraege, uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { wertSetzen } from "../register/schreiben.ts";
import { regelMs, regelText } from "../regeln.ts";
import { mandat, mitarbeiter } from "../team.ts";
import { waehle } from "./modell.ts";

type Zugang = { zugang?: string; geheimnis?: string };
type Knoten = { name: string; ollama: boolean };

const sha = (t: string) => createHash("sha256").update(t).digest("hex");
const hmac = (k: string | Buffer, t: string) => createHmac("sha256", k).update(t).digest();

export function signiere(z: Required<Zugang>, a: { host: string; query: Record<string, string>; region: string; dienst: string; zeit: number }): { query: string; kopf: Record<string, string> } {
  const amz = new Date(a.zeit).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const query = Object.keys(a.query).sort().map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(a.query[k])}`).join("&");
  const kopf = { "content-type": "application/x-www-form-urlencoded; charset=utf-8", host: a.host, "x-amz-date": amz };
  const namen = Object.keys(kopf).join(";");
  const anfrage = ["GET", "/", query, ...Object.entries(kopf).map(([k, v]) => `${k}:${v}`), "", namen, sha("")].join("\n");
  const bereich = `${amz.slice(0, 8)}/${a.region}/${a.dienst}/aws4_request`;
  const schluessel = [amz.slice(0, 8), a.region, a.dienst, "aws4_request"].reduce<string | Buffer>((k, t) => hmac(k, t), `AWS4${z.geheimnis}`);
  const unterschrift = hmac(schluessel, ["AWS4-HMAC-SHA256", amz, bereich, sha(anfrage)].join("\n")).toString("hex");
  return { query, kopf: { ...kopf, authorization: `AWS4-HMAC-SHA256 Credential=${z.zugang}/${bereich}, SignedHeaders=${namen}, Signature=${unterschrift}` } };
}

async function ec2(z: Required<Zugang>, aktion: string): Promise<void> {
  const region = regelText("rechenknoten_region");
  const host = `ec2.${region}.amazonaws.com`;
  const { query, kopf } = signiere(z, { host, region, dienst: "ec2", zeit: uhr.jetzt(), query: { Action: aktion, "InstanceId.1": regelText("rechenknoten_instanz"), Version: "2016-11-15" } });
  const { host: _, ...senden } = kopf;
  const r = await fetch(`${regelText("rechenknoten_aws_url").replace("{host}", host)}?${query}`, { headers: senden, signal: AbortSignal.timeout(regelMs("aws_zeitlimit_s")) });
  if (!r.ok) throw new Error(`AWS ${aktion} ${r.status}`);
}

function gebraucht(db: Register): boolean {
  const team = mitarbeiter();
  const wartet = auftraege(db, ["bereit"]).some((a) => team.includes(String(a.verantwortlich)) && waehle(a, mandat(String(a.verantwortlich))).ort === "rechenknoten");
  return wartet || aktiveLaeufe(db).some((l) => l.ort === "rechenknoten");
}

export async function knotenJob(db: Register, z: Zugang, liste: () => Promise<Knoten[]>): Promise<void> {
  const knoten = JSON.stringify(await liste());
  if ((wert(db, "knoten")?.wert ?? "[]") !== knoten) wertSetzen(db, "knoten", knoten, "arbeitsdienst");
  if (!z.zugang || !z.geheimnis) return;
  const jetzt = uhr.jetzt();
  const w = wert(db, "rechenknoten");
  const bis = w?.gueltig_bis ?? 0;
  const leerlauf = regelMs("rechenknoten_leerlauf_min");
  if (gebraucht(db)) {
    if (w?.wert !== "an" || bis <= jetzt) await ec2({ zugang: z.zugang, geheimnis: z.geheimnis }, "StartInstances");
    if (w?.wert !== "an" || bis - jetzt < leerlauf / 2) wertSetzen(db, "rechenknoten", "an", "arbeitsdienst", jetzt + leerlauf);
  } else if (w?.wert === "an" && bis <= jetzt) {
    await ec2({ zugang: z.zugang, geheimnis: z.geheimnis }, "StopInstances");
    wertSetzen(db, "rechenknoten", "aus", "arbeitsdienst");
  }
}

export function knoten(db: Register): Knoten[] {
  return JSON.parse(wert(db, "knoten")?.wert ?? "[]");
}
