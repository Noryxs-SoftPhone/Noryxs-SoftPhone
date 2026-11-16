# NORYXS VIRTUAL SIP TERMINAL — Especificación

Terminal telefónico virtual profesional para macOS, Windows y Linux.
Resumen fiel de la especificación original (2026-11-14). En caso de duda, manda este documento.

**No** es un panel de administración de centralitas, ni un CRM, ni un dashboard de supervisión.
Es un teléfono IP virtual que se comporta como un terminal físico Yealink, Fanvil o Grandstream,
conectado a FreePBX mediante extensiones SIP. Debe usar un motor SIP real y no simular funciones.

## 1. Plataformas y tecnología
- macOS, Windows y Linux exclusivamente.
- Interfaz: Flutter + Dart.
- Motor: PJSIP nativo integrado por FFI o puente nativo. RTP y SRTP. SIP sobre UDP, TCP y TLS.
- No implementar un motor SIP propio en Dart. Sin servicios cloud: conexión directa a FreePBX.

## 2. Múltiples líneas SIP (característica más importante)
- Mínimo **dos líneas SIP simultáneas**, cada una con su registro, identidad, extensión y estado de llamada.
- Arquitectura ampliable a 4, 6 u 8 líneas.
- Diferenciar cuentas SIP registradas y líneas de llamada; una cuenta puede tener varias sesiones.
- Al menos dos sesiones simultáneas, aunque sean de líneas distintas.
- Cada línea: identificador, nombre, cuenta asociada, extensión, estado de registro, estado telefónico, llamada activa, indicador visual.

## 3. Llamadas entrantes
- Identificar la línea receptora; mostrar número, nombre de contacto si existe y extensión destinataria; tono de llamada; aviso visual.
- Acciones: contestar, rechazar, silenciar tono.
- Con una llamada activa en la línea 1 y otra entrante en la 2: mantener o retener la primera, mostrar la segunda como entrante, poder contestarla y alternar. **Nunca** colgar automáticamente una llamada existente.

## 4. Llamadas salientes
- Desde teclado numérico, número escrito, contacto o historial.
- Elegir la línea de salida antes de llamar y mostrar claramente cuál se usa.

## 5. Funciones telefónicas
- Retener (SIP hold; el interlocutor recibe la música de espera de la centralita) y recuperar.
- Alternar entre dos llamadas.
- Transferencia ciega y atendida (retener, llamar al segundo, hablar, completar o cancelar y recuperar). REFER y mecanismos compatibles con PJSIP/Asterisk.
- Silenciar micrófono, audio on/off, DTMF, volumen, colgar, duración, estado.

## 6. Dos llamadas simultáneas
- Gestor de sesiones; cada llamada con id único.
- Estados: entrante, saliente, sonando, conectando, activa, retenida, transferencia en curso, finalizada, fallida.
- Máquina de estados que impida operaciones incompatibles.
- **Escenario obligatorio:** hablando por L1 → entra llamada por L2 → contestar L2 → L1 queda retenida → alternar → transferir cualquiera → colgar una sin afectar a la otra. El audio RTP no debe mezclarse.

## 7. Interfaz
- Aspecto de teléfono IP moderno, no de dashboard. Fondo blanco, minimalista, tipografía elegante, botones discretos y redondeados, gris claro, texto oscuro, detalles dorados muy sutiles.
- Arriba: logotipo NORYXS, indicador de conexión, estado de cuentas.
- Centro: líneas diferenciadas con extensión, estado, interlocutor, duración e indicador (libre, sonando, ocupada, retenida, desconectada).
- Abajo: teclado 1–9, *, 0, #; campo de número; selector de línea; llamar; borrar.
- Controles con llamada: retener, recuperar, transferir, silenciar, teclado DTMF, colgar; adaptados al estado.
- Diseño de referencia: capturas de referencia (pestañas Terminal, Agenda, Historial, Cuentas SIP).

## 8. Configuración SIP
- Por línea: nombre, usuario, contraseña, servidor, puerto, transporte, dominio, identidad, proxy, expiración, códecs.
- Probar registro. Estados: registrada, registrando, no registrada, error de autenticación, error de conexión.

