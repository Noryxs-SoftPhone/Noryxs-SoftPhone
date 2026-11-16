/*
 * NORYXS VIRTUAL SIP TERMINAL - Motor telefónico nativo.
 * Implementación sobre PJSUA (API C de alto nivel de PJSIP).
 *
 * Reglas clave:
 *  - Una sola instancia PJSUA para todas las cuentas y llamadas.
 *  - Aislamiento de audio: una llamada solo se conecta a la tarjeta de
 *    sonido si su medio está activo y NO está retenida localmente. Al
 *    retener, el audio se desconecta de inmediato, antes del re-INVITE,
 *    para que nunca se mezclen dos conversaciones.
 *  - Las contraseñas nunca se emiten en eventos ni en logs; las cabeceras
 *    Authorization / Proxy-Authorization se ocultan en las trazas SIP.
 */
#include "noryxs_engine.h"

#include <pjsua-lib/pjsua.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define THIS_FILE "noryxs"
#define NX_VERSION "0.1.0"

#if defined(_MSC_VER)
#  define NX_TLS __declspec(thread)
#else
#  define NX_TLS __thread
#endif

/* ------------------------------------------------------------------ */
/* Estado global                                                       */
/* ------------------------------------------------------------------ */

typedef struct nx_call_slot {
    int in_use;
    int local_hold;     /* retenida por nosotros */
    int xfer_pending;   /* transferencia en curso */
    int conf;           /* participa en la conferencia local a 3 */
} nx_call_slot;

static struct {
    int            initialized;
    nx_event_cb    cb;
    int            log_level;
    int            sip_trace;
    pj_mutex_t    *mutex;
    pj_pool_t     *pool;
    pjsua_transport_id tp_udp, tp_tcp, tp_tls;
    pjsua_acc_id   local_acc;   /* llamadas directas por IP (sin centralita) */
    nx_call_slot   calls[PJSUA_MAX_CALLS];
    float          speaker_level;
    float          mic_level;
    int            muted;
    unsigned       clock_rate;
    pjmedia_port  *ring_port;
    pjsua_conf_port_id ring_slot;
    int            ringing;
    int            dnd;          /* No molestar: rechazar entrantes con 486 */
    pjsua_recorder_id rec_id;    /* grabación en curso */
    pjsua_call_id  rec_call;
} g = { 0 };

static void lock(void)   { if (g.mutex) pj_mutex_lock(g.mutex); }
static void unlock(void) { if (g.mutex) pj_mutex_unlock(g.mutex); }

/* Registra en PJSIP el hilo que llama (los hilos de Dart no lo están). */
static void reg_thread(void)
{
    static NX_TLS pj_thread_desc desc;
    pj_thread_t *t;
    if (!pj_thread_is_registered()) {
        pj_bzero(desc, sizeof(desc));
        pj_thread_register("nx_api", desc, &t);
    }
}

#define API_GUARD() do { if (!g.initialized) return -1; reg_thread(); } while (0)

/* ------------------------------------------------------------------ */
/* Constructor de JSON mínimo                                          */
/* ------------------------------------------------------------------ */

typedef struct jb { char *p; size_t len, cap; int first; } jb;

static void jb_raw(jb *b, const char *s, size_t n)
{
    if (b->len + n + 1 > b->cap) {
        size_t nc = (b->cap ? b->cap * 2 : 256);
        while (nc < b->len + n + 1) nc *= 2;
        b->p = (char*)realloc(b->p, nc);
        b->cap = nc;
    }
    memcpy(b->p + b->len, s, n);
    b->len += n;
    b->p[b->len] = '\0';
}
static void jb_s(jb *b, const char *s) { jb_raw(b, s, strlen(s)); }

static void jb_esc(jb *b, const char *s, size_t n)
{
    size_t i;
    char tmp[8];
    jb_raw(b, "\"", 1);
    for (i = 0; i < n; ++i) {
        unsigned char c = (unsigned char)s[i];
        if (c == '"')       jb_raw(b, "\\\"", 2);
        else if (c == '\\') jb_raw(b, "\\\\", 2);
        else if (c == '\n') jb_raw(b, "\\n", 2);
        else if (c == '\r') jb_raw(b, "\\r", 2);
        else if (c == '\t') jb_raw(b, "\\t", 2);
        else if (c < 0x20) { snprintf(tmp, sizeof(tmp), "\\u%04x", c); jb_s(b, tmp); }
        else jb_raw(b, (const char*)&c, 1);
    }
    jb_raw(b, "\"", 1);
}

static void jb_key(jb *b, const char *k)
{
    if (!b->first) jb_raw(b, ",", 1);
    b->first = 0;
    jb_esc(b, k, strlen(k));
    jb_raw(b, ":", 1);
}
static void jb_obj(jb *b)  { jb_raw(b, "{", 1); b->first = 1; }
static void jb_end(jb *b)  { jb_raw(b, "}", 1); b->first = 0; }
static void jb_str(jb *b, const char *k, const char *v)
{ jb_key(b, k); if (v) jb_esc(b, v, strlen(v)); else jb_s(b, "null"); }
static void jb_pstr(jb *b, const char *k, const pj_str_t *v)
{ jb_key(b, k); jb_esc(b, v->ptr ? v->ptr : "", v->ptr ? (size_t)v->slen : 0); }
static void jb_int(jb *b, const char *k, long v)
{ char t[32]; jb_key(b, k); snprintf(t, sizeof(t), "%ld", v); jb_s(b, t); }
static void jb_bool(jb *b, const char *k, int v)
{ jb_key(b, k); jb_s(b, v ? "true" : "false"); }

static void emit(jb *b)
{
    nx_event_cb cb = g.cb;
    if (cb && b->p) cb(b->p);  /* el receptor libera con nx_free() */
    else free(b->p);
    b->p = NULL;
}

/* ------------------------------------------------------------------ */
/* Logs con ocultación de credenciales                                 */
/* ------------------------------------------------------------------ */

static int starts_with_ci(const char *s, const char *pfx)
{
    while (*pfx) {
        if (tolower((unsigned char)*s) != tolower((unsigned char)*pfx)) return 0;
        ++s; ++pfx;
    }
    return 1;
}

static void log_writer(int level, const char *data, int len)
{
    jb b = { 0 };
    jb lines = { 0 };
    const char *p = data, *end = data + len;

    /* Ocultar valores de cabeceras de autenticación línea a línea */
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        size_t n = nl ? (size_t)(nl - p + 1) : (size_t)(end - p);
        const char *q = p;
        while (q < p + n && (*q == ' ' || *q == '\t')) ++q;
        if (starts_with_ci(q, "Authorization:") ||
            starts_with_ci(q, "Proxy-Authorization:") ||
            starts_with_ci(q, "WWW-Authenticate:") ||
            starts_with_ci(q, "Proxy-Authenticate:"))
        {
            const char *colon = memchr(q, ':', n - (size_t)(q - p));
            jb_raw(&lines, p, (size_t)(colon - p + 1));
            jb_s(&lines, " <oculto>\n");
        } else {
            jb_raw(&lines, p, n);
        }
        p += n;
    }

    jb_obj(&b);
    jb_str(&b, "type", "log");
    jb_int(&b, "level", level);
    jb_key(&b, "msg");
    jb_esc(&b, lines.p ? lines.p : "", lines.len);
    jb_end(&b);
    free(lines.p);
    emit(&b);
}

/* ------------------------------------------------------------------ */
/* Utilidades                                                          */
/* ------------------------------------------------------------------ */

static const char *inv_state_name(pjsip_inv_state s)
{
    switch (s) {
    case PJSIP_INV_STATE_NULL:         return "null";
    case PJSIP_INV_STATE_CALLING:      return "calling";
    case PJSIP_INV_STATE_INCOMING:     return "incoming";
    case PJSIP_INV_STATE_EARLY:        return "early";
    case PJSIP_INV_STATE_CONNECTING:   return "connecting";
    case PJSIP_INV_STATE_CONFIRMED:    return "confirmed";
    case PJSIP_INV_STATE_DISCONNECTED: return "disconnected";
    }
    return "unknown";
}

