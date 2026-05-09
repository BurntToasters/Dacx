import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'debug_log_service.dart';
import 'update_service.dart';

typedef HttpStreamFn =
    Future<http.StreamedResponse> Function(http.BaseRequest request);
typedef HttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});
typedef ProcessRunFn =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef ProcessStartFn =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
    });

enum SelfUpdateOutcome {
  unsupportedPlatform,
  missingAsset,
  missingChecksums,
  downloadFailed,
  checksumMismatch,
  extractionFailed,
  signatureInvalid,
  notarizationInvalid,
  teamIdMismatch,
  gatekeeperRejected,
  spawnFailed,
  spawned,
}

class SelfUpdateResult {
  final SelfUpdateOutcome outcome;
  final String? message;
  const SelfUpdateResult(this.outcome, {this.message});
}

class SelfUpdateProgress {
  final int downloadedBytes;
  final int? totalBytes;
  const SelfUpdateProgress(this.downloadedBytes, this.totalBytes);
  double? get fraction =>
      totalBytes != null && totalBytes! > 0 ? downloadedBytes / totalBytes! : null;
}

class SelfUpdateService {
  /// Expected Apple Developer Team ID, baked in at build time via
  /// `--dart-define=DACX_APPLE_TEAM_ID=...`. Sourced from APPLE_TEAM_ID in
  /// `.env` by `scripts/flutter-build-macos.js`. Empty means unconfigured —
  /// macOS self-update is disabled in that case (returns
  /// `gatekeeperRejected` with a clear message).
  static const String expectedTeamId = String.fromEnvironment(
    'DACX_APPLE_TEAM_ID',
    defaultValue: '',
  );
  static const String _macInstallPath = '/Applications/Dacx.app';

  static const Set<String> _allowedHosts = {
    'github.com',
    'www.github.com',
    'objects.githubusercontent.com',
  };

  final DebugLogService? _debugLog;
  final HttpGet _httpGet;
  final HttpStreamFn _httpStream;
  final ProcessRunFn _processRun;
  final ProcessStartFn _processStart;

  SelfUpdateService({
    DebugLogService? debugLog,
    HttpGet? httpGet,
    HttpStreamFn? httpStream,
    ProcessRunFn? processRun,
    ProcessStartFn? processStart,
  }) : _debugLog = debugLog,
       _httpGet = httpGet ?? http.get,
       _httpStream = httpStream ?? _defaultStream,
       _processRun = processRun ?? Process.run,
       _processStart = processStart ?? Process.start;

  static Future<http.StreamedResponse> _defaultStream(
    http.BaseRequest request,
  ) {
    return request.send();
  }

  void _log(
    String event, {
    String? message,
    Map<String, Object?> Function()? detailsBuilder,
    DebugSeverity severity = DebugSeverity.info,
  }) {
    final log = _debugLog;
    if (log == null || !log.isEnabled) return;
    log.logLazy(
      category: DebugLogCategory.update,
      event: event,
      messageBuilder: message == null ? null : () => message,
      detailsBuilder: detailsBuilder,
      severity: severity,
    );
  }

  /// Returns true on Windows or macOS only — the platforms where self-update
  /// is implemented. Linux and others fall back to the existing "View" link.
  static bool isSupported() => Platform.isWindows || Platform.isMacOS;

