import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Como un teléfono: cerrar la ventana no cierra NORYXS (sigue en la barra de menús)
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Clic en el icono del Dock con la ventana oculta: volver a mostrarla
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for w in sender.windows where w is MainFlutterWindow {
        w.makeKeyAndOrderFront(nil)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
