#!/usr/bin/env bash
set -uo pipefail
ORT=$(cd "$(dirname "$0")/.." && pwd)
REGISTER="$HOME/.openclaw/seneca/register.sqlite"
WARTEN_MIN=${WARTEN_MIN:-30}
VERSUCHE=${VERSUCHE:-3}

exec 9>"$HOME/.openclaw/seneca/ausliefern.lock"
flock -n 9 || { echo "Abbruch: ein anderes Ausliefern läuft gerade. Nicht gleichzeitig neu laden."; exit 3; }

STAND=${1:-origin/zusammen}
{ git -C "$ORT" fetch -q origin && git -C "$ORT" checkout -q --detach "$STAND"; } || { echo "Abbruch: Stand $STAND ließ sich nicht holen."; exit 4; }

aktiv() { sqlite3 -readonly "$REGISTER" "SELECT count(*) FROM lauf WHERE zustand IN ('startet','laeuft','haengt')"; }
ruhig() {
  local bis=$(( $(date +%s) + WARTEN_MIN * 60 )) n
  while n=$(aktiv) && [ "$n" -gt 0 ]; do
    [ "$(date +%s)" -lt "$bis" ] || { echo "Noch $n Mitarbeiter-Lauf/Läufe aktiv nach $WARTEN_MIN min."; return 1; }
    sleep 20
  done
}

for v in $(seq 1 "$VERSUCHE"); do
  ruhig || { echo "Nicht neu geladen: Mitarbeiter arbeiten noch. Später erneut starten."; exit 2; }
  if timeout -k 30 660 openclaw plugins reload seneca --wait --json; then
    echo "Ausgeliefert: $(git -C "$ORT" log --oneline -1)"
    exit 0
  fi
  echo "Versuch $v: Neuladen kam nicht durch (ein Lauf hielt das Plugin). Alter Stand läuft weiter."
done
echo "Nicht neu geladen nach $VERSUCHE Versuchen."
exit 1
