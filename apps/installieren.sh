#!/bin/bash
set -uo pipefail
ZIEL="${1:-iphone}"
SOFORT=""; TROCKEN=""
for a in "${@:2}"; do case "$a" in --jetzt) SOFORT=--jetzt ;; --trocken) TROCKEN=1 ;; esac; done
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
QUELLE="$HOME/Library/Caches/seneca-quelle"
BAU="$HOME/Library/Caches/seneca-bau-$ZIEL"
STAND="$HOME/Library/Caches/seneca-installiert-$ZIEL"
LOG="$HOME/Library/Logs/seneca-installieren.log"
mkdir -p "$(dirname "$LOG")"
[ -n "$TROCKEN" ] || exec >>"$LOG" 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M') $ZIEL ==="
melden() { osascript -e "display notification \"$1\" with title \"Seneca installieren\"" >/dev/null 2>&1; echo "MELDUNG: $1"; }
ausf() { if [ -n "$TROCKEN" ]; then echo "TROCKEN: $*"; else "$@"; fi; }
APP="/Applications/Seneca Nativ.app"
mac_beschaeftigt() {
  local d="$HOME/Library/Application Support/Seneca Nativ" f leer vorn
  [ -e "$d/diktat/mikrofon.lock" ] && { echo "Diktat läuft"; return 0; }
  for f in "$d"/speicher-agent_*.json "$d"/chat-history-*.json; do
    [ -e "$f" ] && [ -n "$(find "$f" -mmin -10 2>/dev/null)" ] && { echo "Chat vor weniger als 10 Min benutzt"; return 0; }
  done
  leer=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ { printf "%d", $NF / 1000000000; exit }')
  vorn=$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null)
  case "$vorn" in *"Seneca Nativ"*) [ "${leer:-99999}" -lt 600 ] && { echo "Seneca vorn, letzte Eingabe vor ${leer}s"; return 0; } ;; esac
  return 1
}
mac_tauschen() {
  local neu="$1" lief="" grund v
  pgrep -x "Seneca Nativ" >/dev/null && lief=1
  if [ -n "$lief" ]; then
    if grund=$(mac_beschaeftigt); then echo "Neue Mac-App gebaut, Austausch verschoben: $grund."; return 2; fi
    for v in 1 2 3; do
      ausf osascript -e 'tell application "Seneca Nativ" to quit'
      [ -n "$TROCKEN" ] && break
      for _ in {1..20}; do pgrep -x "Seneca Nativ" >/dev/null || break; sleep 0.5; done
      pgrep -x "Seneca Nativ" >/dev/null || break
    done
    if [ -z "$TROCKEN" ] && pgrep -x "Seneca Nativ" >/dev/null; then echo "Seneca ließ sich nicht beenden, später nochmal."; return 2; fi
  fi
  ausf rm -rf "$BAU-vorher.app"
  ausf cp -R "$APP" "$BAU-vorher.app"
  ausf rm -rf "$APP"
  ausf cp -R "$neu" /Applications/ || return 1
  if [ -n "$lief" ]; then ausf open -g "$APP"; fi
  return 0
}

if [ -n "$TROCKEN" ]; then echo "TROCKEN: git fetch/clone und checkout des Tags $ZIEL-frei-<n> übersprungen, nutze vorhandene Quelle $QUELLE"
elif [ -d "$QUELLE/.git" ]; then git -C "$QUELLE" fetch -q --tags --force origin || { echo "GitHub nicht erreichbar"; exit 0; }
else git clone -q https://github.com/Antonio20045/seneca.git "$QUELLE" || { echo "GitHub nicht erreichbar"; exit 0; }; fi
FREI=$(git -C "$QUELLE" tag -l "$ZIEL-frei-*" | awk -F- '$NF ~ /^[0-9]+$/ { print $NF, $0 }' | sort -n | tail -1 | cut -d" " -f2)
[ -n "$TROCKEN" ] || git -C "$QUELLE" checkout -q --force "refs/tags/${FREI:-$ZIEL-frei-1}" || { melden "Keine freigegebene Fassung: Tag $ZIEL-frei-<n> fehlt."; exit 1; }
regel() { awk -v n="$1" '$1 == n { print $2 }' "$QUELLE/regeln"; }
TAGE=$(regel app_neu_installieren_tage)
[ -n "$TAGE" ] || { melden "regeln: app_neu_installieren_tage fehlt."; exit 1; }
WIE_ALT=$(( ( $(date +%s) - $(cat "$STAND" 2>/dev/null || echo 0) ) / 86400 ))
if [ "$SOFORT" != --jetzt ] && [ "$WIE_ALT" -lt "$TAGE" ]; then echo "Installation $WIE_ALT Tage alt, nichts zu tun."; exit 0; fi

if [ "$ZIEL" = iphone ]; then
  GERAET=$(xcrun devicectl list devices --timeout 15 2>/dev/null | awk '/physical/ && /iPhone/ && /available|connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i }' | head -1)
  if [ -z "$GERAET" ]; then
    echo "iPhone nicht im WLAN erreichbar."
    [ "$WIE_ALT" -gt "$TAGE" ] && melden "Die Seneca-App läuft bald ab. iPhone bitte ins WLAN des Macs bringen."
    exit 0
  fi
  xcodebuild -project "$QUELLE/apps/iPhone/SenecaPocket.xcodeproj" -scheme SenecaPocket -configuration Release -destination "id=$GERAET" \
    -derivedDataPath "$BAU" -allowProvisioningUpdates -quiet build > "$BAU.log" 2>&1 \
    || { grep -m5 'error:' "$BAU.log"; melden "Bau der iPhone-App fehlgeschlagen. Protokoll: $BAU.log"; exit 1; }
  xcrun devicectl device install app --device "$GERAET" "$BAU/Build/Products/Release-iphoneos/SenecaPocket.app" \
    || { melden "Installation aufs iPhone fehlgeschlagen (iPhone entsperren?)."; exit 1; }
else
  if [ -n "$TROCKEN" ]; then echo "TROCKEN: xcodebuild SenecaNativ Release -> $BAU"
  else xcodebuild -project "$QUELLE/apps/Mac/SenecaNativ.xcodeproj" -scheme SenecaNativ -configuration Release ARCHS=arm64 \
    -derivedDataPath "$BAU" -allowProvisioningUpdates -quiet build > "$BAU.log" 2>&1 \
    || { grep -m5 'error:' "$BAU.log"; melden "Bau der Mac-App fehlgeschlagen. Protokoll: $BAU.log"; exit 1; }; fi
  mac_tauschen "$BAU/Build/Products/Release/Seneca Nativ.app"; rc=$?
  [ "$rc" = 2 ] && exit 0
  [ "$rc" = 0 ] || { melden "Mac-App konnte nicht ersetzt werden."; exit 1; }
fi
[ -n "$TROCKEN" ] && { echo "TROCKEN: fertig, nichts verändert."; exit 0; }
date +%s > "$STAND"
echo "Installiert: $ZIEL aus $(git -C "$QUELLE" rev-parse --short HEAD)"
