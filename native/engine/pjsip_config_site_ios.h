/* NORYXS - PJSIP para iOS (pruebas en iPhone) */
#define PJ_CONFIG_IPHONE             1
#include <pj/config_site_sample.h>

#define PJSUA_MAX_ACC                16
#define PJSUA_MAX_CALLS              16
#define PJSUA_MAX_PLAYERS            16
#define PJSUA_MAX_RECORDERS          4
#define PJSUA_MAX_CONF_PORTS         (PJSUA_MAX_CALLS + 2*PJSUA_MAX_PLAYERS + 8)
#define PJMEDIA_HAS_VIDEO            0
#define PJMEDIA_HAS_SRTP             1
#define PJMEDIA_HAS_G722_CODEC       1
#define PJMEDIA_HAS_SPEEX_AEC        1
#define PJ_HAS_SSL_SOCK              0
