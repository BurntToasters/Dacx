import 'dart:io';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/main.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:dacx/widgets/app_snackbar.dart';
import 'package:dacx/widgets/compact_exit_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _acrylicChannel = MethodChannel('com.alexmercerind/flutter_acrylic');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void _installAcrylic() {
  _messenger.setMockMethodCallHandler(_acrylicChannel, (call) async => null);
}

void _uninstallAcrylic() {
  _messenger.setMockMethodCallHandler(_acrylicChannel, null);
}

final class _ThrowingFilePicker extends FilePickerPlatform {
  _ThrowingFilePicker(this.error);

  final Object error;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    throw error;
  }
}

class _WindowMock {
  Size size = const Size(1200, 800);
  Offset position = const Offset(40, 60);
  bool Function(Map<Object?, Object?> args)? failSetBounds;

  void install() {
    _messenger.setMockMethodCallHandler(
      PlayerScreenHarness.windowManagerChannel,
      handle,
    );
  }

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'isMaximized':
      case 'isMinimized':
      case 'isFullScreen':
        return false;
      case 'isVisible':
        return true;
      case 'getBounds':
        return {
          'x': position.dx,
          'y': position.dy,
          'width': size.width,
          'height': size.height,
        };
      case 'setBounds':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final fail = failSetBounds;
        if (fail != null && fail(args)) {
          throw PlatformException(code: 'set_bounds_failed');
        }
        final width = args['width'];
        final height = args['height'];
        if (width is num && height is num) {
          size = Size(width.toDouble(), height.toDouble());
        }
        final x = args['x'];
        final y = args['y'];
        if (x is num && y is num) {
          position = Offset(x.toDouble(), y.toDouble());
        }
        return null;
      case 'getTitleBarHeight':
        return 0;
      default:
        return null;
    }
  }
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [
      WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0),
    ],
  );
}

Future<void> _settle(WidgetTester tester, {int steps = 6}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pressMiniPlayerShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

List<String> _visibleSnackTexts(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );
  return [
    for (final element in texts.evaluate())
      if ((element.widget as Text).data != null) (element.widget as Text).data!,
  ];
}

Future<Set<String>> _collectSnackTexts(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 12),
}) async {
  final seen = <String>{};
  var elapsed = Duration.zero;
  const step = Duration(milliseconds: 250);
  while (elapsed <= total) {
    seen.addAll(_visibleSnackTexts(tester));
    await tester.pump(step);
    elapsed += step;
  }
  return seen;
}

