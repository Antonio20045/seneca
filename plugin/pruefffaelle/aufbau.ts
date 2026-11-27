import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { uhr } from "../src/register/lesen.ts";
import { oeffne, type Register } from "../src/register/schema.ts";
import { auftragAnlegen, frageStellen, type NeuerAuftrag, wertSetzen } from "../src/register/schreiben.ts";
import { mitarbeiter } from "../src/team.ts";
import plugin from "../src/index.ts";

export function frischesRegister(): Register {
  return oeffne(join(mkdtempSync(join(tmpdir(), "seneca-")), "register.sqlite"));
}

export function um(hhmm: string, tag = "2026-11-27"): number {
  const t = new Date(`${tag}T${hhmm}:00`).getTime();
  uhr.jetzt = () => t;
  return t;
}

export function nurWach(db: Register, ...namen: string[]): void {
  for (const m of mitarbeiter()) if (!namen.includes(m)) wertSetzen(db, `ruht:${m}`, "ja", "test");
}

export function spaeter(ms: number): number {
  const t = uhr.jetzt() + ms;
  uhr.jetzt = () => t;
  return t;
}

export function auftragVonAntonio(db: Register, wortlaut: string, mehr: Partial<NeuerAuftrag> = {}): string {
  const kennung = `msg-${wortlaut.length}-${uhr.jetzt()}`;
  return auftragAnlegen(db, {
    art: "auftrag", wortlaut, wortlaut_quelle: kennung, titel: wortlaut.slice(0, 40), ziel: "Ergebnis mit Beleg", abnahme: "Beleg liegt vor",
    abnahme_durch: "antonio", pruefer_noetig: false, verantwortlich: "produkt", auftraggeber: "antonio", quelle: "du", bereich: "Sundartha",
    arbeitsart: "bauen", nachricht: { kennung, text: `Antonio: ${wortlaut}` }, ...mehr,
  }).id;
}

export function jaNeinFrage(db: Register, auftragId: string, text: string, mehr: Record<string, unknown> = {}): string {
  return frageStellen(db, {
    auftrag_id: auftragId, von: "produkt", text, was_passiert_ist: "Kontext", wenn_nichts: "Es wartet.", empfehlung: "Ja", art: "ja_nein",
    optionen: [{ wert: "ja", text: "Ja", folge: "Es geht weiter." }, { wert: "nein", text: "Nein", folge: "Es bleibt liegen." }], ...mehr,
  });
}

type Werkzeug = { execute: (id: string, p: unknown) => Promise<{ details: unknown }> };
type Fabrik = (ctx: { sessionKey: string; agentId: string }) => Werkzeug;
type Haken = (event: unknown, ctx: unknown) => unknown;

