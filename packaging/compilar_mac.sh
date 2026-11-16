#!/usr/bin/env bash
# Compila la app de macOS en Release con versión, compilación (commit) y fecha, y la instala.
# Uso: packaging/compilar_mac.sh [--no-instalar]
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER=${FLUTTER:-$HOME/development/flutter/bin/flutter}
VER=$(sed -n 's/^version: *//p' app/pubspec.yaml | head -1 | cut -d+ -f1)
BUILD=$(git rev-parse --short HEAD)$(git diff --quiet || echo "-mod")
DATE=$(date +%Y-%m-%d)
make -C native/engine
(cd app && "$FLUTTER" build macos --release --dart-define=APP_VERSION="$VER" --dart-define=BUILD="$BUILD" --dart-define=BUILD_DATE="$DATE")
if [ "${1:-}" != "--no-instalar" ]; then
  pkill -x "NORYXS Terminal" || true
  ditto "app/build/macos/Build/Products/Release/NORYXS Terminal.app" "/Applications/NORYXS Terminal.app"
  echo "Instalada en "/Applications/NORYXS Terminal.app" ($VER, $BUILD, $DATE)"
fi
