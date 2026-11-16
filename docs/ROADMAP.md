# NORYXS — Hoja de ruta

Estado: ✅ hecho y probado · 🟡 hecho, falta validarlo con llamadas reales · ⏳ pendiente · ⛔ bloqueado

Regla del proyecto: **ninguna función se da por terminada hasta probarla con llamadas reales contra FreePBX.**
Historial detallado de cambios: [CHANGELOG.md](../CHANGELOG.md).

_Última actualización: 15/11/2026._

---

## Resumen

| Área | Estado |
|---|---|
| Motor PJSIP (C) | ✅ Completo, probado con FreePBX 17 real |
| App macOS | ✅ Instalada, diseño del cliente, estable (corregidos los cierres BLF) |
| Centralita de pruebas | ✅ FreePBX 17 en 192.168.1.10 con extensiones, cola, AMI |
| 15 pruebas obligatorias | 🟡 Mayoría probadas con el motor; falta la batería completa con 2 líneas en la app |
| iPhone | ✅ Instalada, registrada por NetBird y llamando |
| Windows / Linux | ⏳ Sin empezar |
| Repositorio / CI | ✅ GitHub Actions: Linux (.deb), macOS y Windows |

---

## Fase 0 — Base técnica ✅
- ✅ PJSIP 2.17 macOS arm64 con TLS (OpenSSL 3), SRTP, Opus, G.722, G.711, AEC.
- ✅ Motor `libnoryxs_engine` + `nx_cli`.
- ✅ Llavero de macOS.

## Fase 1 — App Flutter + puente FFI ✅
- ✅ FFI sin paquetes, eventos con `NativeCallable.listener`, motor enlazado dentro del ejecutable.
- ✅ Interfaz según el HTML del cliente; splash, logo, iconos; fuentes Inter + JetBrains Mono.
- ✅ Sin App Sandbox (Llavero con firma ad-hoc); datos en `~/Library/Application Support/NORYXS/`.

## Fase 1B — Anexo técnico ✅ / 🟡
- ✅ MWI por línea — **validado con FreePBX** (contador y "Buzón (1)").
- ✅ BLF (`dialog`) — **sin cierres** tras reescribir el análisis del NOTIFY, y **validado el cambio a *Ocupada*** en tiempo real con una llamada del iPhone (ext. 201). 🟡 Falta ver *Sonando* y la captura `**`.
- 🟡 Captura dirigida `**ext` — falta prueba real.
- 🟡 Aparcamiento 70 / órbitas 71–78 (BLF `*85XX`) — falta prueba real de aparcar y recuperar.
- ✅ DND local (486) probado. 🟡 `*78/*79` en FreePBX por probar desde la app.
- 🟡 Desvíos `*72/*90/*52` — por probar desde la app.
- ✅ Conferencia local a 3, grabación WAV y telemetría/MOS — probadas con llamadas reales.
- ✅ Doble aviso: franja (contexto A) y tarjeta flotante (contexto B); probado con llamada real con la app minimizada.
- ✅ Teclado envía DTMF automáticamente durante la llamada (corregido; verificado en el registro DTMF de Asterisk).

## Centralita de pruebas ✅
- FreePBX 17 + Asterisk 22 (máquina virtual Debian 12).
- Extensiones 200/201/202, aparcamiento, códigos, cola 400, AMI `noryxs`, fail2ban con redes internas en lista blanca.

## Cola de llamadas ✅ / 🟡
- ✅ Cola FreePBX 400 con espera, música, posición y desbordamiento al buzón.
- ✅ AMI limitada accesible desde la LAN.
- ✅ Panel lateral "En espera" con llamadas reales en cola.
- 🟡 "Atender" con autocontestación: las llamadas de prueba terminaron contestadas; confirmar *Transferir*, *Buzón* y *Colgar* desde el panel.

## Fase 2 — Registro y llamadas básicas 🟡
- ✅ Registro de varias cuentas a la vez (motor y app con la 200).
- ✅ Recibir y hacer llamadas; audio bidireccional G.722.
- ⏳ Configurar la Línea 2 (201) en la app del Mac para las pruebas con dos líneas.

## Fase 3 — Multisesión 🟡
- ✅ Dos llamadas, retener, recuperar, alternar, colgar una sin afectar a la otra (motor, llamadas reales).
- ✅ Aislamiento de audio (al contestar la 2.ª, la 1.ª queda en `local_hold`).
- ⏳ Escenario obligatorio completo del punto 6 en la app con dos líneas.

## Fase 4 — Transferencias 🟡
- 🟡 Ciega y atendida implementadas; falta prueba real con FreePBX desde la app.

