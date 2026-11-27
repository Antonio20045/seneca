import { existsSync, readFileSync } from "node:fs";
import type { IncomingHttpHeaders } from "node:http";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { OpenClawPluginApi, OpenClawPluginToolContext } from "openclaw/plugin-sdk/plugin-entry";
import { Type, type TSchema } from "typebox";
import { knotenJob } from "./arbeitsdienst/rechenknoten.ts";
import type { Starter } from "./arbeitsdienst/lauf.ts";
import { faelligeAuftraegeJob, faelligeWirkungenJob, gespraecheJob, kalenderWacheJob, laeufePruefenJob, nachNeustart, pflegenJob, type Befehl } from "./arbeitsdienst/jobs.ts";
import { agentEnde, fragenZurueckziehen, laufGestoppt, werkzeugProtokoll, kontext, merkeNachricht, nachrichtVon, werkzeugAntwort, werkzeugAuftrag, werkzeugFortschreiben, werkzeugFrage, type AuftragEingabe, type Fortschreibung } from "./arbeitsdienst/lauf.ts";
import { takt } from "./arbeitsdienst/takt.ts";
import { lesenWerkzeug, ruhe, stand, uhrStand } from "./pforte/stand.ts";
import { planenJob } from "./pforte/planen.ts";
import { weg } from "./pforte/wochenplan.ts";
import { verstehen } from "./pforte/verstehen.ts";
import { pushSender } from "./pforte/push.ts";
import { zustellenJob, type Poster } from "./pforte/zustellen.ts";
import { nachWerkzeug, pruefeAufruf, unklarePruefen, unteragentEnde, unteragentMerken } from "./ausgang/ausgang.ts";
import { korrigieren, type Korrektur } from "./lernen/lernen.ts";
import { anlaesseJob, statistikAnlass, type Anlass } from "./lernen/anlass.ts";
import { dateiVorschau } from "./quellen/ablage.ts";
import { eingangJob } from "./quellen/eingang.ts";
import { githubEingang } from "./quellen/github.ts";
import { kalenderJob, kalenderWerkzeug } from "./quellen/kalender.ts";
import { mitlesen } from "./quellen/whatsapp.ts";
import { dateiRecht } from "./zugang/rechte.ts";
import { LAUF, schluesselHash, uhrAbgleich, uhrAbholen, uhrKoppeln } from "./zugang/uhr.ts";
import { handeln } from "./zugang/handeln.ts";
import { eintraegeSeit, ereignisse, revision, termineAm, todos, uhr, wert } from "./register/lesen.ts";
import { oeffne, type Register } from "./register/schema.ts";
import { buch, jahr, lauf, monat, tag, uebung, woche } from "./quellen/statistik.ts";
import { anzeigeSetzen, eintragAendern, eintragSetzen, ereignis, todoSetzen, wertSetzen, type NeueFrage, type TodoAktion } from "./register/schreiben.ts";
import { lebensbereich, letzteUhrzeit, naechsteUhrzeit, regelMs, regelText, regelZahl, sekundenAusMs } from "./regeln.ts";

type Kontext = { sitzung: string; agent: string };
type Ausfuehren = (db: Register, k: Kontext, p: Record<string, unknown>) => unknown;

const S = Type.String();
const Z = Type.Number();
const O = Type.Optional;
const Frei = Type.Record(Type.String(), Type.Unknown());

function nurSeneca(k: Kontext): void {
  if (k.agent !== "seneca") throw new Error("Das darf nur Seneca.");
}

