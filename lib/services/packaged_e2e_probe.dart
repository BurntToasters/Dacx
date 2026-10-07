import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'player_service.dart';

/// Opt-in release-candidate probe used by packaged E2E automation.
///
/// Normal launches never create this probe. The package harness must provide
/// every `DACX_E2E_*` value and explicitly set `DACX_E2E_PACKAGED_PROBE=1`.
class PackagedE2eProbe {
  PackagedE2eProbe({
    required this._player,
    required this.reportPath,
    required this.expectedVersion,
    required this.runId,
    required this.fixturePath,
    required this._installedVersion,
  });

  final IPlayerService _player;
  final Future<String> Function() _installedVersion;
  final String reportPath;
  final String expectedVersion;
  final String runId;
  final String fixturePath;

  Duration _duration = Duration.zero;
  bool _playing = false;
  String? _error;
  bool _completing = false;
  bool _completed = false;
  Map<String, Object?>? _lastReport;

  static Future<PackagedE2eProbe?> fromEnvironment({
    required IPlayerService player,
  }) async {
    final environment = Platform.environment;
    if (environment['DACX_E2E_PACKAGED_PROBE'] != '1') return null;
    final report = environment['DACX_E2E_REPORT']?.trim() ?? '';
    final version = environment['DACX_E2E_VERSION']?.trim() ?? '';
    final run = environment['DACX_E2E_RUN_ID']?.trim() ?? '';
    final fixture = environment['DACX_E2E_FIXTURE']?.trim() ?? '';
    if (report.isEmpty || version.isEmpty || run.isEmpty || fixture.isEmpty) {
      return null;
    }
    return PackagedE2eProbe(
      player: player,
      reportPath: report,
      expectedVersion: version,
      runId: run,
      fixturePath: fixture,
      installedVersion: () async => (await PackageInfo.fromPlatform()).version,
    );
  }

  Future<void> recordDuration(Duration value) async {
    if (value > _duration) _duration = value;
    await _maybeComplete();
  }

  Future<void> recordPlaying(bool value) async {
    _playing = value;
    await _maybeComplete();
  }

  void recordError(Object value) {
    _error ??= value.toString();
    final previous = _lastReport;
    if (!_completed || previous == null) return;
    final previousChecks = previous['checks'];
    final checks = previousChecks is Map
        ? Map<String, Object?>.from(previousChecks)
        : <String, Object?>{};
    checks['error'] = _error;
    try {
      _writeReport({
        ...previous,
        'status': 'failed',
        'releaseProof': false,
        'checks': checks,
      });
    } on FileSystemException {
      // Remove stale passing proof if invalidation cannot be persisted.
      final output = File(reportPath);
      if (output.existsSync()) output.deleteSync();
    }
  }

  Future<void> _maybeComplete() async {
    if (_completed || _completing || !_playing || _duration <= Duration.zero) {
      return;
    }
    _completing = true;
    var audioSet = false;
    var subtitleSet = false;
    String? audioRead;
    String? subtitleRead;
    String installed = '';
    try {
      installed = await _installedVersion();
      audioSet = await _player.setProperty('audio-delay', '0.100');
      subtitleSet = await _player.setProperty('sub-delay', '-0.100');
      audioRead = await _player.getProperty('audio-delay');
      subtitleRead = await _player.getProperty('sub-delay');
      final advancedRoundTrip =
          audioSet &&
          subtitleSet &&
          _matchesValue(audioRead, 0.100) &&
          _matchesValue(subtitleRead, -0.100);
      final fixture = File(fixturePath);
      final fixtureExists = fixture.existsSync();
      final versionMatches = installed == expectedVersion;
      final passed =
          fixtureExists &&
          versionMatches &&
          _error == null &&
          advancedRoundTrip;
      final report = <String, Object?>{
        'schema': 'dacx.e2e.desktop-playback.v1',
        'version': expectedVersion,
        'runId': runId,
        'status': passed ? 'passed' : 'failed',
        'releaseProof': passed,
        'platform': Platform.operatingSystem,
        'host': {'os': Platform.operatingSystem, 'runtime': Platform.version},
        'fixture': {
          'path': fixture.absolute.path,
          'bytes': fixtureExists ? fixture.lengthSync() : 0,
          'sha256': fixtureExists
              ? sha256.convert(fixture.readAsBytesSync()).toString()
              : null,
        },
        'checks': {
          'durationMs': _duration.inMilliseconds,
          'playing': _playing,
          'error': _error,
          'installedVersion': installed,
          'versionMatches': versionMatches,
          'advancedPlayback': {
            'audioDelaySet': audioSet,
            'audioDelayRead': audioRead,
            'subtitleDelaySet': subtitleSet,
            'subtitleDelayRead': subtitleRead,
            'roundTrip': advancedRoundTrip,
          },
        },
      };
      _writeReport(report);
      _completed = true;
    } catch (error) {
      _error ??= error.toString();
      _writeReport({
        'schema': 'dacx.e2e.desktop-playback.v1',
        'version': expectedVersion,
        'runId': runId,
        'status': 'failed',
        'releaseProof': false,
        'platform': Platform.operatingSystem,
        'checks': {
          'durationMs': _duration.inMilliseconds,
          'playing': _playing,
          'error': _error,
          'installedVersion': installed,
        },
      });
      _completed = true;
    } finally {
      await _player.setProperty('audio-delay', '0');
      await _player.setProperty('sub-delay', '0');
      _completing = false;
    }
  }

  void _writeReport(Map<String, Object?> report) {
    final output = File(reportPath);
    output.parent.createSync(recursive: true);
    final temporary = File('$reportPath.tmp-$pid');
    temporary.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    if (output.existsSync()) output.deleteSync();
    temporary.renameSync(output.path);
    _lastReport = report;
  }

  static bool _matchesValue(String? value, double expected) {
    final actual = double.tryParse(value?.trim() ?? '');
    return actual != null && (actual - expected).abs() < 0.001;
  }
}
