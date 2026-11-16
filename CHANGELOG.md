# Registro de cambios — NORYXS Virtual SIP Terminal

Formato: cambios agrupados por fecha, del más reciente al más antiguo. Cada entrada indica **qué cambió**, **por qué** y **cómo se comprobó**.

---

## Linux: llamadas sin audio / no arrancan

- Causa: sin dispositivo elegido, PJSIP usaba el primero de ALSA, normalmente la tarjeta física (`hw:`), que PipeWire/PulseAudio tiene ocupada. Sin sonido la llamada no arranca (ni saliente ni el timbre de la entrante), aunque la línea esté registrada.
- Arreglo: en Linux se prefiere el PCM `default` / `pipewire` / `pulse`. El `.deb` recomienda `pipewire-alsa | libasound2-plugins`.
- Diagnóstico: en Windows y Linux se escribe `engine.log` (trazas SIP sin contraseñas) en la carpeta de datos (Linux `~/.config/noryxs/`, Windows `%APPDATA%\NORYXS\`).
- Linux: terminador del esquema de libsecret corregido (`NULL`).

## Linux en cualquier escritorio (Wayland y X11)

- Bandeja: salía una rueda dentada. El icono se pasaba por ruta completa y el estándar StatusNotifier solo resuelve nombres; ahora se pasa por nombre con `data/` como ruta de tema.
- Aviso de llamada en Wayland: Wayland no permite colocar ventanas ni mantenerlas encima, así que la tarjeta flotante quedaba oculta o mal situada. En Wayland se usa la notificación estándar `org.freedesktop.Notifications` (crítica, con Contestar/Silenciar/Rechazar); en X11 sigue la tarjeta.
- Redimensionar: el tamaño mínimo se pide en la vista de Flutter (`gtk_widget_set_size_request`) en vez de con geometry hints, y la ventana se marca redimensionable.
- `.deb`: el lanzador se llama como el APPLICATION_ID para que Wayland asocie ventana e icono.
- Windows: con la ventana maximizada no se cambia su tamaño al abrir el panel de cola (se superpone).
- Splash: muestra el commit de la compilación para saber qué versión se prueba.

## Ventana y panel de cola en Windows/Linux

- Linux: la ventana no se podía redimensionar (tamaño fijo con min = max). Ahora, como en macOS, es redimensionable con mínimo 440×720 (Windows igual, con `WM_GETMINMAXINFO`).
- El botón de cola no mostraba el panel si la ventana no se podía ensanchar (maximizada, en mosaico, Wayland): la interfaz solo lo pintaba con ≥ 760 px. Ahora, si no cabe al lado, se abre superpuesto desde la derecha (también sirve en iPhone).

## CI: arreglos de compilación y paquete .deb

- Windows: PJSIP 2.17 no compila `ssl_sock_ossl.c` con OpenSSL 4.x, que es el que trae ahora MSYS2 (4.1). Se fija OpenSSL 3.6.5 del repositorio oficial de MSYS2 (`pacman -U`), además de tolerar avisos de tipos de GCC 14+.
- Linux: con PJSIP restaurado de caché el motor no encontraba `pjsua.h` (el `.pc` guardaba `.../pjproject/../pjsip-install`). Los Makefiles limpian esas rutas y PJSIP se instala con prefijo absoluto.
- macOS: el Flutter más nuevo de GitHub marca `material.dart` como obsoleto y `flutter analyze` fallaba por avisos informativos. Flutter fijado a 3.47.7 (el del Mac) y `--no-fatal-infos`.
- Linux: el artefacto es ahora un `.deb` (`packaging/linux/build_deb.sh`): app en `/opt`, lanzador en el menú, icono y dependencias.

## Windows y Linux (paridad con macOS)

- Motor: `nx_secret_portable.c` (Administrador de credenciales de Windows / libsecret en Linux; notas cifradas con OpenSSL en el mismo formato `v1:` que macOS). `Makefile.win` (MSYS2 UCRT64, DLL autocontenida) y `Makefile.linux` (.so).
- App: motor cargado por ruta absoluta junto al ejecutable; ventana 466×800; instancia única.
- Integración nativa igual que en macOS: tarjeta flotante de llamada entrante (Windows GDI+ `nx_desktop.cpp`, Linux GTK `nx_desktop.cc`), icono en la bandeja (cerrar oculta), panel lateral de cola que ensancha la ventana, abrir al iniciar sesión y `wake` tras suspender.
- CI: jobs macOS, Windows y Linux solo en la rama `developer` (sin iOS, para ahorrar minutos).
- Prueba: compilación validada en GitHub Actions. Llamadas en Windows/Linux pendientes de probar en un PC.

## 2026-11-15 (noche) — Anexo 2: productividad en la llamada

Especificación: `docs/ESPECIFICACION.md › Anexo 2`.

### ✨ Notas rápidas por llamada (cifradas)
- Bloque plegable **"Añadir nota / Nota y etiquetas"** bajo los controles de la llamada activa y en cada entrada del historial (se despliega al tocarla). 2 líneas, máx. 280 caracteres, se guarda sola al escribir.
- Cada registro del historial tiene ahora un **identificador único** (`HistoryEntry.id`); la nota escrita durante la llamada pasa a ese registro al colgar.
- **Cifrado**: `nx_seal` / `nx_unseal` en el motor (AES-256-CBC + HMAC-SHA256, *encrypt-then-MAC*, IV aleatorio, comparación en tiempo constante) con clave aleatoria de 64 bytes en el Llavero (`notes_key_v1`). Se guardan en `notes.json`; `history.json` no contiene notas. Un registro manipulado se descarta. "Borrar historial" borra también las notas.
- Probado: cifrado/descifrado correcto, texto no legible en el fichero, manipulación rechazada.

### ✨ Etiquetas con un clic
- 4 píldoras de color bajo la nota: `Presupuesto` (dorado), `Urgente` (rojo), `Devolver llamada` (azul), `Resuelto` (verde). Nombres configurables en **SIP › Etiquetas de llamada** (`tags.json`).
- Historial: puntos de color en cada llamada etiquetada y **filtro por etiqueta**.

### ✨ Copiar resumen (comprobante)
- Botón **Copiar resumen** en cada llamada del historial desplegada → portapapeles:
  `[NORYXS SIP] 15/11/2026 17:15 • Ext. 201 → Laura Gómez (+34 612 849 310) (Saliente · Duración: 04:18) | Etiquetas: Presupuesto | Nota: …`

### ✨ Identificación del llamante (offline)
- `lib/core/phone_info.dart`: formato canónico (`+34…`, `0034…`, `6…` → `+34612…`) usado para agenda, historial y notas; origen sin internet: España por provincia (fijos 9xx/8xx), móvil, 900/901/902/80x/905/70; internacional con bandera para ~200 países y móvil/fijo en los principales; extensiones internas. Sin operador (portabilidad).
- Se muestra bajo el número en la franja de llamada entrante, la pantalla de llamada, el historial, la tarjeta flotante del Mac y la notificación del iPhone.
- **Última nota antes de descolgar**: si el número tiene una llamada anterior con nota o etiquetas, se muestra *"Última nota (12/11): …"* con sus etiquetas.
- Pruebas unitarias: `app/test/phone_info_test.dart` (Barcelona, Madrid, Sevilla, Tenerife, móvil, 900, Francia móvil/fijo, Portugal, R. Dominicana, Reino Unido, extensión interna).

### ✨ Botón para mostrar/ocultar el panel de cola
- Icono en la cabecera (junto al buzón), con el número de llamadas en espera en dorado; abre el panel aunque no haya nadie en cola y lo cierra. Solo aparece si el panel de cola está activado.

### ✅ Validado con llamadas reales
- Llamada entrante desde el iPhone (ext. 201, ya conectado por NetBird): franja y pantalla muestran *"Extensión interna"*.
- **BLF**: la tecla de la 201 cambió en tiempo real a *Ocupada* (rojo) mientras el iPhone hablaba — primera validación del cambio de estado BLF tras la corrección de los cierres.

---

## 2026-11-15 (tarde) — Estabilidad, barra de menús y segundo plano

### 🐞 Corregido: la app se cerraba de golpe (también en plena llamada)
- **Síntoma:** NORYXS se cerraba sin aviso en cualquier momento, también durante una conversación. El Mac registró **10 informes de cierre** (`~/Library/Logs/DiagnosticReports/NORYXS Terminal-*.ips`), todos idénticos.
- **Causa:** hilo `pjsua_0` → `on_buddy_dlg_event_state` → `pjsua_buddy_get_dlg_event_info()` → `pj_strncpy` → lectura de la dirección `0x0` (`EXC_BAD_ACCESS / SIGSEGV`). En PJSIP 2.17, esa función copia campos del estado de diálogo con **puntero nulo y longitud > 0** cuando Asterisk envía un `NOTIFY` de tipo `dialog-info` sin algunos datos (estado "terminated", órbitas de aparcamiento `*85XX`…). Los avisos BLF llegan en cualquier momento, de ahí que el cierre pareciera aleatorio.
- **Solución:** el motor ya **no llama** a `pjsua_buddy_get_dlg_event_info()`. Usa el callback `on_buddy_evsub_dlg_event_state` y **analiza él mismo el cuerpo XML del `NOTIFY`** (`<dialog direction=…>`, `<state>`, `<remote><identity display=…>`), validando cada campo y longitud (`native/engine/src/noryxs_engine.c`: `xml_text()`, `xml_attr()`, `on_buddy_evsub_dlg_event_state()`).
- **Comprobado:** con FreePBX real, suscripciones BLF a 200, 201 y la órbita 71 (`*8571`): avisos recibidos sin cierres. La app instalada sigue abierta pasado el momento (≈17 s tras registrarse) en el que antes caía.
- ⚠️ **Regla para el futuro:** no volver a usar `pjsua_buddy_get_dlg_event_info()`.

### ✨ Mac: sigue en la barra de menús y arranca al iniciar sesión
- El botón rojo **oculta** la ventana en lugar de salir (`windowShouldClose` → `orderOut`); `applicationShouldTerminateAfterLastWindowClosed = false`.
- Icono de teléfono en la **barra de menús** con *Abrir NORYXS* (⌘O) y *Salir de NORYXS* (⌘Q). Clic en el Dock con la ventana oculta → la vuelve a mostrar.
- **Abrir al iniciar sesión** con `SMAppService.mainApp` (macOS 13+), activado por defecto y conmutable en *Audio y avisos*.
- Con la ventana oculta, las llamadas entrantes muestran la **tarjeta flotante** (contexto B).

### ✨ iPhone: sigue conectado en segundo plano y avisa con notificación
- Al pasar a segundo plano se activa una **sesión de audio en silencio** (`AVAudioSession .playAndRecord` + `mixWithOthers`, `AVAudioPlayer` en bucle a volumen 0) que, junto con `UIBackgroundModes = audio, voip`, mantiene viva la conexión SIP.
- **Notificación local** de llamada entrante con *Contestar* (abre la app y contesta), *Silenciar* y *Rechazar*. Tocar la notificación solo abre la app.
- Limitaciones (cuenta gratuita de Apple): no funciona si se cierra la app deslizándola ni tras reiniciar; la app firmada caduca a los 7 días. La pantalla de llamada nativa con la app cerrada necesita PushKit + CallKit y el Apple Developer Program de pago.

### 🐞 Corregido: el teclado no enviaba tonos durante la llamada (menús del buzón `*97`)
- **Síntoma:** al llamar al buzón, las opciones marcadas no hacían nada (Mac e iPhone).
- **Diagnóstico:** el motor y la centralita funcionaban: el registro DTMF de Asterisk mostraba `DTMF end '1' received on PJSIP/202…` (`rfc4733`, `telephone-event/8000` negociado). El fallo era de la interfaz: en llamada, el teclado escribía en el campo de marcar salvo que se activara antes el modo "DTMF".
- **Solución:** con una llamada activa, el teclado en pantalla **y el teclado físico** envían DTMF automáticamente; la pantalla muestra **"Tonos enviados"** con los dígitos.

### 📄 Documentación
- `CHANGELOG.md` (este fichero), `docs/MANUAL_USUARIO.md`, README, ROADMAP y guía de la centralita actualizados.

Commits: `460842a` (DTMF), `c13dde2` (cierres BLF, barra de menús, segundo plano iPhone).

---

## 2026-11-15 (mediodía) — Centralita nueva, cola de llamadas e iPhone

### Centralita de pruebas FreePBX 17
- La centralita antigua (`192.168.1.10`, contenedor LXC Debian 13) no tenía FreePBX operativo. Se recreó el contenedor con **Debian 12** y se instaló **FreePBX 17.0.33 + Asterisk 22.11** con el instalador oficial (`--opensourceonly --nochrony`). El instalador se detuvo al quitar un módulo comercial (`oracle_connector`); se relanzó una copia con ese paso tolerante a errores (`--skipversion`) y terminó correctamente.
- Extensiones **200** (Linea Principal), **201** (Atencion Directa), **202** (Soporte): PJSIP, buzón, Call Waiting, `max_contacts=3`, suscripciones, códecs `g722&ulaw&alaw&opus`. Credenciales generadas en `pbx/credenciales.local.txt` (no versionado).
- Aparcamiento `70` / órbitas `71–78`; códigos `*72 *73 *90 *52 *78 *79 *97 **` verificados.
- **fail2ban** bloqueó el Mac por las conexiones SSH seguidas → desbloqueo desde consola, conexión SSH compartida (`ControlMaster`) y redes internas en `ignoreip`.
- Probado desde el Mac: registro de 200/201/202, llamada 200→201 con nombre, G.722 con MOS 4.4, DTMF.

### Cola de llamadas
- Cola FreePBX **400** "Cola NORYXS": agente 200, `ringall`, *Skip Busy Agents* = *Yes + (ringinuse=no)*, música, posición cada 30 s, 300 s → buzón 200.
- **AMI** abierta a la LAN mediante `manager_custom.conf` (`[general](+) bindaddr=0.0.0.0`) y usuario **`noryxs`** limitado (`read=call,agent`, `write=call`, ACL a redes internas). Comprobado: `QueueStatus` funciona y los comandos de sistema se rechazan.
- App: `QueueManager` (cliente AMI en Dart, sin paquetes) y **panel lateral "En espera"**: posición, contador de espera, *Atender* (redirige a tu extensión y la contesta sola), *Transferir*, *Al buzón*, *Colgar*. La ventana se ensancha 320 pt.
- Probado: con la 200 ocupada (en pausa), dos llamadas en cola aparecen en el panel con sus contadores.

### Documentación para clientes
- `docs/GUIA_CONFIGURACION_CENTRALITA.md`: todo lo que hay que configurar en FreePBX. Corrección: en FreePBX 17 *Extensions* está en **Connectivity**; el BLF de las órbitas es `*85XX`.

### iPhone (pruebas)
- PJSIP 2.17 para iOS arm64 (sin OpenSSL ni Opus), motor `Makefile.ios`, plataforma iOS en Flutter, permisos (micrófono, red local, audio/voip), iconos.
- Instalado en iPhone 15 Pro con `devicectl` (emparejamiento por cable, Modo de desarrollador, confianza en el desarrollador).
- **Corregido:** se quedaba en la pantalla de arranque → en iOS no existe `HOME`; la carpeta de datos se calcula ahora desde la carpeta temporal (`appHome()`). Añadido `startup.log` y aviso de error en el splash (nunca vuelve a quedarse colgado).
- **Red:** el iPhone necesita la VPN **NetBird** para llegar a `192.168.1.x` (la centralita no recibía ningún intento de registro).

### Repositorio y CI
- Repositorio git local (`main`), README completo, `.github/workflows/build.yml` (macOS con artefacto, iOS sin firmar). `Makefile` portátil (detecta el sufijo de PJSIP y Homebrew).

---

## 2026-11-15 (mañana) — Anexo técnico y diseño del cliente

- **Motor:** MWI (RFC 3842), BLF (`dialog`), DND local (486), conferencia local a 3, grabación WAV, telemetría RTP/MOS, cuenta local para llamadas IP directas, 3 tonos de llamada.
- **Interfaz** rehecha según el HTML del cliente (`docs/diseno/`): Inter + JetBrains Mono, navegación inferior de 5 pestañas, cabecera DND/Desvío/Buzón/Audio, teclas BLF, LCD con controles 3×2, ⓘ telemetría, REC, transferencia integrada.
- **Avisos:** franja de llamada entrante integrada (contexto A) y tarjeta flotante nativa SwiftUI (contexto B).
- Splash premium, logo vectorial e icono; botones de ventana de macOS en franja propia sobre la cabecera; sandbox desactivado para poder usar el Llavero con firma ad-hoc.

## 2026-11-14 — Primera versión

- PJSIP 2.17 compilado (TLS, SRTP, Opus, G.722); motor C con cuentas, llamadas, retención con aislamiento de audio, transferencias, DTMF, audio, códecs, Llavero; `nx_cli`.
- App Flutter macOS con terminal, agenda, historial y cuentas SIP.
