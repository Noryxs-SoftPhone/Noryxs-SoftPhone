# Registro de cambios — NORYXS Virtual SIP Terminal

Formato: cambios agrupados por fecha, del más reciente al más antiguo. Cada entrada indica **qué cambió**, **por qué** y **cómo se comprobó**.

---

## CI de Windows: transcripción

- **Fallo**: el job de Windows terminaba con código 127 (comando no encontrado) en el paso nuevo de whisper.cpp y el modelo.
- **Causa**: Git en Windows convierte los `.sh` a CRLF al hacer el checkout; `#!/usr/bin/env bash\r` no existe y bash falla con `\r`.
- **Solución**:
  - `.gitattributes` fuerza LF en `*.sh`, Makefiles y C.
  - La descarga del modelo pasa al bash de Git (curl y sha1sum incluidos) y se añade `curl` a MSYS2.
- **Segundo fallo (127 tras el `git clone` de whisper.cpp)**: el `cmake` de MSYS2 dejaba de funcionar sin dar mensaje.
  - Causa probable: el paso que baja OpenSSL de 4.x a 3.6 (necesario para PJSIP 2.17) quita la DLL de OpenSSL 4 que necesita cmake.
  - Solución: whisper.cpp y el modelo se preparan **antes** de bajar OpenSSL. `compilar_whisper.sh` comprueba primero que cmake arranca y, si no, lo dice claramente.
- **Tercer fallo (enlace del motor)**: `ld: cannot find .../whisper.cpp/build/ggml/src/libggml.a`. En Windows CMake deja las bibliotecas de ggml en otra carpeta.
  - Solución: `compilar_whisper.sh` copia `whisper`, `ggml`, `ggml-cpu`, `ggml-base` (y `ggml-blas` si existe) a `build/libs` con nombre fijo, y avisa si falta alguna.
  - Los tres Makefiles enlazan desde ahí; en Linux y Windows dentro de `--start-group … --end-group`, para que no importe el orden.
- **Prueba**: en macOS, whisper recompilado desde cero con el script nuevo, motor enlazado y transcripción correcta. Windows y Linux, pendientes del siguiente job.

## 16/11/2026 — Fase 8: mejoras

NORYXS incorpora todas las mejoras de la Fase 8 (descritas en las entradas siguientes). Conserva su nombre, su paleta oro/grafito (ahora también en modo oscuro), su logotipo, sus rutas (`NORYXS/`, `Documentos/NORYXS Grabaciones`) y su esquema de enlaces `noryxs:`. Las entradas siguientes describen cada mejora.

- Prueba: `flutter analyze` sin avisos, 18 pruebas en verde, motor compilado con transcripción, app compilada e instalada en macOS.

## Ajustes › Acerca de

- **Qué**: nueva sección *Acerca de* (grupo App), que reúne:
  - La app y su versión.
  - **Compilación**: versión, commit, fecha, sistema, motor de voz, transcripción e interfaz.
  - **Copiar información** para soporte: versión y estado de las líneas, sin contraseñas.
  - **Autor**: Yandry Hernández Acosta, administrador de sistemas y telecomunicaciones, con LinkedIn y el repositorio de GitHub.
  - Qué incluye, privacidad y licencias de cada componente.
  - Firma «© año · Software libre (GPL)».
- **Por qué**: dar a la app la firma de su autor aunque el código sea abierto, y tener a mano la versión exacta instalada para soporte.
- **Cómo**:
  - `lib/ui/about_section.dart`.
  - `lib/core/links.dart` abre enlaces en el navegador del sistema.
  - La fecha de compilación llega por `--dart-define=BUILD_DATE`: la CI la pone en los tres sistemas, y en local la ponen `packaging/compilar_mac.sh` (versión, commit y fecha) y su instalación en /Applications.
  - Textos en es/en/ca.
- **Prueba**: `flutter analyze` sin avisos; compilada con `packaging/compilar_mac.sh` e instalada.

## Colas de llamadas por línea

- **Qué**: cada línea indica las colas de FreePBX que atiende (*Ajustes › Líneas SIP › Colas que atiende*, p. ej. Línea 1 → 400, Línea 2 → 401).
  - El panel *En espera* agrupa las llamadas por cola, con la línea que la atiende.
  - **Atender** y **Al buzón** usan la extensión de esa línea, sin tener que seleccionarla. Las colas sin línea (campo *Otras colas*) siguen usando la línea seleccionada.