const WERKZEUGE: [string, string, TSchema, Ausfuehren][] = [
  ["seneca_lesen", "Kurze Sicht aus dem Register: tag (Antonios Tag für Briefing, Morgenbericht, Rückblick: Satz, To-dos, Routinen, Termine, Körper, Fragen, Aufträge seit gestern), status (ehrliche Lage auf „Status“: alle offenen Fragen an Antonio, geparkte Aufträge mit Zahl, was läuft, nächste Läufe, Team), auftrag mit id, auftraege (deine offenen Aufträge mit Wortlaut und Stand, mit id = Projekt nur dieses), team, fragen (alle offenen), profil, fakten, kontakt.", Type.Object({ was: S, id: O(S) }),
    (db, k, p) => lesenWerkzeug(db, String(p.was), p.id as string | undefined, k.agent)],
  ["seneca_auftrag", "Auftrag anlegen (nur aus Antonios Nachricht im Gespräch; nachricht_kennung nur, wenn du sie kennst, sonst gilt seine letzte; wortlaut = sein Text), Unterauftrag, Vorschlag (mit termin: Block im Kalender nach Ja), Idee, Abnahme, Verwerfen oder geparkten Auftrag fortsetzen (nur auf Antonios Nachricht).",
    Type.Object({ art: S, nachricht_kennung: O(S), wortlaut: O(S), titel: O(S), ziel: O(S), abnahme: O(S), abnahme_durch: O(S), pruefer_noetig: O(Type.Boolean()),
      an: O(S), bereich: O(S), projekt: O(S), frist: O(Z), arbeitsart: O(S), schaetzung_min: O(Z), eltern_id: O(S), auftrag_id: O(S), urteil: O(S), satz: O(S), herkunft: O(S),
      termin: O(Type.Object({ titel: S, start: Z, ende: Z, ort: O(S) })) }),
    (db, k, p) => werkzeugAuftrag(db, k, p as AuftragEingabe)],
  ["seneca_fortschreiben", "Pflicht am Ende jedes Laufs: letzter Stand, Beleg, nächster Schritt, Ergebnis weiter, wartet oder fertig. Bei fertig: abnahme_art text, test, hoerprobe oder bau; bei Hörprobe hoerprobe_s; abnahme: kursiv (Halbsatz zum Titel), transkript, geaendert, vorher (Datei), vorher_s, unterschied (Text mit [-weg-] {+neu+}, Code als Zeilen mit „+ “/„- “), dateien, folge („Passt: …“), ergebnis (Test in einem Satz), urteil (Prüfer: passt oder nachbessern, letzter_stand nennt dann den Fehler in einem Satz). befunde: Teilergebnisse, die schon bereitliegen (mit beleg). checkliste: was fertig ist und was offen bleibt; bericht: kurz, z. B. „4 Dateien · Tests grün“.",
    Type.Object({ letzter_stand: S, naechster_schritt: S, ergebnis: S, beleg: O(S), wartet_auf: O(S), folge: O(S), nachfass_um: O(Z), schritt_nr: O(Z),
      schritt_gesamt: O(Z), befunde: O(Type.Array(S)), stufe: O(S), abnahme_art: O(S), hoerprobe_s: O(Z),
      abnahme: O(Type.Object({ urteil: O(S), kursiv: O(S), transkript: O(S), geaendert: O(S), vorher: O(S), vorher_s: O(Z), unterschied: O(Type.Array(S)), dateien: O(Z), folge: O(S), ergebnis: O(S) })),
      checkliste: O(Type.Array(Type.Object({ text: S, fertig: Type.Boolean() }))), bericht: O(S) }),
    (db, k, p) => werkzeugFortschreiben(db, k.sitzung, p as Fortschreibung)],
  ["seneca_frage", "Frage zurückziehen (art zurueckziehen, frage_id, text: ein Satz, was jetzt passiert), Frage an Antonio stellen (mit Kontext, Folge, Empfehlung, grund: warum du das empfiehlst, kurz: „Testanruf freigeben?“, zeit_fuer: „den Anruf“, wenn er danach Zeit braucht, lage: ein Satz, worauf du wartest, haengt: was daran hängt mit Zeitpunkt, rueckfragen: drei kurze Fragen, die Antonio dir stellen könnte, zusatz: was es ihn kostet in wenigen Worten, „zwei Minuten, nur Staging“) oder seine Antwort eintragen. Fassungen zur Wahl: je Option titel („Fassung A · klar“), preis, einheit, text.",
    Type.Object({ art: S, auftrag_id: O(S), text: O(S), was_passiert_ist: O(S), wenn_nichts: O(S), empfehlung: O(S), fragenart: O(S),
      optionen: O(Type.Array(Type.Object({ wert: S, text: S, folge: S, titel: O(S), preis: O(S), einheit: O(S) }))), frist: O(Z), frage_id: O(S), antwort: O(S), nachricht_kennung: O(S), kurz: O(S), zeit_fuer: O(S),
      grund: O(S), lage: O(S), zusatz: O(S), rueckfragen: O(Type.Array(S)), haengt: O(Type.Array(Type.Object({ um: Z, text: S }))) }),
    (db, k, { grund, lage, zusatz, rueckfragen, haengt, ...p }) => p.art === "antwort" ? werkzeugAntwort(db, k.sitzung, String(p.frage_id), String(p.antwort), p.nachricht_kennung as string | undefined)
      : p.art === "zurueckziehen" ? fragenZurueckziehen(db, String(p.frage_id), k.agent, String(p.text))
      : { frage_id: werkzeugFrage(db, k.sitzung, { ...(p as unknown as NeueFrage), art: String(p.fragenart ?? "auswahl"), von: k.agent, mehr: { grund, lage, zusatz, rueckfragen, haengt } }) }],
  ["seneca_projekt", "Projekt fortschreiben: Untertitel, worum es geht (ein Satz für Antonio), Stand in einem Satz, Phasen (fertig, jetzt, offen), Start (ms), nach (wartet auf Projekt), ruht (Grund).",
    Type.Object({ name: S, untertitel: O(S), worum: O(S), satz: O(S), phasen: O(Type.Array(Type.Object({ name: S, zustand: S }))), start: O(Z), nach: O(S), ruht: O(S) }),
    (db, k, p) => {
      const { name, ...rest } = p;
      if (!wert(db, `projekt:${name}`) && rest.worum) statistikAnlass(db, k.agent, { art: "ziel", thema: `projekt ${name}`, satz: String(rest.worum) });
      return { ok: wertSetzen(db, `projekt:${name}`, JSON.stringify(rest), k.agent) > 0 };
    }],
  ["seneca_lernen", "Korrektur von Antonio an genau einem Ort lernen: skill, profil, sperre oder fakt.",
    Type.Object({ nachricht_kennung: O(S), wortlaut: S, ort: S, ziel: S, kern: S, wiederholung_von: O(Z),
      aenderung: Type.Object({ skill: O(S), alt: O(S), neu: O(S), schluessel: O(S), wert: O(S) }) }),
    (db, k, p) => korrigieren(db, k.agent, nachrichtVon(k.sitzung), p as Korrektur)],
  ["seneca_einstellen", "Wert setzen: ruht:<name>, kontakt:<nummer oder mail>, name:<nummer oder mail> (Vorname), profil:<feld>, fakt:<thema>, ankunft:<termin-uid> (ms), termin_notiz:<termin-uid> (ein Satz, was Seneca dazu getan hat).", Type.Object({ schluessel: S, wert: S, gueltig_bis: O(Z) }),
    (db, k, p) => {
      nurSeneca(k);
      return { ok: wertSetzen(db, String(p.schluessel), String(p.wert), k.agent, p.gueltig_bis as number | undefined) > 0 };
    }],
  ["seneca_anzeige", "Anzeige setzen oder entfernen (höchstens 4 je Projekt). Statistik ohne Code: anzeigenart statistik, werte { metrik: art.feld aus den Einträgen (lauf.km, lauf.pace_s, lauf.h, satz.1rm, satz.volumen, nacht.hrv, tag.ruhepuls, aktivitaet.anzahl …), filter: { u: \"Kniebeuge\" }, zeitraum_tage, gruppe: tag|woche|monat|einzeln, rechnung: summe|schnitt|max|min|anzahl|letzter, diagramm: balken|linie|ring|zahl, einheit, ziel, grund: ein Satz, warum }.", Type.Object({ id: O(S), projekt: S, anzeigenart: S, titel: S, werte: Frei, zustand: O(S), beantwortet: O(S) }),
    (db, k, p) => ({ anzeige_id: anzeigeSetzen(db, { ...(p as { projekt: string; titel: string; werte: object }), art: String(p.anzeigenart), besitzer: k.agent }) })],
  ["seneca_statistik", "Anlass für eine Statistik. art frage: Antonio fragt nach einem Stand („wie läuft X“, „wie weit ist Y“); thema: das Ding in ein, zwei kleinen Wörtern (kniebeuge, wochen-km), satz: seine Frage, an: wer zuständig ist. Beim zweiten Mal in 14 Tagen entsteht ein Auftrag an den Zuständigen. art ziel: Ziel neu oder geändert („100 km bis Juni“), satz: das Ziel. art luecke: Auftrag aus dem Rundgang, satz: was fehlt. art sicht: Ziele, Statistiken mit Besitzer, Grund und zuletzt angesehen, Standfragen.",
    Type.Object({ art: S, thema: O(S), satz: O(S), an: O(S) }), (db, k, p) => statistikAnlass(db, k.agent, p as Anlass)],
  ["seneca_todo", "To-do anlegen, ändern, erledigt (mit satz: was du getan hast), verschieben, löschen, wiederherstellen; felder.bereich ist soziales, wachstum oder unternehmertum (fehlt er, ordnet Seneca nach dem Titel zu); vorschlagen (felder.titel): Antonio erwähnt im Gespräch etwas zu tun, dann leise fragen statt still anlegen.", Type.Object({ aktion: S, id: O(S), felder: O(Frei), gesehen_revision: O(Z), satz: O(S) }),
    (db, k, p) => {
      nurSeneca(k);
      if (p.aktion === "vorschlagen") return { ok: wertSetzen(db, "todo_vorschlag", JSON.stringify({ ...(p.felder as object), um: uhr.jetzt() }), "seneca", uhr.jetzt() + regelMs("todo_vorschlag_min")) > 0 };
      const r = todoSetzen(db, { ...(p as unknown as TodoAktion), geraet: "seneca" });
      if (r.ergebnis === "ueberholt") ereignis(db, { art: "todo.ueberholt", geraet: "seneca", schluessel: r.id, daten: { aktion: p.aktion, tag: (p.felder as { tag?: string } | undefined)?.tag ?? null } });
      return r;
    }],
  ["seneca_eintrag", "Statistik-Eintrag: Satz, Lesen, Laufen, Gewicht.", Type.Object({ art: S, werte: Frei, zeit: O(Z) }),
    (db, k, p) => {
      nurSeneca(k);
      return { eintrag_id: eintragSetzen(db, { art: String(p.art), werte: p.werte as object, zeit: (p.zeit as number | undefined) ?? uhr.jetzt(), quelle: "seneca" }) };
    }],
];

