#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(ls -d "$HOME"/Library/Application\ Support/Garmin/ConnectIQ/Sdks/* | tail -1)
SCHLUESSEL=${SENECA_UHR_SCHLUESSEL:-$HOME/.seneca/uhr-schluessel.der}
mkdir -p bin
for geraet in fenix9pro43mm fenix9pro47mm fenix9pro51mm; do
  "$SDK/bin/monkeyc" -d "$geraet" -f monkey.jungle -o "bin/seneca-$geraet.prg" -y "$SCHLUESSEL" -r -w
done
