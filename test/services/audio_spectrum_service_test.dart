import 'dart:async';

import 'package:dacx/services/audio_spectrum_service.dart';
import 'package:dacx/services/player_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake that satisfies the AudioSpectrumService contract without
/// requiring native libmpv. Only [getProperty] and [isDisposed] are used
/// during polling.
class _FakePlayerService implements PlayerService {
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
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('afSegment contains label and astats config', () {
      expect(AudioSpectrumService.afSegment, contains('@dacxstats:'));
      expect(AudioSpectrumService.afSegment, contains('lavfi='));
      expect(AudioSpectrumService.afSegment, contains('astats='));
      expect(AudioSpectrumService.afSegment, contains('metadata=1'));
      expect(AudioSpectrumService.afSegment, contains('reset=1'));
    });

    test('initial state is inactive with zero bands', () {
      expect(service.isActive, isFalse);
      expect(service.isFilterInstalled, isFalse);
      expect(service.currentSpectrum, everyElement(0.0));
      expect(service.currentSpectrum.length, 16);
    });

    test(
      'start activates but does not install filter or begin polling',
      () async {
        await service.start();
        expect(service.isActive, isTrue);
        expect(service.isFilterInstalled, isFalse);
      },
    );

    test('confirmFilterInstalled enables polling', () async {
      await service.start();
      service.confirmFilterInstalled();
      expect(service.isFilterInstalled, isTrue);
    });

    test('confirmFilterFailed prevents polling', () async {
      await service.start();
      service.confirmFilterFailed();
      expect(service.isFilterInstalled, isFalse);
      expect(service.isActive, isTrue);
    });

    test('stop resets state and emits zeros', () async {
      final emissions = <List<double>>[];
      final sub = service.spectrumStream.listen(emissions.add);

      await service.start();
      service.confirmFilterInstalled();
      await service.stop();

      expect(service.isActive, isFalse);
      expect(service.isFilterInstalled, isFalse);

      // Should have emitted a zeroed-out list on stop.
      expect(emissions, isNotEmpty);
      expect(emissions.last, everyElement(0.0));

      await sub.cancel();
    });

    test('markFilterDirty pauses polling until re-confirmed', () async {
      await service.start();
      service.confirmFilterInstalled();
      expect(service.isFilterInstalled, isTrue);

      service.markFilterDirty();
      expect(service.isFilterInstalled, isFalse);

      service.confirmFilterInstalled();
      expect(service.isFilterInstalled, isTrue);
    });

    test('resetDynamics zeros all bands', () async {
      await service.start();
      service.confirmFilterInstalled();

      // Simulate some energy by feeding metadata.
      fakePlayer
              .properties['af-metadata/dacxstats/lavfi.astats.Overall.RMS_level'] =
          '-10.0';
      fakePlayer
              .properties['af-metadata/dacxstats/lavfi.astats.Overall.Peak_level'] =
          '-5.0';

      // Wait for a poll cycle.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      service.resetDynamics();
      expect(service.currentSpectrum, everyElement(0.0));
    });

    test('polling emits non-zero values when metadata is available', () async {
      fakePlayer
              .properties['af-metadata/dacxstats/lavfi.astats.Overall.RMS_level'] =
          '-12.0';
      fakePlayer
              .properties['af-metadata/dacxstats/lavfi.astats.Overall.Peak_level'] =
          '-8.0';
      fakePlayer.properties['af-metadata/dacxstats/lavfi.astats.1.RMS_level'] =
          '-14.0';
      fakePlayer.properties['af-metadata/dacxstats/lavfi.astats.2.RMS_level'] =
          '-10.0';

      final emissions = <List<double>>[];
      final sub = service.spectrumStream.listen(emissions.add);

      await service.start();
      service.confirmFilterInstalled();

      // Wait for at least 2 poll cycles.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(emissions, isNotEmpty);
      // At least some bands should have energy > 0.
      expect(emissions.last.any((v) => v > 0.0), isTrue);

      await sub.cancel();
    });

    test('polling does not emit when player is disposed', () async {
      fakePlayer
              .properties['af-metadata/dacxstats/lavfi.astats.Overall.RMS_level'] =
          '-10.0';
      fakePlayer._disposed = true;

      final emissions = <List<double>>[];
      final sub = service.spectrumStream.listen(emissions.add);

      await service.start();
      service.confirmFilterInstalled();

      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Should not have emitted since player is disposed.
      expect(emissions, isEmpty);

      await sub.cancel();
    });

    test('polling does not emit when metadata returns null', () async {
      // No properties set — all getProperty calls return null.
      final emissions = <List<double>>[];
      final sub = service.spectrumStream.listen(emissions.add);

      await service.start();
      service.confirmFilterInstalled();

      await Future<void>.delayed(const Duration(milliseconds: 60));

      // No emissions because all metadata returned null.
      expect(emissions, isEmpty);

      await sub.cancel();
    });

    test('dispose stops everything and closes stream', () async {
      await service.start();
      service.confirmFilterInstalled();
      service.dispose();

      expect(service.isActive, isFalse);
      expect(service.isFilterInstalled, isFalse);
    });

    test('start is idempotent when already active', () async {
      await service.start();
      await service.start();
      expect(service.isActive, isTrue);
    });
  });
}