static const char *media_status_name(pjsua_call_media_status s)
{
    switch (s) {
    case PJSUA_CALL_MEDIA_NONE:        return "none";
    case PJSUA_CALL_MEDIA_ACTIVE:      return "active";
    case PJSUA_CALL_MEDIA_LOCAL_HOLD:  return "local_hold";
    case PJSUA_CALL_MEDIA_REMOTE_HOLD: return "remote_hold";
    case PJSUA_CALL_MEDIA_ERROR:       return "error";
    }
    return "unknown";
}

static void err_text(pj_status_t st, char *buf, size_t n)
{
    pj_str_t s = pj_strerror(st, buf, n);
    buf[s.slen < (pj_ssize_t)n ? s.slen : (pj_ssize_t)n - 1] = '\0';
}

/* Extrae nombre visible y número (user part) de "Name" <sip:user@host> */
static void parse_party(const pj_str_t *info, char *name, size_t nlen,
                        char *num, size_t numlen)
{
    pj_pool_t *pool;
    char *buf;
    pjsip_uri *uri;

    name[0] = '\0';
    num[0] = '\0';
    if (!info->ptr || info->slen <= 0) return;

    pool = pjsua_pool_create("nxparse", 512, 512);
    if (!pool) return;
    buf = (char*)pj_pool_alloc(pool, (pj_size_t)info->slen + 1);
    pj_memcpy(buf, info->ptr, (pj_size_t)info->slen);
    buf[info->slen] = '\0';

    uri = pjsip_parse_uri(pool, buf, (pj_size_t)info->slen, PJSIP_PARSE_URI_AS_NAMEADDR);
    if (uri) {
        pjsip_uri *inner;
        if (PJSIP_URI_SCHEME_IS_SIP(uri) || PJSIP_URI_SCHEME_IS_SIPS(uri) ||
            pjsip_uri_get_uri(uri) != uri)
        {
            pjsip_name_addr *na = (pjsip_name_addr*)uri;
            if (pjsip_uri_get_uri(uri) != uri && na->display.slen > 0) {
                size_t n = (size_t)na->display.slen < nlen - 1 ? (size_t)na->display.slen : nlen - 1;
                memcpy(name, na->display.ptr, n);
                name[n] = '\0';
            }
        }
        inner = (pjsip_uri*)pjsip_uri_get_uri(uri);
        if (PJSIP_URI_SCHEME_IS_SIP(inner) || PJSIP_URI_SCHEME_IS_SIPS(inner)) {
            pjsip_sip_uri *su = (pjsip_sip_uri*)inner;
            size_t n = (size_t)su->user.slen < numlen - 1 ? (size_t)su->user.slen : numlen - 1;
            memcpy(num, su->user.ptr, n);
            num[n] = '\0';
        }
    }
    pj_pool_release(pool);
}

/* ------------------------------------------------------------------ */
/* Audio: conexión de llamadas a la tarjeta de sonido                  */
/* ------------------------------------------------------------------ */

static void audio_detach(pjsua_call_id cid)
{
    pjsua_conf_port_id slot = pjsua_call_get_conf_port(cid);
    if (slot != PJSUA_INVALID_ID) {
        pjsua_conf_disconnect(slot, 0);
        pjsua_conf_disconnect(0, slot);
    }
}

static void audio_attach(pjsua_call_id cid)
{
    pjsua_conf_port_id slot = pjsua_call_get_conf_port(cid);
    if (slot != PJSUA_INVALID_ID) {
        pjsua_conf_connect(slot, 0);
        pjsua_conf_connect(0, slot);
    }
}

/* Desconecta la llamada de la tarjeta y de cualquier otra llamada (conferencia) */
static void audio_isolate(pjsua_call_id cid)
{
    pjsua_call_id ids[PJSUA_MAX_CALLS];
    unsigned i, n = PJ_ARRAY_SIZE(ids);
    pjsua_conf_port_id slot = pjsua_call_get_conf_port(cid);
    audio_detach(cid);
    if (slot == PJSUA_INVALID_ID || pjsua_enum_calls(ids, &n) != PJ_SUCCESS) return;
    for (i = 0; i < n; ++i) {
        pjsua_conf_port_id o = pjsua_call_get_conf_port(ids[i]);
        if (ids[i] == cid || o == PJSUA_INVALID_ID) continue;
        pjsua_conf_disconnect(slot, o);
        pjsua_conf_disconnect(o, slot);
    }
}

/* Conferencia local: cruza el audio de todas las llamadas marcadas y activas */
static void conf_rewire(void)
{
    pjsua_call_id ids[PJSUA_MAX_CALLS];
    unsigned i, j, n = PJ_ARRAY_SIZE(ids);
    if (pjsua_enum_calls(ids, &n) != PJ_SUCCESS) return;
    for (i = 0; i < n; ++i) {
        pjsua_conf_port_id a = pjsua_call_get_conf_port(ids[i]);
        if (a == PJSUA_INVALID_ID || !g.calls[ids[i]].conf || g.calls[ids[i]].local_hold) continue;
        for (j = 0; j < n; ++j) {
            pjsua_conf_port_id b = pjsua_call_get_conf_port(ids[j]);
            if (i == j || b == PJSUA_INVALID_ID || !g.calls[ids[j]].conf || g.calls[ids[j]].local_hold) continue;
            pjsua_conf_connect(a, b);
        }
    }
}

static void apply_levels(void)
{
    pjsua_conf_adjust_tx_level(0, g.speaker_level);
    pjsua_conf_adjust_rx_level(0, g.muted ? 0.0f : g.mic_level);
}

/* ------------------------------------------------------------------ */
/* Eventos                                                             */
/* ------------------------------------------------------------------ */

static void emit_call(pjsua_call_id cid, const char *type)
{
    pjsua_call_info ci;
    jb b = { 0 };
    char rname[128], rnum[128], lname[128], lnum[128];
    int local_hold, xfer;

    if (pjsua_call_get_info(cid, &ci) != PJ_SUCCESS) return;
    parse_party(&ci.remote_info, rname, sizeof(rname), rnum, sizeof(rnum));
    parse_party(&ci.local_info, lname, sizeof(lname), lnum, sizeof(lnum));

    lock();
    local_hold = g.calls[cid].local_hold;
    xfer = g.calls[cid].xfer_pending;
    unlock();

    jb_obj(&b);
    jb_str(&b, "type", type);
    jb_int(&b, "call_id", cid);
    jb_int(&b, "acc_id", ci.acc_id);
    jb_str(&b, "direction", ci.role == PJSIP_ROLE_UAC ? "out" : "in");
    jb_str(&b, "state", inv_state_name(ci.state));
    jb_int(&b, "status_code", ci.last_status);
    jb_pstr(&b, "status_text", &ci.last_status_text);
    jb_str(&b, "media", media_status_name(ci.media_status));
    jb_bool(&b, "local_hold", local_hold);
    jb_bool(&b, "xfer_pending", xfer);
    jb_pstr(&b, "remote_uri", &ci.remote_info);
    jb_str(&b, "remote_name", rname);
    jb_str(&b, "remote_number", rnum);
    jb_str(&b, "local_number", lnum);
    jb_pstr(&b, "sip_call_id", &ci.call_id);
    jb_int(&b, "connect_duration", ci.connect_duration.sec);
    jb_int(&b, "total_duration", ci.total_duration.sec);
    jb_end(&b);
    emit(&b);
}

static void emit_simple(const char *type, const char *k1, long v1,
                        const char *k2, const char *v2)
{
    jb b = { 0 };
    jb_obj(&b);
    jb_str(&b, "type", type);
    if (k1) jb_int(&b, k1, v1);
    if (k2) jb_str(&b, k2, v2);
    jb_end(&b);
    emit(&b);
}

/* ------------------------------------------------------------------ */
/* Callbacks PJSUA                                                     */
/* ------------------------------------------------------------------ */

static void on_reg_started2(pjsua_acc_id acc_id, pjsua_reg_info *info)
{
    jb b = { 0 };
    jb_obj(&b);
    jb_str(&b, "type", "reg");
    jb_int(&b, "acc_id", acc_id);
    jb_str(&b, "state", info->renew ? "registering" : "unregistering");
    jb_int(&b, "code", 0);
    jb_str(&b, "reason", "");
    jb_end(&b);
    emit(&b);
}

