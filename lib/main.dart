import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'debug_agent_log.dart';
import 'screens/player_screen.dart';
import 'services/debug_log_service.dart';
import 'services/hardware_acceleration_service.dart';
import 'services/instance_mode_service.dart';
import 'services/settings_service.dart';
import 'services/shared_preferences_bootstrap.dart';
import 'theme/window_visuals.dart';

const _safeStartupArg = '--safe-startup';

class _NoBounceScrollBehavior extends MaterialScrollBehavior {
  const _NoBounceScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

void _installAgentFlutterErrorHook() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    // #region agent log
    agentDebugNdjson(
      location: 'main.dart:flutter_error',
      message: 'framework_error',
      hypothesisId: 'H2',
      data: {'exception': details.exceptionAsString()},
    );
    // #endregion
    previousOnError?.call(details);
  };
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

void _installAsyncErrorHandler(DebugLogService debugLog) {
  PlatformDispatcher.instance.onError = (error, stack) {
    // #region agent log
    agentDebugNdjson(
      location: 'main.dart:async_error',
      message: 'uncaught_async_error',
      hypothesisId: 'H2',
      data: {
        'error': error.toString(),
        'stack_present': stack.toString().isNotEmpty,
      },
    );
    // #endregion
    debugLog.log(
      category: DebugLogCategory.error,
      event: 'uncaught_async_error',
      message: error.toString(),
      severity: DebugSeverity.error,
    );
    return true;
  };
}

void main(List<String> args) {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    _dacxMainAsync(args).then((_) {}, onError: fatalStartupCapture);
  }, fatalStartupCapture);
}

Future<void> _dacxMainAsync(List<String> args) async {
  // #region agent log
  agentDebugNdjson(
    location: 'main.dart:main',
    message: 'binding_ready',
    hypothesisId: 'H3',
    data: {
      'arg_count': args.length,
      'safe_startup_arg': args.contains(_safeStartupArg),
      'os': Platform.operatingSystem,
    },
  );
  // #endregion
  final startupSafeMode = args.contains(_safeStartupArg);
  _installKeyboardStateRecovery();
  _installAgentFlutterErrorHook();
  MediaKit.ensureInitialized();
  // #region agent log
  agentDebugNdjson(
    location: 'main.dart:main',
    message: 'media_kit_ready',
    hypothesisId: 'H3',
    data: const {},
  );
  // #endregion
  try {
    await Window.initialize();
    // #region agent log
    agentDebugNdjson(
      location: 'main.dart:main',
      message: 'flutter_acrylic_init_ok',
      hypothesisId: 'H3',
      data: const {},
    );
    // #endregion
  } catch (e) {
    debugPrint('Dacx: Window.initialize failed: $e');
    // #region agent log
    agentDebugNdjson(
      location: 'main.dart:main',
      message: 'flutter_acrylic_init_failed',
      hypothesisId: 'H3',
      data: {'error': e.toString()},
    );
    // #endregion
  }

  if (Platform.isWindows) {
    await dacxRepairSharedPreferencesFileBestEffort();
  }

  // #region agent log
  agentDebugNdjson(
    location: 'main.dart:main',
    message: 'prefs_get_instance_start',
    hypothesisId: 'H3',
    data: const {},
  );
  // #endregion
  final prefs = await SharedPreferences.getInstance();
  // #region agent log
  agentDebugNdjson(
    location: 'main.dart:main',
    message: 'prefs_ready',
    hypothesisId: 'H3',
    data: const {},
  );
  // #endregion
  final settings = SettingsService(prefs);
  unawaited(settings.syncInstanceModeFlag());
  final debugLog = DebugLogService(isEnabled: () => settings.debugModeEnabled);
  _installAsyncErrorHandler(debugLog);
  // Prime macOS hardware-acceleration probes off the UI isolate so the first
  // frame is not blocked by sysctl + system_profiler subprocesses. No-op
  // elsewhere.
  unawaited(HardwareAccelerationService.prime());

  try {
    await windowManager.ensureInitialized();
    // #region agent log
    agentDebugNdjson(
      location: 'main.dart:main',
      message: 'window_manager_ready',
      hypothesisId: 'H3',
      data: const {},
    );
    // #endregion
  } catch (e) {
    debugPrint('Dacx: windowManager.ensureInitialized failed: $e');
    // #region agent log
    agentDebugNdjson(
      location: 'main.dart:main',
      message: 'window_manager_failed',
      hypothesisId: 'H3',
      data: {'error': e.toString()},
    );
    // #endregion
  }

  // Restore saved window geometry or use defaults.
  final savedSize = settings.rememberWindow ? settings.windowSize : null;
  final savedPos = settings.rememberWindow ? settings.windowPosition : null;

  final windowOptions = WindowOptions(
    size: savedSize ?? const Size(960, 600),
    minimumSize: const Size(480, 320),
    center: savedPos == null,
    title: 'Dacx',
    backgroundColor: Colors.transparent,
    titleBarStyle: !startupSafeMode && (Platform.isWindows || Platform.isMacOS)
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
  );

  final windowReady = Completer<void>();
  final firstFrameReady = Completer<void>();
  var windowShown = false;

  Future<void> applyHiddenTitleBarBestEffort() async {
    if (startupSafeMode) return;
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    } catch (e) {
      debugPrint('Dacx: setTitleBarStyle failed: $e');
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
  }

  unawaited(
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      try {
        if (savedPos != null) {
          await windowManager.setPosition(savedPos);
        }
        await windowManager.setAlwaysOnTop(settings.alwaysOnTop);
        await applyHiddenTitleBarBestEffort();
      } catch (e) {
        debugPrint('Dacx: startup window operations failed: $e');
      } finally {
        if (!windowReady.isCompleted) {
          windowReady.complete();
        }
      }
      await showWindowIfReady();
    }),
  );
  final cliFile = _parseCliFilePath(args);

  // #region agent log
  agentDebugNdjson(
    location: 'main.dart:main',
    message: 'run_app',
    hypothesisId: 'H3',
    data: {
      'remember_window': settings.rememberWindow,
      'cli_file': cliFile != null,
    },
  );
  // #endregion

  runApp(
    DacxApp(
      settings: settings,
      debugLog: debugLog,
      initialFile: cliFile,
      startupSafeMode: startupSafeMode,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!firstFrameReady.isCompleted) {
      firstFrameReady.complete();
    }
    await showWindowIfReady();
  });

  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 600), () async {
      if (windowShown) return;
      if (!windowReady.isCompleted) {
        windowReady.complete();
      }
      if (!firstFrameReady.isCompleted) {
        firstFrameReady.complete();
      }
      await showWindowIfReady();
    }),
  );
}

