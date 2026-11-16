import Cocoa
import CoreText
import FlutterMacOS
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - Tarjeta flotante de llamada entrante (contexto B: ventana minimizada)

final class CallCardModel: ObservableObject {
  @Published var callId = -1
  @Published var lineBadge = ""
  @Published var name = ""
  @Published var number = ""
  @Published var initials = ""
  @Published var note = ""
  @Published var geo = ""
  @Published var muted = false
  @Published var queued = 0

  func apply(_ a: [String: Any]) {
    callId = a["callId"] as? Int ?? callId
    lineBadge = a["lineBadge"] as? String ?? lineBadge
    name = a["name"] as? String ?? name
    number = a["number"] as? String ?? number
    initials = a["initials"] as? String ?? initials
    note = a["note"] as? String ?? note
    geo = a["geo"] as? String ?? geo
    muted = a["muted"] as? Bool ?? muted
  }
}

private extension Color {
  static let nxCharcoal = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255)
  static let nxGold = Color(red: 0xC5 / 255, green: 0xA0 / 255, blue: 0x59 / 255)
  static let nxGoldDark = Color(red: 0x9A / 255, green: 0x7B / 255, blue: 0x3E / 255)
  static let nxGoldLight = Color(red: 0xFA / 255, green: 0xF5 / 255, blue: 0xEB / 255)
  static let nxSurface = Color(red: 0xF9 / 255, green: 0xFA / 255, blue: 0xFB / 255)
  static let nxBorder = Color(red: 0xE5 / 255, green: 0xE7 / 255, blue: 0xEB / 255)
  static let nxGray = Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
  static let nxEmerald = Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255)
  static let nxRed50 = Color(red: 0xFE / 255, green: 0xF2 / 255, blue: 0xF2 / 255)
  static let nxRed200 = Color(red: 0xFE / 255, green: 0xCA / 255, blue: 0xCA / 255)
  static let nxRed700 = Color(red: 0xB9 / 255, green: 0x1C / 255, blue: 0x1C / 255)
}

private func inter(_ size: CGFloat, _ weight: Font.Weight) -> Font {
  let name: String
  switch weight {
  case .bold: name = "Inter-Bold"
  case .semibold: name = "Inter-SemiBold"
  case .medium: name = "Inter-Medium"
  default: name = "Inter-Regular"
  }
  return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight)
}

private func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
  let name = weight == .bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular"
  return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight, design: .monospaced)
}

struct CallCardView: View {
  @ObservedObject var model: CallCardModel
  var onAnswer: () -> Void
  var onMute: () -> Void
  var onReject: () -> Void
  @State private var bell = false

