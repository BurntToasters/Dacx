import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart' as cryptography;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'debug_log_service.dart';
import 'trusted_http.dart';
import 'update_trust_config.dart';
import 'update_service.dart';
import 'windows_system_paths.dart';
import 'windows_process_ffi.dart';

typedef HttpStreamFn =
    Future<http.StreamedResponse> Function(http.BaseRequest request);
typedef ProcessRunFn =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef WindowsSpawnFn =
    Future<WindowsSpawnResult> Function(
      String commandLine, {
      String? applicationName,
    });

enum SelfUpdateOutcome {
  unsupportedPlatform,
  missingAsset,
  missingChecksums,
  missingSignature,
  downloadFailed,
  checksumMismatch,
  extractionFailed,
  signatureInvalid,
  bundleIdentifierMismatch,
  versionMismatch,
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
  double? get fraction => totalBytes != null && totalBytes! > 0
      ? downloadedBytes / totalBytes!
      : null;
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
  static const String expectedWindowsSignerThumbprint = String.fromEnvironment(
    'DACX_WINDOWS_SIGNER_THUMBPRINT',
    defaultValue: '',
  );
  static const String _macInstallPath = '/Applications/Dacx.app';
  static const String _windowsManifestName =
      'Dacx-update-manifest-Windows-x64.json';
  static const String _windowsManifestSignatureName =
      'Dacx-update-manifest-Windows-x64.json.sig';

  static const Set<String> _allowedHosts = {
    'github.com',
    'www.github.com',
    'objects.githubusercontent.com',
  };
  static const int _maxDownloadRedirects = 5;

  bool _installInFlight = false;

  final DebugLogService? _debugLog;
  final HttpStreamFn _httpStream;
  final ProcessRunFn _processRun;
  final WindowsSpawnFn _windowsSpawn;

  SelfUpdateService({
    DebugLogService? debugLog,
    HttpStreamFn? httpStream,
    ProcessRunFn? processRun,
    WindowsSpawnFn? windowsSpawn,
  }) : _debugLog = debugLog,
       _httpStream = httpStream ?? platformHttpStreamFn,
       _processRun = processRun ?? Process.run,
       _windowsSpawn = windowsSpawn ?? _defaultWindowsSpawn;

  static Future<WindowsSpawnResult> _defaultWindowsSpawn(
    String commandLine, {
    String? applicationName,
  }) =>
      WindowsProcessFfi.runAsync(commandLine, applicationName: applicationName);

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
  /// Portable Windows builds (marked by a `portable.txt` file next to the
  /// executable) also return false: there is no MSI install state to upgrade,
  /// and the user is expected to replace the unzipped folder manually.
  static bool isSupported() {
    if (Platform.isWindows && isPortable()) return false;
    return Platform.isWindows || Platform.isMacOS;
  }