static void on_reg_state2(pjsua_acc_id acc_id, pjsua_reg_info *info)
{
    struct pjsip_regc_cbparam *rp = info->cbparam;
    const char *state;
    jb b = { 0 };
    char errbuf[160];
    int code = rp ? rp->code : 0;

    if (rp && rp->status != PJ_SUCCESS && code == 0) {
        state = "connection_error";
    } else if (code / 100 == 2) {
        state = (rp->expiration > 0) ? "registered" : "unregistered";
    } else if (code == 401 || code == 403 || code == 407) {
        state = "auth_error";
    } else if (code == 408 || code == 502 || code == 503 || code == 504 || code == 0) {
        state = "connection_error";
    } else {
        state = "error";
    }

    jb_obj(&b);
    jb_str(&b, "type", "reg");
    jb_int(&b, "acc_id", acc_id);
    jb_str(&b, "state", state);
    jb_int(&b, "code", code);
    if (rp && rp->status != PJ_SUCCESS && code == 0) {
        err_text(rp->status, errbuf, sizeof(errbuf));
        jb_str(&b, "reason", errbuf);
    } else if (rp) {
        jb_pstr(&b, "reason", &rp->reason);
    } else {
        jb_str(&b, "reason", "");
    }
    jb_int(&b, "expires", rp ? (long)rp->expiration : 0);
    jb_end(&b);
    emit(&b);
}

static void on_incoming_call(pjsua_acc_id acc_id, pjsua_call_id cid,
                             pjsip_rx_data *rdata)
{
    PJ_UNUSED_ARG(acc_id);
    PJ_UNUSED_ARG(rdata);
    lock();
    g.calls[cid].in_use = 1;
    g.calls[cid].local_hold = 0;
    g.calls[cid].xfer_pending = 0;
    g.calls[cid].conf = 0;
    unlock();
    if (g.dnd) {
        /* No molestar: 486 para que FreePBX aplique buzón / desborde */
        emit_call(cid, "dnd_rejected");
        pjsua_call_answer(cid, 486, NULL, NULL);
        return;
    }
    /* 180 Ringing: el terminal suena; la interfaz decide contestar/rechazar */
    pjsua_call_answer(cid, 180, NULL, NULL);
    emit_call(cid, "incoming");
}

static void on_call_state(pjsua_call_id cid, pjsip_event *e)
{
    pjsua_call_info ci;
    PJ_UNUSED_ARG(e);
    emit_call(cid, "call");
    if (pjsua_call_get_info(cid, &ci) == PJ_SUCCESS &&
        ci.state == PJSIP_INV_STATE_DISCONNECTED)
    {
        if (g.rec_id != PJSUA_INVALID_ID && g.rec_call == cid) nx_rec_stop();
        lock();
        pj_bzero(&g.calls[cid], sizeof(g.calls[cid]));
        unlock();
    }
}

static void on_call_media_state(pjsua_call_id cid)
{
    pjsua_call_info ci;
    int local_hold;

    if (pjsua_call_get_info(cid, &ci) != PJ_SUCCESS) return;
    lock();
    local_hold = g.calls[cid].local_hold;
    unlock();

    if (!local_hold && (ci.media_status == PJSUA_CALL_MEDIA_ACTIVE ||
                        ci.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD))
    {
        audio_attach(cid);
        conf_rewire();
    } else {
        audio_isolate(cid);
    }

    emit_call(cid, "call");
}

static void on_call_transfer_status(pjsua_call_id cid, int st_code,
                                    const pj_str_t *st_text, pj_bool_t final,
                                    pj_bool_t *p_cont)
{
    jb b = { 0 };
    jb_obj(&b);
    jb_str(&b, "type", "xfer");
    jb_int(&b, "call_id", cid);
    jb_int(&b, "code", st_code);
    jb_pstr(&b, "text", st_text);
    jb_bool(&b, "final", final);
    jb_end(&b);
    emit(&b);

    if (final) {
        lock();
        g.calls[cid].xfer_pending = 0;
        unlock();
        *p_cont = PJ_FALSE;
        if (st_code / 100 == 2) {
            /* Transferencia completada: liberar nuestra pata */
            pjsua_call_hangup(cid, 0, NULL, NULL);
        }
    }
}

static void on_call_replaced(pjsua_call_id old_cid, pjsua_call_id new_cid)
{
    lock();
    g.calls[new_cid].in_use = 1;
    g.calls[new_cid].local_hold = 0;
    unlock();
    emit_simple("replaced", "old_call_id", old_cid, NULL, NULL);
    emit_call(new_cid, "call");
}

/* Buzón de voz (RFC 3842): "Messages-Waiting: yes" / "Voice-Message: 2/5" */
static void on_mwi_info(pjsua_acc_id acc_id, pjsua_mwi_info *mwi)
{
    char body[512];
    int waiting = 0;
    long nnew = 0, nold = 0;
    const char *p;
    jb b = { 0 };
    pjsip_msg_body *mb = (mwi && mwi->rdata) ? mwi->rdata->msg_info.msg->body : NULL;

    body[0] = '\0';
    if (mb && mb->len > 0) {
        unsigned n = mb->len < sizeof(body) - 1 ? mb->len : (unsigned)sizeof(body) - 1;
        memcpy(body, mb->data, n);
        body[n] = '\0';
    }
    for (p = body; *p; ++p) {
        if (starts_with_ci(p, "Messages-Waiting:")) {
            const char *v = p + 17;
            while (*v == ' ') ++v;
            waiting = starts_with_ci(v, "yes");
        } else if (starts_with_ci(p, "Voice-Message:")) {
            sscanf(p + 14, " %ld/%ld", &nnew, &nold);
        }
    }

    jb_obj(&b);
    jb_str(&b, "type", "mwi");
    jb_int(&b, "acc_id", acc_id);
    jb_bool(&b, "waiting", waiting || nnew > 0);
    jb_int(&b, "new", nnew);
    jb_int(&b, "old", nold);
    jb_end(&b);
    emit(&b);
}

/* BLF: estado de diálogo de una extensión supervisada (dialog-info+xml).
 *
 * No se usa pjsua_buddy_get_dlg_event_info(): en PJSIP 2.17 copia campos con
 * puntero nulo y longitud > 0 cuando Asterisk envía NOTIFY sin algunos datos
 * (p.ej. órbitas de aparcamiento), lo que provocaba un cierre de la app.
 * Se analiza el cuerpo del NOTIFY directamente, validando cada campo. */

/* Busca <tag ...>texto</tag> dentro de [p, end) y copia el texto. */
static int xml_text(const char *p, const char *end, const char *tag, char *out, size_t outlen)
{
    char open[48];
    const char *a, *b;
    size_t n;
    out[0] = '\0';
    snprintf(open, sizeof(open), "<%s", tag);
    for (a = p; a && a < end; ++a) {
        a = strstr(a, open);
        if (!a || a >= end) return 0;
        b = a + strlen(open);
        if (*b == '>' || *b == ' ' || *b == '\t' || *b == '\n' || *b == '\r' || *b == '/') break;
    }
    if (!a || a >= end) return 0;
    a = strchr(a, '>');
    if (!a || a >= end || a[-1] == '/') return 0;
    ++a;
    b = strchr(a, '<');
    if (!b || b > end) return 0;
    while (a < b && (*a == ' ' || *a == '\n' || *a == '\r' || *a == '\t')) ++a;
    n = (size_t)(b - a);
    while (n > 0 && (a[n - 1] == ' ' || a[n - 1] == '\n' || a[n - 1] == '\r' || a[n - 1] == '\t')) --n;
    if (n >= outlen) n = outlen - 1;
    memcpy(out, a, n);
    out[n] = '\0';
    return 1;
}

/* Valor de un atributo attr="..." dentro de [p, end). */
static int xml_attr(const char *p, const char *end, const char *attr, char *out, size_t outlen)
{
    char key[48];
    const char *a, *b;
    size_t n;
    out[0] = '\0';
    snprintf(key, sizeof(key), "%s=\"", attr);
    a = strstr(p, key);
    if (!a || a >= end) return 0;
    a += strlen(key);
    b = strchr(a, '"');
    if (!b || b > end) return 0;
    n = (size_t)(b - a);
    if (n >= outlen) n = outlen - 1;
    memcpy(out, a, n);
    out[n] = '\0';
    return 1;
}