- **Por qué**: antes las colas eran una lista única del puesto y Atender siempre iba a la línea seleccionada. Con varias extensiones en un puesto (recepción + reservas) había que acordarse de cambiar de línea antes de atender.
- **Cómo**:
  - `SipAccountConfig.queues` (se guarda en `accounts.json` y viaja en la configuración de puestos).
  - `QueueManager.watched` = colas generales ∪ colas de las líneas activas; se usa para filtrar eventos AMI y para `QueueStatus`. `refreshQueues()` al guardar o borrar una línea (sin reconectar).
  - `AppController.lineForQueue()` (primera línea activa con esa cola; si no hay, la seleccionada) y `queueHasLine()`.
  - Panel lateral agrupado por cola, con etiqueta de línea. Ajustes › Cola: *Colas* pasa a *Otras colas* y aparece el resumen *Colas por línea*.
  - La conexión AMI sigue siendo una por puesto.
- **Prueba**:
  - `test/line_queues_test.dart`: las colas se guardan y se leen; las cuentas antiguas sin colas cargan con la lista vacía.
  - `flutter analyze` sin avisos; 16 pruebas en verde.
  - Compilada e instalada en macOS.
  - Pendiente: probar Atender por la Línea 2 con la cola real (la centralita de pruebas no responde sin VPN).

## Transcripción local de las llamadas grabadas

- **Qué**: al colgar una llamada grabada, la grabación se transcribe sola en el ordenador. El texto aparece bajo el reproductor de la grabación en el Historial (plegado/desplegado, marcas mm:ss, copiar) y **el buscador del historial busca también en lo hablado**, resaltando la coincidencia.
- **Por qué así**: privacidad (el audio de huéspedes no sale del equipo) y la regla de no depender de servidores.
- **Cómo**:
  - Motor: `native/engine/src/nx_transcribe.c`, sobre whisper.cpp v1.9.5 (MIT) enlazado estático.
    - Lee el WAV PCM16 del grabador (cualquier frecuencia/canales) y lo pasa a 16 kHz mono (remuestreo lineal).
    - Decodificación greedy con idioma automático; devuelve texto con `[mm:ss]` por segmento.
    - El modelo se carga una vez y se reutiliza (mutex).
    - API: `nx_transcribe(wav, model, lang, threads)`.
  - Modelo `ggml-base-q5_1.bin` (57 MB) como asset de Flutter (`app/assets/models/`, no versionado: `packaging/descargar_modelo.sh` con comprobación SHA-1).
  - Compilación: `packaging/compilar_whisper.sh` (macOS arm64 con Accelerate; Linux/Windows x64 con AVX2/FMA, sin BLAS). Los Makefiles enlazan whisper solo si está compilado: sin él, el motor sale sin `nx_transcribe` y la app oculta la función (iOS no la incluye).
  - CI: nuevo paso con caché que compila whisper.cpp y descarga el modelo en los tres sistemas.
  - Dart: `TranscriptionManager` (`lib/core/transcription.dart`).
    - Cola en segundo plano (`Isolate.run`), una grabación a la vez, y espera si hay una llamada en curso; usa la mitad de los núcleos (2–6 hilos).
    - Texto cifrado con `nx_seal` en `transcripts.json`; se poda al cargar y al borrar el historial.
    - Al abrir la app retoma las grabaciones de los últimos 7 días sin transcribir.
  - UI: `lib/ui/transcript_view.dart`; nota informativa en Ajustes › Audio; textos en es/en/ca.
- **Prueba**:
  - Voz sintética en castellano a 8 kHz: transcrita correctamente en 1,2 s en un M-series.
  - App real (release macOS) con una entrada de historial de prueba: se generó `transcripts.json` cifrado para ella y para una grabación real de una llamada del mismo día.
  - `flutter analyze` sin avisos.
  - Pendiente: probar Windows y Linux tras la CI.

## Audio más limpio, aviso de mala conexión y perdidas pendientes