  /// Detects the portable Windows build. The portable ZIP ships with a
  /// `portable.txt` marker file alongside `dacx.exe`; MSI installs do not.
  static bool isPortable() {
    if (!Platform.isWindows) return false;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      return File(p.join(exeDir.path, 'portable.txt')).existsSync();
    } catch (_) {
      return false;
    }
  }

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
      final spIdx = line.indexOf('  ');
      if (spIdx != 64) continue;
      final hash = line.substring(0, 64);
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) continue;
      final nameRaw = line.substring(66).trim();
      final name = nameRaw.startsWith('*') ? nameRaw.substring(1) : nameRaw;
      if (p.basename(name) == target) return hash.toLowerCase();
    }
    return null;
  }

  /// Whether [url] may be used for self-update downloads (GitHub hosts only).
  static bool isAllowedDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return _isAllowedHost(uri.host);
  }

  static bool _isAllowedHost(String host) {
    final h = host.toLowerCase();
    if (_allowedHosts.contains(h)) return true;
    // GitHub serves release-asset downloads from rotating *.githubusercontent.com
    return h == 'githubusercontent.com' || h.endsWith('.githubusercontent.com');
  }

  static bool _isRedirectStatus(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static String normalizeCertificateThumbprint(String value) {
    return value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
  }

  static ({String status, String thumbprint, String message})
  parseAuthenticodeStatus(String text) {
    final line = const LineSplitter()
        .convert(text)
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final parts = line.split('|');
    return (
      status: parts.isNotEmpty ? parts[0].trim() : '',
      thumbprint: parts.length > 1
          ? normalizeCertificateThumbprint(parts[1])
          : '',
      message: parts.length > 2 ? parts.sublist(2).join('|').trim() : '',
    );
  }

  static Future<bool> verifyEd25519Signature({
    required List<int> message,
    required List<int> signature,
    required String publicKeyBase64,
  }) async {
    final publicKeyBytes = base64Decode(publicKeyBase64.trim());
    final algorithm = cryptography.Ed25519();
    return algorithm.verify(
      message,
      signature: cryptography.Signature(
        signature,
        publicKey: cryptography.SimplePublicKey(
          publicKeyBytes,
          type: cryptography.KeyPairType.ed25519,
        ),
      ),
    );
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
    await outFile.parent.create(recursive: true);
    final resp = await _sendAllowedGet(
      url,
      timeout: const Duration(minutes: 5),
    );
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode} from $url');
    }
    final total = resp.contentLength;
    var downloaded = 0;
    final sink = outFile.openWrite();
    try {
      await resp.stream.listen((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress?.call(SelfUpdateProgress(downloaded, total));
      }).asFuture<void>();
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
    final resp = await _sendAllowedGet(
      url,
      timeout: const Duration(seconds: 30),
    );
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode} from $url');
    }
    return utf8.decode(await resp.stream.toBytes());
  }

  Future<List<int>> _fetchBytes(String url) async {
    final resp = await _sendAllowedGet(
      url,
      timeout: const Duration(seconds: 30),
    );
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode} from $url');
    }
    return resp.stream.toBytes();
  }

  Future<http.StreamedResponse> _sendAllowedGet(
    String url, {
    required Duration timeout,
  }) async {
    var uri = Uri.parse(url);
    for (
      var redirectCount = 0;
      redirectCount <= _maxDownloadRedirects;
      redirectCount++
    ) {
      if (!isAllowedDownloadUrl(uri.toString())) {
        throw StateError('Refusing to fetch from non-allowlisted host: $uri');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await _httpStream(request).timeout(timeout);
      if (!_isRedirectStatus(response.statusCode)) {
        return response;
      }

      final location = response.headers['location'];
      await response.stream.drain<void>();
      if (location == null || location.trim().isEmpty) {
        throw StateError(
          'HTTP ${response.statusCode} redirect missing Location',
        );
      }
      final next = uri.resolve(location);
      if (!isAllowedDownloadUrl(next.toString())) {
        throw StateError('Refusing redirect to non-allowlisted host: $next');
      }
      uri = next;
    }
    throw StateError('Too many redirects from $url');
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
    if (_installInFlight) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.spawnFailed,
        message: 'An update is already in progress.',
      );
    }
    _installInFlight = true;
    SelfUpdateResult result;
    try {
      if (Platform.isWindows) {
        result = await _applyWindows(info, onProgress: onProgress);
      } else if (Platform.isMacOS) {
        result = await _applyMacos(info, onProgress: onProgress);
      } else {
        result = const SelfUpdateResult(SelfUpdateOutcome.unsupportedPlatform);
      }
    } catch (e, st) {
      _log(
        'self_update_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
        detailsBuilder: () => {'stack': st.toString()},
      );
      result = SelfUpdateResult(
        SelfUpdateOutcome.spawnFailed,
        message: e.toString(),
      );
    }
    if (result.outcome != SelfUpdateOutcome.spawned) {
      _installInFlight = false;
      if (result.outcome != SelfUpdateOutcome.unsupportedPlatform) {
        final failed = result;
        _log(
          'self_update_outcome',
          message: failed.message,
          severity: DebugSeverity.error,
          detailsBuilder: () => {
            'outcome': failed.outcome.name,
            'platform': Platform.operatingSystem,
            'target_version': info.version,
          },
        );
      }
    }
    return result;
  }

  Future<void> _cleanUpdateCache() async {
    try {
      final dir = updateCacheDir();
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync()) {
        final name = p.basename(entity.path).toLowerCase();
        if (entity is File &&
            (name.endsWith('.msi') ||
                name.endsWith('.zip') ||
                name.endsWith('.ps1') ||
                name.endsWith('.vbs'))) {
          entity.deleteSync();
        } else if (entity is Directory && name == 'extracted') {
          entity.deleteSync(recursive: true);
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────── Windows path

  Future<SelfUpdateResult> _applyWindows(
    UpdateInfo info, {
    void Function(SelfUpdateProgress)? onProgress,
  }) async {
    await _cleanUpdateCache();
    final asset =
        pickAssetByPattern(
          info.assets,
          RegExp(r'^Dacx-Windows-x64\.msi$', caseSensitive: false),
        ) ??
        pickAsset(info.assets, '.msi');
    final checksums = pickAsset(info.assets, 'SHA256SUMS-Windows-x64.txt');
    final manifest = pickAsset(info.assets, _windowsManifestName);
    final manifestSignature = pickAsset(
      info.assets,
      _windowsManifestSignatureName,
    );
    if (asset == null) {
      return const SelfUpdateResult(SelfUpdateOutcome.missingAsset);
    }
    if (checksums == null) {
      return const SelfUpdateResult(SelfUpdateOutcome.missingChecksums);
    }
    if (manifest == null || manifestSignature == null) {
      return const SelfUpdateResult(SelfUpdateOutcome.missingSignature);
    }

    final cacheDir = updateCacheDir();
    final msiPath = File(p.join(cacheDir.path, asset.name));

    String checksumsBody;
    List<int> manifestBytes;
    List<int> manifestSignatureBytes;
    try {
      await _downloadTo(asset.downloadUrl, msiPath, onProgress: onProgress);
      checksumsBody = await _fetchText(checksums.downloadUrl);
      manifestBytes = await _fetchBytes(manifest.downloadUrl);
      final manifestSignatureBody = await _fetchText(
        manifestSignature.downloadUrl,
      );
      manifestSignatureBytes = base64Decode(manifestSignatureBody.trim());
    } catch (e) {
      return SelfUpdateResult(
        SelfUpdateOutcome.downloadFailed,
        message: e.toString(),
      );
    }

    final manifestResult = await _validateWindowsManifest(
      manifestBytes: manifestBytes,
      signatureBytes: manifestSignatureBytes,
      version: info.version,
      assetName: asset.name,
    );
    if (manifestResult.outcome != SelfUpdateOutcome.spawned) {
      return manifestResult;
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

    final manifestHash = hashFromWindowsManifest(manifestBytes, asset.name);
    if (manifestHash == null) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'No MSI entry in signed update manifest',
      );
    }
    if (actualHash != manifestHash) {
      return SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'signed manifest expected $manifestHash, got $actualHash',
      );
    }

    if (expectedWindowsSignerThumbprint.isNotEmpty) {
      final signature = await _validateWindowsInstallerSignature(msiPath);
      if (signature.outcome != SelfUpdateOutcome.spawned) {
        return signature;
      }
    }

    final scriptPath = File(p.join(cacheDir.path, 'apply-update.ps1'));
    await scriptPath.writeAsString(buildWindowsWatchdogPowerShellScript());

    final thumb = normalizeCertificateThumbprint(
      expectedWindowsSignerThumbprint,
    );
    final bootstrapPath = File(p.join(cacheDir.path, 'spawn-watchdog.ps1'));
    await bootstrapPath.writeAsString(
      buildWindowsBootstrapPowerShellScript(
        scriptPath: scriptPath.path,
        dacxPid: pid,
        msiPath: msiPath.path,
        thumbprint: thumb,
        sha256: actualHash,
      ),
    );

    try {
      final commandLine = buildBootstrapCommandLine(bootstrapPath.path);
      final spawn = await _windowsSpawn(
        commandLine,
        applicationName: WindowsSystemPaths.powershell(),
      );
      if (!spawn.launched) {
        return SelfUpdateResult(
          SelfUpdateOutcome.spawnFailed,
          message: spawn.error ?? 'CreateProcessW failed',
        );
      }
      if (spawn.exitCode != null && spawn.exitCode != 0) {
        return SelfUpdateResult(
          SelfUpdateOutcome.spawnFailed,
          message: 'bootstrap exit ${spawn.exitCode}',
        );
      }
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

  Future<SelfUpdateResult> _validateWindowsManifest({
    required List<int> manifestBytes,
    required List<int> signatureBytes,
    required String version,
    required String assetName,
  }) async {
    final publicKey = UpdateTrustConfig.windowsManifestPublicKeyBase64.trim();
    if (publicKey.isEmpty) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message:
            'Self-update is misconfigured: Windows update manifest public key is not set.',
      );
    }

    bool isValid;
    try {
      isValid = await verifyEd25519Signature(
        message: manifestBytes,
        signature: signatureBytes,
        publicKeyBase64: publicKey,
      );
    } catch (e) {
      return SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: e.toString(),
      );
    }
    if (!isValid) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: 'Windows update manifest signature is invalid.',
      );
    }

    final decoded = jsonDecode(utf8.decode(manifestBytes));
    if (decoded is! Map<String, dynamic>) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: 'Windows update manifest is malformed.',
      );
    }
    if (decoded['version'] != version) {
      return SelfUpdateResult(
        SelfUpdateOutcome.versionMismatch,
        message: 'expected $version, got "${decoded['version']}"',
      );
    }
    final app = decoded['app'];
    if (app is! String || app.toLowerCase() != 'dacx') {
      return const SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: 'Windows update manifest app field is invalid.',
      );
    }
    final platform = decoded['platform'];
    if (platform is! String || platform.toLowerCase() != 'windows-x64') {
      return const SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: 'Windows update manifest platform field is invalid.',
      );
    }
    final releasedAt = decoded['released_at'];
    if (releasedAt is String) {
      final ts = DateTime.tryParse(releasedAt)?.toUtc();
      final now = DateTime.now().toUtc();
      if (ts == null ||
          ts.isBefore(DateTime.utc(2024)) ||
          ts.isAfter(now.add(const Duration(hours: 1)))) {
        return const SelfUpdateResult(
          SelfUpdateOutcome.signatureInvalid,
          message:
              'Windows update manifest released_at is invalid or out of range.',
        );
      }
    }
    final assets = decoded['assets'];
    if (assets is! Map || assets[assetName] is! String) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'Windows update manifest does not include the MSI asset.',
      );
    }
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  static String? hashFromWindowsManifest(
    List<int> manifestBytes,
    String assetName,
  ) {
    final decoded = jsonDecode(utf8.decode(manifestBytes));
    if (decoded is! Map<String, dynamic>) return null;
    final assets = decoded['assets'];
    if (assets is! Map) return null;
    final hash = assets[assetName];
    if (hash is! String) return null;
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) return null;
    return hash.toLowerCase();
  }

  Future<SelfUpdateResult> _validateWindowsInstallerSignature(File file) async {
    final expected = normalizeCertificateThumbprint(
      expectedWindowsSignerThumbprint,
    );
    if (expected.isEmpty) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message:
            'Self-update is misconfigured: DACX_WINDOWS_SIGNER_THUMBPRINT was not set at build time.',
      );
    }

    final authenticodeCommand = [
      r"$sig = Get-AuthenticodeSignature -LiteralPath $args[0];",
      r"$thumb = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { '' };",
      r"Write-Output ($sig.Status.ToString() + '|' + $thumb + '|' + $sig.StatusMessage)",
    ].join(' ');
    final result = await _processRun(WindowsSystemPaths.powershell(), [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      authenticodeCommand,
      file.path,
    ]);
    if (result.exitCode != 0) {
      return SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: result.stderr.toString(),
      );
    }

    final parsed = parseAuthenticodeStatus(result.stdout.toString());
    if (parsed.status != 'Valid') {
      return SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: parsed.message.isNotEmpty
            ? parsed.message
            : 'Authenticode status: ${parsed.status}',
      );
    }
    if (parsed.thumbprint != expected) {
      return SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: 'expected signer $expected, got "${parsed.thumbprint}"',
      );
    }
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  /// Builds the full command line passed to `CreateProcessW` to launch the
  /// bootstrap script with no console window. The script path is quoted so
  /// spaces in `%LOCALAPPDATA%` are handled.
  @visibleForTesting
  static String buildBootstrapCommandLine(String bootstrapPath) {
    return '-NoProfile -ExecutionPolicy Bypass '
        '-WindowStyle Hidden -File "$bootstrapPath"';
  }

  @visibleForTesting
  static String buildWindowsWatchdogPowerShellScript() {
    return r'''
param(
  [Parameter(Mandatory=$true)][int]$DacxPid,
  [Parameter(Mandatory=$true)][string]$DacxMsi,
  [Parameter(Mandatory=$false)][AllowEmptyString()][string]$ExpectedThumbprint = '',
  [Parameter(Mandatory=$true)][string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'

$LogDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Dacx', 'updates')
$null = [System.IO.Directory]::CreateDirectory($LogDir)
$LogFile = [System.IO.Path]::Combine($LogDir, 'watchdog.log')
function Log($msg) {
  $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Add-Content -LiteralPath $LogFile -Value "$ts $msg" -ErrorAction SilentlyContinue
}

trap {
  Log "fatal: $_"
  exit 99
}

Log "started pid=$DacxPid msi=$DacxMsi thumb=$ExpectedThumbprint sha=$ExpectedSha256"

try {
  $dacxProc = Get-Process -Id $DacxPid -ErrorAction Stop
  if (-not $dacxProc.WaitForExit(600000)) { Log "timeout waiting for pid=$DacxPid"; exit 5 }
} catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
  Log "pid=$DacxPid already gone"
} catch {
  Log "wait-error: $_"
  exit 2
}

Log "dacx exited, verifying sha256"
$actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $DacxMsi).Hash.ToLowerInvariant()
if ($actualSha256 -ine $ExpectedSha256) {
  Log "sha256 mismatch expected=$ExpectedSha256 actual=$actualSha256"
  exit 12
}

if ($ExpectedThumbprint -ne '') {
  $sig = Get-AuthenticodeSignature -LiteralPath $DacxMsi
  if ($sig.Status -ne 'Valid') {
    Log "authenticode status=$($sig.Status)"
    exit 10
  }
  $thumb = $sig.SignerCertificate.Thumbprint -replace '[^0-9A-Fa-f]', ''
  $expected = $ExpectedThumbprint -replace '[^0-9A-Fa-f]', ''
  if ($thumb -ine $expected) {
    Log "authenticode thumbprint mismatch expected=$expected actual=$thumb"
    exit 11
  }
}

Log "launching msiexec"
$msiArgs = @('/i', $DacxMsi, '/passive', '/norestart')
try {
  $install = Start-Process -FilePath '@@MSIEXEC@@' -ArgumentList $msiArgs -Verb RunAs -Wait -PassThru
} catch {
  Log "msiexec launch failed: $_"
  exit 1223
}
if ($null -eq $install) { Log "msiexec process was null"; exit 1 }
Log "msiexec exited code=$($install.ExitCode)"
exit $install.ExitCode
'''
        .replaceAll(
          '@@MSIEXEC@@',
          WindowsSystemPaths.msiexec().replaceAll("'", "''"),
        );
  }

  /// Bootstrap script: spawns the watchdog via WMI `Win32_Process.Create` so it
  /// runs as a child of the WMI service and escapes any Windows Job Object the
  /// parent app belongs to. Without this, `dacx.exe`'s job (Windows GUI Process
  /// Lifetime Management) would kill the watchdog the moment we call `exit(0)`.
  @visibleForTesting
  static String buildWindowsBootstrapPowerShellScript({
    required String scriptPath,
    required int dacxPid,
    required String msiPath,
    required String thumbprint,
    required String sha256,
  }) {
    String esc(String s) => s.replaceAll('"', '\\"');
    final powershellPath = esc(WindowsSystemPaths.powershell());
    final cmd =
        '"$powershellPath" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden '
        '-File "${esc(scriptPath)}" '
        '-DacxPid $dacxPid '
        '-DacxMsi "${esc(msiPath)}" '
        '-ExpectedThumbprint "${esc(thumbprint)}" '
        '-ExpectedSha256 $sha256';
    final cmdLiteral = cmd.replaceAll("'", "''");
    return '''
\$ErrorActionPreference = 'Stop'
\$LogDir = [System.IO.Path]::Combine(\$env:LOCALAPPDATA, 'Dacx', 'updates')
\$null = [System.IO.Directory]::CreateDirectory(\$LogDir)
\$LogFile = [System.IO.Path]::Combine(\$LogDir, 'bootstrap.log')
function Log(\$msg) {
  \$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Add-Content -LiteralPath \$LogFile -Value "\$ts \$msg" -ErrorAction SilentlyContinue
}
trap { Log "fatal: \$_"; exit 99 }
\$cmd = '$cmdLiteral'
Log "spawning via WMI: \$cmd"
\$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = \$cmd }
Log "WMI ReturnValue=\$(\$result.ReturnValue) ProcessId=\$(\$result.ProcessId)"
if (\$result.ReturnValue -ne 0) { exit \$result.ReturnValue }
exit 0
''';
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

    // Fetch the small checksums file in Dart (fast, testable) to get the
    // expected SHA256 hex. The heavy work — download, verify, extract,
    // codesign, swap — all happens in the unsandboxed XPC helper so that no
    // files are stamped with com.apple.provenance from our sandbox.
    final String checksumsBody;
    try {
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

    try {
      final reply = await _macUpdateChannel
          .invokeMapMethod<String, dynamic>('installUpdateFromUrl', {
            'zipUrl': asset.downloadUrl,
            'checksumHex': expectedHash,
            'installedAppPath': _macInstallPath,
            'expectedTeamId': expectedTeamId,
            'expectedVersion': info.version,
            'relaunch': true,
          });
      final accepted = reply?['accepted'] == true;
      if (!accepted) {
        final err = reply?['error']?.toString();
        final message = (err != null && err.trim().isNotEmpty)
            ? err
            : 'XPC update helper rejected install';
        if (message.contains('codesign:') || message.contains('gatekeeper:')) {
          return SelfUpdateResult(
            SelfUpdateOutcome.signatureInvalid,
            message: message,
          );
        }
        if (message.contains('SHA256 mismatch') ||
            message.contains('checksumHex')) {
          return SelfUpdateResult(
            SelfUpdateOutcome.checksumMismatch,
            message: message,
          );
        }
        if (message.contains('ditto')) {
          return SelfUpdateResult(
            SelfUpdateOutcome.extractionFailed,
            message: message,
          );
        }
        return SelfUpdateResult(
          SelfUpdateOutcome.spawnFailed,
          message: message,
        );
      }
    } on PlatformException catch (e) {
      return SelfUpdateResult(
        SelfUpdateOutcome.spawnFailed,
        message: e.message ?? e.code,
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
        'zip_url': asset.downloadUrl,
        'install_path': _macInstallPath,
      },
    );
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  static const MethodChannel _macUpdateChannel = MethodChannel(
    'run.rosie.dacx/update',
  );
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
