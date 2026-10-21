// Covers the controller and focus-node lifetime of the rename-marker dialog and
// the keybind capture dialog. See DIALOG_CONTROLLER_LIFETIME_FAILURE_MODES.md.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/services/advanced_playback_controller.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/widgets/advanced_playback_dialog.dart';
import 'package:dacx/widgets/keybinds_dialog.dart';

import '../support/player_screen_harness.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

enum _Close { save, cancel, submit, escape, barrier }

Future<void> _closeRename(
  WidgetTester tester,
  AppLocalizations l10n,
  _Close how,
) async {
  final dialog = find.byType(AlertDialog).last;
  switch (how) {
    case _Close.save:
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(l10n.actionSave)),
      );
    case _Close.cancel:
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(l10n.actionCancel)),
      );
    case _Close.submit:
      await tester.testTextInput.receiveAction(TextInputAction.done);
    case _Close.escape:
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    case _Close.barrier:
      await tester.tapAt(const Offset(5, 5));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  group('rename marker dialog', () {
    for (final how in _Close.values) {
      testWidgets('closing via ${how.name} exits cleanly', (tester) async {
        PlayerScreenHarness.configureDesktopViewport(tester);
        final services = await PlayerScreenHarness.createServices();
        addTearDown(services.settings.dispose);
        services.settings.advancedPlaybackToolsEnabled = true;
        final controller = AdvancedPlaybackController(
          settings: services.settings,
          player: HeadlessPlayerService(),
        );
        await controller.setSource(PlayableSource.file('/e2e/lifetime.mp3'));
        controller.addMarker(label: 'Intro');
        final l10n = await _l10n();

        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AdvancedPlaybackDialog(
                    controller: controller,
                    settings: services.settings,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(l10n.advancedMarkerRename));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(TextField),
          ),
          'Renamed',
        );
        await tester.pump();

        await _closeRename(tester, l10n, how);

        expect(tester.takeException(), isNull);
        final label = controller.markers.single.label;
        if (how == _Close.save || how == _Close.submit) {
          expect(label, 'Renamed');
        } else {
          expect(label, 'Intro');
        }
      });
    }
  });

  group('keybind capture dialog', () {
    Future<void> openCapture(
      WidgetTester tester,
      void Function(String?) onResult,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => onResult(await captureKeybind(context)),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('Save after a key press returns the accelerator', (
      tester,
    ) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final l10n = await _l10n();
      var called = false;
      String? result;
      await openCapture(tester, (value) {
        called = true;
        result = value;
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.text(l10n.actionSave),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(called, isTrue);
      expect(result, 'Space');
    });

    for (final how in [_Close.cancel, _Close.escape, _Close.barrier]) {
      testWidgets('${how.name} after a key press returns null', (tester) async {
        PlayerScreenHarness.configureDesktopViewport(tester);
        final l10n = await _l10n();
        var called = false;
        String? result = 'unset';
        await openCapture(tester, (value) {
          called = true;
          result = value;
        });
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        switch (how) {
          case _Close.cancel:
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog).last,
                matching: find.text(l10n.actionCancel),
              ),
            );
          case _Close.escape:
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case _Close.barrier:
            await tester.tapAt(const Offset(5, 5));
          default:
            fail('unexpected close path');
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(called, isTrue);
        expect(result, isNull);
      });
    }

    testWidgets('Escape with no key press returns null', (tester) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      var called = false;
      String? result = 'unset';
      await openCapture(tester, (value) {
        called = true;
        result = value;
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(called, isTrue);
      expect(result, isNull);
    });
  });
}
