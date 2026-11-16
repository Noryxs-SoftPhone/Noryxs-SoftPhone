/*
 * Almacenamiento seguro de credenciales en el Llavero de macOS.
 * Las contraseñas SIP nunca se guardan en ficheros de la aplicación.
 */
#include "noryxs_engine.h"

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <stdlib.h>
#include <string.h>

#define NX_KC_SERVICE "com.noryxs.virtual-sip-terminal"

static CFMutableDictionaryRef base_query(const char *key)
{
    CFMutableDictionaryRef q = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFStringRef svc = CFStringCreateWithCString(NULL, NX_KC_SERVICE, kCFStringEncodingUTF8);
    CFStringRef acc = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFDictionarySetValue(q, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(q, kSecAttrService, svc);
    CFDictionarySetValue(q, kSecAttrAccount, acc);
    CFRelease(svc);
    CFRelease(acc);
    return q;
}

NX_API int32_t nx_secret_set(const char *key, const char *value)
{
    CFMutableDictionaryRef q;
    CFDataRef data;
    OSStatus st;

    if (!key || !value) return -10;
    q = base_query(key);
    SecItemDelete(q);

    data = CFDataCreate(NULL, (const UInt8*)value, (CFIndex)strlen(value));
    CFDictionarySetValue(q, kSecValueData, data);
    CFDictionarySetValue(q, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlock);
    st = SecItemAdd(q, NULL);
    CFRelease(data);
    CFRelease(q);
    return st == errSecSuccess ? 0 : (int32_t)st;
}

NX_API char *nx_secret_get(const char *key)
{
    CFMutableDictionaryRef q;
    CFTypeRef result = NULL;
    OSStatus st;
    char *out = NULL;

    if (!key) return NULL;
    q = base_query(key);
    CFDictionarySetValue(q, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(q, kSecMatchLimit, kSecMatchLimitOne);
    st = SecItemCopyMatching(q, &result);
    CFRelease(q);
    if (st == errSecSuccess && result) {
        CFDataRef d = (CFDataRef)result;
        CFIndex n = CFDataGetLength(d);
        out = (char*)malloc((size_t)n + 1);
        memcpy(out, CFDataGetBytePtr(d), (size_t)n);
        out[n] = '\0';
        CFRelease(result);
    }
    return out;
}

NX_API int32_t nx_secret_delete(const char *key)
{
    CFMutableDictionaryRef q;
    OSStatus st;
    if (!key) return -10;
    q = base_query(key);
    st = SecItemDelete(q);
    CFRelease(q);
    return (st == errSecSuccess || st == errSecItemNotFound) ? 0 : (int32_t)st;
}

/* ------------------------------------------------------------------ */
/* Cifrado de datos locales (notas de llamada)                         */
/*   formato: "v1:" + base64( IV[16] | AES-256-CBC(PKCS7) | HMAC-SHA256[32] ) */
/*   clave: 64 bytes aleatorios en el Llavero (32 cifrado + 32 HMAC)   */
/* ------------------------------------------------------------------ */

#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonHMAC.h>

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

/* Obtiene (o crea la primera vez) la clave de 64 bytes del Llavero. */
static int notes_key(unsigned char key[64])
{
    char *stored = nx_secret_get(NX_NOTES_KEY);
    if (stored) {
        size_t n = 0;
        unsigned char *k = b64_decode(stored, &n);
        memset(stored, 0, strlen(stored));
        free(stored);
        if (k && n == 64) {
            memcpy(key, k, 64);
            memset(k, 0, 64);
            free(k);
            return 0;
        }
        free(k);
    }
    {
        char *enc;
        int r;
        if (SecRandomCopyBytes(kSecRandomDefault, 64, key) != errSecSuccess) return -1;
        enc = b64_encode(key, 64);
        if (!enc) return -1;
        r = nx_secret_set(NX_NOTES_KEY, enc);
        memset(enc, 0, strlen(enc));
        free(enc);
        return r == 0 ? 0 : -1;
    }
}

NX_API char *nx_seal(const char *plain)
{
    unsigned char key[64], iv[16], mac[32];
    unsigned char *buf, *ct;
    size_t pn, ctlen = 0, cap;
    char *b64, *out;

    if (!plain) return NULL;
    if (notes_key(key) != 0) return NULL;
    pn = strlen(plain);
    cap = 16 + pn + kCCBlockSizeAES128 + 32;
    buf = (unsigned char*)malloc(cap);
    if (!buf || SecRandomCopyBytes(kSecRandomDefault, 16, iv) != errSecSuccess) { free(buf); return NULL; }
    memcpy(buf, iv, 16);
    ct = buf + 16;
    if (CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 32, iv,
                plain, pn, ct, pn + kCCBlockSizeAES128, &ctlen) != kCCSuccess) {
        memset(key, 0, sizeof(key));
        free(buf);
        return NULL;
    }
    CCHmac(kCCHmacAlgSHA256, key + 32, 32, buf, 16 + ctlen, mac);   /* encrypt-then-MAC */
    memcpy(buf + 16 + ctlen, mac, 32);
    memset(key, 0, sizeof(key));
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
    size_t n = 0, ctlen, plen = 0;
    char *out;
    int diff = 0, i;

    if (!sealed || strncmp(sealed, "v1:", 3) != 0) return NULL;
    raw = b64_decode(sealed + 3, &n);
    if (!raw || n < 16 + 16 + 32) { free(raw); return NULL; }
    if (notes_key(key) != 0) { free(raw); return NULL; }
    ctlen = n - 16 - 32;
    CCHmac(kCCHmacAlgSHA256, key + 32, 32, raw, 16 + ctlen, mac);
    for (i = 0; i < 32; ++i) diff |= mac[i] ^ raw[16 + ctlen + i];   /* comparación en tiempo constante */
    if (diff) { memset(key, 0, sizeof(key)); free(raw); return NULL; }
    out = (char*)malloc(ctlen + 1);
    if (!out || CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 32, raw,
                        raw + 16, ctlen, out, ctlen, &plen) != kCCSuccess) {
        memset(key, 0, sizeof(key));
        free(raw);
        free(out);
        return NULL;
    }
    memset(key, 0, sizeof(key));
    free(raw);
    out[plen] = '\0';
    return out;
}
