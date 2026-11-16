/*
 * NORYXS VIRTUAL SIP TERMINAL - Motor telefónico nativo (API C).
 *
 * Capa fina sobre PJSUA. Una única instancia de PJSIP gestiona todas las
 * cuentas y todas las llamadas. La interfaz (Flutter) envía comandos con
 * estas funciones y recibe eventos JSON por el callback registrado en
 * nx_init().
 *
 * Hilos: todas las funciones pueden llamarse desde cualquier hilo.
 * Los eventos se emiten desde hilos de PJSIP; el puntero recibido es
 * memoria propia del receptor y debe liberarse con nx_free().
 */
#ifndef NORYXS_ENGINE_H
#define NORYXS_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  define NX_API __declspec(dllexport)
#else
#  define NX_API __attribute__((visibility("default"))) __attribute__((used))
#endif

/* Recibe un evento JSON. Propiedad del receptor: liberar con nx_free(). */
typedef void (*nx_event_cb)(char *json);

/* Transportes */
#define NX_TRANSPORT_UDP 0
#define NX_TRANSPORT_TCP 1
#define NX_TRANSPORT_TLS 2

/* SRTP */
#define NX_SRTP_DISABLED  0
#define NX_SRTP_OPTIONAL  1
#define NX_SRTP_MANDATORY 2

typedef struct nx_engine_config {
    int32_t     log_level;      /* 0..5. Por defecto 3 */
    int32_t     sip_trace;      /* 1 = volcar mensajes SIP (cabeceras de auth se ocultan) */
    const char *user_agent;     /* NULL = "NORYXS Virtual SIP Terminal" */
    const char *tls_ca_file;    /* Fichero CA para verificar TLS. NULL = autodetectar */
    int32_t     tls_verify;     /* 1 = verificar certificado del servidor */
    const char *stun_server;    /* NULL o "" = sin STUN */
    int32_t     ec_tail_ms;     /* Cancelación de eco. 0 = desactivada, <0 = defecto (200) */
    int32_t     null_audio;     /* 1 = sin tarjeta de sonido (pruebas automáticas) */
} nx_engine_config;

typedef struct nx_account_config {
    const char *display_name;   /* Nombre visible (identidad) */
    const char *username;       /* Usuario SIP / extensión, p.ej. "201" */
    const char *auth_user;      /* Usuario de autenticación. NULL = username */
    const char *password;       /* Nunca se registra en logs */
    const char *server;         /* Host o IP de la centralita */
    int32_t     port;           /* 0 = por defecto (5060 / 5061 TLS) */
    int32_t     transport;      /* NX_TRANSPORT_* */
    const char *domain;         /* Dominio SIP. NULL = server */
    const char *proxy;          /* Proxy de salida opcional, p.ej. "10.0.0.5:5060" */
    int32_t     reg_expires;    /* Segundos. 0 = 300 */
    int32_t     srtp;           /* NX_SRTP_* */
} nx_account_config;

/* ---- Ciclo de vida ---- */
NX_API int32_t nx_init(const nx_engine_config *cfg, nx_event_cb cb);
NX_API void    nx_shutdown(void);
NX_API void    nx_free(char *p);
NX_API const char *nx_version(void);

/* ---- Cuentas (devuelve acc_id >= 0, o < 0 = error) ---- */
NX_API int32_t nx_account_add(const nx_account_config *cfg);
NX_API int32_t nx_account_remove(int32_t acc_id);
NX_API int32_t nx_account_register(int32_t acc_id, int32_t renew); /* 1 = registrar, 0 = desregistrar */

/* ---- Llamadas (devuelve call_id >= 0, o < 0 = error) ---- */
/* dest puede ser "203" o "sip:203@pbx". Si hold_others = 1 retiene las demás llamadas activas. */
NX_API int32_t nx_call_make(int32_t acc_id, const char *dest, int32_t hold_others);
NX_API int32_t nx_call_ringing(int32_t call_id);                     /* 180 */
NX_API int32_t nx_call_answer(int32_t call_id, int32_t hold_others); /* 200 */
NX_API int32_t nx_call_reject(int32_t call_id);                      /* 486 Busy Here */
NX_API int32_t nx_call_hangup(int32_t call_id);
NX_API int32_t nx_call_hold(int32_t call_id);
NX_API int32_t nx_call_unhold(int32_t call_id, int32_t hold_others);
NX_API int32_t nx_call_dtmf(int32_t call_id, const char *digits);    /* RFC 4733 */
NX_API int32_t nx_call_xfer_blind(int32_t call_id, const char *dest);
NX_API int32_t nx_call_xfer_attended(int32_t call_id, int32_t dest_call_id);
NX_API int32_t nx_hangup_all(void);

/* ---- Audio ---- */
NX_API char   *nx_audio_devices(void);  /* JSON; liberar con nx_free() */
NX_API int32_t nx_audio_set_devices(int32_t capture_id, int32_t playback_id); /* -1 = por defecto */
NX_API int32_t nx_audio_set_mute(int32_t muted);
NX_API int32_t nx_audio_set_volume(float speaker, float mic); /* 0.0 .. 2.0, 1.0 = normal */
NX_API int32_t nx_audio_refresh_devices(void);

