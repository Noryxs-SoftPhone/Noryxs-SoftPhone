// NORYXS Terminal · integración de escritorio en Linux (equivale a MainFlutterWindow.swift):
// canal "noryxs/window", tarjeta flotante de llamada entrante, icono en la bandeja
// (AppIndicator o GtkStatusIcon), cerrar oculta, panel lateral de cola, abrir al
// iniciar sesión (~/.config/autostart) y aviso "wake" al reanudar tras suspender.
#ifndef RUNNER_NX_DESKTOP_H_
#define RUNNER_NX_DESKTOP_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void nx_desktop_init(GtkApplication* app, GtkWindow* window, FlView* view);
void nx_desktop_present(void);

#endif  // RUNNER_NX_DESKTOP_H_