- **Reducción de ruido y volumen automático**: en escritorio el motor usa siempre el cancelador de eco Speex por software (`PJMEDIA_ECHO_SPEEX | USE_SW_ECHO`, agresividad moderada), que incluye reducción de ruido (`PJMEDIA_SPEEX_AEC_USE_DENOISE`) y control automático de ganancia (`_USE_AGC`). Antes podía usarse el de la tarjeta, sin esas mejoras. En iPhone se mantiene el procesado de voz de Apple. Motor probado (arranca y reproduce con la nueva configuración); falta oírlo en una llamada real.
- **Aviso de mala conexión**: durante la llamada se mide la red cada 2 s; si la pérdida supera el 3 %, el jitter 50 ms, el retardo 350 ms o el MOS baja de 3,5, aparece "Conexión inestable" junto al códec (el detalle, al pasar el ratón).
- **Perdidas pendientes de devolver**: una perdida queda pendiente mientras la última llamada con ese número sea esa perdida. Contador rojo en la pestaña Historial, filtro "Pendientes de devolver (N)", etiqueta "Pendiente" en la fila y botón "Marcar atendida" (por si se atendió desde otro teléfono). Se quitan solas al devolver la llamada o al volver a hablar con ese número.

## Catalán e idioma según el sistema

- Nuevo idioma **catalán** (`lib/core/i18n_ca.dart`, 476 textos).
- **Automático** (por defecto): idioma preferido del sistema → catalán, castellano o inglés; cualquier otro idioma → **inglés**. Cambia en directo si el usuario cambia el idioma del sistema (`didChangeLocales`).
- Ajustes › Apariencia e idioma: Automático · Español · Català · English.
- Probado con una copia aislada en catalán: captura revisada.

## Acabado premium de la pantalla principal

- Teclado: cifras en trazo fino (Inter 300–400), letras espaciadas, relieve sutil (degradado tarjeta→superficie y sombra suave), respuesta al pulsar (escala 0,965) y borde de acento al pasar el ratón.
- Botón Llamar: color de la marca con degradado discreto, sombra suave y ligera elevación al pasar el ratón.
- Tarjetas de línea: estado "Desconectada" en texto discreto (el punto de color indica el estado), sombra muy suave; los avisos de "Sin red SIP / No registrada" dejan de dominar en rojo.
- Cabecera: iconos propios de trazo fino (luna DND, desvío, buzón, cola, cascos), coherentes con la barra inferior.
- Marcador: número grande en trazo fino; debajo, el contacto de la agenda o el origen del número (p. ej. "Móvil nacional").
- Transición suave (fundido y desplazamiento corto) al cambiar de pestaña.
- Revisado en modo claro y oscuro con una copia aislada.

## Ajustes ordenados, pantalla principal compacta y teclado directo

- **Pestaña Ajustes** (antes "SIP"): menú por secciones (Teléfono, Centralita, Llamadas, App) con Líneas SIP, Audio y tonos, Avisos y escritorio, Teclas BLF, Cola, Etiquetas, WhatsApp, Apariencia e idioma, Configuración de puestos, Actualizaciones y Diagnóstico. El panel de audio de la cabecera queda solo con micrófono, altavoz y volumen. Los códecs pasan a Audio y tonos (son comunes a todas las líneas).
- **Pantalla principal**: teclas BLF en una tira compacta de una fila con el estado por color (desaparece si no hay teclas); la tarjeta de reposo pasa a una franja de una línea con estado y códec (sin repetir la línea de salida).
- **Teclado del ordenador**: en la pestaña Terminal, las cifras se escriben en el marcador sin hacer clic; Intro llama, Borrar corrige, Esc limpia; con llamada envían DTMF. No interfiere al escribir en notas o búsquedas ni en otras pestañas. Probado con pulsaciones simuladas (567 + borrar → 56).
- **Splash** de unos 5,5 s.
- **Habitaciones (CSV) eliminado**: el nombre de cada extensión ya lo envía FreePBX; el del huésped requeriría el PMS.
- **Manual reescrito** (`docs/MANUAL_USUARIO.md`): instalación por sistema, mapa de Ajustes y cada opción explicada para configurarla uno mismo.

## Mejora 6: aviso de actualización (carpeta compartida, sin servidor)

