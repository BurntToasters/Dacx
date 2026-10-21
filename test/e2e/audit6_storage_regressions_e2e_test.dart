import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

import 'package:dacx/services/preferences_recovery.dart';
import 'package:dacx/services/resume_position_store.dart';
import 'package:dacx/services/settings_service.dart';

class _TempPathProvider extends PathProviderWindows {
  _TempPathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dacx-storage-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('preferences recovery', () {
    late SharedPreferencesStorePlatform previousStore;
    setUp(() => previousStore = SharedPreferencesStorePlatform.instance);
    tearDown(() => SharedPreferencesStorePlatform.instance = previousStore);

    test(
      'truncated file is moved aside and the app gets empty prefs',
      () async {
        final file = File(p.join(dir.path, 'shared_preferences.json'))
          ..writeAsStringSync('{"flutter.playback_volume":80.0,"flutter.re');
        SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
          ..pathProvider = _TempPathProvider(dir.path);
        String? movedTo;
        final prefs = await PreferencesRecovery.load(
          storeFile: () async => file,
          onRecovered: (path) => movedTo = path,
        );
        expect(prefs.getKeys(), isEmpty);
        expect(movedTo, isNotNull);
        expect(File(movedTo!).readAsStringSync(), startsWith('{"flutter.'));
        expect(file.existsSync(), isFalse);
        await prefs.setDouble('playback_volume', 50);
        expect(
          jsonDecode(file.readAsStringSync()),
          containsPair('flutter.playback_volume', 50.0),
        );
      },
    );

    test('a loader that keeps failing moves the file aside once and loads defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final file = File(p.join(dir.path, 'shared_preferences.json'))
        ..writeAsStringSync('garbage');
      var calls = 0;
      final prefs = await PreferencesRecovery.load(
        loader: () async {
          calls++;
          throw const FormatException('still broken');
        },
        storeFile: () async => file,
      );
      expect(prefs.getKeys(), isEmpty);
      expect(calls, 2);
      expect(
        dir.listSync().whereType<File>().where(
          (f) => p.basename(f.path).contains('.corrupt-'),
        ),
        hasLength(1),
      );
    });

    test('without a store file the original error is rethrown', () async {
      Object? error;
      try {
        await PreferencesRecovery.load(
          loader: () async => throw const FormatException('x'),
          storeFile: () async => null,
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<FormatException>());
    });
  });

  group('file resume store', () {
    String path() => p.join(dir.path, 'resume_positions.json');

    test('two instances saving different files keep both entries', () async {
      final a = FileResumePositionStore(path());
      final b = FileResumePositionStore(path());
      a.load();
      b.load();
      await a.save({
        '/m/a.mp3': const ResumeEntry(positionMs: 40000, lastAccessMs: 1),
      });
      await b.save({
        '/m/b.mp3': const ResumeEntry(positionMs: 50000, lastAccessMs: 1),
      });
      final merged = FileResumePositionStore(path()).load();
      expect(merged.keys, containsAll(['/m/a.mp3', '/m/b.mp3']));
    });

    test('removing an entry is not undone by the merge', () async {
      final store = FileResumePositionStore(path());
      await store.save({
        '/m/a.mp3': const ResumeEntry(positionMs: 40000, lastAccessMs: 1),
        '/m/b.mp3': const ResumeEntry(positionMs: 50000, lastAccessMs: 2),
      });
      await store.save(
        {'/m/b.mp3': const ResumeEntry(positionMs: 50000, lastAccessMs: 2)},
        removed: {'/m/a.mp3'},
      );
      expect(FileResumePositionStore(path()).load().keys, ['/m/b.mp3']);
    });

    test('corrupt file loads as empty and is replaced on save', () async {
      File(path()).writeAsStringSync('{"entries":{"/m/a.mp3":{"p":');
      final store = FileResumePositionStore(path());
      expect(store.load(), isEmpty);
      await store.save({
        '/m/c.mp3': const ResumeEntry(positionMs: 40000, lastAccessMs: 1),
      });
      expect(FileResumePositionStore(path()).load().keys, ['/m/c.mp3']);
    });

    test('merge keeps only the newest entries up to the cap', () async {
      final store = FileResumePositionStore(path(), maxEntries: 3);
      await store.save({
        for (var i = 1; i <= 10; i++)
          '/m/$i.mp3': ResumeEntry(positionMs: 40000, lastAccessMs: i),
      });
      expect(FileResumePositionStore(path()).load().keys.toSet(), {
        '/m/8.mp3',
        '/m/9.mp3',
        '/m/10.mp3',
      });
    });

    test('write leaves no temp files behind', () async {
      final store = FileResumePositionStore(path());
      await store.save({
        '/m/a.mp3': const ResumeEntry(positionMs: 40000, lastAccessMs: 1),
      });
      expect(dir.listSync().map((e) => p.basename(e.path)), [
        'resume_positions.json',
      ]);
    });

    test(
      'settings migrate prefs resume data once into the file store',
      () async {
        SharedPreferences.setMockInitialValues({
          'settings_schema_version': SettingsService.currentSchemaVersion,
          'resume_playback_enabled': true,
          'resume_positions_v2': jsonEncode({
            '/m/old.mp3': {'p': 61000, 't': 3},
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsService(
          prefs,
          resumeStore: FileResumePositionStore(path()),
        );
        expect(settings.resumePositionFor('/m/old.mp3'), 61000);
        expect(prefs.containsKey('resume_positions_v2'), isFalse);
        await settings.flushResumePositions();
        expect(FileResumePositionStore(path()).load().keys, ['/m/old.mp3']);
        settings.dispose();
      },
    );

    test('settings save, clear, and reset go to the file store', () async {
      SharedPreferences.setMockInitialValues({
        'settings_schema_version': SettingsService.currentSchemaVersion,
        'resume_playback_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(
        prefs,
        resumeStore: FileResumePositionStore(path()),
      );
      settings.saveResumePosition('/m/a.mp3', 45000);
      await settings.flushResumePositions();
      expect(
        FileResumePositionStore(path()).load()['/m/a.mp3']?.positionMs,
        45000,
      );
      expect(prefs.containsKey('resume_positions_v2'), isFalse);
      settings.saveResumePosition('/m/a.mp3', null);
      await settings.flushResumePositions();
      expect(FileResumePositionStore(path()).load(), isEmpty);
      settings.saveResumePosition('/m/b.mp3', 45000);
      await settings.flushResumePositions();
      settings.clearAllResumePositions();
      await settings.flushResumePositions();
      expect(FileResumePositionStore(path()).load(), isEmpty);
      settings.saveResumePosition('/m/c.mp3', 45000);
      await settings.flushResumePositions();
      await settings.resetAll();
      expect(FileResumePositionStore(path()).load(), isEmpty);
      settings.dispose();
    });
  });
}
