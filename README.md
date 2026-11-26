# Seneca

Seneca ist Antonios Assistent mit seinem Team. Dieses Repo enthält alles, was dafür gebaut wird:
die Erweiterung (Plugin) für OpenClaw auf dem Server, die Apps für Mac, iPhone und Uhr,
und je Mitarbeiter einen Ordner mit Rolle und Mandat.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `plugin/` | OpenClaw-Plugin, die Server-Seite (höchstens 4.000 Zeilen) |
| `plugin/pruefffaelle/` | die höchstens zwölf Prüffälle PF01 bis PF12 |
| `apps/SenecaKern/` | gemeinsamer Code von Mac und iPhone, ein Exemplar |
| `apps/Mac/`, `apps/iPhone/` | die beiden Apps (Xcode-Projekte) |
| `uhr/` | die Garmin-App |
| `team/<name>/` | `rolle.md` und `mandat` je Mitarbeiter |
| `regeln` | alle Zeiten und Schwellen, eine Zeile je Wert |
| `.github/pruefen.sh` | das eine Prüfskript mit 14 Prüfungen |

Module, Grenzen und die Tabelle „Funktion → Ort“ stehen in `ARCHITEKTUR.md`.

## Bauen und prüfen

Voraussetzung: Node 26, `rg` (ripgrep).

```
bash .github/pruefen.sh
cd plugin
npm ci --ignore-scripts
npx tsc --noEmit -p .
node --test "pruefffaelle/PF*.ts"
```

Apps (Xcode 26 oder neuer, ohne Signatur):

```
xcodebuild -project apps/Mac/SenecaNativ.xcodeproj -scheme SenecaNativ CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apps/iPhone/SenecaPocket.xcodeproj -scheme SenecaPocket -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Das Plugin wird als TypeScript geladen; OpenClaw 2026.11.10 übersetzt es selbst.
Das Paket `openclaw` steht nur für Typen und Doku in `devDependencies`.

## Installieren

Noch nicht: Das Plugin geht erst nach dem Update des Servers auf OpenClaw 11.10 hinaus.
Dann liefert `ausliefern.yml` es aus, nur wenn kein Lauf aktiv ist.

Apps: nur kostenloses Apple-Konto, das Profil läuft nach 7 Tagen ab. Darum baut `apps/installieren.sh iphone`
den Stand von `main` und spielt ihn aufs iPhone, sobald es im WLAN ist und die letzte Installation
`app_neu_installieren_tage` alt ist. `apps/de.antonio.seneca-installieren.plist` (nach `~/Library/LaunchAgents`) ruft es
alle 3 Stunden. `installieren.sh mac --jetzt` ersetzt die Mac-App nur, wenn Seneca nicht läuft.

## Regeln für Änderungen

- Ein Ort je Funktion. Wer einen neuen Weg baut, löscht den alten im selben PR.
- Keine Kommentare im Code. Das Warum steht im Namen, im Prüffall oder in `ARCHITEKTUR.md`.
- Zahlen und Zeiten nur in `regeln`.
- Gelöschtes ganz löschen, ohne Reste und ohne Test dafür.
- Jeder PR braucht ein grünes CI.
