import 'dart:io';
import 'dart:ui';

import 'package:dacx/app/window_startup.dart';
import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/main.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/audit9_report.dart';

class _Native {
  final List<MethodCall> windowManagerCalls = [];
  final List<MethodCall> acrylicCalls = [];
  final List<MethodCall> windowMethodCalls = [];
  bool maximized = false;
  bool minimized = false;
  bool fullscreen = false;
  Size size = const Size(1000, 700);
  Offset position = const Offset(40, 50);

  static const _windowManager = MethodChannel('window_manager');
  static const _acrylic = MethodChannel('com.alexmercerind/flutter_acrylic');
  static const _windowMethods = MethodChannel('run.rosie.dacx/window/methods');

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(_windowManager, (call) async {
      windowManagerCalls.add(call);
      switch (call.method) {
        case 'isMaximized':
          return maximized;
        case 'isMinimized':
          return minimized;
        case 'isFullScreen':
          return fullscreen;
        case 'isVisible':
          return true;
        case 'maximize':
          maximized = true;
          return null;
        case 'getBounds':
          return {
            'x': position.dx,
            'y': position.dy,
            'width': size.width,
            'height': size.height,
          };
        case 'setBounds':
          final args = call.arguments as Map<Object?, Object?>;
          final width = args['width'];
          final height = args['height'];
          final x = args['x'];
          final y = args['y'];
          if (width is num && height is num) {
            size = Size(width.toDouble(), height.toDouble());
          }
          if (x is num && y is num) {
            position = Offset(x.toDouble(), y.toDouble());
          }
          return null;
        default:
          return null;
      }
    });
    _messenger.setMockMethodCallHandler(_acrylic, (call) async {
      acrylicCalls.add(call);
      return null;
    });
    _messenger.setMockMethodCallHandler(_windowMethods, (call) async {
      windowMethodCalls.add(call);
      return true;
    });
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(_windowManager, null);
    _messenger.setMockMethodCallHandler(_acrylic, null);
    _messenger.setMockMethodCallHandler(_windowMethods, null);
  }

  void clearCalls() {
    windowManagerCalls.clear();
    acrylicCalls.clear();
    windowMethodCalls.clear();
  }

  List<MethodCall> get setBoundsCalls =>
      windowManagerCalls.where((c) => c.method == 'setBounds').toList();

  List<MethodCall> get effectCalls =>
      acrylicCalls.where((c) => c.method == 'SetEffect').toList();

  List<MethodCall> get opacityCalls =>
      windowManagerCalls.where((c) => c.method == 'setOpacity').toList();

  List<String> get windowManagerMethods =>
      windowManagerCalls.map((c) => c.method).toList();

  Future<void> emit(String eventName) async {
    await _messenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onEvent', {'eventName': eventName}),
      ),
      (_) {},
    );
  }
}

class _Shell {
  _Shell({
    required this.settings,
    required this.debugLog,
    required this.native,
  });

  final SettingsService settings;
  final DebugLogService debugLog;
  final _Native native;
  int materialBuilds = 0;
  int homeBuilds = 0;
}

bool get _blurEffectiveHere => Platform.isWindows || Platform.isMacOS;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
}

