#include "nx_desktop.h"

#include <fontconfig/fontconfig.h>

#include <string.h>
#include <unistd.h>

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#ifdef NX_HAVE_APPINDICATOR
#include <libayatana-appindicator/app-indicator.h>
#endif

namespace {

constexpr int kBaseWidth = 466;
constexpr int kBaseHeight = 800;
constexpr int kMinWidth = 440;
constexpr int kMinHeight = 720;

struct Desktop {
  GtkApplication* app = nullptr;
  GtkWindow* window = nullptr;
  GtkWidget* view = nullptr;
  GDBusConnection* session = nullptr;
  std::map<int64_t, guint32> notifications;  // callId -> id de notificación (Wayland)
  FlMethodChannel* channel = nullptr;
  bool quitting = false;
  bool side_panel_open = false;
  int panel_width = 0;
  std::string exe_dir;

  // Llamadas sonando (la tarjeta muestra la primera)
  std::map<int64_t, FlValue*> ringing;
  std::vector<int64_t> order;

  // Tarjeta flotante
  GtkWidget* card = nullptr;
  GtkWidget* line_label = nullptr;
  GtkWidget* initials_label = nullptr;
  GtkWidget* name_label = nullptr;
  GtkWidget* number_label = nullptr;
  GtkWidget* geo_label = nullptr;
  GtkWidget* note_label = nullptr;
  GtkWidget* mute_button = nullptr;
  int64_t card_call_id = -1;
};

Desktop* D = nullptr;

const char kCss[] =
    "window.nxcard { background-color: transparent; }"
    "#nxcard { background-color: #ffffff; border: 1px solid rgba(197,160,89,0.6); border-radius: 22px;"
    "  padding: 16px; font-family: Inter, 'Noto Sans', sans-serif; color: #18181b; }"
    "#nxbell { background-color: #18181b; color: #C5A059; border-radius: 8px; min-width: 24px; min-height: 24px;"
    "  font-size: 12px; }"
    "#nxbrand { font-weight: 700; font-size: 11px; }"
    "#nxsub { font-size: 10px; color: #6b7280; }"
    "#nxline { font-family: 'JetBrains Mono', monospace; font-weight: 700; font-size: 10px; color: #9A7B3E;"
    "  background-color: #FAF5EB; border: 1px solid rgba(197,160,89,0.4); border-radius: 99px; padding: 2px 8px; }"
    "#nxsep { background-color: #e5e7eb; min-height: 1px; }"
    "#nxavatar { background-color: #f9fafb; border: 1px solid #e5e7eb; border-radius: 16px; min-width: 48px;"
    "  min-height: 48px; font-weight: 700; font-size: 16px; }"
    "#nxname { font-weight: 700; font-size: 16px; }"
    "#nxnumber { font-family: 'JetBrains Mono', monospace; font-size: 12px; color: #6b7280; }"
    "#nxgeo { font-size: 10.5px; color: #6b7280; }"
    "#nxnote { font-size: 11px; color: #9A7B3E; }"
    "button.nxbtn { border-radius: 12px; min-height: 36px; font-weight: 600; font-size: 11px; background-image: none;"
    "  box-shadow: none; text-shadow: none; }"
    "#nxanswer { background-color: #059669; color: #ffffff; border: none; font-size: 12px; }"
    "#nxanswer:hover { background-color: #047857; }"
    "#nxmute { background-color: #f9fafb; color: #454545; border: 1px solid #e5e7eb; }"
    "#nxreject { background-color: #fef2f2; color: #b91c1c; border: 1px solid #fecaca; }";

FlValue* Lookup(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return nullptr;
  return fl_value_lookup_string(map, key);
}

std::string Str(FlValue* map, const char* key) {
  FlValue* v = Lookup(map, key);
  return (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) ? fl_value_get_string(v) : "";
}

int64_t Int(FlValue* map, const char* key, int64_t def) {
  FlValue* v = Lookup(map, key);
  return (v && fl_value_get_type(v) == FL_VALUE_TYPE_INT) ? fl_value_get_int(v) : def;
}

bool Bool(FlValue* map, const char* key, bool def) {
  FlValue* v = Lookup(map, key);
  return (v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL) ? fl_value_get_bool(v) : def;
}

double Double(FlValue* map, const char* key, double def) {
  FlValue* v = Lookup(map, key);
  if (v && fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (v && fl_value_get_type(v) == FL_VALUE_TYPE_INT) return (double)fl_value_get_int(v);
  return def;
}

void FixWindowSize() {
  // Como en macOS: ventana redimensionable con tamaño mínimo 440×720 (más el panel de
  // cola cuando está abierto). El mínimo se pide en la vista de Flutter, no con
  // geometry hints, para no bloquear el redimensionado en ningún escritorio.
  gtk_window_set_resizable(D->window, TRUE);
  if (D->view) {
    gtk_widget_set_size_request(D->view, D->side_panel_open ? kMinWidth + D->panel_width : kMinWidth, kMinHeight);
  }
}

bool IsX11() {
  // Sin incluir <gdk/gdkx.h>: Xlib define macros como Bool o Status que chocan con este código.
  GdkDisplay* d = gdk_display_get_default();
  return d != nullptr && strcmp(G_OBJECT_TYPE_NAME(d), "GdkX11Display") == 0;
}

bool UserIsLookingAtTerminal() {
  if (!gtk_widget_get_visible(GTK_WIDGET(D->window)) || !gtk_window_is_active(D->window)) return false;
  GdkWindow* w = gtk_widget_get_window(GTK_WIDGET(D->window));
  return w != nullptr && !(gdk_window_get_state(w) & GDK_WINDOW_STATE_ICONIFIED);
}

void Invoke(const char* method, FlValue* args) {
  fl_method_channel_invoke_method(D->channel, method, args, nullptr, nullptr, nullptr);
}

void HideCard() {
  if (D->card) gtk_widget_hide(D->card);
}

void CardAction(const char* action, bool bring_front) {
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "action", fl_value_new_string(action));
  fl_value_set_string_take(args, "callId", fl_value_new_int(D->card_call_id));
  Invoke("notificationAction", args);
  if (bring_front) {
    HideCard();
    nx_desktop_present();
  }
}

void OnAnswer(GtkButton*, gpointer) { CardAction("answer", true); }
void OnMute(GtkButton*, gpointer) { CardAction("mute", false); }
void OnReject(GtkButton*, gpointer) { CardAction("reject", false); }

gboolean OnCardPress(GtkWidget* widget, GdkEventButton* event, gpointer) {
  // Arrastrar la tarjeta desde cualquier punto que no sea un botón
  if (event->button == 1) {
    gtk_window_begin_move_drag(GTK_WINDOW(gtk_widget_get_toplevel(widget)), (gint)event->button,
                               (gint)event->x_root, (gint)event->y_root, event->time);
    return TRUE;
  }
  return FALSE;
}

GtkWidget* Label(const char* name, gfloat xalign) {
  GtkWidget* l = gtk_label_new("");
  gtk_widget_set_name(l, name);
  gtk_label_set_xalign(GTK_LABEL(l), xalign);
  gtk_label_set_ellipsize(GTK_LABEL(l), PANGO_ELLIPSIZE_END);
  return l;
}

GtkWidget* Button(const char* name, const char* text, GCallback cb) {
  GtkWidget* b = gtk_button_new_with_label(text);
  gtk_widget_set_name(b, name);
  gtk_style_context_add_class(gtk_widget_get_style_context(b), "nxbtn");
  gtk_widget_set_can_focus(b, FALSE);
  g_signal_connect(b, "clicked", cb, nullptr);
  return b;
}

void CreateCard() {
  GtkWidget* win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(win), "NORYXS Terminal · Llamada entrante");
  gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
  gtk_window_set_keep_above(GTK_WINDOW(win), TRUE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(win), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(win), TRUE);
  gtk_window_set_type_hint(GTK_WINDOW(win), GDK_WINDOW_TYPE_HINT_NOTIFICATION);
  gtk_window_set_accept_focus(GTK_WINDOW(win), FALSE);
  gtk_window_set_focus_on_map(GTK_WINDOW(win), FALSE);
  gtk_window_set_resizable(GTK_WINDOW(win), FALSE);
  gtk_window_stick(GTK_WINDOW(win));
  gtk_style_context_add_class(gtk_widget_get_style_context(win), "nxcard");
  GdkScreen* screen = gtk_widget_get_screen(win);
  GdkVisual* rgba = gdk_screen_get_rgba_visual(screen);
  if (rgba != nullptr && gdk_screen_is_composited(screen)) gtk_widget_set_visual(win, rgba);
  gtk_widget_set_app_paintable(win, TRUE);

