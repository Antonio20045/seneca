# Architektur

Stand und Grenzen der Server-Seite. Ausführlich begründet im Umsetzungsplan (Abschnitte 1 bis 4).

## Grundsätze

- **Eine Wahrheit:** Alles, was Seneca weiß, steht im Register (`~/.openclaw/seneca/register.sqlite`, SQLite über `node:sqlite`, WAL).
- **Ein Schreiber:** Nur `register/schreiben.ts` schreibt. Zustände ändern sich nur über `uebergang()`, erlaubt ist nur, was in `register/uebergaenge.ts` als Daten steht.
- **Jede Änderung ist ein Ereignis.** Die Revision ist die höchste Ereignis-Nummer. Ereignisse werden nur angehängt (zwei Trigger verbieten Ändern und Löschen).
- **Ein Takt:** Hintergrundarbeit läuft nur im Takt (`arbeitsdienst/takt.ts`). Jeder Job nennt seine Ursache.
- **Ein Weg nach außen:** nur der Ausgang (`ausgang/ausgang.ts`) über den Hook `before_tool_call`.
- **Zahlen nur in `regeln`.** Gelesen nur von `regeln.ts`, frisch bei jedem Aufruf.

## Module und Grenzen

| Modul | Aufgabe | Darf kennen |
|---|---|---|
| `index.ts` | meldet Werkzeuge, Hooks, Methoden, Routen, den Dienst und die Takt-Jobs an; reicht nur `uhrStand` an den Uhr-Zugang weiter | alle |
| `regeln.ts`, `team.ts` | reine Leser von `regeln` und `team/<name>/` | nichts |
| `register/` | Schema, Schreiben, Lesen, Sichern | `regeln.ts` |
| `arbeitsdienst/` | Takt, Wecken, Kontext, Fortschreiben, Stufe, Abo, Kosten | `register`, `regeln.ts`, `team.ts` |
| `pforte/` | Stand, „braucht dich“, Zustellung je Gerät | `register`, `regeln.ts`, `team.ts` |
| `ausgang/` | Kontaktstufen, Freigabe, höchstens einmal nach außen | `register`, `regeln.ts`, `team.ts` |
| `lernen/` | Korrektur an genau einen Ort, Wiederholungen | `register`, `regeln.ts`, `team.ts` |
| `zugang/` | `seneca.handeln`, Uhr-Zugang | `register`, `regeln.ts`, `team.ts` |
| `quellen/` | GitHub, WhatsApp mitlesen, Eingänge | `register`, `regeln.ts`, `team.ts` |

Geschwister kennen sich nicht. Sie arbeiten über das Register zusammen: ein Modul schreibt, das andere liest im Takt.

## Apps

| Ordner | Inhalt | Darf kennen |
|---|---|---|
| `apps/SenecaKern/Sources/SenecaKern` | Code, den Mac und iPhone teilen: Chat, Verbindung, Fachlogik. Ein Exemplar, beide Xcode-Projekte übersetzen den Ordner mit. Wo Mac und iPhone verschieden sind, steht `#if os(iOS)` | nichts außerhalb |
| `apps/Mac/MacKern` | Fachlogik nur für den Mac (Meeting, Menüleiste, Tageslauf, Übersicht) | `apps/SenecaKern` |
| `apps/Mac/SenecaNativ`, `SenecaWidget`, `SenecaTeilen` | Oberfläche, Widget und Teilen-Erweiterung der Mac-App | `apps/SenecaKern`, `apps/Mac/MacKern` |
| `apps/iPhone/*` | Oberfläche, Widget, Teilen-Erweiterung der iPhone-App | `apps/SenecaKern` |
| `apps/SenecaKern/Sources/SenecaKern/Widget` | Ein Widget für iPhone (Home, Sperre) und Mac (Mitteilungszentrale): Lage, Zustände, Aussehen. Beide Widget-Erweiterungen übersetzen diese Dateien; die Apps schreiben `WidgetLage` in ihre App-Group | nichts außerhalb |
| `apps/SenecaKern/Sources/SenecaKern/Teilen` | „An Seneca teilen“ für iPhone und Mac: Blatt (Tafel G-iPhone-Teilen), Eintrag in der App-Group, Lesen. Ohne Frage wird es `eingang.datei`, mit Frage eine Nachricht an Seneca oder den gewählten Mitarbeiter. Ersetzt den Mac-Sortierer | nichts außerhalb |

