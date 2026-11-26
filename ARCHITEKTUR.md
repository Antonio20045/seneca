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
| `apps/Mac/SenecaNativ`, `SenecaWidget` | Oberfläche der Mac-App | `apps/SenecaKern`, `apps/Mac/MacKern` |
| `apps/iPhone/*` | Oberfläche, Widget, Teilen-Erweiterung der iPhone-App | `apps/SenecaKern` |

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
| 15, 16 | Wecken; „ruht“ prüfen (einzige Prüfstelle) | `arbeitsdienst/lauf.ts` · `starteLauf()` |
| 17 | Hintergrundjobs mit wachsendem Abstand bei Fehlern | `arbeitsdienst/takt.ts` |
| 18 | Rundgang, Morgenbericht, Rückblick, Briefing | Daueraufträge, geweckt von `faellige_auftraege` |
| 19 | Kontext für den Lauf | `arbeitsdienst/lauf.ts` · Hook `before_prompt_build` |
| 20 | Lauf-Ende: Fortschreibung erzwingen | `arbeitsdienst/lauf.ts` · Hook `agent_end` (ohne Fortschreibung: Befund `ohne_stand`) |
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
| 32, 33 | Ruhe, Abstand der Mitteilungen, Zustellung je Gerät | `pforte/zustellen.ts` |
| 39a | Anruf an Antonio, wenn ein Auftrag feststeckt (nie nachts, Schlaf, Training) | entschieden nur in `pforte/zustellen.ts` (Auftrag `anruf_antonio`), ausgeführt über `ausgang/ausgang.ts` |
| 34 | Push senden (APNs, Schlüssel nur aus der Plugin-Konfiguration, ohne Schlüssel still aus) | `pforte/push.ts`, aufgerufen nur aus `pforte/zustellen.ts` |
| 38, 39, 41, 42 | Nach außen nur nach Stufe, 5 s, höchstens einmal | `ausgang/ausgang.ts` · Hook `before_tool_call` |
| 40 | Stufe je Empfänger | `ausgang/kontakte.ts` |
| 43, 46, 47 | Korrektur einordnen, Sperre als Auftrag, Wiederholungen | `lernen/lernen.ts` |
| 44 | Skill ändern | Skill-Werkstatt von OpenClaw (`skill_workshop`), kein Plugin-Code |
| 48 | Uhr koppeln (Zahlenvergleich, Fenster 10 Min, Schlüssel genau einmal) | `zugang/uhr.ts`; Bestätigung als Handlung in `zugang/handeln.ts` |
| 49 | Uhr-Zugang (Abgleich, Token, Begrenzung) | `zugang/uhr.ts` |
| 45 | Ablage-Rechte je Bereich (lesen: `bereich`, schreiben: `ablage_schreiben`) | `zugang/rechte.ts` · Hook `before_tool_call` |
| 50 | Uhr-Abgleich (Kennung je Handlung) | `zugang/handeln.ts` |
| 53, 54 | Kalender lesen und schreiben (CalDAV, Konflikte, Teilnehmer nur über den Ausgang) | `quellen/kalender.ts` · Werkzeug `seneca_kalender`; Tagesstand je Tag als Wert `kalender:<tag>` (`register/lesen.ts` · `termineAm`) |
| 55, 74 | Tagesplanung (To-dos in Lücken, Fenster frei), Los-Hinweis mit Ankunft, Fokus aus dem Kalender | `pforte/planen.ts`; Fokus wirkt in `pforte/stand.ts` · `ruhe`; Terminvorbereitung offen |
| 56 | Mail lesen | vorhandenes Zoho-Mail-Werkzeug, kein Plugin-Code |
| 57 | WhatsApp mitlesen (nie senden) | `quellen/whatsapp.ts` · Hook `message_received` |
| 58, 59, 63 | Eingang Meeting, Sensor, Datei | `zugang/handeln.ts` → Ereignis `eingang` |
| 60 | Vorschlag → ein Tipp → Auftrag | Frage Art `vorschlag`, `arbeitsdienst/jobs.ts` · Job `faellige_wirkungen` |
| 67 | Plugin ausliefern | offen (`ausliefern.yml` nach dem Update auf 11.10) |
| 71 | Mitarbeiter anlegen | PR legt `team/<name>/` an; Agent anlegen: offen |
| 72 | Doku | `README.md`, `ARCHITEKTUR.md` |

