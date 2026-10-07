import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';

/// Real desktop player smoke. Run with:
///
///   DACX_E2E_FIXTURE=/abs/release-smoke.wav \
///   DACX_E2E_VERSION=1.0.0 \
///   DACX_E2E_RUN_ID=desktop-run-1 \
///   DACX_E2E_REPORT=test-results/e2e/windows/report.json \
///   fvm flutter test integration_test/platform_release_smoke_test.dart -d windows
///
/// Package proof tooling launches a packaged executable with the same fixture;
/// this test proves media_kit opens and plays it inside a real runner.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop package opens and plays deterministic fixture', (
    tester,
  ) async {
    final fixture = Platform.environment['DACX_E2E_FIXTURE'];
    final version = Platform.environment['DACX_E2E_VERSION'];
    final runId = Platform.environment['DACX_E2E_RUN_ID'];
    final reportPath = Platform.environment['DACX_E2E_REPORT'];
    if (fixture == null || fixture.trim().isEmpty) {
      fail('DACX_E2E_FIXTURE is required for release E2E');
    }
    if (version == null || version.trim().isEmpty) {
      fail('DACX_E2E_VERSION is required for release E2E');
    }
    if (runId == null || runId.trim().isEmpty) {
      fail('DACX_E2E_RUN_ID is required for release E2E');
    }
    final fixtureFile = File(fixture);
    if (!fixtureFile.existsSync()) fail('Fixture does not exist: $fixture');

    MediaKit.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final debugLog = DebugLogService(isEnabled: () => false);
    final updates = UpdateService(
      debugLog: debugLog,
      debugSource: 'platform_release_smoke',
      httpGet: (_, {headers}) async => throw StateError('offline in E2E'),
    );
    final player = PlayerService();
    var duration = Duration.zero;
    var playing = false;
    var error = <String, Object?>{};
    final subscriptions = <StreamSubscription<dynamic>>[
      player.durationStream.listen((value) => duration = value),
      player.playingStream.listen((value) => playing = value),
      player.errorStream.listen(
        (value) => error = {
          'operation': value.operation,
          'error': value.error.toString(),
        },
      ),
    ];

    runApp(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlayerScreen(
          settings: settings,
          debugLog: debugLog,
          updateService: updates,
          playerService: player,
          initialFile: fixture,
        ),
      ),
    );

    for (var i = 0; i < 100 && duration <= Duration.zero; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 30 && !playing; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Exercise the same native mpv property boundary used by opt-in advanced
    // playback. Keep this opt-in so the default smoke remains minimalist.
    settings.advancedPlaybackToolsEnabled = true;
    await tester.pumpAndSettle();
    final audioSet = await player.setProperty('audio-delay', '0.100');
    final subtitleSet = await player.setProperty('sub-delay', '-0.100');
    final audioRead = await player.getProperty('audio-delay');
    final subtitleRead = await player.getProperty('sub-delay');
    final advancedRoundTrip =
        settings.advancedPlaybackToolsEnabled &&
        audioSet &&
        subtitleSet &&
        _matchesPropertyValue(audioRead, 0.100) &&
        _matchesPropertyValue(subtitleRead, -0.100);
    // Transport boundary through real libmpv. The widget suite fakes
    // PlayerService, so volume, rate, pause, seek, and completion are only
    // proven here.
    final transport = await _exerciseTransport(tester, player);
    final passed =
        duration > Duration.zero &&
        playing &&
        error.isEmpty &&
        advancedRoundTrip &&
        transport['passed'] == true;
    final report = <String, Object?>{
      'schema': 'dacx.e2e.desktop-playback.v1',
      'version': version,
      'runId': runId,
      'status': passed ? 'passed' : 'failed',
      'releaseProof': passed,
      'platform': Platform.operatingSystem,
      'host': {'os': Platform.operatingSystem, 'runtime': Platform.version},
      'fixture': {
        'path': fixtureFile.absolute.path,
        'bytes': fixtureFile.lengthSync(),
        'sha256': sha256.convert(fixtureFile.readAsBytesSync()).toString(),
      },
      'checks': {
        'durationMs': duration.inMilliseconds,
        'playing': playing,
        'error': error.isEmpty ? null : error,
        'advancedPlayback': {
          'enabled': settings.advancedPlaybackToolsEnabled,
          'audioDelaySet': audioSet,
          'audioDelayRead': audioRead,
          'subtitleDelaySet': subtitleSet,
          'subtitleDelayRead': subtitleRead,
          'roundTrip': advancedRoundTrip,
        },
        'transport': transport,
      },
    };
    final output = reportPath == null || reportPath.trim().isEmpty
        ? File('test-results/e2e/${Platform.operatingSystem}/report.json')
        : File(reportPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );

    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    settings.dispose();
    if (!passed) {
      fail('Desktop fixture playback failed; report: ${output.path}');
    }
  });
}

Future<Map<String, Object?>> _exerciseTransport(
  WidgetTester tester,
  PlayerService player,
) async {
  var volume = -1.0;
  var playing = true;
  var position = Duration.zero;
  var completed = false;
  final subscriptions = <StreamSubscription<dynamic>>[
    player.volumeStream.listen((value) => volume = value),
    player.playingStream.listen((value) => playing = value),
    player.positionStream.listen((value) => position = value),
    player.completedStream.listen((value) {
      if (value) completed = true;
    }),
  ];
  Future<void> pumpUntil(bool Function() done, {int maxTicks = 50}) async {
    for (var i = 0; i < maxTicks && !done(); i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  try {
    // A saved loop mode would suppress completion; force a single pass.
    await player.setPlaylistMode(PlaylistMode.none);

    await player.setVolume(42);
    await pumpUntil(() => (volume - 42).abs() < 0.5);
    final volumeOk = (volume - 42).abs() < 0.5;

    await player.setRate(1.5);
    final speedRead = await player.getProperty('speed');
    final rateOk = _matchesPropertyValue(speedRead, 1.5);

    await player.pause();
    await pumpUntil(() => !playing);
    final pauseOk = !playing;

    const seekTarget = Duration(seconds: 3);
    const seekTolerance = Duration(milliseconds: 500);
    await player.seek(seekTarget);
    await pumpUntil(() => (position - seekTarget).abs() < seekTolerance);
    final seekPosition = position;
    final seekOk = (seekPosition - seekTarget).abs() < seekTolerance;

    // About 3s of fixture left at 1.5x; allow 8s before calling it failed.
    await player.play();
    await pumpUntil(() => completed, maxTicks: 80);

    return {
      'volumeSet': 42,
      'volumeObserved': volume,
      'volumeOk': volumeOk,
      'speedRead': speedRead,
      'rateOk': rateOk,
      'pauseOk': pauseOk,
      'seekTargetMs': seekTarget.inMilliseconds,
      'seekObservedMs': seekPosition.inMilliseconds,
      'seekOk': seekOk,
      'completed': completed,
      'passed': volumeOk && rateOk && pauseOk && seekOk && completed,
    };
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

bool _matchesPropertyValue(String? value, double expected) {
  final actual = double.tryParse(value?.trim() ?? '');
  return actual != null && (actual - expected).abs() < 0.001;
}
