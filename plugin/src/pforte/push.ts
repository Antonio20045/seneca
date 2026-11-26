import { sign } from "node:crypto";
import { connect } from "node:http2";
import { uhr, wert } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { befund } from "../register/schreiben.ts";
import { msAusSekunden, regelMs, regelText } from "../regeln.ts";

type Zugang = { schluessel?: string; schluessel_id?: string; team_id?: string };
export type Sender = (db: Register, geraet: string, text: string, frageId: string) => Promise<void>;

const b64 = (o: object | Buffer) => (Buffer.isBuffer(o) ? o : Buffer.from(JSON.stringify(o))).toString("base64url");

export function pushSender(z: Zugang): Sender | undefined {
  if (!z.schluessel || !z.schluessel_id || !z.team_id) return undefined;
  let marke = { text: "", um: 0 };
  const jwt = () => {
    if (uhr.jetzt() - marke.um > regelMs("apns_marke_neu_min")) {
      const kopf = `${b64({ alg: "ES256", kid: z.schluessel_id })}.${b64({ iss: z.team_id, iat: Math.floor(uhr.jetzt() / msAusSekunden(1)) })}`;
      marke = { text: `${kopf}.${b64(sign("sha256", Buffer.from(kopf), { key: String(z.schluessel), dsaEncoding: "ieee-p1363" }))}`, um: uhr.jetzt() };
    }
    return marke.text;
  };
  return async (db, geraet, text, frageId) => {
    const ziel = wert(db, `push:${geraet}`)?.wert;
    if (!ziel) return;
    const verbindung = connect(regelText("apns_url"));
    const status = await new Promise<number>((fertig, fehler) => {
      const r = verbindung.request({ ":method": "POST", ":path": `/3/device/${ziel}`, authorization: `bearer ${jwt()}`, "apns-topic": regelText("apns_thema"), "apns-push-type": "alert" }, { signal: AbortSignal.timeout(regelMs("apns_zeitlimit_s")) });
      r.on("response", (k) => fertig(Number(k[":status"])));
      r.on("error", fehler);
      r.end(JSON.stringify({ aps: { alert: { title: "Seneca", body: text }, sound: "default", "thread-id": frageId }, frage: frageId }));
    }).finally(() => verbindung.close());
    if (status !== 200) befund(db, { art: "fehler", satz: `Mitteilung an ${geraet} nicht angekommen (APNs ${status}).` });
  };
}