  var body: some View {
    VStack(spacing: 0) {
      // Cabecera
      HStack(spacing: 8) {
        ZStack {
          RoundedRectangle(cornerRadius: 8).fill(Color.nxCharcoal).frame(width: 24, height: 24)
          Image(systemName: "bell")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.nxGold)
            .rotationEffect(.degrees(bell ? 12 : -10))
            .animation(Animation.easeInOut(duration: 0.18).repeatForever(autoreverses: true), value: bell)
        }
        HStack(spacing: 4) {
          Text("NORYXS SIP").font(inter(11, .bold)).foregroundColor(.nxCharcoal)
          Text("• Llamada entrante").font(inter(10, .regular)).foregroundColor(Color.gray.opacity(0.8))
        }
        Spacer(minLength: 4)
        Text(model.lineBadge)
          .font(mono(10, .bold))
          .foregroundColor(.nxGoldDark)
          .padding(.horizontal, 8).padding(.vertical, 2)
          .background(Capsule().fill(Color.nxGoldLight))
          .overlay(Capsule().stroke(Color.nxGold.opacity(0.4), lineWidth: 1))
          .lineLimit(1)
      }
      .padding(.bottom, 10)
      .overlay(Rectangle().fill(Color.nxBorder.opacity(0.6)).frame(height: 1), alignment: .bottom)
      .padding(.bottom, 10)

      // Llamante
      HStack(spacing: 14) {
        ZStack(alignment: .bottomTrailing) {
          RoundedRectangle(cornerRadius: 16).fill(Color.nxSurface)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.nxBorder, lineWidth: 1))
            .frame(width: 48, height: 48)
            .overlay(
              Group {
                if model.initials.isEmpty {
                  Image(systemName: "person").font(.system(size: 18)).foregroundColor(.nxCharcoal)
                } else {
                  Text(model.initials).font(inter(16, .bold)).foregroundColor(.nxCharcoal)
                }
              })
          Circle().fill(Color.nxGold).frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .offset(x: 4, y: 4)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(model.name).font(inter(16, .bold)).foregroundColor(.nxCharcoal).lineLimit(1)
          if !model.number.isEmpty {
            Text(model.number).font(mono(12, .regular)).foregroundColor(.nxGray)
          }
          if !model.geo.isEmpty {
            Text(model.geo).font(inter(10.5, .medium)).foregroundColor(.nxGray).lineLimit(1)
          }
          Text(model.queued > 0 ? "\(model.note) · +\(model.queued) en cola" : model.note)
            .font(inter(11, .medium)).foregroundColor(.nxGoldDark).lineLimit(1)
            .padding(.top, 2)
        }
        Spacer(minLength: 0)
      }
      .padding(.bottom, 14)

      // Acciones
      GeometryReader { g in
        let unit = (g.size.width - 16) / 12
        HStack(spacing: 8) {
          Button(action: onAnswer) {
            HStack(spacing: 6) {
              Image(systemName: "phone.fill").font(.system(size: 12, weight: .bold))
              Text("Contestar").font(inter(12, .semibold))
            }
            .frame(width: unit * 6 + 8, height: 36)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.nxEmerald))
          }.buttonStyle(.plain)
          Button(action: onMute) {
            HStack(spacing: 4) {
              Image(systemName: "speaker.slash").font(.system(size: 11))
              Text(model.muted ? "Silenciado" : "Silenciar").font(inter(11, .semibold))
            }
            .frame(width: unit * 3, height: 36)
            .foregroundColor(Color(white: 0.27))
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.nxSurface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.nxBorder, lineWidth: 1))
          }.buttonStyle(.plain).disabled(model.muted).opacity(model.muted ? 0.6 : 1)
          Button(action: onReject) {
            Text("Rechazar").font(inter(11, .semibold))
              .frame(width: unit * 3, height: 36)
              .foregroundColor(.nxRed700)
              .background(RoundedRectangle(cornerRadius: 12).fill(Color.nxRed50))
              .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.nxRed200, lineWidth: 1))
          }.buttonStyle(.plain)
        }
      }
      .frame(height: 36)
    }
    .padding(16)
    .frame(width: 390)
    .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.97)))
    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.nxGold.opacity(0.6), lineWidth: 1))
    .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 14)
    .padding(24)  // espacio para la sombra
    .onAppear { bell = true }
  }
}

final class CallCardPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

// MARK: - Ventana principal

