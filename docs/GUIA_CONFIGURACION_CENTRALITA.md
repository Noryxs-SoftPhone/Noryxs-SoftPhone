# NORYXS Virtual SIP Terminal — Guía de configuración de la centralita

**Destinatario:** administrador de la centralita FreePBX/Asterisk del cliente.
**Objetivo:** dejar la centralita preparada para que el terminal NORYXS funcione con todas sus funciones: varias líneas, retención, transferencias, buzón, BLF, aparcamiento, desvíos, No molestar, cola de llamadas y seguridad.

> Todas las funciones de esta guía se han validado con llamadas reales en FreePBX 17.0 + Asterisk 22 (contenedor Debian 12). Las rutas de menú son las de FreePBX 17; en FreePBX 16 son prácticamente iguales.

---

## Índice

1. [Requisitos](#1-requisitos)
2. [Red, puertos y cortafuegos](#2-red-puertos-y-cortafuegos)
3. [Ajustes globales de SIP (PJSIP)](#3-ajustes-globales-de-sip-pjsip)
4. [Extensiones (una por línea del terminal)](#4-extensiones-una-por-línea-del-terminal)
5. [Llamada en espera y dos llamadas simultáneas](#5-llamada-en-espera-y-dos-llamadas-simultáneas)
6. [Transferencias ciega y atendida](#6-transferencias-ciega-y-atendida)
7. [Buzón de voz y aviso de mensajes (MWI)](#7-buzón-de-voz-y-aviso-de-mensajes-mwi)
8. [Teclas BLF y captura dirigida](#8-teclas-blf-y-captura-dirigida)
9. [Aparcamiento de llamadas (Call Park)](#9-aparcamiento-de-llamadas-call-park)
10. [Desvíos y No molestar](#10-desvíos-y-no-molestar)
11. [Cola de llamadas (panel "En espera")](#11-cola-de-llamadas-panel-en-espera)
12. [Acceso AMI para el panel de cola](#12-acceso-ami-para-el-panel-de-cola)
13. [Códecs y calidad de audio](#13-códecs-y-calidad-de-audio)
14. [Seguridad: SIP TLS y SRTP](#14-seguridad-sip-tls-y-srtp)
15. [fail2ban](#15-fail2ban)
16. [Datos que hay que entregar al usuario](#16-datos-que-hay-que-entregar-al-usuario)
17. [Lista de verificación final](#17-lista-de-verificación-final)
18. [Solución de problemas](#18-solución-de-problemas)
19. [Anexo: valores de referencia](#19-anexo-valores-de-referencia)

---

## 1. Requisitos

| Elemento | Mínimo | Recomendado |
|---|---|---|
| FreePBX | 16 | **17** |
| Asterisk | 18 | **20 o 22** |
| Driver SIP | `chan_pjsip` | `chan_pjsip` (chan_sip no está soportado) |
| Módulos FreePBX | Core, Voicemail, Call Waiting, Call Forward, Do-Not-Disturb, Parking, Queues | Además: Music on Hold |

Comprobar los módulos en **Admin → Module Admin** (deben aparecer como *Enabled*), o por consola:

```bash
fwconsole ma list | grep -E "core|voicemail|callwaiting|callforward|donotdisturb|parking|queues|music"
```

**No necesitas** credenciales de administrador de FreePBX en el terminal. NORYXS solo usa:
- una **extensión SIP** por línea;
- opcionalmente, un **usuario AMI limitado** para el panel de cola (sección 12).

---

## 2. Red, puertos y cortafuegos

### 2.1 Puertos que deben estar abiertos desde los puestos con NORYXS hacia la centralita

| Puerto | Protocolo | Uso | ¿Obligatorio? |
|---|---|---|---|
| 5060 | UDP/TCP | SIP | Sí (si se usa UDP/TCP) |
| 5061 | TCP | SIP sobre TLS | Solo si se usa TLS |
| 10000–20000 | UDP | Audio RTP/SRTP | **Sí** |
| 5038 | TCP | AMI (panel de cola) | Solo para el panel "En espera" |

El rango RTP se comprueba en **Settings → Asterisk SIP Settings → General SIP Settings → RTP Port Ranges** (por defecto 10000–20000).

### 2.2 El puesto está en otra red, en una VPN o detrás de NAT

Es el origen del 90 % de los problemas de audio. En **Settings → Asterisk SIP Settings → General SIP Settings**:

- **External Address:** IP pública o la IP con la que los terminales ven la centralita. Pulsar *Detect Network Settings*.
- **Local Networks:** añadir **todas** las redes internas (por ejemplo `192.168.0.0/16`, `10.0.0.0/8` y la red de la VPN).

Y en cada extensión (sección 4): `rtp_symmetric = yes`, `force_rport = yes`, `rewrite_contact = yes`, `direct_media = no`.

### 2.3 bis Puestos que acceden por VPN (NetBird, WireGuard…)

Si la centralita está en una red a la que los puestos solo llegan por VPN (ejemplo validado: centralita en `192.168.1.0/24`, puestos por NetBird), **cada dispositivo con NORYXS necesita la VPN conectada**, también los iPhone. Síntoma sin VPN: la centralita **no recibe ningún REGISTER** (no hay ni siquiera intentos fallidos en `/var/log/asterisk/full`). Añade la red de la VPN y la del router de la VPN a *Local Networks* (sección 2.2) y a la lista blanca de fail2ban si procede.

> **Comprobación rápida:** si la línea queda en "Registrando…" o da **408 Request Timeout**, el puesto no llega a la centralita. Revisa la ruta y la VPN con `ping` y `nc -z IP 5060` antes de tocar FreePBX.

### 2.3 Cortafuegos de FreePBX

Si el módulo Firewall está activo, añade las redes de los puestos como **Trusted** (o al menos *Local*) en **Connectivity → Firewall → Networks**.

---

## 3. Ajustes globales de SIP (PJSIP)

**Settings → Asterisk SIP Settings → SIP Settings [chan_pjsip]:**

| Ajuste | Valor | Para qué |
|---|---|---|
| Allow Transports Reload | Yes | Aplicar cambios sin reiniciar |
| udp `0.0.0.0` puerto 5060 | Yes | Transporte UDP |
| tcp `0.0.0.0` puerto 5060 | Yes (recomendado) | Transporte TCP |
| tls `0.0.0.0` puerto 5061 | Yes si se usa TLS | Ver sección 14 |

**Settings → Asterisk SIP Settings → General SIP Settings:**

| Ajuste | Valor |
|---|---|
| Allow SIP Guests | **No** |
| Allow Anonymous Inbound SIP Calls | **No** |

Pulsar **Submit** y luego **Apply Config**.

---

## 4. Extensiones (una por línea del terminal)

En NORYXS, **cada línea es una extensión**. Si el usuario quiere 2 líneas (por ejemplo 200 y 201), crea 2 extensiones.

**Connectivity → Extensions → Add Extension → Add New SIP [chan_pjsip] Extension** (en FreePBX 16: *Applications → Extensions*)

### Pestaña General

| Campo | Valor |
|---|---|
| User Extension | Número (ej. `200`) |
| Display Name | Nombre que verán los demás (ej. `Linea Principal`) |
| Secret | Contraseña **fuerte** (mín. 16 caracteres). Se entrega al usuario (sección 16) |

### Pestaña Voicemail

| Campo | Valor |
|---|---|
| Enabled | **Yes** |
| Voicemail Password | PIN numérico |

### Pestaña Advanced (valores necesarios)

| Campo | Valor | Motivo |
|---|---|---|
| Max Contacts | **3** (mínimo 2) | NORYXS + teléfono físico/móvil a la vez |
| Remove Existing | Yes | Evita contactos obsoletos tras reiniciar el portátil |
| Qualify Frequency | 60 | Detecta caídas de conexión |
| Allow Subscriptions | **Yes** | BLF y MWI |
| Disallowed Codecs / Allowed Codecs | `g722&ulaw&alaw&opus` | Audio HD (sección 13) |
| DTMF Signaling | RFC 4733 | Tonos DTMF fiables |
| Direct Media | **No** | Necesario con NAT/VPN |
| RTP Symmetric | Yes | NAT |
| Force rport | Yes | NAT |
| Rewrite Contact | Yes | NAT |
| Media Encryption | `No` (o `SRTP via in-SDP` si se usa SRTP, sección 14) | |
| Transport | `0.0.0.0-udp` (o `-tls` si se usa TLS) | |

Pulsar **Submit** y luego **Apply Config**.

> **Creación masiva:** para muchas extensiones usa **Admin → Bulk Handler → Extensions** con un CSV.

---

## 5. Llamada en espera y dos llamadas simultáneas

NORYXS gestiona varias llamadas por línea (retener, alternar, conferencia). Para que la centralita entregue una **segunda llamada a una extensión ocupada**, esa extensión necesita Call Waiting.

- **Connectivity → Extensions → (extensión) → Advanced → Call Waiting: Enable**
- O desde el propio terminal, marcando `*70` (activar) / `*71` (desactivar).
- Por consola: `asterisk -rx "database put CW 200 ENABLED"`

**Síntoma si falta:** la segunda llamada da **ocupado** al llamante en vez de sonar en el terminal.

> **Excepción:** si se usa la **cola de llamadas** (sección 11), Call Waiting no afecta a las llamadas de la cola, porque se configura con "Skip Busy Agents". Las llamadas directas a la extensión sí seguirán entrando como segunda llamada.

---

## 6. Transferencias ciega y atendida

NORYXS usa **SIP REFER** (ciega) y **REFER con Replaces** (atendida). En FreePBX están permitidas por defecto. Comprobar:

- **Extensions → (extensión) → Advanced → Allow Transfer: Yes** (si existe la opción en tu versión).
- Si la extensión pertenece a un *Class of Service* o *Feature Codes* restringidos, comprobar que no bloquea transferencias.

No hace falta configurar los códigos `##` / `*2` de transferencia por DTMF: NORYXS transfiere por señalización SIP.

---

## 7. Buzón de voz y aviso de mensajes (MWI)

1. Activar el buzón en cada extensión (sección 4, pestaña Voicemail).
2. El aviso de mensajes (MWI, RFC 3842) es **automático**: FreePBX asocia `mailboxes = <ext>@default` al endpoint PJSIP y NORYXS se suscribe solo.
3. Código de acceso al buzón: **`*97`** (Admin → Feature Codes → Voicemail → *My Voicemail*). Debe estar **Enabled**.

**Comprobación:**
```bash
asterisk -rx "pjsip show endpoint 200" | grep mailboxes     # → 200@default
asterisk -rx "voicemail show users" | grep 200
```

**Opcional — lista de mensajes uno a uno en el terminal:** activa el envío por email en cada buzón (Voicemail → Email Address + *Email Attachment: Yes*). NORYXS podrá leerlos de esa cuenta por IMAP (función en desarrollo).

---

## 8. Teclas BLF y captura dirigida

### 8.1 BLF (estado de compañeros)
NORYXS se suscribe al evento `dialog` (`application/dialog-info+xml`) de las extensiones configuradas en sus teclas.

- FreePBX crea automáticamente los *hints* de todas las extensiones.
- La extensión **que usa NORYXS** necesita **Allow Subscriptions = Yes** (sección 4).

**Comprobación:**
```bash
asterisk -rx "core show hints" | grep -E "^ *20[0-9]"
```

### 8.2 Captura dirigida (pulsar una tecla BLF que está sonando)
NORYXS marca **`**` + extensión** (por ejemplo `**205`).

- **Admin → Feature Codes → Core → Directed Call Pickup:** código `**`, **Enabled**.
- Si se usan *Pickup Groups*, el usuario debe tener permiso de captura sobre la extensión destino (Extensions → Advanced → Pickup Group / Call Group).

---

## 9. Aparcamiento de llamadas (Call Park)

NORYXS aparca **transfiriendo la llamada a la extensión de aparcamiento** y la recupera **marcando la órbita**.

**Applications → Parking → Default Lot:**

| Campo | Valor de referencia |
|---|---|
| Parking Lot Extension | **70** |
| Parking Lot Starting Position | **71** |
| Number of Slots | **8** (órbitas 71–78) |
| Parking Timeout | 45 s |
| Parked Music Class | default |
| Come Back to Origin | Yes |
| Generate Feature Codes | Yes |

FreePBX publica el estado de cada órbita como un *hint* `*85` + órbita (`*8571` para la 71, `*8572` para la 72…). NORYXS se suscribe a esos hints automáticamente; la llamada aparcada se **recupera marcando la órbita** (`71`).

Si usas otra numeración, indícasela al usuario para que la configure en sus teclas (pestaña SIP → Teclas rápidas).

**Comprobación:**
```bash
asterisk -rx "parking show default"              # Parking Extension 70 · Spaces 71-78
asterisk -rx "core show hints" | grep park-hints   # *8571@park-hints : park:71@parkedcalls …
```

---

## 10. Desvíos y No molestar

NORYXS activa los desvíos y el No molestar **en la propia centralita**, marcando los códigos de servicio estándar de FreePBX. Así **funcionan aunque el ordenador esté apagado**.

**Admin → Feature Codes**, todos **Enabled**:

| Función | Activar | Desactivar | Módulo |
|---|---|---|---|
| Desvío incondicional | `*72` + número | `*73` | Call Forward |
| Desvío si ocupado | `*90` + número | `*91` | Call Forward |
| Desvío si no contesta | `*52` + número | `*53` | Call Forward |
| No molestar | `*78` | `*79` | Do-Not-Disturb |
| Buzón propio | `*97` | — | Voicemail |
| Captura dirigida | `**` + ext | — | Core |

Si cambias algún código, los de NORYXS deben coincidir (consúltalo con soporte NORYXS).

Además, el No molestar de NORYXS responde **486 Busy Here** a las llamadas entrantes. FreePBX las trata como "ocupado" y aplica el destino de ocupado de la extensión (normalmente el buzón).

---

## 11. Cola de llamadas (panel "En espera")

Permite que, mientras el usuario habla, las nuevas llamadas **esperen en una cola con música y aviso de posición**, en vez de dar ocupado o sonar encima. NORYXS las muestra en su panel lateral "En espera".

**Applications → Queues → Add Queue**

### General

| Campo | Valor de referencia |
|---|---|
| Queue Number | `400` |
| Queue Name | `Cola NORYXS` |
| Static Agents | `200,0` (extensión del usuario; una por línea) |
| Ring Strategy | `ringall` |
| **Skip Busy Agents** | **Yes + (ringinuse=no)** ← imprescindible |
| Music on Hold Class | `default` |
| Join Empty / Leave Empty | Yes / No |

### Timing & Agent Options

| Campo | Valor |
|---|---|
| Agent Timeout | 20 s |
| Retry | 2 s |
| Wrap-Up-Time | 0 |
| Max Wait Time | 300 s |

### Caller Position / Announcements

| Campo | Valor |
|---|---|
| Announce Position | Yes |
| Frequency | 30 s |
| Announce Hold Time | No |

### Fail Over Destination
`Voicemail → 200 (unavail)`: si nadie atiende en el tiempo máximo, la llamada va al buzón.

### Events
- **Event When Called:** Yes
- **Member Status Event:** Yes

(Necesarios para que el panel de NORYXS se actualice al instante.)

### Llevar llamadas a la cola
- **Llamadas externas:** Connectivity → **Inbound Routes** → destino *Queues → 400*.
- **Llamadas internas de prueba:** marcar `400` desde otra extensión.

**Comprobación (con la 200 en una llamada y otra extensión llamando al 400):**
```bash
asterisk -rx "queue show 400"
# Debe mostrar: Members … (ringinuse disabled) (In use)  y  Callers: 1. PJSIP/…
```

---

## 12. Acceso AMI para el panel de cola

El panel "En espera" consulta la cola por la **Asterisk Manager Interface (AMI)** y permite *Atender*, *Transferir*, *Al buzón* y *Colgar*. Se usa un **usuario AMI dedicado y limitado**, nunca el usuario interno de FreePBX.

> ⚠️ **Seguridad:** el puerto AMI (5038) **nunca** debe quedar accesible desde Internet. Permítelo solo desde las redes de los puestos, con la ACL del usuario y con el cortafuegos.

### 12.1 Crear el usuario y escuchar en la red local

FreePBX regenera `manager.conf`, así que **no lo edites**. Usa `/etc/asterisk/manager_custom.conf`:

```ini
; NORYXS: AMI accesible desde la LAN para el panel de cola.
; Los usuarios internos de FreePBX siguen limitados a 127.0.0.1 por su propia ACL.
[general](+)
bindaddr = 0.0.0.0

[noryxs]
secret = CONTRASEÑA_LARGA_ALEATORIA
deny   = 0.0.0.0/0.0.0.0
permit = 127.0.0.1/255.255.255.255
permit = 192.168.1.0/255.255.255.0      ; ← redes de los puestos NORYXS
permit = 10.8.0.0/255.255.255.0
read   = call,agent
write  = call
writetimeout = 5000
```

Aplicar:
```bash
chown asterisk:asterisk /etc/asterisk/manager_custom.conf
chmod 640 /etc/asterisk/manager_custom.conf
asterisk -rx "manager reload"
ss -tlnp | grep 5038        # → 0.0.0.0:5038
asterisk -rx "manager show user noryxs"
```

### 12.2 Permisos y por qué

| Permiso | Para qué |
|---|---|
| `read = call,agent` | Ver quién espera en la cola y el estado de los agentes |
| `write = call` | Mover una llamada en espera a la extensión (*Atender/Transferir/Buzón*) o colgarla |

El usuario **no puede** ejecutar comandos de sistema, leer configuración ni originar llamadas arbitrarias. Si lo intenta, Asterisk responde `Permission denied`.

### 12.3 Antes de abrir el puerto, comprueba los usuarios existentes

```bash
awk '/^\[/{s=$0} /^(deny|permit)/{print s": "$0}' /etc/asterisk/manager.conf /etc/asterisk/manager_additional.conf
```
Todos los usuarios internos deben tener `permit=127.0.0.1/…`. Si alguno no lo tiene, **corrígelo antes** de poner `bindaddr = 0.0.0.0`.

### 12.4 Cortafuegos
Permite TCP 5038 **solo** desde las redes de los puestos (Firewall de FreePBX → Trusted, o iptables/nftables).

---

## 13. Códecs y calidad de audio

**Settings → Asterisk SIP Settings → General SIP Settings → Codecs:** marca y ordena:

1. **G.722** (audio HD 16 kHz) ← recomendado en LAN/VPN
2. G.711 µ-law (`ulaw`)
3. G.711 A-law (`alaw`)
4. Opus (si el módulo `codec_opus` está disponible)

En cada extensión, *Allowed Codecs* = `g722&ulaw&alaw&opus`.

NORYXS muestra en directo **jitter, pérdida de paquetes, RTT y MOS** (pulsando el indicador de códec durante la llamada). Un MOS ≥ 4.0 es calidad excelente.

---

## 14. Seguridad: SIP TLS y SRTP

### 14.1 Certificado
**Admin → Certificate Management:** genera uno con Let's Encrypt (si hay nombre DNS público) o importa el certificado de la empresa. Márcalo como **Default**.

### 14.2 Transporte TLS
**Settings → Asterisk SIP Settings → SIP Settings [chan_pjsip]:**
- `tls` → **Yes**, puerto **5061**
- Certificate Manager → el certificado anterior
- SSL Method → `tlsv1_2` (o superior)
- Verify Client → No · Verify Server → Yes

### 14.3 Extensión
- Transport → `0.0.0.0-tls`
- Media Encryption → **SRTP via in-SDP (recommended)**

### 14.4 En NORYXS
Pestaña SIP → Transporte **TLS**, puerto **5061**, Opciones avanzadas → SRTP **Obligatorio**.
Si el certificado es autofirmado, el usuario debe tener la CA instalada o desactivar la verificación (no recomendado).

---

## 15. fail2ban

FreePBX activa fail2ban para SSH, el panel web, Asterisk y Apache. Un puesto con la contraseña SIP mal escrita **puede quedar bloqueado en todos los puertos** (síntoma: "Connection refused").

**Desbloquear:**
```bash
fail2ban-client status                 # lista de filtros
fail2ban-client unban <IP>             # o: fail2ban-client unban --all
```

**Lista blanca de redes internas de confianza** (opcional, decisión del administrador): añade las redes al parámetro `ignoreip` de cada filtro en `/etc/fail2ban/jail.local` y recarga:
```bash
fail2ban-client reload
fail2ban-client get sshd ignoreip
```
> Poner redes en lista blanca reduce la protección frente a equipos de esa red. Valóralo según tu política de seguridad.

---

## 16. Datos que hay que entregar al usuario

Entrega por un canal seguro (nunca por email en claro):

| Dato | Ejemplo | Dónde se pone en NORYXS |
|---|---|---|
| Servidor (IP o dominio) | `192.168.1.10` / `pbx.empresa.com` | SIP → Servidor |
| Puerto y transporte | `5060 UDP` / `5061 TLS` | SIP → Puerto / Transporte |
| Extensión de cada línea | `200`, `201` | SIP → Usuario / Extensión |
| Secreto SIP de cada línea | (contraseña) | SIP → Contraseña (se guarda en el Llavero/Credential Manager) |
| Nombre de cada línea | `Linea Principal` | SIP → Nombre identidad |
| Extensiones para teclas BLF | `200 Recepción`, `205 Soporte` | SIP → Teclas rápidas |
| Órbita de aparcamiento | `70` / `71–78` | SIP → Teclas rápidas (órbita) |
| PIN del buzón | `1234` | Lo pide el propio buzón al marcar `*97` |
| **Panel de cola (opcional):** servidor AMI, puerto, usuario y contraseña, número de cola | `192.168.1.10`, `5038`, `noryxs`, `400` | SIP → Panel de cola |

---

## 17. Lista de verificación final

Marca cada punto con llamadas reales:

- [ ] 1. Las dos líneas se registran (estado "Registrada" en verde).
- [ ] 2. Se recibe una llamada por la línea 1.
- [ ] 3. Se recibe una llamada por la línea 2.
- [ ] 4. Se puede llamar desde cada línea.
- [ ] 5. Dos llamadas simultáneas: al contestar la segunda, la primera queda retenida (con música).
- [ ] 6. Retener y 7. recuperar funcionan.
- [ ] 8. "Alternar" cambia entre las dos llamadas.
- [ ] 9. La transferencia ciega llega al destino.
- [ ] 10. La transferencia atendida permite consultar y completar o cancelar.
- [ ] 11. Los DTMF funcionan (navegar el menú del buzón con `*97`).
- [ ] 12. Colgar una llamada no corta la otra.
- [ ] 13. Tras desconectar la red 1 minuto, la línea vuelve a registrarse sola.
- [ ] 14. Audio en ambos sentidos en las dos líneas.
- [ ] 15. Con dos llamadas, cada interlocutor solo oye su conversación.
- [ ] Buzón: el contador sube al dejar un mensaje.
- [ ] BLF: la tecla de un compañero se pone roja al hablar y dorada al sonar; pulsarla captura la llamada.
- [ ] Aparcar: "Aparcar 71" deja la llamada en la órbita y la tecla 71 parpadea en ámbar.
- [ ] Desvío y No molestar se activan y desactivan desde la cabecera.
- [ ] Cola: con la línea ocupada, una llamada al 400 aparece en "En espera" y se puede atender.

---

## 18. Solución de problemas

| Síntoma en NORYXS | Causa probable | Solución |
|---|---|---|
| "Registrando…" o **408 Request Timeout** | El puesto no llega a la centralita (ruta, VPN, cortafuegos) | `ping` / `nc -z IP 5060`; revisar VPN, Local Networks y cortafuegos |
| **401/403** "Error de autenticación" | Secreto o usuario incorrectos | Revisar el secreto de la extensión; comprobar si fail2ban ha bloqueado la IP |
| "Connection refused" en todo | fail2ban ha bloqueado la IP | `fail2ban-client unban <IP>` (sección 15) |
| Audio en un solo sentido o sin audio | NAT/RTP | `direct_media=no`, `rtp_symmetric/force_rport/rewrite_contact=yes`, External Address y Local Networks, puertos 10000–20000 UDP |
| La llamada conecta pero **no se oye nada** y se corta a los ~30 s | La red del puesto no está en *Local Networks*: Asterisk anuncia su IP **pública** (External Address) en el SDP y en el Contact; el audio y el ACK salen hacia Internet y no vuelven. Caso real: centralita de un cliente 192.168.10.5, puesto en 172.16.0.0/24, SDP con `c=IN IP4 203.0.113.10` | *Settings › Asterisk SIP Settings › Local Networks*: añadir la red del puesto (p. ej. `172.16.0.0/24` o `172.16.0.0/12`) → Submit → Apply Config |
| La segunda llamada da ocupado | Call Waiting desactivado | Sección 5 |
| La cola suena encima de la llamada en curso | Falta *Skip Busy Agents = Yes + (ringinuse=no)* | Sección 11 |
| Tecla BLF gris ("Sin estado") | Suscripciones desactivadas o la extensión no existe | *Allow Subscriptions = Yes*; `core show hints` |
| La app se cerraba al cambiar el estado de una tecla BLF | Fallo de PJSIP 2.17 con NOTIFY incompletos (corregido en NORYXS el 15/11/2026) | Actualizar NORYXS; no requiere cambios en la centralita |
| Los menús de voz (`*97`, IVR) no reaccionan a las teclas | Versiones antiguas de NORYXS solo enviaban DTMF en "modo DTMF" | Actualizar NORYXS; en la centralita `dtmf_mode = rfc4733` |
| Tecla de órbita no parpadea | No existen los hints `*85XX` (Parking mal configurado) | Sección 9: `core show hints` y buscar `park-hints` |
| El contador del buzón no cambia | Buzón desactivado o sin `mailboxes` | Sección 7 |
| `*72`, `*78`… no hacen nada | Código de servicio desactivado o cambiado | Admin → Feature Codes (sección 10) |
| Panel de cola "Sin conexión AMI" | AMI escuchando solo en 127.0.0.1, ACL o cortafuegos | Sección 12: `ss -tlnp | grep 5038`, `permit`, puerto 5038 |
| Panel de cola "Usuario o contraseña AMI incorrectos" | Credenciales | `asterisk -rx "manager show user noryxs"` |
| MOS bajo (< 3.5) | Pérdida de paquetes o jitter en la red/VPN | Revisar Wi-Fi, VPN y QoS; preferir cable |

**Registros útiles en la centralita:**
```bash
asterisk -rvvv                                  # consola en vivo
asterisk -rx "pjsip show contacts"              # quién está registrado
asterisk -rx "pjsip set logger on"              # traza SIP (desactivar después)
tail -f /var/log/asterisk/full
```

---

## 19. Anexo: valores de referencia

Configuración validada en la centralita de pruebas de NORYXS:

| Elemento | Valor |
|---|---|
| Plataforma | FreePBX 17.0.33 · Asterisk 22.11 · Debian 12 |
| Extensiones | 200 *Linea Principal*, 201 *Atencion Directa*, 202 *Soporte* — PJSIP, buzón, Call Waiting, Max Contacts 3, Allow Subscriptions |
| Códecs | g722, ulaw, alaw, opus |
| Aparcamiento | 70 / órbitas 71–78 / 45 s / vuelve al origen |
| Códigos | `*72` `*73` `*90` `*91` `*52` `*53` `*78` `*79` `*97` `**` |
| Cola | 400 *Cola NORYXS* · agente 200 · ringall · Skip Busy Agents (ringinuse=no) · posición cada 30 s · 300 s → buzón 200 |
| AMI | usuario `noryxs` · read=call,agent · write=call · ACL a redes internas · puerto 5038 |
| Resultado de las pruebas | Registro 200/201/202 ✔ · Llamada 200→201 con nombre ✔ · G.722 MOS 4.4 ✔ · DTMF ✔ · Cola: llamada en espera durante conversación y entrega al colgar ✔ · AMI: estado de cola ✔, comandos de sistema denegados ✔ |
