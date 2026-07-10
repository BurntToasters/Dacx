import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'screens/player_screen.dart';
import 'services/debug_log_service.dart';
import 'services/hardware_acceleration_service.dart';
import 'services/instance_mode_service.dart';
import 'services/macos_install_location_service.dart';
import 'services/settings_service.dart';
import 'services/trusted_http.dart';
import 'services/update_service.dart';
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

void _installAsyncErrorHandler(DebugLogService debugLog) {
  PlatformDispatcher.instance.onError = (error, stack) {
    debugLog.log(
      category: DebugLogCategory.error,
      event: 'uncaught_async_error',
      message: error.toString(),
      severity: DebugSeverity.error,
    );
    // Let the platform fallback path still report the failure in production
    // even when debug logging is disabled.
    return false;
  };
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _installKeyboardStateRecovery();
  MediaKit.ensureInitialized();
  await Window.initialize();

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  unawaited(settings.syncInstanceModeFlag());
  final debugLog = DebugLogService(isEnabled: () => settings.debugModeEnabled);
  _installAsyncErrorHandler(debugLog);
  // Prime macOS hardware-acceleration probes off the UI isolate so the first
  // frame is not blocked by sysctl + system_profiler subprocesses. No-op
  // elsewhere.
  unawaited(HardwareAccelerationService.prime());
  if (Platform.isWindows) {
    unawaited(primeWindowsTlsTrust());
  }

  await windowManager.ensureInitialized();

  // Restore saved window geometry or use defaults.
  final savedSize = settings.rememberWindow ? settings.windowSize : null;
  var savedPos = settings.rememberWindow ? settings.windowPosition : null;

  if (savedPos != null) {
    final effectiveSize = savedSize ?? const Size(960, 600);
    if (!_isPositionOnScreen(savedPos, effectiveSize)) {
      savedPos = null;
    }
  }

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

  Future<void> applyHiddenTitleBarBestEffort() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: setTitleBarStyle failed: $e');
      }
    }
  }

  Future<void> nudgeWindowSurface() async {
    if (!Platform.isWindows) return;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final size = await windowManager.getSize();
      await windowManager.setSize(Size(size.width + 1, size.height + 1));
      await windowManager.setSize(size);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: window surface nudge failed: $e');
      }
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
    await nudgeWindowSurface();
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
        if (kDebugMode) {
          debugPrint('Dacx: startup window operations failed: $e');
        }
      } finally {
        if (!windowReady.isCompleted) {
          windowReady.complete();
        }
      }
      await showWindowIfReady();
    }),
  );
  final cliFile = _parseCliFilePath(args);
  final updateService = UpdateService(debugLog: debugLog, debugSource: 'app');

  runApp(
    DacxApp(
      settings: settings,
      debugLog: debugLog,
      updateService: updateService,
      initialFile: cliFile,
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

bool _isPositionOnScreen(Offset pos, Size windowSize) {
  // The Flutter 3.44 Display API exposes each display's size but not its
  // origin, so an exact multi-monitor bounds check is impossible here. Use the
  // summed logical extent of all connected displays as a generous upper bound.
  // Empty display list (info not yet available) means "don't reset" so we never
  // regress a valid position. This catches the common failure mode: a position
  // saved on a monitor that has since been disconnected, leaving the window
  // far beyond the remaining desktop extent.
  final displays = PlatformDispatcher.instance.displays;
  if (displays.isEmpty) return true;
  var totalW = 0.0;
  var totalH = 0.0;
  for (final d in displays) {
    final dpr = d.devicePixelRatio <= 0 ? 1.0 : d.devicePixelRatio;
    totalW += d.size.width / dpr;
    totalH += d.size.height / dpr;
  }
  if (totalW <= 0 || totalH <= 0) return true;
  const margin = 80.0;
  final left = pos.dx;
  final top = pos.dy;
  final right = pos.dx + windowSize.width;
  final bottom = pos.dy + windowSize.height;
  final withinX = right > (-totalW + margin) && left < (totalW - margin);
  final withinY = bottom > (-totalH + margin) && top < (totalH - margin);
  return withinX && withinY;
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
      if (kDebugMode) {
        debugPrint('Dacx: parseCliFilePath toFilePath failed: $e');
      }
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
    if (kDebugMode) {
      debugPrint('Dacx: parseCliFilePath windows regex failed: $e');
    }
  }

  return null;
}

class DacxApp extends StatefulWidget {
  final SettingsService settings;
  final DebugLogService debugLog;
  final UpdateService updateService;
  final String? initialFile;

  const DacxApp({
    super.key,
    required this.settings,
    required this.debugLog,
    required this.updateService,
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
  _ThemeBundle? _cachedThemes;
  _ThemeInputs? _cachedThemeInputs;

  bool _isEffectiveBlurEnabled(SettingsService settings) {
    if (!settings.experimentalFeaturesEnabled) return false;
    if (!settings.windowBlurEnabled) return false;
    if (Platform.isWindows || Platform.isMacOS) return true;
    if (Platform.isLinux) return settings.linuxCompositorBlurExperimental;
    return false;
  }

  bool _shouldBypassNativeOpacity(bool blurEnabled) {
    if (!blurEnabled) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static const MethodChannel _windowVisualsChannel = MethodChannel(
    'run.rosie.dacx/window/methods',
  );

  Future<void> _clearWindowsLayeredStyle() async {
    if (!Platform.isWindows) return;
    try {
      await _windowVisualsChannel.invokeMethod<bool>('clearLayeredStyle');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: clearLayeredStyle failed: $e');
      }
    }
  }

  /// macOS vibrancy: await material set (flutter_acrylic's setEffect does not),
  /// force alpha=1, active blur state, and appearance so NSVisualEffectView
  /// actually composites the desktop behind the window.
  Future<void> _applyMacOSBlur({required double strength}) async {
    final dark = _isDarkMode();
    // Prefer materials that blur desktop content (research: windowBackground
    // is mostly opaque wallpaper-tint and reads as "no blur").
    final material = switch (strength) {
      < 0.25 => NSVisualEffectViewMaterial.underWindowBackground,
      < 0.50 => NSVisualEffectViewMaterial.hudWindow,
      < 0.75 => NSVisualEffectViewMaterial.sidebar,
      _ => NSVisualEffectViewMaterial.fullScreenUI,
    };
    try {
      // Ensure window alpha is fully opaque — alpha < 1 fades the whole
      // window including the vibrancy layer into sharp transparency.
      await WindowManipulator.setWindowAlphaValue(1.0);
      await WindowManipulator.setWindowBackgroundColorToClear();
      await WindowManipulator.makeTitlebarTransparent();
      await WindowManipulator.enableFullSizeContentView();
      await WindowManipulator.hideTitle();
      await WindowManipulator.setMaterial(material);
      await WindowManipulator.setNSVisualEffectViewState(
        NSVisualEffectViewState.active,
      );
      await WindowManipulator.overrideMacOSBrightness(dark: dark);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: macOS blur apply failed: $e');
      }
      // Fallback through flutter_acrylic in case direct manipulator failed.
      try {
        final effect = switch (strength) {
          < 0.25 => WindowEffect.underWindowBackground,
          < 0.50 => WindowEffect.hudWindow,
          < 0.75 => WindowEffect.sidebar,
          _ => WindowEffect.fullScreenUI,
        };
        await Window.setEffect(effect: effect, dark: dark);
        await Window.setBlurViewState(MacOSBlurViewState.active);
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('Dacx: macOS blur fallback failed: $e2');
        }
      }
    }
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
    unawaited(_applyWindowVisualSettings());
  }

  Future<void> _syncKeyboardState() async {
    try {
      await HardwareKeyboard.instance.syncKeyboardState();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: syncKeyboardState failed: $e');
      }
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
      final bypassNativeOpacity = _shouldBypassNativeOpacity(blurEnabled);
      final effectiveOpacity = experimentalEnabled ? s.windowOpacity : 1.0;

      try {
        if (bypassNativeOpacity) {
          // window_manager.setOpacity enables WS_EX_LAYERED on Windows and alters
          // alphaValue on macOS / gtk opacity on Linux — all of which flatten or
          // fight native blur/vibrancy/compositor blur.
          if (Platform.isWindows) {
            await _clearWindowsLayeredStyle();
          } else {
            // Reset any prior opacity fade so the transparent/blur path is clean.
            await windowManager.setOpacity(1.0);
          }
          await windowManager.setIgnoreMouseEvents(false);
        } else {
          await windowManager.setOpacity(effectiveOpacity);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: window opacity apply failed: $e');
        }
      }

      try {
        if (Platform.isMacOS) {
          try {
            await Window.setWindowBackgroundColorToClear();
            await Window.makeTitlebarTransparent();
            await Window.enableFullSizeContentView();
            await Window.hideTitle();
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Dacx: macOS titlebar visuals apply failed: $e');
            }
          }
        }

        if (blurEnabled) {
          final strength = s.windowBlurStrength;
          if (Platform.isWindows) {
            final dark = _isDarkMode();
            // Ensure layered style is gone immediately before DWM effect apply.
            await _clearWindowsLayeredStyle();
            if (strength < 0.12) {
              await Window.setEffect(
                effect: WindowEffect.disabled,
                color: Colors.transparent,
                dark: dark,
              );
            } else {
              // Tint alpha: stronger glass → more see-through acrylic tint.
              final alpha = (200 - (strength * 110)).round().clamp(70, 200);
              // Prefer acrylic (true blur-behind). On Win11 22523+ the plugin
              // maps this to DWMSBT_TRANSIENTWINDOW; older builds use
              // ACCENT_ENABLE_ACRYLICBLURBEHIND.
              await Window.setEffect(
                effect: WindowEffect.acrylic,
                color: dark
                    ? Color.fromARGB(alpha, 24, 30, 37)
                    : Color.fromARGB(alpha, 245, 248, 252),
                dark: dark,
              );
            }
            // Size nudge forces DWM to recomposite after style/effect change.
            try {
              final size = await windowManager.getSize();
              await windowManager.setSize(Size(size.width + 1, size.height));
              await windowManager.setSize(size);
            } catch (_) {}
          } else if (Platform.isMacOS) {
            await _applyMacOSBlur(strength: strength);
          } else if (Platform.isLinux) {
            // Linux has no GTK blur API — only transparency. Compositor
            // (KWin forceblur, etc.) blurs the transparent regions.
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
        if (kDebugMode) {
          debugPrint('Dacx: window blur effect apply failed: $e');
        }
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
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final s = widget.settings;
        final experimentalEnabled = s.experimentalFeaturesEnabled;
        final blurEnabled = _isEffectiveBlurEnabled(s);
        final uiOpacityValue = experimentalEnabled ? s.windowOpacity : 1.0;
        const opacityMin = SettingsService.windowOpacityMin;
        final opacitySliderT =
            ((uiOpacityValue - opacityMin) / (1.0 - opacityMin)).clamp(
              0.0,
              1.0,
            );
        // Opacity slider → Flutter shell tint strength (native window opacity
        // stays at 1.0 so acrylic/vibrancy can composite). Floor at ~0.22 so
        // chrome stays readable over the blur.
        final blurUiOpacity =
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
                blurEnabled
            ? lerpDouble(0.22, 0.82, Curves.easeOut.transform(opacitySliderT))!
            : 1.0;
        final popupAlpha = blurEnabled
            ? ((Platform.isWindows || Platform.isMacOS || Platform.isLinux)
                  ? (blurUiOpacity + 0.12).clamp(0.0, 1.0)
                  : 0.96)
            : 1.0;
        final inputs = _ThemeInputs(
          seed: s.accentColor.color,
          blurEnabled: blurEnabled,
          blurStrength: s.windowBlurStrength,
          blurUiOpacity: blurUiOpacity,
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
          // Critical for macOS/Windows/Linux blur: Flutter's Metal/OpenGL
          // surface starts opaque. Without BlendMode.clear, semi-transparent
          // widgets composite onto that opaque buffer (looks solid dark) and
          // never reveal the NSVisualEffectView / acrylic behind.
          // Pattern from macos_window_utils official example.
          builder: (context, child) {
            Widget content = _MacInstallLocationWarning(
              debugLog: widget.debugLog,
              child: child ?? const SizedBox.shrink(),
            );
            if (blurEnabled) {
              content = DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF000000),
                  backgroundBlendMode: BlendMode.clear,
                ),
                child: content,
              );
            }
            return content;
          },
          home: PlayerScreen(
            settings: s,
            debugLog: widget.debugLog,
            updateService: widget.updateService,
            initialFile: widget.initialFile,
          ),
        );
      },
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
      uiOpacity: inputs.blurUiOpacity,
    );
    final darkVisuals = WindowVisuals.fromScheme(
      darkScheme,
      blurEnabled: inputs.blurEnabled,
      blurStrength: inputs.blurStrength,
      uiOpacity: inputs.blurUiOpacity,
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
          color: lightVisuals.panelTopColor.withValues(
            alpha: inputs.popupAlpha,
          ),
          surfaceTintColor: Colors.transparent,
          elevation: inputs.blurEnabled
              ? (4.0 * (1.0 - inputs.blurStrength)).clamp(1.0, 4.0)
              : 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: lightVisuals.panelBorderColor),
          ),
        ),
        cardTheme: inputs.blurEnabled
            ? CardThemeData(
                color: lightVisuals.panelTopColor.withValues(alpha: 0.92),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: lightVisuals.panelBorderColor),
                ),
              )
            : null,
        snackBarTheme: const SnackBarThemeData(showCloseIcon: true),
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
          color: darkVisuals.panelTopColor.withValues(alpha: inputs.popupAlpha),
          surfaceTintColor: Colors.transparent,
          elevation: inputs.blurEnabled
              ? (4.0 * (1.0 - inputs.blurStrength)).clamp(1.0, 4.0)
              : 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: darkVisuals.panelBorderColor),
          ),
        ),
        cardTheme: inputs.blurEnabled
            ? CardThemeData(
                color: darkVisuals.panelTopColor.withValues(alpha: 0.92),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: darkVisuals.panelBorderColor),
                ),
              )
            : null,
        snackBarTheme: const SnackBarThemeData(showCloseIcon: true),
        extensions: [darkVisuals],
      ),
    );
  }
}