function geheim(api: OpenClawPluginApi, bereich: string): Record<string, string | undefined> {
  return ((api.pluginConfig ?? {})[bereich] ?? {}) as Record<string, string | undefined>;
}

function werkzeug(db: Register, [name, description, parameters, ausfuehren]: (typeof WERKZEUGE)[number]) {
  return (ctx: OpenClawPluginToolContext) => ({
    name, label: name, description, parameters,
    async execute(_id: string, p: unknown) {
      try {
        const ergebnis = await ausfuehren(db, { sitzung: ctx.sessionKey ?? "", agent: ctx.agentId ?? "" }, p as Record<string, unknown>);
        return { content: [{ type: "text" as const, text: typeof ergebnis === "string" ? ergebnis : JSON.stringify(ergebnis) }], details: ergebnis };
      } catch (fehler) {
        return { content: [{ type: "text" as const, text: `Abgelehnt: ${(fehler as Error).message}` }], details: { fehler: (fehler as Error).message } };
      }
    },
  });
}

function skillLeser(wer: string, arbeitsart: string): string | undefined {
  const pfad = join(process.env.OPENCLAW_STATE_DIR ?? join(homedir(), ".openclaw"), "agents", wer, "agent", "workshop-skills", arbeitsart.replaceAll("_", "-"), "SKILL.md");
  return existsSync(pfad) ? readFileSync(pfad, "utf8") : undefined;
}

