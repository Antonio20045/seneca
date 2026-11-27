import { existsSync, readdirSync, rmdirSync, rmSync, statfsSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { aktiveLaeufe, auftraege, ereignisse, faelligeAuftraege, faelligeWirkungen, fragen, hole, naechsteFaelligkeit, offeneFrage, termineAm, todos, uhr, vorschlagDaten, wert, werte, type Zeile } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { sichern } from "../register/sichern.ts";
import { anzeigeEntfernen, auftragAnlegen, auftragSetzen, befund, ereignis, frageBeantworten, frageStellen, frageWirkt, vorschlagAnlegen, laufEnde, todoSetzen, uebergang, wertSetzen, type Wirkung } from "../register/schreiben.ts";
import { regelListe, regelMs, regelText, regelUhrzeitNach, regelZahl } from "../regeln.ts";
import { mandat, mitarbeiter } from "../team.ts";
import { naechsterTermin, starteLauf, zurueckMitWartezeit, type Starter } from "./lauf.ts";

async function starteOderBefund(db: Register, a: Zeile, starte: Starter): Promise<void> {
  try {
    await starteLauf(db, a, starte);
  } catch (fehler) {
    befund(db, { art: "fehler", auftrag_id: String(a.id), satz: `Start nicht möglich: ${(fehler as Error).message}` });
    zurueckMitWartezeit(db, hole(db, "auftrag", String(a.id)), "start_fehler");
  }
}

export async function faelligeAuftraegeJob(db: Register, starte: Starter): Promise<number | undefined> {
  const jetzt = uhr.jetzt();
  for (const a of faelligeAuftraege(db, jetzt)) {
    const id = String(a.id);
    if (a.zustand === "bereit") await starteOderBefund(db, a, starte);
    else if (a.zustand === "wartet") uebergang(db, "auftrag", id, "bereit", Number(a.naechster_anlass) <= jetzt ? "nachfassen" : "kind_haengt", { naechster_anlass: jetzt });
    else auftragSetzen(db, id, { naechster_anlass: regelUhrzeitNach("fenster", jetzt) }, "Abnahme rutscht ins nächste Fenster.");
  }
  return naechsteFaelligkeit(db);
}

function wirkung(db: Register, f: Zeile, a: Zeile, jetzt: number): void {
  const id = String(a.id);
  const antwort = String(f.antwort);
  if (antwort === "spaeter") return;
  if (f.art === "stufe_festlegen") wertSetzen(db, `kontakt:${f.ausgang_schluessel}`, antwort, "antonio");
  if (f.art === "vorschlag_lassen" && antwort === "ja") wertSetzen(db, `vorschlag:lassen:${f.ausgang_schluessel}`, "ja", "antonio");
  const termin = (vorschlagDaten(db, id).wirkung as Wirkung | undefined)?.termin;
  if (f.art === "vorschlag" && a.zustand === "vorgeschlagen") vorschlagWirkt(db, id, f, jetzt);
  if (f.art === "vorschlag" && antwort === "nein" && termin && f.antwort_geraet !== "frist") zweitesNein(db, id, termin);
  if (f.art === "vorschlag") return;
  if (f.von === "arbeitsdienst:kostenrahmen" && antwort === "weiter") auftragSetzen(db, id, { kostenrahmen_cent: Number(a.kostenrahmen_cent) * 2 }, "Rahmen erhöht.");
  const anhalten = antwort === "anhalten" && ["arbeitsdienst:kostenrahmen", "arbeitsdienst:haengt", "arbeitsdienst:start"].includes(String(f.von));
  if (f.von === "arbeitsdienst:haengt") {
    const lauf = aktiveLaeufe(db).find((l) => l.auftrag_id === id);
    if (lauf && anhalten) laufEnde(db, String(lauf.id), "abgebrochen", { grund: "angehalten" });
    if (lauf && !anhalten) wertSetzen(db, `anstupsen:${lauf.id}`, "offen", "arbeitsdienst");
  }
  const jetztA = hole(db, "auftrag", id);
  if (anhalten && ["bereit", "laeuft", "wartet"].includes(String(jetztA.zustand))) return uebergang(db, "auftrag", id, "geparkt", "anhalten");
  if (jetztA.zustand === "wartet") uebergang(db, "auftrag", id, "bereit", ["freigabe", "ausfuehrliches_ja"].includes(String(f.art)) ? "freigabe" : "antwort", { naechster_anlass: jetzt });
}

const OFT = ["sonntags", "montags", "dienstags", "mittwochs", "donnerstags", "freitags", "samstags"];
const art = (t: { titel: string; start: number }) => `${new Date(t.start).getDay()}:${t.titel}`;

function zweitesNein(db: Register, id: string, t: { titel: string; start: number }): void {
  const frueher = fragen(db, "beantwortet").filter((f) => f.art === "vorschlag" && f.antwort === "nein" && f.antwort_geraet !== "frist" && f.auftrag_id !== id)
    .map((f) => (vorschlagDaten(db, String(f.auftrag_id)).wirkung as Wirkung | undefined)?.termin).filter((x) => x && art(x) === art(t));
  if (frueher.length !== 1) return;
  frageStellen(db, {
    auftrag_id: id, von: regelText("dauerauftraege_von"), art: "vorschlag_lassen", ausgang_schluessel: art(t), text: `Gut. Soll ich ${OFT[new Date(t.start).getDay()]} nicht mehr fragen?`,
    was_passiert_ist: `Zweimal Nein zu ${t.titel}.`, wenn_nichts: "Seneca fragt weiter.", empfehlung: "Nicht mehr fragen, wenn der Tag dafür nie passt.",
    optionen: [{ wert: "ja", text: "Nicht mehr fragen", folge: "Diesen Vorschlag gibt es an diesem Wochentag nicht mehr." }, { wert: "nein", text: "Weiter fragen", folge: "Seneca fragt weiter." }],
  });
}

function vorschlagWirkt(db: Register, id: string, f: Zeile, jetzt: number): void {
  const w = vorschlagDaten(db, id).wirkung as Wirkung | undefined;
  if (f.antwort !== "ja") return uebergang(db, "auftrag", id, "verworfen", "vorschlag");
  const start = Number(wert(db, `vorschlag:zeit:${f.id}`)?.wert ?? w?.termin?.start);
  if (!w) return uebergang(db, "auftrag", id, "bereit", "vorschlag", { naechster_anlass: jetzt });
  if (w.todo) todoSetzen(db, { aktion: "anlegen", felder: w.todo, geraet: "seneca" });
  if (w.wert) wertSetzen(db, w.wert.schluessel, w.wert.wert, "antonio");
  if (w.parken && ["bereit", "laeuft", "wartet"].includes(String(hole(db, "auftrag", w.parken).zustand))) uebergang(db, "auftrag", w.parken, "geparkt", "vorschlag");
  for (const id of (w.fortsetzen ?? []).filter((x) => hole(db, "auftrag", x).zustand === "geparkt")) uebergang(db, "auftrag", id, "bereit", "vorschlag", { naechster_anlass: jetzt });
  if (w.anzeige_weg) anzeigeEntfernen(db, w.anzeige_weg, "antonio");
  if (w.termin) wertSetzen(db, `kalender:schreiben:${id}`, JSON.stringify({ aktion: "anlegen", uid: `${id}-seneca`, kalender: regelText("kalender_seneca"), ...w.termin, start, ende: start + w.termin.ende - w.termin.start }), "antonio");
  uebergang(db, "auftrag", id, "erledigt", "vorschlag");
}

export function kalenderWacheJob(db: Register): void {
  const jetzt = uhr.jetzt();
  for (const f of fragen(db, "offen").filter((x) => x.art === "vorschlag" && x.frist !== null && Number(x.frist) < jetzt)) frageBeantworten(db, { frage_id: String(f.id), antwort: "nein", geraet: "frist", kennung: `frist:${f.id}` });
  if (Number(wert(db, "praesenz:mac")?.gueltig_bis ?? 0) <= jetzt) return;
  for (const t of termineAm(db, jetzt)) {
    const weg = regelMs("eine_minute_min") * Number(wert(db, `wegzeit:${t.uid}`)?.wert ?? 0);
    const da = Number(wert(db, `ankunft:${t.uid}`)?.wert ?? t.start - regelMs("ankunft_puffer_min"));
    const name = t.titel.split(" mit ")[1];
    if (!weg || !name || jetzt < da - weg + regelMs("zu_spaet_nach_min") || jetzt > da || wert(db, `zuspaet:${t.uid}`)) continue;
    const neu = Math.ceil((jetzt + weg) / regelMs("zu_spaet_runden_min")) * regelMs("zu_spaet_runden_min");
    const um = new Date(neu).toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
    wertSetzen(db, `zuspaet:${t.uid}`, String(neu), "seneca");
    vorschlagAnlegen(db, {
      wortlaut: `${name} schreiben, dass Antonio um ${um} da ist. Danach ankunft:${t.uid} auf ${neu} setzen.`, wortlaut_quelle: `zuspaet:${t.uid}`, titel: `${name} schreiben: ${um} da`,
      ziel: `${name} weiß, dass Antonio um ${um} kommt`, abnahme: "Nachricht ist raus", abnahme_durch: "beleg", pruefer_noetig: false, verantwortlich: regelText("dauerauftraege_von"),
      auftraggeber: regelText("dauerauftraege_von"), bereich: "Privat", arbeitsart: "standard", herkunft: `zuspaet:${t.uid}`,
      frage: { text: `Du bist noch am Schreibtisch. ${name} schreiben, dass du ${um} da bist?`, was_passiert_ist: `${t.titel} beginnt bald, der Weg dauert länger als die Zeit bis dahin.`, empfehlung: "Senden", frist: da, ja: "Senden" },
    });
  }
}

export function faelligeWirkungenJob(db: Register): number | undefined {
  const jetzt = uhr.jetzt();
  for (const f of faelligeWirkungen(db, jetzt)) if (frageWirkt(db, String(f.id))) wirkung(db, f, hole(db, "auftrag", String(f.auftrag_id)), jetzt);
  return naechsteFaelligkeit(db);
}

function neuStarten(db: Register, l: Zeile, grund: string): void {
  const a = hole(db, "auftrag", String(l.auftrag_id));
  laufEnde(db, String(l.id), "abgebrochen", { grund });
  if (a.zustand === "laeuft") zurueckMitWartezeit(db, a, "wiederaufnahme");
}

type Stupser = (sitzung: string, text: string, kennung: string) => Promise<boolean>;

export async function laeufePruefenJob(db: Register, stupse: Stupser, befehl: Befehl): Promise<void> {
  const jetzt = uhr.jetzt();
  for (const l of aktiveLaeufe(db)) {
    const still = jetzt - Number(l.letzter_schritt_um), auftragId = String(l.auftrag_id), aus = String(hole(db, "auftrag", auftragId).zustand);
    if (aus === "verworfen" || aus === "geparkt") {
      laufEnde(db, String(l.id), "abgebrochen", { grund: `Auftrag ${aus}` });
      const r = await befehl([regelText("openclaw_befehl"), "gateway", "call", "chat.abort", "--json", "--params", JSON.stringify({ sessionKey: l.sitzung })], regelMs("takt_job_haengt_s"));
      if (r.code !== 0) ereignis(db, { art: "lauf.abbruch_offen", lauf_id: String(l.id), auftrag_id: auftragId, satz: r.stderr.slice(0, 200) });
      continue;
    }
    const stups = wert(db, `anstupsen:${l.id}`);
    if (stups?.wert === "offen") {
      const ok = await stupse(String(l.sitzung), "Wo hängst du? Sag in einem Satz, was fehlt.", `anstupsen-${l.id}`);
      if (ok) wertSetzen(db, `anstupsen:${l.id}`, "gestupst", "arbeitsdienst", jetzt + regelMs("haengt_leise_min"));
      else neuStarten(db, l, "angestupst, startet neu");
      continue;
    }
    if (stups?.wert === "gestupst" && Number(stups.gueltig_bis) <= jetzt && Number(l.letzter_schritt_um) < Number(stups.gueltig_bis) - regelMs("haengt_leise_min")) {
      neuStarten(db, l, "angestupst, keine Antwort, startet neu");
      continue;
    }
    if (l.zustand === "laeuft" && still > regelMs("haengt_leise_min")) uebergang(db, "lauf", String(l.id), "haengt", "kein Schritt");
    if (still > regelMs("haengt_frage_min") && !offeneFrage(db, auftragId) && !stups) {
      frageStellen(db, {
        auftrag_id: auftragId, von: "arbeitsdienst:haengt", art: "auswahl", text: `${l.mitarbeiter} hängt seit ${new Date(Number(l.letzter_schritt_um)).toTimeString().slice(0, 5)}. Was tun?`,
        was_passiert_ist: `Letzter Schritt: ${l.letzter_schritt ?? "keiner"}.`, wenn_nichts: "Der Lauf hängt weiter.", empfehlung: "Anstupsen",
        optionen: [{ wert: "anstupsen", text: "Anstupsen", folge: "Seneca fragt den Lauf, wo er hängt; ohne Antwort startet er neu." }, { wert: "anhalten", text: "Anhalten", folge: "Der Auftrag wird geparkt." }],
      });
    }
  }
}

export function nachNeustart(db: Register): void {
  for (const l of aktiveLaeufe(db)) {
    laufEnde(db, String(l.id), "abgebrochen", { grund: "Neustart des Gateways" });
    befund(db, { art: "fehler", auftrag_id: String(l.auftrag_id), lauf_id: String(l.id), satz: "Der Lauf endete durch einen Neustart des Gateways." });
    zurueckMitWartezeit(db, hole(db, "auftrag", String(l.auftrag_id)), "wiederaufnahme");
  }
}

const ZUSTAENDE = ["vorgeschlagen", "geparkt", "bereit", "laeuft", "wartet", "wartet_auf_abnahme", "erledigt", "verworfen"];

const DAUERAUFTRAEGE: Record<string, string> = {
  morgenbericht: "Morgenbericht: je Auftrag des Vortags Stand, Beleg und was fehlt.",
  rueckblick: "Rückblick am Abend: Erledigtes, Wiederholungen, Bestwerte, was gefehlt hat.",
  briefing: "Briefing: Tagesplan mit Energie und Terminen.",
};

function dauerauftrag(db: Register, wer: string, arbeitsart: string, wortlaut: string): void {
  if (auftraege(db, ZUSTAENDE.slice(0, 6)).some((a) => a.quelle === "dauerauftrag" && a.verantwortlich === wer && a.arbeitsart === arbeitsart)) return;
  auftragAnlegen(db, {
    art: "dauerauftrag", wortlaut, wortlaut_quelle: "mandat", titel: wortlaut.split(":")[0], ziel: wortlaut, abnahme: "Fortschreibung mit Beleg", abnahme_durch: "beleg",
    pruefer_noetig: false, verantwortlich: wer, auftraggeber: wer, quelle: "dauerauftrag", bereich: mandat(wer).bereich[0], arbeitsart,
    naechster_anlass: naechsterTermin({ arbeitsart, verantwortlich: wer }, uhr.jetzt()),
  });
}

export type Befehl = (argv: string[], ms: number) => Promise<{ code: number | null; stderr: string }>;

function arbeitVerfallen(db: Register): void {
  const ablage = regelText("ablage_pfad");
  const wurzel = join(ablage, "_arbeit");
  if (!existsSync(wurzel)) return;
  const grenze = uhr.jetzt() - regelMs("arbeitsdateien_tage");
  const eintraege = readdirSync(wurzel, { recursive: true, withFileTypes: true }).map((d) => ({ pfad: join(d.parentPath, d.name), datei: d.isFile() }));
  const alt = eintraege.filter((e) => e.datei && statSync(e.pfad).mtimeMs < grenze).map((e) => relative(ablage, e.pfad));
  if (!alt.length) return;
  const verweise = [...auftraege(db, ZUSTAENDE).map((a) => a.ergebnis), ...ereignisse(db, {}).map((e) => e.beleg), ...["offen", "erledigt"].flatMap((z) => todos(db, z).map((t) => t.anhang))].join("\n");
  const weg = alt.filter((rel) => !verweise.includes(rel));
  for (const rel of weg) rmSync(join(ablage, rel));
  for (const e of eintraege.filter((x) => !x.datei && dirname(x.pfad) !== wurzel).reverse()) if (!readdirSync(e.pfad).length) rmdirSync(e.pfad);
  if (weg.length) ereignis(db, { art: "ablage.verfallen", daten: { anzahl: weg.length, beispiele: weg.slice(0, 10) } });
}

async function tagesSicherung(db: Register, register: string, befehl: Befehl): Promise<void> {
  const jetzt = uhr.jetzt();
  const passwort = regelText("sicherung_passwort");
  if (!existsSync(passwort) || Number(wert(db, "sicherung:tag")?.gueltig_bis ?? 0) > jetzt) return;
  const zustand = join(dirname(register), "openclaw-zustand");
  const ablage = regelText("ablage_pfad");
  const restic = ["restic", "-r", regelText("sicherung_ziel"), "--password-file", passwort];
  rmSync(zustand, { recursive: true, force: true });
  for (const schritt of [
    [regelText("openclaw_befehl"), "backup", "sqlite", "create", "--global", "--repository", zustand],
    [...restic, "backup", "--tag", "seneca", "--exclude", join(ablage, "_sicherung"), "--exclude", join(ablage, ".stversions"), register, zustand, ablage, ...regelListe("sicherung_quellen")],
    [...restic, "forget", "--tag", "seneca", "--keep-daily", regelText("sicherung_tage"), "--keep-monthly", regelText("sicherung_monate"), "--prune"],
  ]) {
    const r = await befehl(schritt, regelMs("sicherung_max_min"));
    if (r.code !== 0) throw new Error(`Sicherung: ${schritt.slice(0, 4).join(" ")} endet mit ${r.code}: ${r.stderr.slice(0, 300)}`);
  }
  rmSync(zustand, { recursive: true, force: true });
  wertSetzen(db, "sicherung:tag", new Date(jetzt).toISOString(), "arbeitsdienst", jetzt + regelMs("sicherung_abstand_h"));
}

export async function gespraecheJob(db: Register, befehl: Befehl): Promise<void> {
  for (const [schluessel, key] of [...werte(db, "gespraech:neu:")].filter(([, k]) => k)) {
    const r = await befehl([regelText("openclaw_befehl"), "gateway", "call", "sessions.reset", "--json", "--params", JSON.stringify({ key, reason: "new" })], regelMs("takt_job_haengt_s"));
    wertSetzen(db, schluessel, "", "arbeitsdienst");
    wertSetzen(db, "hinweis:gespraech", r.code === 0 ? "" : `Das Gespräch ließ sich nicht neu beginnen: ${r.stderr.slice(0, 200)}`, "arbeitsdienst");
  }
}

export async function pflegenJob(db: Register, sicherungsOrdner: string, befehl?: Befehl): Promise<void> {
  const [, tag] = sichern(db, sicherungsOrdner);
  arbeitVerfallen(db);
  const frei = statfsSync(sicherungsOrdner);
  if (frei.bavail * frei.bsize < regelZahl("platte_frei_min_mb") * 1e6) befund(db, { art: "risiko", satz: "Die Platte des Servers ist fast voll." });
  for (const wer of mitarbeiter()) {
    if (mandat(wer).rundgang.length) dauerauftrag(db, wer, "rundgang", "Rundgang: Signale des Mandats lesen, eigene Aufträge mit Nutzen anlegen, Anzeigen aufräumen.");
  }
  for (const [art, wortlaut] of Object.entries(DAUERAUFTRAEGE)) dauerauftrag(db, regelText("dauerauftraege_von"), art, wortlaut);
  if (befehl) await tagesSicherung(db, tag, befehl);
}