Die Apps sprechen mit dem Plugin nur über das Gateway. Ihre Zeilen dürfen nicht wachsen (Budget in `pruefen.sh`, Prüfung P1).

## Zustandsmaschinen

Auftrag: vorgeschlagen · geparkt · bereit · laeuft · wartet · wartet_auf_abnahme · erledigt · verworfen.
Lauf: startet · laeuft · haengt · beendet · abgebrochen. Frage: offen · beantwortet · ersetzt · zurueckgezogen · abgelaufen.
To-do: offen · erledigt · geloescht. Die erlaubten Übergänge, Pflichtfelder und Nebenwirkungen stehen nur in `register/uebergaenge.ts`.

## Funktion → Ort

| Nr | Funktion | Ort |
|---|---|---|
| 1 | Auftrag anlegen (Wortlaut unverändert, Ziel, Abnahme) | `register/schreiben.ts` · `auftragAnlegen`, über Werkzeug `seneca_auftrag` |
| 2 | Unterauftrag mit Elternverweis | `register/schreiben.ts` · `auftragAnlegen`, Feld `eltern_id` |
| 3 | Zustand ändern (Auftrag, Lauf, Frage, To-do) | `register/schreiben.ts` · `uebergang()`, Daten in `register/uebergaenge.ts` |
| 4 | „wartet“ nur mit Folge und Nachfasszeit | `register/uebergaenge.ts` (Pflichtfelder) |
| 5 | Handlung idempotent | `register/schreiben.ts` · `handlung()` |
| 6 | Rückgängig in der Frist | `register/schreiben.ts` · `frageZuruecknehmen`; gewirkt wird erst nach `frage.wirkt` |
| 7 | Befund festhalten | `register/schreiben.ts` · `befund` |
| 8 | To-do anlegen, abhaken, verschieben („Erledigt gewinnt“) | `register/schreiben.ts` · `todoSetzen` |
| 9 | Statistik-Eintrag | `register/schreiben.ts` · `eintragSetzen` |
| 10 | Ziele, Serien, Bestwerte | `pforte/stand.ts` |
| 11 | Anzeige setzen (höchstens 4 je Projekt) | `register/schreiben.ts` · `anzeigeSetzen` |
| 12, 13 | Fakt, Profil, Kontaktstufe, „ruht“ (neuester Wert gilt) | `register/schreiben.ts` · `wertSetzen` |
| 14 | Register sichern | `register/sichern.ts`, nur vom Job `pflegen` |
| 14a | Tägliche Sicherung (Register, OpenClaw-Zustand mit Skill-Werkstatt, `openclaw.json`, Skills, die Ablage ohne `_sicherung`) mit restic in `~/Ablage/_sicherung` | `arbeitsdienst/jobs.ts` · `tagesSicherung`, nur vom Job `pflegen` |
| 15, 16 | Wecken; „ruht“ prüfen (einzige Prüfstelle) | `arbeitsdienst/lauf.ts` · `starteLauf()` |
| 17 | Hintergrundjobs mit wachsendem Abstand bei Fehlern | `arbeitsdienst/takt.ts` |
| 18 | Rundgang, Morgenbericht, Rückblick, Briefing | Daueraufträge, geweckt von `faellige_auftraege` |
| 18a | Rundgang: Feststeckendes, Team, Eingänge, Signale und Ziele im Kontext; Anzeigen grau; Regel-Vorschläge aus Mustern (dreimal Ja zum selben Kontakt, dreimal vertagt, Anzeige ungesehen); Folgezug (`seneca_auftrag` art `nachfassen`) und eigener Auftrag (art `eigener`) nur im Rundgang | `arbeitsdienst/rundgang.ts` |
| 19 | Kontext für den Lauf | `arbeitsdienst/lauf.ts` · Hook `before_prompt_build` |
| 20 | Lauf-Ende: Fortschreibung erzwingen | `arbeitsdienst/lauf.ts` · Hooks `agent_end` (ohne Fortschreibung: Befund `ohne_stand`) und `run_stopped` (Stopp von außen: Lauf abgebrochen, Auftrag geparkt) · Job `laeufe_pruefen` bricht Läufe verworfener oder geparkter Aufträge über `chat.abort` ab |
| 21 | Mandat lesen, frisch bei jedem Lauf | `team.ts` |
| 22, 27 | Modellstufe wählen, Rückfall lokal → Haiku; lokale Textarbeit über das native Werkzeug `node_inference` im Lauf, wenn ein Knoten `ollama.chat` anbietet | `arbeitsdienst/modell.ts`, `arbeitsdienst/lauf.ts` |
| 23 | Abo-Reihenfolge | `arbeitsdienst/abo.ts` |
| 24, 25 | Kosten zählen, Kostenrahmen prüfen | `arbeitsdienst/kosten.ts` |
| 26 | Läufe prüfen, „hängt“, Anstupsen als Folgezug (`steerActiveRun`) | `arbeitsdienst/jobs.ts` · Job `laeufe_pruefen` |
| 76 | Knoten erkennen, Rechenknoten bei Bedarf starten und nach Leerlauf stoppen (AWS) | `arbeitsdienst/rechenknoten.ts` · Job `knoten` |
| 28 | Frage stellen (höchstens eine offen je Auftrag) | `register/schreiben.ts` · `frageStellen`, über Werkzeug `seneca_frage` |
| 29 | Frage beantworten (erste Antwort gilt) | `register/schreiben.ts` · `frageBeantworten` |
| 30 | Frage ersetzt oder zurückgezogen | `register/uebergaenge.ts` (Nebenwirkungen) |
| 31, 35, 37, 52 | „Braucht dich“ (höchstens 3), Stand mit Revision, Regeln an die Geräte, Version | `pforte/stand.ts` |
| 32, 33 | Ruhe, Abstand der Mitteilungen, Zustellung je Gerät; die Uhr gilt bis `uhr_verbunden_min` nach ihrem letzten Abgleich als verbunden (`zugang/uhr.ts`) und bekommt Ja/Nein-Fragen und Vorschläge | `pforte/zustellen.ts` |
| 39a | Anruf an Antonio, wenn ein Auftrag feststeckt (nie nachts, Schlaf, Training) | entschieden nur in `pforte/zustellen.ts` (Auftrag `anruf_antonio`); beim Wählen prüft `ausgang/ausgang.ts` Nummer, Ruhe und „genau einmal“ |
| 34 | Push senden (APNs, Schlüssel nur aus der Plugin-Konfiguration, ohne Schlüssel still aus) | `pforte/push.ts`, aufgerufen nur aus `pforte/zustellen.ts` |
| 38, 39, 41, 42 | Nach außen nur nach Stufe, 5 s, höchstens einmal | `ausgang/ausgang.ts` · Hook `before_tool_call` |
| 40 | Stufe je Empfänger | `ausgang/kontakte.ts` |
| – | Unteragent (`sessions_spawn`) und Nachricht an Kollegen (`sessions_send`): nie von oder an einen Ruhenden, fremde Kollegen nur laut `unterauftrag_an` (Regel `unteragent_werkzeuge`); jeder Unteragent-Lauf steht als Ereignis `unteragent` und `unteragent.ende` im Register. Anruf-Auftrag (`anruf_antonio`): nur Antonios Nummer, nie in Nacht, Schlaf oder Training, genau einmal | `ausgang/ausgang.ts` · Hooks `before_tool_call`, `subagent_spawned`, `agent_end` |
| – | Nichts live ohne Antonios ausführliches Ja (Mandatsfeld `live_nur_mit_ja`, Regel `live_muster`); Außen-Werkzeuge auch als Shell-Aufruf, dazu gesperrt: Löschen, Force-Push, Schlüssel und `.env` (`<werkzeug>~<muster>` in `aussen_werkzeuge`, `aussen_gesperrt`); kein Gateway-Neustart außer im Bauablauf mit Ja (Regel `gateway_muster`) | `ausgang/ausgang.ts` · Hook `before_tool_call` |
| 43, 46, 47 | Korrektur einordnen (aus dem Gespräch oder Antonios Satz beim Nachbessern), die 5 ähnlichsten früheren, Skill höchstens eine Zeile mehr, Sperre als Auftrag, Wiederholung → Auftrag an den Besitzer; Zählung `wiederholungenSeit` in `register/lesen.ts`; Zeile „Gelernt: …“ im Stand (`gelernt`) | `lernen/lernen.ts` |
| 47a | Zurücknehmen (einmal; Skill und gebaute Sperre über einen Umkehr-Auftrag) | `register/schreiben.ts` · `korrekturZuruecknehmen`, Handlung `lernen.zuruecknehmen` |
| 44 | Skill ändern | Skill-Werkstatt von OpenClaw (`skill_workshop`), kein Plugin-Code |
| 48 | Uhr koppeln (Zahlenvergleich, Fenster 10 Min, Schlüssel genau einmal) | `zugang/uhr.ts`; Bestätigung als Handlung in `zugang/handeln.ts` |
| 49 | Uhr-Zugang (Abgleich, Token, Begrenzung) | `zugang/uhr.ts` |
| 49 | Körperwerte im Abgleich: Feld `k` = `bb` [Body Battery, Zeit s], `st` Stress, `sc` Schritte; Server legt `koerper` und `koerper:morgens` als Wert ab, Ausgabe in `seneca.stand.koerper`. Schlaf liest das iPhone aus HealthKit und schickt ihn per `seneca.handeln` (Art `koerper`: `schlaf_min`, `bis` in ms) → `koerper.schlaf` | `uhr/source/Abgleich.mc` → `zugang/uhr.ts` → `pforte/stand.ts` |
| – | Entscheiden-Seite: `seneca.stand.entscheiden` (Kopfsatz, Fenster, heute schon entschieden, Danach), `buendel.fortschritt` (3 von 14, ✓/↺, „Danach noch …“) und `buendel.abnahmen` mit Satz, Prüfer-Urteil, Art und Hörprobe; Optionen mit `titel`, `preis`, `einheit`, `knopf`, Frage mit `folge` (Wirkung nach außen) | `pforte/entscheiden.ts` |
| – | Heute-Seite: Kopfsatz `seneca.stand.heute.satz` zählt wartende Fragen, To-dos und Termine („Eine Frage, zwei To-dos. Der Rest des Tages gehört dir.“); `aufgaben.jeden_tag` mit `ab` und `dauer_min`, `team[].zuletzt.art`. Die Mac-Tagesschiene rechnet nur aus dem Stand, leere Blöcke fallen weg, Knöpfe über `seneca.handeln` | `pforte/heute.ts` · Mac `SnHeuteTafel.swift` |
| – | Projekte: Werkzeug `seneca_projekt` legt je Projekt den Wert `projekt:<name>` ab (Untertitel, Satz, Phasen, Start, nach, ruht); `seneca.stand.projekte` rechnet Zustand (braucht dich, läuft, wartet), Fragen, Läufe und nächsten Auftrag dazu | `pforte/projekte.ts` |
| – | Kalender: `seneca.stand.wochenplan` = Wochen (Kopf), Tage mit Body Battery, Ganztägigem, Blöcken (termin, bewegung, seneca, vorschlag, todos, fenster, zugleich) und Marken; `plant` = erste Überschneidung mit freier Zeit. Apps schreiben über `seneca.handeln`: `termin.anlegen`, `termin.verschieben` (mit Teilnehmern wird daraus ein Auftrag an Seneca), `termin.wegzeit` (Mac rechnet mit MapKit; `wegzeit:<uid>` Minuten, `wegstrecke:<uid>` Meter und Art), `kalender.lassen`. Schreibwünsche liegen als `kalender:schreiben:<kennung>`, der Kalender-Job trägt sie per CalDAV ein | `pforte/wochenplan.ts`, `quellen/kalender.ts`, `zugang/handeln.ts` |
| 45 | Ablage-Rechte je Bereich (lesen: `bereich`, `ablage_alle_lesen`; schreiben: `ablage_schreiben` und `_arbeit/<name>`) | `zugang/rechte.ts` · Hook `before_tool_call` |
| 78 | Arbeitsdateien in `_arbeit/` verfallen nach `arbeitsdateien_tage`, außer sie hängen an einem Auftrag | `arbeitsdienst/jobs.ts` · `arbeitVerfallen`, nur vom Job `pflegen` |
| 78a | Jeder Lauf erfährt seine Ablage-Rechte und `_arbeit/<name>` (ein Satz, für alle gleich) | `arbeitsdienst/lauf.ts` · `kontext` |
| 50 | Uhr-Abgleich (Kennung je Handlung) | `zugang/handeln.ts` |
| 53, 54 | Kalender lesen und schreiben (CalDAV, Konflikte, Teilnehmer nur über den Ausgang) | `quellen/kalender.ts` · Werkzeug `seneca_kalender`; Tagesstand je Tag als Wert `kalender:<tag>` (`register/lesen.ts` · `termineAm`) |
| – | Trainer (`team/trainer`, kein fester Rundgang): Garmin-Workouts Lauf, Rad und natives Kraft (Übungskatalog, Sätze, Wiederholungen, Gewicht, Pausen) anlegen, ändern, auf ein Datum legen, verlegen, auflisten, löschen; erledigte Aktivitäten, Schlaf, Body Battery, HRV und Trainingsbereitschaft lesen. Python-Skript mit der Bibliothek `garminconnect`, vom Trainer per `exec` aufgerufen; Venv `~/.garmin-venv`, Token nur am Server in `~/.garminconnect` (Rechte 700/600), Anmeldung einmal von Hand (`garmin.py anmelden`). Statistiken der Mitarbeiter: Anzeige der Art `statistik` mit Metrik, Zeitraum, Gruppe, Rechnung, Diagramm, Ziel und Grund; eine fehlerhafte Definition liefert nur `fehler` an ihrer Karte. Jede Einheit steht zusätzlich als Termin `Training: <Kurzname>` im Kalender `Privat` (zählt als Sport); erledigt heißt: Titel endet auf ` ✓`. Schreiben im Kalender dürfen die Mitarbeiter der Regel `kalender_schreiber` | `garmin/garmin.py`, `quellen/kalender.ts` |
| 55, 74 | Tagesplanung (To-dos in Lücken, Fenster frei), Los-Hinweis mit Ankunft, Fokus aus dem Kalender | `pforte/planen.ts`; Fokus wirkt in `pforte/stand.ts` · `ruhe`; Terminvorbereitung offen |
| 56 | Mail lesen | vorhandenes Zoho-Mail-Werkzeug, kein Plugin-Code |
| 57 | WhatsApp mitlesen (nie senden) | `quellen/whatsapp.ts` · Hook `message_received` |
| 58, 59, 63 | Eingang Meeting, Sensor, Datei: Ereignis `eingang`; Meeting und Datei werden ein Auftrag an Seneca, Sensor ein Vorschlag (nur sicher, höchstens 3 am Tag) oder ein Eintrag `tagesspur` | `zugang/handeln.ts` → `quellen/eingang.ts` · Job `eingang` |
| 79 | Datei aus der Ablage zeigen (Gespräch, Bericht): Vorschau nur innerhalb `ablage_pfad`, ohne `_sicherung` | `quellen/ablage.ts` · `dateiVorschau`, über `seneca.stand` mit `sicht: datei` |
| 80 | Gespräch neu beginnen (Handlung `gespraech.neu`; das Admin-Recht hat nur der Server) | `zugang/handeln.ts` → `arbeitsdienst/jobs.ts` · Job `gespraeche` |
| 60 | Vorschlag → ein Tipp → Auftrag, To-do, Wert oder Parken (ein Weg für alle Quellen, Herkunft je Vorschlag) | `register/schreiben.ts` · `vorschlagAnlegen`; Wirkung nach Ja: `arbeitsdienst/jobs.ts` · Job `faellige_wirkungen` |
| 60a | Vorschläge einer Quelle mit wenig Ja kommen nur noch ins Fenster; Vorschlag mit Frist verfällt | `pforte/zustellen.ts` |
| 67 | Plugin ausliefern | offen (`ausliefern.yml` nach dem Update auf 11.10) |
| 71 | Mitarbeiter anlegen | PR legt `team/<name>/` an; Agent anlegen: offen |
| 72 | Doku | `README.md`, `ARCHITEKTUR.md` |

