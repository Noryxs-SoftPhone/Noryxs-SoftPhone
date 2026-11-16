#!/usr/bin/env bash
# Compila whisper.cpp (v1.9.5, MIT) como bibliotecas estáticas en third_party/whisper.cpp/build.
# El motor (native/engine) las enlaza para la transcripción local de grabaciones.
# Uso: packaging/compilar_whisper.sh   (macOS arm64, Linux x64 o MSYS2 UCRT64 en Windows)
set -euo pipefail
cd "$(dirname "$0")/.."
WH=third_party/whisper.cpp
# Comprobación: si cmake no arranca (p. ej. le falta una DLL en MSYS2), decirlo claramente
cmake --version >/dev/null 2>&1 || { echo "ERROR: cmake no está instalado o no arranca"; exit 1; }
[ -d "$WH" ] || git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp "$WH"
EXTRA=()
case "$(uname -s)" in
  Darwin) EXTRA+=(-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0) ;;
  # x64: AVX2/FMA (cualquier PC de 2013 en adelante); sin ellas sería varias veces más lento
  MINGW*|MSYS*) EXTRA+=(-G Ninja -DGGML_BLAS=OFF -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON) ;;
  *) EXTRA+=(-DGGML_BLAS=OFF)
     [ "$(uname -m)" = x86_64 ] && EXTRA+=(-DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON) ;;
esac
cmake -S "$WH" -B "$WH/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_METAL=OFF -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON "${EXTRA[@]}"
cmake --build "$WH/build" --config Release -j 8
# Las bibliotecas acaban en carpetas distintas según el sistema y el generador (en Windows
# no están en build/ggml/src): se copian todas a build/libs con nombre fijo para los Makefiles.
mkdir -p "$WH/build/libs"
for n in whisper ggml ggml-cpu ggml-base ggml-blas; do
  f=$(find "$WH/build" -path "$WH/build/libs" -prune -o \( -name "lib$n.a" -o -name "$n.a" -o -name "$n.lib" \) -type f -print | head -1)
  if [ -n "$f" ]; then cp "$f" "$WH/build/libs/lib$n.a"; elif [ "$n" != ggml-blas ]; then echo "ERROR: no se encuentra la biblioteca $n"; find "$WH/build" -name "*.a"; exit 1; fi
done
ls -l "$WH/build/libs"
echo "whisper.cpp listo en $WH/build"
