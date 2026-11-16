# NORYXS Virtual SIP Terminal

Teléfono IP virtual multilínea, premium y minimalista, para **macOS, Windows y Linux** (y versión de pruebas para **iPhone**).
Se comporta como un terminal físico Yealink / Fanvil / Grandstream, pero instalado en el ordenador, y se conecta **directamente** a centralitas **FreePBX / Asterisk** con extensiones SIP.

> **No es** un panel de administración de centralitas, ni un CRM, ni un dashboard. Es un teléfono.

- Interfaz: **Flutter / Dart** (escritorio y móvil).
- Motor telefónico: **PJSIP 2.17 nativo en C**, accedido por FFI. Una sola instancia PJSUA para todas las cuentas y llamadas.
- Sin servicios en la nube: la app habla directamente con la centralita.

---

## Índice

1. [Funciones](#funciones)
2. [Capturas y diseño](#capturas-y-diseño)
3. [Arquitectura](#arquitectura)
4. [Estructura del repositorio](#estructura-del-repositorio)
5. [Compilar en macOS](#compilar-en-macos)
6. [Compilar para iPhone (pruebas)](#compilar-para-iphone-pruebas)
7. [Windows y Linux](#windows-y-linux)
8. [Compilación automática (GitHub Actions)](#compilación-automática-github-actions)
9. [Configurar la centralita](#configurar-la-centralita)
10. [Usar NORYXS](#usar-noryxs)
11. [Probar sin interfaz: `nx_cli`](#probar-sin-interfaz-nx_cli)
12. [Seguridad](#seguridad)
13. [Estado del proyecto](#estado-del-proyecto)
14. [Documentación](#documentación)
15. [Licencias](#licencias)

---

## Funciones

### Telefonía
| Función | Detalle |
|---|---|
| **Varias líneas SIP** | Mínimo 2 garantizadas, arquitectura para 8. Cada línea = una cuenta/extensión con su registro, identidad y estado |
| **Varias llamadas a la vez** | Por línea y entre líneas. Contestar, llamar o recuperar retiene automáticamente la llamada activa (nunca la corta) |
| **Aislamiento de audio** | Solo la llamada activa se conecta a la tarjeta de sonido; al retener se desconecta *antes* del re-INVITE |
| Retener / recuperar / alternar | SIP hold (`sendonly`), la centralita pone su música de espera |
| **Transferencias** | Ciega (REFER) y atendida (REFER + Replaces) con consulta, completar o cancelar y recuperar |
| **Conferencia local a 3** | Une las dos llamadas en el puente de PJSIP; *Dividir* devuelve una a espera |
| DTMF | RFC 4733 |
| Silenciar, volumen, dispositivos | Micrófono / altavoz / auriculares USB y Bluetooth, cancelación de eco |
| **Grabación local** | Botón REC, WAV en `Documentos/NORYXS Grabaciones` |
| **Telemetría RTP** | Jitter, pérdida, RTT y **MOS** en vivo pulsando el indicador de códec |
| Códecs | G.722 (HD), Opus, G.711 A-law, G.711 µ-law |

### Funciones de centralita
| Función | Detalle |
|---|---|
| **Buzón por línea (MWI, RFC 3842)** | Contador dorado en la cabecera, "Buzón (N)" en cada línea, pestaña Buzón, `*97` |
| **Teclas BLF** | Suscripción `dialog`: verde libre, rojo ocupada, dorado latiendo sonando → **captura dirigida** `**ext` |
| **Aparcamiento** | "Aparcar 71" (transferencia a 70) y tecla de órbita que parpadea en ámbar y recupera con un toque |
| **No molestar** | Local (486 Busy Here) + FreePBX `*78/*79` |
| **Desvíos** | Siempre `*72`, si ocupado `*90`, si no contesta `*52` — en la centralita, funcionan con el ordenador apagado |
| **Cola de llamadas** | Panel lateral **"En espera"** con las llamadas de la cola FreePBX: Atender (con autocontestación), Transferir, Al buzón, Colgar |

### Experiencia
- **Doble aviso de llamada entrante**: franja oscura integrada en el terminal si está a la vista; **tarjeta flotante nativa** sobre el escritorio si está minimizado o detrás de otra app.
- Timbre generado por PJSIP (3 tonos), aviso suave de llamada en espera si ya hablas.
- Pantalla de arranque animada, logotipo vectorial, tipografías Inter y JetBrains Mono.
- Agenda con favoritos, historial (entrantes, salientes, perdidas) con rellamada por la misma línea.
- **Notas rápidas y etiquetas por llamada** (cifradas en local), filtro por etiqueta y **Copiar resumen** como comprobante.
- **Identificación offline del llamante** (provincia/país, móvil/fijo) y **última nota antes de descolgar**.
- Botón en la cabecera para **mostrar/ocultar el panel de cola**.
- Contraseñas en el **Llavero del sistema**, nunca en ficheros ni en logs.
- **Mac:** al cerrar la ventana sigue en la **barra de menús** recibiendo llamadas, y se abre sola al iniciar sesión.
- **iPhone:** sigue conectado en segundo plano y avisa con una **notificación** con Contestar / Silenciar / Rechazar.
- Durante una llamada, el teclado (en pantalla y físico) **envía tonos DTMF** automáticamente (menús de voz, buzón).

---

## Capturas y diseño

El diseño de referencia es el HTML del cliente: [`docs/diseno/noryxs_virtual_sip_terminal-3.html`](docs/diseno/noryxs_virtual_sip_terminal-3.html) (ábrelo en el navegador).
Fondo blanco, grises claros, texto oscuro y detalles dorados sutiles (`#C5A059`), botones redondeados con efecto táctil.

---

## Arquitectura

```
┌───────────────────────── Flutter (Dart) ─────────────────────────┐
│ UI: terminal · buzón · contactos · historial · SIP · panel cola  │
│ Gestores (ChangeNotifier):                                       │
│  SipAccountManager · SipRegistrationManager · MultiLineManager   │
│  CallSessionManager · CallStateMachine · CallTransferManager     │
│  DtmfManager · AudioDeviceManager · ContactManager               │
│  CallHistoryManager · NotificationManager · VoicemailManager     │
│  BlfManager · PbxFeatureManager · QueueManager (AMI)             │
│ SipEngine (fachada) ──► native_bindings.dart (FFI, sin paquetes) │
└───────────────▲──────────────────────────┬───────────────────────┘
   eventos JSON │ NativeCallable.listener  │ llamadas C
┌───────────────┴──────────────────────────▼───────────────────────┐
│ Motor nativo C: libnoryxs_engine (noryxs_engine.h)               │
│  cuentas · llamadas · hold con aislamiento · REFER · DTMF        │
│  MWI · BLF · DND · conferencia · grabación · stats/MOS · timbre  │
│  Llavero (Security.framework)                                    │
└───────────────────────────────▲──────────────────────────────────┘
                                │
                     PJSIP 2.17 (PJSUA) + OpenSSL + Opus
                                │ SIP UDP/TCP/TLS · RTP/SRTP
                         FreePBX / Asterisk
```

Principios (no reabrir sin motivo):
- **El núcleo nativo es la fuente de verdad** del estado SIP; Dart traduce sus eventos con `CallStateMachine` y bloquea operaciones incompatibles.
- **Sin dependencias de pub.dev**: FFI con `malloc/free` de libc, estado con `ChangeNotifier`, persistencia en JSON.
- **Eventos del motor** (JSON con `type`): `ready`, `reg`, `incoming`, `call`, `xfer`, `replaced`, `transport`, `log`, `mwi`, `blf`, `dnd_rejected`, `conf`, `rec`.

---

## Estructura del repositorio

```
README.md                         este fichero
docs/
  ESPECIFICACION.md               especificación original del cliente
  ROADMAP.md                      fases, estado y pendientes
  GUIA_CONFIGURACION_CENTRALITA.md   qué configurar en la FreePBX del cliente
  diseno/                         diseño HTML de referencia
native/engine/
  include/noryxs_engine.h         API C pública (contrato con Dart)
  src/noryxs_engine.c             motor sobre PJSUA
  src/nx_secret_mac.c             Llavero (macOS / iOS)
  tools/nx_cli.c                  cliente de terminal para probar sin interfaz
  pjsip_config_site.h             config_site de PJSIP (escritorio)
  pjsip_config_site_ios.h         config_site de PJSIP (iOS)
  Makefile / Makefile.ios
app/                              aplicación Flutter
  lib/engine/                     FFI + fachada SipEngine
  lib/core/                       modelos, máquina de estados, gestores
  lib/ui/                         pantallas y componentes
  assets/fonts/                   Inter + JetBrains Mono (OFL)
  macos/ ios/ windows/ linux/     plataformas
pbx/
  configurar_extensiones.php      script de alta de extensiones de prueba en FreePBX
.github/workflows/build.yml       compilación automática
```

`third_party/` (PJSIP) no se versiona: se descarga y compila (ver abajo).

---

## Compilar en macOS

Requisitos: macOS en Apple Silicon, Xcode, [Flutter](https://docs.flutter.dev/get-started/install/macos) (estable) y Homebrew.

```bash
brew install openssl@3 opus pkgconf
```

### 1. PJSIP 2.17

```bash
mkdir -p third_party && cd third_party
git clone --depth 1 --branch 2.17 https://github.com/pjsip/pjproject.git
cd pjproject
cp ../../native/engine/pjsip_config_site.h pjlib/include/pj/config_site.h
./configure --prefix=$PWD/../pjsip-install \
  --with-ssl=$(brew --prefix openssl@3) --with-opus=$(brew --prefix opus) \
  --disable-video --disable-v4l2 --disable-sdl --disable-ffmpeg \
  --disable-openh264 --disable-libyuv --disable-libwebrtc CFLAGS="-O2 -fPIC"
make -j8 && make install          # no usar 'make dep'
cd ../..
```

### 2. Motor nativo

```bash
cd native/engine && make && cd ../..
```
Genera `build/libnoryxs_engine.a` (todo PJSIP + OpenSSL + Opus dentro), `libnoryxs_engine.dylib` y `nx_cli`.

### 3. App

```bash
cd app
flutter build macos --release
# instalar:
ditto "build/macos/Build/Products/Release/NORYXS Terminal.app" "/Applications/NORYXS Terminal.app"
```

Notas:
- El motor se enlaza **dentro del ejecutable** (`-force_load` en `app/macos/Runner/Configs/Noryxs.xcconfig`); Dart lo usa con `DynamicLibrary.process()`.
- Solo **arm64** (OpenSSL/Opus de Homebrew son arm64).
- **Sin App Sandbox**: con firma ad-hoc el sandbox impide usar el Llavero. Tras recompilar, macOS puede pedir permiso para leer el Llavero.
- Datos de la app: `~/Library/Application Support/NORYXS/`.
- Regenerar iconos: `flutter test test/gen_icon_test.dart`.

---

## Compilar para iPhone (pruebas)

```bash
# PJSIP para iOS (sin OpenSSL ni Opus por ahora → sin TLS en iOS)
cd third_party
cp -R pjproject pjproject-ios && cd pjproject-ios && make distclean || true
cp ../../native/engine/pjsip_config_site_ios.h pjlib/include/pj/config_site.h
ARCH="-arch arm64" MIN_IOS="-miphoneos-version-min=15.0" ./configure-iphone \
  --prefix=$PWD/../pjsip-install-ios --disable-ssl --disable-opus --disable-video \
  --disable-sdl --disable-ffmpeg --disable-openh264 --disable-libyuv --disable-libwebrtc
make -j8 && make install && cd ../..

# Motor
cd native/engine && make -f Makefile.ios && cd ../..

# App (firmada con el equipo configurado en Xcode)
cd app && flutter build ios --release
xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --terminate-existing --device <UDID> com.noryxs.noryxsTerminal
```

La primera vez: activar *Modo de desarrollador* en el iPhone, emparejar (`xcrun devicectl manage pair --device <UDID>`) y confiar en el desarrollador en *Ajustes → General → VPN y gestión de dispositivos*.

Funcionamiento en iPhone:
- **Red:** necesita la VPN **NetBird** si la centralita está en otra red (`192.168.1.x`).
- **Segundo plano:** sesión de audio en silencio + notificación local de llamada entrante (`ios/Runner/AppDelegate.swift`). No funciona si se cierra la app deslizándola ni tras reiniciar.
- **Cuenta gratuita de Apple:** la app caduca a los 7 días; sin PushKit/CallKit (pantalla de llamada nativa con la app cerrada → Apple Developer Program de pago).
- Sin TLS ni Opus; el panel de cola lateral no cabe en la pantalla.
- Diagnóstico: `Application Support/NORYXS/startup.log` dentro del contenedor (`xcrun devicectl device copy from --domain-type appDataContainer …`).

---

## Windows y Linux

El motor es el mismo C sobre PJSIP; solo cambia el guardado de secretos (`nx_secret_portable.c`):
Windows → Administrador de credenciales; Linux → libsecret (GNOME Keyring/KWallet). Las notas se cifran
con OpenSSL en el mismo formato que en macOS.

**Linux** (Ubuntu/Debian):
```bash
sudo apt install build-essential pkg-config libssl-dev libopus-dev libasound2-dev libsecret-1-dev uuid-dev clang cmake ninja-build libgtk-3-dev
cd third_party/pjproject && cp ../../native/engine/pjsip_config_site.h pjlib/include/pj/config_site.h
./configure --prefix=$PWD/../pjsip-install --disable-video --disable-v4l2 --disable-sdl --disable-ffmpeg --disable-openh264 --disable-libyuv --disable-libwebrtc CFLAGS="-O2 -fPIC" && make -j && make install
cd ../../native/engine && make -f Makefile.linux
cd ../../app && flutter build linux --release      # → build/linux/x64/release/bundle
cd .. && packaging/linux/build_deb.sh            # → <app>_<versión>_amd64.deb  (sudo apt install ./….deb)
```

**Windows** (PJSIP y motor con MSYS2 UCRT64; la app con Flutter/Visual Studio):
```bash
# En la consola "MSYS2 UCRT64":
pacman -S make git mingw-w64-ucrt-x86_64-{gcc,openssl,opus,pkgconf}
cd third_party/pjproject && cp ../../native/engine/pjsip_config_site.h pjlib/include/pj/config_site.h
./configure --prefix=$PWD/../pjsip-install --with-ssl=/ucrt64 --with-opus=/ucrt64 --disable-video --disable-v4l2 --disable-sdl --disable-ffmpeg --disable-openh264 --disable-libyuv --disable-libwebrtc && make -j && make install
cd ../../native/engine && make -f Makefile.win    # → build-win/noryxs_engine.dll autocontenida
# En PowerShell:
cd app; flutter build windows --release           # → build\windows\x64\runner\Release
```

Integración de escritorio (igual que en macOS):
- **Tarjeta flotante** de llamada entrante arriba a la derecha cuando la ventana está minimizada, oculta o
  detrás de otra app (Contestar / Silenciar / Rechazar). Windows: `windows/runner/nx_desktop.cpp` (GDI+);
  Linux: `linux/runner/nx_desktop.cc` (GTK). En Linux con Wayland el compositor decide la posición.
- **Icono en la bandeja** (Abrir / Salir). Cerrar la ventana la oculta y sigue recibiendo llamadas.
  Linux: AppIndicator (Ubuntu/GNOME) o GtkStatusIcon.
- **Panel lateral de cola**: ensancha la ventana como en macOS.
- **Abrir al iniciar sesión**: Windows → registro `HKCU\...\Run`; Linux → `~/.config/autostart/noryxs-terminal.desktop`.
- **Instancia única** y aviso `wake` al reanudar tras suspender (Windows `WM_POWERBROADCAST`, Linux logind).

CI (`.github/workflows/build.yml`): jobs macOS, Windows y Linux al integrar en `main`;
cada uno publica su paquete como artefacto.

---

## Compilación automática (GitHub Actions)

[`.github/workflows/build.yml`](.github/workflows/build.yml) compila al integrar en `main` (pull request desde `developer`) o a mano desde Actions:

| Job | Qué hace | Resultado |
|---|---|---|
| `macos` | PJSIP 2.17 + motor + `flutter build macos --release` | Artefacto `NORYXS-Terminal-macOS.zip` |
| `windows` | PJSIP + motor con MSYS2 UCRT64 + `flutter build windows --release` | Artefacto `NORYXS-Terminal-Windows.zip` |
| `linux` | PJSIP + motor (gcc) + `flutter build linux --release` | Artefacto `NORYXS-Terminal-Linux.tar.gz` |

PJSIP se guarda en caché entre ejecuciones para acelerar.

---

## Configurar la centralita

Toda la configuración necesaria en FreePBX (extensiones, Call Waiting, transferencias, buzón, BLF, aparcamiento, desvíos, No molestar, cola, AMI, códecs, TLS/SRTP, fail2ban, lista de verificación y solución de problemas) está en:

➡️ **[docs/GUIA_CONFIGURACION_CENTRALITA.md](docs/GUIA_CONFIGURACION_CENTRALITA.md)**

Resumen mínimo: una extensión PJSIP por línea con *Max Contacts ≥ 2*, *Allow Subscriptions = Yes*, buzón activo, Call Waiting activo, `direct_media=no` y RTP 10000–20000/UDP abierto.

---

## Usar NORYXS

1. **SIP → Línea 1**: nombre, extensión, contraseña, servidor, puerto, transporte → *Guardar y Probar Registro*. Repite para la Línea 2.
2. **Terminal**: elige la línea de salida con las píldoras "Salida por", marca y pulsa *Llamar*.
3. Durante una llamada: Retener / Transferir / Silenciar / Alternar o DTMF / Conferencia o Aparcar / Colgar; **REC** y el indicador **ⓘ** (calidad) junto al códec.
4. **Cabecera**: DND, Desvío (panel), Buzón (contador), Audio (dispositivos, volumen, tono, avisos).
5. **SIP → Teclas rápidas**: extensiones BLF y órbitas de aparcamiento.
6. **SIP → Panel de cola**: servidor AMI, puerto, colas, usuario y contraseña (Llavero).

---

## Probar sin interfaz: `nx_cli`

```bash
native/engine/build/nx_cli cuentas.conf [-v] [-null]
```
`cuentas.conf` (nunca se sube a git): `nombre|usuario|contraseña|servidor|puerto|udp/tcp/tls|srtp(0/1/2)`

Comandos: `call <acc> <num>`, `answer <cid>`, `reject`, `hangup`, `hold`, `unhold`, `dtmf <cid> <dígitos>`, `xfer <cid> <num>`, `axfer <cid> <cid2>`, `conf`, `split <cid>`, `rec <cid> <ruta.wav>`, `recstop`, `stats <cid>`, `dnd 0|1`, `blf <acc> <ext>`, `mute`, `devs`, `codecs`, `state`, `quit`.

---

## Diagnóstico

| Qué | Dónde |
|---|---|
| Informes de cierre (Mac) | `~/Library/Logs/DiagnosticReports/NORYXS Terminal-*.ips` |
| Datos y configuración (Mac) | `~/Library/Application Support/NORYXS/` (`accounts.json`, `queue.json`, `blf.json`…; sin contraseñas) |
| Arranque (iPhone) | `startup.log` en el contenedor de la app |
| Centralita | `asterisk -rx "pjsip show contacts"`, `/var/log/asterisk/full`, `queue show 400`, `manager show connected` |
| Motor sin interfaz | `nx_cli cuentas.conf -v` (trazas SIP con cabeceras de autenticación ocultas) |

## Seguridad

- Contraseñas SIP y AMI en el **Llavero** (macOS/iOS). Nunca en JSON ni en logs; las cabeceras `Authorization`/`WWW-Authenticate` se ocultan en las trazas SIP.
- SIP TLS + SRTP (escritorio). Verificación de certificados configurable.
- Panel de cola con **usuario AMI limitado** (`read=call,agent`, `write=call`) y ACL por red; nunca el usuario interno de FreePBX.
- No se usan credenciales de administrador de FreePBX.
- Ficheros de credenciales (`*.conf`, `pbx/*.local*`) excluidos de git.

---

## Estado del proyecto

Ver **[docs/ROADMAP.md](docs/ROADMAP.md)**. A fecha de 15/11/2026:

- ✅ Motor completo y probado con llamadas reales contra **FreePBX 17 + Asterisk 22**: registro de varias líneas, llamadas con nombre, G.722 (MOS 4.4), DTMF, retención con aislamiento, conferencia, grabación, DND, cola con espera y entrega.
- ✅ App macOS instalada con el diseño del cliente, doble aviso de llamada, panel de cola, buzón con MWI real.
- ✅ Versión iPhone de pruebas instalada (segundo plano con notificación).
- ✅ Corregidos los cierres repentinos de la app (avisos BLF) y el teclado DTMF en llamada.
- ✅ Mac en la barra de menús y arranque al iniciar sesión.
- ⏳ Batería completa de las 15 pruebas obligatorias con dos líneas en la app (ver tabla en el roadmap).
- ⏳ Windows y Linux · PushKit/CallKit en iPhone · lista de mensajes de voz por IMAP.

---

## Documentación

| Documento | Para quién |
|---|---|
| [README.md](README.md) | Todos: visión general y compilación |
| [docs/MANUAL_USUARIO.md](docs/MANUAL_USUARIO.md) | Usuario final: cómo usar cada función |
| [CHANGELOG.md](CHANGELOG.md) | Historial detallado de cambios y correcciones |
| [docs/GUIA_CONFIGURACION_CENTRALITA.md](docs/GUIA_CONFIGURACION_CENTRALITA.md) | Administrador de la centralita del cliente |
| [docs/ESPECIFICACION.md](docs/ESPECIFICACION.md) | Requisitos originales del cliente |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Estado, fases y pendientes |
| [docs/diseno/](docs/diseno/) | Diseño de referencia (HTML) |

---

## Licencias

- **NORYXS Virtual SIP Terminal**: GNU GPL v2 o posterior (`GPL-2.0-or-later`), ver [LICENSE](LICENSE).
- **PJSIP**: GPLv2 (Teluu), enlazado en el motor nativo.
- **Inter** y **JetBrains Mono**: SIL Open Font License 1.1 (`app/assets/fonts/*-OFL.txt`).
- OpenSSL (Apache 2.0) y Opus (BSD).
