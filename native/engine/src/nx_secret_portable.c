/*
 * Almacenamiento seguro de credenciales en Windows y Linux, y cifrado de las
 * notas locales (mismo formato que nx_secret_mac.c, para que sean equivalentes).
 *
 *   Windows: Administrador de credenciales (wincred, CRED_TYPE_GENERIC,
 *            persistencia por usuario). Destino "com.noryxs.virtual-sip-terminal/<clave>".
 *   Linux:   libsecret (GNOME Keyring / KWallet vía Secret Service).
 *
 * Cifrado de notas: "v1:" + base64( IV[16] | AES-256-CBC(PKCS7) | HMAC-SHA256[32] )
 * con OpenSSL (ya enlazado para el TLS de PJSIP). Clave de 64 bytes aleatorios
 * guardada con nx_secret_set("notes_key_v1").
 */
#include "noryxs_engine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <openssl/crypto.h>

#define NX_KC_SERVICE "com.noryxs.virtual-sip-terminal"

/* ------------------------------------------------------------------ */
#if defined(_WIN32)

#include <windows.h>
#include <wincred.h>

static void target_name(const char *key, char *out, size_t n)
{
    snprintf(out, n, "%s/%s", NX_KC_SERVICE, key);
}

NX_API int32_t nx_secret_set(const char *key, const char *value)
{
    CREDENTIALA c;
    char target[512];
    if (!key || !value) return -10;
    target_name(key, target, sizeof(target));
    memset(&c, 0, sizeof(c));
    c.Type = CRED_TYPE_GENERIC;
    c.TargetName = target;
    c.CredentialBlobSize = (DWORD)strlen(value);
    c.CredentialBlob = (LPBYTE)value;
    c.Persist = CRED_PERSIST_LOCAL_MACHINE;   /* por usuario, sin itinerancia */
    c.UserName = (LPSTR)"NORYXS Terminal";
    return CredWriteA(&c, 0) ? 0 : (int32_t)GetLastError();
}

NX_API char *nx_secret_get(const char *key)
{
    PCREDENTIALA c = NULL;
    char target[512];
    char *out = NULL;
    if (!key) return NULL;
    target_name(key, target, sizeof(target));
    if (!CredReadA(target, CRED_TYPE_GENERIC, 0, &c)) return NULL;
    out = (char*)malloc(c->CredentialBlobSize + 1);
    if (out) {
        memcpy(out, c->CredentialBlob, c->CredentialBlobSize);
        out[c->CredentialBlobSize] = '\0';
    }
    SecureZeroMemory(c->CredentialBlob, c->CredentialBlobSize);
    CredFree(c);
    return out;
}

NX_API int32_t nx_secret_delete(const char *key)
{
    char target[512];
    if (!key) return -10;
    target_name(key, target, sizeof(target));
    if (CredDeleteA(target, CRED_TYPE_GENERIC, 0)) return 0;
    return GetLastError() == ERROR_NOT_FOUND ? 0 : (int32_t)GetLastError();
}

/* ------------------------------------------------------------------ */
#else /* Linux */

#include <libsecret/secret.h>

static const SecretSchema *nx_schema(void)
{
    static const SecretSchema schema = {
        NX_KC_SERVICE, SECRET_SCHEMA_NONE,
        {
            { "key", SECRET_SCHEMA_ATTRIBUTE_STRING },
            { NULL, (SecretSchemaAttributeType)0 },
        }
    };
    return &schema;
}

NX_API int32_t nx_secret_set(const char *key, const char *value)
{
    GError *err = NULL;
    gboolean ok;
    char label[256];
    if (!key || !value) return -10;
    snprintf(label, sizeof(label), "NORYXS Terminal: %s", key);
    ok = secret_password_store_sync(nx_schema(), SECRET_COLLECTION_DEFAULT, label,
                                    value, NULL, &err, "key", key, NULL);
    if (err) { g_error_free(err); return -1; }
    return ok ? 0 : -1;
}

NX_API char *nx_secret_get(const char *key)
{
    GError *err = NULL;
    gchar *pw;
    char *out = NULL;
    if (!key) return NULL;
    pw = secret_password_lookup_sync(nx_schema(), NULL, &err, "key", key, NULL);
    if (err) { g_error_free(err); return NULL; }
    if (pw) {
        out = strdup(pw);
        secret_password_free(pw);
    }
    return out;
}

NX_API int32_t nx_secret_delete(const char *key)
{
    GError *err = NULL;
    if (!key) return -10;
    secret_password_clear_sync(nx_schema(), NULL, &err, "key", key, NULL);
    if (err) { g_error_free(err); return -1; }
    return 0;
}

#endif

/* ------------------------------------------------------------------ */
/* Cifrado de notas (OpenSSL)                                          */
/* ------------------------------------------------------------------ */

