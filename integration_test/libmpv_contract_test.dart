import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/playback/audio_filter_chain.dart';
import 'package:dacx/playback/native_lib_policy.dart';
import 'package:dacx/services/equalizer_service.dart';
import 'package:dacx/services/player_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PlayerService service;
  late Directory dir;
  late String media;

  setUp(() async {
    final fixture = Platform.environment['DACX_E2E_FIXTURE'];
    if (fixture == null || fixture.trim().isEmpty) {
      fail('DACX_E2E_FIXTURE is required');
    }
    MediaKit.ensureInitialized();
    dir = Directory.systemTemp.createTempSync('dacx-libmpv-');
    media = p.join(dir.path, 'media.wav');
    File(fixture).copySync(media);
    service = PlayerService();
  });

  tearDown(() async {
    await service.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<int> trackCount() async =>
      int.tryParse(await service.getProperty('track-list/count') ?? '') ?? -1;

  Future<void> openAndSettle(WidgetTester tester, String path) async {
    await tester.runAsync(() async {
      await service.open(path, play: false);
      for (var i = 0; i < 50 && await trackCount() < 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
  }

  testWidgets('bundled FFmpeg meets the refresh policy', (tester) async {
    await openAndSettle(tester, media);
    final ffmpeg = await tester.runAsync(
      () => service.getProperty('ffmpeg-version'),
    );
    final mpv = await tester.runAsync(() => service.getProperty('mpv-version'));
    debugPrint('libmpv contract: $mpv, FFmpeg $ffmpeg');
    expect(
      NativeLibPolicy.acceptsFfmpeg(ffmpeg, os: Platform.operatingSystem),
      isTrue,
      reason: 'FFmpeg $ffmpeg is older than the bundled-library policy',
    );
  });

  testWidgets('external subtitle and audio attach to the current file', (
    tester,
  ) async {
    await openAndSettle(tester, media);
    final srt = File(p.join(dir.path, 'extra.srt'))
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:05,000\ncontract\n');
    final audio = p.join(dir.path, 'extra.wav');
    File(media).copySync(audio);
    final before = (await tester.runAsync(trackCount))!;
    expect(before, greaterThan(0));
    expect(
      await tester.runAsync(() => service.addExternalSubtitle(srt.path)),
      isTrue,
    );
    expect(await tester.runAsync(trackCount), before + 1);
    expect(
      await tester.runAsync(() => service.addExternalAudio(audio)),
      isTrue,
    );
    expect(await tester.runAsync(trackCount), before + 2);
    final missing = p.join(dir.path, 'missing.srt');
    expect(
      await tester.runAsync(() => service.addExternalSubtitle(missing)),
      isFalse,
    );
    expect(await tester.runAsync(trackCount), before + 2);
  });

  testWidgets('enabling then disabling the equalizer clears af', (
    tester,
  ) async {
    await openAndSettle(tester, media);
    final bands = kEqPresets.firstWhere((p) => p.id == 'bass_boost').gains;
    final enabled = (await tester.runAsync(
      () => AudioFilterChain.apply(
        lastAppliedChain: null,
        eqEnabled: true,
        eqBands: bands,
        setAudioFilter: service.setAudioFilter,
      ),
    ))!;
    expect(enabled.failed, isFalse);
    expect(await tester.runAsync(() => service.getProperty('af')), isNotEmpty);
    final disabled = (await tester.runAsync(
      () => AudioFilterChain.apply(
        lastAppliedChain: enabled.appliedChain,
        eqEnabled: false,
        eqBands: bands,
        setAudioFilter: service.setAudioFilter,
      ),
    ))!;
    expect(disabled.failed, isFalse);
    expect(await tester.runAsync(() => service.getProperty('af')), '');
  });
}
