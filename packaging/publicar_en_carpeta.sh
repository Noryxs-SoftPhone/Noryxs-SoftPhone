#!/usr/bin/env bash
# Publica una versión de NORYXS en la carpeta compartida del hotel para que los
# puestos la detecten solos (sin servidor). Uso:
#   packaging/publicar_en_carpeta.sh <carpeta_compartida> <carpeta_con_paquetes> ["notas de la versión"]
# <carpeta_con_paquetes>: donde has descargado los artefactos de GitHub Actions
#   (NORYXS-Terminal-macOS.zip, NORYXS-Terminal-Windows.zip y NORYXS-Terminal_<versión>_amd64.deb).
set -euo pipefail
DEST="${1:?carpeta compartida}"
SRC="${2:?carpeta con los paquetes}"
NOTES="${3:-}"
VER=$(sed -n 's/^version: *//p' "$(dirname "$0")/../app/pubspec.yaml" | head -1 | cut -d+ -f1)

mac=$(cd "$SRC" && ls NORYXS-Terminal-macOS*.zip 2>/dev/null | head -1 || true)
win=$(cd "$SRC" && ls NORYXS-Terminal-Windows*.zip 2>/dev/null | head -1 || true)
deb=$(cd "$SRC" && ls NORYXS-Terminal_*_amd64.deb 2>/dev/null | head -1 || true)
[ -z "$mac$win$deb" ] && { echo "No hay paquetes en $SRC"; exit 1; }

mkdir -p "$DEST"
for f in "$mac" "$win" "$deb"; do [ -n "$f" ] && cp "$SRC/$f" "$DEST/"; done
python3 - "$DEST/latest.json" "$VER" "$NOTES" "$mac" "$win" "$deb" <<'PY'
import json, sys
out, ver, notes, mac, win, deb = sys.argv[1:7]
json.dump({"version": ver, "notes": notes, "macos": mac, "windows": win, "linux": deb},
          open(out, "w"), ensure_ascii=False, indent=2)
PY
echo "Publicada la versión $VER en $DEST"
cat "$DEST/latest.json"
