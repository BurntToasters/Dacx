import 'dart:async';
import 'dart:convert';

import 'package:cryptography_plus/cryptography_plus.dart' as cryptography;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/services/player_shortcuts_service.dart';
import 'package:dacx/services/seek_preview_service.dart';
import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_trust_config.dart';
import 'package:dacx/services/tray_service.dart';
import 'package:dacx/widgets/keybinds_dialog.dart';

import '../support/player_screen_harness.dart';

const _space = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: LogicalKeyboardKey.space,
  timeStamp: Duration.zero,
);
const _keyL = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyL,
  logicalKey: LogicalKeyboardKey.keyL,
  timeStamp: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shortcuts', () {
    PlayerShortcutAction? resolve(KeyEvent e, Map<String, List<String>> c) =>
        PlayerShortcutsService.resolve(
          event: e,
          hasMedia: true,
          isMetaPressed: false,
          isControlPressed: false,
          customBindings: c,
        );

    test('a rebound action no longer fires on its old default key', () {
      expect(
        resolve(_space, {
          'playPause': ['K'],
        }),
        isNull,
      );
      expect(resolve(_space, const {}), PlayerShortcutAction.playPause);
    });

    test('Space captured by older builds as a blank still works', () {
      expect(
        resolve(_space, {
          'seekForward': [' '],
          'playPause': ['K'],
        }),
        PlayerShortcutAction.seekForward,
      );
      expect(
        PlayerShortcutsService.normalizeAccelerator('Ctrl+ '),
        'Ctrl+Space',
      );
    });

    test('a rebound advanced action no longer fires on its default key', () {
      expect(
        PlayerShortcutsService.resolveAdvanced(
          event: _keyL,
          isMetaPressed: false,
          isControlPressed: false,
          isShiftPressed: false,
          customBindings: const {
            'cycleAdvancedLoop': ['Ctrl+L'],
          },
        ),
        isNull,
      );
    });

    test('conflict lookup sees defaults and custom bindings', () {
      expect(
        PlayerShortcutsService.actionUsing(
          'Space',
          const {},
          except: PlayerShortcutAction.seekForward,
        ),
        PlayerShortcutAction.playPause,
      );
      expect(
        PlayerShortcutsService.actionUsing('Space', const {
          'playPause': ['K'],
        }, except: PlayerShortcutAction.seekForward),
        isNull,
      );
    });

    testWidgets('assigning a used key asks, then moves it', (tester) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKeybindsDialog(
                context: context,
                settings: services.settings,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );
      final tile = find.ancestor(
        of: find.text(l10n.shortcutSeekForward),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(
          of: tile,
          matching: find.byTooltip(l10n.actionSetNewBinding),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.actionSave));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dialogKeybindConflictTitle), findsOneWidget);
      await tester.tap(find.text(l10n.actionReassign));
      await tester.pumpAndSettle();
      expect(services.settings.keybinds['seekForward'], ['Space']);
      expect(services.settings.keybinds['playPause'], isEmpty);
    });
  });

  group('update key rotation', () {
    Future<({String key, List<int> signature, List<int> bytes})> sign() async {
      final bytes = utf8.encode(
        jsonEncode({
          'version': '1.0.1',
          'app': 'dacx',
          'platform': 'windows-x64',
          'assets': {'Dacx-Windows-x64.msi': 'c' * 64},
        }),
      );
      final algorithm = cryptography.Ed25519();
      final pair = await algorithm.newKeyPair();
      final publicKey = await pair.extractPublicKey();
      final signature = await algorithm.sign(bytes, keyPair: pair);
      return (
        key: base64Encode(publicKey.bytes),
        signature: signature.bytes,
        bytes: bytes,
      );
    }

    Future<SelfUpdateOutcome> validate(
      List<String> keys,
      ({String key, List<int> signature, List<int> bytes}) signed,
    ) async {
      final svc = SelfUpdateService(windowsManifestPublicKeysOverride: keys);
      final result = await svc.validateWindowsManifestForTesting(
        manifestBytes: signed.bytes,
        signatureBytes: signed.signature,
        version: '1.0.1',
        assetName: 'Dacx-Windows-x64.msi',
      );
      return result.outcome;
    }

    test('a manifest signed by the next key passes during rotation', () async {
      final current = await sign();
      final next = await sign();
      expect(
        await validate([current.key, next.key], next),
        SelfUpdateOutcome.spawned,
      );
    });

    test('a manifest signed by an unknown key fails', () async {
      final trusted = await sign();
      final stranger = await sign();
      expect(
        await validate([trusted.key], stranger),
        SelfUpdateOutcome.signatureInvalid,
      );
    });

    test('an empty key list is a configuration error', () async {
      final signed = await sign();
      expect(
        await validate(const [], signed),
        SelfUpdateOutcome.signatureInvalid,
      );
    });

    test('shipped config has at least one valid 32-byte key', () {
      expect(UpdateTrustConfig.windowsManifestPublicKeysBase64, isNotEmpty);
      for (final key in UpdateTrustConfig.windowsManifestPublicKeysBase64) {
        expect(base64Decode(key), hasLength(32));
      }
    });
  });

  group('tray', () {
    setUp(PlayerScreenHarness.installChannelMocks);
    tearDown(PlayerScreenHarness.uninstallChannelMocks);

    test('closing to tray minimizes when the tray cannot be created', () async {
      final tray = TrayService(onQuit: () async {});
      final hidden = await tray.hideToTray();
      expect(tray.isInitialized, isFalse);
      expect(hidden, isFalse);
      final methods = PlayerScreenHarness.windowManagerCalls.map(
        (c) => c.method,
      );
      expect(methods, isNot(contains('hide')));
      expect(methods, contains('minimize'));
    });
  });

  group('seek preview', () {
    test('a frame always belongs to the latest requested position', () async {
      final gates = <int, Completer<void>>{};
      final captured = <int>[];
      final service = SeekPreviewService(
        captureForTesting: (key) async {
          captured.add(key);
          final gate = gates[key] = Completer<void>();
          await gate.future;
          return Uint8List.fromList([key ~/ 1000]);
        },
      );
      await service.setEnabled(true);
      service.markReadyForTesting('/m/a.mkv');
      final first = service.requestPreview(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final second = service.requestPreview(const Duration(seconds: 50));
      gates[captured.first]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(captured.last, isNot(captured.first));
      gates[captured.last]!.complete();
      expect(captured.last, 50000);
      expect((await second)!.single, 50);
      expect((await first)!.single, 50);
      await service.dispose();
    });
  });
}
