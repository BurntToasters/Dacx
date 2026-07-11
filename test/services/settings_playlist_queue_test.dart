import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  group('SettingsService playlist queue persistence', () {
    test('round-trips queue snapshot with debounce flush', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      settings.savePlaylistQueue([
        PlayableSource.file('/a.mp3'),
        PlayableSource.url('https://example.com/b.flac'),
      ], 1);
      settings.flushPlaylistQueue();

      final snap = settings.readPlaylistQueue();
      expect(snap.items, ['/a.mp3', 'https://example.com/b.flac']);
      expect(snap.index, 1);

      settings.clearPlaylistQueue();
      expect(settings.readPlaylistQueue().isEmpty, isTrue);
      expect(prefs.getString('playlist_queue_v1'), isNull);
    });

    test('rejects unsafe paths and clamps index', () async {
      SharedPreferences.setMockInitialValues({
        'playlist_queue_v1':
            '{"items":["/ok.mp3","..\\\\evil","https://u:p@x/a"],"index":99}',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      final snap = settings.readPlaylistQueue();
      expect(snap.items, ['/ok.mp3']);
      expect(snap.index, 0);
    });

    test('empty state tip flag defaults false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      expect(settings.emptyStateTipDismissed, isFalse);
      settings.emptyStateTipDismissed = true;
      expect(settings.emptyStateTipDismissed, isTrue);
    });
  });
}
