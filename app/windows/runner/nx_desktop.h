// NORYXS Terminal · integración de escritorio en Windows (equivale a MainFlutterWindow.swift):
//  - canal "noryxs/window" (incomingCall, updateCall, callHandled, setSidePanel,
//    startDrag, attention, setLaunchAtLogin, getLaunchAtLogin) → notificationAction / wake
//  - tarjeta flotante de llamada entrante arriba a la derecha (contexto B)
//  - icono en la bandeja del sistema; cerrar la ventana la oculta
//  - panel lateral de cola: ensancha la ventana
#ifndef RUNNER_NX_DESKTOP_H_
#define RUNNER_NX_DESKTOP_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

class NxCallCard;

class NxDesktop {
 public:
  NxDesktop(HWND window, flutter::BinaryMessenger* messenger);
  ~NxDesktop();

  // Mensajes de la ventana principal. Devuelve un valor si el mensaje se ha tratado.
  std::optional<LRESULT> HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  // Acción pulsada en la tarjeta flotante.
  void CardAction(const char* action, int call_id, bool bring_front);

  void BringToFront();
  void Quit();

 private:
  void OnMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void IncomingCall(const flutter::EncodableMap& a);
  void UpdateCall(const flutter::EncodableMap& a);
  void CallHandled(const flutter::EncodableMap& a);
  void RefreshCard();
  void SetSidePanel(bool open, double width);
  bool UserIsLookingAtTerminal() const;
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<NxCallCard> card_;
  std::map<int, flutter::EncodableMap> ringing_;
  std::vector<int> ringing_order_;
  bool side_panel_open_ = false;
  int side_panel_width_ = 320;
  bool quitting_ = false;
  bool tray_added_ = false;
  UINT taskbar_created_msg_ = 0;
};

#endif  // RUNNER_NX_DESKTOP_H_
