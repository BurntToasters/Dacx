import Cocoa
import FlutterMacOS

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
    configureOpenFileChannelsIfNeeded()
  }

  private func configureOpenFileChannelsIfNeeded() {
    if channelsConfigured { return }
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      DispatchQueue.main.async { [weak self] in
        self?.configureOpenFileChannelsIfNeeded()
      }
      return
    }

    let messenger = controller.engine.binaryMessenger
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

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    handleOpenFile(filename)
    return true
  }

  override func application(_ application: NSApplication, openFiles filenames: [String]) {
    for filename in filenames {
      handleOpenFile(filename)
    }
    NSApp.reply(toOpenOrPrint: .success)
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