## Angemeldete Namen → Ort

| Art | Name → Ort |
|---|---|
| Werkzeuge | `seneca_lesen` → `pforte/stand.ts` · `seneca_auftrag`, `seneca_fortschreiben` → `arbeitsdienst/lauf.ts` · `seneca_frage`, `seneca_einstellen`, `seneca_anzeige`, `seneca_todo`, `seneca_eintrag` → `register/schreiben.ts` · `seneca_lernen` → `lernen/lernen.ts` · `seneca_kalender` → `quellen/kalender.ts` |
| Gateway-Methoden | `seneca.stand` → `pforte/stand.ts` · `seneca.handeln` → `zugang/handeln.ts` · `seneca.verstehen` (Satz → To-do-Felder, Kalender des Tages) → `pforte/verstehen.ts` |
| HTTP-Routen | `/seneca/uhr/v1/abgleich`, `/seneca/uhr/v1/koppeln`, `/seneca/uhr/v1/abholen`, `/seneca/uhr/v1/zifferblatt` (nur Lesen, Schlüssel der Lauf-Ruhe) → `zugang/uhr.ts` · `/seneca/github` → `quellen/github.ts` (Lesen des Körpers mit Grenze: `index.ts`) |
| Hooks | `before_prompt_build`, `agent_end`, `run_stopped` → `arbeitsdienst/lauf.ts` · `before_tool_call` → `ausgang/ausgang.ts` und `zugang/rechte.ts` · `after_tool_call`, `subagent_spawned` → `ausgang/ausgang.ts` · `message_received` → `quellen/whatsapp.ts` |
| Dienst | `seneca.takt` → `arbeitsdienst/takt.ts` |
| Verlauf je Gespräch: Quittung (was Seneca getan hat, Ergebnis, „Termin zurücklegen“), Gerät je Nachricht (Schlüssel `<geraet>-<uuid>`), Antworten ohne eigene Frage | `pforte/verlauf.ts` → `seneca.stand.verlauf`; Apps: `SenecaKern/Pocket/VerlaufLogik.swift` |
| Takt-Jobs | `faellige_auftraege`, `faellige_wirkungen`, `kalender_wache` (Vorschläge verfallen still, „Zu spät“ fragt einmal), `laeufe_pruefen`, `pflegen`, `gespraeche` → `arbeitsdienst/jobs.ts` · `knoten` → `arbeitsdienst/rechenknoten.ts` · `zustellen` → `pforte/zustellen.ts` · `kalender` → `quellen/kalender.ts` · `eingang` → `quellen/eingang.ts` · `planen` → `pforte/planen.ts` · `melden` (Ereignis `stand` an die Apps bei neuer Revision) → `index.ts` · `garmin` (ohne Modell: neue Garmin-Aktivitäten, Sätze, Nacht- und Tageswerte als Einträge mit Kennung `garmin:…`, Health-Lauf zur selben Zeit wird gelöscht, Garmin führt; Kennzahlen und Statistiken der Mitarbeiter als Wert `statistik:kennzahlen`, in `seneca.stand` sicht `statistik`) → `index.ts`, gerechnet in `garmin/garmin.py` |