## Fase 5 — Robustez y seguridad 🟡
- ✅ Corregidos los cierres de la app por avisos BLF (10 informes, misma causa).
- ✅ Reconexión tras suspender el Mac (`wake` → `nx_network_changed`).
- ✅ Mac sigue en la barra de menús al cerrar la ventana y abre al iniciar sesión.
- ⏳ SIP TLS + SRTP contra FreePBX (certificado en Certificate Management).
- ⏳ STUN/ICE y verificación TLS en la interfaz.
- ⏳ Registro de logs a fichero en el Mac (ya existe `startup.log`).

## iPhone (pruebas) 🟡
- ✅ PJSIP + motor iOS, plataforma Flutter iOS, permisos, iconos.
- ✅ Instalada en iPhone 15 Pro; corregido el bloqueo en el splash (`HOME` inexistente en iOS).
- ✅ Segundo plano con sesión de audio en silencio + notificación local con acciones.
- ✅ Registrado por NetBird y llamando a la ext. 200 (validado el 15/11/2026).
- ⏳ TLS/Opus en iOS (compilar OpenSSL y Opus para iOS).
- ⛔ Pantalla de llamada nativa con la app cerrada (PushKit + CallKit): requiere **Apple Developer Program de pago**. Con la cuenta gratuita la app caduca a los 7 días.
- ⏳ Panel de cola como hoja inferior en móvil.

## Anexo 2 — Productividad en la llamada ✅ (15/11/2026)
Especificación: [ESPECIFICACION.md › Anexo 2](ESPECIFICACION.md).
- ✅ Notas rápidas por llamada, cifradas (AES-256 + HMAC, clave en Llavero) — cifrado probado.
- ✅ Etiquetas con un clic (4, nombres configurables) y filtro en historial.
- ✅ Copiar resumen de llamada al portapapeles.
- ✅ Identificación offline del llamante — pruebas unitarias y validado con llamada real ("Extensión interna"). 🟡 Ver "última nota" con un número externo real.
- ✅ Botón en la cabecera para mostrar/ocultar el panel de cola.

## Fase 6 — Windows y Linux ✅ (16/11/2026)
- ✅ Motor para Windows (MSYS2 UCRT64, OpenSSL 3.6) y Linux; `.deb` para Linux.
- ✅ Tarjeta flotante (X11) / notificación de escritorio (Wayland), bandeja, panel de cola, inicio de sesión, instancia única.
- ✅ Linux probado con llamadas reales (Wayland). 🟡 Windows: falta probar llamadas en un PC.

## Fase 7 — Distribución interna ⏳
- Subir a GitHub (URL pendiente) y comprobar el CI.
- Firma y notarización en macOS, o distribución interna sin notarizar.
- Lista de mensajes de voz por IMAP (FreePBX voicemail-to-email).

---

## Fase 8 — Mejoras (16/11/2026) ⏳

Cada una: CHANGELOG con prueba y manual al día.