  GtkWidget* events = gtk_event_box_new();
  gtk_event_box_set_visible_window(GTK_EVENT_BOX(events), FALSE);
  g_signal_connect(events, "button-press-event", G_CALLBACK(OnCardPress), nullptr);
  gtk_container_add(GTK_CONTAINER(win), events);

  GtkWidget* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
  gtk_widget_set_name(root, "nxcard");
  gtk_widget_set_size_request(root, 390, -1);
  gtk_container_add(GTK_CONTAINER(events), root);

  // Cabecera
  GtkWidget* head = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  GtkWidget* bell = gtk_label_new("\xF0\x9F\x94\x94");  // 🔔
  gtk_widget_set_name(bell, "nxbell");
  GtkWidget* brand = gtk_label_new("NORYXS SIP");
  gtk_widget_set_name(brand, "nxbrand");
  GtkWidget* sub = gtk_label_new("\xE2\x80\xA2 Llamada entrante");
  gtk_widget_set_name(sub, "nxsub");
  D->line_label = gtk_label_new("");
  gtk_widget_set_name(D->line_label, "nxline");
  gtk_box_pack_start(GTK_BOX(head), bell, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(head), brand, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(head), sub, FALSE, FALSE, 0);
  gtk_box_pack_end(GTK_BOX(head), D->line_label, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(root), head, FALSE, FALSE, 0);
  GtkWidget* sep = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_name(sep, "nxsep");
  gtk_box_pack_start(GTK_BOX(root), sep, FALSE, FALSE, 0);

