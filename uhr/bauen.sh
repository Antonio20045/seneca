#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(ls -d "$HOME"/Library/Application\ Support/Garmin/ConnectIQ/Sdks/* | tail -1)
SCHLUESSEL=${SENECA_UHR_SCHLUESSEL:-$HOME/.seneca/uhr-schluessel.der}
mkdir -p bin
for projekt in .:seneca zifferblatt:zifferblatt trail:trail; do
  for geraet in fenix9pro43mm fenix9pro47mm fenix9pro51mm; do
    "$SDK/bin/monkeyc" -d "$geraet" -f "${projekt%%:*}/monkey.jungle" -o "bin/${projekt#*:}-$geraet.prg" -y "$SCHLUESSEL" -r -w
  done
done