| # | Mejora | Diseño acordado | Estado |
|---|---|---|---|
| 1 | Atajos de teclado globales y botones de cascos | Combinaciones configurables para contestar / colgar / silenciar desde cualquier app; botón de cascos USB/Bluetooth (reproducir/pausa) contesta o cuelga | 🟡 hecho, falta probar con cascos reales |
| 2 | Escuchar grabaciones desde el historial | ▶ en la llamada grabada; reproductor integrado (motor PJSIP); abrir carpeta | 🟡 hecho, falta probar con una grabación real |
| 3 | Buzón de voz dentro de la app | Lista de mensajes (remitente, fecha, duración), escuchar, borrar y devolver la llamada. **Leído directamente de la centralita** con un acceso de solo lectura en FreePBX (documentado en la guía), autenticado con la extensión y su PIN de buzón | ⏳ pendiente (necesita acceso a la centralita de pruebas) |
| 4 | Desvío y No molestar por línea | El estado de desvío/DND pertenece a cada línea; la cabecera muestra el de la línea seleccionada (antes era global) | 🟡 hecho, falta probar con llamadas |
| 5 | Configuración automática de puestos | Exportar desde un puesto e importar en otros por **fichero, enlace o QR**: líneas, BLF, cola, etiquetas. **Incluye contraseñas, cifradas con PIN**. No toca la centralita | 🟡 hecho, falta probar una importación real entre dos puestos |
| 6 | Aviso de actualización | **Sin servidor:** la app consulta un `latest.json` en una **carpeta compartida** del hotel (NAS / recurso de red, ruta configurable) y avisa con el instalador. Script `packaging/publicar_en_carpeta.sh` | 🟡 hecho, falta ver el aviso en un puesto real |
| 7 | Clic para llamar | La app se registra para enlaces `tel:` y `sip:` en macOS, Windows y Linux | 🟡 hecho (pruebas unitarias), falta probar en cada sistema |
| 8 | ~~Habitaciones~~ | Eliminado (16/11): FreePBX ya envía el nombre de la extensión; el del huésped necesitaría el PMS | ❌ descartado |
| 9 | Buscador en historial y agenda | Filtro instantáneo por nombre, número, nota o habitación | ✅ (pruebas unitarias) |
| 10 | Modo oscuro | Claro / oscuro / automático (según el sistema) | ✅ |
| 11 | Inglés | Español e inglés; idioma del sistema o elegido en ajustes | ✅ (falta traducir las piezas nativas) |
| 12 | Timbre distinto por línea | Cada línea elige su timbre | 🟡 hecho, falta probar con llamadas |
| 13 | Diagnóstico de red y audio | Botón que prueba conexión con la centralita, registro, micrófono/altavoz (eco) y muestra el resultado | ✅ |
| 15 | Catalán | Idioma automático según el sistema (ca/es/en; cualquier otro → inglés) o elegido en ajustes | ✅ |
| 16 | Reducción de ruido y volumen automático | Speex AEC por software con denoise y AGC, siempre activo en escritorio | 🟡 hecho, falta oírlo en una llamada real |
| 17 | Aviso de mala conexión | "Conexión inestable" si pérdida > 3 %, jitter > 50 ms, RTT > 350 ms o MOS < 3,5 | 🟡 hecho, falta verlo con red mala real |
| 18 | Perdidas pendientes de devolver | Contador, filtro, etiqueta "Pendiente", "Marcar atendida" | ✅ |
| 19 | Transcripción local de grabaciones | whisper.cpp 1.9.5 (MIT) + modelo Base q5_1 (57 MB) dentro de la app; automática al colgar, en segundo plano, cifrada, buscable desde el historial. macOS/Windows/Linux (no iOS) | 🟡 probada en macOS (WAV real de la app); Windows/Linux pendiente de la CI |
| 20 | Colas por línea | Cada línea indica las colas que atiende; el panel agrupa por cola y Atender/Al buzón usan la extensión de esa línea (si no tiene, la seleccionada). Una sola conexión AMI por puesto | 🟡 hecho (pruebas unitarias + interfaz), falta probar con la cola real |
| 21 | Acerca de | Ajustes › Acerca de: versión, compilación (commit y fecha), sistema, componentes, autor (Yandry Hernández Acosta, LinkedIn y GitHub), privacidad y licencias; *Copiar información* para soporte | ✅ |
| 14 | WhatsApp | **Sin servidor:** botón WhatsApp en llamada e historial con plantillas (ES/EN); abre WhatsApp Desktop/Web con el chat y el mensaje escrito (enlace oficial `wa.me`), se pulsa Enviar. Sin riesgo de bloqueo. (Descartado WAHA: requería servidor) | ✅ (pruebas unitarias) |

Decisión (16/11/2026): **nada puede depender de un servidor** → actualizaciones por carpeta compartida y WhatsApp por enlace oficial.

## Las 15 pruebas obligatorias

| # | Prueba | Estado |
|---|---|---|
| 1 | Registrar dos cuentas a la vez | ✅ motor (200/201/202) · ⏳ app con 2 líneas |
| 2 | Recibir por la línea 1 | ✅ |
| 3 | Recibir por la línea 2 | ⏳ app (falta configurar la Línea 2) |
| 4 | Llamar por cada línea | ✅ motor · ⏳ app línea 2 |
| 5 | Dos llamadas simultáneas | ✅ motor |
| 6 | Retener | ✅ motor |
| 7 | Recuperar | ✅ motor |
| 8 | Alternar | ✅ motor |
| 9 | Transferencia ciega | 🟡 |
| 10 | Transferencia atendida | 🟡 |
| 11 | DTMF | ✅ (Asterisk recibe los dígitos) |
| 12 | Colgar una sin afectar a la otra | ✅ motor |
| 13 | Recuperar registro tras desconexión | 🟡 implementado (reintentos + wake) |
| 14 | Audio bidireccional en ambas líneas | ✅ línea 200 · ⏳ línea 2 |
| 15 | Audio aislado | ✅ motor (`local_hold` + `audio_isolate`) |

---

## Limitaciones conocidas
- Códecs globales (PJSUA no permite códecs por cuenta).
- Solo arm64 en macOS.
- iPhone: sin TLS ni Opus; sin llamadas con la app cerrada; caduca cada 7 días con la cuenta gratuita.
- No usar `pjsua_buddy_get_dlg_event_info()` (cierre en PJSIP 2.17; ver CHANGELOG).

### Organización de la interfaz (16/11/2026)
- Ajustes en una pestaña propia por secciones; pantalla principal compacta (BLF en tira, franja de estado); teclado del ordenador directo al marcador; splash 5,5 s.