- SIP › Actualizaciones: carpeta compartida (NAS / red). La app lee `latest.json` al arrancar y cada 6 h; si hay versión mayor muestra un aviso con "Instalar" (abre el paquete del sistema).
- `packaging/publicar_en_carpeta.sh <carpeta> <paquetes> [notas]` copia los paquetes y genera `latest.json` (probado).
- CI pasa `APP_VERSION` (de pubspec) a cada compilación.
- Pendiente: comprobar el aviso en pantalla (la captura de prueba no lo mostró en el recorte).

## Mejora 14: WhatsApp (sin servidor)

- Botón **WhatsApp** en la pantalla de llamada (junto a nota y etiquetas) y en cada llamada del historial, solo para números externos.
- Plantillas editables (SIP › Plantillas de WhatsApp; `{nombre}` = nombre del cliente). Se abre WhatsApp Desktop/Web con el chat y el mensaje escrito mediante el enlace oficial `wa.me`; el envío se confirma en WhatsApp. Sin servidor, gratis y sin riesgo de bloqueo del número.
- Descartado WAHA (envío directo) porque necesitaba un servidor: decisión de no depender de ninguno.
- `WhatsAppManager.waNumber` con pruebas (`test/whatsapp_test.dart`).

## Mejora 5: configuración automática de puestos

- SIP › Configuración de puestos › Exportar: pide un PIN y genera un paquete con las líneas (y sus contraseñas), teclas BLF, cola (con la contraseña AMI), etiquetas, habitaciones y códecs. Se puede guardar como fichero `.noryxs`, copiar como enlace `noryxs:provision?d=…` o mostrar como **QR**.
- Importar: desde fichero, enlace, dirección http (p. ej. el futuro servidor interno) o texto pegado, con el PIN. Sustituye la configuración de la app; no toca la centralita.
- Cifrado en el motor: `nx_pin_seal/nx_pin_unseal` — PBKDF2-SHA256 (200 000 iteraciones) + AES-256-CBC + HMAC-SHA256 (CommonCrypto en macOS/iOS, OpenSSL en Windows/Linux). El JSON se comprime (gzip) antes de cifrar. Probado: PIN correcto recupera el contenido; PIN erróneo o paquete alterado se rechazan.
- Generador QR propio (`lib/core/qr.dart`, modo byte, nivel L). Probado generando códigos de 48 a 2 428 caracteres y leyéndolos con el lector de códigos de macOS (Vision): todos idénticos.
- El esquema `noryxs:` abre la importación en macOS, Windows (registrado al arrancar), Linux (`.desktop`) e iPhone (al escanear el QR con la cámara, `SceneDelegate`).
- Pruebas de extracción de paquetes en `test/provisioning_test.dart`.

## Mejora 8: habitaciones

- SIP › Habitaciones › "Importar CSV": extensión, habitación y huésped (separador «;», «,» o tabulador; cabecera opcional y en cualquier orden). Sustituye el directorio anterior (`rooms.json`).
- Las llamadas entrantes, la pantalla de llamada, el historial y el panel de cola muestran "Hab. 214 · Sr. García" cuando el número es una habitación (la agenda tiene prioridad).
- Selector de ficheros nativo en macOS (NSOpenPanel/NSSavePanel), Windows (GetOpenFileName/GetSaveFileName) y Linux (GtkFileChooser), también para la configuración de puestos.
- `parseRoomsCsv` con pruebas (`test/rooms_test.dart`).

## Mejora 13: diagnóstico de red y audio

- Ajustes › Audio y avisos › "Diagnóstico de red y audio": comprueba cada centralita con un SIP OPTIONS (tiempo de respuesta y versión), detecta NAT (la IP con la que te ve la centralita no es la del equipo → aviso de «Local Networks», el caso del hotel), el registro de cada línea con su código de error, los dispositivos de audio y la conexión AMI del panel de cola.
- Botones: "Prueba de eco (*43)", "Repetir" y "Copiar informe" para enviarlo a soporte.
- Probado el OPTIONS contra la centralita real (192.168.1.10: 8 ms, FreePBX 16, sin NAT) y contra centralitas inaccesibles (no responde).

## Mejora 1: atajos de teclado globales y botón de los cascos

