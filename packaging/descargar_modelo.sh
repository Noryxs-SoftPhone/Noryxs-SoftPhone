#!/usr/bin/env bash
# Descarga el modelo de transcripción (whisper.cpp Base, cuantizado q5_1, ~57 MB, licencia MIT)
# a app/assets/models/. Solo hace falta una vez por máquina de compilación.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=app/assets/models/ggml-base-q5_1.bin
SHA=a3733eda680ef76256db5fc5dd9de8629e62c5e7
if [ -f "$DEST" ]; then echo "Ya existe $DEST"; exit 0; fi
mkdir -p "$(dirname "$DEST")"
curl -fL --retry 3 -o "$DEST.part" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin
GOT=$( (shasum -a 1 "$DEST.part" 2>/dev/null || sha1sum "$DEST.part") | cut -d' ' -f1)
if [ "$GOT" != "$SHA" ]; then echo "SHA-1 incorrecto ($GOT)"; rm -f "$DEST.part"; exit 1; fi
mv "$DEST.part" "$DEST"
echo "Modelo listo: $DEST"
