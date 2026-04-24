import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/player_screen.dart';
import 'services/debug_log_service.dart';
import 'services/settings_service.dart';
import 'theme/window_visuals.dart';

class _NoBounceScrollBehavior extends MaterialScrollBehavior {
  const _NoBounceScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

void _installKeyboardStateRecovery() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final text = details.exceptionAsString();
    if (text.contains(
          'A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed',
        ) ||
        text.contains(
          'A KeyUpEvent is dispatched, but the state shows that the physical key is not pressed',
        )) {
      unawaited(HardwareKeyboard.instance.syncKeyboardState());
    }
    previousOnError?.call(details);
  };
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _installKeyboardStateRecovery();
  MediaKit.ensureInitialized();
  await Window.initialize();

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final debugLog = DebugLogService(isEnabled: () => settings.debugModeEnabled);

  await windowManager.ensureInitialized();

  // Restore saved window geometry or use defaults.
  final savedSize = settings.rememberWindow ? settings.windowSize : null;
  final savedPos = settings.rememberWindow ? settings.windowPosition : null;

  final windowOptions = WindowOptions(
    size: savedSize ?? const Size(960, 600),
    minimumSize: const Size(480, 320),
    center: savedPos == null,
    title: 'Dacx',
    backgroundColor: Colors.transparent,
    titleBarStyle: Platform.isWindows || Platform.isMacOS
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
  );

  final windowReady = Completer<void>();
  final firstFrameReady = Completer<void>();
  var windowShown = false;

  Future<void> ensureHiddenTitleBarApplied() async {
    if (Platform.isMacOS) {
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      } catch (_) {}
      return;
    }
    if (!Platform.isWindows) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        final titleBarHeight = await windowManager.getTitleBarHeight();
        if (titleBarHeight <= 8) return;
      } catch (_) {
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: 36 * (attempt + 1)));
    }
  }

  Future<void> showWindowIfReady() async {
    if (windowShown ||
        !windowReady.isCompleted ||
        !firstFrameReady.isCompleted) {
      return;
    }
    windowShown = true;
    await windowManager.show();
    await windowManager.focus();
    unawaited(ensureHiddenTitleBarApplied());
  }

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    try {
      if (savedPos != null) {
        await windowManager.setPosition(savedPos);
      }
      await windowManager.setAlwaysOnTop(settings.alwaysOnTop);
      await ensureHiddenTitleBarApplied();
    } catch (_) {
      // Continue to show fallback even if startup window operations fail.
    } finally {
      if (!windowReady.isCompleted) {
        windowReady.complete();
      }
    }
    await showWindowIfReady();
  });

  // Collect CLI file argument (first non-flag arg).
  final cliFile = _parseCliFilePath(args);

  runApp(DacxApp(settings: settings, debugLog: debugLog, initialFile: cliFile));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!firstFrameReady.isCompleted) {
      firstFrameReady.complete();
    }
    await showWindowIfReady();
  });

  Future<void>.delayed(const Duration(seconds: 2), () async {
    if (windowShown) return;
    if (!windowReady.isCompleted) {
      windowReady.complete();
    }
    if (!firstFrameReady.isCompleted) {
      firstFrameReady.complete();
    }
    await showWindowIfReady();
  });
}

/// Extracts the first CLI argument that looks like a file path.
String? _parseCliFilePath(List<String> args) {
  for (final rawArg in args) {
    if (rawArg.trim().isEmpty || rawArg.startsWith('-')) continue;
    final candidatePath = _normalizeCliPath(rawArg);
    if (candidatePath != null && File(candidatePath).existsSync()) {
      return candidatePath;
    }
  }
  return null;
}

String? _normalizeCliPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.length >= 2 &&
      ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
          (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
    return trimmed.substring(1, trimmed.length - 1);
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    try {
      return uri.toFilePath(windows: Platform.isWindows);
    } catch (_) {
      return null;
    }
  }

  if (!trimmed.contains(':')) return trimmed;

  // Preserve Windows paths such as C:\music\song.mp3
  try {
    if (Platform.isWindows &&
        trimmed.length > 2 &&
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
      return trimmed;
    }
  } catch (_) {}

  return null;
}

class DacxApp extends StatefulWidget {
  final SettingsService settings;
  final DebugLogService debugLog;
  final String? initialFile;