static void on_buddy_evsub_dlg_event_state(pjsua_buddy_id bid, pjsip_evsub *sub, pjsip_event *event)
{
    char body[4096], state[32] = "", direction[32] = "", remote[128] = "", remote_uri[160] = "";
    const char *dlg, *dlg_end, *rem, *rem_end;
    pjsua_buddy_info bi;
    pjsip_msg *msg = NULL;
    jb b = { 0 };
    int have_body = 0;

    if (!event || event->type != PJSIP_EVENT_TSX_STATE) return;
    if (event->body.tsx_state.type == PJSIP_EVENT_RX_MSG && event->body.tsx_state.src.rdata)
        msg = event->body.tsx_state.src.rdata->msg_info.msg;
    if (!msg || msg->type != PJSIP_REQUEST_MSG ||
        pjsip_method_cmp(&msg->line.req.method, &pjsip_notify_method) != 0)
        return;   /* solo nos interesan los NOTIFY entrantes */

    body[0] = '\0';
    if (msg->body && msg->body->data && msg->body->len > 0) {
        unsigned n = msg->body->len < sizeof(body) - 1 ? msg->body->len : (unsigned)sizeof(body) - 1;
        memcpy(body, msg->body->data, n);
        body[n] = '\0';
        have_body = 1;
    }

    if (have_body) {
        dlg = strstr(body, "<dialog ");
        if (!dlg) dlg = strstr(body, "<dialog>");
        if (dlg) {
            dlg_end = strstr(dlg, "</dialog>");
            if (!dlg_end) dlg_end = body + strlen(body);
            xml_attr(dlg, dlg_end, "direction", direction, sizeof(direction));
            xml_text(dlg, dlg_end, "state", state, sizeof(state));
            rem = strstr(dlg, "<remote");
            if (rem && rem < dlg_end) {
                rem_end = strstr(rem, "</remote>");
                if (!rem_end || rem_end > dlg_end) rem_end = dlg_end;
                xml_attr(rem, rem_end, "display", remote, sizeof(remote));
                xml_text(rem, rem_end, "identity", remote_uri, sizeof(remote_uri));
            }
        }
    }

    jb_obj(&b);
    jb_str(&b, "type", "blf");
    jb_int(&b, "buddy_id", bid);
    if (pjsua_buddy_get_info(bid, &bi) == PJ_SUCCESS && bi.uri.ptr) jb_pstr(&b, "uri", &bi.uri);
    else jb_str(&b, "uri", "");
    jb_str(&b, "dialog_state", state);      /* early / confirmed / terminated / "" (libre) */
    jb_str(&b, "direction", direction);     /* initiator / recipient */
    jb_str(&b, "remote", remote);
    jb_str(&b, "remote_uri", remote_uri);
    jb_int(&b, "sub_state", sub ? (long)pjsip_evsub_get_state(sub) : 0);
    jb_end(&b);
    emit(&b);
}

static void on_transport_state(pjsip_transport *tp, pjsip_transport_state state,
                               const pjsip_transport_state_info *info)
{
    jb b = { 0 };
    char errbuf[160];
    if (state != PJSIP_TP_STATE_DISCONNECTED) return;

    jb_obj(&b);
    jb_str(&b, "type", "transport");
    jb_str(&b, "state", "disconnected");
    jb_str(&b, "transport", tp->type_name);
    jb_key(&b, "remote");
    jb_esc(&b, tp->remote_name.host.ptr, (size_t)tp->remote_name.host.slen);
    if (info && info->status != PJ_SUCCESS) {
        err_text(info->status, errbuf, sizeof(errbuf));
        jb_str(&b, "reason", errbuf);
    }
    jb_end(&b);
    emit(&b);
}

/* ------------------------------------------------------------------ */
/* Ciclo de vida                                                       */
/* ------------------------------------------------------------------ */

static const char *autodetect_ca(void)
{
    static const char *cands[] = {
        "/etc/ssl/cert.pem",                      /* macOS */
        "/opt/homebrew/etc/openssl@3/cert.pem",   /* Homebrew */
        "/etc/ssl/certs/ca-certificates.crt",     /* Debian/Ubuntu */
        "/etc/pki/tls/certs/ca-bundle.crt",       /* Fedora/RHEL */
        NULL
    };
    int i;
    for (i = 0; cands[i]; ++i) {
        FILE *f = fopen(cands[i], "r");
        if (f) { fclose(f); return cands[i]; }
    }
    return NULL;
}

static void set_default_codecs(void)
{
    pjsua_codec_info ci[64];
    unsigned i, count = PJ_ARRAY_SIZE(ci);
    pj_str_t id;

    if (pjsua_enum_codecs(ci, &count) == PJ_SUCCESS) {
        for (i = 0; i < count; ++i)
            pjsua_codec_set_priority(&ci[i].codec_id, 0);
    }
    /* Orden por defecto: G.722 (HD) > G.711 A-law > G.711 µ-law > Opus */
    pjsua_codec_set_priority(pj_cstr(&id, "G722/16000"), 254);
    pjsua_codec_set_priority(pj_cstr(&id, "PCMA/8000"), 253);
    pjsua_codec_set_priority(pj_cstr(&id, "PCMU/8000"), 252);
    pjsua_codec_set_priority(pj_cstr(&id, "opus/48000"), 200);
}

NX_API const char *nx_version(void) { return NX_VERSION; }
NX_API void nx_free(char *p) { free(p); }

NX_API int32_t nx_init(const nx_engine_config *cfg, nx_event_cb cb)
{
    pjsua_config ua;
    pjsua_logging_config lc;
    pjsua_media_config mc;
    pjsua_transport_config tc;
    pj_status_t st;
    const char *ca;

    if (g.initialized) return 0;

    st = pjsua_create();
    if (st != PJ_SUCCESS) return -1;

    g.cb = cb;
    g.log_level = cfg ? cfg->log_level : 3;
    g.sip_trace = cfg ? cfg->sip_trace : 0;
    g.speaker_level = 1.0f;
    g.mic_level = 1.0f;

    pjsua_config_default(&ua);
    ua.user_agent = pj_str((char*)(cfg && cfg->user_agent ? cfg->user_agent
                                                          : "NORYXS Virtual SIP Terminal/" NX_VERSION));
    ua.max_calls = PJSUA_MAX_CALLS;
    ua.cb.on_reg_started2 = &on_reg_started2;
    ua.cb.on_reg_state2 = &on_reg_state2;
    ua.cb.on_incoming_call = &on_incoming_call;
    ua.cb.on_call_state = &on_call_state;
    ua.cb.on_call_media_state = &on_call_media_state;
    ua.cb.on_call_transfer_status = &on_call_transfer_status;
    ua.cb.on_call_replaced = &on_call_replaced;
    ua.cb.on_transport_state = &on_transport_state;
    ua.cb.on_mwi_info = &on_mwi_info;
    ua.cb.on_buddy_evsub_dlg_event_state = &on_buddy_evsub_dlg_event_state;
    if (cfg && cfg->stun_server && cfg->stun_server[0]) {
        ua.stun_srv_cnt = 1;
        ua.stun_srv[0] = pj_str((char*)cfg->stun_server);
    }

    pjsua_logging_config_default(&lc);
    lc.level = (unsigned)g.log_level;
    lc.console_level = 0;
    lc.msg_logging = g.sip_trace ? PJ_TRUE : PJ_FALSE;
    lc.cb = &log_writer;

    pjsua_media_config_default(&mc);
    mc.ec_tail_len = (cfg && cfg->ec_tail_ms >= 0) ? (unsigned)cfg->ec_tail_ms : 200;
    mc.no_vad = PJ_TRUE;
    g.clock_rate = mc.clock_rate ? mc.clock_rate : 16000;

    st = pjsua_init(&ua, &lc, &mc);
    if (st != PJ_SUCCESS) { pjsua_destroy(); return -2; }

    g.pool = pjsua_pool_create("noryxs", 1024, 1024);
    pj_mutex_create_recursive(g.pool, "nx", &g.mutex);

    /* Transportes: puertos efímeros para convivir con otros softphones */
    pjsua_transport_config_default(&tc);
    tc.port = 0;
    g.tp_udp = g.tp_tcp = g.tp_tls = PJSUA_INVALID_ID;
    pjsua_transport_create(PJSIP_TRANSPORT_UDP, &tc, &g.tp_udp);
    pjsua_transport_create(PJSIP_TRANSPORT_TCP, &tc, &g.tp_tcp);

    pjsua_transport_config_default(&tc);
    tc.port = 0;
    ca = (cfg && cfg->tls_ca_file && cfg->tls_ca_file[0]) ? cfg->tls_ca_file : autodetect_ca();
    if (ca) tc.tls_setting.ca_list_file = pj_str((char*)ca);
    tc.tls_setting.verify_server = (cfg && cfg->tls_verify) ? PJ_TRUE : PJ_FALSE;
    tc.tls_setting.method = PJSIP_TLSV1_2_METHOD;
    pjsua_transport_create(PJSIP_TRANSPORT_TLS, &tc, &g.tp_tls);

    /* Cuenta local: acepta llamadas IP directas (sip:x@ip:puerto) y sirve
     * de cuenta por defecto para peticiones que no encajan con ninguna línea */
    g.local_acc = PJSUA_INVALID_ID;
    if (g.tp_udp != PJSUA_INVALID_ID)
        pjsua_acc_add_local(g.tp_udp, PJ_FALSE, &g.local_acc);

    if (cfg && cfg->null_audio) pjsua_set_null_snd_dev();

    st = pjsua_start();
    if (st != PJ_SUCCESS) { pjsua_destroy(); return -3; }

    set_default_codecs();

    g.rec_id = PJSUA_INVALID_ID;
    g.rec_call = PJSUA_INVALID_ID;
    g.dnd = 0;

    /* Generador de timbre local, conectado a la tarjeta solo mientras suena */
    g.ring_slot = PJSUA_INVALID_ID;
    if (pjmedia_tonegen_create(g.pool, g.clock_rate, 1, g.clock_rate * 20 / 1000,
                               16, PJMEDIA_TONEGEN_LOOP, &g.ring_port) == PJ_SUCCESS)
        pjsua_conf_add_port(g.pool, g.ring_port, &g.ring_slot);

    g.initialized = 1;
    apply_levels();

    {
        pjsua_transport_info ti;
        jb b = { 0 };
        jb_obj(&b);
        jb_str(&b, "type", "ready");
        jb_str(&b, "version", NX_VERSION);
        jb_int(&b, "local_acc", g.local_acc);
        if (pjsua_transport_get_info(g.tp_udp, &ti) == PJ_SUCCESS)
            jb_int(&b, "udp_port", ti.local_name.port);
        jb_end(&b);
        emit(&b);
    }
    return 0;
}

