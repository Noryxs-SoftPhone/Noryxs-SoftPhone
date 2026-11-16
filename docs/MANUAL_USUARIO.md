# NORYXS Virtual SIP Terminal — Manual de usuario

Guía para el uso diario del terminal en **Mac** (y la versión de pruebas para **iPhone**).
Para la configuración de la centralita, consulta [GUIA_CONFIGURACION_CENTRALITA.md](GUIA_CONFIGURACION_CENTRALITA.md).

---

## Índice

1. [Primer arranque](#1-primer-arranque)
2. [La pantalla del terminal](#2-la-pantalla-del-terminal)
3. [Configurar las líneas (pestaña SIP)](#3-configurar-las-líneas-pestaña-sip)
4. [Hacer una llamada](#4-hacer-una-llamada)
5. [Recibir llamadas](#5-recibir-llamadas)
6. [Durante una llamada](#6-durante-una-llamada)
7. [Dos llamadas a la vez](#7-dos-llamadas-a-la-vez)
8. [Transferir](#8-transferir)
9. [Conferencia a tres](#9-conferencia-a-tres)
10. [Aparcar una llamada](#10-aparcar-una-llamada)
11. [Teclas rápidas BLF y captura](#11-teclas-rápidas-blf-y-captura)
12. [Buzón de voz](#12-buzón-de-voz)
13. [No molestar y desvíos](#13-no-molestar-y-desvíos)
14. [Cola de llamadas: panel "En espera"](#14-cola-de-llamadas-panel-en-espera)
15. [Grabar una llamada](#15-grabar-una-llamada)
16. [Calidad de audio (MOS)](#16-calidad-de-audio-mos)
17. [Audio, tono de llamada y avisos](#17-audio-tono-de-llamada-y-avisos)
18. [Contactos e historial](#18-contactos-e-historial)
19. [Mac: barra de menús y arranque automático](#19-mac-barra-de-menús-y-arranque-automático)
20. [iPhone](#20-iphone)
21. [Problemas frecuentes](#21-problemas-frecuentes)
22. [Notas rápidas y etiquetas](#22-notas-rápidas-y-etiquetas)
23. [Copiar resumen de una llamada](#23-copiar-resumen-de-una-llamada)
24. [Quién llama: origen y última nota](#24-quién-llama-origen-y-última-nota)

---

## 1. Primer arranque

1. Abre **NORYXS Terminal** desde Aplicaciones. Verás la pantalla de arranque con el logo dorado mientras se inicia el motor telefónico.
2. La primera vez, macOS puede pedir:
   - **Micrófono** → *Permitir* (necesario para hablar).
   - **Llavero** → *Permitir siempre* (ahí se guardan tus contraseñas de forma segura).
   - **Notificaciones** → *Permitir* (si activas la notificación del sistema).
3. Ve a la pestaña **SIP** (abajo a la derecha) y configura tus líneas (sección 3).

> **Red:** el ordenador debe llegar a la centralita. Si la centralita está en otra red (por ejemplo `192.168.1.x`), necesitas la VPN de la empresa (NetBird) conectada.

---

## 2. La pantalla del terminal

De arriba abajo:

| Zona | Qué muestra |
|---|---|
| **Cabecera** | Logo NORYXS · **DND** (No molestar) · **Desvío** · **Buzón** con contador dorado de mensajes nuevos · **Audio** |
| **Líneas SIP** | Una tarjeta por línea: LED, número de línea, extensión, estado (*Libre*, *Sonando…*, *Llamando…*, duración en verde, *Retenida*, *Desconectada*) y "Buzón (N)" si hay mensajes. La tarjeta con borde dorado es la seleccionada |
| **Teclas rápidas** | Teclas BLF de compañeros y órbitas de aparcamiento, y acceso directo **Buzón (*97)** |
| **Pantalla (LCD)** | Sin llamada: línea, estado de registro, códec. En llamada: interlocutor, duración, controles |
| **Marcador** | Campo para escribir el número, botón de borrar y **"Salida por"** (línea con la que llamarás) |
| **Teclado** | 1–9, *, 0, #. Mantén pulsado **1** para el buzón y **0** para "+" |
| **Barra de llamada** | *Limpiar* · *Llamar desde LÍNEA X* |
| **Navegación** | Terminal · Buzón · Contactos · Historial · SIP |

Colores de estado:
- 🟢 **Verde:** registrada / libre / en conversación.
- 🟡 **Dorado latiendo:** sonando.
- 🟠 **Ámbar:** retenida.
- 🔴 **Rojo:** desconectada / error.
- 🔵 **Azul:** llamando.

---

## 3. Configurar las líneas (pestaña SIP)

1. Pulsa **SIP**.
2. Arriba a la derecha elige la línea (**Línea 1 (Ext. …)**). Con *+ Añadir línea* puedes tener hasta 8.
3. Rellena:
   - **Nombre identidad:** cómo te verán (ej. *Linea Principal*).
   - **Usuario / Extensión SIP:** tu extensión (ej. *200*).
   - **Contraseña SIP:** la que te dio el administrador. Se guarda en el Llavero; después solo verás puntos.
   - **Servidor:** IP o nombre de la centralita.
   - **Puerto / Transporte:** normalmente *5060 UDP* (o *5061 TLS*).
   - **Expiración:** 300 segundos (por defecto).
4. **Códecs:** toca para activar/desactivar; mantén pulsado para subir prioridad. Recomendado: *G.722 (HD)* primero.
5. **Opciones avanzadas:** dominio, usuario de autenticación, proxy, **SRTP** (cifrado de audio) y **Línea activada**.
6. Pulsa **Guardar y Probar Registro**. Debe aparecer **"Registrada (200 OK)"** en verde.

Mensajes posibles: *Registrando…*, *Registrada*, *No registrada*, *Error de autenticación* (contraseña mal), *Error de conexión* (no llega a la centralita), *Falta la contraseña*.

---

## 4. Hacer una llamada

1. Elige la línea en **"Salida por"** (o pulsando su tarjeta).
2. Escribe el número con el teclado en pantalla o el del ordenador.
3. Pulsa **Llamar** (o Intro).

Atajos:
- **Llamar con el campo vacío** rellena el último número marcado.
- Desde **Contactos**, **Historial** o **Buzón**, el botón *Llamar/Devolver* marca directamente (desde el historial y el buzón, por la misma línea).

Si ya estás hablando, la llamada actual **se retiene automáticamente** al llamar a otro número.

---

## 5. Recibir llamadas

**Con la ventana a la vista:** aparece una **franja oscura** arriba del terminal con la línea que recibe, el nombre y el número, y los botones **Contestar**, **Silenciar** (para el tono) y **Rechazar**. Si ya estás hablando, indica **"Multi-línea activa · Retendrá Línea X"**: al contestar, tu llamada actual queda en espera, nunca se corta.

**Con la ventana minimizada, oculta o detrás de otra app:** aparece una **tarjeta flotante** arriba a la derecha del escritorio con *Contestar* (trae el terminal al frente), *Silenciar* y *Rechazar*.

Si ya estás en una conversación, en lugar del timbre normal suena un **aviso suave** de llamada en espera.

---

## 6. Durante una llamada

La pantalla muestra el interlocutor, la duración y seis controles:

| Botón | Qué hace |
|---|---|
| **Retener / Recuperar** | Pone en espera (el otro oye la música de la centralita) o la retoma |
| **Transferir** | Abre el panel de transferencia (sección 8) |
| **Silenciar** | Corta tu micrófono (el botón se pone dorado) |
| **Alternar / DTMF** | Con dos llamadas: cambia entre ellas. Con una: modo tonos |
| **Conferencia / Aparcar 71** | Con dos llamadas: une las tres personas. Con una: aparca la llamada |
| **Colgar** | Cuelga esta llamada (las demás siguen) |

Junto a la duración:
- **● REC:** graba la llamada (sección 15).
- **G.722 • RTP ⓘ:** calidad de audio en directo (sección 16).

**Tonos (menús de voz, buzón, IVR):** con la llamada activa, **el teclado envía tonos directamente**, tanto el de la pantalla como el del ordenador. Verás *"Tonos enviados: 1 2 #"*.

---

## 7. Dos llamadas a la vez

1. Estás hablando por la línea 1 y entra otra llamada (por la misma línea o por otra).
2. Pulsa **Contestar**: la primera queda **retenida** con música y pasas a la nueva.
3. **Alternar** cambia de una a otra.
4. Puedes **transferir** cualquiera, **unirlas en conferencia** o **colgar una** sin afectar a la otra.
5. En la pantalla verás "Sesión en curso en LÍNEA X → *Ver sesión*" para saltar a la otra llamada; también puedes pulsar la tarjeta de la línea.

Cada llamada tiene su propio audio: nunca se mezclan, salvo que actives la conferencia.

---

## 8. Transferir

Pulsa **Transferir** durante la llamada y escribe el destino.

- **Transferencia ciega:** se pasa la llamada directamente al destino y tú quedas libre.
- **Atendida (consultar):**
  1. La llamada original queda en espera y se llama al destino.
  2. Hablas con el destino.
  3. **Completar transferencia** une al interlocutor original con el destino; o **Cancelar y recuperar** cuelga la consulta y vuelve a la original.

---

## 9. Conferencia a tres

Con una llamada activa y otra retenida, pulsa **Conferencia**: las tres personas se oyen. **Dividir conf.** devuelve la otra llamada a espera sin colgar a nadie.

---

## 10. Aparcar una llamada

- **Aparcar 71:** la llamada se deja en una órbita de la centralita (71, 72…) con música, y tu línea queda libre.
- La tecla de órbita (*Órbita Park 71*) **parpadea en ámbar** mientras hay una llamada aparcada.
- Para **recuperarla**, desde este u otro teléfono, pulsa la tecla de órbita o marca **71**.

---

## 11. Teclas rápidas BLF y captura

Muestran en tiempo real el estado de compañeros:

| LED | Estado | Al pulsar |
|---|---|---|
| 🟢 | Libre | Llama a esa extensión |
| 🔴 | Ocupada | Llama (o pasa el ratón para ver con quién habla) |
| 🟡 latiendo | Sonando | **Captura** la llamada (`**ext`): la contestas tú |
| ⚪ | Sin estado | La centralita no informa de esa extensión |

**Configurar:** pestaña **SIP → Teclas rápidas BLF y órbitas → + Añadir**. Indica el nombre, la extensión y si es una órbita de aparcamiento (71–78). Hasta 6 teclas.

---

## 12. Buzón de voz

- El **contador dorado** de la cabecera y la etiqueta **"Buzón (N)"** de cada línea indican los mensajes nuevos.
- Para escucharlos: **Buzón (*97)**, la pestaña **Buzón → Escuchar** (por la línea que tiene los mensajes) o mantén pulsado **1**.
- La centralita te pedirá el PIN del buzón y te guiará por su menú; las teclas funcionan automáticamente durante la llamada.

---

## 13. No molestar y desvíos

**DND (No molestar):** pulsa **DND** en la cabecera; se pone rojo. Las llamadas se rechazan y la centralita las envía al buzón. Se activa también en la centralita (`*78`), así que funciona aunque cierres el ordenador. Vuelve a pulsarlo para desactivarlo.

**Desvío:**
1. Pulsa **Desvío** en la cabecera.
2. Elige el modo:
   - *Siempre* (`*72`)
   - *Si está ocupado* (`*90`)
   - *Si no contesta* (`*52`)
3. Escribe el número de destino (extensión o móvil).
4. Pulsa **Aplicar desvío**. La cabecera mostrará **"→ número"** en dorado.
5. Para quitarlo: modo *Desactivado* → *Aplicar*.

Los desvíos se aplican **en la centralita** a la línea seleccionada y funcionan con el ordenador apagado.

---

## 14. Cola de llamadas: panel "En espera"

Si tu empresa usa una **cola** (ej. 400), las llamadas que entran mientras hablas esperan en la centralita con música y aviso de posición.

**Activar (una vez):** pestaña **SIP → Panel de cola (FreePBX)**:
1. Activa el interruptor.
2. Rellena: servidor, puerto `5038`, colas (ej. `400`), usuario AMI (ej. `noryxs`) y contraseña (la da el administrador; se guarda en el Llavero).
3. Pulsa **Guardar y conectar**. Debe salir el punto verde con **"Conectado · cola 400"**.

**Botón de la cabecera:** el icono de grupo (junto al buzón) **muestra u oculta el panel** en cualquier momento, aunque no haya nadie esperando; lleva un contador dorado con las llamadas en cola.

**Uso:** cuando hay llamadas esperando, la ventana se ensancha y aparece **"EN ESPERA • N"**:
- Cada tarjeta muestra la posición (la primera en dorado), quién llama y **cuánto lleva esperando** (en rojo pasados 2 minutos).
- **Atender:** la llamada pasa a tu línea y **se contesta sola**; tu conversación actual queda retenida.
- **Transferir** (a otra extensión), **Buzón** (a tu buzón), **Colgar**.
- **›** oculta el panel; se vuelve a abrir solo si entra otra llamada.

---

## 15. Grabar una llamada

Pulsa **● REC** junto al códec durante la llamada; el punto se pone rojo y late. Vuelve a pulsar para parar (también se para al colgar).
Las grabaciones se guardan en **Documentos › NORYXS Grabaciones** como `AAAA-MM-DD_HHMMSS_L1_número.wav`, con tu voz y la del interlocutor.

> Respeta la normativa: informa al interlocutor cuando grabes.

---

## 16. Calidad de audio (MOS)

Pulsa **G.722 • RTP ⓘ** durante la llamada para ver en directo:
- **Jitter** (variación del retardo).
- **Pérdida de paquetes** (%).
- **Latencia RTT** (ms).
- **MOS**: nota de calidad de 1 a 5. Con 4,0 o más es excelente; por debajo de 3,5 hay problemas de red (Wi-Fi, VPN…).

---

## 17. Audio, tono de llamada y avisos

Pulsa el icono de **auriculares** en la cabecera:
- **Micrófono** y **Altavoz/auricular**: elige entre los del sistema, USB o Bluetooth (se detectan al conectarlos).
- **Volumen** del altavoz y del micrófono. La cancelación de eco está siempre activa.
- **Tono de llamada:** *Trino*, *Clásico* o *Carillón*. Al tocar uno se escucha 3 segundos.
- **Mac:** *Tarjeta flotante si está minimizada*, *Notificación del sistema* y *Abrir NORYXS al iniciar sesión*.

---

## 18. Contactos e historial

**Contactos:** *+ Nuevo* para añadir (nombre, número, empresa, favorito ★). Toca un contacto para editarlo o borrarlo, y **Llamar** para marcar. Los favoritos salen primero. Al recibir una llamada de un contacto se muestra su nombre.

**Historial:** entrantes (↙ verde), salientes (↗ azul) y perdidas (✕ rojo), con línea, hora y duración. Filtros arriba. **Devolver** llama por la misma línea; el icono de persona guarda el número en contactos. *Borrar* vacía el historial.

---

## 19. Mac: barra de menús y arranque automático

- Cerrar la ventana (botón rojo) **no apaga NORYXS**: sigue registrado y recibiendo llamadas. Verás un **icono de teléfono** en la barra de menús, junto al reloj.
- Menú del icono: **Abrir NORYXS** (⌘O) y **Salir de NORYXS** (⌘Q, que sí cierra la app y desconecta las líneas).
- Con la ventana cerrada, las llamadas muestran la **tarjeta flotante**.
- **Abrir al iniciar sesión** está activado por defecto. Se cambia en *Audio y avisos* o en *Ajustes del Sistema › General › Ítems de inicio*.

---

## 20. iPhone

Versión de pruebas, con el mismo diseño que en el Mac.

- **Instalación:** la hace el equipo técnico desde el Mac. La primera vez: activar *Modo de desarrollador* y confiar en el desarrollador en *Ajustes › General › VPN y gestión de dispositivos*.
- **Red:** conecta la VPN **NetBird** para llegar a la centralita.
- **Segundo plano:** si sales de la app o bloqueas el iPhone, NORYXS sigue conectada y avisa con una **notificación** (*Contestar*, *Silenciar*, *Rechazar*).
- Limitaciones:
  - No recibe llamadas si cierras la app deslizándola hacia arriba, ni después de reiniciar el iPhone (ábrela una vez).
  - Con la cuenta gratuita de Apple, la app **caduca a los 7 días** y hay que reinstalarla.
  - Sin TLS por ahora.
  - El panel de cola lateral no está disponible en el móvil.

---

## 21. Problemas frecuentes

| Problema | Qué hacer |
|---|---|
| La línea se queda en "Registrando…" o "Error de conexión" | Comprueba la red y la VPN; el servidor y el puerto deben ser correctos |
| "Error de autenticación" | Contraseña o extensión incorrectas; vuelve a escribir la contraseña y guarda |
| "Falta la contraseña" | Escríbela en la pestaña SIP y guarda (macOS puede pedir permiso para el Llavero) |
| No se oye o solo se oye en un sentido | Revisa micrófono y altavoz en *Audio*; si persiste, avisa al administrador (NAT/puertos RTP) |
| El buzón no responde a las teclas | Actualiza a la última versión (corregido el 15/11/2026) |
| La segunda llamada da ocupado | El administrador debe activar *Call Waiting* en tu extensión |
| El panel de cola dice "Sin conexión AMI" | Revisa los datos AMI en SIP; el administrador debe permitir tu red (ver guía) |
| La app se cierra sola | Corregido el 15/11/2026. Si vuelve a pasar, envía el informe de *~/Library/Logs/DiagnosticReports/NORYXS Terminal-….ips* |
| macOS pide acceso al Llavero tras actualizar | Normal con las versiones internas: pulsa *Permitir siempre* |

---

## 22. Notas rápidas y etiquetas

Para apuntar lo importante de una llamada **sin salir del terminal** y sin perder a qué llamada pertenece.

**Durante la llamada:**
1. Bajo los controles, pulsa **✎ Añadir nota**.
2. Escribe hasta dos líneas (ej. *"Llamar mañana a las 10:00 — Ref. 402"*). Se guarda sola.
3. Marca con un toque las **etiquetas** que correspondan:
   - `Presupuesto` (dorado)
   - `Urgente` (rojo)
   - `Devolver llamada` (azul)
   - `Resuelto` (verde)

   Otro toque las quita.
4. Al colgar, la nota y las etiquetas quedan en esa llamada del **Historial**.

**En el Historial:**
- Las llamadas con nota muestran un icono 🗒 y un resumen en cursiva; las etiquetadas, puntos de color.
- Toca una llamada para **desplegarla**: puedes leer o editar la nota y cambiar las etiquetas.
- Arriba, los **filtros por etiqueta** muestran solo, por ejemplo, las llamadas *Devolver llamada*.

**Cambiar los nombres de las etiquetas:** pestaña **SIP › Etiquetas de llamada** → escribe los nombres → *Guardar*. Los colores no cambian.

**Privacidad:** las notas y etiquetas se guardan **cifradas** en tu ordenador (la clave está en el Llavero), nunca salen de él, y se borran con *Borrar historial*.

---

## 23. Copiar resumen de una llamada

Para dejar constancia en un correo o expediente:
1. **Historial** → toca la llamada para desplegarla.
2. Pulsa **Copiar resumen**.
3. Pega (⌘V) donde quieras. Ejemplo:

```
[NORYXS SIP] 15/11/2026 17:15 • Ext. 201 → Laura Gómez (+34 612 849 310) (Saliente · Duración: 04:18) | Etiquetas: Presupuesto | Nota: Confirmada cita para el martes.
```

`→` saliente · `←` entrante · `✕` perdida.

---

## 24. Quién llama: origen y última nota

Cuando entra una llamada, bajo el número aparece **de dónde llama**, sin necesidad de internet:
- España: provincia de los fijos (*Barcelona • Fijo*), *Móvil nacional*, *Número gratuito*, *Tarifa nacional (902)*…
- Extranjero: país con su bandera (*🇫🇷 Francia • Móvil*).
- Compañeros: *Extensión interna*.

No se muestra la compañía telefónica, porque con la portabilidad no se puede saber de forma fiable sin internet.

**Última nota:** si ya hablaste antes con ese número y apuntaste algo, verás **antes de descolgar** *"Última nota (12/11): Preguntó por presupuesto de implantes"* y sus etiquetas. Aparece en la franja de llamada entrante, en la tarjeta flotante del Mac y en la notificación del iPhone.

Los números se reconocen escritos de cualquier forma (`+34 612…`, `0034 612…`, `612…`) para la agenda, el historial y las notas.
