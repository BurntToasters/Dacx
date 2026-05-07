import Cocoa
import CoreServices
import FlutterMacOS
import os.log

// Subsystem identifies our binary in unified logging; category groups the
// open-file/Launch-Services bridge messages. Paths are passed via
// %{private}@ so Console.app redacts them unless explicitly enabled.
private let dacxLog = OSLog(subsystem: "run.rosie.dacx", category: "open-file")

@main
class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private let openFileMethodChannelName = "run.rosie.dacx/open_file/methods"
  private let openFileEventChannelName = "run.rosie.dacx/open_file/events"
  private let windowMethodChannelName = "run.rosie.dacx/window/methods"

  private var openFileMethodChannel: FlutterMethodChannel?
  private var openFileEventChannel: FlutterEventChannel?
  private var windowMethodChannels: [ObjectIdentifier: FlutterMethodChannel] = [:]
  private var openFileEventSink: FlutterEventSink?
  private var pendingOpenFiles: [String] = []
  private var channelsConfigured = false
  private var auxiliaryWindows: [MainFlutterWindow] = []
  private let mediaSessionBridge = MediaSessionBridge()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    refreshLaunchServicesRegistrationInBackground()
    configureOpenFileChannelsIfNeeded()
  }

  /// Re-registers the running bundle with Launch Services
  private func refreshLaunchServicesRegistrationInBackground() {
    let bundleURL = Bundle.main.bundleURL
    DispatchQueue.global(qos: .utility).async {
      let status = LSRegisterURL(bundleURL as CFURL, true)
      if status == noErr {
        os_log("LSRegisterURL(%{private}@) succeeded", log: dacxLog, type: .info, bundleURL.path)
      } else {
        os_log("LSRegisterURL(%{private}@) failed with OSStatus %d", log: dacxLog, type: .error, bundleURL.path, status)
      }
    }
  }

  func registerFlutterChannels(messenger: FlutterBinaryMessenger, for window: MainFlutterWindow) {
    setupWindowChannel(messenger: messenger, for: window)
    if channelsConfigured { return }
    os_log("registering Flutter channels eagerly from MainFlutterWindow", log: dacxLog, type: .debug)
    setupChannels(messenger: messenger)
  }

  private func configureOpenFileChannelsIfNeeded() {
    if channelsConfigured { return }
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      DispatchQueue.main.async { [weak self] in
        self?.configureOpenFileChannelsIfNeeded()
      }
      return
    }
    if let window = mainFlutterWindow as? MainFlutterWindow {
      setupWindowChannel(messenger: controller.engine.binaryMessenger, for: window)
    }
    setupChannels(messenger: controller.engine.binaryMessenger)
  }

  private func setupWindowChannel(messenger: FlutterBinaryMessenger, for window: MainFlutterWindow) {
    let windowId = ObjectIdentifier(window)
    if windowMethodChannels[windowId] != nil { return }

    let methodChannel = FlutterMethodChannel(
      name: windowMethodChannelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "openNewWindow":
        result(self.openNewWindow())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    windowMethodChannels[windowId] = methodChannel
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(flutterWindowWillClose(_:)),
      name: NSWindow.willCloseNotification,
      object: window
    )
  }

  private func setupChannels(messenger: FlutterBinaryMessenger) {
    if channelsConfigured { return }
    let methodChannel = FlutterMethodChannel(
      name: openFileMethodChannelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result([])
        return
      }
      switch call.method {
      case "getPendingFiles":
        result(self.drainPendingOpenFiles())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: openFileEventChannelName,
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)

    openFileMethodChannel = methodChannel
    openFileEventChannel = eventChannel
    mediaSessionBridge.attach(messenger: messenger)
    channelsConfigured = true
    os_log("Flutter channels configured (pending=%d)", log: dacxLog, type: .debug, pendingOpenFiles.count)
  }

  private func drainPendingOpenFiles() -> [String] {
    let files = pendingOpenFiles
    pendingOpenFiles.removeAll()
    return files
  }

  private func handleOpenFile(_ rawPath: String) {
    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    if path.isEmpty { return }

    configureOpenFileChannelsIfNeeded()
    if let sink = openFileEventSink {
      sink(path)
    } else {
      pendingOpenFiles.append(path)
    }
  }

  private func openNewWindow() -> Bool {
    let referenceFrame = NSApp.keyWindow?.frame ?? mainFlutterWindow?.frame
    let contentRect: NSRect
    if let frame = referenceFrame {
      contentRect = frame.offsetBy(dx: 28, dy: -28)
    } else if let screenFrame = NSScreen.main?.visibleFrame {
      let size = NSSize(width: 960, height: 600)
      contentRect = NSRect(
        x: screenFrame.midX - size.width / 2,
        y: screenFrame.midY - size.height / 2,
        width: size.width,
        height: size.height
      )
    } else {
      contentRect = NSRect(x: 0, y: 0, width: 960, height: 600)
    }

    let window = MainFlutterWindow(
      contentRect: contentRect,
      styleMask: [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
        .fullSizeContentView,
      ],
      backing: .buffered,
      defer: false
    )
    window.title = "Dacx"
    window.isReleasedWhenClosed = false
    window.configureFlutterContent()
    auxiliaryWindows.append(window)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return true
  }

  @objc private func flutterWindowWillClose(_ notification: Notification) {
    guard let closedWindow = notification.object as? MainFlutterWindow else {
      return
    }
    NotificationCenter.default.removeObserver(
      self,
      name: NSWindow.willCloseNotification,
      object: closedWindow
    )
    windowMethodChannels.removeValue(forKey: ObjectIdentifier(closedWindow))
    auxiliaryWindows.removeAll { $0 === closedWindow }
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    super.application(application, open: urls)
    os_log("application(_:open urls:) received %d URL(s)", log: dacxLog, type: .info, urls.count)
    for url in urls {
      // For sandboxed workaround
      let scoped = url.startAccessingSecurityScopedResource()
      defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
      }
      if url.isFileURL {
        os_log("handling file URL: %{private}@ (scoped=%{public}@)", log: dacxLog, type: .info, url.path, scoped ? "true" : "false")
        handleOpenFile(url.path)
      } else {
        os_log("handling non-file URL: %{private}@", log: dacxLog, type: .info, url.absoluteString)
        handleOpenFile(url.absoluteString)
      }
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    os_log("application(_:openFile:) received: %{private}@", log: dacxLog, type: .info, filename)
    handleOpenFile(filename)
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    openFileEventSink = events
    let pending = drainPendingOpenFiles()
    for path in pending {
      events(path)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    openFileEventSink = nil
    return nil
  }
}