## Uhr-App: Aussehen

Vorlage ist der Entwurf „Seneca – ein Assistent, drei Geräte“, Seite Garmin (Maße in px auf 466 × 466).

| Teil | Ort |
|---|---|
| Farben, Schriften, Grundformen (Tastenmarke, Ring, Balken, Haken), Bewegung | `uhr/gemeinsam/Zeichnen.mc` (App, Zifferblatt, Trail), Klasse `Bewegung` in `uhr/source/Ansicht.mc` |
| Zifferblatt (Elegant, Sportlich, Always-On) | `uhr/zifferblatt/`, eigenes Watch-Face-Projekt |
| Trail-Datenfeld (Vollbild) | `uhr/trail/`, Connect-IQ-Datenfeld |
| Alle Positionen je Ansicht, in Entwurfs-px, skaliert auf 416, 454 und 466 px | `uhr/source/Bildschirm.mc` |
| Eigene Sätze je Übung, Bestwerte, letztes Training (bleiben auf der Uhr, auch nach dem Abgleich) | `uhr/source/Verlauf.mc` |
| Bitmap-Schriften (BMFont) und Lichtpunkt je Uhrgröße | `uhr/resources*/gestalt/`, erzeugt mit `python3 uhr/werkzeug/gestalt.py <Ordner mit den TTF von Google Fonts>` (Pillow, fontTools) |