  // Llamante
  GtkWidget* caller = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14);
  D->initials_label = gtk_label_new("");
  gtk_widget_set_name(D->initials_label, "nxavatar");
  gtk_widget_set_valign(D->initials_label, GTK_ALIGN_START);
  GtkWidget* texts = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  D->name_label = Label("nxname", 0);
  D->number_label = Label("nxnumber", 0);
  D->geo_label = Label("nxgeo", 0);
  D->note_label = Label("nxnote", 0);
  gtk_box_pack_start(GTK_BOX(texts), D->name_label, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(texts), D->number_label, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(texts), D->geo_label, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(texts), D->note_label, FALSE, FALSE, 2);
  gtk_box_pack_start(GTK_BOX(caller), D->initials_label, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(caller), texts, TRUE, TRUE, 0);
  gtk_box_pack_start(GTK_BOX(root), caller, FALSE, FALSE, 0);

  // Acciones (proporción 6/3/3 como en el diseño)
  GtkWidget* actions = gtk_grid_new();
  gtk_grid_set_column_spacing(GTK_GRID(actions), 8);
  gtk_grid_set_column_homogeneous(GTK_GRID(actions), TRUE);
  D->mute_button = Button("nxmute", "Silenciar", G_CALLBACK(OnMute));
  gtk_grid_attach(GTK_GRID(actions), Button("nxanswer", "\xE2\x98\x8E  Contestar", G_CALLBACK(OnAnswer)), 0, 0, 2, 1);
  gtk_grid_attach(GTK_GRID(actions), D->mute_button, 2, 0, 1, 1);
  gtk_grid_attach(GTK_GRID(actions), Button("nxreject", "Rechazar", G_CALLBACK(OnReject)), 3, 0, 1, 1);
  gtk_box_pack_start(GTK_BOX(root), actions, FALSE, FALSE, 4);

  gtk_widget_show_all(events);
  D->card = win;
}