#define NX_NOTES_KEY "notes_key_v1"

static const char B64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char *b64_encode(const unsigned char *in, size_t n)
{
    size_t i, o = 0, olen = 4 * ((n + 2) / 3);
    char *out = (char*)malloc(olen + 1);
    if (!out) return NULL;
    for (i = 0; i < n; i += 3) {
        unsigned v = (unsigned)in[i] << 16;
        if (i + 1 < n) v |= (unsigned)in[i + 1] << 8;
        if (i + 2 < n) v |= in[i + 2];
        out[o++] = B64[(v >> 18) & 63];
        out[o++] = B64[(v >> 12) & 63];
        out[o++] = (i + 1 < n) ? B64[(v >> 6) & 63] : '=';
        out[o++] = (i + 2 < n) ? B64[v & 63] : '=';
    }
    out[o] = '\0';
    return out;
}

static int b64_val(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static unsigned char *b64_decode(const char *in, size_t *outlen)
{
    size_t n = strlen(in), i, o = 0;
    unsigned char *out;
    unsigned v = 0;
    int bits = 0;
    out = (unsigned char*)malloc(n * 3 / 4 + 3);
    if (!out) return NULL;
    for (i = 0; i < n; ++i) {
        int d;
        if (in[i] == '=') break;
        d = b64_val(in[i]);
        if (d < 0) continue;
        v = (v << 6) | (unsigned)d;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[o++] = (unsigned char)((v >> bits) & 0xFF);
        }
    }
    *outlen = o;
    return out;
}

static int notes_key(unsigned char key[64])
{
    char *stored = nx_secret_get(NX_NOTES_KEY);
    if (stored) {
        size_t n = 0;
        unsigned char *k = b64_decode(stored, &n);
        OPENSSL_cleanse(stored, strlen(stored));
        free(stored);
        if (k && n == 64) {
            memcpy(key, k, 64);
            OPENSSL_cleanse(k, 64);
            free(k);
            return 0;
        }
        free(k);
    }
    {
        char *enc;
        int r;
        if (RAND_bytes(key, 64) != 1) return -1;
        enc = b64_encode(key, 64);
        if (!enc) return -1;
        r = nx_secret_set(NX_NOTES_KEY, enc);
        OPENSSL_cleanse(enc, strlen(enc));
        free(enc);
        return r == 0 ? 0 : -1;
    }
}

static int aes_cbc(int enc, const unsigned char *key, const unsigned char *iv,
                   const unsigned char *in, size_t n, unsigned char *out, size_t *outlen)
{
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    int l1 = 0, l2 = 0, ok;
    if (!ctx) return -1;
    ok = EVP_CipherInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv, enc) == 1
      && EVP_CipherUpdate(ctx, out, &l1, in, (int)n) == 1
      && EVP_CipherFinal_ex(ctx, out + l1, &l2) == 1;
    EVP_CIPHER_CTX_free(ctx);
    if (!ok) return -1;
    *outlen = (size_t)(l1 + l2);
    return 0;
}

NX_API char *nx_seal(const char *plain)
{
    unsigned char key[64], mac[32];
    unsigned char *buf;
    unsigned int maclen = 0;
    size_t pn, ctlen = 0;
    char *b64, *out;

    if (!plain) return NULL;
    if (notes_key(key) != 0) return NULL;
    pn = strlen(plain);
    buf = (unsigned char*)malloc(16 + pn + 16 + 32);
    if (!buf || RAND_bytes(buf, 16) != 1) { free(buf); OPENSSL_cleanse(key, 64); return NULL; }
    if (aes_cbc(1, key, buf, (const unsigned char*)plain, pn, buf + 16, &ctlen) != 0) {
        OPENSSL_cleanse(key, 64);
        free(buf);
        return NULL;
    }
    HMAC(EVP_sha256(), key + 32, 32, buf, 16 + ctlen, mac, &maclen);   /* encrypt-then-MAC */
    memcpy(buf + 16 + ctlen, mac, 32);
    OPENSSL_cleanse(key, 64);
    b64 = b64_encode(buf, 16 + ctlen + 32);
    free(buf);
    if (!b64) return NULL;
    out = (char*)malloc(strlen(b64) + 4);
    if (out) { memcpy(out, "v1:", 3); strcpy(out + 3, b64); }
    free(b64);
    return out;
}

