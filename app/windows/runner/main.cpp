#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "nx_desktop.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Clic para llamar: ¿nos han abierto con un enlace tel:/sip:/callto:?
  std::string dial_url;
  for (const auto& a : GetCommandLineArguments()) {
    if (NxIsDialUrl(a)) dial_url = a;
  }

  // Una sola instancia: dos motores SIP con las mismas cuentas se pisarían el registro.
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"Local\\Noryxs.SingleInstance");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"NORYXS Terminal");
    if (existing != nullptr) {
      if (!dial_url.empty()) {
        COPYDATASTRUCT cds{kNxUrlCopyData, (DWORD)dial_url.size(), (PVOID)dial_url.data()};
        ::SendMessageW(existing, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
      }
      ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  g_nx_initial_url = dial_url;

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(466, 800);  // tamaño de teléfono, como en macOS
  if (!window.Create(L"NORYXS Terminal", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