const uebungen = (db: Register) => [...new Set(eintraegeSeit(db, 0).filter((e) => e.art === "satz").map((e) => String(JSON.parse(String(e.werte)).u)).reverse())];
const uhrSicht = (db: Register, t: number) => ({ ...uhrStand(db, t), tr: uebungen(db).slice(0, regelZahl("uhr_uebungen")).map((u) => uebung(db, t, u)?.uhr).filter(Boolean), l: buch(db, t)?.uhr ?? null });
const zifferblattSicht = (db: Register, t: number) => {
  type Termin = ReturnType<typeof termineAm>[number];
  const alle = termineAm(db, t), heute = alle.filter((x) => !x.ganztag), erledigt = heute.find((x) => /^Training: .* ✓$/.test(x.titel));
  const los = (x: Termin) => weg(db, x).los_ms, art = (x: Termin) => (/^Training: /.test(x.titel) ? (x.titel.endsWith(" ✓") ? "te" : "tr") : "t");
  const name = (x: Termin) => x.titel.replace(/^Training: /, "").replace(/ ✓$/, "");
  const bereich = (x: Termin) => (art(x) !== "t" ? "t" : ({ wachstum: "t", soziales: "s" } as Record<string, string>)[lebensbereich(`${x.titel} ${x.kalender ?? ""}`)] ?? "a");
  const kurz = (s: string) => (s.match(/\bmit\s+(\S+)/i)?.[1] ?? s.split(/\s+/)[0]).replace(/[^\p{L}\p{N}-]/gu, "").slice(0, regelZahl("uhr_kurz_zeichen"));
  const eintrag = (x: Termin) => [sekundenAusMs(x.start), sekundenAusMs(x.ende), name(x), art(x), los(x) === null ? null : sekundenAusMs(Number(los(x))), bereich(x), kurz(name(x))];
  const fertig = new Set(todos(db, "erledigt").map((x) => x.id)), seit = letzteUhrzeit(regelText("tag_grenze"), t);
  const getan = new Set(ereignisse(db, { art: "todo.erledigt", seit }).map((e) => e.schluessel).filter((s) => fertig.has(s))).size;
  return { n: uhrStand(db, t).n, tf: erledigt ? [sekundenAusMs(erledigt.start), sekundenAusMs(erledigt.ende)] : null, gz: alle.find((x) => x.ganztag && x.ende > t)?.titel ?? null,
    td: [getan, Math.min(todos(db, "offen").length, regelZahl("uhr_todos"))],
    tg: [...heute.filter((x) => x.ende > t), ...termineAm(db, naechsteUhrzeit(regelText("tag_grenze"), t)).filter((x) => !x.ganztag)].slice(0, regelZahl("uhr_termine") + 2).map(eintrag) };
};

