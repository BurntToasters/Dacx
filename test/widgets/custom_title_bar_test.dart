import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:dacx/widgets/custom_title_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowManager = MethodChannel('window_manager');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManager, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isMaximized':
            case 'isFullScreen':
              return false;
            case 'getTitleBarHeight':
              return 0;
            case 'setTitleBarStyle':
            case 'startDragging':
            case 'minimize':
            case 'maximize':
            case 'unmaximize':
            case 'close':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManager, null);
  });

  Widget wrap(Widget child) {
    final visuals = WindowVisuals.fromScheme(
      const ColorScheme.dark(),
      blurEnabled: false,
      blurStrength: 0,
    );
    return MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [visuals]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  Offset windowButtonCenter(WidgetTester tester, int indexFromRight) {
    final topRight = tester.getTopRight(find.byType(CustomTitleBar));
    return topRight.translate(-23 - (46.0 * indexFromRight), 16);
  }

  testWidgets('renders nothing on Linux', (tester) async {
    if (!Platform.isLinux) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    expect(find.text('Dacx'), findsNothing);
  });

  testWidgets('renders the Dacx label on Windows/macOS', (tester) async {
    if (Platform.isLinux) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    await tester.pump();
    // Allow first startup probe to confirm native caption is hidden.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Dacx'), findsOneWidget);
  });

  testWidgets('omits window control buttons on macOS', (tester) async {
    if (!Platform.isMacOS) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    await tester.pump();
    expect(find.bySemanticsLabel('Minimize window'), findsNothing);
    expect(find.bySemanticsLabel('Maximize window'), findsNothing);
    expect(find.bySemanticsLabel('Close window'), findsNothing);
  });

  testWidgets('shows minimize/maximize/close buttons on Windows', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    await tester.pump();
    // Wait past the first startup probe (50ms) so the controls become
    // visible after the title-bar style is confirmed hidden.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('Minimize window'), findsOneWidget);
    expect(find.bySemanticsLabel('Maximize window'), findsOneWidget);
    expect(find.bySemanticsLabel('Close window'), findsOneWidget);
  });

  testWidgets('drag start invokes window_manager.startDragging', (
    tester,
  ) async {
    if (Platform.isLinux) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Dacx')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'startDragging'), isTrue);
  });

  testWidgets('double tap toggles maximize', (tester) async {
    if (Platform.isLinux) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final center = tester.getCenter(find.text('Dacx'));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(
      calls.any((c) => c.method == 'maximize' || c.method == 'unmaximize'),
      isTrue,
    );
  });

  testWidgets('window control buttons forward to window_manager (Windows)', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    calls.clear();

    await tester.tapAt(windowButtonCenter(tester, 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.any((c) => c.method == 'minimize'), isTrue);

    calls.clear();
    await tester.tapAt(windowButtonCenter(tester, 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      calls.any((c) => c.method == 'maximize' || c.method == 'unmaximize'),
      isTrue,
    );

    calls.clear();
    await tester.tapAt(windowButtonCenter(tester, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.any((c) => c.method == 'close'), isTrue);
  });

  testWidgets('responds to window maximize/unmaximize listener events', (
    tester,
  ) async {
    if (Platform.isLinux) return;
    await tester.pumpWidget(wrap(const CustomTitleBar()));
    await tester.pump();
    // Simulate window-manager broadcasting that the window was maximized.
    final encoded = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onEvent', {'eventName': 'maximize'}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('window_manager', encoded, (_) {});
    await tester.pump();
    final encodedRestore = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onEvent', {'eventName': 'unmaximize'}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('window_manager', encodedRestore, (_) {});
    await tester.pump();
    // Pumping doesn't throw; widget remains rendered.
    expect(find.text('Dacx'), findsOneWidget);
  });
}
