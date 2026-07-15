import 'package:dacx/playback/player_audio_session.dart';
import 'package:dacx/playback/player_controller.dart';
import 'package:dacx/services/player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayerService implements IPlayerService {
  String? lastAf;
  bool afOk = true;

  @override
  bool get isDisposed => false;

  @override
  Future<bool> setAudioFilter(String? chain) async {
    lastAf = chain;
    return afOk;
  }

  @override
  Future<String?> getProperty(String name) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerAudioSession', () {
    late _FakePlayerService playerService;
    late SettingsService settings;
    late PlayerController player;
    late PlayerAudioSession session;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
      playerService = _FakePlayerService();
      player = PlayerController();
      session = PlayerAudioSession(
        playerService: playerService,
        settings: settings,
        player: player,
      );
    });

    test('applyMergedAudioFilters applies EQ when enabled', () async {
      settings.eqEnabled = true;
      settings.eqBands = const [4, 0, 0, 0, 0, 0, 0, 0, 0, 0];

      final result = await session.applyMergedAudioFilters();
      expect(result.failed, isFalse);
      expect(result.skipped, isFalse);
      expect(playerService.lastAf, contains('equalizer'));
      expect(player.lastAppliedAfChain, contains('equalizer'));
    });

    test('applyMergedAudioFilters skips when chain unchanged', () async {
      settings.eqEnabled = false;
      player.lastAppliedAfChain = '';

      final result = await session.applyMergedAudioFilters();
      expect(result.skipped, isTrue);
      expect(playerService.lastAf, isNull);
    });

    test('applyMergedAudioFilters reports failed when mpv rejects', () async {
      settings.eqEnabled = true;
      settings.eqBands = const [4, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      playerService.afOk = false;

      final result = await session.applyMergedAudioFilters();
      expect(result.failed, isTrue);
    });
  });
}
