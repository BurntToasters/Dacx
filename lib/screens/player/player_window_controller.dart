import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/debug_log_service.dart';

typedef PlayerWindowLog = void Function(
  String event, {
  DebugLogCategory category,
  String? message,
  Map<String, Object?> Function()? detailsBuilder,
  DebugSeverity severity,
});

class PlayerWindowController extends ChangeNotifier {
  PlayerWindowController({
    required this.isMounted,
    required this.isDisposed,
    required this.alwaysOnTop,
    required this.log,
    required this.onFullscreenRejected,
    required this.onCompactModeChanged,
    this.shouldHoldChrome,
    this.videoAspectRatio,
  });

  static const Size compactWindowSize = Size(480, 320);
  static const Size compactMinimumSize = Size(240, 135);
  static const Size normalMinimumSize = Size(480, 320);

  @visibleForTesting
  static bool? debugLinuxOverride;
  static const Duration fullscreenChromeIdleDelay = Duration(seconds: 3);

  final bool Function() isMounted;
  final bool Function() isDisposed;
  final bool Function() alwaysOnTop;
  final PlayerWindowLog log;
  final VoidCallback onFullscreenRejected;
  final ValueChanged<bool> onCompactModeChanged;
  final bool Function()? shouldHoldChrome;
  final Future<double?> Function()? videoAspectRatio;

  Timer? _fullscreenChromeHideTimer;
  bool _pointerOverChrome = false;
  int _pointersDownInChrome = 0;
  bool _waitingForHoldRelease = false;
  bool _fullscreenToggleInFlight = false;
  bool _isFullscreen = false;
  bool _fullscreenChromeVisible = true;

  // Compact mini-player mode (PiP-style on desktop).
  bool _compactMode = false;
  bool _compactToggleInFlight = false;
  Size? _preCompactSize;
  Offset? _preCompactPos;
  bool _preCompactMaximized = false;
  double? _compactAspect;

  bool get isFullscreen => _isFullscreen;
  bool get fullscreenChromeVisible => _fullscreenChromeVisible;
  bool get compactMode => _compactMode;

  void revealFullscreenChrome() {
    if (!_isFullscreen) return;
    if (!_fullscreenChromeVisible && isMounted()) {
      _fullscreenChromeVisible = true;
      notifyListeners();
    }
    _scheduleFullscreenChromeHide();
  }

  bool get _chromeHeld =>
      _pointerOverChrome ||
      _pointersDownInChrome > 0 ||
      (shouldHoldChrome?.call() ?? false);

  void setPointerOverChrome(bool over) {
    _pointerOverChrome = over;
    if (!over) onChromeHoldsChanged();
  }

  void pointerDownInChrome() {
    _pointersDownInChrome++;
  }

  void pointerUpInChrome() {
    if (_pointersDownInChrome > 0) _pointersDownInChrome--;
    onChromeHoldsChanged();
  }

  void onChromeHoldsChanged() {
    if (!_waitingForHoldRelease || _chromeHeld) return;
    _scheduleFullscreenChromeHide();
  }

  void _resetChromeHolds() {
    _pointerOverChrome = false;
    _pointersDownInChrome = 0;
    _waitingForHoldRelease = false;
  }

  void _scheduleFullscreenChromeHide() {
    _fullscreenChromeHideTimer?.cancel();
    _waitingForHoldRelease = false;
    if (!_isFullscreen) return;
    _fullscreenChromeHideTimer = Timer(fullscreenChromeIdleDelay, () {
      if (!isMounted() || isDisposed() || !_isFullscreen) return;
      if (_chromeHeld) {
        _waitingForHoldRelease = true;
        return;
      }
      _fullscreenChromeVisible = false;
      notifyListeners();
    });
  }

  void onEnterFullScreen() {
    if (!isMounted()) return;
    _isFullscreen = true;
    _fullscreenChromeVisible = true;
    notifyListeners();
    _scheduleFullscreenChromeHide();
  }

  void onLeaveFullScreen() {
    _fullscreenChromeHideTimer?.cancel();
    _resetChromeHolds();
    if (!isMounted()) {
      _isFullscreen = false;
      _fullscreenChromeVisible = true;
      return;
    }
    _isFullscreen = false;
    _fullscreenChromeVisible = true;
    notifyListeners();
  }

