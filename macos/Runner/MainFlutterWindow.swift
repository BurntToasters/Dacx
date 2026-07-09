import Cocoa
import FlutterMacOS
import macos_window_utils
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    configureFlutterContent()
    super.awakeFromNib()
  }

  func configureFlutterContent() {
    // Already wrapped for native vibrancy / blur.
    if contentViewController is MacOSWindowUtilsViewController { return }
    // Already has a bare Flutter VC (e.g. mid-migration); wrap it below.
    if contentViewController is FlutterViewController {
      wrapExistingFlutterViewController()
      return
    }

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    isOpaque = false
    backgroundColor = .clear

    let windowFrame = self.frame
    // MacOSWindowUtilsViewController hosts an NSVisualEffectView behind Flutter.
    // Without this wrap, flutter_acrylic setMaterial has nothing to tint — window
    // stays transparent with no blur (sharp desktop shows through).
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController()
    macOSWindowUtilsViewController.flutterViewController.backgroundColor = .clear
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(
      registry: macOSWindowUtilsViewController.flutterViewController
    )

    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.registerFlutterChannels(
        messenger: macOSWindowUtilsViewController.flutterViewController.engine.binaryMessenger,
        for: self
      )
    }
  }

  /// Wraps a bare FlutterViewController in MacOSWindowUtilsViewController so
  /// NSVisualEffectView materials from flutter_acrylic can take effect.
  private func wrapExistingFlutterViewController() {
    guard let flutterViewController = contentViewController as? FlutterViewController
    else { return }

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    isOpaque = false
    backgroundColor = .clear
    flutterViewController.backgroundColor = .clear

    let windowFrame = self.frame
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController(
      flutterViewController: flutterViewController
    )
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)
  }

  /// Flutter engine for this window (works with or without the blur wrapper).
  var flutterViewController: FlutterViewController? {
    if let wrapped = contentViewController as? MacOSWindowUtilsViewController {
      return wrapped.flutterViewController
    }
    return contentViewController as? FlutterViewController
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
