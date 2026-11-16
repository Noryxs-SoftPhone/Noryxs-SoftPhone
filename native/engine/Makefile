# NORYXS engine - build para macOS (arm64)
# Genera:
#   build/libnoryxs_engine.a      (para enlazar estáticamente en la app Flutter)
#   build/libnoryxs_engine.dylib  (para pruebas)
#   build/nx_cli                  (herramienta de prueba en terminal)

ROOT      := $(abspath ../..)
PJ        := $(ROOT)/third_party/pjsip-install
# Sufijo de las bibliotecas de PJSIP (p.ej. aarch64-apple-darwin27.2.0); se detecta solo
TRIPLE    := $(patsubst $(PJ)/lib/libpj-%.a,%,$(firstword $(wildcard $(PJ)/lib/libpj-*.a)))
OPENSSL   ?= $(shell brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)
OPUS      ?= $(shell brew --prefix opus 2>/dev/null || echo /opt/homebrew/opt/opus)
# Transcripción local: whisper.cpp compilado en third_party/whisper.cpp/build (estático)
WH        := $(ROOT)/third_party/whisper.cpp
# Opcional: sin compilar (packaging/compilar_whisper.sh) el motor sale sin nx_transcribe.
ifneq ($(wildcard $(WH)/build/src/libwhisper.a),)
WH_A      := $(WH)/build/src/libwhisper.a $(WH)/build/ggml/src/libggml.a $(WH)/build/ggml/src/libggml-base.a \
             $(WH)/build/ggml/src/libggml-cpu.a $(wildcard $(WH)/build/ggml/src/ggml-blas/libggml-blas.a)
WH_O      := build/nx_transcribe.o
endif

CC        := clang
CFLAGS    := -O2 -Wall -fPIC -fvisibility=hidden -Iinclude -I$(PJ)/include -I$(WH)/include -I$(WH)/ggml/include \
             -DPJ_AUTOCONF=1 -DPJ_IS_BIG_ENDIAN=0 -DPJ_IS_LITTLE_ENDIAN=1

PJLIBS    := pjsua pjsip-ua pjsip-simple pjsip pjmedia-codec pjmedia-audiodev \
             pjmedia pjnath pjlib-util srtp resample speex g7221codec pj
PJ_A      := $(foreach l,$(PJLIBS),$(PJ)/lib/lib$(l)-$(TRIPLE).a)
EXT_A     := $(OPENSSL)/lib/libssl.a $(OPENSSL)/lib/libcrypto.a $(OPUS)/lib/libopus.a
FRAMEWORKS:= -framework CoreAudio -framework CoreServices -framework AudioUnit \
             -framework AudioToolbox -framework Foundation -framework AppKit \
             -framework Security -framework CoreFoundation -framework Accelerate -lc++
SYSLIBS   := -lm -lpthread

all: build/libnoryxs_engine.a build/libnoryxs_engine.dylib build/nx_cli

OBJS := build/noryxs_engine.o build/nx_secret_mac.o $(WH_O)

build/%.o: src/%.c include/noryxs_engine.h
	@mkdir -p build
	$(CC) $(CFLAGS) -c $< -o $@

# Biblioteca estática única con PJSIP + OpenSSL + Opus dentro
build/libnoryxs_engine.a: $(OBJS)
	libtool -static -o $@ $(OBJS) $(PJ_A) $(EXT_A) $(WH_A) 2>/dev/null

build/libnoryxs_engine.dylib: $(OBJS)
	$(CC) -dynamiclib -o $@ $(OBJS) $(PJ_A) $(EXT_A) $(WH_A) $(FRAMEWORKS) $(SYSLIBS) \
	      -install_name @rpath/libnoryxs_engine.dylib

build/nx_cli: tools/nx_cli.c build/libnoryxs_engine.a
	$(CC) -O2 -Wall -Iinclude $< build/libnoryxs_engine.a $(FRAMEWORKS) $(SYSLIBS) -o $@

clean:
	rm -rf build

.PHONY: all clean
