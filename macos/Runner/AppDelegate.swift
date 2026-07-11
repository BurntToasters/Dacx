import Cocoa
import CoreServices
import FlutterMacOS
import os.log

private let dacxLog = OSLog(subsystem: "run.rosie.dacx", category: "open-file")

// Per-window engine bookkeeping so each Flutter view participates in OS
// integrations (open-file, media session) like the primary window.
private final class EngineRegistration {
  weak var window: MainFlutterWindow?
  let messenger: FlutterBinaryMessenger
  let openFileMethodChannel: FlutterMethodChannel
  let openFileEventChannel: FlutterEventChannel
  let openFileStreamHandler: OpenFileStreamHandler
  let windowMethodChannel: FlutterMethodChannel
  let mediaSessionChannel: FlutterMethodChannel
  let updateBridge: UpdateBridge
  let bookmarkBridge: BookmarkBridge

  init(window: MainFlutterWindow,
       messenger: FlutterBinaryMessenger,
       openFileMethodChannel: FlutterMethodChannel,
       openFileEventChannel: FlutterEventChannel,
       openFileStreamHandler: OpenFileStreamHandler,
       windowMethodChannel: FlutterMethodChannel,
       mediaSessionChannel: FlutterMethodChannel,
       updateBridge: UpdateBridge,
       bookmarkBridge: BookmarkBridge) {
    self.window = window
    self.messenger = messenger
    self.openFileMethodChannel = openFileMethodChannel
    self.openFileEventChannel = openFileEventChannel
    self.openFileStreamHandler = openFileStreamHandler
    self.windowMethodChannel = windowMethodChannel
    self.mediaSessionChannel = mediaSessionChannel
    self.updateBridge = updateBridge
    self.bookmarkBridge = bookmarkBridge
  }
}

/// Per-engine `FlutterStreamHandler` that forwards onListen/onCancel to
/// closures.
final class OpenFileStreamHandler: NSObject, FlutterStreamHandler {
  private let onListenCallback: (FlutterEventSink) -> Void
  private let onCancelCallback: () -> Void
  private(set) var sink: FlutterEventSink?