NX_API char *nx_unseal(const char *sealed)
{
    unsigned char key[64], mac[32];
    unsigned char *raw;
    unsigned int maclen = 0;
    size_t n = 0, ctlen, plen = 0;
    char *out;

    if (!sealed || strncmp(sealed, "v1:", 3) != 0) return NULL;
    raw = b64_decode(sealed + 3, &n);
    if (!raw || n < 16 + 16 + 32) { free(raw); return NULL; }
    if (notes_key(key) != 0) { free(raw); return NULL; }
    ctlen = n - 16 - 32;
    HMAC(EVP_sha256(), key + 32, 32, raw, 16 + ctlen, mac, &maclen);
    if (CRYPTO_memcmp(mac, raw + 16 + ctlen, 32) != 0) {   /* tiempo constante */
        OPENSSL_cleanse(key, 64);
        free(raw);
        return NULL;
    }
    out = (char*)malloc(ctlen + 1);
    if (!out || aes_cbc(0, key, raw, raw + 16, ctlen, (unsigned char*)out, &plen) != 0) {
        OPENSSL_cleanse(key, 64);
        free(raw);
        free(out);
        return NULL;
    }
    OPENSSL_cleanse(key, 64);
    free(raw);
    out[plen] = '\0';
    return out;
}

/* ------------------------------------------------------------------ */
/* Cifrado con PIN (configuración de puestos)                          */
/* ------------------------------------------------------------------ */
#define NX_PIN_ITER 200000

static int pin_key(const char *pin, const unsigned char salt[16], unsigned char key[64]);
static int pin_rand(unsigned char *buf, size_t n);
static int pin_aes(int enc, const unsigned char *key, const unsigned char *iv,
                   const unsigned char *in, size_t n, unsigned char *out, size_t *outlen);
static void pin_hmac(const unsigned char *key, const unsigned char *data, size_t n, unsigned char mac[32]);

NX_API char *nx_pin_seal(const char *plain, const char *pin)
{
    unsigned char key[64], mac[32], *buf;
    size_t pn, ctlen = 0;
    char *b64, *out;
    if (!plain || !pin || !pin[0]) return NULL;
    pn = strlen(plain);
    buf = (unsigned char*)malloc(32 + pn + 16 + 32);
    if (!buf || pin_rand(buf, 32) != 0) { free(buf); return NULL; }   /* sal + IV */
    if (pin_key(pin, buf, key) != 0 ||
        pin_aes(1, key, buf + 16, (const unsigned char*)plain, pn, buf + 32, &ctlen) != 0) {
        memset(key, 0, sizeof(key)); free(buf); return NULL;
    }
    pin_hmac(key + 32, buf, 32 + ctlen, mac);
    memcpy(buf + 32 + ctlen, mac, 32);
    memset(key, 0, sizeof(key));
    b64 = b64_encode(buf, 32 + ctlen + 32);
    free(buf);
    if (!b64) return NULL;
    out = (char*)malloc(strlen(b64) + 6);
    if (out) { memcpy(out, "SSP1:", 5); strcpy(out + 5, b64); }
    free(b64);
    return out;
}

NX_API char *nx_pin_unseal(const char *sealed, const char *pin)
{
    unsigned char key[64], mac[32], *raw;
    size_t n = 0, ctlen, plen = 0;
    char *out;
    int diff = 0, i;
    if (!sealed || !pin || strncmp(sealed, "SSP1:", 5) != 0) return NULL;
    raw = b64_decode(sealed + 5, &n);
    if (!raw || n < 32 + 16 + 32) { free(raw); return NULL; }
    if (pin_key(pin, raw, key) != 0) { free(raw); return NULL; }
    ctlen = n - 32 - 32;
    pin_hmac(key + 32, raw, 32 + ctlen, mac);
    for (i = 0; i < 32; ++i) diff |= mac[i] ^ raw[32 + ctlen + i];
    if (diff) { memset(key, 0, sizeof(key)); free(raw); return NULL; }   /* PIN incorrecto */
    out = (char*)malloc(ctlen + 1);
    if (!out || pin_aes(0, key, raw + 16, raw + 32, ctlen, (unsigned char*)out, &plen) != 0) {
        memset(key, 0, sizeof(key)); free(raw); free(out); return NULL;
    }
    memset(key, 0, sizeof(key));
    free(raw);
    out[plen] = '\0';
    return out;
}

static int pin_key(const char *pin, const unsigned char salt[16], unsigned char key[64])
{
    return PKCS5_PBKDF2_HMAC(pin, (int)strlen(pin), salt, 16, NX_PIN_ITER, EVP_sha256(), 64, key) == 1 ? 0 : -1;
}
static int pin_rand(unsigned char *buf, size_t n)
{
    return RAND_bytes(buf, (int)n) == 1 ? 0 : -1;
}
static int pin_aes(int enc, const unsigned char *key, const unsigned char *iv,
                   const unsigned char *in, size_t n, unsigned char *out, size_t *outlen)
{
    return aes_cbc(enc, key, iv, in, n, out, outlen);
}
static void pin_hmac(const unsigned char *key, const unsigned char *data, size_t n, unsigned char mac[32])
{
    unsigned int l = 0;
    HMAC(EVP_sha256(), key, 32, data, n, mac, &l);
}
