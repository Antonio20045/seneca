#!/bin/bash
set -uo pipefail
ZIEL="${1:-iphone}"
SOFORT="${2:-}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
QUELLE="$HOME/Library/Caches/seneca-quelle"
BAU="$HOME/Library/Caches/seneca-bau-$ZIEL"
STAND="$HOME/Library/Caches/seneca-installiert-$ZIEL"
LOG="$HOME/Library/Logs/seneca-installieren.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M') $ZIEL ==="
melden() { osascript -e "display notification \"$1\" with title \"Seneca installieren\"" >/dev/null 2>&1; echo "MELDUNG: $1"; }

if [ -d "$QUELLE/.git" ]; then git -C "$QUELLE" fetch -q --tags --force origin || { echo "GitHub nicht erreichbar"; exit 0; }
else git clone -q https://github.com/Antonio20045/seneca.git "$QUELLE" || { echo "GitHub nicht erreichbar"; exit 0; }; fi
git -C "$QUELLE" checkout -q --force "refs/tags/$ZIEL-frei" || { melden "Keine freigegebene Fassung: Tag $ZIEL-frei fehlt."; exit 1; }
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
  xcodebuild -project "$QUELLE/apps/Mac/SenecaNativ.xcodeproj" -scheme SenecaNativ -configuration Release ARCHS=arm64 \
    -derivedDataPath "$BAU" -allowProvisioningUpdates -quiet build > "$BAU.log" 2>&1 \
    || { grep -m5 'error:' "$BAU.log"; melden "Bau der Mac-App fehlgeschlagen. Protokoll: $BAU.log"; exit 1; }
  if pgrep -x "Seneca Nativ" >/dev/null; then melden "Neue Mac-App ist gebaut. Sie ersetzt die laufende erst, wenn Seneca beendet ist."; exit 0; fi
  rm -rf "$BAU-vorher.app" && cp -R "/Applications/Seneca Nativ.app" "$BAU-vorher.app" 2>/dev/null
  rm -rf "/Applications/Seneca Nativ.app" && cp -R "$BAU/Build/Products/Release/Seneca Nativ.app" /Applications/ \
    || { melden "Mac-App konnte nicht ersetzt werden."; exit 1; }
fi
date +%s > "$STAND"
echo "Installiert: $ZIEL aus $(git -C "$QUELLE" rev-parse --short HEAD)"
