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

  private var openFileMethodChannel: FlutterMethodChannel?
  private var openFileEventChannel: FlutterEventChannel?
  private var openFileEventSink: FlutterEventSink?
  private var pendingOpenFiles: [String] = []
  private var channelsConfigured = false
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
      os_log("LSRegisterURL(%{private}@) returned %d", log: dacxLog, type: .info, bundleURL.path, status)
    }
  }

  func registerFlutterChannels(messenger: FlutterBinaryMessenger) {
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
    setupChannels(messenger: controller.engine.binaryMessenger)
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