/* ---- Tonos locales (timbre) ---- */
#define NX_RING_INCOMING 0   /* timbre normal */
#define NX_RING_WAITING  1   /* aviso de llamada en espera (con otra llamada activa) */
#define NX_RING_CLASSIC  2   /* clásico 440+480 Hz */
#define NX_RING_SOFT     3   /* carillón suave */
NX_API int32_t nx_ring_start(int32_t type);
NX_API int32_t nx_ring_stop(void);

/* ---- Almacenamiento seguro (Llavero / Credential Manager / libsecret) ---- */
NX_API int32_t nx_secret_set(const char *key, const char *value);
NX_API char   *nx_secret_get(const char *key);  /* NULL si no existe; liberar con nx_free() */
NX_API int32_t nx_secret_delete(const char *key);

/* ---- No molestar (rechaza entrantes con 486 Busy Here) ---- */
NX_API int32_t nx_set_dnd(int32_t on);

/* Cifrado con PIN (paquetes de configuración de puestos):
 * "SSP1:" + base64( sal[16] | IV[16] | AES-256-CBC | HMAC-SHA256[32] ), clave = PBKDF2-SHA256(PIN, sal, 200000).
 * nx_pin_unseal devuelve NULL si el PIN es incorrecto o el paquete está manipulado. Liberar con nx_free. */
NX_API char *nx_pin_seal(const char *plain, const char *pin);

/* Transcripción local (whisper.cpp) de un WAV grabado. Bloqueante: llamar desde otro hilo.
 * lang: "es", "ca", "en" o "auto". Devuelve texto con [mm:ss] por segmento o NULL (nx_free).
 * No disponible en iOS. */
NX_API char *nx_transcribe(const char *wav, const char *model, const char *lang, int32_t threads);
NX_API char *nx_pin_unseal(const char *sealed, const char *pin);

/* Reproductor de WAV por el altavoz (grabaciones, buzón). Evento {"type":"play","state":"end"} al acabar. */
NX_API int32_t nx_play_start(const char *path);   /* duración en ms o < 0 */
NX_API int32_t nx_play_stop(void);
NX_API int32_t nx_play_pos(void);                 /* ms, o -1 si no reproduce */
NX_API int32_t nx_play_seek(int32_t ms);
/* No molestar solo para una cuenta (línea): sus entrantes reciben 486. */
NX_API int32_t nx_set_dnd_acc(int32_t acc_id, int32_t on);

/* ---- BLF: SUBSCRIBE Event: dialog (dialog-info+xml) ----
 * target: "205" (se completa con el servidor de la cuenta) o URI completa.
 * Devuelve buddy_id >= 0. Eventos: {"type":"blf", buddy_id, dialog_state, direction, ...} */
NX_API int32_t nx_blf_add(int32_t acc_id, const char *target);
NX_API int32_t nx_blf_remove(int32_t buddy_id);
NX_API int32_t nx_blf_refresh(int32_t buddy_id);

/* ---- Conferencia local a 3 (puente PJSIP) ---- */
NX_API int32_t nx_conf_join(void);              /* une todas las llamadas establecidas */
NX_API int32_t nx_conf_split(int32_t keep_call); /* keep_call sigue activa, el resto retenidas */
NX_API int32_t nx_conf_active(void);

/* ---- Grabación local WAV (interlocutor + micrófono) ---- */
NX_API int32_t nx_rec_start(int32_t call_id, const char *path);
NX_API int32_t nx_rec_stop(void);

/* ---- Telemetría RTP: JSON {codec, clock, jitter_x10, rtt_ms, loss_x10, mos_x10, srtp} ---- */
NX_API char   *nx_call_stats(int32_t call_id);

/* ---- Cifrado de datos locales (notas de llamada) ----
 * AES-256-CBC + HMAC-SHA256, clave aleatoria de 64 bytes en el Llavero.
 * nx_seal  → "v1:<base64>" (liberar con nx_free) · nx_unseal → texto o NULL si es inválido o fue manipulado */
NX_API char   *nx_seal(const char *plaintext);
NX_API char   *nx_unseal(const char *sealed);

/* ---- Códecs ---- */
NX_API char   *nx_codecs(void);  /* JSON [{id, priority}]; liberar con nx_free() */
NX_API int32_t nx_codec_set_priority(const char *codec_id, int32_t priority); /* 0 = desactivar, 255 = máx */

/* ---- Red ---- */
NX_API int32_t nx_network_changed(void); /* Cambio de IP / reanudación tras suspensión */

/* Diagnóstico: estado completo en JSON (liberar con nx_free) */
NX_API char   *nx_dump_state(void);

#ifdef __cplusplus
}
#endif

#endif /* NORYXS_ENGINE_H */
