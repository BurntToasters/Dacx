import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/player_audio_session.dart';
import 'package:dacx/playback/player_controller.dart';
import 'package:dacx/services/audio_spectrum_service.dart';
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
    late AudioSpectrumService spectrum;
    late PlayerAudioSession session;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
      playerService = _FakePlayerService();
      player = PlayerController();
      spectrum = AudioSpectrumService(playerService: playerService);
      session = PlayerAudioSession(
        playerService: playerService,
        settings: settings,
        player: player,
        spectrum: spectrum,
      );
    });

    tearDown(() {
      spectrum.dispose();
    });

    test('applyMergedAudioFilters confirms spectrum when wanted', () async {
      settings.experimentalFeaturesEnabled = true;
      settings.audioWaveformEnabled = true;
      player.beginSourceLoad(PlayableSource.file('/tmp/song.mp3'), 'mp3');
      await spectrum.start();

      final result = await session.applyMergedAudioFilters();
      expect(result.spectrumInstalled || result.needsSpectrumConfirm, isTrue);
      expect(spectrum.isFilterInstalled, isTrue);
      expect(playerService.lastAf, contains('dacxb0'));
    });

    test('spectrumWanted is false when mix is enabled', () async {
      settings.experimentalFeaturesEnabled = true;
      settings.audioWaveformEnabled = true;
      settings.multiAudioMix = true;
      player.beginSourceLoad(PlayableSource.file('/tmp/song.mp3'), 'mp3');
      await spectrum.start();
      expect(session.spectrumWanted, isFalse);
    });

    test('syncSpectrum starts when playing audio with visualizer on', () async {
      settings.experimentalFeaturesEnabled = true;
      settings.audioWaveformEnabled = true;
      player.beginSourceLoad(PlayableSource.file('/tmp/song.mp3'), 'mp3');
      session.syncSpectrum(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(spectrum.isActive, isTrue);
    });
  });
}
