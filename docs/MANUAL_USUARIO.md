# NORYXS Virtual SIP Terminal — Manual de usuario y de configuración

Teléfono IP virtual de escritorio para centralitas FreePBX / Asterisk.
Funciona en **macOS**, **Windows**, **Linux** (paquete `.deb`) e **iPhone** (versión de pruebas).

Este manual explica el uso diario y **todas las opciones de configuración**, que se hacen
desde la propia app. Lo que hay que preparar en la centralita está en
[GUIA_CONFIGURACION_CENTRALITA.md](GUIA_CONFIGURACION_CENTRALITA.md).

---

## Índice

1. [Instalación](#1-instalación)
2. [Primer arranque y primera línea](#2-primer-arranque-y-primera-línea)
3. [La pantalla principal](#3-la-pantalla-principal)
4. [Ajustes: dónde está cada opción](#4-ajustes-dónde-está-cada-opción)
5. [Ajustes › Líneas SIP](#5-ajustes--líneas-sip)
6. [Ajustes › Audio y tonos](#6-ajustes--audio-y-tonos)
7. [Ajustes › Avisos y escritorio](#7-ajustes--avisos-y-escritorio)
8. [Ajustes › Teclas BLF y aparcamiento](#8-ajustes--teclas-blf-y-aparcamiento)
9. [Ajustes › Cola de llamadas](#9-ajustes--cola-de-llamadas)
10. [Ajustes › Etiquetas y WhatsApp](#10-ajustes--etiquetas-y-whatsapp)
11. [Ajustes › Apariencia e idioma](#11-ajustes--apariencia-e-idioma)
12. [Ajustes › Configuración de puestos](#12-ajustes--configuración-de-puestos)
13. [Ajustes › Actualizaciones](#13-ajustes--actualizaciones)
14. [Ajustes › Diagnóstico](#14-ajustes--diagnóstico)
    - [Ajustes › Acerca de](#14b-ajustes--acerca-de)
15. [Llamar](#15-llamar)
16. [Recibir llamadas](#16-recibir-llamadas)
17. [Durante una llamada](#17-durante-una-llamada)
18. [Dos llamadas, transferir, conferencia y aparcar](#18-dos-llamadas-transferir-conferencia-y-aparcar)
19. [Desvío y No molestar (por línea)](#19-desvío-y-no-molestar-por-línea)
20. [Buzón de voz](#20-buzón-de-voz)
21. [Historial y agenda](#21-historial-y-agenda)
22. [Atajos de teclado y cascos](#22-atajos-de-teclado-y-cascos)
23. [Particularidades de cada sistema](#23-particularidades-de-cada-sistema)
24. [Problemas frecuentes](#24-problemas-frecuentes)

---

## 1. Instalación

| Sistema | Paquete | Cómo se instala |
|---|---|---|
| **macOS** (Apple Silicon) | `NORYXS-Terminal-macOS.zip` | Descomprimir y arrastrar *NORYXS Terminal.app* a *Aplicaciones*. La primera vez: clic derecho › *Abrir* (la app no está firmada por Apple). |
| **Windows** (x64) | `NORYXS-Terminal-Windows.zip` | Descomprimir en una carpeta (p. ej. `C:\Program Files\NORYXS`) y abrir `noryxs_terminal.exe`. Si sale el aviso de SmartScreen: *Más información › Ejecutar de todas formas*. |
| **Linux** (Ubuntu/Debian x64) | `NORYXS-Terminal_<versión>_amd64.deb` | `sudo apt install ./NORYXS-Terminal_<versión>_amd64.deb`. Aparece en el menú de aplicaciones. |
| **iPhone** | Desde el Mac de desarrollo | Versión de pruebas (caduca a los 7 días con cuenta gratuita de Apple). |

Los paquetes se generan en GitHub Actions al subir a la rama `developer`, o se publican en la
carpeta compartida del hotel ([sección 13](#13-ajustes--actualizaciones)).

Carpeta de datos de la app (copias de seguridad):

| Sistema | Carpeta |
|---|---|
| macOS | `~/Library/Application Support/NORYXS/` |
| Windows | `%APPDATA%\NORYXS\` |
| Linux | `~/.config/noryxs/` |

Las **contraseñas no están en esas carpetas**: van al almacén seguro del sistema (Llavero de macOS,
Administrador de credenciales de Windows, llavero del escritorio en Linux).

---

## 2. Primer arranque y primera línea

1. Abre NORYXS. Durante unos 5 segundos verás la presentación mientras arranca el motor telefónico.
2. Ve a **Ajustes** (último botón de la barra inferior) › **Líneas SIP**.
3. Rellena la línea 1 ([sección 5](#5-ajustes--líneas-sip)) y pulsa **Guardar y Probar Registro**.
4. Cuando la tarjeta de la línea se ponga en verde (**Registrada**), ya puedes llamar y recibir.

> Si vas a configurar varios ordenadores iguales, configura uno y copia la configuración a
> los demás con [Configuración de puestos](#12-ajustes--configuración-de-puestos).

---

## 3. La pantalla principal

**Cabecera**
- **DND**: No molestar de la **línea seleccionada** (rojo = activo).
- **Desvío**: desvío de la **línea seleccionada**; si está activo muestra el destino (`→ 600…`).
- **Buzón** (icono de cinta): número de mensajes nuevos; abre la pestaña Buzón.
- **Cola** (icono de grupo, solo si la cola está activada): muestra u oculta el panel "En espera", con el número de llamadas en cola.
- **Audio** (cascos): micrófono, altavoz y volumen al momento. El resto de opciones están en Ajustes.

**Líneas SIP simultáneas**
- Una tarjeta por línea con su extensión y su estado: *Registrada / Desconectada / Sonando / En conversación / Retenida*.
- Si la línea tiene **DND** o **desvío**, la tarjeta lo indica (`DND` en rojo, `→ destino`).
- Tocar una tarjeta **selecciona esa línea** para llamar y para DND/desvío.
- **+ Ver 4 líneas** muestra todas las líneas (hasta 8).

**Teclas BLF** (tira de botones; solo aparece si hay teclas configuradas)
- Cada botón es un compañero o una órbita de aparcamiento, con su estado por color:
  verde libre · rojo ocupado · **teja parpadeando = está sonando, tócalo para capturar** · ámbar = llamada aparcada (tócala para recuperarla) · gris sin estado.
- Con muchas teclas, la tira se desplaza en horizontal.

**Franja de estado** (en reposo)
- Línea de salida, su estado y el códec. Si la línea no registra, el motivo (p. ej. *Falta la contraseña*).
- Durante una llamada esta zona pasa a ser la **pantalla de llamada** con todos los controles.

**Marcador y teclado**
- **Teclea el número directamente con el teclado del ordenador**, sin hacer clic en ningún sitio:
  - cifras, `*`, `#` y `+` se escriben en el marcador;
  - **Intro** llama · **Borrar** quita la última cifra · **Esc** limpia el marcador;
  - durante una llamada, las cifras envían **tonos DTMF** (menús de voz, buzón).
- **Salida por**: línea con la que se llama.
- Mantener pulsada la tecla **1** llama al buzón (`*97`).

**Barra inferior**: Terminal · Buzón · Contactos · Historial · **Ajustes**.

---

## 4. Ajustes: dónde está cada opción

Toda la configuración está en la pestaña **Ajustes**. Toca una sección para abrirla y **‹ Ajustes** para volver.

| Grupo | Sección | Qué se configura |
|---|---|---|
| **Teléfono** | Líneas SIP | Extensiones, servidor, contraseñas, transporte, SRTP y **timbre de cada línea** |
| | Audio y tonos | Micrófono, altavoz, volúmenes, **tono de llamada general**, códecs |
| | Avisos y escritorio | Tarjeta flotante, notificación, abrir al iniciar sesión, **atajos de teclado**, **clic para llamar** |
| **Centralita** | Teclas BLF y aparcamiento | Compañeros a supervisar y órbitas de aparcamiento |
| | Cola de llamadas | Panel "En espera" (AMI de FreePBX) |
| **Llamadas** | Etiquetas de llamada | Nombres de las 4 etiquetas |
| | WhatsApp | Plantillas de mensajes |
| **App** | Apariencia e idioma | Tema claro/oscuro/automático; español/inglés/automático |
| | Configuración de puestos | Exportar/importar la configuración (fichero, enlace o QR con PIN) |
| | Actualizaciones | Carpeta compartida con las versiones nuevas |
| | Diagnóstico | Comprobar centralita, líneas, red y audio |

---

## 5. Ajustes › Líneas SIP

Cada **línea** es una **extensión de FreePBX**. Elige la línea en el desplegable de arriba a la derecha (o *+ Añadir línea*).

| Campo | Qué poner | Ejemplo |
|---|---|---|
| Nombre (identidad) | Nombre que verá quien recibe la llamada | `Recepción` |
| Usuario / Extensión SIP | Número de extensión | `200` |
| Contraseña SIP | *Secret* de la extensión en FreePBX (se guarda en el almacén seguro y no se vuelve a mostrar) | — |
| Servidor FreePBX / IP | IP o nombre de la centralita | `192.168.1.10` |
| Puerto | 5060 (UDP/TCP) o 5061 (TLS) | `5060` |
| Transporte | UDP, TCP o TLS | `UDP` |
| Expiración (s) | Cada cuánto renueva el registro | `300` |
| **Timbre de esta línea** | Tono propio de la línea o "El general". ▶ para escucharlo | `Clásico` |
| **Colas que atiende** | Números de cola de FreePBX que atiende esta línea, separados por comas. En el panel *En espera*, **Atender** pasa las llamadas de esas colas a esta extensión. Vacío = ninguna. Ver [sección 9](#9-ajustes--cola-de-llamadas) | `400, 401` |

**Opciones avanzadas**

| Campo | Uso |
|---|---|
| Dominio SIP | Solo si la centralita usa un dominio distinto de la IP |
| Usuario de autenticación | Solo si es distinto de la extensión |
| Proxy de salida | `host:puerto`, solo en redes especiales |
| SRTP (cifrado de audio) | Desactivado / Opcional / Obligatorio (debe coincidir con la extensión en FreePBX) |
| Línea activada | Apagar una línea sin borrarla |

**Guardar y Probar Registro** muestra el resultado debajo: *Registrada (200 OK)* o el error (*401* = contraseña incorrecta, *408* = no llega a la centralita).

---

## 6. Ajustes › Audio y tonos

- **Dispositivos**: micrófono y altavoz/auricular. *Predeterminado del sistema* sigue al sistema (útil con cascos que se conectan y desconectan).
- **Volumen** y **Micrófono**: ganancia de salida y de entrada.
- **Procesado de voz (siempre activo, sin opciones)**: cancelación de eco, **reducción del ruido de fondo** (ventiladores, aire acondicionado, recepción) y **volumen automático** de la voz, que iguala a quien habla bajo o lejos del micrófono. En el iPhone se usa el procesado de voz del propio sistema.
- **Transcripción de llamadas grabadas** (solo informativo): indica que las grabaciones se transcriben solas en el ordenador. Ver [sección 21](#21-historial-y-agenda). No aparece en iPhone.
- **Tono de llamada** (general): Trino, Clásico o Carillón; al tocarlo suena de muestra. Cada línea puede tener el suyo ([sección 5](#5-ajustes--líneas-sip)).
- **Códecs**: orden de preferencia para **todas las líneas**. Toca uno para activarlo/desactivarlo y mantén pulsado para subirlo. Por defecto: G.722 (HD) › Opus › G.711 A › G.711 µ. Pulsa **Guardar códecs**.

> El botón **Audio** de la cabecera es un acceso rápido a micrófono, altavoz y volumen.

---

## 7. Ajustes › Avisos y escritorio

**Llamadas entrantes**
- **Tarjeta flotante**: con la ventana minimizada, oculta o detrás de otra app, aparece arriba a la derecha una tarjeta con *Contestar / Silenciar / Rechazar*. En Linux con Wayland sale una notificación del escritorio con los mismos botones.
- **Notificación del sistema** (macOS): además de la tarjeta.

**Escritorio**
- **Abrir al iniciar sesión**: NORYXS arranca sola. Al cerrar la ventana **no se cierra**: sigue en la barra de menús (macOS) o en la bandeja (Windows/Linux) recibiendo llamadas. Para salir del todo: icono › *Salir de NORYXS*.
- **Atajos de teclado globales**: ver [sección 22](#22-atajos-de-teclado-y-cascos).

**Clic para llamar**
- **Usar NORYXS**: al hacer clic en un número en el navegador, el correo u otro programa (enlaces `tel:` / `sip:`), llama NORYXS por la línea seleccionada.
  - macOS: el sistema pide confirmación.
  - Windows: se abre *Aplicaciones predeterminadas*; elige NORYXS para **TEL** y **SIP**.
  - Linux: queda configurado al momento.

---

## 8. Ajustes › Teclas BLF y aparcamiento

- **+ Añadir**: nombre (p. ej. *Dirección*) y extensión a supervisar (*203*), o una **órbita de aparcamiento** (71–78).
- En la pantalla principal cada tecla muestra el estado en tiempo real. Al tocarla:
  - compañero libre u ocupado → le llama;
  - compañero **sonando** → **captura** la llamada (`**ext`);
  - órbita con llamada → la **recupera**; órbita libre → indica cómo aparcar.
- En FreePBX: suscripciones permitidas (*Allow Subscriptions = Yes*) y aparcamiento activo (guía de la centralita, secciones 8 y 9).

---

## 9. Ajustes › Cola de llamadas

Panel lateral **"En espera"**: quién espera en la cola de FreePBX, cuánto lleva, y botones **Atender**, **Transferir**, **Al buzón** y **Colgar**.

| Campo | Qué poner |
|---|---|
| Activado | Enciende el panel y el botón de cola de la cabecera |
| Servidor AMI | IP de la centralita |
| Puerto | `5038` |
| Usuario AMI | Usuario limitado creado en FreePBX (p. ej. `noryxs`) |
| Contraseña AMI | Se guarda en el almacén seguro |
| Otras colas | Colas que se quieren ver **sin línea propia** (p. ej. `402`). Se atienden con la línea seleccionada. Puede quedar vacío si todas las colas están asignadas a alguna línea |

### Colas por línea

La conexión AMI es **una por puesto** (un solo servidor, usuario y contraseña), tenga el puesto 1 u 8 líneas. Lo que se asigna a cada línea son **las colas que atiende**, en *Ajustes › Líneas SIP › Colas que atiende*.

**Ejemplo** (un puesto de recepción con dos extensiones):

| Línea | Extensión | Colas que atiende |
|---|---|---|
| Línea 1 | 201 (Recepción) | `400` |
| Línea 2 | 202 (Reservas) | `401` |

Resultado:
- El panel vigila **todas** las colas: las de cada línea más las de *Otras colas*, sin repetir. No hace falta escribirlas dos veces.
- El panel *En espera* agrupa las llamadas **por cola**. Cada grupo lleva una etiqueta con la línea que la atiende: *Línea 1 · 201* (en color) o *Seleccionada · 201* (en gris, si la cola no tiene línea asignada).
- **Atender** pasa la llamada a la extensión de la línea de su cola: una llamada de la 401 entra por la Línea 2 aunque esté seleccionada la Línea 1. La llamada en curso queda retenida y la nueva se contesta sola.
- **Al buzón** la manda al buzón de esa misma extensión. **Transferir** pide la extensión destino, como siempre.
- Una cola sin línea asignada (o asignada a una línea desactivada) se atiende con la **línea seleccionada**.
- Si una cola está en varias líneas, se usa la **primera** (Línea 1 antes que Línea 2).
- En *Ajustes › Cola de llamadas* un recuadro **Colas por línea** resume qué cola atiende cada línea.
- Al guardar una línea, el panel se actualiza solo, sin reconectar.
- La **Configuración de puestos** (exportar/importar) copia también las colas de cada línea.

**Varias extensiones en varios puestos:** cada ordenador configura la misma conexión AMI (el mismo usuario sirve para varios puestos a la vez) y asigna a sus líneas sus colas. Cada puesto ve las colas que le interesan.

> En FreePBX, cada extensión debe ser **miembro** (agente) de las colas que atiende (guía de la centralita, sección 11). Si no lo es, Atender sigue funcionando (la app redirige la llamada a la extensión), pero la cola no le ofrecerá las llamadas sola.

El usuario AMI y sus permisos se crean en FreePBX (guía de la centralita, sección 12). Si la ventana no se puede ensanchar (maximizada, Linux en mosaico…), el panel se abre por encima del terminal.

---

## 10. Ajustes › Etiquetas y WhatsApp

**Etiquetas de llamada**: nombre de las 4 etiquetas (por defecto *Presupuesto, Urgente, Devolver llamada, Resuelto*). Se marcan con un toque durante la llamada o en el historial.

**WhatsApp**: plantillas de mensaje; `{nombre}` se sustituye por el nombre del cliente. *+ Añadir*, editar y **Guardar**. Uso en la [sección 21](#21-historial-y-agenda).

---

## 11. Ajustes › Apariencia e idioma

- **Tema**: Claro, Oscuro o **Automático** (sigue al sistema).
- **Idioma**: **Automático**, Español, Català o English.
  - En **Automático** manda el idioma del ordenador: **catalán → catalán**, **castellano → castellano**, **inglés → inglés**; con **cualquier otro idioma, inglés**. Si cambias el idioma del sistema, la app cambia sola.
  - Elegir uno concreto lo fija aunque el ordenador esté en otro idioma.

---

## 12. Ajustes › Configuración de puestos

Sirve para **instalar varios ordenadores sin teclear nada**. Copia las líneas **con sus contraseñas**, las teclas BLF, la cola (con la contraseña AMI), las etiquetas, las plantillas de WhatsApp y los códecs. **No cambia nada en la centralita.**

**Exportar** (en el puesto ya configurado)
1. Ajustes › Configuración de puestos › **Exportar**.
2. Elige un **PIN** (mínimo 4 cifras) y repítelo. Sin el PIN el paquete no se puede abrir.
3. Elige cómo pasarlo:
   - **QR**: escanéalo con la cámara del iPhone y se abre NORYXS con la importación.
   - **Copiar enlace**: envíalo por correo o mensaje; al pulsarlo en otro puesto se abre la importación.
   - **Guardar fichero…**: `puesto.noryxs` (USB, carpeta compartida…).

**Importar** (en el puesto nuevo)
1. Ajustes › Configuración de puestos › **Importar** (o abre el enlace o escanea el QR).
2. Pega el enlace o una dirección `http(s)`, o pulsa **Fichero…**.
3. Escribe el **PIN** y pulsa **Importar**. Sustituye las líneas y ajustes de ese puesto y registra las líneas.

> Seguridad: el paquete va cifrado (AES-256; clave derivada del PIN con 200 000 iteraciones). Un PIN incorrecto o un paquete modificado se rechazan. No envíes el PIN por el mismo canal que el paquete.

---

## 13. Ajustes › Actualizaciones

Sin servidores: los puestos miran una **carpeta compartida** del hotel.

**En cada puesto**: Ajustes › Actualizaciones › escribe la ruta (o **Elegir…** y selecciona el `latest.json` de la carpeta) y pulsa **Comprobar**.

| Sistema | Ejemplo de ruta |
|---|---|
| Windows | `\\NAS\noryxs` |
| macOS | `/Volumes/noryxs` (la carpeta de red conectada en Finder) |
| Linux | `/mnt/noryxs` (montada por el sistema) |

La app comprueba al arrancar y cada 6 horas. Si hay una versión mayor aparece la franja **"Nueva versión X disponible · Instalar"**; *Instalar* abre el paquete con el programa del sistema.

**Publicar una versión** (quien administra):
1. Sube la versión en `app/pubspec.yaml` antes de compilar.
2. Descarga los paquetes de GitHub Actions (macOS, Windows y `.deb`).
3. Ejecuta:
   ```bash
   packaging/publicar_en_carpeta.sh /ruta/de/la/carpeta /ruta/de/los/paquetes "Notas de la versión"
   ```
   Copia los paquetes y crea `latest.json`.

---

## 14. Ajustes › Diagnóstico

**Ejecutar diagnóstico** comprueba y explica:
- si **cada centralita responde** (tiempo y versión);
- si hay **NAT** entre el ordenador y la centralita (causa típica de "conecta pero no se oye": añadir la red del puesto en *Local Networks* de FreePBX);
- el **registro de cada línea** con su código de error;
- los **dispositivos de audio**;
- la conexión del **panel de cola**.

Botones: **Prueba de eco (\*43)** (hablas y te oyes con retardo: comprueba micrófono, altavoz y audio de red), **Repetir** y **Copiar informe** (para enviarlo a soporte).

---

## 14b. Ajustes › Acerca de

Última opción del grupo **App**. Reúne todo sobre la aplicación:

- **Cabecera**: emblema, nombre, descripción y **versión** instalada.
- **Compilación**:
  - **Versión**: la del paquete (p. ej. `1.0.0`).
  - **Compilación**: el commit del código con el que se generó (en las compilaciones de GitHub, el identificador del commit; en las locales, el commit corto, con `-mod` si había cambios sin guardar).
  - **Fecha de compilación**.
  - **Sistema**: sistema operativo y versión.
  - **Motor de voz** (PJSIP 2.17), **Transcripción** (whisper.cpp 1.9.5 · Base, o *No disponible en este equipo*) e **Interfaz** (Flutter/Dart).
  - **Copiar información**: copia versión, compilación, sistema, transcripción y el estado de cada línea (extensión, servidor, transporte, registro) para enviarlo a soporte. No incluye contraseñas.
- **Creado por**: autor de la aplicación, **Yandry Hernández Acosta**, administrador de sistemas y telecomunicaciones, con enlaces a su **LinkedIn** y al **código en GitHub**.
- **Qué incluye**: resumen de las funciones.
- **Privacidad**: todo funciona en el ordenador y en la centralita, sin servidores externos; contraseñas en el almacén seguro; notas y transcripciones cifradas.
- **Licencias y agradecimientos**: NORYXS (GPL-2.0-or-later), PJSIP (GPL-2.0), whisper.cpp/ggml (MIT), OpenSSL (Apache-2.0), Opus (BSD), fuentes Inter y JetBrains Mono (SIL OFL 1.1), Flutter (BSD-3-Clause).

Al pedir ayuda, pulsa **Copiar información** y pégalo en el correo o mensaje.

---

## 15. Llamar

- Teclea el número (teclado del ordenador o en pantalla) y pulsa **Intro** o **Llamar desde LÍNEA X**.
- Elige antes la línea en **Salida por**.
- Desde **Historial** (*Devolver*), **Agenda** o **Buzón**.
- Con el marcador vacío, *Llamar* recupera el último número marcado.
- **Clic para llamar** desde el navegador o el correo ([sección 7](#7-ajustes--avisos-y-escritorio)).

---

## 16. Recibir llamadas

- Con NORYXS a la vista: franja oscura arriba con quién llama, su origen (provincia, móvil, país o "Extensión interna") y **la última nota** tomada con ese número.
- Minimizada o detrás de otra app: **tarjeta flotante** (notificación en Linux/Wayland).
- Suena el timbre de la línea que recibe; si ya hablas, un aviso suave de llamada en espera.
- *Contestar* retiene automáticamente la llamada en curso (nunca la cuelga).

---

## 17. Durante una llamada

Controles: **Retener · Transferir · Silenciar · Alternar/DTMF · Conferencia/Aparcar · Colgar**.

- **REC**: graba en WAV (`Documentos/NORYXS Grabaciones`); se escucha luego desde el historial y, al colgar, **se transcribe sola** (ver [sección 21](#21-historial-y-agenda)).
- **ⓘ** junto al códec: calidad en tiempo real (MOS, jitter, pérdida, RTT).
- **Conexión inestable**: la red se mide cada 2 segundos; si empeora, aparece este aviso en ámbar junto al códec. Al pasar el ratón se ve el motivo. Umbrales: pérdida de paquetes > 3 %, jitter > 50 ms, retardo (RTT) > 350 ms o MOS < 3,5. Desaparece solo cuando la red se recupera. Si sale a menudo, ejecuta el **Diagnóstico** y revisa la wifi/VPN del puesto.
- **Nota y etiquetas**: nota rápida (cifrada en el ordenador) y etiquetas; quedan en el historial.
- **WhatsApp** (números externos): abre WhatsApp con una plantilla.
- Las teclas del ordenador envían **tonos DTMF**.

---

## 18. Dos llamadas, transferir, conferencia y aparcar

- **Dos llamadas**: contestar la segunda retiene la primera; **Alternar** cambia entre ellas.
- **Transferir**: *Transferencia ciega* (pasa la llamada directamente) o *Atendida* (consultas primero; luego *Completar* o *Cancelar y recuperar*).
- **Conferencia a 3**: con dos llamadas establecidas, *Conferencia* las une; *Dividir* devuelve una a espera.
- **Aparcar**: deja la llamada en una órbita (70 → 71…78); se recupera tocando la tecla de la órbita o marcando 71…

---

## 19. Desvío y No molestar (por línea)

Cada línea tiene **su propio** desvío y No molestar, que se aplican a la **línea seleccionada** (toca antes su tarjeta).

- **DND**: rechaza las llamadas de esa línea al momento (la centralita las manda al buzón) y lo activa también en FreePBX (`*78` / `*79`).
- **Desvío**: *Siempre* (`*72`), *Si está ocupado* (`*90`) o *Si no contesta* (`*52`) hacia una extensión o un móvil. Queda en la centralita: **funciona aunque el ordenador esté apagado**.
- La tarjeta de cada línea muestra su estado (`DND`, `→ destino`).

---

## 20. Buzón de voz

- Pestaña **Buzón**: mensajes nuevos y escuchados de cada línea (aviso MWI de FreePBX).
- **Llamar al Buzón (\*97)** o mantener pulsada la tecla 1; los menús se manejan con el teclado.
- *Pendiente*: lista de mensajes con remitente y reproducción dentro de la app (requiere un pequeño acceso en FreePBX).

---

## 21. Historial y agenda

**Historial**
- Filtros *Todas / Entrantes / Salientes / Perdidas* y por **etiqueta**.
- **Buscador** por nombre, número (con o sin prefijo o espacios), nota, etiqueta o **lo que se dijo en una llamada grabada** (su transcripción), sin importar acentos. Lo buscado se resalta en la transcripción.
- **Pendientes de devolver**: una llamada perdida queda *pendiente* mientras sea lo último que hay con ese número (no se devolvió ni volvió a llamar y se habló).
  - La pestaña **Historial** muestra un contador rojo con las pendientes.
  - El filtro **Pendientes de devolver (N)** las lista (una por número, la más reciente).
  - Cada una lleva la etiqueta **Pendiente**.
  - Se quitan solas al devolver la llamada o al hablar de nuevo con ese número. Si se atendió desde otro teléfono, despliega la llamada y pulsa **Marcar atendida**.
- Toca una llamada para desplegarla:
  - **Nota y etiquetas** editables;
  - **Grabación**: ▶, barra para avanzar y *Mostrar en la carpeta*;
  - **Transcripción** (debajo de cada grabación): texto de lo hablado, generado **en el propio ordenador** (ver abajo);
  - **WhatsApp**: eliges plantilla, la editas y se abre WhatsApp con el mensaje escrito; pulsas *Enviar* allí;
  - **Copiar resumen**: comprobante de la llamada para un correo o expediente.
- *Devolver* llama por la misma línea.

**Transcripción de las grabaciones**
- Al colgar una llamada **grabada** (botón REC), la grabación se transcribe **sola, en este ordenador**, con el modelo de reconocimiento de voz Whisper *Base* que va dentro de la app. **El audio no sale nunca del equipo** y no hace falta internet ni ningún servidor.
- Detecta solo el idioma (castellano, catalán, inglés…).
- Si hay una llamada en curso, espera a que termine para no restar potencia al audio. Tarda unos segundos por cada minuto de grabación (en un Mac M1/M2, ~1 s por cada 10 s de audio).
- Mientras tanto se ve *En cola para transcribir…* o *Transcribiendo en este ordenador…*.
- Plegada muestra dos líneas; con **⌄** se despliega entera con la **marca de tiempo** (mm:ss) de cada frase. El texto se puede seleccionar y **copiar** (icono de copiar).
- Si la grabación no tiene voz reconocible, lo indica y ofrece **Reintentar**. Las grabaciones de los últimos 7 días que quedaran sin transcribir (por ejemplo, si se cerró la app) se transcriben al volver a abrirla; las más antiguas tienen el botón **Transcribir**.
- Es automática: puede tener errores con nombres propios, ruido o voces solapadas. No sustituye a la grabación.
- Se guarda **cifrada** en el ordenador (`transcripts.json`, misma clave del Llavero/almacén de credenciales que las notas). Se borra al borrar el historial.
- No disponible en iPhone.

**Agenda**: contactos locales con nombre, empresa y número; búsqueda tolerante como la del historial; ★ favoritos.

---

## 22. Atajos de teclado y cascos

| Acción | macOS | Windows | Linux |
|---|---|---|---|
| Contestar | ⌃⌥A | Ctrl+Alt+A | atajo del sistema → `noryxs-terminal --answer` |
| Colgar (o rechazar si solo suena) | ⌃⌥H | Ctrl+Alt+H | `noryxs-terminal --hangup` |
| Silenciar micrófono | ⌃⌥M | Ctrl+Alt+M | `noryxs-terminal --mute` |
| **Botón de los cascos** (reproducir/pausa) | contesta si suena, cuelga si hablas | igual | igual |

- Se activan y desactivan en Ajustes › Avisos y escritorio.
- El botón de los cascos solo actúa mientras hay una llamada; el resto del tiempo sigue controlando la música.
- **Linux**: en *Configuración › Teclado › Atajos personalizados* crea un atajo por orden (p. ej. Ctrl+Alt+A → `noryxs-terminal --answer`).

---

## 23. Particularidades de cada sistema

**macOS**: icono en la barra de menús; cerrar la ventana la oculta. Tras actualizar, macOS puede pedir permiso para leer el Llavero (*Permitir siempre*).

**Windows**: icono en la bandeja junto al reloj (*Abrir / Salir*). Una sola instancia: si se abre otra vez, trae al frente la que ya está abierta.

**Linux**: GNOME, KDE, XFCE…, con Wayland o X11. El icono de la bandeja necesita AppIndicator (Ubuntu lo trae). En Wayland el aviso de llamada es una notificación del escritorio. Sonido por PipeWire/PulseAudio. Registro de diagnóstico: `~/.config/noryxs/engine.log`.

**iPhone**: sigue registrada en segundo plano y avisa con una notificación (*Contestar / Silenciar / Rechazar*). Si se cierra deslizándola, no recibe llamadas. Para una centralita de otra red necesita la VPN.

---

## 24. Problemas frecuentes

| Síntoma | Solución |
|---|---|
| La línea no registra (*408*) | El ordenador no llega a la centralita: red, VPN o cortafuegos. Ejecuta el **Diagnóstico**. |
| *401 / Error de autenticación* | Contraseña (secret) incorrecta: vuelve a escribirla en Líneas SIP. |
| Conecta pero **no se oye** y se corta a los 30 s | La centralita no considera local la red del ordenador: FreePBX › *Asterisk SIP Settings* › **Local Networks** → añade la red del puesto. El Diagnóstico avisa de NAT. |
| Linux: registrada pero no llama ni recibe | Falta el sonido por PipeWire/PulseAudio: `sudo apt install pipewire-alsa`. |
| La segunda llamada da ocupado | Activa *Call Waiting* en la extensión (guía de la centralita). |
| Las teclas BLF salen grises | Activa *Allow Subscriptions* en FreePBX. |
| El panel de cola dice *sin conexión* | Revisa Ajustes › Cola (IP, usuario y contraseña AMI) y que el puerto 5038 esté permitido desde el puesto. |
| No aparece el aviso de actualización | Revisa la ruta en Ajustes › Actualizaciones (**Comprobar**) y que la versión de `latest.json` sea mayor que la instalada. |
| Una grabación no se transcribe | Mira el texto bajo la grabación: si dice *No se reconoció voz*, la grabación está vacía o muy corta (< 0,5 s); pulsa **Reintentar**. Si no aparece el recuadro *Transcripción*, esa instalación no incluye el modelo (versión compilada sin él). |
| Aparece *Conexión inestable* | La red del puesto pierde paquetes o tiene retardo: wifi débil, VPN saturada o red cargada. Ejecuta el **Diagnóstico**; mejor por cable. |
| Al pulsar un número se abre otra app | Ajustes › Avisos y escritorio › **Usar NORYXS** (en Windows, elegirla en *Aplicaciones predeterminadas*). |