NX_API void nx_shutdown(void)
{
    if (!g.initialized) return;
    reg_thread();
    pjsua_call_hangup_all();
    g.initialized = 0;
    g.cb = NULL;            /* no entregar eventos durante la destrucción */
    pjsua_destroy();
    g.mutex = NULL;
    g.pool = NULL;
    g.ring_port = NULL;
    g.ring_slot = PJSUA_INVALID_ID;
    g.ringing = 0;
    memset(g.calls, 0, sizeof(g.calls));
}

/* ------------------------------------------------------------------ */
/* Timbre                                                              */
/* ------------------------------------------------------------------ */

NX_API int32_t nx_ring_start(int32_t type)
{
    pjmedia_tone_desc t[24];
    unsigned i, n = 0;

    API_GUARD();
    if (!g.ring_port || g.ring_slot == PJSUA_INVALID_ID) return -2;
    pj_bzero(t, sizeof(t));

    if (type == NX_RING_CLASSIC) {
        /* Clásico: 440+480 Hz, 2 s sonando, 4 s de silencio */
        t[n].freq1 = 440; t[n].freq2 = 480; t[n].on_msec = 2000; t[n].off_msec = 4000;
        t[n].volume = 8000; ++n;
    } else if (type == NX_RING_SOFT) {
        /* Suave: carillón de tres notas */
        static const short notes[3] = { 659, 784, 988 };
        for (i = 0; i < 3; ++i) {
            t[n].freq1 = notes[i]; t[n].on_msec = 260; t[n].off_msec = 60;
            t[n].volume = 7000; ++n;
        }
        t[n - 1].off_msec = 2200;
    } else if (type == NX_RING_WAITING) {
        /* Dos pitidos suaves cada 4 s, para no tapar la conversación activa */
        for (i = 0; i < 2; ++i) {
            t[n].freq1 = 440; t[n].on_msec = 180; t[n].off_msec = 180;
            t[n].volume = 6000; ++n;
        }
        t[n - 1].off_msec = 4000;
    } else {
        /* Trino de teléfono de sobremesa: 1 s de trino, 2 s de silencio */
        for (i = 0; i < 20; ++i) {
            t[n].freq1 = (i & 1) ? 1100 : 880;
            t[n].on_msec = 50; t[n].off_msec = 0;
            t[n].volume = 9000; ++n;
        }
        t[n - 1].off_msec = 2000;
    }

    pjmedia_tonegen_stop(g.ring_port);
    pjmedia_tonegen_rewind(g.ring_port);
    pjmedia_tonegen_play(g.ring_port, n, t, PJMEDIA_TONEGEN_LOOP);
    if (!g.ringing) pjsua_conf_connect(g.ring_slot, 0);
    g.ringing = 1;
    return 0;
}