class MainFlutterWindow: NSWindow, UNUserNotificationCenterDelegate, NSWindowDelegate {
  private var windowChannel: FlutterMethodChannel?
  private var cardPanel: CallCardPanel?
  private let cardModel = CallCardModel()
  private var ringing: [Int: [String: Any]] = [:]
  private var ringingOrder: [Int] = []
  private var sidePanelOpen = false
  private var statusItem: NSStatusItem?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Ventana con formato de terminal telefónico (proporciones del diseño de referencia)
    self.setContentSize(NSSize(width: 466, height: 800))
    self.contentMinSize = NSSize(width: 440, height: 720)
    self.title = "NORYXS Virtual SIP Terminal"
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)  // Flutter dibuja bajo la barra de título
    self.backgroundColor = NSColor(calibratedRed: 0.071, green: 0.075, blue: 0.086, alpha: 1)
    self.center()

    registerBundledFonts()
    self.delegate = self
    setupStatusItem()

    let channel = FlutterMethodChannel(name: "noryxs/window",
                                       binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "incomingCall": self.incomingCall(args)
      case "updateCall": self.updateCall(args)
      case "callHandled": self.callHandled(args)
      case "requestNotificationPermission": self.setupNotifications()
      case "startDrag":
        if let e = NSApp.currentEvent { self.performDrag(with: e) }
      case "attention": NSApp.requestUserAttention(.criticalRequest)
      case "setLaunchAtLogin":
        result(self.setLaunchAtLogin(args["enabled"] as? Bool ?? true))
        return
      case "getLaunchAtLogin":
        result(self.launchAtLoginEnabled())
        return
      case "setSidePanel": self.setSidePanel(open: args["open"] as? Bool ?? false, width: CGFloat(args["width"] as? Double ?? 320))
      default: break
      }
      result(nil)
    }
    windowChannel = channel

    // Tras suspender el Mac: rehacer transportes y registros SIP
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.windowChannel?.invokeMethod("wake", arguments: nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  /// Registra Inter / JetBrains Mono (assets de Flutter) para la tarjeta nativa.
  private func registerBundledFonts() {
    let base = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Frameworks/App.framework/Resources/flutter_assets/assets/fonts")
    guard let files = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return }
    for f in files where f.pathExtension == "ttf" {
      CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
    }
  }

  // MARK: Barra de menús y cierre de ventana

  /// El botón rojo oculta la ventana: NORYXS sigue registrado y recibiendo llamadas.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    self.orderOut(nil)
    return false
  }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let b = item.button {
      let img = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: "NORYXS")
      img?.isTemplate = true
      b.image = img
      b.toolTip = "NORYXS Virtual SIP Terminal"
    }
    let menu = NSMenu()
    let open = NSMenuItem(title: "Abrir NORYXS", action: #selector(menuOpen), keyEquivalent: "o")
    open.target = self
    menu.addItem(open)
    menu.addItem(NSMenuItem.separator())
    let quit = NSMenuItem(title: "Salir de NORYXS", action: #selector(menuQuit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    item.menu = menu
    statusItem = item
  }

  @objc private func menuOpen() { bringToFront() }
  @objc private func menuQuit() { NSApp.terminate(nil) }

  // MARK: Arrancar al iniciar sesión (SMAppService, macOS 13+)

  private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
          if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        }
        return true
      } catch {
        return false
      }
    }
    return false
  }

  private func launchAtLoginEnabled() -> Bool {
    if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
    return false
  }

  // MARK: Panel lateral de cola

  /// Ensancha la ventana hacia la derecha para el panel "En espera" (y la recoge al cerrarlo).
  private func setSidePanel(open: Bool, width: CGFloat) {
    guard open != sidePanelOpen else { return }
    sidePanelOpen = open
    var f = self.frame
    f.size.width += open ? width : -width
    if let vf = self.screen?.visibleFrame, f.maxX > vf.maxX {
      f.origin.x = max(vf.minX, vf.maxX - f.size.width)
    }
    self.contentMinSize = NSSize(width: open ? 440 + width : 440, height: 720)
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.28
      ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
      self.animator().setFrame(f, display: true)
    }
  }

  // MARK: Llamadas entrantes

  private var userIsLookingAtTerminal: Bool {
    NSApp.isActive && self.isVisible && !self.isMiniaturized && !NSApp.isHidden && self.occlusionState.contains(.visible)
  }

  private func incomingCall(_ a: [String: Any]) {
    let callId = a["callId"] as? Int ?? -1
    ringing[callId] = a
    if !ringingOrder.contains(callId) { ringingOrder.append(callId) }

    // Contexto A (terminal a la vista): la franja integrada de Flutter es suficiente.
    if userIsLookingAtTerminal { return }

    NSApp.requestUserAttention(.criticalRequest)
    if a["card"] as? Bool ?? true { showCard() }
    if a["notify"] as? Bool ?? false {
      postNotification(callId: callId, title: a["title"] as? String ?? "Llamada entrante", body: a["body"] as? String ?? "")
    }
  }

  private func updateCall(_ a: [String: Any]) {
    let callId = a["callId"] as? Int ?? -1
    guard ringing[callId] != nil else { return }
    ringing[callId] = a
    if cardModel.callId == callId { cardModel.apply(a) }
    cardModel.queued = max(0, ringingOrder.count - 1)
  }

  private func callHandled(_ a: [String: Any]) {
    let callId = a["callId"] as? Int ?? -1
    ringing.removeValue(forKey: callId)
    ringingOrder.removeAll { $0 == callId }
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call-\(callId)"])
    if ringingOrder.isEmpty {
      hideCard()
    } else if cardModel.callId == callId, let next = ringingOrder.first, let args = ringing[next] {
      cardModel.apply(args)
      cardModel.queued = max(0, ringingOrder.count - 1)
    }
  }

  private func showCard() {
    guard let first = ringingOrder.first, let args = ringing[first] else { return }
    cardModel.apply(args)
    cardModel.queued = max(0, ringingOrder.count - 1)

    if cardPanel == nil {
      let view = CallCardView(
        model: cardModel,
        onAnswer: { [weak self] in self?.cardAction("answer", bringFront: true) },
        onMute: { [weak self] in self?.cardAction("mute", bringFront: false) },
        onReject: { [weak self] in self?.cardAction("reject", bringFront: false) })
      let host = NSHostingView(rootView: view)
      let size = host.fittingSize
      let panel = CallCardPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.contentView = host
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.level = .statusBar
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.isMovableByWindowBackground = true
      panel.hidesOnDeactivate = false
      cardPanel = panel
    }
    guard let panel = cardPanel, let screen = NSScreen.main else { return }
    let vf = screen.visibleFrame
    let size = panel.frame.size
    let target = NSPoint(x: vf.maxX - size.width + 24 - 24, y: vf.maxY - size.height + 24 - 56)
    if !panel.isVisible {
      // Entrada deslizando desde la derecha (slide-in-right del diseño)
      panel.setFrameOrigin(NSPoint(x: target.x + 36, y: target.y))
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.32
        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        panel.animator().setFrameOrigin(target)
        panel.animator().alphaValue = 1
      }
    }
  }

  private func hideCard() {
    guard let panel = cardPanel, panel.isVisible else { return }
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.2
      panel.animator().alphaValue = 0
    }, completionHandler: { panel.orderOut(nil) })
  }

  private func cardAction(_ action: String, bringFront: Bool) {
    windowChannel?.invokeMethod("notificationAction", arguments: ["action": action, "callId": cardModel.callId])
    if bringFront { self.bringToFront() }
  }

  // MARK: Notificaciones del sistema (opcionales)

  private func setupNotifications() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    let answer = UNNotificationAction(identifier: "answer", title: "Contestar", options: [.foreground])
    let reject = UNNotificationAction(identifier: "reject", title: "Rechazar", options: [.destructive])
    let category = UNNotificationCategory(identifier: "incoming-call", actions: [answer, reject], intentIdentifiers: [], options: [])
    center.setNotificationCategories([category])
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  private func postNotification(callId: Int, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = "incoming-call"
    content.userInfo = ["callId": callId]
    content.interruptionLevel = .timeSensitive
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "call-\(callId)", content: content, trigger: nil))
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    let callId = response.notification.request.content.userInfo["callId"] as? Int ?? -1
    DispatchQueue.main.async {
      switch response.actionIdentifier {
      case "answer":
        self.windowChannel?.invokeMethod("notificationAction", arguments: ["action": "answer", "callId": callId])
        self.bringToFront()
      case "reject":
        self.windowChannel?.invokeMethod("notificationAction", arguments: ["action": "reject", "callId": callId])
      default:
        self.bringToFront()
      }
    }
    completionHandler()
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list])
  }

  private func bringToFront() {
    if NSApp.isHidden { NSApp.unhide(nil) }
    if self.isMiniaturized { self.deminiaturize(nil) }
    NSApp.activate(ignoringOtherApps: true)
    self.makeKeyAndOrderFront(nil)
  }
}
