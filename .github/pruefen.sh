#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
BUDGET=("plugin/src/register|610" "plugin/src/arbeitsdienst|780" "plugin/src/pforte|1184" "plugin/src/ausgang|250"
  "plugin/src/lernen|120" "plugin/src/zugang|331" "plugin/src/quellen|400" "plugin/src/index.ts plugin/src/regeln.ts plugin/src/team.ts|360"
  "plugin/src|4000" "plugin/pruefffaelle|1500" ".github/pruefen.sh|150" ".github/workflows|150"
  "apps/Mac|28737" "apps/iPhone|20658" "apps/SenecaKern|11092")
TRY_BESTAND=602
ERLAUBT=" openclaw typescript @types/node typebox yaml "
PF_MAX=12
MODULE="arbeitsdienst pforte ausgang lernen zugang quellen"
fehler=0
melde() { echo "$1: $2"; fehler=1; }
verbot() { local r=$1 t; shift; t=$(rg -n "$@" 2>/dev/null) && melde "$r" "$t"; }
dateien() { git ls-files --cached --others --exclude-standard "$@"; }

for e in "${BUDGET[@]}"; do
  n=$(rg -N --no-filename '\S' ${e%|*} 2>/dev/null | wc -l)
  [ "$n" -le "${e#*|}" ] || melde P1 "${e%|*}: $n Zeilen, Budget ${e#*|}"
done

verbot P2 -P -w -e '(INSERT|UPDATE|DELETE|CREATE|ALTER)(?!")' -e 'node:sqlite' plugin apps uhr -g '!plugin/src/register/**'

verbot P3 -e 'SET[^;]*\bzustand\s*=' -e '\.zustand\s*=[^=]' plugin -g '!plugin/src/register/schreiben.ts'
verbot P3 -e '\b(if|for|while|function)\b' -e '=>' plugin/src/register/uebergaenge.ts

for m in $MODULE; do verbot P4 -P 'from "\.\./(?!register/|regeln\.ts"|team\.ts")' plugin/src/$m; done
verbot P4 -P 'from "\.\./(?!regeln\.ts")' plugin/src/register
verbot P4 -e 'from "\.' plugin/src/regeln.ts plugin/src/team.ts
verbot P4 -e 'from "[^"]*\b(apps|uhr|team)/' plugin

verbot P5 -e 'setInterval|setTimeout\(|\bcron\b|\bschedule|systemd|launchd' plugin/src -g '!plugin/src/arbeitsdienst/takt.ts'
t=$(dateien | rg -e '\.timer$' -e '\.service$' -e 'LaunchAgent') && melde P5 "$t"
[ "$(rg -c 'job: "' plugin/src/index.ts)" = "$(rg -c 'job: "[a-z_]+", ursache: "[^"]+"' plugin/src/index.ts)" ] || melde P5 "Job ohne ursache in index.ts"

verbot P6 -e smtp -e nodemailer -e place_call -e telnyx -e twilio -e sendMail -e wacli -e sendMessage plugin/src -g '!plugin/src/ausgang/**'

t=$(dateien | rg -e '\.(bak|orig|alt)$' -e '\.vor-' -e '-kopie' -e '(^|/)einbau') && melde P7 "$t"
PRUEFBAR=$(dateien | rg -v -e '^\.github/pruefen\.sh$' -e 'package-lock\.json$')
verbot P7 -i -e 'bleibt annehmbar' -e 'wird ignoriert' -e deprecated -e legacy -e compat $PRUEFBAR
verbot P7 -e TODO -e FIXME $PRUEFBAR
verbot P7 -e 'gh[pousr]_[A-Za-z0-9]{20,}' -e 'github_pat_' -e 'sk-ant-' -e 'AKIA[0-9A-Z]{16}' -e 'xox[abp]-' -e 'BEGIN [A-Z ]*PRIVATE KEY' $PRUEFBAR

verbot P8 -e '^\s*(//|/\*|\*)' -e '\s//\s' plugin -g '*.ts'
verbot P8 -e '^\s*//(?! swift-tools-version:)' -P apps uhr -g '*.swift' -g '*.mc'
for f in $(dateien '*.sh'); do t=$(rg -n '^\s*#' "$f" | rg -v '^1:#!') && melde P8 "$f $t"; done

