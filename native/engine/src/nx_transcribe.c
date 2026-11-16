/*
 * Transcripción local de grabaciones con whisper.cpp (sin enviar nada a internet).
 *
 *   char *nx_transcribe(const char *wav, const char *model, const char *lang, int threads)
 *
 * Lee el WAV PCM de 16 bits que graba el motor (cualquier frecuencia y canales), lo pasa a
 * 16 kHz mono en coma flotante y lo transcribe. Devuelve el texto con una marca [mm:ss] por
 * segmento, o NULL si falla. Liberar con nx_free(). Es bloqueante: llamarla desde un hilo
 * aparte (en Dart, desde un Isolate).
 */
#include "noryxs_engine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "whisper.h"

#ifdef _WIN32
#include <windows.h>
static CRITICAL_SECTION g_lock;
static int g_lock_init = 0;
static void tr_lock(void) { if (!g_lock_init) { InitializeCriticalSection(&g_lock); g_lock_init = 1; } EnterCriticalSection(&g_lock); }
static void tr_unlock(void) { LeaveCriticalSection(&g_lock); }
#else
#include <pthread.h>
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static void tr_lock(void) { pthread_mutex_lock(&g_lock); }
static void tr_unlock(void) { pthread_mutex_unlock(&g_lock); }
#endif

/* El modelo se carga una vez y se reutiliza (cargarlo cuesta ~0,5 s). */
static struct whisper_context *g_ctx = NULL;
static char g_model[1024] = "";

static unsigned rd16(const unsigned char *p) { return (unsigned)p[0] | ((unsigned)p[1] << 8); }
static unsigned rd32(const unsigned char *p) { return rd16(p) | (rd16(p + 2) << 16); }

/* Lee un WAV PCM16 y devuelve muestras float mono a 16 kHz. */
static float *read_wav_16k(const char *path, int *out_n)
{
    FILE *f = fopen(path, "rb");
    unsigned char hdr[12], ch[8];
    unsigned rate = 0, chans = 0, bits = 0, data_len = 0;
    unsigned char *data = NULL;
    float *mono, *out;
    long frames, i, n16;

    *out_n = 0;
    if (!f) return NULL;
    if (fread(hdr, 1, 12, f) != 12 || memcmp(hdr, "RIFF", 4) || memcmp(hdr + 8, "WAVE", 4)) { fclose(f); return NULL; }
    while (fread(ch, 1, 8, f) == 8) {
        unsigned len = rd32(ch + 4);
        if (!memcmp(ch, "fmt ", 4)) {
            unsigned char fmt[40];
            unsigned take = len < sizeof(fmt) ? len : sizeof(fmt);
            if (fread(fmt, 1, take, f) != take) break;
            if (len > take) fseek(f, (long)(len - take), SEEK_CUR);
            if (rd16(fmt) != 1) { fclose(f); return NULL; }   /* solo PCM */
            chans = rd16(fmt + 2);
            rate = rd32(fmt + 4);
            bits = rd16(fmt + 14);
        } else if (!memcmp(ch, "data", 4)) {
            data_len = len;
            data = (unsigned char*)malloc(len ? len : 1);
            if (!data || fread(data, 1, len, f) != len) { free(data); data = NULL; }
            break;
        } else {
            fseek(f, (long)(len + (len & 1)), SEEK_CUR);
        }
    }
    fclose(f);
    if (!data || bits != 16 || chans == 0 || rate == 0) { free(data); return NULL; }

    frames = (long)(data_len / (2 * chans));
    mono = (float*)malloc(sizeof(float) * (size_t)(frames ? frames : 1));
    if (!mono) { free(data); return NULL; }
    for (i = 0; i < frames; ++i) {
        long acc = 0;
        unsigned c;
        for (c = 0; c < chans; ++c) {
            const unsigned char *p = data + (i * chans + c) * 2;
            acc += (short)rd16(p);
        }
        mono[i] = (float)acc / (float)chans / 32768.0f;
    }
    free(data);

    if (rate == WHISPER_SAMPLE_RATE) { *out_n = (int)frames; return mono; }
    /* Remuestreo lineal a 16 kHz (suficiente para voz) */
    n16 = (long)((double)frames * WHISPER_SAMPLE_RATE / rate);
    out = (float*)malloc(sizeof(float) * (size_t)(n16 ? n16 : 1));
    if (!out) { free(mono); return NULL; }
    for (i = 0; i < n16; ++i) {
        double pos = (double)i * rate / WHISPER_SAMPLE_RATE;
        long j = (long)pos;
        double fr = pos - (double)j;
        float a = mono[j < frames ? j : frames - 1];
        float b = mono[j + 1 < frames ? j + 1 : frames - 1];
        out[i] = (float)(a + (b - a) * fr);
    }
    free(mono);
    *out_n = (int)n16;
    return out;
}

static void quiet_log(enum ggml_log_level level, const char *text, void *user)
{
    (void)level; (void)text; (void)user;
}

NX_API char *nx_transcribe(const char *wav, const char *model, const char *lang, int32_t threads)
{
    struct whisper_full_params wp;
    float *pcm;
    int n = 0, segs, i;
    size_t cap = 4096, len = 0;
    char *out;

    if (!wav || !model) return NULL;
    pcm = read_wav_16k(wav, &n);
    if (!pcm || n < WHISPER_SAMPLE_RATE / 2) { free(pcm); return NULL; }   /* < 0,5 s: nada que transcribir */

    tr_lock();
    if (!g_ctx || strcmp(g_model, model) != 0) {
        struct whisper_context_params cp = whisper_context_default_params();
        if (g_ctx) whisper_free(g_ctx);
        whisper_log_set(quiet_log, NULL);
        cp.use_gpu = false;
        g_ctx = whisper_init_from_file_with_params(model, cp);
        snprintf(g_model, sizeof(g_model), "%s", g_ctx ? model : "");
    }
    if (!g_ctx) { tr_unlock(); free(pcm); return NULL; }

    wp = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wp.n_threads = threads > 0 ? threads : 4;
    wp.language = (lang && lang[0]) ? lang : "auto";
    wp.translate = false;
    wp.no_context = true;
    wp.print_progress = false;
    wp.print_realtime = false;
    wp.print_special = false;
    wp.print_timestamps = false;
    wp.suppress_blank = true;

    if (whisper_full(g_ctx, wp, pcm, n) != 0) { tr_unlock(); free(pcm); return NULL; }
    free(pcm);

    out = (char*)malloc(cap);
    if (!out) { tr_unlock(); return NULL; }
    out[0] = '\0';
    segs = whisper_full_n_segments(g_ctx);
    for (i = 0; i < segs; ++i) {
        const char *t = whisper_full_get_segment_text(g_ctx, i);
        long cs = (long)whisper_full_get_segment_t0(g_ctx, i);   /* centésimas de segundo */
        char stamp[24];
        size_t need;
        while (t && *t == ' ') ++t;
        if (!t || !*t) continue;
        snprintf(stamp, sizeof(stamp), "[%02ld:%02ld] ", cs / 6000, (cs / 100) % 60);
        need = len + strlen(stamp) + strlen(t) + 2;
        if (need > cap) {
            char *bigger;
            while (cap < need) cap *= 2;
            bigger = (char*)realloc(out, cap);
            if (!bigger) break;
            out = bigger;
        }
        len += (size_t)sprintf(out + len, "%s%s\n", stamp, t);
    }
    tr_unlock();
    return out;
}
