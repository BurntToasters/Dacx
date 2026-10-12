import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/m3u_playlist.dart';
import 'package:dacx/services/idle_inhibit_service.dart';
import 'package:dacx/services/media_session_service.dart';
import 'package:dacx/services/player_shortcuts_service.dart';
import 'package:dacx/services/preferences_recovery.dart';
import 'package:dacx/services/resume_position_store.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/windows_shell_service.dart';
import 'package:dacx/widgets/keybinds_dialog.dart';

import '../support/player_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preferences recovery only heals decode errors', () {
    test('locked file is retried without moving anything aside', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory.systemTemp.createTempSync('dacx-a7-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/shared_preferences.json')
        ..writeAsStringSync('{"flutter.playback_volume":42.0}');
      var calls = 0;
      String? movedTo;
      final prefs = await PreferencesRecovery.load(
        loader: () async {
          calls++;
          if (calls == 1) {
            throw const FileSystemException(
              'Cannot open file',
              'shared_preferences.json',
              OSError('file is being used by another process', 32),
            );
          }
          return SharedPreferences.getInstance();
        },
        storeFile: () async => file,
        onRecovered: (path) => movedTo = path,
      );
      expect(prefs.getKeys(), isEmpty);
      expect(calls, 2);
      expect(movedTo, isNull);
      expect(file.existsSync(), isTrue);
    });

    test('undecodable json is still moved aside', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory.systemTemp.createTempSync('dacx-a7-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/shared_preferences.json')
        ..writeAsStringSync('{"flutter.');
      String? movedTo;
      final prefs = await PreferencesRecovery.load(
        loader: () async => throw const FormatException('bad json'),
        storeFile: () async => file,
        onRecovered: (path) => movedTo = path,
      );
      expect(prefs.getKeys(), isEmpty);
      expect(movedTo, isNotNull);
      expect(file.existsSync(), isFalse);
    });
  });

  group('update check cooldown', () {
    Future<SettingsService> settings() async {
      SharedPreferences.setMockInitialValues({
        'settings_schema_version': SettingsService.currentSchemaVersion,
        'update_check_enabled': true,
      });
      return SettingsService(await SharedPreferences.getInstance());
    }

    test('future timestamp counts as stale', () async {
      final s = await settings();
      addTearDown(s.dispose);
      s.lastUpdateCheck = DateTime(2099).millisecondsSinceEpoch;
      expect(s.shouldCheckForUpdate, isTrue);
    });

    test('recent timestamp suppresses the check', () async {
      final s = await settings();
      addTearDown(s.dispose);
      s.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
      expect(s.shouldCheckForUpdate, isFalse);
    });

    test('disabled checks stay off even with a future timestamp', () async {
      final s = await settings();
      addTearDown(s.dispose);
      s.updateCheckEnabled = false;
      s.lastUpdateCheck = DateTime(2099).millisecondsSinceEpoch;
      expect(s.shouldCheckForUpdate, isFalse);
    });
  });

  group('resume migration', () {
    test('legacy entries land in the store before the key is gone', () async {
      final dir = Directory.systemTemp.createTempSync('dacx-a7-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/resume_positions.json';
      await FileResumePositionStore(path).save({
        '/m/new.mp3': const ResumeEntry(positionMs: 50000, lastAccessMs: 7),
      });
      SharedPreferences.setMockInitialValues({
        'settings_schema_version': SettingsService.currentSchemaVersion,
        'resume_playback_enabled': true,
        'resume_positions_v2': jsonEncode({
          '/m/old.mp3': {'p': 61000, 't': 3},
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final s = SettingsService(
        prefs,
        resumeStore: FileResumePositionStore(path),
      );
      addTearDown(s.dispose);
      expect(prefs.containsKey('resume_positions_v2'), isFalse);
      final stored = FileResumePositionStore(path).load();
      expect(stored.keys, containsAll(['/m/old.mp3', '/m/new.mp3']));
      expect(s.resumePositionFor('/m/old.mp3'), 61000);
    });
  });

  group('shortcut conflicts', () {
    test('macos cmd normalizes to the same binding as ctrl', () {
      expect(
        PlayerShortcutsService.normalizeAccelerator('Meta+O'),
        PlayerShortcutsService.normalizeAccelerator('Ctrl+O'),
      );
    });

    test('hidden advanced bindings are not conflicts while tools are off', () {
      expect(
        PlayerShortcutsService.actionUsing(
          'L',
          const {},
          except: PlayerShortcutAction.seekForward,
          includeAdvanced: false,
        ),
        isNull,
      );
    });

    testWidgets('dialog does not flag a hidden advanced key as used', (
      tester,
    ) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      expect(services.settings.advancedPlaybackToolsEnabled, isFalse);
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
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.actionSave));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dialogKeybindConflictTitle), findsNothing);
      expect(services.settings.keybinds['seekForward'], ['L']);
    });
  });

  group('jump list privacy', () {
    test('stream urls never reach the jump list', () {
      expect(
        WindowsShellService.filterJumpListPaths([
          'C:\\music\\a.mp3',
          'https://example.com/stream?token=secret',
          'http://example.com/x#frag',
          'C:\\music\\b.mp3',
        ]),
        ['C:\\music\\a.mp3', 'C:\\music\\b.mp3'],
      );
    });
  });

  group('playlist export', () {
    test('export starts with a bom and round-trips in dacx', () {
      final sources = [PlayableSource.file('C:\\music\\t\u00e4st.mp3')];
      final encoded = M3uPlaylist.encode(sources);
      expect(encoded.startsWith('\uFEFF'), isTrue);
      final roundTripped = M3uPlaylist.parse(
        M3uPlaylist.decodeBytes(utf8.encode(encoded)),
      );
      expect(roundTripped, sources);
    });
  });

  group('idle inhibit follows video presence', () {
    setUp(PlayerScreenHarness.installChannelMocks);
    tearDown(PlayerScreenHarness.uninstallChannelMocks);

    test('audio-only playback does not hold the display awake', () async {
      final service = IdleInhibitService();
      await service.setPlaying(true, hasVideo: false);
      final inhibits = PlayerScreenHarness.windowMethodsCalls.where(
        (c) => c.method == IdleInhibitService.setIdleInhibitMethod,
      );
      expect(inhibits.where((c) => c.arguments == true), isEmpty);
      await service.dispose();
    });

    test('video playback still holds the display awake', () async {
      final service = IdleInhibitService();
      await service.setPlaying(true, hasVideo: true);
      final inhibits = PlayerScreenHarness.windowMethodsCalls.where(
        (c) =>
            c.method == IdleInhibitService.setIdleInhibitMethod &&
            c.arguments == true,
      );
      expect(inhibits, isNotEmpty);
      await service.dispose();
    });
  });

  group('media session quit', () {
    setUp(PlayerScreenHarness.installChannelMocks);
    tearDown(PlayerScreenHarness.uninstallChannelMocks);

    testWidgets('quit exits through the tray quit path', (tester) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      final commands = StreamController<MediaSessionCommand>();
      addTearDown(commands.close);
      var quitCalled = false;
      await tester.pumpWidget(
        PlayerScreenHarness.wrap(
          settings: services.settings,
          debugLog: services.debugLog,
          updates: services.updates,
          mediaSessionCommandsForTesting: commands,
          onQuitRequest: () async => quitCalled = true,
        ),
      );
      await tester.pumpAndSettle();
      commands.add(const MediaSessionCommand('quit', null));
      await tester.pumpAndSettle();
      expect(quitCalled, isTrue);
    });
  });
}
