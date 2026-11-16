/*
 * nx_cli - prueba del motor NORYXS desde terminal, sin interfaz gráfica.
 *
 * Uso:  nx_cli cuentas.conf
 *
 * cuentas.conf: una cuenta por línea (las líneas con # se ignoran):
 *   nombre|usuario|contraseña|servidor|puerto|transporte(udp/tcp/tls)|srtp(0/1/2)
 *   Linea 1|201|secreto|192.168.1.10|5060|udp|0
 *
 * Comandos (escribir y pulsar Enter):
 *   call <acc> <numero>     llamar desde la cuenta <acc>
 *   answer <cid>            contestar (retiene las demás)
 *   reject <cid>            rechazar (486)
 *   hangup <cid>            colgar
 *   hold <cid> / unhold <cid>
 *   dtmf <cid> <digitos>
 *   xfer <cid> <numero>     transferencia ciega
 *   axfer <cid> <cid2>      transferencia atendida (cid retenida, cid2 consulta)
 *   mute 0|1
 *   devs                    dispositivos de audio
 *   state                   estado completo
 *   rereg <acc>             forzar registro
 *   quit
 */
#include "noryxs_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_verbose = 0;

static void on_event(char *json)
{
    if (strncmp(json, "{\"type\":\"log\"", 13) != 0 || g_verbose)
        printf("<< %s\n", json);
    fflush(stdout);
    nx_free(json);
}

static int load_accounts(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[512];
    int n = 0;
    if (!f) { perror(path); return -1; }
    while (fgets(line, sizeof(line), f)) {
        char *fld[7] = { 0 };
        char *p = line, *s;
        int i = 0;
        nx_account_config c;
        int id;

        line[strcspn(line, "\r\n")] = '\0';
        if (!line[0] || line[0] == '#') continue;
        while (i < 7 && (s = strsep(&p, "|")) != NULL) fld[i++] = s;
        if (i < 6) { fprintf(stderr, "línea inválida en %s\n", path); continue; }

        memset(&c, 0, sizeof(c));
        c.display_name = fld[0];
        c.username = fld[1];
        c.password = fld[2];
        c.server = fld[3];
        c.port = atoi(fld[4]);
        c.transport = strcmp(fld[5], "tls") == 0 ? NX_TRANSPORT_TLS :
                      strcmp(fld[5], "tcp") == 0 ? NX_TRANSPORT_TCP : NX_TRANSPORT_UDP;
        c.srtp = fld[6] ? atoi(fld[6]) : 0;
        c.reg_expires = 300;
        id = nx_account_add(&c);
        printf("== cuenta '%s' (%s) -> acc_id %d\n", fld[0], fld[1], id);
        memset(fld[2], 0, strlen(fld[2]));   /* borrar contraseña de memoria */
        ++n;
    }
    fclose(f);
    return n;
}

int main(int argc, char **argv)
{
    nx_engine_config cfg;
    char line[512];

    if (argc < 2) { fprintf(stderr, "uso: %s cuentas.conf [-v] [-null]\n", argv[0]); return 1; }

    memset(&cfg, 0, sizeof(cfg));
    cfg.log_level = 3;
    cfg.ec_tail_ms = -1;
    for (int i = 2; i < argc; ++i) {
        if (!strcmp(argv[i], "-v")) { g_verbose = 1; cfg.log_level = 5; cfg.sip_trace = 1; }
        if (!strcmp(argv[i], "-null")) cfg.null_audio = 1;
    }

    if (nx_init(&cfg, on_event) != 0) { fprintf(stderr, "nx_init falló\n"); return 1; }
    printf("== NORYXS engine %s\n", nx_version());
    if (load_accounts(argv[1]) < 0) { nx_shutdown(); return 1; }

    while (fgets(line, sizeof(line), stdin)) {
        char cmd[32] = "", a[256] = "", b[256] = "";
        int r = 0;
        line[strcspn(line, "\r\n")] = '\0';
        if (sscanf(line, "%31s %255s %255s", cmd, a, b) < 1) continue;

        if      (!strcmp(cmd, "quit"))   break;
        else if (!strcmp(cmd, "call"))   r = nx_call_make(atoi(a), b, 1);
        else if (!strcmp(cmd, "answer")) r = nx_call_answer(atoi(a), 1);
        else if (!strcmp(cmd, "reject")) r = nx_call_reject(atoi(a));
        else if (!strcmp(cmd, "hangup")) r = nx_call_hangup(atoi(a));
        else if (!strcmp(cmd, "hold"))   r = nx_call_hold(atoi(a));
        else if (!strcmp(cmd, "unhold")) r = nx_call_unhold(atoi(a), 1);
        else if (!strcmp(cmd, "dtmf"))   r = nx_call_dtmf(atoi(a), b);
        else if (!strcmp(cmd, "xfer"))   r = nx_call_xfer_blind(atoi(a), b);
        else if (!strcmp(cmd, "axfer"))  r = nx_call_xfer_attended(atoi(a), atoi(b));
        else if (!strcmp(cmd, "mute"))   r = nx_audio_set_mute(atoi(a));
        else if (!strcmp(cmd, "rereg"))  r = nx_account_register(atoi(a), 1);
        else if (!strcmp(cmd, "dnd"))    r = nx_set_dnd(atoi(a));
        else if (!strcmp(cmd, "conf"))   r = nx_conf_join();
        else if (!strcmp(cmd, "split"))  r = nx_conf_split(atoi(a));
        else if (!strcmp(cmd, "rec"))    r = nx_rec_start(atoi(a), b);
        else if (!strcmp(cmd, "recstop")) r = nx_rec_stop();
        else if (!strcmp(cmd, "blf"))    r = nx_blf_add(atoi(a), b);
        else if (!strcmp(cmd, "stats")) {
            char *s2 = nx_call_stats(atoi(a));
            printf("%s\n", s2 ? s2 : "null");
            nx_free(s2);
            continue;
        }
        else if (!strcmp(cmd, "devs") || !strcmp(cmd, "state") || !strcmp(cmd, "codecs")) {
            char *s = !strcmp(cmd, "devs") ? nx_audio_devices() :
                      !strcmp(cmd, "codecs") ? nx_codecs() : nx_dump_state();
            printf("%s\n", s ? s : "null");
            nx_free(s);
            continue;
        } else { printf("?? comando desconocido\n"); continue; }
        printf("== %s -> %d\n", cmd, r);
        fflush(stdout);
    }

    nx_shutdown();
    return 0;
}