  Future<void> exitFullscreenIfActuallyFullscreen() async {
    try {
      if (!await windowManager.isFullScreen()) return;
      if (!isMounted()) return;
      _isFullscreen = true;
      notifyListeners();
      log('shortcut_exit_fullscreen', category: DebugLogCategory.ui);
      await exitFullscreen();
    } catch (e) {
      log(
        'fullscreen_reconcile_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  Future<void> toggleFullscreen() async {
    if (_fullscreenToggleInFlight) return;
    _fullscreenToggleInFlight = true;
    try {
      final enabled = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!enabled);
      // Verify state actually changed (Wayland / tiling WMs may reject).
      final actual = await windowManager.isFullScreen();
      if (isMounted()) {
        _isFullscreen = actual;
        if (actual) {
          _fullscreenChromeVisible = true;
        } else {
          _fullscreenChromeHideTimer?.cancel();
          _resetChromeHolds();
          _fullscreenChromeVisible = true;
        }
        notifyListeners();
        if (actual) {
          _scheduleFullscreenChromeHide();
        }
      }
      if (actual == enabled && isMounted()) {
        onFullscreenRejected();
      }
      log(
        'fullscreen_toggled',
        category: DebugLogCategory.ui,
        detailsBuilder: () => {'requested': !enabled, 'actual': actual},
      );
    } catch (e) {
      log(
        'fullscreen_toggle_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    } finally {
      _fullscreenToggleInFlight = false;
    }
  }

  Future<void> exitFullscreen() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        if (isMounted()) {
          _isFullscreen = false;
          _fullscreenChromeHideTimer?.cancel();
          _resetChromeHolds();
          _fullscreenChromeVisible = true;
          notifyListeners();
        }
      } else if (isMounted()) {
        _isFullscreen = false;
        _fullscreenChromeHideTimer?.cancel();
        _resetChromeHolds();
        _fullscreenChromeVisible = true;
        notifyListeners();
      }
    } catch (e) {
      log(
        'fullscreen_exit_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  // ── Compact / mini-player mode ────────────────────────────

  Future<void> toggleCompactMode() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    if (_compactToggleInFlight) return;
    _compactToggleInFlight = true;
    try {
      if (_compactMode) {
        // Restore window state.
        try {
          await windowManager.setAspectRatio(0);
          await windowManager.setMinimumSize(normalMinimumSize);
          if (_preCompactMaximized) {
            await windowManager.maximize();
          } else {
            if (_preCompactSize != null) {
              await windowManager.setSize(_preCompactSize!);
            }
            if (_preCompactPos != null) {
              await windowManager.setPosition(_preCompactPos!);
            }
          }
          await windowManager.setAlwaysOnTop(alwaysOnTop());
        } catch (e) {
          log(
            'compact_mode_restore_failed',
            category: DebugLogCategory.ui,
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
          await _reapplyCompactConstraints();
          return;
        }
        _compactAspect = null;
        if (!isMounted() || isDisposed()) return;
        _compactMode = false;
        notifyListeners();
        onCompactModeChanged(false);
      } else {
        try {
          final size = await windowManager.getSize();
          final position = await windowManager.getPosition();
          final maximized = await windowManager.isMaximized();
          if (await windowManager.isFullScreen()) {
            await windowManager.setFullScreen(false);
            if (isMounted()) {
              _isFullscreen = false;
            }
          }
          if (maximized) {
            await windowManager.unmaximize();
          }
          final aspect = await _currentVideoAspect();
          await windowManager.setMinimumSize(compactMinimumSize);
          await windowManager.setSize(_compactSizeFor(aspect));
          await windowManager.setAlwaysOnTop(true);
          if (aspect != null) {
            await windowManager.setAspectRatio(aspect);
            _compactAspect = aspect;
          }
          _preCompactSize = size;
          _preCompactPos = position;
          _preCompactMaximized = maximized;
        } catch (e) {
          log(
            'compact_mode_enter_failed',
            category: DebugLogCategory.ui,
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
          await _releaseCompactConstraints();
          return;
        }
        if (!isMounted() || isDisposed()) return;
        _compactMode = true;
        notifyListeners();
        onCompactModeChanged(true);
      }
    } finally {
      _compactToggleInFlight = false;
    }
  }

  Future<double?> _currentVideoAspect() async {
    final provider = videoAspectRatio;
    if (provider == null) return null;
    try {
      final ratio = await provider();
      if (ratio == null || !ratio.isFinite || ratio <= 0) return null;
      return ratio;
    } catch (_) {
      return null;
    }
  }

  Size _compactSizeFor(double? aspect) {
    if (aspect == null) return compactWindowSize;
    const box = compactWindowSize;
    var width = box.width;
    var height = width / aspect;
    if (height > box.height) {
      height = box.height;
      width = height * aspect;
    }
    return Size(
      width.clamp(compactMinimumSize.width, double.infinity).roundToDouble(),
      height.clamp(compactMinimumSize.height, double.infinity).roundToDouble(),
    );
  }

  Future<void> _releaseCompactConstraints() async {
    _compactAspect = null;
    try {
      await windowManager.setAspectRatio(0);
      await windowManager.setMinimumSize(normalMinimumSize);
    } catch (e) {
      log(
        'compact_mode_constraints_release_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  Future<void> _reapplyCompactConstraints() async {
    try {
      await windowManager.setMinimumSize(compactMinimumSize);
      final aspect = _compactAspect;
      if (aspect != null) {
        await windowManager.setAspectRatio(aspect);
      }
    } catch (e) {
      log(
        'compact_mode_constraints_reapply_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  Future<void> syncCompactAspectRatio() async {
    if (!_compactMode || _compactToggleInFlight) return;
    final aspect = await _currentVideoAspect();
    if (!_compactMode || _compactToggleInFlight || !isMounted()) return;
    final previous = _compactAspect;
    if (aspect == previous) return;
    if (aspect != null && previous != null) {
      if ((aspect - previous).abs() < 0.001) return;
    }
    try {
      if (aspect == null) {
        await windowManager.setAspectRatio(0);
        _compactAspect = null;
        return;
      }
      await windowManager.setAspectRatio(aspect);
      _compactAspect = aspect;
      final current = await windowManager.getSize();
      final target = Size(
        current.width,
        (current.width / aspect).roundToDouble(),
      );
      if (target.height >= compactMinimumSize.height &&
          (target.height - current.height).abs() >= 1) {
        await windowManager.setSize(target);
      }
    } catch (e) {
      log(
        'compact_mode_aspect_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  void startWindowDrag() {
    if (debugLinuxOverride ?? Platform.isLinux) return;
    unawaited(
      windowManager.startDragging().catchError((Object e) {
        log(
          'window_drag_failed',
          category: DebugLogCategory.ui,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
  }

  void applyAlwaysOnTop(bool value) {
    unawaited(
      windowManager.setAlwaysOnTop(value).catchError((Object e) {
        log(
          'always_on_top_apply_failed',
          category: DebugLogCategory.system,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
  }

  @override
  void dispose() {
    _fullscreenChromeHideTimer?.cancel();
    super.dispose();
  }
}
