#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "nx_desktop.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // Una sola instancia (GtkApplication): si ya hay ventana, traerla al frente
  if (self->window != nullptr) {
    nx_desktop_present();
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "NORYXS Terminal");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "NORYXS Terminal");
  }

  // Tamaño de teléfono (mismo que en macOS): 466×800; mínimo 440×720 (nx_desktop.cc)
  gtk_window_set_default_size(window, 466, 800);
  self->window = window;

  // Icono de NORYXS (data/noryxs.png junto al ejecutable)
  {
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    if (exe != nullptr) {
      g_autofree gchar* dir = g_path_get_dirname(exe);
      g_autofree gchar* icon = g_build_filename(dir, "data", "noryxs.png", nullptr);
      gtk_window_set_icon_from_file(window, icon, nullptr);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  nx_desktop_init(GTK_APPLICATION(application), window, view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // Clic para llamar: los enlaces tel:/sip:/callto: se entregan con "open" (también a
  // la instancia que ya esté abierta); el resto de casos, "activate".
  g_autoptr(GPtrArray) files = g_ptr_array_new_with_free_func(g_object_unref);
  for (gchar** a = *arguments + 1; a && *a; ++a) {
    if (g_str_has_prefix(*a, "tel:") || g_str_has_prefix(*a, "sip:") || g_str_has_prefix(*a, "sips:") ||
        g_str_has_prefix(*a, "callto:") || g_str_has_prefix(*a, "noryxs:")) {
      g_ptr_array_add(files, g_file_new_for_uri(*a));
    } else if (g_strcmp0(*a, "--answer") == 0 || g_strcmp0(*a, "--hangup") == 0 || g_strcmp0(*a, "--mute") == 0) {
      // Atajos de teclado del sistema: "noryxs-terminal --answer" contesta en la instancia abierta
      g_autofree gchar* uri = g_strdup_printf("noryxs:%s", *a + 2);
      g_ptr_array_add(files, g_file_new_for_uri(uri));
    }
  }
  if (files->len > 0) {
    g_application_open(application, reinterpret_cast<GFile**>(files->pdata), (gint)files->len, "");
  } else {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::open (enlaces tel:/sip:/callto:).
static void my_application_open(GApplication* application, GFile** files, gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) g_application_activate(application);
  for (gint i = 0; i < n_files; ++i) {
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    nx_desktop_open_url(uri);
  }
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));  // instancia única + enlaces tel:/sip:
}