void SetLabel(GtkWidget* l, const std::string& text) {
  gtk_label_set_text(GTK_LABEL(l), text.c_str());
  gtk_widget_set_visible(l, !text.empty());
}

void RefreshCard() {
  if (D->order.empty()) return;
  if (!D->card) CreateCard();
  FlValue* a = D->ringing[D->order.front()];
  D->card_call_id = Int(a, "callId", -1);
  SetLabel(D->line_label, Str(a, "lineBadge"));
  std::string initials = Str(a, "initials");
  gtk_label_set_text(GTK_LABEL(D->initials_label), initials.empty() ? "\xE2\x98\x8E" : initials.c_str());
  SetLabel(D->name_label, Str(a, "name"));
  SetLabel(D->number_label, Str(a, "number"));
  SetLabel(D->geo_label, Str(a, "geo"));
  std::string note = Str(a, "note");
  if (D->order.size() > 1) note += " \xC2\xB7 +" + std::to_string(D->order.size() - 1) + " en cola";
  SetLabel(D->note_label, note);
  bool muted = Bool(a, "muted", false);
  gtk_button_set_label(GTK_BUTTON(D->mute_button), muted ? "Silenciado" : "Silenciar");
  gtk_widget_set_sensitive(D->mute_button, !muted);
}

void ShowCard() {
  RefreshCard();
  if (!D->card) return;
  GtkRequisition size;
  gtk_widget_get_preferred_size(D->card, nullptr, &size);
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* mon = gdk_display_get_primary_monitor(display);
  if (mon == nullptr) mon = gdk_display_get_monitor(display, 0);
  if (mon != nullptr) {
    GdkRectangle work;
    gdk_monitor_get_workarea(mon, &work);
    gtk_window_move(GTK_WINDOW(D->card), work.x + work.width - size.width - 16, work.y + 16);
  }
  gtk_widget_show(D->card);
}

// ---- Notificación de escritorio (Wayland y cualquier escritorio sin ventanas flotantes) ----
// Wayland no deja a las apps colocar ventanas ni mantenerlas encima: en su lugar se usa
// la notificación estándar org.freedesktop.Notifications (GNOME, KDE, XFCE…), crítica
// (no caduca) y con botones Contestar / Silenciar / Rechazar.

void OnNotifyReply(GObject* source, GAsyncResult* res, gpointer data) {
  int64_t call_id = GPOINTER_TO_INT(data);
  g_autoptr(GVariant) r = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), res, nullptr);
  if (r == nullptr) return;
  guint32 id = 0;
  g_variant_get(r, "(u)", &id);
  if (D->notifications.count(call_id) || std::find(D->order.begin(), D->order.end(), call_id) != D->order.end()) {
    D->notifications[call_id] = id;
  }
}

void CloseNotification(int64_t call_id) {
  auto it = D->notifications.find(call_id);
  if (it == D->notifications.end() || D->session == nullptr) return;
  g_dbus_connection_call(D->session, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                         "org.freedesktop.Notifications", "CloseNotification", g_variant_new("(u)", it->second),
                         nullptr, G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr, nullptr);
  D->notifications.erase(it);
}

void SendNotification(FlValue* a) {
  if (D->session == nullptr) return;
  int64_t call_id = Int(a, "callId", -1);
  guint32 replaces = D->notifications.count(call_id) ? D->notifications[call_id] : 0;
  std::string line = Str(a, "lineBadge");
  std::string summary = line.empty() ? "Llamada entrante" : "Llamada entrante \xC2\xB7 " + line;
  std::string body = Str(a, "name");
  std::string number = Str(a, "number"), geo = Str(a, "geo"), note = Str(a, "note");
  if (!number.empty()) body += "  " + number;
  if (!geo.empty()) body += "\n" + geo;
  if (!note.empty()) body += "\n" + note;
  bool muted = Bool(a, "muted", false);

  GVariantBuilder actions;
  g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
  for (const char* s : {"default", "Abrir", "answer", "Contestar"}) g_variant_builder_add(&actions, "s", s);
  if (!muted) { g_variant_builder_add(&actions, "s", "mute"); g_variant_builder_add(&actions, "s", "Silenciar"); }
  g_variant_builder_add(&actions, "s", "reject");
  g_variant_builder_add(&actions, "s", "Rechazar");
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&hints, "{sv}", "urgency", g_variant_new_byte(2));
  g_variant_builder_add(&hints, "{sv}", "category", g_variant_new_string("im.received"));
  g_variant_builder_add(&hints, "{sv}", "desktop-entry", g_variant_new_string("com.noryxs.noryxs_terminal"));
  g_variant_builder_add(&hints, "{sv}", "suppress-sound", g_variant_new_boolean(TRUE));  // el timbre lo da PJSIP
  std::string icon = D->exe_dir + "/data/noryxs.png";

  g_dbus_connection_call(D->session, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                         "org.freedesktop.Notifications", "Notify",
                         g_variant_new("(susssasa{sv}i)", "NORYXS Terminal", replaces, icon.c_str(), summary.c_str(),
                                       body.c_str(), &actions, &hints, 0),
                         G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, OnNotifyReply,
                         GINT_TO_POINTER((gint)call_id));
}