  /// Picks the asset whose name ends with [suffix] (case-insensitive).
  /// Returns null if no match is found.
  static UpdateAsset? pickAsset(List<UpdateAsset> assets, String suffix) {
    final lowerSuffix = suffix.toLowerCase();
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith(lowerSuffix)) return a;
    }
    return null;
  }

  /// Picks the asset whose name matches [pattern] (case-insensitive).
  /// Returns null if no match is found.
  static UpdateAsset? pickAssetByPattern(
    List<UpdateAsset> assets,
    RegExp pattern,
  ) {
    for (final a in assets) {
      if (pattern.hasMatch(a.name)) return a;
    }
    return null;
  }

  /// Looks up the SHA256 hex digest for [assetName] inside SHA256SUMS-style
  /// text content. Format: `<64-hex>  <filename>` per POSIX (two spaces).
  /// Returns null if not found or content is malformed.
  static String? parseChecksumsFile(String text, String assetName) {
    final target = p.basename(assetName);
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      // Split on whitespace; first token is hash, last is filename.
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final hash = parts.first;
      final name = parts.last;
      if (hash.length != 64) continue;
      if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hash)) continue;
      if (p.basename(name) == target) return hash.toLowerCase();
    }
    return null;
  }

  static bool _isAllowedHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return _allowedHosts.contains(uri.host.toLowerCase());
  }

  /// Cross-platform "Dacx update cache" dir. Mirrors the env-var pattern used
  /// by [InstanceModeService] rather than pulling in path_provider.
  static Directory updateCacheDir() {
    final env = Platform.environment;
    String? base;
    if (Platform.isWindows) {
      base = env['LOCALAPPDATA'];
      if (base != null && base.isNotEmpty) {
        return Directory(p.join(base, 'Dacx', 'updates'));
      }
    } else if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(p.join(home, 'Library', 'Caches', 'Dacx', 'updates'));
      }
    } else if (Platform.isLinux) {
      final cache = env['XDG_CACHE_HOME'];
      if (cache != null && cache.isNotEmpty) {
        return Directory(p.join(cache, 'dacx', 'updates'));
      }
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(p.join(home, '.cache', 'dacx', 'updates'));
      }
    }
    return Directory(p.join(Directory.systemTemp.path, 'dacx-updates'));
  }

  /// Downloads [url] to [outFile] streaming, calling [onProgress] periodically.
  /// Throws on HTTP error.
  Future<void> _downloadTo(
    String url,
    File outFile, {
    void Function(SelfUpdateProgress)? onProgress,
  }) async {
    if (!_isAllowedHost(url)) {
      throw StateError('Refusing to download from non-allowlisted host: $url');
    }
    await outFile.parent.create(recursive: true);
    final request = http.Request('GET', Uri.parse(url));
    final resp = await _httpStream(request).timeout(const Duration(minutes: 5));
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode} from $url');
    }
    final total = resp.contentLength;
    var downloaded = 0;
    final sink = outFile.openWrite();
    try {
      await resp.stream.listen(
        (chunk) {
          sink.add(chunk);
          downloaded += chunk.length;
          onProgress?.call(SelfUpdateProgress(downloaded, total));
        },
      ).asFuture<void>();
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Computes hex SHA256 of [file] by streaming the bytes through digest.
  Future<String> _computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  /// Fetches [url] as text. Throws on HTTP error.
  Future<String> _fetchText(String url) async {
    if (!_isAllowedHost(url)) {
      throw StateError('Refusing to fetch from non-allowlisted host: $url');
    }
    final resp = await _httpGet(Uri.parse(url)).timeout(
      const Duration(seconds: 30),
    );
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode} from $url');
    }
    return resp.body;
  }

  /// Top-level orchestrator. On success returns [SelfUpdateOutcome.spawned]
  /// — caller should then call `exit(0)` (the spawned helper/watchdog has
  /// taken over).
  Future<SelfUpdateResult> applyUpdate(
    UpdateInfo info, {
    void Function(SelfUpdateProgress)? onProgress,
  }) async {
    if (!isSupported()) {
      return const SelfUpdateResult(SelfUpdateOutcome.unsupportedPlatform);
    }
    try {
      if (Platform.isWindows) {
        return await _applyWindows(info, onProgress: onProgress);
      }
      if (Platform.isMacOS) {
        return await _applyMacos(info, onProgress: onProgress);
      }
      return const SelfUpdateResult(SelfUpdateOutcome.unsupportedPlatform);
    } catch (e, st) {
      _log(
        'self_update_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
        detailsBuilder: () => {'stack': st.toString()},
      );
      return SelfUpdateResult(
        SelfUpdateOutcome.spawnFailed,
        message: e.toString(),
      );
    }
  }

  // ─────────────────────────────────────────────── Windows path

  Future<SelfUpdateResult> _applyWindows(
    UpdateInfo info, {
    void Function(SelfUpdateProgress)? onProgress,
  }) async {
    final asset = pickAsset(info.assets, '.msi');
    final checksums = pickAsset(info.assets, 'SHA256SUMS-Windows-x64.txt');
    if (asset == null) {
      return const SelfUpdateResult(SelfUpdateOutcome.missingAsset);
    }
    if (checksums == null) {
      return const SelfUpdateResult(SelfUpdateOutcome.missingChecksums);
    }

    final cacheDir = updateCacheDir();
    final msiPath = File(p.join(cacheDir.path, asset.name));

    String checksumsBody;
    try {
      await _downloadTo(asset.downloadUrl, msiPath, onProgress: onProgress);
      checksumsBody = await _fetchText(checksums.downloadUrl);
    } catch (e) {
      return SelfUpdateResult(
        SelfUpdateOutcome.downloadFailed,
        message: e.toString(),
      );
    }

    final expectedHash = parseChecksumsFile(checksumsBody, asset.name);
    if (expectedHash == null) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'No entry for asset in SHA256SUMS file',
      );
    }
    final actualHash = await _computeSha256(msiPath);
    if (actualHash != expectedHash) {
      return SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'expected $expectedHash, got $actualHash',
      );
    }

    // Watchdog .cmd polls until our PID exits, then runs msiexec.
    final cmdPath = File(p.join(cacheDir.path, 'apply-update.cmd'));
    await cmdPath.writeAsString(_buildWindowsWatchdogCmd());
    try {
      await _processStart(
        cmdPath.path,
        [pid.toString(), msiPath.path],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      return SelfUpdateResult(
        SelfUpdateOutcome.spawnFailed,
        message: e.toString(),
      );
    }
    _log(
      'self_update_spawned',
      detailsBuilder: () => {
        'platform': 'windows',
        'msi': msiPath.path,
        'pid': pid,
      },
    );
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  static String _buildWindowsWatchdogCmd() {
    return '@echo off\r\n'
        ':wait\r\n'
        'tasklist /FI "PID eq %1" 2>nul | find "%1" >nul && '
        '(timeout /t 1 /nobreak >nul & goto wait)\r\n'
        'start "" /wait msiexec.exe /i "%2" /passive /norestart\r\n';
  }

  // ─────────────────────────────────────────────── macOS path

  Future<SelfUpdateResult> _applyMacos(
    UpdateInfo info, {
    void Function(SelfUpdateProgress)? onProgress,
  }) async {
    if (expectedTeamId.isEmpty) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.gatekeeperRejected,
        message:
            'Self-update is misconfigured: DACX_APPLE_TEAM_ID was not set at build time.',
      );
    }
    // Match either `Dacx-macOS.zip` or `Dacx-<version>-macos.zip` (the
    // mac-codesign.sh produces the version-suffixed name).
    final asset =
        pickAsset(info.assets, '-macos.zip') ??
        pickAsset(info.assets, 'macos.zip') ??
        pickAssetByPattern(
          info.assets,
          RegExp(r'^Dacx-macOS\.zip$', caseSensitive: false),
        );
    final checksums = pickAsset(info.assets, 'SHA256SUMS-macOS.txt');
    if (asset == null) {
      return const SelfUpdateResult(SelfUpdateOutcome.missingAsset);
    }
    if (checksums == null) {
      return const SelfUpdateResult(SelfUpdateOutcome.missingChecksums);
    }

    final cacheDir = updateCacheDir();
    final zipFile = File(p.join(cacheDir.path, asset.name));

    String checksumsBody;
    try {
      await _downloadTo(asset.downloadUrl, zipFile, onProgress: onProgress);
      checksumsBody = await _fetchText(checksums.downloadUrl);
    } catch (e) {
      return SelfUpdateResult(
        SelfUpdateOutcome.downloadFailed,
        message: e.toString(),
      );
    }

    final expectedHash = parseChecksumsFile(checksumsBody, asset.name);
    if (expectedHash == null) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'No entry for asset in SHA256SUMS file',
      );
    }
    final actualHash = await _computeSha256(zipFile);
    if (actualHash != expectedHash) {
      return SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'expected $expectedHash, got $actualHash',
      );
    }

    final extractDir = Directory(p.join(cacheDir.path, 'extracted'));
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    await extractDir.create(recursive: true);
    final dittoResult = await _processRun('/usr/bin/ditto', [
      '-x',
      '-k',
      '--sequesterRsrc',
      zipFile.path,
      extractDir.path,
    ]);
    if (dittoResult.exitCode != 0) {
      return SelfUpdateResult(
        SelfUpdateOutcome.extractionFailed,
        message: dittoResult.stderr.toString(),
      );
    }

    final extractedAppPath = p.join(extractDir.path, 'Dacx.app');
    if (!Directory(extractedAppPath).existsSync()) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.extractionFailed,
        message: 'Dacx.app not found inside extracted zip',
      );
    }

    final validation = await _validateMacBundle(extractedAppPath);
    if (validation.outcome != SelfUpdateOutcome.spawned) {
      return validation;
    }

    final helperPath = _resolveMacHelperPath();
    if (helperPath == null || !File(helperPath).existsSync()) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.spawnFailed,
        message: 'Update helper binary not found inside running bundle',
      );
    }

    try {
      await _processStart(
        helperPath,
        [
          '--wait-pid',
          pid.toString(),
          '--new-app',
          extractedAppPath,
          '--install-path',
          _macInstallPath,
          '--expected-team-id',
          expectedTeamId,
          '--relaunch',
        ],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      return SelfUpdateResult(
        SelfUpdateOutcome.spawnFailed,
        message: e.toString(),
      );
    }
    _log(
      'self_update_spawned',
      detailsBuilder: () => {
        'platform': 'macos',
        'extracted': extractedAppPath,
        'install_path': _macInstallPath,
        'pid': pid,
      },
    );
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  /// Runs the four-stage Gatekeeper-respecting validation pipeline against
  /// the bundle at [appPath]. Returns SelfUpdateOutcome.spawned on full pass
  /// (sentinel meaning "ok to continue"); any other outcome is a failure.
  Future<SelfUpdateResult> _validateMacBundle(String appPath) async {
    // 1. stapler validate
    final stapler = await _processRun('/usr/bin/xcrun', [
      'stapler',
      'validate',
      appPath,
    ]);
    if (stapler.exitCode != 0) {
      return SelfUpdateResult(
        SelfUpdateOutcome.notarizationInvalid,
        message: stapler.stderr.toString(),
      );
    }
    // 2. codesign --verify --deep --strict
    final verify = await _processRun('/usr/bin/codesign', [
      '--verify',
      '--deep',
      '--strict',
      '--verbose=2',
      appPath,
    ]);
    if (verify.exitCode != 0) {
      return SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: verify.stderr.toString(),
      );
    }
    // 3. Team ID parse
    final dv = await _processRun('/usr/bin/codesign', [
      '-dv',
      '--verbose=4',
      appPath,
    ]);
    final dvOutput = '${dv.stdout}\n${dv.stderr}';
    final teamMatch = RegExp(
      r'^TeamIdentifier=([A-Za-z0-9]+)',
      multiLine: true,
    ).firstMatch(dvOutput);
    final actualTeamId = teamMatch?.group(1) ?? '';
    if (actualTeamId != expectedTeamId) {
      return SelfUpdateResult(
        SelfUpdateOutcome.teamIdMismatch,
        message: 'expected $expectedTeamId, got "$actualTeamId"',
      );
    }
    // 4. spctl --assess
    final spctl = await _processRun('/usr/sbin/spctl', [
      '--assess',
      '--type',
      'execute',
      '--verbose=2',
      appPath,
    ]);
    if (spctl.exitCode != 0) {
      return SelfUpdateResult(
        SelfUpdateOutcome.gatekeeperRejected,
        message: spctl.stderr.toString(),
      );
    }
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  static String? _resolveMacHelperPath() {
    final exe = Platform.resolvedExecutable;
    const marker = '.app/Contents/MacOS/';
    final idx = exe.indexOf(marker);
    if (idx < 0) return null;
    final macosDir = exe.substring(0, idx + marker.length - 1);
    return p.join(macosDir, 'dacx-update-helper');
  }
}

/// Persists "an update was just spawned" so the next launch can show a
/// success/failure snackbar. Format: JSON `{target_version, started_at_ms,
/// channel}`.
class UpdatePendingMarker {
  static const _fileName = 'update_pending.json';

  static File _file() {
    final dir = SelfUpdateService.updateCacheDir();
    return File(p.join(dir.path, _fileName));
  }

  static Future<void> write({
    required String targetVersion,
    required String channel,
  }) async {
    try {
      final f = _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode({
          'target_version': targetVersion,
          'started_at_ms': DateTime.now().millisecondsSinceEpoch,
          'channel': channel,
        }),
        flush: true,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: UpdatePendingMarker.write failed: $e');
      }
    }
  }

  static Map<String, Object?>? readAndClear() {
    final f = _file();
    if (!f.existsSync()) return null;
    try {
      final raw = f.readAsStringSync();
      f.deleteSync();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    return null;
  }
}
