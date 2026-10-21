import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/packaged_e2e_probe.dart';

void main() {
  test('packaged probe writes a version-bound real playback receipt', () async {
    final root = await Directory.systemTemp.createTemp('dacx-packaged-probe-');
    addTearDown(() => root.delete(recursive: true));
    final fixture = File('${root.path}${Platform.pathSeparator}fixture.wav')
      ..writeAsBytesSync(List<int>.generate(128, (index) => index));
    final report = File('${root.path}${Platform.pathSeparator}receipt.json');
    final player = HeadlessPlayerService();
    final probe = PackagedE2eProbe(
      player: player,
      reportPath: report.path,
      expectedVersion: '1.0.0-beta.1',
      runId: 'probe-e2e-run',
      fixturePath: fixture.path,
      installedVersion: () async => '1.0.0-beta.1',
    );

    await probe.recordDuration(const Duration(seconds: 6));
    expect(report.existsSync(), isFalse);
    await probe.recordPlaying(true);

    final decoded =
        jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['schema'], 'dacx.e2e.desktop-playback.v1');
    expect(decoded['version'], '1.0.0-beta.1');
    expect(decoded['runId'], 'probe-e2e-run');
    expect(decoded['status'], 'passed');
    expect(decoded['releaseProof'], isTrue);
    expect(decoded['checks']['durationMs'], 6000);
    expect(decoded['checks']['playing'], isTrue);
    expect(decoded['checks']['error'], isNull);
    expect(decoded['checks']['advancedPlayback']['roundTrip'], isTrue);
    expect(decoded['fixture']['sha256'], hasLength(64));
    expect(player.properties['audio-delay'], '0');
    expect(player.properties['sub-delay'], '0');
  });

  test('packaged probe fails receipt on installed version mismatch', () async {
    final root = await Directory.systemTemp.createTemp('dacx-packaged-probe-');
    addTearDown(() => root.delete(recursive: true));
    final fixture = File('${root.path}${Platform.pathSeparator}fixture.wav')
      ..writeAsBytesSync(const [1, 2, 3]);
    final report = File('${root.path}${Platform.pathSeparator}receipt.json');
    final probe = PackagedE2eProbe(
      player: HeadlessPlayerService(),
      reportPath: report.path,
      expectedVersion: '1.0.0',
      runId: 'probe-version-mismatch',
      fixturePath: fixture.path,
      installedVersion: () async => '1.0.0-beta.1',
    );

    await probe.recordDuration(const Duration(seconds: 6));
    await probe.recordPlaying(true);

    final decoded =
        jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['status'], 'failed');
    expect(decoded['releaseProof'], isFalse);
    expect(decoded['checks']['installedVersion'], '1.0.0-beta.1');
  });

  test(
    'packaged probe invalidates proof after a later playback error',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dacx-packaged-probe-',
      );
      addTearDown(() => root.delete(recursive: true));
      final fixture = File('${root.path}${Platform.pathSeparator}fixture.wav')
        ..writeAsBytesSync(const [1, 2, 3]);
      final report = File('${root.path}${Platform.pathSeparator}receipt.json');
      final probe = PackagedE2eProbe(
        player: HeadlessPlayerService(),
        reportPath: report.path,
        expectedVersion: '1.0.0-beta.1',
        runId: 'probe-late-error',
        fixturePath: fixture.path,
        installedVersion: () async => '1.0.0-beta.1',
      );

      await probe.recordDuration(const Duration(seconds: 6));
      await probe.recordPlaying(true);
      probe.recordError(StateError('decoder stopped'));

      final decoded =
          jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['status'], 'failed');
      expect(decoded['releaseProof'], isFalse);
      expect(decoded['checks']['error'], contains('decoder stopped'));
    },
  );
}