## Angemeldete Namen → Ort

| Art | Name → Ort |
|---|---|
| Werkzeuge | `seneca_lesen` → `pforte/stand.ts` · `seneca_auftrag`, `seneca_fortschreiben` → `arbeitsdienst/lauf.ts` · `seneca_frage`, `seneca_einstellen`, `seneca_anzeige`, `seneca_todo`, `seneca_eintrag` → `register/schreiben.ts` · `seneca_lernen` → `lernen/lernen.ts` · `seneca_kalender` → `quellen/kalender.ts` |
| Gateway-Methoden | `seneca.stand` → `pforte/stand.ts` · `seneca.handeln` → `zugang/handeln.ts` |
| HTTP-Routen | `/seneca/uhr/v1/abgleich`, `/seneca/uhr/v1/koppeln`, `/seneca/uhr/v1/abholen` → `zugang/uhr.ts` · `/seneca/github` → `quellen/github.ts` (Lesen des Körpers mit Grenze: `index.ts`) |
| Hooks | `before_prompt_build`, `agent_end` → `arbeitsdienst/lauf.ts` · `before_tool_call` → `ausgang/ausgang.ts` und `zugang/rechte.ts` · `after_tool_call` → `ausgang/ausgang.ts` · `message_received` → `quellen/whatsapp.ts` |
| Dienst | `seneca.takt` → `arbeitsdienst/takt.ts` |
| Takt-Jobs | `faellige_auftraege`, `faellige_wirkungen`, `laeufe_pruefen`, `pflegen` → `arbeitsdienst/jobs.ts` · `knoten` → `arbeitsdienst/rechenknoten.ts` · `zustellen` → `pforte/zustellen.ts` · `kalender` → `quellen/kalender.ts` · `planen` → `pforte/planen.ts` · `melden` (Ereignis `stand` an die Apps bei neuer Revision) → `index.ts` |

## Uhr-App: Aussehen

Vorlage ist der Entwurf „Seneca – ein Assistent, drei Geräte“, Seite Garmin (Maße in px auf 466 × 466).

| Teil | Ort |
|---|---|
| Farben, Schriften, Grundformen (Tastenmarke, Ring, Balken, Haken), Bewegung | `uhr/source/Zeichnen.mc`, Klasse `Bewegung` in `uhr/source/Ansicht.mc` |
| Alle Positionen je Ansicht, in Entwurfs-px, skaliert auf 416, 454 und 466 px | `uhr/source/Bildschirm.mc` |
| Eigene Sätze je Übung, Bestwerte, letztes Training (bleiben auf der Uhr, auch nach dem Abgleich) | `uhr/source/Verlauf.mc` |
| Bitmap-Schriften (BMFont) und Lichtpunkt je Uhrgröße | `uhr/resources*/gestalt/`, erzeugt mit `python3 uhr/werkzeug/gestalt.py <Ordner mit den TTF von Google Fonts>` (Pillow, fontTools) |

App-Ansichten auf Schwarz (#000), wie im Entwurf. Die Ansichten liefern nur Inhalt und Tastenbelegung. Der Uhr-Stand (`uhrStand` in `pforte/stand.ts`) bringt je To-do Bereich und Dauer und `ta` (wie viele im Team arbeiten). Schriften: IBM Plex Mono, Instrument Serif, Space Grotesk (OFL, `uhr/werkzeug/OFL.txt`).
