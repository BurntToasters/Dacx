import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/debug_log_service.dart';
import '../../services/window_metrics.dart';

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
    required this.onCompactGeometryHold,
    this.shouldHoldChrome,
    this.videoAspectRatio,
  });

  static const Size compactWindowSize = WindowMetrics.compactWindowSize;
  static const Size compactMinimumSize = WindowMetrics.compactMinimumSize;
  static const Size normalMinimumSize = WindowMetrics.normalMinimumSize;

  @visibleForTesting
  static bool? debugLinuxOverride;
  static const Duration fullscreenChromeIdleDelay = Duration(seconds: 3);

  final bool Function() isMounted;
  final bool Function() isDisposed;
  final bool Function() alwaysOnTop;
  final PlayerWindowLog log;
  final VoidCallback onFullscreenRejected;
  final ValueChanged<bool> onCompactModeChanged;
  final ValueChanged<bool> onCompactGeometryHold;
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
  bool _compactGeometryHeld = false;
  bool _restoreCompactAfterFullscreen = false;
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
    final leavingCompact = _compactMode;
    if (leavingCompact) {
      _compactMode = false;
      _restoreCompactAfterFullscreen = true;
    }
    _isFullscreen = true;
    _fullscreenChromeVisible = true;
    notifyListeners();
    _scheduleFullscreenChromeHide();
    if (leavingCompact) unawaited(_releaseCompactForFullscreen());
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
    if (_restoreCompactAfterFullscreen) {
      _restoreCompactAfterFullscreen = false;
      unawaited(_restoreCompactBoundsAfterFullscreen());
    }
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
      if (_compactMode && !await _exitCompactMode()) return;
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
    if (_compactMode) {
      await _exitCompactMode();
    } else {
      await _enterCompactMode();
    }
  }

  void releaseCompactGeometryHold() => _setCompactGeometryHold(false);

  void _setCompactGeometryHold(bool held) {
    if (_compactGeometryHeld == held) return;
    _compactGeometryHeld = held;
    onCompactGeometryHold(held);
  }

  Future<void> _enterCompactMode() async {
    _compactToggleInFlight = true;
    _setCompactGeometryHold(true);
    try {
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
        _setCompactGeometryHold(false);
        return;
      }
      if (!isMounted() || isDisposed()) return;
      _compactMode = true;
      notifyListeners();
      onCompactModeChanged(true);
    } finally {
      _compactToggleInFlight = false;
    }
  }

  Future<bool> _exitCompactMode() async {
    if (_compactToggleInFlight) return false;
    _compactToggleInFlight = true;
    try {
      try {
        // Restore window state.
        await windowManager.setAspectRatio(0);
        await windowManager.setMinimumSize(normalMinimumSize);
        await _restorePreCompactBounds();
        await windowManager.setAlwaysOnTop(alwaysOnTop());
      } catch (e) {
        log(
          'compact_mode_restore_failed',
          category: DebugLogCategory.ui,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
        await _reapplyCompactConstraints();
        return false;
      }
      _compactAspect = null;
      if (!isMounted() || isDisposed()) return true;
      _compactMode = false;
      notifyListeners();
      onCompactModeChanged(false);
      _setCompactGeometryHold(false);
      return true;
    } finally {
      _compactToggleInFlight = false;
    }
  }

  Future<void> _restorePreCompactBounds() async {
    if (_preCompactMaximized) {
      await windowManager.maximize();
      return;
    }
    final size = _preCompactSize;
    if (size != null) {
      await windowManager.setSize(size);
    }
    final position = _preCompactPos;
    if (position != null) {
      await windowManager.setPosition(position);
    }
  }

  Future<void> _releaseCompactForFullscreen() async {
    await _releaseCompactConstraints();
    try {
      await windowManager.setAlwaysOnTop(alwaysOnTop());
    } catch (e) {
      log(
        'compact_mode_fullscreen_release_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
    _setCompactGeometryHold(false);
  }

  Future<void> _restoreCompactBoundsAfterFullscreen() async {
    try {
      await _restorePreCompactBounds();
    } catch (e) {
      log(
        'compact_mode_fullscreen_restore_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
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
    if (_compactMode || _compactToggleInFlight) return;
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