Future<SettingsService> _pumpPlayer(
  WidgetTester tester, {
  required ValueChanged<bool> onCompactModeChanged,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _theme(),
      home: PlayerScreen(
        settings: services.settings,
        debugLog: services.debugLog,
        updateService: services.updates,
        playerService: HeadlessPlayerService(),
        headlessMediaSurface: true,
        onCompactModeChanged: onCompactModeChanged,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return services.settings;
}

Future<void> _pumpSnackHost(
  WidgetTester tester,
  void Function(BuildContext context) onReady,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onReady(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _tapGo(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pump();
}

Future<SettingsService> _pumpDacxApp(
  WidgetTester tester, {
  required SettingsService settings,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final debugLog = DebugLogService(isEnabled: () => false);
  final updates = UpdateService(
    debugLog: debugLog,
    debugSource: 'feedback_test',
    httpGet: (_, {headers}) async => throw Exception('offline'),
  );
  final player = HeadlessPlayerService();
  await tester.pumpWidget(
    DacxApp(
      settings: settings,
      debugLog: debugLog,
      updateService: updates,
      shouldWarnForInstallLocation: () => false,
      playerHomeBuilder: (context, s, onCompactModeChanged) => PlayerScreen(
        settings: s,
        debugLog: debugLog,
        updateService: updates,
        playerService: player,
        headlessMediaSurface: true,
        onCompactModeChanged: onCompactModeChanged,
      ),
    ),
  );
  await _settle(tester);
  return settings;
}

Future<void> _emitWindowEvent(String eventName) async {
  await _messenger.handlePlatformMessage(
    'window_manager',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onEvent', {'eventName': eventName}),
    ),
    (_) {},
  );
}

Future<void> _resizeEvents(WidgetTester tester) async {
  await _emitWindowEvent('resize');
  await _emitWindowEvent('move');
  await tester.pump(const Duration(milliseconds: 250));
  await _settle(tester);
}

Future<void> _teardownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'feedback',
    expectedIds: [
      'M23.1',
      'M23.2',
      'M23.3',
      'M23.4',
      'M23.5',
      'M3.11',
      'M3.12',
      'M3.13',
      'M3.14',
    ],
  );

  setUpAll(() async {
    PlayerScreenHarness.installChannelMocks();
    _installAcrylic();
    await Window.initialize();
    _uninstallAcrylic();
    PlayerScreenHarness.uninstallChannelMocks();
  });

  setUp(() {
    PlayerScreenHarness.installChannelMocks();
    _installAcrylic();
  });

  tearDown(() {
    _uninstallAcrylic();
    PlayerScreenHarness.uninstallChannelMocks();
  });

  tearDownAll(report.write);

  group('Finding 23: snackbars replace instead of queue', () {
    testWidgets('M23.1 a second message on the player replaces the first', (
      tester,
    ) async {
      await _pumpPlayer(tester, onCompactModeChanged: (_) {});
      FilePickerPlatform.instance = _ThrowingFilePicker(
        PlatformException(code: 'denied', message: 'first'),
      );
      await tester.tap(find.byTooltip('Play Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add files…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('File picker failed. first'), findsOneWidget);

      FilePickerPlatform.instance = _ThrowingFilePicker(
        PlatformException(code: 'denied', message: 'second'),
      );
      await tester.tap(find.text('Add files…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('File picker failed. second'), findsOneWidget);
      expect(find.text('File picker failed. first'), findsNothing);
      final seen = await _collectSnackTexts(tester);
      expect(seen, isNot(contains('File picker failed. first')));
      report.pass('M23.1');
    });

    testWidgets('M23.2 a burst shows only the last message and queues none', (
      tester,
    ) async {
      await _pumpSnackHost(tester, (context) {
        showAppSnackBar(context, 'one');
        showAppSnackBar(context, 'two');
        showAppSnackBar(context, 'three');
      });
      await _tapGo(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_visibleSnackTexts(tester), ['three']);

      final seen = await _collectSnackTexts(tester);
      expect(seen, {'three'});
      expect(find.byType(SnackBar), findsNothing);
      report.pass('M23.2');
    });

    testWidgets('M23.3 actions and durations are preserved', (tester) async {
      var actionRuns = 0;
      var step = 0;
      await _pumpSnackHost(tester, (context) {
        step++;
        if (step == 1) {
          showAppSnackBar(
            context,
            'with action',
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => actionRuns++,
            ),
            duration: const Duration(seconds: 10),
          );
        } else {
          showAppSnackBar(context, 'plain');
        }
      });
      await _tapGo(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('with action'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 10),
      );
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(actionRuns, 1);
      await tester.pump(const Duration(seconds: 1));

      await _tapGo(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('plain'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 4),
      );
      report.pass('M23.3');
    });

    testWidgets('M23.4 the messenger entry point replaces the same way', (
      tester,
    ) async {
      late ScaffoldMessengerState messenger;
      await _pumpSnackHost(tester, (context) {
        messenger = ScaffoldMessenger.of(context);
      });
      await _tapGo(tester);
      messenger.showAppSnackBar('alpha', duration: const Duration(seconds: 3));
      messenger.showAppSnackBar('beta', duration: const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_visibleSnackTexts(tester), ['beta']);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 3),
      );
      final seen = await _collectSnackTexts(tester);
      expect(seen, {'beta'});
      expect(find.byType(SnackBar), findsNothing);
      report.pass('M23.4');
    });

    test('M23.5 no showSnackBar call remains in lib outside the helper', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        if (normalized.endsWith('lib/widgets/app_snackbar.dart')) continue;
        if (entity.readAsStringSync().contains('showSnackBar(')) {
          offenders.add(normalized);
        }
      }
      expect(offenders, isEmpty);
      report.pass('M23.5');
    });
  });

  group('Finding 3: mini-player geometry', () {
    testWidgets('M3.11 enter and exit are reported once committed', (
      tester,
    ) async {
      final win = _WindowMock()..install();
      final reported = <bool>[];
      await _pumpPlayer(tester, onCompactModeChanged: reported.add);

      win.failSetBounds = (args) =>
          args['width'] == 480 && args['height'] == 320;
      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      expect(find.byType(CompactExitButton), findsNothing);
      expect(reported, isEmpty);

      win.failSetBounds = null;
      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);
      expect(reported, [true]);

      win.failSetBounds = (_) => true;
      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);
      expect(reported, [true]);

      win.failSetBounds = null;
      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      expect(find.byType(CompactExitButton), findsNothing);
      expect(reported, [true, false]);
      report.pass('M3.11');
    });

    testWidgets('M3.12 disposal reports false only while in the mini-player', (
      tester,
    ) async {
      _WindowMock().install();
      final inMini = <bool>[];
      await _pumpPlayer(tester, onCompactModeChanged: inMini.add);
      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);
      expect(inMini, [true]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(inMini, [true, false]);

      final normal = <bool>[];
      await _pumpPlayer(tester, onCompactModeChanged: normal.add);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(normal, isEmpty);
      report.pass('M3.12');
    });

    const storedSize = Size(900, 600);
    const storedPos = Offset(10, 20);

    Future<SettingsService> seededSettings() async {
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      final settings = SettingsService(shared);
      settings.saveWindowSize(storedSize);
      settings.saveWindowPosition(storedPos);
      return settings;
    }

    testWidgets('M3.13 resize in the mini-player saves nothing', (
      tester,
    ) async {
      _WindowMock().install();
      final settings = await _pumpDacxApp(
        tester,
        settings: await seededSettings(),
      );
      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);

      await _resizeEvents(tester);
      expect(settings.windowSize, storedSize);
      expect(settings.windowPosition, storedPos);
      expect(settings.windowMaximized, isFalse);
      await _teardownApp(tester);
      report.pass('M3.13');
    });

    testWidgets('M3.14 saving resumes after leaving the mini-player', (
      tester,
    ) async {
      _WindowMock().install();
      final settings = await _pumpDacxApp(
        tester,
        settings: await seededSettings(),
      );
      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      await _resizeEvents(tester);
      expect(settings.windowSize, storedSize);

      await _pressMiniPlayerShortcut(tester);
      await _settle(tester);
      expect(find.byType(CompactExitButton), findsNothing);
      await _resizeEvents(tester);
      expect(settings.windowSize, const Size(1200, 800));
      expect(settings.windowPosition, const Offset(40, 60));
      await _teardownApp(tester);
      report.pass('M3.14');
    });
  });
}
