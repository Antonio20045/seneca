import { kalenderTag, termineAm, uhr, wert, werte } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { ereignis, wertSetzen } from "../register/schreiben.ts";
import { kalenderSpanne, regelMs, regelText, regelZahl } from "../regeln.ts";

type Zugang = { benutzer?: string; passwort?: string };
type Termin = { uid: string; start: number; ende: number; titel: string; ort?: string; teilnehmer: string[]; namen: string[]; notiz?: string; kalender?: string; ganztag: boolean };
type Ort = { href: string; etag: string; kalender: string; ics: string };
type Kalender = { url: string; name: string };

const orte = new Map<string, Ort>();
let kalender: Kalender[] = [];
let zuletzt = 0;

const ics = (t: number) => new Date(t).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");

function zeit(wert: string): number {
  const [, j, mo, d, h = "00", mi = "00", s = "00", z] = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?(Z)?/.exec(wert) ?? [];
  return z ? Date.UTC(+j, +mo - 1, +d, +h, +mi, +s) : new Date(+j, +mo - 1, +d, +h, +mi, +s).getTime();
}

function termineAus(text: string): Termin[] {
  const zeilen = text.replace(/\r?\n[ \t]/g, "").split(/\r?\n/);
  const termine: Termin[] = [];
  let t: Partial<Termin> | undefined;
  for (const z of zeilen) {
    const [kopf, ...rest] = z.split(":");
    const [name] = kopf.split(";");
    const w = rest.join(":");
    if (z === "BEGIN:VEVENT") t = { teilnehmer: [], namen: [], ganztag: false };
    else if (z === "END:VEVENT" && t?.uid && t.start) termine.push({ ende: t.start, ...t } as Termin);
    else if (t && name === "UID") t.uid = w;
    else if (t && name === "SUMMARY") t.titel = w;
    else if (t && name === "LOCATION") t.ort = w;
    else if (t && name === "DESCRIPTION") t.notiz = w.replace(/\\n/g, "\n");
    else if (t && name === "ATTENDEE") {
      const mail = w.replace(/^mailto:/i, "");
      t.teilnehmer?.push(mail);
      t.namen?.push(/;CN="?([^;:"]+)/i.exec(kopf)?.[1] ?? mail.split("@")[0].replace(/^./, (c) => c.toUpperCase()));
    }
    else if (t && (name === "DTSTART" || name === "DTEND")) {
      t[name === "DTSTART" ? "start" : "ende"] = zeit(w);
      t.ganztag = kopf.includes("VALUE=DATE");
    }
  }
  return termine;
}

async function dav(z: Zugang, url: string, methode: string, body?: string, kopf: Record<string, string> = {}): Promise<{ status: number; text: string; etag: string }> {
  const r = await fetch(url, {
    method: methode, body, signal: AbortSignal.timeout(regelMs("kalender_zeitlimit_s")),
    headers: { authorization: `Basic ${Buffer.from(`${z.benutzer}:${z.passwort}`).toString("base64")}`, "content-type": "application/xml; charset=utf-8", ...kopf },
  });
  const text = await r.text();
  if (r.status >= 400) throw new Error(`CalDAV ${methode} ${r.status}`);
  return { status: r.status, text, etag: r.headers.get("etag") ?? "" };
}

const href = (text: string, element: string) => new RegExp(`<[^>]*${element}[^>]*>\\s*<[^>]*href[^>]*>([^<]+)<`, "i").exec(text)?.[1];
const absolut = (basis: string, pfad: string) => new URL(pfad, basis).toString();