verbot P9 -e '\*\s*(1000|60)\b' -e 'setTimeout\([^)]*,\s*[0-9]' plugin/src -g '!plugin/src/regeln.ts'
verbot P9 -e '\*\s*(1000|60)\b' -e '\b(1000|60000|3600)\b' uhr/source -g '!uhr/source/Regeln.mc'
def=" $(rg -o --no-filename '^[a-z0-9_]+' regeln | tr '\n' ' ')"
gel=" $(rg -o --no-filename -r '$2' 'regel(Zahl|Text|Ms|Liste|UhrzeitNach)\("([a-z0-9_]+)"' plugin/src | tr '\n' ' ') $(rg -o --no-filename -r '$1' '\bregel ([a-z0-9_]+)' apps/installieren.sh | tr '\n' ' ') $(rg -o --no-filename -P '^[a-z0-9_]+(?=\s.*\sapp$)' regeln | tr '\n' ' ')"
for n in $def; do [[ $gel == *" $n "* ]] || melde P9 "regeln: $n wird nie gelesen"; done
for n in $gel; do [[ $def == *" $n "* ]] || melde P9 "$n fehlt in regeln"; done

verbot P10 -U -e 'catch\s*(\([^)]*\))?\s*\{\s*\}' plugin/src
verbot P10 -w -e catch plugin/src/register
verbot P10 -e 'as any\b' -e 'as unknown as' plugin/src -g '!plugin/src/index.ts' -g '!plugin/src/quellen/**'
n=$(rg -c 'try\?' apps | awk -F: '{s+=$2} END {print s+0}')
[ "$n" -le $TRY_BESTAND ] || melde P10 "try? in apps: $n Zeilen, Bestand $TRY_BESTAND"

for p in $(dateien '*package.json'); do
  im=0
  while IFS= read -r z; do
    [[ $z =~ \"[a-zA-Z]*[dD]ependencies\" ]] && { im=1; continue; }
    [[ $z =~ \} ]] && im=0
    [[ $im = 1 && $z =~ \"([^\"]+)\": ]] && [[ $ERLAUBT != *" ${BASH_REMATCH[1]} "* ]] && melde P11 "$p: ${BASH_REMATCH[1]} nicht erlaubt"
  done < "$p"
done

for f in $(dateien '*.md'); do
  case $f in README.md) max=60 ;; ARCHITEKTUR.md) max=250 ;; team/*/rolle.md | team/engineer/bauregeln.md) max=60 ;; *) melde P12 "$f nicht erlaubt"; continue ;; esac
  n=$(wc -l < "$f"); [ "$n" -le "$max" ] || melde P12 "$f: $n Zeilen > $max"
done
t=$(dateien | rg '(^|/)docs/') && melde P12 "docs/ verboten: $t"

t=$(dateien | rg -e '\.(test|spec)\.' -e '(^|/)(tests?|__tests__)/' -e 'PF[0-9]{2}' | rg -v -e '^plugin/pruefffaelle/' -e '^apps/SenecaKern/Tests/') && melde P13 "Test am falschen Ort: $t"
t=$(dateien plugin/pruefffaelle apps/SenecaKern/Tests | rg -v -e 'PF[0-9]{2}' -e 'aufbau\.ts$') && melde P13 "ohne PF-Nummer: $t"
n=$(dateien plugin/pruefffaelle apps/SenecaKern/Tests | rg -o 'PF[0-9]{2}' | sort -u | wc -l)
[ "$n" -le $PF_MAX ] || melde P13 "$n Prüffälle, höchstens $PF_MAX"
verbot P13 -e 'nicht mehr' -e 'gelöscht' -e 'removed' -e 'no longer' plugin/pruefffaelle apps/SenecaKern/Tests

NAMEN='"(seneca[._][a-z_.]+)"|api\.on\("([a-z_]+)"|job: "([a-z_]+)"|route\("([^"]+)"'
for n in $(rg -o --no-filename -r '$1$2$3$4' "$NAMEN" plugin/src/index.ts 2>/dev/null); do rg -qF "\`$n\`" ARCHITEKTUR.md || melde P14 "$n fehlt in ARCHITEKTUR.md"; done
for p in $(rg -o --no-filename -r '$1' '`((register|arbeitsdienst|pforte|ausgang|lernen|zugang|quellen)/[a-z]+\.ts|regeln\.ts|team\.ts|index\.ts)`' ARCHITEKTUR.md); do
  [ -f "plugin/src/$p" ] || melde P14 "ARCHITEKTUR.md nennt $p, die Datei fehlt"
done
for n in $(rg -o --no-filename -P -r '$1' '^export (?:async )?(?:function|const|type) ([A-Za-z0-9_]+)' plugin/src); do
  [ "$(rg -lw "$n" plugin -g '*.ts' | wc -l)" -ge 2 ] || melde P14 "toter Export $n"
done

verbot P15 -e '(~|/|")Bereiche/' $PRUEFBAR

[ $fehler = 0 ] && echo "pruefen: alle 15 Prüfungen bestanden"
exit $fehler