/// Extracts the first CLI argument that looks like a file path.
String? _parseCliFilePath(List<String> args) {
  for (final rawArg in args) {
    if (rawArg.trim().isEmpty || rawArg.startsWith('-')) continue;
    if (rawArg == InstanceModeService.newInstanceFlag) continue;
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
    } catch (e) {
      debugPrint('Dacx: parseCliFilePath toFilePath failed: $e');
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
  } catch (e) {
    debugPrint('Dacx: parseCliFilePath windows regex failed: $e');
  }

  return null;
}

class DacxApp extends StatefulWidget {
  final SettingsService settings;
  final DebugLogService debugLog;
  final String? initialFile;
  final bool startupSafeMode;

  const DacxApp({
    super.key,
    required this.settings,
    required this.debugLog,
    this.initialFile,
    required this.startupSafeMode,
  });

  @override
  State<DacxApp> createState() => _DacxAppState();
}

class _DacxAppState extends State<DacxApp>
    with WindowListener, WidgetsBindingObserver {
  bool _applyingWindowVisuals = false;
  bool _pendingWindowVisuals = false;
  Timer? _geometrySaveDebounce;
  _ThemeBundle? _cachedThemes;
  _ThemeInputs? _cachedThemeInputs;

  bool _isEffectiveBlurEnabled(SettingsService settings) {
    if (widget.startupSafeMode) return false;
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
        'startup_safe_mode': widget.startupSafeMode,
      },
    );
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    widget.settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_applyWindowVisualSettings());
      unawaited(_syncKeyboardState());
    });
  }

  @override
  void dispose() {
    _geometrySaveDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    widget.settings.removeListener(_onSettingsChanged);
    widget.settings.dispose();
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
    } catch (e) {
      debugPrint('Dacx: syncKeyboardState failed: $e');
    }
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
      } catch (e) {
        debugPrint('Dacx: window opacity apply failed: $e');
      }

      try {
        if (Platform.isMacOS) {
          try {
            await Window.setWindowBackgroundColorToClear();
            await Window.makeTitlebarTransparent();
            await Window.enableFullSizeContentView();
            await Window.hideTitle();
          } catch (e) {
            debugPrint('Dacx: macOS titlebar visuals apply failed: $e');
          }
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
      } catch (e) {
        debugPrint('Dacx: window blur effect apply failed: $e');
        // #region agent log
        if (Platform.isWindows) {
          agentDebugNdjson(
            location: 'main.dart:_applyWindowVisualSettings',
            message: 'window_blur_apply_failed',
            hypothesisId: 'H4',
            data: {'error': e.toString()},
          );
        }
        // #endregion
      }
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
    final inputs = _ThemeInputs(
      seed: s.accentColor.color,
      blurEnabled: blurEnabled,
      blurStrength: s.windowBlurStrength,
      windowsBlurUiOpacity: windowsBlurUiOpacity,
      popupAlpha: popupAlpha,
    );
    final themes = _cachedThemeInputs == inputs && _cachedThemes != null
        ? _cachedThemes!
        : (_cachedThemes = _buildThemes(inputs));
    _cachedThemeInputs = inputs;

    return MaterialApp(
      title: 'Dacx',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior: const _NoBounceScrollBehavior(),
      themeMode: s.themeMode,
      theme: themes.light,
      darkTheme: themes.dark,
      home: PlayerScreen(
        settings: s,
        debugLog: widget.debugLog,
        initialFile: widget.initialFile,
        startupSafeMode: widget.startupSafeMode,
      ),
    );
  }

  _ThemeBundle _buildThemes(_ThemeInputs inputs) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: inputs.seed,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: inputs.seed,
      brightness: Brightness.dark,
    );
    final lightVisuals = WindowVisuals.fromScheme(
      lightScheme,
      blurEnabled: inputs.blurEnabled,
      blurStrength: inputs.blurStrength,
      uiOpacity: inputs.windowsBlurUiOpacity,
    );
    final darkVisuals = WindowVisuals.fromScheme(
      darkScheme,
      blurEnabled: inputs.blurEnabled,
      blurStrength: inputs.blurStrength,
      uiOpacity: inputs.windowsBlurUiOpacity,
    );
    return _ThemeBundle(
      light: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: inputs.blurEnabled
            ? Colors.transparent
            : lightVisuals.windowBottomColor,
        canvasColor: lightVisuals.contentColor,
        dividerColor: lightVisuals.dividerColor,
        popupMenuTheme: PopupMenuThemeData(
          color: lightVisuals.contentColor.withValues(alpha: inputs.popupAlpha),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: lightVisuals.borderColor),
          ),
        ),
        extensions: [lightVisuals],
      ),
      dark: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: inputs.blurEnabled
            ? Colors.transparent
            : darkVisuals.windowBottomColor,
        canvasColor: darkVisuals.contentColor,
        dividerColor: darkVisuals.dividerColor,
        popupMenuTheme: PopupMenuThemeData(
          color: darkVisuals.contentColor.withValues(alpha: inputs.popupAlpha),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: darkVisuals.borderColor),
          ),
        ),
        extensions: [darkVisuals],
      ),
    );
  }
}

class _ThemeInputs {
  final Color seed;
  final bool blurEnabled;
  final double blurStrength;
  final double windowsBlurUiOpacity;
  final double popupAlpha;

  const _ThemeInputs({
    required this.seed,
    required this.blurEnabled,
    required this.blurStrength,
    required this.windowsBlurUiOpacity,
    required this.popupAlpha,
  });

  @override
  bool operator ==(Object other) =>
      other is _ThemeInputs &&
      other.seed.toARGB32() == seed.toARGB32() &&
      other.blurEnabled == blurEnabled &&
      other.blurStrength == blurStrength &&
      other.windowsBlurUiOpacity == windowsBlurUiOpacity &&
      other.popupAlpha == popupAlpha;

  @override
  int get hashCode => Object.hash(
    seed.toARGB32(),
    blurEnabled,
    blurStrength,
    windowsBlurUiOpacity,
    popupAlpha,
  );
}

class _ThemeBundle {
  final ThemeData light;
  final ThemeData dark;

  const _ThemeBundle({required this.light, required this.dark});
}
