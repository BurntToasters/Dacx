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
    // start() resets titlebar/background to opaque defaults — undo that so
    // NSVisualEffectView can show through.
    restoreVibrancyWindowChrome()

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

    flutterViewController.backgroundColor = .clear

    let windowFrame = self.frame
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController(
      flutterViewController: flutterViewController
    )
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)
    restoreVibrancyWindowChrome()
  }

  /// Re-apply chrome needed for behind-window vibrancy after
  /// MainFlutterWindowManipulator.start() (which sets opaque defaults).
  private func restoreVibrancyWindowChrome() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    isOpaque = false
    backgroundColor = .clear
    // Keep shadow; invalidate after transparency changes so DWM/AppKit
    // recomputes the silhouette (Flutter #122133).
    hasShadow = true
    styleMask.insert(.fullSizeContentView)
    if let wrapped = contentViewController as? MacOSWindowUtilsViewController {
      let flutterVC = wrapped.flutterViewController
      flutterVC.backgroundColor = .clear
      // Ensure the Flutter NSView itself is not treated as opaque.
      flutterVC.view.wantsLayer = true
      flutterVC.view.layer?.backgroundColor = NSColor.clear.cgColor
      flutterVC.view.layer?.isOpaque = false
      if let effectView = wrapped.view as? NSVisualEffectView {
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        if #available(macOS 10.14, *) {
          // underWindowBackground / hudWindow actually blur desktop content;
          // windowBackground is mostly opaque wallpaper-tint.
          effectView.material = .underWindowBackground
        }
      }
    }
    invalidateShadow()
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