export function ladePlugin(ordner = mkdtempSync(join(tmpdir(), "seneca-plugin-")), mehr: Record<string, unknown> = {}) {
  const werkzeuge = new Map<string, Fabrik>();
  const haken = new Map<string, Haken>();
  const vorWerkzeug: Haken[] = [];
  const methoden = new Map<string, (o: { params: Record<string, unknown> }) => unknown>();
  const starts: { sessionKey: string; message: string; model: string; werkzeuge: string[] }[] = [];
  const api = {
    rootDir: new URL("..", import.meta.url).pathname,
    pluginConfig: { ordner, ...mehr },
    registerTool: (f: Fabrik, o: { name: string }) => werkzeuge.set(o.name, f),
    on: (name: string, h: Haken) => (name === "before_tool_call" ? vorWerkzeug.push(h) : haken.set(name, h)),
    registerGatewayMethod: (name: string, h: (o: { params: Record<string, unknown> }) => unknown) => methoden.set(name, h),
    registerService: () => undefined,
    registerHttpRoute: () => undefined,
    runtime: { subagent: { run: async (p: { sessionKey: string; message: string; model: string; werkzeuge: string[] }) => (starts.push(p), { runId: `run-${starts.length}` }) } },
  };
  plugin.register(api as unknown as Parameters<typeof plugin.register>[0]);
  const db = oeffne(join(ordner, "register.sqlite"));
  const starte = (p: { sessionKey: string; message: string; model: string; idempotencyKey: string; werkzeuge: string[] }) => api.runtime.subagent.run(p);
  return {
    db, starts, starte, ordner,
    aufruf: (sitzung: string, toolName: string, params: Record<string, unknown>, toolCallId = `t-${Math.random()}`, agentId = "produkt") =>
      vorWerkzeug.map((h) => h({ toolName, params, toolCallId }, { sessionKey: sitzung, toolName, agentId })).find(Boolean) as { block: true; blockReason: string } | undefined,
    nachAufruf: (toolCallId: string) => haken.get("after_tool_call")?.({ toolName: "x", params: {}, toolCallId }, {}),
    werkzeug: async (name: string, sitzung: string, agent: string, p: object) => (await (werkzeuge.get(name) as Fabrik)({ sessionKey: sitzung, agentId: agent }).execute("t", p)).details as Record<string, string>,
    nachricht: (sitzung: string, kennung: string, text: string, vonAntonio = true) => haken.get("before_prompt_build")?.(
      { prompt: text, messages: [], currentUserMessage: text, currentUserMessageId: kennung }, { sessionKey: sitzung, inputProvenance: { kind: vonAntonio ? "external_user" : "inter_session" } }),
    kontext: (sitzung: string) => (haken.get("before_prompt_build")?.({ prompt: "", messages: [] }, { sessionKey: sitzung }) as { prependContext?: string } | undefined)?.prependContext,
    ende: (sitzung: string, ausgabeTokens = 0) => haken.get("agent_end")?.({ messages: [{ role: "assistant", content: "Ich bin fertig.", usage: { input: 0, output: ausgabeTokens } }], success: true }, { sessionKey: sitzung }),
    empfangen: (kanal: string, messageId: string, from: string) => haken.get("message_received")?.({ content: "geheim", messageId, from }, { channelId: kanal }),
    methode: (name: string, params: Record<string, unknown>) => (methoden.get(name) as (o: { params: Record<string, unknown> }) => unknown)({ params }),
  };
}

export async function kalenderAttrappe(termine: Map<string, string>) {
  const aufrufe: string[] = [];
  const antwort = (inhalt: string) => `<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">${inhalt}</d:multistatus>`;
  const server = createServer(async (req, res) => {
    let koerper = "";
    for await (const teil of req) koerper += teil;
    aufrufe.push(`${req.method} ${req.url}`);
    const pfad = String(req.url);
    if (req.method === "PROPFIND" && pfad === "/") res.end(antwort("<d:response><d:href>/</d:href><d:propstat><d:prop><d:current-user-principal><d:href>/p/</d:href></d:current-user-principal></d:prop></d:propstat></d:response>"));
    else if (req.method === "PROPFIND" && pfad === "/p/") res.end(antwort("<d:response><d:href>/p/</d:href><d:propstat><d:prop><c:calendar-home-set><d:href>/h/</d:href></c:calendar-home-set></d:prop></d:propstat></d:response>"));
    else if (req.method === "PROPFIND") res.end(antwort("<d:response><d:href>/h/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response><d:response><d:href>/h/k1/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/><c:calendar/></d:resourcetype></d:prop></d:propstat></d:response>"));
    else if (req.method === "REPORT") res.end(antwort([...termine].map(([uid, ics]) => `<d:response><d:href>/h/k1/${uid}.ics</d:href><d:propstat><d:prop><d:getetag>"e${ics.length}"</d:getetag><c:calendar-data>${ics.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</c:calendar-data></d:prop></d:propstat></d:response>`).join("")));
    else if (req.method === "PUT") {
      termine.set(pfad.replace("/h/k1/", "").replace(".ics", ""), koerper);
      res.statusCode = 201;
      res.end();
    } else res.end();
  });
  await new Promise<void>((fertig) => server.listen(0, "127.0.0.1", fertig));
  return { url: `http://127.0.0.1:${(server.address() as AddressInfo).port}/`, aufrufe, server };
}

export function regelnMit(werte: Record<string, string>): () => void {
  const kopie = join(mkdtempSync(join(tmpdir(), "regeln-")), "regeln");
  const text = Object.entries(werte).reduce((t, [k, v]) => t.replace(new RegExp(`^${k} .*$`, "m"), `${k} ${v}`), readFileSync(new URL("../../regeln", import.meta.url), "utf8"));
  writeFileSync(kopie, text);
  process.env.SENECA_REGELN = kopie;
  return () => delete process.env.SENECA_REGELN;
}
