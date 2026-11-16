import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // Enlaces noryxs: (QR de configuración de puestos escaneado con la cámara) y tel:
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for ctx in connectionOptions.urlContexts { NxUrlInbox.shared.receive(ctx.url.absoluteString) }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for ctx in URLContexts { NxUrlInbox.shared.receive(ctx.url.absoluteString) }
  }
}

/// Guarda los enlaces que llegan antes de que Dart esté listo y los entrega después.
final class NxUrlInbox {
  static let shared = NxUrlInbox()
  private var pending: [String] = []
  var deliver: ((String) -> Void)?

  func receive(_ url: String) {
    if let d = deliver { d(url) } else { pending.append(url) }
  }

  func takePending() -> [String] {
    defer { pending.removeAll() }
    return pending
  }
}
