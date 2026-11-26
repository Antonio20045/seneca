import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { uhr } from "../src/register/lesen.ts";
import { oeffne, type Register } from "../src/register/schema.ts";
import { auftragAnlegen, frageStellen, type NeuerAuftrag } from "../src/register/schreiben.ts";
import plugin from "../src/index.ts";

export function frischesRegister(): Register {
  return oeffne(join(mkdtempSync(join(tmpdir(), "seneca-")), "register.sqlite"));
}

export function um(hhmm: string, tag = "2026-11-27"): number {
  const t = new Date(`${tag}T${hhmm}:00`).getTime();
  uhr.jetzt = () => t;
  return t;
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

export function ladePlugin() {
  const ordner = mkdtempSync(join(tmpdir(), "seneca-plugin-"));
  const werkzeuge = new Map<string, Fabrik>();
  const haken = new Map<string, Haken>();
  const methoden = new Map<string, (o: { params: Record<string, unknown> }) => unknown>();
  const starts: { sessionKey: string; message: string; model: string }[] = [];
  const api = {
    pluginConfig: { ordner },
    registerTool: (f: Fabrik, o: { name: string }) => werkzeuge.set(o.name, f),
    on: (name: string, h: Haken) => haken.set(name, h),
    registerGatewayMethod: (name: string, h: (o: { params: Record<string, unknown> }) => unknown) => methoden.set(name, h),
    registerService: () => undefined,
    registerHttpRoute: () => undefined,
    runtime: { subagent: { run: async (p: { sessionKey: string; message: string; model: string }) => (starts.push(p), { runId: `run-${starts.length}` }) } },
  };
  plugin.register(api as unknown as Parameters<typeof plugin.register>[0]);
  const db = oeffne(join(ordner, "register.sqlite"));
  const starte = (p: { sessionKey: string; message: string; model: string; idempotencyKey: string }) => api.runtime.subagent.run(p);
  return {
    db, starts, starte,
    werkzeug: async (name: string, sitzung: string, agent: string, p: object) => (await (werkzeuge.get(name) as Fabrik)({ sessionKey: sitzung, agentId: agent }).execute("t", p)).details as Record<string, string>,
    nachricht: (sitzung: string, kennung: string, text: string, vonAntonio = true) => haken.get("before_prompt_build")?.(
      { prompt: text, messages: [], currentUserMessage: text, currentUserMessageId: kennung }, { sessionKey: sitzung, inputProvenance: { kind: vonAntonio ? "external_user" : "inter_session" } }),
    kontext: (sitzung: string) => (haken.get("before_prompt_build")?.({ prompt: "", messages: [] }, { sessionKey: sitzung }) as { prependContext?: string } | undefined)?.prependContext,
    ende: (sitzung: string, ausgabeTokens = 0) => haken.get("agent_end")?.({ messages: [{ role: "assistant", content: "Ich bin fertig.", usage: { input: 0, output: ausgabeTokens } }], success: true }, { sessionKey: sitzung }),
    methode: (name: string, params: Record<string, unknown>) => (methoden.get(name) as (o: { params: Record<string, unknown> }) => unknown)({ params }),
  };
}
