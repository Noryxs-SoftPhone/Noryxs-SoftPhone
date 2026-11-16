/* NORYXS VIRTUAL SIP TERMINAL - PJSIP build configuration */
#define PJ_CONFIG_MAXIMUM_SPEED      1

/* Varias cuentas y llamadas simultáneas (arquitectura preparada para 8 líneas) */
#define PJSUA_MAX_ACC                16
#define PJSUA_MAX_CALLS              16
#define PJSUA_MAX_PLAYERS            16
#define PJSUA_MAX_RECORDERS          4
#define PJSUA_MAX_CONF_PORTS         (PJSUA_MAX_CALLS + 2*PJSUA_MAX_PLAYERS + 8)

/* Seguridad: TLS y SRTP */
#define PJ_HAS_SSL_SOCK              1
#define PJMEDIA_HAS_SRTP             1

/* Sin vídeo: es un teléfono de voz */
#define PJMEDIA_HAS_VIDEO            0

/* Códecs de audio */
#define PJMEDIA_HAS_G711_CODEC       1
#define PJMEDIA_HAS_G722_CODEC       1
#define PJMEDIA_HAS_OPUS_CODEC       1
#define PJMEDIA_HAS_L16_CODEC        0
#define PJMEDIA_HAS_GSM_CODEC        0
#define PJMEDIA_HAS_SPEEX_CODEC      0
#define PJMEDIA_HAS_ILBC_CODEC       0

/* Cancelación de eco */
#define PJMEDIA_HAS_SPEEX_AEC        1
