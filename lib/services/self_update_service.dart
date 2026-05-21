import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'debug_log_service.dart';
import 'trusted_http.dart';
import 'update_trust_config.dart';
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
  static const String _macBundleIdentifier = 'run.rosie.dacx';
  static const String _windowsManifestName =
      'Dacx-update-manifest-Windows-x64.json';
  static const String _windowsManifestSignatureName =
      'Dacx-update-manifest-Windows-x64.json.sig';

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
       _httpGet = httpGet ?? platformHttpGetFn,
       _httpStream = httpStream ?? platformHttpStreamFn,
       _processRun = processRun ?? Process.run,
       _processStart = processStart ?? Process.start;

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

  static Map<String, String> parseCodesignDetails(String text) {
    final result = <String, String>{};
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      final idx = line.indexOf('=');
      if (idx <= 0 || idx == line.length - 1) continue;
      result[line.substring(0, idx)] = line.substring(idx + 1);
    }
    return result;
  }

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
    if (!_isAllowedHost(url)) {
      throw StateError('Refusing to fetch from non-allowlisted host: $url');
    }
    final resp = await _httpGet(
      Uri.parse(url),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode} from $url');
    }
    return resp.body;
  }

  Future<List<int>> _fetchBytes(String url) async {
    if (!_isAllowedHost(url)) {
      throw StateError('Refusing to fetch from non-allowlisted host: $url');
    }
    final resp = await _httpGet(
      Uri.parse(url),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode} from $url');
    }
    return resp.bodyBytes;
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

    final manifestHash = _hashFromWindowsManifest(manifestBytes, asset.name);
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

    // Hidden watchdog polls until our PID exits, then runs msiexec.
    final scriptPath = File(p.join(cacheDir.path, 'apply-update.ps1'));
    await scriptPath.writeAsString(buildWindowsWatchdogPowerShellScript());
    try {
      await _processStart('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptPath.path,
        pid.toString(),
        msiPath.path,
        normalizeCertificateThumbprint(expectedWindowsSignerThumbprint),
        actualHash,
      ], mode: ProcessStartMode.detached);
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
    final assets = decoded['assets'];
    if (assets is! Map || assets[assetName] is! String) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.checksumMismatch,
        message: 'Windows update manifest does not include the MSI asset.',
      );
    }
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  static String? _hashFromWindowsManifest(
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
    final result = await _processRun('powershell.exe', [
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

  @visibleForTesting
  static String buildWindowsWatchdogPowerShellScript() {
    return r'''
param(
  [Parameter(Mandatory=$true)][int]$DacxPid,
  [Parameter(Mandatory=$true)][string]$DacxMsi,
  [Parameter(Mandatory=$true)][string]$ExpectedThumbprint,
  [Parameter(Mandatory=$true)][string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'

while (Get-Process -Id $DacxPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Seconds 1
}

$actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $DacxMsi).Hash.ToLowerInvariant()
if ($actualSha256 -ine $ExpectedSha256) {
  exit 12
}

if ($ExpectedThumbprint -ne '') {
  $sig = Get-AuthenticodeSignature -LiteralPath $DacxMsi
  if ($sig.Status -ne 'Valid') {
    exit 10
  }
  $thumb = $sig.SignerCertificate.Thumbprint -replace '[^0-9A-Fa-f]', ''
  $expected = $ExpectedThumbprint -replace '[^0-9A-Fa-f]', ''
  if ($thumb -ine $expected) {
    exit 11
  }
}

$msiArgs = @('/i', $DacxMsi, '/passive', '/norestart')
$install = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
exit $install.ExitCode
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

    final validation = await _validateMacBundle(
      extractedAppPath,
      expectedVersion: info.version,
    );
    if (validation.outcome != SelfUpdateOutcome.spawned) {
      return validation;
    }

    try {
      final reply = await _macUpdateChannel
          .invokeMapMethod<String, dynamic>('installUpdate', {
            'newAppPath': extractedAppPath,
            'installedAppPath': _macInstallPath,
            'expectedTeamId': expectedTeamId,
            'expectedVersion': info.version,
            'relaunch': true,
          });
      final accepted = reply?['accepted'] == true;
      if (!accepted) {
        final err = reply?['error']?.toString();
        return SelfUpdateResult(
          SelfUpdateOutcome.spawnFailed,
          message: (err != null && err.trim().isNotEmpty)
              ? err
              : 'XPC update helper rejected install',
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
        'extracted': extractedAppPath,
        'install_path': _macInstallPath,
      },
    );
    return const SelfUpdateResult(SelfUpdateOutcome.spawned);
  }

  static const MethodChannel _macUpdateChannel = MethodChannel(
    'run.rosie.dacx/update',
  );

  /// Runs a Gatekeeper-respecting validation pipeline against
  /// the bundle at [appPath]. Returns SelfUpdateOutcome.spawned on full pass
  /// (sentinel meaning "ok to continue"); any other outcome is a failure.
  Future<SelfUpdateResult> _validateMacBundle(
    String appPath, {
    required String expectedVersion,
  }) async {
    // 1. Verify the full nested code signature. This uses the built-in
    // codesign tool only; no Xcode/CLT-only stapler dependency at runtime.
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

    // 2. Read signed code metadata and make sure this is Dacx from our team.
    final dv = await _processRun('/usr/bin/codesign', [
      '-dv',
      '--verbose=4',
      appPath,
    ]);
    if (dv.exitCode != 0) {
      return SelfUpdateResult(
        SelfUpdateOutcome.signatureInvalid,
        message: dv.stderr.toString(),
      );
    }
    final dvOutput = '${dv.stdout}\n${dv.stderr}';
    final details = parseCodesignDetails(dvOutput);
    final actualIdentifier = details['Identifier'] ?? '';
    if (actualIdentifier != _macBundleIdentifier) {
      return SelfUpdateResult(
        SelfUpdateOutcome.bundleIdentifierMismatch,
        message: 'expected $_macBundleIdentifier, got "$actualIdentifier"',
      );
    }
    final actualTeamId = details['TeamIdentifier'] ?? '';
    if (actualTeamId != expectedTeamId) {
      return SelfUpdateResult(
        SelfUpdateOutcome.teamIdMismatch,
        message: 'expected $expectedTeamId, got "$actualTeamId"',
      );
    }

    final version = await _readMacBundleReleaseVersion(appPath);
    if (version == null) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.versionMismatch,
        message: 'DacxReleaseVersion not found in bundle Info.plist',
      );
    }
    if (version.source != 'DacxReleaseVersion' &&
        expectedVersion.contains('-')) {
      return const SelfUpdateResult(
        SelfUpdateOutcome.versionMismatch,
        message:
            'Prerelease macOS updates must include DacxReleaseVersion in bundle Info.plist',
      );
    }
    if (version.value != expectedVersion) {
      return SelfUpdateResult(
        SelfUpdateOutcome.versionMismatch,
        message: 'expected $expectedVersion, got "${version.value}"',
      );
    }

    // 4. Ask Gatekeeper to assess the app. This validates notarization without
    // relying on the developer-only `xcrun stapler` command being installed.
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

  Future<({String value, String source})?> _readMacBundleReleaseVersion(
    String appPath,
  ) async {
    final infoPlist = p.join(appPath, 'Contents', 'Info.plist');
    for (final key in const [
      'DacxReleaseVersion',
      'CFBundleShortVersionString',
    ]) {
      final value = await UpdateService.readBundleInfoString(infoPlist, key);
      if (value != null) {
        return (value: value, source: key);
      }
    }
    return null;
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