- Atajos desde cualquier app: contestar, colgar (o rechazar si solo suena) y silenciar. macOS ⌃⌥A / ⌃⌥H / ⌃⌥M con `RegisterEventHotKey` (sin permisos de accesibilidad); Windows Ctrl+Alt+A / H / M con `RegisterHotKey`. Se activan o desactivan en Ajustes › Audio y avisos.
- Botón de los cascos o tecla reproducir/pausa: contesta si suena y cuelga si hay conversación. Solo se apodera de esa tecla mientras hay una llamada (macOS `MPRemoteCommandCenter`, Windows `VK_MEDIA_PLAY_PAUSE`, Linux reproductor MPRIS `org.mpris.MediaPlayer2.noryxs`).
- Linux (Wayland no permite atajos globales a las apps): órdenes `noryxs-terminal --answer | --hangup | --mute` para asignarlas a atajos del sistema; llegan a la instancia abierta.
- Falta probar con teclado y cascos reales en cada sistema.

## Barra inferior con iconos propios

- Iconos dibujados a medida (`lib/ui/nav_icons.dart`, rejilla de 24, trazo fino homogéneo): terminal de sobremesa, cinta de buzón, tarjeta de contacto, reloj con vuelta atrás y deslizadores de ajustes.
- Pestaña activa: degradado crema→tarjeta, borde y sombra suave en el color de acento (oro), icono con relleno tenue, ligera ampliación animada e indicador superior. Revisado en claro y oscuro.

## Mejora 11: inglés

- Ajustes › Audio y avisos › Idioma: Español, English o Automático (idioma del sistema). Cambia en directo.
- `tr('texto en español', [args])` (`lib/core/i18n.dart`) con el diccionario `lib/core/i18n_en.dart` (≈360 textos); si falta una traducción se muestra el español.
- Los textos se envolvieron con un analizador léxico de Dart (respeta cadenas crudas, interpolaciones anidadas y etiquetas `case`); los comandos AMI, nombres de códec, rutas y trazas internas se dejaron sin traducir a propósito.
- Probado con una copia aislada en inglés: captura revisada.
- Pendiente menor: los textos de las piezas nativas (botones de la tarjeta flotante y menú de la bandeja) siguen en español.

## Mejora 10: modo oscuro

- Ajustes › Audio y avisos › Tema: Claro, Oscuro o Automático (sigue al sistema y cambia en directo).
- `NxColors` pasa de constantes a getters con paleta clara y oscura (oro más luminoso en oscuro); los fondos blancos fijos usan ahora `NxColors.card`.
- Preferencias de interfaz en `ui.json` (`UiPrefs`), cargadas antes de arrancar.
- Probado con una copia aislada (carpeta de datos vacía) en modo oscuro: captura revisada.

## Mejora 7: clic para llamar (tel: / sip: / callto:)

- Al pulsar un número en el navegador, el correo u otra app, NORYXS llama por la línea seleccionada (o la primera registrada). Si la app estaba cerrada, se abre y espera a que una línea registre.
- macOS: esquemas en `Info.plist`, `application(_:open:)` y botón para hacerla app predeterminada (`NSWorkspace.setDefaultApplication`).
- Windows: registro en `HKCU\Software\Classes\Noryxs.Url` + Capabilities/RegisteredApplications y apertura de "Aplicaciones predeterminadas" (Windows exige que el usuario confirme). Una segunda instancia pasa el enlace a la primera con `WM_COPYDATA`.
- Linux: el `.desktop` del `.deb` declara `x-scheme-handler/tel;sip;callto` y `%u`; GApplication recibe el enlace con `open` (también en la instancia abierta); botón con `xdg-mime default`.
- Los enlaces que llegan antes de que la app esté lista se guardan y se entregan después (`urlHandlerReady`).
- `parseDialUrl` con pruebas (`test/dial_url_test.dart`). Ajustes › Audio y avisos › "Usar NORYXS".

## Mejora 12: timbre distinto por línea

- Cada línea puede tener su propio timbre (SIP › Línea › "Timbre de esta línea", con botón para escucharlo); por defecto usa el general.
- Si suenan llamadas de líneas distintas, suena el timbre de la primera; el aviso de llamada en espera no cambia.
- `SipAccountConfig.ringTone` (-1 = general) en `accounts.json`.

## Mejora 2: escuchar las grabaciones desde el historial