void OnNotificationAction(GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar*, GVariant* params,
                          gpointer) {
  guint32 id = 0;
  const gchar* key = nullptr;
  g_variant_get(params, "(u&s)", &id, &key);
  for (auto& kv : D->notifications) {
    if (kv.second != id) continue;
    int64_t call_id = kv.first;
    if (strcmp(key, "default") == 0) {
      nx_desktop_present();
      return;
    }
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "action", fl_value_new_string(key));
    fl_value_set_string_take(args, "callId", fl_value_new_int(call_id));
    Invoke("notificationAction", args);
    if (strcmp(key, "answer") == 0) nx_desktop_present();
    return;
  }
}

void WatchNotifications() {
  D->session = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (D->session == nullptr) return;
  g_dbus_connection_signal_subscribe(D->session, "org.freedesktop.Notifications", "org.freedesktop.Notifications",
                                     "ActionInvoked", "/org/freedesktop/Notifications", nullptr,
                                     G_DBUS_SIGNAL_FLAGS_NONE, OnNotificationAction, nullptr, nullptr);
}

void IncomingCall(FlValue* a) {
  int64_t id = Int(a, "callId", -1);
  auto it = D->ringing.find(id);
  if (it != D->ringing.end()) fl_value_unref(it->second);
  D->ringing[id] = fl_value_ref(a);
  if (std::find(D->order.begin(), D->order.end(), id) == D->order.end()) D->order.push_back(id);

  // Contexto A (terminal a la vista): basta la franja integrada de Flutter
  if (UserIsLookingAtTerminal()) return;
  gtk_window_set_urgency_hint(D->window, TRUE);
  if (!Bool(a, "card", true)) return;
  // X11: tarjeta flotante arriba a la derecha. Wayland: notificación de escritorio.
  if (IsX11()) ShowCard();
  else SendNotification(a);
}

void UpdateCall(FlValue* a) {
  int64_t id = Int(a, "callId", -1);
  auto it = D->ringing.find(id);
  if (it == D->ringing.end()) return;
  fl_value_unref(it->second);
  it->second = fl_value_ref(a);
  if (D->card_call_id == id) RefreshCard();
  // Tono silenciado: actualizar la notificación (Wayland) para quitar el botón Silenciar
  if (D->notifications.count(id) && Bool(a, "muted", false)) SendNotification(a);
}

void CallHandled(FlValue* a) {
  int64_t id = Int(a, "callId", -1);
  auto it = D->ringing.find(id);
  if (it != D->ringing.end()) {
    fl_value_unref(it->second);
    D->ringing.erase(it);
  }
  D->order.erase(std::remove(D->order.begin(), D->order.end(), id), D->order.end());
  CloseNotification(id);
  if (D->order.empty()) {
    HideCard();
    gtk_window_set_urgency_hint(D->window, FALSE);
  } else {
    RefreshCard();
  }
}

void SetSidePanel(bool open, double width) {
  if (open == D->side_panel_open) return;
  D->side_panel_open = open;
  D->panel_width = (int)width;
  gint w = 0, h = 0;
  gtk_window_get_size(D->window, &w, &h);
  FixWindowSize();
  gtk_window_resize(D->window, open ? w + D->panel_width : std::max(kMinWidth, w - D->panel_width), h);
}