Future<_Shell> _pumpApp(
  WidgetTester tester,
  _Native native, {
  Map<String, Object> prefs = const {},
  bool Function()? shouldWarn,
  void Function(SettingsService settings)? configure,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final shared = await SharedPreferences.getInstance();
  final settings = SettingsService(shared);
  configure?.call(settings);
  final debugLog = DebugLogService(isEnabled: () => true);
  final updates = UpdateService(
    debugLog: debugLog,
    debugSource: 'shell_test',
    httpGet: (_, {headers}) async => throw Exception('offline'),
  );
  final shell = _Shell(settings: settings, debugLog: debugLog, native: native);
  await tester.pumpWidget(
    DacxApp(
      settings: settings,
      debugLog: debugLog,
      updateService: updates,
      shouldWarnForInstallLocation: shouldWarn ?? () => false,
      homeBuilder: (context, s) {
        shell.homeBuilds++;
        return const SizedBox.expand();
      },
      onMaterialAppBuild: () => shell.materialBuilds++,
    ),
  );
  await _settle(tester);
  return shell;
}

Future<void> _pumpAppDefaults(
  WidgetTester tester,
  _Native native, {
  required DebugLogService debugLog,
  required SettingsService settings,
}) async {
  await tester.pumpWidget(
    DacxApp(
      settings: settings,
      debugLog: debugLog,
      updateService: UpdateService(
        debugLog: debugLog,
        debugSource: 'shell_test',
        httpGet: (_, {headers}) async => throw Exception('offline'),
      ),
      homeBuilder: (context, s) => const SizedBox.expand(),
    ),
  );
  await _settle(tester);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

MaterialApp _materialApp(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

class _LegacyInputs {
  const _LegacyInputs({
    required this.seed,
    required this.blurEnabled,
    required this.blurStrength,
    required this.blurUiOpacity,
    required this.popupAlpha,
  });

  final Color seed;
  final bool blurEnabled;
  final double blurStrength;
  final double blurUiOpacity;
  final double popupAlpha;
}

_LegacyInputs _legacyInputs(SettingsService s, {required bool blurEnabled}) {
  const opacityMin = SettingsService.windowOpacityMin;
  final opacitySliderT = ((s.windowOpacity - opacityMin) / (1.0 - opacityMin))
      .clamp(0.0, 1.0);
  final blurUiOpacity = blurEnabled
      ? lerpDouble(0.22, 0.82, Curves.easeOut.transform(opacitySliderT))!
      : 1.0;
  final popupAlpha = blurEnabled ? (blurUiOpacity + 0.12).clamp(0.0, 1.0) : 1.0;
  return _LegacyInputs(
    seed: s.accentColor.color,
    blurEnabled: blurEnabled,
    blurStrength: s.windowBlurStrength,
    blurUiOpacity: blurUiOpacity,
    popupAlpha: popupAlpha,
  );
}

ThemeData _legacyLight(_LegacyInputs inputs) {
  final lightScheme = ColorScheme.fromSeed(
    seedColor: inputs.seed,
    brightness: Brightness.light,
  );
  final lightVisuals = WindowVisuals.fromScheme(
    lightScheme,
    blurEnabled: inputs.blurEnabled,
    blurStrength: inputs.blurStrength,
    uiOpacity: inputs.blurUiOpacity,
  );
  return ThemeData(
    colorScheme: lightScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: inputs.blurEnabled
        ? Colors.transparent
        : lightVisuals.windowBottomColor,
    canvasColor: lightVisuals.contentColor,
    dividerColor: lightVisuals.dividerColor,
    popupMenuTheme: PopupMenuThemeData(
      color: lightVisuals.panelTopColor.withValues(alpha: inputs.popupAlpha),
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
  );
}

ThemeData _legacyDark(_LegacyInputs inputs) {
  final darkScheme = ColorScheme.fromSeed(
    seedColor: inputs.seed,
    brightness: Brightness.dark,
  );
  final darkVisuals = WindowVisuals.fromScheme(
    darkScheme,
    blurEnabled: inputs.blurEnabled,
    blurStrength: inputs.blurStrength,
    uiOpacity: inputs.blurUiOpacity,
  );
  return ThemeData(
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
  );
}

void _expectVisualsEqual(WindowVisuals? actual, WindowVisuals expected) {
  expect(actual, isNotNull);
  final a = actual!;
  expect(a.blurEnabled, expected.blurEnabled);
  expect(a.blurStrength, expected.blurStrength);
  expect(a.windowTopColor, expected.windowTopColor);
  expect(a.windowBottomColor, expected.windowBottomColor);
  expect(a.chromeTopColor, expected.chromeTopColor);
  expect(a.chromeBottomColor, expected.chromeBottomColor);
  expect(a.panelTopColor, expected.panelTopColor);
  expect(a.panelBottomColor, expected.panelBottomColor);
  expect(a.panelBorderColor, expected.panelBorderColor);
  expect(a.rimHighlightColor, expected.rimHighlightColor);
  expect(a.overlayTopColor, expected.overlayTopColor);
  expect(a.overlayBottomColor, expected.overlayBottomColor);
  expect(a.dividerColor, expected.dividerColor);
  expect(a.shadowColor, expected.shadowColor);
  expect(a.dragOverlayColor, expected.dragOverlayColor);
}

void _expectThemeEquivalent(ThemeData actual, ThemeData expected) {
  expect(actual.brightness, expected.brightness);
  expect(actual.useMaterial3, expected.useMaterial3);
  expect(actual.colorScheme, expected.colorScheme);
  expect(actual.scaffoldBackgroundColor, expected.scaffoldBackgroundColor);
  expect(actual.canvasColor, expected.canvasColor);
  expect(actual.dividerColor, expected.dividerColor);
  expect(actual.popupMenuTheme, expected.popupMenuTheme);
  expect(actual.cardTheme, expected.cardTheme);
  expect(actual.snackBarTheme, expected.snackBarTheme);
  expect(actual.visualDensity, expected.visualDensity);
  expect(
    actual.copyWith(extensions: const <ThemeExtension<dynamic>>[]),
    equals(expected.copyWith(extensions: const <ThemeExtension<dynamic>>[])),
  );
  _expectVisualsEqual(
    actual.extension<WindowVisuals>(),
    expected.extension<WindowVisuals>()!,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'shell',
    expectedIds: [
      'M3.5',
      'M3.6',
      'M3.7',
      'M3.8',
      'M3.9',
      'M3.10',
      'M6.1',
      'M6.2',
      'M6.3',
      'M6.4',
      'M6.5',
      'M10.1',
      'M10.2',
      'M10.3',
      'M10.4',
      'M10.5',
      'M14.6',
      'M14.7',
      'M14.8',
      'M14.9',
      'M14.10',
      'M14.11',
      'M30.1',
      'M30.2',
      'M30.3',
    ],
  );

  final native = _Native();

  setUpAll(() async {
    native.install();
    await Window.initialize();
    native.uninstall();
  });

  setUp(() {
    native
      ..maximized = false
      ..minimized = false
      ..fullscreen = false
      ..size = const Size(1000, 700)
      ..position = const Offset(40, 50)
      ..clearCalls()
      ..install();
  });

  tearDown(native.uninstall);

  tearDownAll(report.write);

  group('Finding 3: geometry saved only for a normal window', () {
    const storedSize = Size(900, 600);
    const storedPos = Offset(10, 20);

    void seedNormal(SettingsService s) {
      s.saveWindowSize(storedSize);
      s.saveWindowPosition(storedPos);
    }

    Future<void> resizeEvent(WidgetTester tester) async {
      await native.emit('resize');
      await native.emit('move');
      await tester.pump(const Duration(milliseconds: 250));
      await _settle(tester);
    }

    testWidgets('M3.5 maximized window saves nothing and records the flag', (
      tester,
    ) async {
      final shell = await _pumpApp(tester, native, configure: seedNormal);
      native
        ..maximized = true
        ..size = const Size(1920, 1080)
        ..position = Offset.zero;
      await resizeEvent(tester);
      expect(shell.settings.windowSize, storedSize);
      expect(shell.settings.windowPosition, storedPos);
      expect(shell.settings.windowMaximized, isTrue);
      await _teardown(tester);
      report.pass('M3.5');
    });

    testWidgets('M3.6 fullscreen window saves nothing', (tester) async {
      final shell = await _pumpApp(
        tester,
        native,
        configure: (s) {
          seedNormal(s);
          s.windowMaximized = true;
        },
      );
      native
        ..fullscreen = true
        ..size = const Size(1920, 1080)
        ..position = Offset.zero;
      await resizeEvent(tester);
      expect(shell.settings.windowSize, storedSize);
      expect(shell.settings.windowPosition, storedPos);
      expect(shell.settings.windowMaximized, isTrue);
      await _teardown(tester);
      report.pass('M3.6');
    });

    testWidgets('M3.7 minimized window saves nothing', (tester) async {
      final shell = await _pumpApp(tester, native, configure: seedNormal);
      native
        ..minimized = true
        ..size = const Size(160, 28)
        ..position = const Offset(-32000, -32000);
      await resizeEvent(tester);
      expect(shell.settings.windowSize, storedSize);
      expect(shell.settings.windowPosition, storedPos);
      expect(shell.settings.windowMaximized, isFalse);
      await _teardown(tester);
      report.pass('M3.7');
    });

    testWidgets('M3.8 normal window saves bounds and clears the flag', (
      tester,
    ) async {
      final shell = await _pumpApp(
        tester,
        native,
        configure: (s) {
          seedNormal(s);
          s.windowMaximized = true;
        },
      );
      native
        ..size = const Size(1100, 750)
        ..position = const Offset(70, 80);
      await resizeEvent(tester);
      expect(shell.settings.windowSize, const Size(1100, 750));
      expect(shell.settings.windowPosition, const Offset(70, 80));
      expect(shell.settings.windowMaximized, isFalse);
      await _teardown(tester);
      report.pass('M3.8');
    });

    testWidgets('M3.9 remember window off saves nothing', (tester) async {
      final shell = await _pumpApp(
        tester,
        native,
        configure: (s) => s.rememberWindow = false,
      );
      native.maximized = true;
      await resizeEvent(tester);
      native
        ..maximized = false
        ..size = const Size(1100, 750);
      await resizeEvent(tester);
      expect(shell.settings.windowSize, isNull);
      expect(shell.settings.windowPosition, isNull);
      expect(shell.settings.windowMaximized, isFalse);
      await _teardown(tester);
      report.pass('M3.9');
    });

    testWidgets('M3.10 startup restores position then maximizes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      final settings = SettingsService(shared);
      settings.windowMaximized = true;

      native.clearCalls();
      await restoreWindowGeometry(settings, position: const Offset(30, 40));
      final methods = native.windowManagerMethods;
      expect(methods, contains('maximize'));
      expect(
        methods.indexOf('setBounds'),
        lessThan(methods.indexOf('maximize')),
      );

      native.clearCalls();
      settings.windowMaximized = false;
      await restoreWindowGeometry(settings, position: const Offset(30, 40));
      expect(native.windowManagerMethods, isNot(contains('maximize')));

      native.clearCalls();
      settings.windowMaximized = true;
      settings.rememberWindow = false;
      await restoreWindowGeometry(settings, position: null);
      expect(native.windowManagerMethods, isNot(contains('maximize')));
      report.pass('M3.10');
    });
  });

  group('Finding 6: install location dialog', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    int warningLogs(_Shell shell) => shell.debugLog.entries
        .where((e) => e.event == 'macos_install_location_warning')
        .length;

    testWidgets('M6.1 dialog is visible when the check says to warn', (
      tester,
    ) async {
      final shell = await _pumpApp(tester, native, shouldWarn: () => true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.dialogMacInstallLocationTitle), findsOneWidget);
      expect(find.text(l10n.dialogMacInstallLocationMessage), findsOneWidget);
      expect(shell.materialBuilds, greaterThan(0));
      await _teardown(tester);
      report.pass('M6.1');
    });

    testWidgets('M6.2 closes with Close and never shows twice', (tester) async {
      final shell = await _pumpApp(tester, native, shouldWarn: () => true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.dialogMacInstallLocationTitle), findsOneWidget);
      await tester.tap(find.text(l10n.actionClose));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.dialogMacInstallLocationTitle), findsNothing);
      shell.settings.themeMode = ThemeMode.light;
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(find.text(l10n.dialogMacInstallLocationTitle), findsNothing);
      await _teardown(tester);
      report.pass('M6.2');
    });

    testWidgets('M6.3 no dialog when the check says not to warn', (
      tester,
    ) async {
      final shell = await _pumpApp(tester, native, shouldWarn: () => false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.dialogMacInstallLocationTitle), findsNothing);
      expect(warningLogs(shell), 0);
      await _teardown(tester);
      report.pass('M6.3');
    });

    testWidgets('M6.4 logs the warning event once', (tester) async {
      final shell = await _pumpApp(tester, native, shouldWarn: () => true);
      await tester.pump(const Duration(milliseconds: 400));
      shell.settings.themeMode = ThemeMode.light;
      await tester.pump(const Duration(milliseconds: 400));
      expect(warningLogs(shell), 1);
      await _teardown(tester);
      report.pass('M6.4');
    });

    testWidgets('M6.5 production default shows nothing off macOS', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      final settings = SettingsService(shared);
      final debugLog = DebugLogService(isEnabled: () => true);
      await _pumpAppDefaults(
        tester,
        native,
        debugLog: debugLog,
        settings: settings,
      );
      await tester.pump(const Duration(milliseconds: 400));
      if (!Platform.isMacOS) {
        expect(find.text(l10n.dialogMacInstallLocationTitle), findsNothing);
      }
      await _teardown(tester);
      report.pass('M6.5');
    });
  });

  group('Finding 10: focus does not nudge the window', () {
    void enableBlur(SettingsService s) {
      s.experimentalFeaturesEnabled = true;
      s.linuxCompositorBlurExperimental = true;
      s.windowBlurEnabled = true;
    }

    testWidgets(
      'M10.1 focus with blur re-applies the effect without resizing',
      (tester) async {
        await _pumpApp(tester, native, configure: enableBlur);
        native.clearCalls();
        await native.emit('focus');
        await _settle(tester);
        expect(native.setBoundsCalls, isEmpty);
        if (Platform.isWindows) {
          expect(native.effectCalls, hasLength(1));
        } else {
          expect(native.effectCalls, isEmpty);
        }
        await _teardown(tester);
        report.pass('M10.1');
      },
    );

    testWidgets('M10.2 focus without blur touches nothing', (tester) async {
      await _pumpApp(tester, native);
      native.clearCalls();
      await native.emit('focus');
      await _settle(tester);
      expect(native.setBoundsCalls, isEmpty);
      expect(native.effectCalls, isEmpty);
      expect(native.opacityCalls, isEmpty);
      await _teardown(tester);
      report.pass('M10.2');
    });

    testWidgets('M10.3 a settings change in a normal window still nudges', (
      tester,
    ) async {
      final shell = await _pumpApp(tester, native, configure: enableBlur);
      native.clearCalls();
      shell.settings.windowBlurStrength = 0.9;
      await _settle(tester);
      if (Platform.isWindows) {
        expect(native.effectCalls, hasLength(1));
        final bounds = native.setBoundsCalls;
        expect(bounds, hasLength(2));
        final first = bounds.first.arguments as Map<Object?, Object?>;
        final second = bounds.last.arguments as Map<Object?, Object?>;
        expect(first['width'], 1001);
        expect(second['width'], 1000);
        expect(second['height'], 700);
      } else {
        expect(native.setBoundsCalls, isEmpty);
      }
      await _teardown(tester);
      report.pass('M10.3');
    });

    for (final mode in ['maximized', 'fullscreen']) {
      testWidgets('M10.4 settings change while $mode never resizes', (
        tester,
      ) async {
        final shell = await _pumpApp(tester, native, configure: enableBlur);
        native
          ..maximized = mode == 'maximized'
          ..fullscreen = mode == 'fullscreen'
          ..clearCalls();
        shell.settings.windowBlurStrength = 0.9;
        await _settle(tester);
        if (Platform.isWindows) {
          expect(native.effectCalls, hasLength(1));
        }
        expect(native.setBoundsCalls, isEmpty);
        await _teardown(tester);
        if (mode == 'fullscreen') report.pass('M10.4');
      });

      testWidgets('M10.5 focus while $mode never resizes', (tester) async {
        await _pumpApp(tester, native, configure: enableBlur);
        native
          ..maximized = mode == 'maximized'
          ..fullscreen = mode == 'fullscreen'
          ..clearCalls();
        await native.emit('focus');
        await _settle(tester);
        expect(native.setBoundsCalls, isEmpty);
        await _teardown(tester);
        if (mode == 'fullscreen') report.pass('M10.5');
      });
    }
  });

  group('Finding 14: app-level rebuilds', () {
    testWidgets('M14.6 unrelated settings writes do not rebuild MaterialApp', (
      tester,
    ) async {
      final shell = await _pumpApp(tester, native);
      final before = shell.materialBuilds;
      final s = shell.settings;
      s.volume = 37;
      await tester.pump();
      s.speed = 1.5;
      await tester.pump();
      s.osdEnabled = !s.osdEnabled;
      await tester.pump();
      s.addRecentFile('C:/media/a.mp3');
      await tester.pump();
      await _settle(tester);
      expect(shell.materialBuilds, before);
      await _teardown(tester);
      report.pass('M14.6');
    });

    testWidgets('M14.7 theme mode change rebuilds and applies', (tester) async {
      final shell = await _pumpApp(tester, native);
      final before = shell.materialBuilds;
      shell.settings.themeMode = ThemeMode.light;
      await tester.pump();
      expect(shell.materialBuilds, greaterThan(before));
      expect(_materialApp(tester).themeMode, ThemeMode.light);
      await _teardown(tester);
      report.pass('M14.7');
    });

    testWidgets('M14.8 accent change rebuilds and changes the scheme', (
      tester,
    ) async {
      final shell = await _pumpApp(tester, native);
      final before = shell.materialBuilds;
      final oldPrimary = _materialApp(tester).darkTheme!.colorScheme.primary;
      shell.settings.accentColor = AccentColor.purple;
      await tester.pump();
      expect(shell.materialBuilds, greaterThan(before));
      final expected = ColorScheme.fromSeed(
        seedColor: Colors.purple,
        brightness: Brightness.dark,
      ).primary;
      final actual = _materialApp(tester).darkTheme!.colorScheme.primary;
      expect(actual, expected);
      expect(actual, isNot(oldPrimary));
      await _teardown(tester);
      report.pass('M14.8');
    });

    testWidgets('M14.9 blur and opacity changes rebuild and update themes', (
      tester,
    ) async {
      final shell = await _pumpApp(
        tester,
        native,
        configure: (s) {
          s.experimentalFeaturesEnabled = true;
          s.linuxCompositorBlurExperimental = true;
        },
      );
      var count = shell.materialBuilds;
      shell.settings.windowBlurEnabled = true;
      await tester.pump();
      expect(shell.materialBuilds, greaterThan(count));
      expect(
        _materialApp(tester).darkTheme!.scaffoldBackgroundColor,
        Colors.transparent,
      );
      count = shell.materialBuilds;
      shell.settings.windowBlurStrength = 0.9;
      await tester.pump();
      expect(shell.materialBuilds, greaterThan(count));
      expect(
        _materialApp(tester).darkTheme!
            .extension<WindowVisuals>()!
            .blurStrength,
        0.9,
      );
      count = shell.materialBuilds;
      shell.settings.windowOpacity = SettingsService.windowOpacityMin;
      await tester.pump();
      expect(shell.materialBuilds, greaterThan(count));
      await _teardown(tester);
      report.pass('M14.9');
    });

    testWidgets('M14.10 system brightness change still rebuilds', (
      tester,
    ) async {
      final shell = await _pumpApp(
        tester,
        native,
        configure: (s) => s.themeMode = ThemeMode.system,
      );
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final before = shell.materialBuilds;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(shell.materialBuilds, greaterThan(before));
      await _teardown(tester);
      report.pass('M14.10');
    });

    testWidgets('M14.11 the player home still rebuilds on a settings write', (
      tester,
    ) async {
      final shell = await _pumpApp(tester, native);
      final before = shell.homeBuilds;
      shell.settings.volume = 21;
      await tester.pump();
      expect(shell.homeBuilds, greaterThan(before));
      await _teardown(tester);
      report.pass('M14.11');
    });
  });

  group('Finding 30: one theme builder for both brightnesses', () {
    testWidgets('light and dark themes match the previous output', (
      tester,
    ) async {
      for (final blur in [false, true]) {
        final shell = await _pumpApp(
          tester,
          native,
          configure: (s) {
            s.experimentalFeaturesEnabled = true;
            s.linuxCompositorBlurExperimental = true;
            s.accentColor = AccentColor.teal;
            s.windowBlurEnabled = blur;
            s.windowBlurStrength = 0.4;
            s.windowOpacity = 0.7;
          },
        );
        final effective = blur && (_blurEffectiveHere || Platform.isLinux);
        final inputs = _legacyInputs(shell.settings, blurEnabled: effective);
        final app = _materialApp(tester);
        _expectThemeEquivalent(app.theme!, _legacyLight(inputs));
        _expectThemeEquivalent(app.darkTheme!, _legacyDark(inputs));
        if (effective) {
          expect(app.theme!.cardTheme.color, isNotNull);
          expect(app.darkTheme!.cardTheme.color, isNotNull);
          expect(app.theme!.cardTheme.elevation, 0);
          expect(app.theme!.scaffoldBackgroundColor, Colors.transparent);
          expect(app.darkTheme!.scaffoldBackgroundColor, Colors.transparent);
        } else {
          expect(app.theme!.cardTheme.color, isNull);
          expect(app.darkTheme!.cardTheme.color, isNull);
        }
        await _teardown(tester);
      }
      report
        ..pass('M30.1')
        ..pass('M30.2')
        ..pass('M30.3');
    });
  });
}