- Motor: reproductor de WAV por el altavoz (`nx_play_start/stop/pos/seek`, evento `play` al terminar), nunca enviado a la llamada. Probado con un programa contra el motor: duración 2000 ms, posición a 1 s = 1000 ms, salto a 1500 ms y evento de fin.
- Cada llamada guarda las rutas de sus grabaciones (`HistoryEntry.recordings`, campo `rec` en `history.json`).
- Historial: icono de grabación en la fila y, al desplegarla, reproductor con ▶/■, barra de posición (se puede saltar) y "Mostrar en la carpeta".
- Las grabaciones de versiones anteriores se enlazan solas con su llamada por la fecha y el número del nombre del fichero.
- Una llamada entrante detiene la reproducción.

## Mejora 9: buscador en historial y agenda

- Historial: campo de búsqueda por nombre, número, nota, etiqueta u origen; se combina con los filtros de tipo y etiqueta.
- Agenda: la búsqueda ya existía; ahora ignora acentos y mayúsculas y compara números solo por sus dígitos (con o sin +34).
- `lib/core/search.dart` (`matchesQuery`) con pruebas en `test/search_test.dart`.

## Mejora 4: desvío y No molestar por línea

- Antes el desvío y el No molestar eran globales: al cambiar de línea la cabecera seguía mostrando (y aplicando) el mismo estado.
- Ahora cada línea tiene su propio estado (`LineFeatures` en `features.json`, clave = id de la cuenta). La cabecera muestra y cambia el de la línea seleccionada, y cada tarjeta de línea indica su DND o su desvío (`→ destino`).
- Motor: nuevo `nx_set_dnd_acc(acc_id, on)`: el 486 local se aplica solo a las entrantes de esa cuenta. FreePBX *78/*79 se marca solo por esa línea.
- Migración: el formato antiguo (DND global + un desvío) se convierte al nuevo al arrancar.

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
- Prueba: misma base de código; compilación pendiente de validar en GitHub Actions. Llamadas en Windows/Linux pendientes de probar en un PC.

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
- `CHANGELOG.md` (este fichero), `docs/MANUAL_USUARIO.md`, README, ROADMAP, CLAUDE.md y guía de la centralita actualizados.

Commits: `460842a` (DTMF), `c13dde2` (cierres BLF, barra de menús, segundo plano iPhone).

---

## 2026-11-15 (mediodía) — Centralita nueva, cola de llamadas e iPhone

### Centralita de pruebas FreePBX 17
- La centralita antigua (`192.168.1.10`, contenedor LXC Debian 13) no tenía FreePBX operativo. Se recreó el contenedor con **Debian 12** y se instaló **FreePBX 17.0.33 + Asterisk 22.11** con el instalador oficial (`--opensourceonly --nochrony`). El instalador se detuvo al quitar un módulo comercial (`oracle_connector`); se relanzó una copia con ese paso tolerante a errores (`--skipversion`) y terminó correctamente.
- Extensiones **200** (Linea Principal), **201** (Atencion Directa), **202** (Soporte): PJSIP, buzón, Call Waiting, `max_contacts=3`, suscripciones, códecs `g722&ulaw&alaw&opus`. Credenciales generadas en `pbx/credenciales.local.txt` (no versionado).
- Aparcamiento `70` / órbitas `71–78`; códigos `*72 *73 *90 *52 *78 *79 *97 **` verificados.
- **fail2ban** bloqueó el Mac por las conexiones SSH seguidas → desbloqueo desde consola, conexión SSH compartida (`ControlMaster`) y, con autorización del usuario, redes internas en `ignoreip`.
- Probado desde el Mac: registro de 200/201/202, llamada 200→201 con nombre, G.722 con MOS 4.4, DTMF.

### Cola de llamadas (opción B elegida por el usuario)
- Cola FreePBX **400** "Cola NORYXS": agente 200, `ringall`, *Skip Busy Agents* = *Yes + (ringinuse=no)*, música, posición cada 30 s, 300 s → buzón 200.
- **AMI** abierta a la LAN (autorizado por el usuario) mediante `manager_custom.conf` (`[general](+) bindaddr=0.0.0.0`) y usuario **`noryxs`** limitado (`read=call,agent`, `write=call`, ACL a redes internas). Comprobado: `QueueStatus` funciona y los comandos de sistema se rechazan.
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