std::string AutostartPath() {
  g_autofree gchar* p = g_build_filename(g_get_user_config_dir(), "autostart", "noryxs-terminal.desktop", nullptr);
  return p;
}

bool SetLaunchAtLogin(bool enabled) {
  std::string path = AutostartPath();
  if (!enabled) {
    unlink(path.c_str());
    return true;
  }
  g_autofree gchar* dir = g_path_get_dirname(path.c_str());
  g_mkdir_with_parents(dir, 0700);
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return false;
  std::string icon = D->exe_dir + "/data/noryxs.png";
  std::string content = std::string("[Desktop Entry]\nType=Application\nName=NORYXS Terminal\nComment=NORYXS Virtual SIP Terminal\n") +
                        "Exec=\"" + exe + "\"\nIcon=" + icon + "\nTerminal=false\nX-GNOME-Autostart-enabled=true\n";
  return g_file_set_contents(path.c_str(), content.c_str(), -1, nullptr);
}

void StartDrag() {
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = seat ? gdk_seat_get_pointer(seat) : nullptr;
  if (pointer == nullptr) return;
  gint x = 0, y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  gtk_window_begin_move_drag(D->window, 1, x, y, GDK_CURRENT_TIME);
}

void OnMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* m = fl_method_call_get_name(call);
  FlValue* a = fl_method_call_get_args(call);
  g_autoptr(FlValue) result = nullptr;

  if (strcmp(m, "incomingCall") == 0) {
    IncomingCall(a);
  } else if (strcmp(m, "updateCall") == 0) {
    UpdateCall(a);
  } else if (strcmp(m, "callHandled") == 0) {
    CallHandled(a);
  } else if (strcmp(m, "setSidePanel") == 0) {
    SetSidePanel(Bool(a, "open", false), Double(a, "width", 320));
  } else if (strcmp(m, "startDrag") == 0) {
    StartDrag();
  } else if (strcmp(m, "attention") == 0) {
    gtk_window_set_urgency_hint(D->window, TRUE);
  } else if (strcmp(m, "setLaunchAtLogin") == 0) {
    result = fl_value_new_bool(SetLaunchAtLogin(Bool(a, "enabled", true)));
  } else if (strcmp(m, "getLaunchAtLogin") == 0) {
    result = fl_value_new_bool(g_file_test(AutostartPath().c_str(), G_FILE_TEST_EXISTS));
  }
  fl_method_call_respond_success(call, result, nullptr);
}

// Cerrar la ventana la oculta: NORYXS Terminal sigue registrada y recibiendo llamadas
gboolean OnDelete(GtkWidget* widget, GdkEvent*, gpointer) {
  if (D->quitting) return FALSE;
  gtk_widget_hide(widget);
  return TRUE;
}

gboolean OnFocusIn(GtkWidget*, GdkEvent*, gpointer) {
  gtk_window_set_urgency_hint(D->window, FALSE);
  HideCard();
  return FALSE;
}

void Quit() {
  D->quitting = true;
  if (D->card) gtk_widget_destroy(D->card);
  D->card = nullptr;
  g_application_quit(G_APPLICATION(D->app));
}

void OnMenuOpen(GtkMenuItem*, gpointer) { nx_desktop_present(); }
void OnMenuQuit(GtkMenuItem*, gpointer) { Quit(); }

GtkWidget* TrayMenu() {
  GtkWidget* menu = gtk_menu_new();
  GtkWidget* open = gtk_menu_item_new_with_label("Abrir NORYXS Terminal");
  GtkWidget* quit = gtk_menu_item_new_with_label("Salir de NORYXS Terminal");
  g_signal_connect(open, "activate", G_CALLBACK(OnMenuOpen), nullptr);
  g_signal_connect(quit, "activate", G_CALLBACK(OnMenuQuit), nullptr);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), open);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit);
  gtk_widget_show_all(menu);
  return menu;
}