  init(onListen: @escaping (FlutterEventSink) -> Void,
       onCancel: @escaping () -> Void) {
    self.onListenCallback = onListen
    self.onCancelCallback = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    onListenCallback(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    onCancelCallback()
    return nil
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  private let openFileMethodChannelName = "run.rosie.dacx/open_file/methods"
  private let openFileEventChannelName = "run.rosie.dacx/open_file/events"
  private let windowMethodChannelName = "run.rosie.dacx/window/methods"

  private var registrations: [ObjectIdentifier: EngineRegistration] = [:]
  private var pendingOpenFiles: [[String: String]] = []
  private var auxiliaryWindows: [MainFlutterWindow] = []
  // MPNowPlayingInfoCenter / MPRemoteCommandCenter are process singletons;
  // one bridge attached to every engine's messenger.
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

  /// Called by `MainFlutterWindow.configureFlutterContent()` for both the
  /// primary window and any auxiliary window from `openNewWindow`.
  func registerFlutterChannels(messenger: FlutterBinaryMessenger, for window: MainFlutterWindow) {
    setupChannels(messenger: messenger, for: window)
  }

  private func configureOpenFileChannelsIfNeeded() {
    if !registrations.isEmpty { return }
    guard let window = mainFlutterWindow as? MainFlutterWindow,
          let controller = window.flutterViewController else {
      DispatchQueue.main.async { [weak self] in
        self?.configureOpenFileChannelsIfNeeded()
      }
      return
    }
    setupChannels(messenger: controller.engine.binaryMessenger, for: window)
  }

  private func setupChannels(messenger: FlutterBinaryMessenger, for window: MainFlutterWindow) {
    let windowId = ObjectIdentifier(window)
    if registrations[windowId] != nil { return }

    let openFileMethodChannel = FlutterMethodChannel(
      name: openFileMethodChannelName,
      binaryMessenger: messenger
    )
    openFileMethodChannel.setMethodCallHandler { [weak self] call, result in
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

    let openFileEventChannel = FlutterEventChannel(
      name: openFileEventChannelName,
      binaryMessenger: messenger
    )
    let streamHandler = OpenFileStreamHandler(
      onListen: { [weak self] sink in
        guard let self else { return }
        // Drain queued paths into the first sink that comes online.
        let pending = self.drainPendingOpenFiles()
        for payload in pending { sink(payload) }
      },
      onCancel: {}
    )
    openFileEventChannel.setStreamHandler(streamHandler)

    let windowMethodChannel = FlutterMethodChannel(
      name: windowMethodChannelName,
      binaryMessenger: messenger
    )
    windowMethodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "openNewWindow":
        result(self.openNewWindow())
      case "clearLayeredStyle":
        // Windows-only helper; no-op on macOS so Dart can call unconditionally.
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let mediaSessionChannel = mediaSessionBridge.attach(messenger: messenger)
    let updateBridge = UpdateBridge(messenger: messenger)
    let bookmarkBridge = BookmarkBridge(messenger: messenger)

    let registration = EngineRegistration(
      window: window,
      messenger: messenger,
      openFileMethodChannel: openFileMethodChannel,
      openFileEventChannel: openFileEventChannel,
      openFileStreamHandler: streamHandler,
      windowMethodChannel: windowMethodChannel,
      mediaSessionChannel: mediaSessionChannel,
      updateBridge: updateBridge,
      bookmarkBridge: bookmarkBridge
    )
    registrations[windowId] = registration

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(flutterWindowWillClose(_:)),
      name: NSWindow.willCloseNotification,
      object: window
    )
    os_log("Flutter channels configured for window (engines=%d, pending=%d)",
           log: dacxLog, type: .debug, registrations.count, pendingOpenFiles.count)
  }

  private func drainPendingOpenFiles() -> [[String: String]] {
    let files = pendingOpenFiles
    pendingOpenFiles.removeAll()
    return files
  }

  private func handleOpenFile(_ rawPath: String, bookmark: String? = nil) {
    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    if path.isEmpty { return }
    var payload = ["path": path]
    if let bookmark, !bookmark.isEmpty {
      payload["bookmark"] = bookmark
    }

    configureOpenFileChannelsIfNeeded()

    // Prefer the key/main window's sink; fall back to any active sink, else queue.
    if let preferred = preferredActiveSink() {
      preferred(payload)
      return
    }
    pendingOpenFiles.append(payload)
  }

  private func securityScopedBookmark(for url: URL) -> String? {
    guard url.isFileURL else { return nil }
    do {
      let data = try url.bookmarkData(options: [.withSecurityScope],
                                      includingResourceValuesForKeys: nil,
                                      relativeTo: nil)
      return data.base64EncodedString()
    } catch {
      os_log("security-scoped bookmark create failed for %{private}@: %{public}@",
             log: dacxLog, type: .error, url.path, "\(error)")
      return nil
    }
  }

  private func preferredActiveSink() -> FlutterEventSink? {
    let preferredWindow = (NSApp.keyWindow as? MainFlutterWindow)
        ?? (NSApp.mainWindow as? MainFlutterWindow)
        ?? (mainFlutterWindow as? MainFlutterWindow)
    if let win = preferredWindow,
       let reg = registrations[ObjectIdentifier(win)],
       let sink = reg.openFileStreamHandler.sink {
      return sink
    }
    for reg in registrations.values {
      if let sink = reg.openFileStreamHandler.sink { return sink }
    }
    return nil
  }

  private func openNewWindow() -> Bool {
    let referenceWindow = NSApp.keyWindow ?? mainFlutterWindow
    let baseContentRect: NSRect
    if let refWin = referenceWindow {
      // Use content rect (not frame) so the new window doesn't grow by the
      // title bar height each spawn.
      baseContentRect = refWin.contentRect(forFrameRect: refWin.frame)
    } else if let screenFrame = NSScreen.main?.visibleFrame {
      let size = NSSize(width: 960, height: 600)
      baseContentRect = NSRect(
        x: screenFrame.midX - size.width / 2,
        y: screenFrame.midY - size.height / 2,
        width: size.width,
        height: size.height
      )
    } else {
      baseContentRect = NSRect(x: 0, y: 0, width: 960, height: 600)
    }

    let window = MainFlutterWindow(
      contentRect: baseContentRect,
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
    if let refWin = referenceWindow {
      _ = window.cascadeTopLeft(from: NSPoint(x: refWin.frame.minX, y: refWin.frame.maxY))
    }
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
    let windowId = ObjectIdentifier(closedWindow)
    if let reg = registrations.removeValue(forKey: windowId) {
      reg.openFileMethodChannel.setMethodCallHandler(nil)
      reg.openFileEventChannel.setStreamHandler(nil)
      reg.windowMethodChannel.setMethodCallHandler(nil)
      mediaSessionBridge.detach(channel: reg.mediaSessionChannel)
    }
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
        handleOpenFile(url.path, bookmark: securityScopedBookmark(for: url))
      } else {
        os_log("handling non-file URL: %{private}@", log: dacxLog, type: .info, url.absoluteString)
        handleOpenFile(url.absoluteString)
      }
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    os_log("application(_:openFile:) received: %{private}@", log: dacxLog, type: .info, filename)
    let url = URL(fileURLWithPath: filename)
    handleOpenFile(filename, bookmark: securityScopedBookmark(for: url))
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Application menu → Flutter Settings-equivalent update check.
  @IBAction func checkForUpdates(_ sender: Any?) {
    invokeFlutterMethod("checkForUpdates")
  }

  /// Application menu → Flutter Settings (Preferences… / ⌘,).
  @IBAction func openPreferences(_ sender: Any?) {
    invokeFlutterMethod("openPreferences")
  }

  /// File → Open….
  @IBAction func openMediaFile(_ sender: Any?) {
    invokeFlutterMethod("openFile")
  }

  /// File → Open URL….
  @IBAction func openMediaUrl(_ sender: Any?) {
    invokeFlutterMethod("openUrl")
  }

  /// File → Open Recent item (representedObject is the path string).
  @IBAction func openRecentFile(_ sender: Any?) {
    guard let item = sender as? NSMenuItem,
          let path = item.representedObject as? String,
          !path.isEmpty else { return }
    invokeFlutterMethod("openRecent", arguments: path)
  }

  private func invokeFlutterMethod(_ method: String, arguments: Any? = nil) {
    guard let channel = preferredWindowMethodChannel() else {
      os_log("%{public}@: no Flutter window channel ready",
             log: dacxLog, type: .error, method)
      return
    }
    channel.invokeMethod(method, arguments: arguments)
  }

  private func preferredWindowMethodChannel() -> FlutterMethodChannel? {
    let preferredWindow = (NSApp.keyWindow as? MainFlutterWindow)
        ?? (NSApp.mainWindow as? MainFlutterWindow)
        ?? (mainFlutterWindow as? MainFlutterWindow)
    if let win = preferredWindow,
       let reg = registrations[ObjectIdentifier(win)] {
      return reg.windowMethodChannel
    }
    return registrations.values.first?.windowMethodChannel
  }

  /// Rebuilds File → Open Recent from Flutter's recent_files list.
  func refreshOpenRecentMenu() {
    guard let recentMenu = openRecentSubmenu() else { return }
    recentMenu.removeAllItems()
    guard let channel = preferredWindowMethodChannel() else {
      recentMenu.addItem(disabledRecentPlaceholder())
      return
    }
    channel.invokeMethod("getRecentFiles", arguments: nil) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        recentMenu.removeAllItems()
        let paths = (result as? [Any])?.compactMap { $0 as? String } ?? []
        if paths.isEmpty {
          recentMenu.addItem(self.disabledRecentPlaceholder())
          return
        }
        for path in paths.prefix(12) {
          let title = (path as NSString).lastPathComponent
          let item = NSMenuItem(
            title: title.isEmpty ? path : title,
            action: #selector(self.openRecentFile(_:)),
            keyEquivalent: ""
          )
          item.target = self
          item.representedObject = path
          recentMenu.addItem(item)
        }
      }
    }
  }

  private func openRecentSubmenu() -> NSMenu? {
    guard let mainMenu = NSApp.mainMenu else { return nil }
    for root in mainMenu.items {
      guard let submenu = root.submenu, submenu.title == "File" else { continue }
      for item in submenu.items where item.title == "Open Recent" {
        return item.submenu
      }
    }
    return nil
  }

  private func disabledRecentPlaceholder() -> NSMenuItem {
    let item = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    super.applicationDidBecomeActive(notification)
    refreshOpenRecentMenu()
  }
}