async function finde(z: Zugang): Promise<Kalender[]> {
  if (kalender.length) return kalender;
  const basis = regelText("caldav_url");
  const p = '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:current-user-principal/><c:calendar-home-set/></d:prop></d:propfind>';
  const prinzipal = absolut(basis, href((await dav(z, basis, "PROPFIND", p, { depth: "0" })).text, "current-user-principal") ?? "/");
  const heim = absolut(prinzipal, href((await dav(z, prinzipal, "PROPFIND", p, { depth: "0" })).text, "calendar-home-set") ?? "/");
  const liste = (await dav(z, heim, "PROPFIND", '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:resourcetype/><d:displayname/><c:supported-calendar-component-set/></d:prop></d:propfind>', { depth: "1" })).text;
  kalender = [...liste.matchAll(/<[^>]*response[^>]*>([\s\S]*?)<\/[^>]*response>/gi)].filter((m) => /<(?:[\w-]+:)?calendar[\s/>]/i.test(m[1]) && (!/<[^>]*comp\s+name=/i.test(m[1]) || /name=["']VEVENT["']/i.test(m[1])))
    .map((m) => ({ url: absolut(heim, /<[^>]*href[^>]*>([^<]+)</i.exec(m[1])?.[1] ?? ""), name: /<[^>]*displayname[^>]*>([^<]*)</i.exec(m[1])?.[1] ?? "Kalender" }));
  return kalender;
}

export async function kalenderAbgleich(db: Register, z: Zugang): Promise<void> {
  if (!z.benutzer || !z.passwort) return;
  const { von } = kalenderSpanne(uhr.jetzt());
  const bis = uhr.jetzt() + regelMs("kalender_vorschau_tage");
  const abfrage = `<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:getetag/><c:calendar-data><c:expand start="${ics(von)}" end="${ics(bis)}"/></c:calendar-data></d:prop>
    <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"><c:time-range start="${ics(von)}" end="${ics(bis)}"/></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>`;
  const tage = new Map<string, Termin[]>();
  for (const { url: k, name } of await finde(z)) {
    const text = (await dav(z, k, "REPORT", abfrage, { depth: "1" })).text;
    for (const m of text.matchAll(/<[^>]*response[^>]*>([\s\S]*?)<\/[^>]*response>/gi)) {
      const daten = /calendar-data[^>]*>([\s\S]*?)<\//i.exec(m[1])?.[1]?.replace(/&#13;/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&") ?? "";
      for (const t of termineAus(daten).map((x) => ({ ...x, kalender: name }))) {
        orte.set(t.uid, { href: absolut(k, /<[^>]*href[^>]*>([^<]+)</i.exec(m[1])?.[1] ?? ""), etag: /getetag[^>]*>([^<]+)</i.exec(m[1])?.[1] ?? "", kalender: k, ics: daten });
        tage.set(kalenderTag(t.start), [...(tage.get(kalenderTag(t.start)) ?? []), t]);
      }
    }
  }
  for (const tag = new Date(von); tag.getTime() < bis; tag.setDate(tag.getDate() + 1)) {
    const t = tag.getTime();
    const liste = (tage.get(kalenderTag(t)) ?? []).sort((a, b) => a.start - b.start).map((x) => ({ ...x, titel: x.titel?.slice(0, regelZahl("kalender_titel_zeichen")) }));
    const neu = JSON.stringify(liste);
    if (wert(db, kalenderTag(t))?.wert !== neu) wertSetzen(db, kalenderTag(t), neu, "kalender");
  }
  const namen = JSON.stringify(kalender.map((k) => k.name));
  if (wert(db, "kalender:liste")?.wert !== namen) wertSetzen(db, "kalender:liste", namen, "kalender");
}

export async function kalenderJob(db: Register, z: Zugang): Promise<void> {
  if (!z.benutzer || !z.passwort) return;
  const offen = [...werte(db, "kalender:schreiben:")].filter(([, v]) => v);
  for (const [schluessel, v] of offen) {
    const p = JSON.parse(v);
    await schreiben(db, z, { ...p, trotzdem: true }).catch((f: Error) => wertSetzen(db, "hinweis:kalender", `„${p.titel ?? "Termin"}“ ging nicht in den Kalender: ${f.message}`, "kalender"));
    wertSetzen(db, schluessel, "", "kalender");
  }
  if (!offen.length && uhr.jetzt() - zuletzt < regelMs("kalender_abgleich_min")) return;
  zuletzt = uhr.jetzt();
  await kalenderAbgleich(db, z);
}

type Eingabe = { aktion: string; uid?: string; titel?: string; start?: number; ende?: number; ort?: string; teilnehmer?: string[]; trotzdem?: boolean; kalender?: string };

const TAG = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
const MONAT = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sep", "Okt", "Nov", "Dez"];

function wann(t: number): string {
  const d = new Date(t);
  return `${TAG[d.getDay()]} ${d.getDate()}. ${MONAT[d.getMonth()]} · ${d.getHours()}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export async function kalenderWerkzeug(db: Register, z: Zugang, agent: string, p: Eingabe, sitzung = ""): Promise<object> {
  if (!z.benutzer || !z.passwort) throw new Error("Kalender ist noch nicht verbunden (App-Passwort fehlt).");
  if (p.aktion === "lesen") return { termine: termineAm(db, p.start ?? uhr.jetzt()) };
  if (agent !== regelText("dauerauftraege_von")) throw new Error("Nur Seneca schreibt in den Kalender.");
  const r = await schreiben(db, z, { ...p, kalender: p.kalender ?? regelText("kalender_seneca") }) as { ok?: boolean; uid?: string; titel?: string; vorher?: Termin };
  if (r.ok && p.aktion !== "loeschen") ereignis(db, { art: "quittung", schluessel: sitzung, daten: { teil: "Kalender", ergebnis: `${r.titel} · ${wann(Number(p.start))}`,
    zurueck: r.vorher ? { uid: r.uid, start: r.vorher.start, ende: r.vorher.ende } : null } });
  return r;
}

async function schreiben(db: Register, z: Zugang, p: Eingabe): Promise<object> {
  const alt = p.uid ? orte.get(p.uid) : undefined;
  if (p.aktion === "loeschen") {
    if (!alt) throw new Error("Termin unbekannt.");
    await dav(z, alt.href, "DELETE", undefined, { "if-match": alt.etag });
    await kalenderAbgleich(db, z);
    return { ok: true };
  }
  if (p.aktion === "verschieben" && !alt) throw new Error("Termin unbekannt.");
  const start = Number(p.start);
  const ende = Number(p.ende ?? start + regelMs("termin_standard_min"));
  const konflikte = termineAm(db, start).filter((t) => t.uid !== p.uid && !t.ganztag && t.start < ende && t.ende > start).map((t) => t.titel);
  if (konflikte.length && !p.trotzdem) return { ok: false, konflikte };
  const uid = p.uid ?? `${uhr.jetzt()}-seneca`;
  const liste = await finde(z);
  const ziel = alt?.href ?? `${(liste.find((k) => k.name === p.kalender) ?? liste.find((k) => k.name === regelText("kalender_standard")) ?? liste[0]).url}${uid}.ics`;
  const kopf = `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Seneca//DE\r\nBEGIN:VEVENT\r\nUID:${uid}\r\nDTSTAMP:${ics(uhr.jetzt())}\r\nDTSTART:${ics(start)}\r\nDTEND:${ics(ende)}\r\n`;
  const altTermin = alt ? termineAus(alt.ics).find((t) => t.uid === uid) : undefined;
  if (altTermin?.teilnehmer.length && !p.teilnehmer?.length) throw new Error("Der Termin hat Teilnehmer: gib sie als teilnehmer mit, damit der Ausgang fragen kann.");
  const titel = p.titel ?? altTermin?.titel ?? "Termin";
  const leute = (p.teilnehmer ?? altTermin?.teilnehmer ?? []).map((m) => `ATTENDEE:mailto:${m}\r\n`).join("");
  const text = `${kopf}SUMMARY:${titel}\r\n${p.ort ?? altTermin?.ort ? `LOCATION:${p.ort ?? altTermin?.ort}\r\n` : ""}${leute}END:VEVENT\r\nEND:VCALENDAR\r\n`;
  await dav(z, ziel, "PUT", text, { "content-type": "text/calendar; charset=utf-8", ...(alt ? { "if-match": alt.etag } : { "if-none-match": "*" }) });
  await kalenderAbgleich(db, z);
  return { ok: true, uid, konflikte, titel, vorher: altTermin };
}