App-Ansichten auf Schwarz (#000), wie im Entwurf. Die Ansichten liefern nur Inhalt und Tastenbelegung. Der Uhr-Stand (`uhrStand` in `pforte/stand.ts`) bringt je To-do Bereich und Dauer, `tm` (Team: Zustand, Satz, Projekt, Ende, heute Fertiges), `tg` (Termine heute: Sport, Fokus, Termin) und zur Frage Absender, Kontext, Projekt, gestellt und die Später-Zeit (`sb`). Zeiten an die Uhr in Sekunden. Die Uhr zeigt beim Start und im Takt, was dran ist (`Hinweise` in `AnsichtSeneca.mc`): Frage, Los-Hinweis 10 Min vor dem Termin, Akku knapp, Weitermachen, Speicher, Neu, Nacht, Morgen. Vibration: kurz = eingetragen, doppelt = Frage, Los-Hinweis, Pause vorbei, lang = Fehler und Akku; nachts keine. Schriften: IBM Plex Mono, Instrument Serif, Space Grotesk (OFL, `uhr/werkzeug/OFL.txt`).

Zifferblatt und App teilen keinen Speicher. Die App meldet die Seneca-Zeile als geschützte Komplikation (`Stand.melden`, nur Apps mit demselben Schlüssel sehen sie), das Zifferblatt abonniert sie. Ist die App nie gelaufen, zeigt das Zifferblatt die Fassung ohne Seneca-Zeile. Schlaf kommt nicht aus Connect IQ, sondern als `koerper.schlaf` (Minuten) im Uhr-Stand; fehlt er, steht „–“. Lauf-Ruhe: das Trail-Datenfeld meldet alle 5 Min `zs: trail` (eigene Einstellungen Adresse/Schlüssel), der Server hält Seneca dann still, bis 12 Min keine Meldung kam (`uhr_lauf_ruhe_min`).