NX_API int32_t nx_ring_stop(void)
{
    API_GUARD();
    if (!g.ring_port) return -2;
    if (g.ringing) pjsua_conf_disconnect(g.ring_slot, 0);
    pjmedia_tonegen_stop(g.ring_port);
    g.ringing = 0;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Cuentas                                                             */
/* ------------------------------------------------------------------ */

static const char *tp_param(int t)
{
    return t == NX_TRANSPORT_TCP ? ";transport=tcp" :
           t == NX_TRANSPORT_TLS ? ";transport=tls" : "";
}

NX_API int32_t nx_account_add(const nx_account_config *c)
{
    pjsua_acc_config ac;
    pjsua_acc_id acc_id;
    char id[256], reg[256], proxy[256], hostport[160];
    const char *domain;
    pj_status_t st;

    API_GUARD();
    if (!c || !c->username || !c->server) return -10;

    domain = (c->domain && c->domain[0]) ? c->domain : c->server;
    if (c->port > 0) snprintf(hostport, sizeof(hostport), "%s:%d", c->server, c->port);
    else             snprintf(hostport, sizeof(hostport), "%s", c->server);

    if (c->display_name && c->display_name[0])
        snprintf(id, sizeof(id), "\"%s\" <sip:%s@%s>", c->display_name, c->username, domain);
    else
        snprintf(id, sizeof(id), "<sip:%s@%s>", c->username, domain);
    snprintf(reg, sizeof(reg), "sip:%s%s", hostport, tp_param(c->transport));

    pjsua_acc_config_default(&ac);
    ac.id = pj_str(id);
    ac.reg_uri = pj_str(reg);
    ac.reg_timeout = c->reg_expires > 0 ? (unsigned)c->reg_expires : 300;
    ac.reg_retry_interval = 30;
    ac.reg_first_retry_interval = 5;
    ac.register_on_acc_add = PJ_TRUE;

    ac.cred_count = 1;
    ac.cred_info[0].realm = pj_str("*");
    ac.cred_info[0].scheme = pj_str("digest");
    ac.cred_info[0].username = pj_str((char*)((c->auth_user && c->auth_user[0]) ? c->auth_user : c->username));
    ac.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    ac.cred_info[0].data = pj_str((char*)(c->password ? c->password : ""));

    if (c->proxy && c->proxy[0]) {
        snprintf(proxy, sizeof(proxy), "sip:%s;lr%s", c->proxy, tp_param(c->transport));
        ac.proxy_cnt = 1;
        ac.proxy[0] = pj_str(proxy);
    }

    ac.transport_id = c->transport == NX_TRANSPORT_TCP ? g.tp_tcp :
                      c->transport == NX_TRANSPORT_TLS ? g.tp_tls : g.tp_udp;
    if (ac.transport_id == PJSUA_INVALID_ID) return -11;

    ac.use_srtp = c->srtp == NX_SRTP_MANDATORY ? PJMEDIA_SRTP_MANDATORY :
                  c->srtp == NX_SRTP_OPTIONAL  ? PJMEDIA_SRTP_OPTIONAL :
                                                 PJMEDIA_SRTP_DISABLED;
    ac.srtp_secure_signaling = 0;   /* permitir SRTP también sobre UDP/TCP */
    ac.mwi_enabled = PJ_TRUE;       /* SUBSCRIBE message-summary por línea */

    st = pjsua_acc_add(&ac, PJ_FALSE, &acc_id);   /* pjsua copia la configuración */
    /* Borrar la copia local de la contraseña de la pila */
    if (st != PJ_SUCCESS) return -12;
    return acc_id;
}

NX_API int32_t nx_account_remove(int32_t acc_id)
{
    API_GUARD();
    return pjsua_acc_del(acc_id) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_account_register(int32_t acc_id, int32_t renew)
{
    API_GUARD();
    return pjsua_acc_set_registration(acc_id, renew ? PJ_TRUE : PJ_FALSE) == PJ_SUCCESS ? 0 : -1;
}

/* ------------------------------------------------------------------ */
/* Llamadas                                                            */
/* ------------------------------------------------------------------ */

static int is_active_call(pjsua_call_id cid)
{
    pjsua_call_info ci;
    if (pjsua_call_get_info(cid, &ci) != PJ_SUCCESS) return 0;
    return ci.state == PJSIP_INV_STATE_CONFIRMED;
}

static pj_status_t do_hold(pjsua_call_id cid)
{
    lock();
    g.calls[cid].local_hold = 1;
    g.calls[cid].conf = 0;
    unlock();
    audio_isolate(cid);  /* aislar audio ya, sin esperar al re-INVITE */
    return pjsua_call_set_hold(cid, NULL);
}

static void hold_others(pjsua_call_id except)
{
    pjsua_call_id ids[PJSUA_MAX_CALLS];
    unsigned i, n = PJ_ARRAY_SIZE(ids);
    int lh;
    if (pjsua_enum_calls(ids, &n) != PJ_SUCCESS) return;
    for (i = 0; i < n; ++i) {
        if (ids[i] == except) continue;
        lock();
        lh = g.calls[ids[i]].local_hold;
        unlock();
        if (!lh && is_active_call(ids[i])) do_hold(ids[i]);
    }
}

NX_API int32_t nx_call_make(int32_t acc_id, const char *dest, int32_t hold)
{
    pjsua_acc_info ai;
    pjsua_call_setting opt;
    pjsua_call_id cid;
    pj_str_t uri;
    char buf[320];
    pj_status_t st;

    API_GUARD();
    if (!dest || !dest[0]) return -10;
    if (pjsua_acc_get_info(acc_id, &ai) != PJ_SUCCESS) return -11;

    if (strncmp(dest, "sip:", 4) == 0 || strncmp(dest, "sips:", 5) == 0) {
        snprintf(buf, sizeof(buf), "%s", dest);
    } else {
        /* Construir sip:destino@<host del registrador> manteniendo el transporte */
        pjsua_acc_config ac;
        pj_pool_t *pool = pjsua_pool_create("nxmk", 512, 512);
        pjsua_acc_get_config(acc_id, pool, &ac);
        /* reg_uri = sip:host[:port][;transport=x] */
        if (ac.reg_uri.slen > 4)
            snprintf(buf, sizeof(buf), "sip:%s@%.*s", dest,
                     (int)ac.reg_uri.slen - 4, ac.reg_uri.ptr + 4);
        else
            snprintf(buf, sizeof(buf), "sip:%s", dest);
        pj_pool_release(pool);
    }

    if (hold) hold_others(PJSUA_INVALID_ID);

    pjsua_call_setting_default(&opt);
    opt.aud_cnt = 1;
    opt.vid_cnt = 0;
    uri = pj_str(buf);
    st = pjsua_call_make_call(acc_id, &uri, &opt, NULL, NULL, &cid);
    if (st != PJ_SUCCESS) return -12;

    lock();
    g.calls[cid].in_use = 1;
    g.calls[cid].local_hold = 0;
    g.calls[cid].xfer_pending = 0;
    unlock();
    return cid;
}

NX_API int32_t nx_call_ringing(int32_t cid)
{
    API_GUARD();
    return pjsua_call_answer(cid, 180, NULL, NULL) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_call_answer(int32_t cid, int32_t hold)
{
    pjsua_call_setting opt;
    API_GUARD();
    if (hold) hold_others(cid);
    pjsua_call_setting_default(&opt);
    opt.aud_cnt = 1;
    opt.vid_cnt = 0;
    return pjsua_call_answer2(cid, &opt, 200, NULL, NULL) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_call_reject(int32_t cid)
{
    API_GUARD();
    return pjsua_call_hangup(cid, 486, NULL, NULL) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_call_hangup(int32_t cid)
{
    API_GUARD();
    return pjsua_call_hangup(cid, 0, NULL, NULL) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_hangup_all(void)
{
    API_GUARD();
    pjsua_call_hangup_all();
    return 0;
}

NX_API int32_t nx_call_hold(int32_t cid)
{
    API_GUARD();
    if (!is_active_call(cid)) return -2;
    return do_hold(cid) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_call_unhold(int32_t cid, int32_t hold)
{
    pjsua_call_setting opt;
    API_GUARD();
    if (!is_active_call(cid)) return -2;
    if (hold) hold_others(cid);
    lock();
    g.calls[cid].local_hold = 0;
    unlock();
    pjsua_call_setting_default(&opt);
    opt.aud_cnt = 1;
    opt.vid_cnt = 0;
    opt.flag = PJSUA_CALL_UNHOLD;
    /* El audio se reconecta en on_call_media_state cuando el medio vuelve a estar activo */
    return pjsua_call_reinvite2(cid, &opt, NULL) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_call_dtmf(int32_t cid, const char *digits)
{
    pj_str_t d;
    API_GUARD();
    if (!digits || !digits[0]) return -10;
    d = pj_str((char*)digits);
    return pjsua_call_dial_dtmf(cid, &d) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_call_xfer_blind(int32_t cid, const char *dest)
{
    pjsua_call_info ci;
    pj_str_t uri;
    char buf[320];
    API_GUARD();
    if (!dest || !dest[0]) return -10;
    if (pjsua_call_get_info(cid, &ci) != PJ_SUCCESS) return -11;

    if (strncmp(dest, "sip:", 4) == 0 || strncmp(dest, "sips:", 5) == 0) {
        snprintf(buf, sizeof(buf), "%s", dest);
    } else {
        pjsua_acc_config ac;
        pj_pool_t *pool = pjsua_pool_create("nxxf", 512, 512);
        pjsua_acc_get_config(ci.acc_id, pool, &ac);
        if (ac.reg_uri.slen > 4)
            snprintf(buf, sizeof(buf), "sip:%s@%.*s", dest,
                     (int)ac.reg_uri.slen - 4, ac.reg_uri.ptr + 4);
        else
            snprintf(buf, sizeof(buf), "sip:%s", dest);
        pj_pool_release(pool);
    }
    lock();
    g.calls[cid].xfer_pending = 1;
    unlock();
    uri = pj_str(buf);
    if (pjsua_call_xfer(cid, &uri, NULL) != PJ_SUCCESS) {
        lock();
        g.calls[cid].xfer_pending = 0;
        unlock();
        return -1;
    }
    return 0;
}

NX_API int32_t nx_call_xfer_attended(int32_t cid, int32_t dest_cid)
{
    API_GUARD();
    if (cid == dest_cid) return -10;
    lock();
    g.calls[cid].xfer_pending = 1;
    unlock();
    /* REFER a la llamada original con Replaces apuntando a la consulta */
    if (pjsua_call_xfer_replaces(cid, dest_cid, PJSUA_XFER_NO_REQUIRE_REPLACES, NULL) != PJ_SUCCESS) {
        lock();
        g.calls[cid].xfer_pending = 0;
        unlock();
        return -1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* Audio                                                               */
/* ------------------------------------------------------------------ */

NX_API char *nx_audio_devices(void)
{
    pjmedia_aud_dev_info info[64];
    unsigned i, count = PJ_ARRAY_SIZE(info);
    int cap = -1, play = -2;
    jb b = { 0 };

    if (!g.initialized) return NULL;
    reg_thread();
    if (pjsua_enum_aud_devs(info, &count) != PJ_SUCCESS) count = 0;
    pjsua_get_snd_dev(&cap, &play);

    jb_obj(&b);
    jb_int(&b, "capture", cap);
    jb_int(&b, "playback", play);
    jb_key(&b, "devices");
    jb_s(&b, "[");
    for (i = 0; i < count; ++i) {
        if (i) jb_s(&b, ",");
        jb_obj(&b);
        jb_int(&b, "id", (long)i);
        jb_str(&b, "name", info[i].name);
        jb_str(&b, "driver", info[i].driver);
        jb_int(&b, "inputs", (long)info[i].input_count);
        jb_int(&b, "outputs", (long)info[i].output_count);
        jb_end(&b);
    }
    jb_s(&b, "]");
    b.first = 0;
    jb_end(&b);
    return b.p;
}

#if defined(__linux__) && !defined(__ANDROID__)
/* Linux: el "primer dispositivo" de ALSA suele ser la tarjeta física (hw:), que
 * PipeWire/PulseAudio tiene ocupada -> no se abre el sonido y las llamadas no
 * arrancan. Se prefiere el PCM que pasa por el servidor de sonido. */
static int linux_preferred_dev(int capture)
{
    static const char *pref[] = { "default", "pipewire", "pulse", "sysdefault" };
    unsigned i, p, count = pjmedia_aud_dev_count();
    for (p = 0; p < PJ_ARRAY_SIZE(pref); ++p) {
        for (i = 0; i < count; ++i) {
            pjmedia_aud_dev_info info;
            if (pjmedia_aud_dev_get_info((pjmedia_aud_dev_index)i, &info) != PJ_SUCCESS) continue;
            if (capture ? info.input_count == 0 : info.output_count == 0) continue;
            if (strcmp(info.name, pref[p]) == 0 ||
                (strncmp(info.name, pref[p], strlen(pref[p])) == 0 && info.name[strlen(pref[p])] == ':'))
                return (int)i;
        }
    }
    return capture ? PJMEDIA_AUD_DEFAULT_CAPTURE_DEV : PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
}
#endif

NX_API int32_t nx_audio_set_devices(int32_t cap, int32_t play)
{
    API_GUARD();
#if defined(__linux__) && !defined(__ANDROID__)
    if (cap < 0) cap = linux_preferred_dev(1);
    if (play < 0) play = linux_preferred_dev(0);
    PJ_LOG(3, ("nx", "Audio Linux: captura=%d reproduccion=%d", cap, play));
#endif
    if (cap < 0) cap = PJMEDIA_AUD_DEFAULT_CAPTURE_DEV;
    if (play < 0) play = PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
    if (pjsua_set_snd_dev(cap, play) != PJ_SUCCESS) return -1;
    apply_levels();
    return 0;
}

NX_API int32_t nx_audio_set_mute(int32_t muted)
{
    API_GUARD();
    g.muted = muted ? 1 : 0;
    apply_levels();
    return 0;
}

NX_API int32_t nx_audio_set_volume(float speaker, float mic)
{
    API_GUARD();
    if (speaker >= 0) g.speaker_level = speaker;
    if (mic >= 0) g.mic_level = mic;
    apply_levels();
    return 0;
}

NX_API int32_t nx_audio_refresh_devices(void)
{
    API_GUARD();
    return pjmedia_aud_dev_refresh() == PJ_SUCCESS ? 0 : -1;
}

/* ------------------------------------------------------------------ */
/* Códecs                                                              */
/* ------------------------------------------------------------------ */

NX_API char *nx_codecs(void)
{
    pjsua_codec_info ci[64];
    unsigned i, count = PJ_ARRAY_SIZE(ci);
    jb b = { 0 };
    if (!g.initialized) return NULL;
    reg_thread();
    if (pjsua_enum_codecs(ci, &count) != PJ_SUCCESS) count = 0;
    jb_s(&b, "[");
    for (i = 0; i < count; ++i) {
        if (i) jb_s(&b, ",");
        jb_obj(&b);
        jb_pstr(&b, "id", &ci[i].codec_id);
        jb_int(&b, "priority", ci[i].priority);
        jb_end(&b);
    }
    jb_s(&b, "]");
    return b.p;
}

NX_API int32_t nx_codec_set_priority(const char *codec_id, int32_t prio)
{
    pj_str_t id;
    API_GUARD();
    if (!codec_id) return -10;
    if (prio < 0) prio = 0;
    if (prio > 255) prio = 255;
    return pjsua_codec_set_priority(pj_cstr(&id, codec_id), (pj_uint8_t)prio) == PJ_SUCCESS ? 0 : -1;
}

/* ------------------------------------------------------------------ */
/* Red y diagnóstico                                                   */
/* ------------------------------------------------------------------ */

NX_API int32_t nx_network_changed(void)
{
    pjsua_ip_change_param p;
    API_GUARD();
    pjsua_ip_change_param_default(&p);
    return pjsua_handle_ip_change(&p) == PJ_SUCCESS ? 0 : -1;
}

NX_API char *nx_dump_state(void)
{
    pjsua_acc_id accs[PJSUA_MAX_ACC];
    pjsua_call_id calls[PJSUA_MAX_CALLS];
    unsigned i, na = PJ_ARRAY_SIZE(accs), nc = PJ_ARRAY_SIZE(calls);
    jb b = { 0 };

    if (!g.initialized) return NULL;
    reg_thread();
    pjsua_enum_accs(accs, &na);
    pjsua_enum_calls(calls, &nc);

    jb_obj(&b);
    jb_key(&b, "accounts");
    jb_s(&b, "[");
    for (i = 0; i < na; ++i) {
        pjsua_acc_info ai;
        if (pjsua_acc_get_info(accs[i], &ai) != PJ_SUCCESS) continue;
        if (i) jb_s(&b, ",");
        jb_obj(&b);
        jb_int(&b, "acc_id", ai.id);
        jb_pstr(&b, "uri", &ai.acc_uri);
        jb_int(&b, "status", ai.status);
        jb_pstr(&b, "status_text", &ai.status_text);
        jb_int(&b, "expires", ai.expires);
        jb_end(&b);
    }
    jb_s(&b, "]");
    b.first = 0;
    jb_key(&b, "calls");
    jb_s(&b, "[");
    for (i = 0; i < nc; ++i) {
        pjsua_call_info ci;
        if (pjsua_call_get_info(calls[i], &ci) != PJ_SUCCESS) continue;
        if (i) jb_s(&b, ",");
        jb_obj(&b);
        jb_int(&b, "call_id", ci.id);
        jb_int(&b, "acc_id", ci.acc_id);
        jb_str(&b, "state", inv_state_name(ci.state));
        jb_str(&b, "media", media_status_name(ci.media_status));
        jb_int(&b, "conf_slot", pjsua_call_get_conf_port(ci.id));
        jb_bool(&b, "local_hold", g.calls[ci.id].local_hold);
        jb_end(&b);
    }
    jb_s(&b, "]");
    b.first = 0;
    jb_end(&b);
    return b.p;
}


/* ------------------------------------------------------------------ */
/* No molestar                                                         */
/* ------------------------------------------------------------------ */

NX_API int32_t nx_set_dnd(int32_t on)
{
    API_GUARD();
    g.dnd = on ? 1 : 0;
    return 0;
}

/* ------------------------------------------------------------------ */
/* BLF (Busy Lamp Field)                                               */
/* ------------------------------------------------------------------ */

NX_API int32_t nx_blf_add(int32_t acc_id, const char *target)
{
    pjsua_buddy_config bc;
    pjsua_buddy_id bid;
    char buf[320];

    API_GUARD();
    if (!target || !target[0]) return -10;
    if (strncmp(target, "sip:", 4) == 0 || strncmp(target, "sips:", 5) == 0) {
        snprintf(buf, sizeof(buf), "%s", target);
    } else {
        pjsua_acc_config ac;
        pj_pool_t *pool = pjsua_pool_create("nxblf", 512, 512);
        if (pjsua_acc_get_config(acc_id, pool, &ac) != PJ_SUCCESS) { pj_pool_release(pool); return -11; }
        if (ac.reg_uri.slen > 4)
            snprintf(buf, sizeof(buf), "sip:%s@%.*s", target, (int)ac.reg_uri.slen - 4, ac.reg_uri.ptr + 4);
        else
            snprintf(buf, sizeof(buf), "sip:%s", target);
        pj_pool_release(pool);
    }
    pjsua_buddy_config_default(&bc);
    bc.uri = pj_str(buf);
    bc.subscribe = PJ_FALSE;           /* sin presencia: solo estado de diálogo */
    bc.subscribe_dlg_event = PJ_TRUE;  /* SUBSCRIBE Event: dialog */
    if (pjsua_buddy_add(&bc, &bid) != PJ_SUCCESS) return -12;
    return bid;
}

NX_API int32_t nx_blf_remove(int32_t buddy_id)
{
    API_GUARD();
    return pjsua_buddy_del(buddy_id) == PJ_SUCCESS ? 0 : -1;
}

NX_API int32_t nx_blf_refresh(int32_t buddy_id)
{
    API_GUARD();
    pjsua_buddy_subscribe_dlg_event(buddy_id, PJ_TRUE);
    return pjsua_buddy_update_dlg_event(buddy_id) == PJ_SUCCESS ? 0 : -1;
}

/* ------------------------------------------------------------------ */
/* Conferencia local a 3                                               */
/* ------------------------------------------------------------------ */

NX_API int32_t nx_conf_join(void)
{
    pjsua_call_id ids[PJSUA_MAX_CALLS];
    unsigned i, n = PJ_ARRAY_SIZE(ids), joined = 0;
    pjsua_call_setting opt;

    API_GUARD();
    if (pjsua_enum_calls(ids, &n) != PJ_SUCCESS) return -1;
    for (i = 0; i < n; ++i) {
        int was_held;
        if (!is_active_call(ids[i])) continue;
        lock();
        was_held = g.calls[ids[i]].local_hold;
        g.calls[ids[i]].conf = 1;
        g.calls[ids[i]].local_hold = 0;
        unlock();
        ++joined;
        if (was_held) {
            pjsua_call_setting_default(&opt);
            opt.aud_cnt = 1;
            opt.vid_cnt = 0;
            opt.flag = PJSUA_CALL_UNHOLD;
            pjsua_call_reinvite2(ids[i], &opt, NULL);  /* el audio se cruza al reactivarse */
        } else {
            audio_attach(ids[i]);
        }
    }
    conf_rewire();
    emit_simple("conf", "members", (long)joined, NULL, NULL);
    return joined >= 2 ? 0 : -2;
}

/* Divide la conferencia: keep_call sigue activa, las demás quedan retenidas */
NX_API int32_t nx_conf_split(int32_t keep_call)
{
    pjsua_call_id ids[PJSUA_MAX_CALLS];
    unsigned i, n = PJ_ARRAY_SIZE(ids);
    API_GUARD();
    if (pjsua_enum_calls(ids, &n) != PJ_SUCCESS) return -1;
    for (i = 0; i < n; ++i) {
        if (!g.calls[ids[i]].conf) continue;
        if (ids[i] == keep_call) {
            lock();
            g.calls[ids[i]].conf = 0;
            unlock();
        } else {
            do_hold(ids[i]);
        }
    }
    audio_isolate(keep_call);
    audio_attach(keep_call);
    emit_simple("conf", "members", 0, NULL, NULL);
    return 0;
}

NX_API int32_t nx_conf_active(void)
{
    pjsua_call_id ids[PJSUA_MAX_CALLS];
    unsigned i, n = PJ_ARRAY_SIZE(ids), c = 0;
    if (!g.initialized || pjsua_enum_calls(ids, &n) != PJ_SUCCESS) return 0;
    for (i = 0; i < n; ++i) if (g.calls[ids[i]].conf) ++c;
    return c >= 2;
}

/* ------------------------------------------------------------------ */
/* Grabación local (WAV): voz remota + micrófono                       */
/* ------------------------------------------------------------------ */

NX_API int32_t nx_rec_start(int32_t call_id, const char *path)
{
    pj_str_t p;
    pjsua_conf_port_id rs, cs;
    API_GUARD();
    if (!path || !path[0]) return -10;
    if (g.rec_id != PJSUA_INVALID_ID) nx_rec_stop();
    cs = pjsua_call_get_conf_port(call_id);
    if (cs == PJSUA_INVALID_ID) return -11;
    p = pj_str((char*)path);
    if (pjsua_recorder_create(&p, 0, NULL, -1, 0, &g.rec_id) != PJ_SUCCESS) {
        g.rec_id = PJSUA_INVALID_ID;
        return -12;
    }
    rs = pjsua_recorder_get_conf_port(g.rec_id);
    pjsua_conf_connect(cs, rs);  /* interlocutor */
    pjsua_conf_connect(0, rs);   /* nuestro micrófono */
    g.rec_call = call_id;
    {
        jb b = { 0 };
        jb_obj(&b);
        jb_str(&b, "type", "rec");
        jb_bool(&b, "recording", 1);
        jb_int(&b, "call_id", call_id);
        jb_str(&b, "path", path);
        jb_end(&b);
        emit(&b);
    }
    return 0;
}

NX_API int32_t nx_rec_stop(void)
{
    API_GUARD();
    if (g.rec_id == PJSUA_INVALID_ID) return 0;
    pjsua_recorder_destroy(g.rec_id);
    g.rec_id = PJSUA_INVALID_ID;
    emit_simple("rec", "call_id", g.rec_call, NULL, NULL);
    g.rec_call = PJSUA_INVALID_ID;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Telemetría RTP                                                      */
/* ------------------------------------------------------------------ */

static double estimate_mos(double rtt_ms, double jitter_ms, double loss_pct)
{
    double lat = rtt_ms / 2.0 + 2.0 * jitter_ms + 10.0;
    double r = 93.2 - (lat < 160.0 ? lat / 40.0 : (lat - 120.0) / 10.0) - 2.5 * loss_pct;
    double mos;
    if (r < 0) r = 0;
    if (r > 100) r = 100;
    mos = 1.0 + 0.035 * r + 0.000007 * r * (r - 60.0) * (100.0 - r);
    if (mos < 1.0) mos = 1.0;
    if (mos > 4.5) mos = 4.5;
    return mos;
}

NX_API char *nx_call_stats(int32_t call_id)
{
    pjsua_stream_stat st;
    pjsua_stream_info si;
    pjmedia_transport_info ti;
    jb b = { 0 };
    char codec[64] = "";
    unsigned clock = 0, i;
    double jitter = 0, rtt = 0, loss = 0;
    int srtp = 0;

    if (!g.initialized) return NULL;
    reg_thread();
    if (pjsua_call_get_stream_info(call_id, 0, &si) == PJ_SUCCESS && si.type == PJMEDIA_TYPE_AUDIO) {
        snprintf(codec, sizeof(codec), "%.*s", (int)si.info.aud.fmt.encoding_name.slen,
                 si.info.aud.fmt.encoding_name.ptr);
        clock = si.info.aud.fmt.clock_rate;
    }
    if (pjsua_call_get_stream_stat(call_id, 0, &st) == PJ_SUCCESS) {
        unsigned rx = st.rtcp.rx.pkt + st.rtcp.rx.loss;
        jitter = st.rtcp.rx.jitter.n ? st.rtcp.rx.jitter.mean / 1000.0 : 0;
        rtt = st.rtcp.rtt.n ? st.rtcp.rtt.last / 1000.0 : 0;
        loss = rx ? 100.0 * st.rtcp.rx.loss / rx : 0;
    }
    pjmedia_transport_info_init(&ti);
    if (pjsua_call_get_med_transport_info(call_id, 0, &ti) == PJ_SUCCESS) {
        for (i = 0; i < ti.specific_info_cnt; ++i) {
            if (ti.spc_info[i].type == PJMEDIA_TRANSPORT_TYPE_SRTP) {
                pjmedia_srtp_info *sri = (pjmedia_srtp_info*)ti.spc_info[i].buffer;
                srtp = sri->active ? 1 : 0;
            }
        }
    }
    jb_obj(&b);
    jb_str(&b, "codec", codec);
    jb_int(&b, "clock", (long)clock);
    jb_int(&b, "jitter_x10", (long)(jitter * 10 + 0.5));
    jb_int(&b, "rtt_ms", (long)(rtt + 0.5));
    jb_int(&b, "loss_x10", (long)(loss * 10 + 0.5));
    jb_int(&b, "mos_x10", (long)(estimate_mos(rtt, jitter, loss) * 10 + 0.5));
    jb_bool(&b, "srtp", srtp);
    jb_end(&b);
    return b.p;
}