class _MacInstallLocationWarning extends StatefulWidget {
  final DebugLogService debugLog;
  final Widget child;

  const _MacInstallLocationWarning({
    required this.debugLog,
    required this.child,
  });

  @override
  State<_MacInstallLocationWarning> createState() =>
      _MacInstallLocationWarningState();
}

class _MacInstallLocationWarningState
    extends State<_MacInstallLocationWarning> {
  bool _scheduled = false;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showIfNeeded());
    });
  }

  Future<void> _showIfNeeded() async {
    if (!mounted || _shown) return;
    if (!MacosInstallLocationService.shouldWarnForCurrentApp()) return;
    _shown = true;
    widget.debugLog.log(
      category: DebugLogCategory.update,
      event: 'macos_install_location_warning',
      message: 'Dacx is running outside /Applications.',
      severity: DebugSeverity.warn,
    );
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dialogMacInstallLocationTitle),
        content: Text(l10n.dialogMacInstallLocationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ThemeInputs {
  final Color seed;
  final bool blurEnabled;
  final double blurStrength;
  final double blurUiOpacity;
  final double popupAlpha;

  const _ThemeInputs({
    required this.seed,
    required this.blurEnabled,
    required this.blurStrength,
    required this.blurUiOpacity,
    required this.popupAlpha,
  });

  @override
  bool operator ==(Object other) =>
      other is _ThemeInputs &&
      other.seed.toARGB32() == seed.toARGB32() &&
      other.blurEnabled == blurEnabled &&
      other.blurStrength == blurStrength &&
      other.blurUiOpacity == blurUiOpacity &&
      other.popupAlpha == popupAlpha;

  @override
  int get hashCode => Object.hash(
    seed.toARGB32(),
    blurEnabled,
    blurStrength,
    blurUiOpacity,
    popupAlpha,
  );
}

class _ThemeBundle {
  final ThemeData light;
  final ThemeData dark;

  const _ThemeBundle({required this.light, required this.dark});
}