  const DacxApp({
    super.key,
    required this.settings,
    required this.debugLog,
    this.initialFile,
  });

  @override
  State<DacxApp> createState() => _DacxAppState();
}

class _DacxAppState extends State<DacxApp>
    with WindowListener, WidgetsBindingObserver {
  bool _applyingWindowVisuals = false;
  bool _pendingWindowVisuals = false;
  Timer? _geometrySaveDebounce;

  bool _isEffectiveBlurEnabled(SettingsService settings) {
    if (!settings.experimentalFeaturesEnabled) return false;
    if (!settings.windowBlurEnabled) return false;
    if (Platform.isWindows || Platform.isMacOS) return true;
    if (Platform.isLinux) return settings.linuxCompositorBlurExperimental;
    return false;
  }

  @override
  void initState() {
    super.initState();
    widget.debugLog.logLazy(
      category: DebugLogCategory.system,
      event: 'app_init',
      detailsBuilder: () => {
        'platform': Platform.operatingSystem,
        'initial_file_present': widget.initialFile != null,
      },
    );
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    widget.settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_applyWindowVisualSettings());
      unawaited(_syncKeyboardState());
      Future<void>.delayed(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        unawaited(_applyWindowVisualSettings());
      });
    });
  }

  @override
  void dispose() {
    _geometrySaveDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    widget.debugLog.logLazy(
      category: DebugLogCategory.system,
      event: 'settings_changed_notification',
      detailsBuilder: () => {
        'theme_mode': widget.settings.themeMode.name,
        'always_on_top': widget.settings.alwaysOnTop,
        'experimental_features': widget.settings.experimentalFeaturesEnabled,
      },
    );
    setState(() {});
    unawaited(_applyWindowVisualSettings());
  }

  Future<void> _syncKeyboardState() async {
    try {
      await HardwareKeyboard.instance.syncKeyboardState();
    } catch (_) {}
  }

  @override
  void onWindowFocus() {
    unawaited(_syncKeyboardState());
    unawaited(_applyWindowVisualSettings());
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.settings.themeMode == ThemeMode.system) {
      setState(() {});
      unawaited(_applyWindowVisualSettings());
    }
  }

  bool _isDarkMode() {
    final mode = widget.settings.themeMode;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  Future<void> _applyWindowVisualSettings() async {
    if (!mounted) return;
    if (_applyingWindowVisuals) {
      _pendingWindowVisuals = true;
      return;
    }
    _applyingWindowVisuals = true;
    do {
      _pendingWindowVisuals = false;
      final s = widget.settings;
      final experimentalEnabled = s.experimentalFeaturesEnabled;
      final blurEnabled = _isEffectiveBlurEnabled(s);
      final bypassNativeOpacity = Platform.isWindows && blurEnabled;
      final effectiveOpacity = experimentalEnabled ? s.windowOpacity : 1.0;

      try {
        if (bypassNativeOpacity) {
          // window_manager.setOpacity enables WS_EX_LAYERED on Windows, which
          // can flatten/disable DWM blur materials.
          await windowManager.setIgnoreMouseEvents(false);
        } else {
          await windowManager.setOpacity(effectiveOpacity);
        }
      } catch (_) {}

      try {
        if (Platform.isMacOS) {
          try {
            await Window.setWindowBackgroundColorToClear();
            await Window.makeTitlebarTransparent();
            await Window.enableFullSizeContentView();
            await Window.hideTitle();
          } catch (_) {}
        }

        if (blurEnabled) {
          final strength = s.windowBlurStrength;
          if (Platform.isWindows) {
            final dark = _isDarkMode();
            if (strength < 0.12) {
              await Window.setEffect(
                effect: WindowEffect.disabled,
                color: Colors.transparent,
                dark: dark,
              );
            } else {
              final alpha = (220 - (strength * 120)).round().clamp(90, 220);
              await Window.setEffect(
                effect: WindowEffect.aero,
                color: dark
                    ? Color.fromARGB(alpha, 24, 30, 37)
                    : Color.fromARGB(alpha, 245, 248, 252),
                dark: dark,
              );
            }
          } else if (Platform.isMacOS) {
            final effect = switch (strength) {
              < 0.20 => WindowEffect.windowBackground,
              < 0.40 => WindowEffect.sidebar,
              < 0.60 => WindowEffect.hudWindow,
              _ => WindowEffect.fullScreenUI,
            };
            await Window.setEffect(effect: effect, dark: _isDarkMode());
          } else if (Platform.isLinux) {
            await Window.setEffect(
              effect: WindowEffect.transparent,
              color: Colors.transparent,
              dark: _isDarkMode(),
            );
          } else {
            await Window.setEffect(
              effect: WindowEffect.disabled,
              color: Colors.transparent,
              dark: _isDarkMode(),
            );
          }
        } else {
          await Window.setEffect(
            effect: WindowEffect.disabled,
            color: Colors.transparent,
            dark: _isDarkMode(),
          );
        }
      } catch (_) {}
      if (widget.debugLog.isEnabled) {
        widget.debugLog.logLazy(
          category: DebugLogCategory.system,
          event: 'window_visuals_applied',
          detailsBuilder: () => {
            'experimental_enabled': experimentalEnabled,
            'blur_enabled': blurEnabled,
            'bypass_native_opacity': bypassNativeOpacity,
            'effective_opacity': effectiveOpacity.toStringAsFixed(3),
            'blur_strength': s.windowBlurStrength.toStringAsFixed(3),
          },
        );
      }
    } while (_pendingWindowVisuals && mounted);
    _applyingWindowVisuals = false;
  }

  // ── WindowListener ───────────────────────────────────────

  @override
  void onWindowResize() => _scheduleGeometrySave();

  @override
  void onWindowResized() => _scheduleGeometrySave();

  @override
  void onWindowMove() => _scheduleGeometrySave();

  @override
  void onWindowMoved() => _scheduleGeometrySave();

  void _scheduleGeometrySave() {
    _geometrySaveDebounce?.cancel();
    _geometrySaveDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_saveGeometry());
    });
  }

  Future<void> _saveGeometry() async {
    if (!widget.settings.rememberWindow) return;
    final size = await windowManager.getSize();
    final pos = await windowManager.getPosition();
    widget.settings.saveWindowSize(size);
    widget.settings.saveWindowPosition(pos);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final experimentalEnabled = s.experimentalFeaturesEnabled;
    final blurEnabled = _isEffectiveBlurEnabled(s);
    final uiOpacityValue = experimentalEnabled ? s.windowOpacity : 1.0;
    final opacitySliderT = ((uiOpacityValue - 0.65) / 0.35).clamp(0.0, 1.0);
    final windowsBlurUiOpacity = (Platform.isWindows && blurEnabled)
        ? lerpDouble(0.05, 1.0, Curves.easeOut.transform(opacitySliderT))!
        : 1.0;
    final popupAlpha = blurEnabled
        ? (Platform.isWindows ? windowsBlurUiOpacity : 0.96)
        : 1.0;
    final seed = s.accentColor.color;
    final lightScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    final lightVisuals = WindowVisuals.fromScheme(
      lightScheme,
      blurEnabled: blurEnabled,
      blurStrength: s.windowBlurStrength,
      uiOpacity: windowsBlurUiOpacity,
    );
    final darkVisuals = WindowVisuals.fromScheme(
      darkScheme,
      blurEnabled: blurEnabled,
      blurStrength: s.windowBlurStrength,
      uiOpacity: windowsBlurUiOpacity,
    );

    return MaterialApp(
      title: 'Dacx',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _NoBounceScrollBehavior(),
      themeMode: s.themeMode,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: blurEnabled
            ? Colors.transparent
            : lightVisuals.windowBottomColor,
        canvasColor: lightVisuals.contentColor,
        dividerColor: lightVisuals.dividerColor,
        popupMenuTheme: PopupMenuThemeData(
          color: lightVisuals.contentColor.withValues(alpha: popupAlpha),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: lightVisuals.borderColor),
          ),
        ),
        extensions: [lightVisuals],
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: blurEnabled
            ? Colors.transparent
            : darkVisuals.windowBottomColor,
        canvasColor: darkVisuals.contentColor,
        dividerColor: darkVisuals.dividerColor,
        popupMenuTheme: PopupMenuThemeData(
          color: darkVisuals.contentColor.withValues(alpha: popupAlpha),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: darkVisuals.borderColor),
          ),
        ),
        extensions: [darkVisuals],
      ),
      home: PlayerScreen(
        settings: s,
        debugLog: widget.debugLog,
        initialFile: widget.initialFile,
      ),
    );
  }
}