#ifndef NX_HAVE_APPINDICATOR
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
void OnStatusActivate(GtkStatusIcon*, gpointer) { nx_desktop_present(); }
void OnStatusPopup(GtkStatusIcon* icon, guint button, guint time, gpointer menu) {
  gtk_menu_popup(GTK_MENU(menu), nullptr, nullptr, gtk_status_icon_position_menu, icon, button, time);
}
G_GNUC_END_IGNORE_DEPRECATIONS
#endif

void SetupTray() {
  // El icono se pide por NOMBRE con la carpeta data/ como ruta de tema: el estándar
  // StatusNotifier (GNOME con AppIndicator, KDE, XFCE…) no resuelve rutas completas y
  // en ese caso muestra un icono genérico (la rueda dentada).
  std::string theme_dir = D->exe_dir + "/data";
#ifdef NX_HAVE_APPINDICATOR
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  AppIndicator* ind = app_indicator_new_with_path("noryxs-terminal", "noryxs", APP_INDICATOR_CATEGORY_COMMUNICATIONS,
                                                  theme_dir.c_str());
  app_indicator_set_icon_full(ind, "noryxs", "NORYXS Terminal");
  app_indicator_set_title(ind, "NORYXS Terminal");
  app_indicator_set_status(ind, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_menu(ind, GTK_MENU(TrayMenu()));
  G_GNUC_END_IGNORE_DEPRECATIONS
#else
  std::string icon = theme_dir + "/noryxs.png";
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  GtkStatusIcon* si = gtk_status_icon_new_from_file(icon.c_str());
  gtk_status_icon_set_tooltip_text(si, "NORYXS Terminal");
  gtk_status_icon_set_visible(si, TRUE);
  g_signal_connect(si, "activate", G_CALLBACK(OnStatusActivate), nullptr);
  g_signal_connect(si, "popup-menu", G_CALLBACK(OnStatusPopup), TrayMenu());
  G_GNUC_END_IGNORE_DEPRECATIONS
#endif
}

// Tras suspender el equipo: rehacer transportes y registros SIP (logind PrepareForSleep)
void OnPrepareForSleep(GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar*, GVariant* params,
                       gpointer) {
  gboolean sleeping = TRUE;
  g_variant_get(params, "(b)", &sleeping);
  if (!sleeping) Invoke("wake", nullptr);
}

void WatchResume() {
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, nullptr);
  if (bus == nullptr) return;
  g_dbus_connection_signal_subscribe(bus, "org.freedesktop.login1", "org.freedesktop.login1.Manager",
                                     "PrepareForSleep", "/org/freedesktop/login1", nullptr,
                                     G_DBUS_SIGNAL_FLAGS_NONE, OnPrepareForSleep, nullptr, nullptr);
}

}  // namespace

void nx_desktop_init(GtkApplication* app, GtkWindow* window, FlView* view) {
  D = new Desktop();
  D->app = app;
  D->window = window;
  D->view = GTK_WIDGET(view);
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    D->exe_dir = dir;
  }

  // Fuentes de la app (Inter / JetBrains Mono) para la tarjeta nativa
  std::string fonts = D->exe_dir + "/data/flutter_assets/assets/fonts";
  FcConfigAppFontAddDir(nullptr, reinterpret_cast<const FcChar8*>(fonts.c_str()));

  GtkCssProvider* css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css, kCss, -1, nullptr);
  gtk_style_context_add_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(css),
                                            GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  FixWindowSize();
  gtk_window_resize(window, kBaseWidth, kBaseHeight);
  g_signal_connect(window, "delete-event", G_CALLBACK(OnDelete), nullptr);
  g_signal_connect(window, "focus-in-event", G_CALLBACK(OnFocusIn), nullptr);

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  D->channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine), "noryxs/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(D->channel, OnMethodCall, nullptr, nullptr);

  SetupTray();
  WatchResume();
  WatchNotifications();
}

void nx_desktop_present(void) {
  if (D == nullptr) return;
  gtk_widget_show(GTK_WIDGET(D->window));
  gtk_window_deiconify(D->window);
  gtk_window_present(D->window);
}
