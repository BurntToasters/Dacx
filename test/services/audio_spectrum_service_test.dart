import 'package:dacx/services/audio_spectrum_service.dart';
import 'package:dacx/services/player_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlayerService implements IPlayerService {
  final Map<String, String?> properties = {};
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<String?> getProperty(String name) async => properties[name];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('AudioSpectrumService', () {
    late _FakePlayerService fakePlayer;
    late AudioSpectrumService service;

    setUp(() {
      fakePlayer = _FakePlayerService();
      service = AudioSpectrumService(
        playerService: fakePlayer,
        bandCount: 16,
        pollInterval: const Duration(milliseconds: 20),
        probeFailLimit: 3,
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('afSegment contains labeled multiband astats filters', () {
      expect(AudioSpectrumService.afSegment, contains('@dacxb0:'));
      expect(AudioSpectrumService.afSegment, contains('@dacxb3:'));
      expect(AudioSpectrumService.afSegment, contains('lavfi='));
      expect(AudioSpectrumService.afSegment, contains('astats='));
      expect(AudioSpectrumService.afSegments, hasLength(4));
    });

    test('initial state is inactive with zero bands', () {
      expect(service.isActive, isFalse);
      expect(service.isFilterInstalled, isFalse);
      expect(service.currentSpectrum, everyElement(0.0));
      expect(service.currentSpectrum.length, 16);
    });

    test('start activates but does not begin polling', () async {
      await service.start();
      expect(service.isActive, isTrue);
      expect(service.isFilterInstalled, isFalse);
    });

    test('confirmFilterInstalled enables polling', () async {
      await service.start();
      service.confirmFilterInstalled();
      expect(service.isFilterInstalled, isTrue);
    });

    test('stop resets state and emits zeros', () async {
      final emissions = <List<double>>[];
      final sub = service.spectrumStream.listen(emissions.add);

      await service.start();
      service.confirmFilterInstalled();
      await service.stop();

      expect(service.isActive, isFalse);
      expect(emissions, isNotEmpty);
      expect(emissions.last, everyElement(0.0));
      await sub.cancel();
    });

    test('markFilterDirty pauses polling until re-confirmed', () async {
      await service.start();
      service.confirmFilterInstalled();
      service.markFilterDirty();
      expect(service.isFilterInstalled, isFalse);
      service.confirmFilterInstalled();
      expect(service.isFilterInstalled, isTrue);
    });

    test('resetDynamics zeros and emits', () async {
      final emissions = <List<double>>[];
      final sub = service.spectrumStream.listen(emissions.add);
      await service.start();
      service.resetDynamics();
      expect(service.currentSpectrum, everyElement(0.0));
      expect(emissions.last, everyElement(0.0));
      await sub.cancel();
    });

    test('polling emits when multiband metadata is available', () async {
      fakePlayer
              .properties['af-metadata/dacxb0/lavfi.astats.Overall.RMS_level'] =
          '-8.0';
      fakePlayer
              .properties['af-metadata/dacxb1/lavfi.astats.Overall.RMS_level'] =
          '-12.0';
      fakePlayer
              .properties['af-metadata/dacxb2/lavfi.astats.Overall.RMS_level'] =
          '-18.0';
      fakePlayer
              .properties['af-metadata/dacxb3/lavfi.astats.Overall.RMS_level'] =
          '-25.0';

      final emissions = <List<double>>[];
      final sub = service.spectrumStream.listen(emissions.add);

      await service.start();
      service.confirmFilterInstalled();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(emissions, isNotEmpty);
      expect(emissions.last.any((v) => v > 0.0), isTrue);
      // Bass band (index 0) should trend higher than treble for these dB values.
      expect(emissions.last.first, greaterThan(emissions.last.last));
      await sub.cancel();
    });

    test('capabilityFailed after repeated empty polls', () async {
      await service.start();
      service.confirmFilterInstalled();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.capabilityFailed, isTrue);
      expect(service.isFilterInstalled, isFalse);
    });

    test('dispose stops everything', () async {
      await service.start();
      service.confirmFilterInstalled();
      service.dispose();
      expect(service.isActive, isFalse);
    });
  });
}