## 9. Motor PJSIP
- Independiente de Flutter. Registro y gestión de varias cuentas, sesiones, entrantes/salientes, retenciones, transferencias, audio, RTP, DTMF, reconexiones, errores.
- Una instancia PJSIP para todo; no una por llamada. Sincronización correcta motor ↔ interfaz.

## 10. Audio
- Bidireccional. Códecs G.711 A/µ, G.722, Opus si es compatible.
- Micrófono integrado, USB, Bluetooth, altavoces; selección de dispositivos; volumen; silencio; eco; ruido si es compatible.
- Mantener una llamada en espera mientras se atiende otra.

## 11. Seguridad
- SIP TLS, SRTP, verificación de certificados, credenciales en el almacén seguro del sistema, nunca contraseñas en texto plano ni en logs. Sin credenciales administrativas de FreePBX.

## 12. Agenda e historial
- Agenda: nombre, número, empresa, favoritos.
- Historial: entrantes, salientes, perdidas, duración, fecha, línea. Rellamar desde el historial.

## 13. Arquitectura
Módulos: SipAccountManager, SipRegistrationManager, CallSessionManager, MultiLineManager,
CallStateMachine, CallTransferManager, AudioDeviceManager, DtmfManager, ContactManager,
CallHistoryManager, NotificationManager. Sin limitar la lógica a dos líneas fijas.

## 14. Pruebas obligatorias (contra Asterisk/FreePBX real)
1. Registrar dos cuentas a la vez. 2. Recibir por L1. 3. Recibir por L2. 4. Llamar por cada línea.
5. Dos llamadas simultáneas. 6. Retener. 7. Recuperar. 8. Alternar. 9. Transferencia ciega.
10. Transferencia atendida. 11. DTMF. 12. Colgar una sin afectar a la otra.
13. Recuperar registro tras desconexión. 14. Audio bidireccional en ambas líneas. 15. Audio aislado.

## 15. Prioridades
Estabilidad, calidad de audio, dos líneas simultáneas, gestión de sesiones, retención,
recuperación, transferencias, compatibilidad FreePBX, interfaz sencilla y profesional.
Desarrollar por fases y validar cada función con llamadas reales.

---

# Anexo 2 — Productividad en la llamada (solicitado el 15/11/2026)

Sin convertir el terminal en un CRM. Todo se guarda **en local**.

## A2.1 Notas rápidas de llamada
- Desplegable "Nota" en la tarjeta de llamada activa y en cada entrada del historial.
- 2 líneas (máx. ~280 caracteres) vinculadas a ese registro concreto de llamada (ej. "Llamar mañana a las 10:00 — Ref. 402").
- **Cifradas en disco** (AES-256 + HMAC-SHA256, clave en el Llavero). "Borrar historial" borra también las notas.

## A2.2 Etiquetas de contexto con un clic
- 4 píldoras de color bajo la nota: por defecto `Presupuesto`, `Urgente`, `Devolver llamada`, `Resuelto`.
- **Nombres configurables** en ajustes (el color y el orden se mantienen).
- Filtro por etiqueta en el historial.

## A2.3 Copiar resumen de llamada (comprobante)
- Botón "Copiar resumen" en cada entrada del historial. Copia al portapapeles:
  `[NORYXS SIP] 15/11/2026 17:15 • Ext. 201 → +34 612 849 310 (Duración: 04:18) | Etiquetas: … | Nota: …`
- `→` saliente, `←` entrante, `✕` perdida; nombre del contacto si existe.

## A2.4 Identificación del llamante desconocido (offline)
- Etiqueta bajo el número: España con detalle (provincia para fijos, móvil, 900/901/902/80x) y país + móvil/fijo para el resto (principales países).
- No se muestra el operador (portabilidad: no es fiable sin internet).
- Si el número tiene llamadas previas con nota, se muestra **"Última nota"** y sus etiquetas **antes de descolgar** (franja de llamada, tarjeta flotante, notificación iPhone).
- Formato de número unificado (`+34…`, `0034…`, `6…`) para agenda, historial y notas.

## A2.5 Botón para mostrar/ocultar el panel de cola
- Botón discreto en la cabecera (junto al buzón) con el número de llamadas en espera en dorado.
- Muestra u oculta el panel lateral "En espera" en cualquier momento, aunque no haya llamadas en cola.
- Solo visible si el panel de cola está activado en ajustes.
