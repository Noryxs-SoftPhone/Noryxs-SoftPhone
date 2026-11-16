import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channel: FlutterMethodChannel?
  private var keepAlive: AVAudioPlayer?
  private var ringing = Set<Int>()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    nc.addObserver(self, selector: #selector(enteringForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Mismo canal que en macOS: avisos de llamada entrante
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NoryxsCallAlerts") else { return }
    let ch = FlutterMethodChannel(name: "noryxs/window", binaryMessenger: registrar.messenger())
    ch.setMethodCallHandler { [weak self] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "requestNotificationPermission": self?.setupNotifications()
      case "incomingCall": self?.incomingCall(args)
      case "updateCall": self?.updateCall(args)
      case "callHandled": self?.callHandled(args)
      default: break
      }
      result(nil)
    }
    channel = ch
    setupNotifications()
  }

  // MARK: - Segundo plano: mantener la conexión SIP viva

  /// iOS suspende las apps en segundo plano. Con el modo de audio en segundo plano y una
  /// sesión de audio activa (silencio), NORYXS sigue registrada y puede recibir llamadas.
  /// No funciona si el usuario cierra la app deslizándola, ni tras reiniciar el iPhone.
  @objc private func enteredBackground() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .voiceChat,
                              options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
      try session.setActive(true)
      if keepAlive == nil {
        keepAlive = try AVAudioPlayer(data: Self.silentWav())
        keepAlive?.numberOfLoops = -1
        keepAlive?.volume = 0
      }
      keepAlive?.play()
    } catch {
      NSLog("NORYXS: no se pudo mantener la app en segundo plano: \(error)")
    }
  }

  @objc private func enteringForeground() {
    keepAlive?.stop()
  }

  /// 1 s de silencio PCM 8 kHz mono.
  private static func silentWav() -> Data {
    let rate: UInt32 = 8000, samples = rate
    var d = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
    d.append("RIFF".data(using: .ascii)!); u32(36 + samples * 2)
    d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
    d.append("data".data(using: .ascii)!); u32(samples * 2)
    d.append(Data(count: Int(samples * 2)))
    return d
  }

  // MARK: - Notificación de llamada entrante

  private func setupNotifications() {
    let center = UNUserNotificationCenter.current()
    let answer = UNNotificationAction(identifier: "answer", title: "Contestar", options: [.foreground])
    let mute = UNNotificationAction(identifier: "mute", title: "Silenciar", options: [])
    let reject = UNNotificationAction(identifier: "reject", title: "Rechazar", options: [.destructive])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "incoming-call", actions: [answer, mute, reject], intentIdentifiers: [], options: [])
    ])
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
  }

  private func incomingCall(_ a: [String: Any]) {
    let callId = a["callId"] as? Int ?? -1
    ringing.insert(callId)
    // Con la app en primer plano, la franja integrada de Flutter es suficiente
    guard UIApplication.shared.applicationState != .active else { return }
    post(a, callId: callId)
  }

  private func updateCall(_ a: [String: Any]) {
    let callId = a["callId"] as? Int ?? -1
    guard ringing.contains(callId), UIApplication.shared.applicationState != .active else { return }
    // Tono silenciado: actualizar la notificación sin volver a sonar
    if a["muted"] as? Bool == true { post(a, callId: callId, silent: true) }
  }

  private func callHandled(_ a: [String: Any]) {
    let callId = a["callId"] as? Int ?? -1
    ringing.remove(callId)
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call-\(callId)"])
  }

  private func post(_ a: [String: Any], callId: Int, silent: Bool = false) {
    let c = UNMutableNotificationContent()
    let line = a["lineBadge"] as? String ?? ""
    c.title = line.isEmpty ? "Llamada entrante" : "Llamada entrante · \(line.capitalized)"
    let name = a["name"] as? String ?? "Número oculto"
    let number = a["number"] as? String ?? ""
    let geo = a["geo"] as? String ?? ""
    var body = number.isEmpty ? name : "\(name) · \(number)"
    if !geo.isEmpty { body += "\n\(geo)" }
    c.body = body
    if let note = a["note"] as? String, note.hasPrefix("Al contestar") {
      c.subtitle = note
    } else if let last = a["lastNote"] as? String, !last.isEmpty {
      c.subtitle = "Última nota: \(last)"
    }
    c.categoryIdentifier = "incoming-call"
    c.userInfo = ["callId": callId]
    c.sound = silent ? nil : .default
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "call-\(callId)", content: c, trigger: nil))
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
    let callId = response.notification.request.content.userInfo["callId"] as? Int ?? -1
    let action: String
    switch response.actionIdentifier {
    case "answer": action = "answer"   // tocar la notificación solo abre la app
    case "mute": action = "mute"
    case "reject": action = "reject"
    default: action = ""
    }
    if !action.isEmpty {
      channel?.invokeMethod("notificationAction", arguments: ["action": action, "callId": callId])
    }
    completionHandler()
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // En primer plano no se muestra: ya está la franja de llamada entrante
    completionHandler([])
  }
}
