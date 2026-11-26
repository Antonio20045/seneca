import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { regelMs } from "../regeln.ts";

export type Register = DatabaseSync;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS auftrag (
  id TEXT PRIMARY KEY, wortlaut TEXT NOT NULL, wortlaut_quelle TEXT NOT NULL, titel TEXT NOT NULL,
  ziel TEXT NOT NULL, abnahme TEXT NOT NULL, abnahme_durch TEXT NOT NULL, pruefer_noetig INTEGER NOT NULL,
  verantwortlich TEXT NOT NULL, auftraggeber TEXT NOT NULL, quelle TEXT NOT NULL, eltern_id TEXT REFERENCES auftrag(id),
  zustand TEXT NOT NULL, letzter_stand TEXT NOT NULL DEFAULT '', naechster_schritt TEXT NOT NULL DEFAULT '',
  naechster_anlass INTEGER, anlass TEXT, wartet_auf TEXT, folge TEXT, schritt_nr INTEGER, schritt_gesamt INTEGER, frist INTEGER,
  ergebnis TEXT, verspaetung_gemeldet INTEGER NOT NULL DEFAULT 0, bereich TEXT NOT NULL, projekt TEXT,
  arbeitsart TEXT NOT NULL, stufe_fest TEXT, fable_ja INTEGER NOT NULL DEFAULT 0, schaetzung_min INTEGER,
  kostenrahmen_cent INTEGER NOT NULL, fehlversuche INTEGER NOT NULL DEFAULT 0, erstellt INTEGER NOT NULL, geaendert INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS auftrag_takt ON auftrag(zustand, naechster_anlass);
CREATE INDEX IF NOT EXISTS auftrag_wer ON auftrag(verantwortlich, zustand);
CREATE INDEX IF NOT EXISTS auftrag_eltern ON auftrag(eltern_id);
CREATE TABLE IF NOT EXISTS lauf (
  id TEXT PRIMARY KEY, auftrag_id TEXT NOT NULL REFERENCES auftrag(id), mitarbeiter TEXT NOT NULL, anlass TEXT NOT NULL,
  zustand TEXT NOT NULL, art TEXT NOT NULL, ort TEXT NOT NULL, sitzung TEXT NOT NULL, run_id TEXT,
  stufe TEXT NOT NULL, modell TEXT NOT NULL, abo TEXT, tokens_ein INTEGER NOT NULL DEFAULT 0, tokens_aus INTEGER NOT NULL DEFAULT 0,
  kosten_cent INTEGER NOT NULL DEFAULT 0, fortgeschrieben INTEGER NOT NULL DEFAULT 0, gestartet INTEGER NOT NULL,
  letzter_schritt_um INTEGER NOT NULL, beendet_um INTEGER, letzter_schritt TEXT, grund TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS lauf_aktiv ON lauf(auftrag_id) WHERE zustand IN ('startet','laeuft','haengt');
CREATE TABLE IF NOT EXISTS frage (
  id TEXT PRIMARY KEY, auftrag_id TEXT NOT NULL REFERENCES auftrag(id), von TEXT NOT NULL, text TEXT NOT NULL,
  was_passiert_ist TEXT NOT NULL, wenn_nichts TEXT NOT NULL, empfehlung TEXT NOT NULL, art TEXT NOT NULL,
  optionen TEXT NOT NULL, roh TEXT, wirkung_aussen TEXT NOT NULL DEFAULT 'keine', ausgang_schluessel TEXT, inhalt_hash TEXT,
  frist INTEGER, zustand TEXT NOT NULL, antwort TEXT, antwort_geraet TEXT, antwort_um INTEGER, antwort_kennung TEXT,
  wirkt_ab INTEGER, grund TEXT, ersetzt_durch TEXT, gestellt INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS frage_offen ON frage(auftrag_id) WHERE zustand = 'offen';
CREATE TABLE IF NOT EXISTS todo (
  id TEXT PRIMARY KEY, titel TEXT NOT NULL, kurz_uhr TEXT, bereich TEXT, tag TEXT, bis_wann INTEGER, dauer_min INTEGER,
  geschaetzt TEXT, wichtig INTEGER NOT NULL DEFAULT 0, notiz TEXT, anhang TEXT, oeffnet TEXT, wiederkehrend TEXT,
  selbst_abhaken TEXT, geplant_von INTEGER, geplant_bis INTEGER, verschoben_anzahl INTEGER NOT NULL DEFAULT 0,
  herkunft TEXT NOT NULL, zustand TEXT NOT NULL, erledigt_von TEXT, erledigt_ereignis INTEGER, revision INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS eintrag (
  id TEXT PRIMARY KEY, art TEXT NOT NULL, werte TEXT NOT NULL, zeit INTEGER NOT NULL, quelle TEXT NOT NULL,
  handlung_kennung TEXT UNIQUE, verweis TEXT, zustand TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS anzeige (
  id TEXT PRIMARY KEY, projekt TEXT NOT NULL, art TEXT NOT NULL, titel TEXT NOT NULL, werte TEXT NOT NULL,
  beantwortet TEXT, besitzer TEXT NOT NULL, stand INTEGER NOT NULL, zuletzt_angesehen INTEGER, zustand TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ereignis (
  nr INTEGER PRIMARY KEY AUTOINCREMENT, zeit INTEGER NOT NULL, art TEXT NOT NULL, wer TEXT, geraet TEXT,
  auftrag_id TEXT, frage_id TEXT, lauf_id TEXT, schluessel TEXT, daten TEXT, satz TEXT, beleg TEXT
);
CREATE INDEX IF NOT EXISTS ereignis_auftrag ON ereignis(auftrag_id, nr);
CREATE INDEX IF NOT EXISTS ereignis_wert ON ereignis(art, schluessel, nr DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ereignis_handlung ON ereignis(schluessel) WHERE art = 'handlung';
CREATE UNIQUE INDEX IF NOT EXISTS ereignis_ausgang ON ereignis(schluessel) WHERE art = 'ausgang.gestartet';
CREATE TRIGGER IF NOT EXISTS ereignis_kein_update BEFORE UPDATE ON ereignis BEGIN SELECT RAISE(ABORT, 'ereignis nur anhaengen'); END;
CREATE TRIGGER IF NOT EXISTS ereignis_kein_delete BEFORE DELETE ON ereignis BEGIN SELECT RAISE(ABORT, 'ereignis nur anhaengen'); END;
`;

export function oeffne(pfad: string): Register {
  mkdirSync(dirname(pfad), { recursive: true });
  const db = new DatabaseSync(pfad);
  db.exec(`PRAGMA journal_mode = WAL; PRAGMA busy_timeout = ${regelMs("register_warten_s")}; PRAGMA foreign_keys = ON;`);
  db.exec(SCHEMA);
  return db;
}
