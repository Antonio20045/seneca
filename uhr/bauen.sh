#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(ls -d "$HOME"/Library/Application\ Support/Garmin/ConnectIQ/Sdks/* | tail -1)
SCHLUESSEL=${SENECA_UHR_SCHLUESSEL:-$HOME/.seneca/uhr-schluessel.der}
ADRESSE=${SENECA_UHR_ADRESSE:-$(cat "$HOME/.seneca/uhr-adresse" 2>/dev/null || true)}
LAUF=$HOME/.seneca/uhr-lauf
[ -s "$LAUF" ] || (umask 077 && openssl rand -hex 24 > "$LAUF")
mkdir -p bin/adresse
printf '(:background, :glance)\nmodule Adresse {\n    const SERVER = "%s";\n    const LAUF = "%s";\n}\n' "${ADRESSE%/}" "$(cat "$LAUF")" > bin/adresse/Adresse.mc
for projekt in .:seneca zifferblatt:zifferblatt trail:trail; do
  for geraet in fenix9pro43mm fenix9pro47mm fenix9pro51mm fenix9prosolar51mm; do
    "$SDK/bin/monkeyc" -d "$geraet" -f "${projekt%%:*}/monkey.jungle" -o "bin/${projekt#*:}-$geraet.prg" -y "$SCHLUESSEL" -r -w
  done
done