export default {
  id: "seneca",
  name: "Seneca",
  description: "Register, Arbeitsdienst, Pforte und Ausgang für Seneca und sein Team.",
  register(api: OpenClawPluginApi) {
    const ordner = (api.pluginConfig?.ordner as string | undefined) ?? join(homedir(), ".openclaw", "seneca");
    const repo = dirname(api.rootDir ?? dirname(dirname(api.source)));
    process.env.SENECA_REGELN ??= join(repo, "regeln");
    process.env.SENECA_TEAM ??= join(repo, "team");
    const db = oeffne(join(ordner, "register.sqlite"));
    const kalender = geheim(api, "kalender");
    const senden = pushSender(geheim(api, "push"));
    const alle: typeof WERKZEUGE = [...WERKZEUGE, ["seneca_kalender", "Kalender lesen; Seneca: anlegen, verschieben, loeschen. Mit Teilnehmern fragt der Ausgang.",
      Type.Object({ aktion: S, uid: O(S), titel: O(S), start: O(Z), ende: O(Z), ort: O(S), teilnehmer: O(Type.Array(S)), trotzdem: O(Type.Boolean()) }),
      (db, k, p) => kalenderWerkzeug(db, kalender, k.agent, p as Parameters<typeof kalenderWerkzeug>[3], k.sitzung)]];
    for (const w of alle) api.registerTool(werkzeug(db, w), { name: w[0] });
    const befehl: Befehl = (argv, ms) => api.runtime.system.runCommandWithTimeout(argv, ms).then((r) => ({ code: r.code, stderr: r.stderr }));
    let reihe = "";
    const starte: Starter = async ({ werkzeuge, abos, ...p }) => {
      const r = JSON.stringify(abos) === reihe ? undefined : await befehl([regelText("openclaw_befehl"), "config", "set", "auth.order.anthropic", JSON.stringify(abos), "--strict-json"], regelMs("takt_job_haengt_s"));
      if (r && r.code !== 0) throw new Error(`Abo-Reihenfolge nicht gesetzt: ${r.stderr.slice(0, 200)}`);
      reihe = JSON.stringify(abos);
      return api.runtime.subagent.run({ ...p, toolsAlsoAllow: [...alle.map((w) => w[0]), ...werkzeuge], deliver: false });
    };
    const poste: Poster = async (sitzung, text, data, idempotencyKey) => {
      const generation = await api.runtime.system.captureSessionGeneration({ agentId: sitzung.split(":")[1], sessionKey: sitzung });
      return generation ? (await api.runtime.system.postSessionNotice({ generation, notice: { type: "auftrag", text, data }, idempotencyKey, systemEvent: text })).status : "ohne Gespräch";
    };
    const stupse = async (sessionKey: string, text: string, idempotencyKey: string) => (await api.session.workflow.steerActiveRun({ sessionKey, text, idempotencyKey })).steered;
    const knotenListe = async () => (await api.runtime.nodes.list({ connected: true })).nodes
      .map((k) => ({ name: k.displayName ?? k.nodeId, ollama: (k.invocableCommands ?? []).includes("ollama.chat") }));

    api.on("before_prompt_build", (event, ctx) => {
      const sitzung = ctx.sessionKey ?? "";
      merkeNachricht(sitzung, event.messages);
      const text = kontext(db, sitzung, skillLeser);
      return text ? { prependContext: text } : undefined;
    });
    api.on("agent_end", (event, ctx) => {
      type Nutzung = { input?: number; output?: number; cacheRead?: number; cacheWrite?: number; cost?: { total?: number } };
      const nutzung = event.messages.map((m) => (m as { usage?: Nutzung }).usage ?? {});
      const summe = (f: (u: Nutzung) => number | undefined) => nutzung.reduce((n, u) => n + (f(u) ?? 0), 0);
      const dollar = nutzung.some((u) => u.cost?.total !== undefined) ? summe((u) => u.cost?.total) : undefined;
      const tokens = { ein: summe((u) => (u.input ?? 0) + (u.cacheRead ?? 0) + (u.cacheWrite ?? 0)), aus: summe((u) => u.output), cent: dollar === undefined ? undefined : Math.round(dollar * 100) };
      agentEnde(db, ctx.sessionKey ?? "", `${event.error ?? ""}${JSON.stringify(event.messages.at(-1) ?? "")}`, tokens);
      unteragentEnde(db, ctx.sessionKey ?? "", tokens);
    });
    api.on("run_stopped", (event) => event.sessions.forEach((s) => laufGestoppt(db, s.sessionKey)));
    api.on("subagent_spawned", (event, ctx) => unteragentMerken(db, event.childSessionKey, { an: event.agentId, modus: event.mode, lauf: event.runId, modell: event.resolvedModel ?? null }, ctx.requesterSessionKey ?? ""));

    api.on("before_tool_call", (event, ctx) => pruefeAufruf(db, { werkzeug: event.toolName, params: event.params, sitzung: ctx.sessionKey ?? "", agent: ctx.agentId ?? "", aufrufId: event.toolCallId, ruhe: () => ruhe(db, uhr.jetzt()) }, nachrichtVon(ctx.sessionKey ?? "")));
    api.on("before_tool_call", (event, ctx) => dateiRecht({ werkzeug: event.toolName, params: event.params, agent: ctx.agentId ?? "" }));
    api.on("after_tool_call", (event, ctx) => {
      nachWerkzeug(db, event.toolCallId, event.error);
      werkzeugProtokoll(db, ctx.sessionKey ?? "", event.toolName, event.params, event.durationMs);
    });
    api.on("message_received", (event, ctx) => mitlesen(db, ctx.channelId, event));
    const route = (path: string, verarbeite: (roh: Buffer, kopf: IncomingHttpHeaders) => { status: number; inhalt?: object; kopf?: Record<string, string> }) =>
      api.registerHttpRoute({ path, auth: "plugin", match: "exact", handler: async (req, res) => {
        const teile: Buffer[] = [];
        let groesse = 0;
        for await (const t of req) {
          groesse += (t as Buffer).length;
          if (groesse > regelZahl("http_anfrage_max_kb") * 1024) break;
          teile.push(t as Buffer);
        }
        const a = groesse > regelZahl("http_anfrage_max_kb") * 1024 ? { status: 413 } : verarbeite(Buffer.concat(teile), req.headers);
        res.writeHead(a.status, { "content-type": "application/json", ...a.kopf });
        res.end(a.inhalt ? JSON.stringify(a.inhalt) : undefined);
        return true;
      } });
    route("/seneca/uhr/v1/abgleich", (roh, kopf) => uhrAbgleich(db, roh, kopf, (t) => uhrSicht(db, t)));
    const laufGeprueft = (kopf: IncomingHttpHeaders) => schluesselHash(String(kopf.authorization ?? "").replace(/^Bearer /, "")) === wert(db, `uhr:${LAUF}`)?.wert;
    route("/seneca/uhr/v1/zifferblatt", (_roh, kopf) => laufGeprueft(kopf) ? { status: 200, inhalt: zifferblattSicht(db, uhr.jetzt()) } : { status: 401, inhalt: { f: "unbekannt" } });
    route("/seneca/uhr/v1/sonde", (roh, kopf) => !laufGeprueft(kopf) ? { status: 401, inhalt: { f: "unbekannt" } } : !String(kopf["content-type"] ?? "").includes("json") ? { status: 200, inhalt: { n: roh.length } } : { status: 200, inhalt: { ok: wertSetzen(db, "uhr-sonde", JSON.stringify({ ...JSON.parse(wert(db, "uhr-sonde")?.wert ?? "{}"), [String(JSON.parse(roh.toString("utf8")).k)]: JSON.parse(roh.toString("utf8")) }), "uhr") } });
    route("/seneca/uhr/v1/koppeln", (roh) => uhrKoppeln(db, roh));
    route("/seneca/uhr/v1/abholen", (roh) => uhrAbholen(db, roh));
    route("/seneca/github", (roh, kopf) => ({ status: githubEingang(db, roh, kopf, geheim(api, "github").geheimnis) }));
    api.registerGatewayMethod("seneca.handeln", ({ params }) => handeln(db, params as Parameters<typeof handeln>[1]), { scope: "operator.write" });
    api.registerGatewayMethod("seneca.verstehen", ({ params }) => verstehen(db, String(params.satz ?? ""), uhr.jetzt()), { scope: "operator.read" });
    api.registerGatewayMethod("seneca.stand", ({ params }) => params.sicht === "datei" ? dateiVorschau(String(params.pfad ?? "")) : params.sicht === "statistik" ? { woche: woche(db, uhr.jetzt()), lauf: lauf(db, params.lauf as string | undefined), tag: tag(db, uhr.jetzt()), monat: monat(db, uhr.jetzt()), jahr: jahr(db, uhr.jetzt()), uebung: uebung(db, uhr.jetzt(), params.uebung as string | undefined), buch: buch(db, uhr.jetzt(), params.buch as string | undefined), kennzahlen: JSON.parse(wert(db, "statistik:kennzahlen")?.wert ?? "null") }
      : stand(db, { geraet: String(params.geraet), revision: params.revision as number | undefined }, uhr.jetzt()), { scope: "operator.read" });

    let gesendet = 0;
    let melde: ((r: number) => void) | undefined;
    const dienst = takt(db, [
      { job: "faellige_auftraege", ursache: "Aufträge mit fälligem Anlass wecken, nur hier", lauf: () => faelligeAuftraegeJob(db, starte) },
      { job: "kalender_wache", ursache: "Vorschläge verfallen still, zu spät fragt einmal", lauf: () => kalenderWacheJob(db), abstand: () => regelMs("weg_neu_min") },
      { job: "faellige_wirkungen", ursache: "Antworten wirken erst nach der Rückgängig-Frist", lauf: () => faelligeWirkungenJob(db) },
      { job: "laeufe_pruefen", ursache: "hängende Läufe erkennen statt still warten", lauf: () => laeufePruefenJob(db, stupse, befehl) },
      { job: "knoten", ursache: "Rechenknoten nur bei Bedarf an", lauf: () => knotenJob(db, geheim(api, "aws"), knotenListe), abstand: () => regelMs("knoten_pruefen_min") },
      { job: "zustellen", ursache: "Fragen nach Ruhe, Eile und Gerät zustellen", lauf: () => zustellenJob(db, senden, poste) },
      { job: "pflegen", ursache: "Sicherung, volle Platte, neue Mitarbeiter, Arbeitsdateien verfallen", lauf: () => pflegenJob(db, join(ordner, "sicherung"), befehl), abstand: () => regelMs("pflegen_h") },
      { job: "gespraeche", ursache: "Neu beginnen braucht das Admin-Recht des Servers, die Apps haben es nicht", lauf: () => gespraecheJob(db, befehl) },
      { job: "eingang", ursache: "Meeting, Datei und Sensor werden Anlass oder Vorschlag", lauf: () => eingangJob(db) },
      { job: "kalender", ursache: "Termine am Server statt am Mac", lauf: () => kalenderJob(db, kalender) },
      { job: "planen", ursache: "Los-Hinweis vor Terminen", lauf: () => planenJob(db), abstand: () => regelMs("planen_min") },
      { job: "garmin", ursache: "Garmin, Kennzahlen und Statistiken der Mitarbeiter ohne Modell", abstand: () => regelMs("garmin_abgleich_min"), lauf: async () => {
        const r = await api.runtime.system.runCommandWithTimeout([regelText("garmin_python"), regelText("garmin_skript"), "abgleich", join(ordner, "register.sqlite"), String(regelZahl("garmin_tage"))], regelMs("garmin_haengt_s"));
        if (r.code !== 0) throw new Error(`garmin.py: ${(r.stdout || r.stderr).slice(0, 300)}`);
        const a = JSON.parse(r.stdout) as { eintraege: { kennung: string; art: string; zeit: number; werte: object }[]; loeschen: string[]; kennzahlen: object }, k = JSON.stringify(a.kennzahlen);
        for (const e of a.eintraege) eintragSetzen(db, { ...e, quelle: "garmin", handlung_kennung: e.kennung });
        for (const id of a.loeschen) eintragAendern(db, id, { zustand: "geloescht" }, "garmin");
        if (wert(db, "statistik:kennzahlen")?.wert !== k) wertSetzen(db, "statistik:kennzahlen", k, "garmin");
      } },
      { job: "statistik_anlaesse", ursache: "Neue Datenart oder neues Ziel im Mandat wird Auftrag für eine Statistik", abstand: () => regelMs("garmin_abgleich_min"), lauf: () => anlaesseJob(db) },
      { job: "melden", ursache: "Apps holen den Stand nur bei neuer Revision", lauf: () => {
        const r = revision(db);
        if (r !== gesendet) melde?.(r);
        gesendet = r;
      } },
    ]);
    api.registerService({
      id: "seneca.takt",
      start(ctx) {
        melde = (r) => ctx.gatewayEvents?.emit("stand", { revision: r }, { scope: "operator.read" });
        nachNeustart(db);
        unklarePruefen(db);
        dienst.start();
      },
      stop() {
        dienst.stopp();
        db.close();
      },
    });
  },
};
