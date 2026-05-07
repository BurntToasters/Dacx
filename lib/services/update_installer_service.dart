import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'debug_log_service.dart';
import 'update_service.dart';

typedef IsPlatformFn = bool Function();
typedef TempDirectoryProvider = Directory Function();
typedef InstallerLauncher =
    Future<void> Function(String executable, List<String> arguments);
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef CurrentAppBundleProvider = Directory? Function();
typedef BundleInfoReader =
    Future<MacOsBundleInfo> Function(Directory appBundle);

class UpdateInstallerService {
  static const String _windowsInstallerAssetName = 'Dacx-Windows-x64.msi';
  static const String _macOsZipAssetName = 'Dacx-macOS.zip';
  static const String _appBundleName = 'Dacx.app';

  final DebugLogService? _debugLog;
  final String _debugSource;
  final HttpGet _httpGet;
  final IsPlatformFn _isWindows;
  final IsPlatformFn _isMacOS;
  final TempDirectoryProvider _tempDirectoryProvider;
  final InstallerLauncher _installerLauncher;
  final ProcessRunner _processRunner;
  final CurrentAppBundleProvider _currentAppBundleProvider;
  late final BundleInfoReader _bundleInfoReader;

  UpdateInstallerService({
    DebugLogService? debugLog,
    String debugSource = 'unknown',
    HttpGet? httpGet,
    IsPlatformFn? isWindows,
    IsPlatformFn? isMacOS,
    TempDirectoryProvider? tempDirectoryProvider,
    InstallerLauncher? installerLauncher,
    ProcessRunner? processRunner,
    CurrentAppBundleProvider? currentAppBundleProvider,
    BundleInfoReader? bundleInfoReader,
  }) : _debugLog = debugLog,
       _debugSource = debugSource,
       _httpGet = httpGet ?? http.get,
       _isWindows = isWindows ?? (() => Platform.isWindows),
       _isMacOS = isMacOS ?? (() => Platform.isMacOS),
       _tempDirectoryProvider =
           tempDirectoryProvider ?? (() => Directory.systemTemp),
       _installerLauncher = installerLauncher ?? _defaultInstallerLauncher,
       _processRunner = processRunner ?? Process.run,
       _currentAppBundleProvider =
           currentAppBundleProvider ?? _defaultCurrentAppBundleProvider {
    _bundleInfoReader = bundleInfoReader ?? _readBundleInfo;
  }

  bool canInstall(UpdateInfo update) {
    if (_isWindows()) return update.hasWindowsInstaller;
    if (_isMacOS()) return update.hasMacOsZip;
    return false;
  }

  Future<void> prepareAndLaunch(UpdateInfo update) async {
    if (_isWindows()) {
      final installer = await downloadWindowsInstaller(update);
      await launchWindowsInstaller(installer, update);
      return;
    }
    if (_isMacOS()) {
      final prepared = await prepareMacOsZipUpdate(update);
      await launchMacOsUpdater(prepared);
      return;
    }
    throw UnsupportedError('Self-updates are not available on this platform.');
  }

  Future<File> downloadWindowsInstaller(UpdateInfo update) async {
    if (!_isWindows()) {
      throw UnsupportedError(
        'Windows MSI updates are only available on Windows.',
      );
    }
    final installerUrl = update.windowsInstallerUrl;
    if (installerUrl == null ||
        !_isReleaseAssetUrl(installerUrl, extension: '.msi')) {
      throw ArgumentError(
        'Update does not include a valid Windows installer URL.',
      );
    }

    return _downloadReleaseAsset(
      update: update,
      url: installerUrl,
      assetName: update.windowsInstallerAssetName ?? _windowsInstallerAssetName,
      expectedSize: update.windowsInstallerSize,
      expectedSha256: update.windowsInstallerSha256,
      platformLabel: 'windows_installer',
    );
  }

  Future<void> launchWindowsInstaller(File installer, UpdateInfo update) async {
    if (!_isWindows()) {
      throw UnsupportedError(
        'Windows MSI updates are only available on Windows.',
      );
    }
    if (!installer.existsSync()) {
      throw ArgumentError('Installer file does not exist: ${installer.path}');
    }

    final logFile = File(
      p.join(installer.parent.path, 'Dacx-update-${update.version}.log'),
    );
    final arguments = [
      '/i',
      installer.path,
      '/passive',
      '/norestart',
      '/l*vx',
      logFile.path,
    ];

    _log(
      'windows_installer_launch_requested',
      detailsBuilder: () => {
        'version': update.version,
        'installer': installer.path,
        'log': logFile.path,
      },
    );

    await _installerLauncher('msiexec.exe', arguments);
    _log(
      'windows_installer_launch_succeeded',
      detailsBuilder: () => {
        'version': update.version,
        'installer': installer.path,
      },
    );
  }

  Future<File> downloadMacOsZip(UpdateInfo update) async {
    if (!_isMacOS()) {
      throw UnsupportedError('macOS zip updates are only available on macOS.');
    }
    final zipUrl = update.macOsZipUrl;
    if (zipUrl == null || !_isReleaseAssetUrl(zipUrl, extension: '.zip')) {
      throw ArgumentError('Update does not include a valid macOS zip URL.');
    }

    return _downloadReleaseAsset(
      update: update,
      url: zipUrl,
      assetName: update.macOsZipAssetName ?? _macOsZipAssetName,
      expectedSize: update.macOsZipSize,
      expectedSha256: update.macOsZipSha256,
      platformLabel: 'macos_zip',
    );
  }

  Future<MacOsPreparedUpdate> prepareMacOsZipUpdate(UpdateInfo update) async {
    if (!_isMacOS()) {
      throw UnsupportedError('macOS zip updates are only available on macOS.');
    }
    final currentApp = _currentAppBundleProvider();
    if (currentApp == null || !currentApp.existsSync()) {
      throw const UpdateInstallException(
        'Could not locate the current Dacx.app bundle.',
      );
    }
    if (_isUnsupportedMacAppLocation(currentApp)) {
      throw const UpdateInstallException(
        'Dacx cannot self-update while running from a mounted disk image or App Translocation path.',
      );
    }
    final requiresAdminPrivileges = !_canWriteToDirectory(currentApp.parent);
    if (requiresAdminPrivileges) {
      _log(
        'macos_update_requires_admin_privileges',
        detailsBuilder: () => {'parent_dir': currentApp.parent.path},
      );
    }

    final zip = await downloadMacOsZip(update);
    final extractDir = Directory(p.join(zip.parent.path, 'macos-extracted'));
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    await extractDir.create(recursive: true);

    await _runChecked('ditto', [
      '-x',
      '-k',
      zip.path,
      extractDir.path,
    ], failureMessage: 'Could not extract the macOS update zip.');
    final newApp = _findExtractedApp(extractDir);
    if (newApp == null) {
      throw const UpdateInstallException(
        'The macOS update zip did not contain Dacx.app.',
      );
    }

    final currentInfo = await _bundleInfoReader(currentApp);
    final newInfo = await _bundleInfoReader(newApp);
    if (currentInfo.bundleId != newInfo.bundleId) {
      throw UpdateInstallException(
        'Update bundle identifier mismatch: expected ${currentInfo.bundleId}, got ${newInfo.bundleId}.',
      );
    }
    if (newInfo.shortVersion != update.version) {
      throw UpdateInstallException(
        'Update bundle version mismatch: expected ${update.version}, got ${newInfo.shortVersion}.',
      );
    }

    await _verifyMacOsAppSignature(newApp);

    return MacOsPreparedUpdate(
      currentApp: currentApp,
      newApp: newApp,
      helperScript: File(
        p.join(zip.parent.path, 'Dacx-macos-update-helper.sh'),
      ),
      logFile: File(p.join(zip.parent.path, 'Dacx-macos-update.log')),
      requiresAdminPrivileges: requiresAdminPrivileges,
    );
  }

  Future<void> launchMacOsUpdater(MacOsPreparedUpdate prepared) async {
    if (!_isMacOS()) {
      throw UnsupportedError('macOS zip updates are only available on macOS.');
    }
    if (!prepared.currentApp.existsSync()) {
      throw ArgumentError(
        'Current app bundle does not exist: ${prepared.currentApp.path}',
      );
    }
    if (!prepared.newApp.existsSync()) {
      throw ArgumentError(
        'New app bundle does not exist: ${prepared.newApp.path}',
      );
    }

    await prepared.helperScript.writeAsString(_macOsHelperScript, flush: true);
    await _runChecked(
      'chmod',
      ['700', prepared.helperScript.path],
      failureMessage: 'Could not make the macOS updater helper executable.',
    );

    _log(
      'macos_update_helper_launch_requested',
      detailsBuilder: () => {
        'current_app': prepared.currentApp.path,
        'new_app': prepared.newApp.path,
        'log': prepared.logFile.path,
        'requires_admin': prepared.requiresAdminPrivileges,
      },
    );

    final helperArguments = [
      prepared.helperScript.path,
      prepared.currentApp.path,
      prepared.newApp.path,
      pid.toString(),
      prepared.logFile.path,
    ];
    if (prepared.requiresAdminPrivileges) {
      final shellCommand = _buildShellCommand('/bin/sh', helperArguments);
      final script =
          'do shell script "${_escapeAppleScriptString(shellCommand)}" '
          'with administrator privileges';
      await _installerLauncher('/usr/bin/osascript', ['-e', script]);
    } else {
      await _installerLauncher('/bin/sh', helperArguments);
    }
    _log(
      'macos_update_helper_launch_succeeded',
      detailsBuilder: () => {
        'current_app': prepared.currentApp.path,
        'new_app': prepared.newApp.path,
        'log': prepared.logFile.path,
        'requires_admin': prepared.requiresAdminPrivileges,
      },
    );
  }

  Future<File> _downloadReleaseAsset({
    required UpdateInfo update,
    required String url,
    required String assetName,
    required int? expectedSize,
    required String? expectedSha256,
    required String platformLabel,
  }) async {
    final updateDir = Directory(
      p.join(_tempDirectoryProvider().path, 'Dacx-update-${update.version}'),
    );
    await updateDir.create(recursive: true);
    final destination = File(p.join(updateDir.path, assetName));
    final partial = File('${destination.path}.download');

    _log(
      '${platformLabel}_download_started',
      detailsBuilder: () => {
        'version': update.version,
        'url': url,
        'destination': destination.path,
      },
    );

    try {
      final response = await _httpGet(
        Uri.parse(url),
        headers: {'Accept': 'application/octet-stream'},
      ).timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) {
        throw UpdateInstallException(
          'Update download failed with HTTP ${response.statusCode}.',
        );
      }

      final bytes = response.bodyBytes;
      if (expectedSize != null &&
          expectedSize > 0 &&
          bytes.length != expectedSize) {
        throw UpdateInstallException(
          'Update download size mismatch: expected $expectedSize bytes, got ${bytes.length}.',
        );
      }

      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final actualSha256 = crypto.sha256.convert(bytes).toString();
        if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
          throw UpdateInstallException(
            'Update SHA-256 mismatch: expected $expectedSha256, got $actualSha256.',
          );
        }
      }

      if (partial.existsSync()) partial.deleteSync();
      await partial.writeAsBytes(bytes, flush: true);
      if (destination.existsSync()) destination.deleteSync();
      await partial.rename(destination.path);

      _log(
        '${platformLabel}_download_completed',
        detailsBuilder: () => {
          'version': update.version,
          'path': destination.path,
          'bytes': bytes.length,
        },
      );
      return destination;
    } catch (e) {
      if (partial.existsSync()) {
        try {
          partial.deleteSync();
        } catch (_) {}
      }
      _log(
        '${platformLabel}_download_failed',
        severity: DebugSeverity.error,
        message: e.toString(),
        detailsBuilder: () => {'version': update.version},
      );
      rethrow;
    }
  }

  Future<MacOsBundleInfo> _readBundleInfo(Directory appBundle) async {
    final plist = p.join(appBundle.path, 'Contents', 'Info.plist');
    final bundleId = await _readPlistValue(plist, 'CFBundleIdentifier');
    final shortVersion = await _readPlistValue(
      plist,
      'CFBundleShortVersionString',
    );
    final buildNumber = await _readPlistValue(plist, 'CFBundleVersion');
    return MacOsBundleInfo(
      bundleId: bundleId,
      shortVersion: shortVersion,
      buildNumber: buildNumber,
    );
  }

  Future<String> _readPlistValue(String plist, String key) async {
    final result = await _processRunner('/usr/bin/plutil', [
      '-extract',
      key,
      'raw',
      '-o',
      '-',
      plist,
    ]);
    if (result.exitCode != 0) {
      throw UpdateInstallException('Could not read $key from $plist.');
    }
    return result.stdout.toString().trim();
  }

  Future<void> _verifyMacOsAppSignature(Directory appBundle) async {
    await _runChecked(
      'codesign',
      ['--verify', '--deep', '--strict', appBundle.path],
      failureMessage: 'The macOS update failed code-signature verification.',
    );
    await _runChecked('spctl', [
      '--assess',
      '--type',
      'execute',
      appBundle.path,
    ], failureMessage: 'The macOS update failed Gatekeeper assessment.');
  }

  Future<void> _runChecked(
    String executable,
    List<String> arguments, {
    required String failureMessage,
  }) async {
    final result = await _processRunner(executable, arguments);
    if (result.exitCode == 0) return;
    final detail = result.stderr.toString().trim();
    throw UpdateInstallException(
      detail.isEmpty ? failureMessage : '$failureMessage $detail',
    );
  }

  Directory? _findExtractedApp(Directory extractDir) {
    final direct = Directory(p.join(extractDir.path, _appBundleName));
    if (direct.existsSync()) return direct;
    for (final entity in extractDir.listSync(recursive: true)) {
      if (entity is Directory && p.basename(entity.path) == _appBundleName) {
        return entity;
      }
    }
    return null;
  }

  bool _isReleaseAssetUrl(String value, {required String extension}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    if (!uri.hasScheme || uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    const allowedHosts = {
      'github.com',
      'www.github.com',
      'objects.githubusercontent.com',
    };
    if (!allowedHosts.contains(uri.host.toLowerCase())) return false;
    return uri.path.toLowerCase().endsWith(extension);
  }

  void _log(
    String event, {
    String? message,
    Map<String, Object?> details = const {},
    String? Function()? messageBuilder,
    Map<String, Object?> Function()? detailsBuilder,
    DebugSeverity severity = DebugSeverity.info,
  }) {
    final debugLog = _debugLog;
    if (debugLog == null || !debugLog.isEnabled) return;
    debugLog.logLazy(
      category: DebugLogCategory.update,
      event: event,
      messageBuilder:
          messageBuilder ?? (message == null ? null : () => message),
      detailsBuilder: () => {
        'source': _debugSource,
        ...(detailsBuilder?.call() ?? details),
      },
      severity: severity,
    );
  }

  static bool _isUnsupportedMacAppLocation(Directory appBundle) {
    final path = appBundle.path;
    return path.startsWith('/Volumes/') || path.contains('/AppTranslocation/');
  }

  static bool _canWriteToDirectory(Directory directory) {
    try {
      final probe = File(
        p.join(directory.path, '.dacx-updater-write-test-$pid.tmp'),
      );
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _buildShellCommand(String executable, List<String> arguments) {
    return <String>[executable, ...arguments].map(_shellQuote).join(' ');
  }

  static String _shellQuote(String value) {
    if (value.isEmpty) return "''";
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  static String _escapeAppleScriptString(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  static Directory? _defaultCurrentAppBundleProvider() {
    var dir = File(Platform.resolvedExecutable).parent;
    while (dir.path != dir.parent.path) {
      if (p.extension(dir.path) == '.app') return dir;
      dir = dir.parent;
    }
    return null;
  }

  static Future<void> _defaultInstallerLauncher(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }
}

class MacOsPreparedUpdate {
  final Directory currentApp;
  final Directory newApp;
  final File helperScript;
  final File logFile;
  final bool requiresAdminPrivileges;

  const MacOsPreparedUpdate({
    required this.currentApp,
    required this.newApp,
    required this.helperScript,
    required this.logFile,
    this.requiresAdminPrivileges = false,
  });
}

class MacOsBundleInfo {
  final String bundleId;
  final String shortVersion;
  final String buildNumber;

  const MacOsBundleInfo({
    required this.bundleId,
    required this.shortVersion,
    required this.buildNumber,
  });
}

class UpdateInstallException implements Exception {
  final String message;

  const UpdateInstallException(this.message);

  @override
  String toString() => message;
}

const String _macOsHelperScript = r'''#!/bin/sh
set -u

CURRENT_APP="$1"
NEW_APP="$2"
DACX_PID="$3"
LOG_FILE="$4"

exec >>"$LOG_FILE" 2>&1

i=0
while kill -0 "$DACX_PID" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 120 ]; then
    echo "Timed out waiting for Dacx to quit."
    exit 1
  fi
  sleep 1
done

PARENT_DIR="$(dirname "$CURRENT_APP")"
APP_NAME="$(basename "$CURRENT_APP")"
BACKUP_APP="$PARENT_DIR/.${APP_NAME}.updater-backup-$(date +%s)"

if [ -d "$CURRENT_APP" ]; then
  mv "$CURRENT_APP" "$BACKUP_APP" || exit 1
fi

if ! ditto "$NEW_APP" "$CURRENT_APP"; then
  rm -rf "$CURRENT_APP"
  if [ -d "$BACKUP_APP" ]; then
    mv "$BACKUP_APP" "$CURRENT_APP"
  fi
  exit 1
fi

rm -rf "$BACKUP_APP"
open "$CURRENT_APP"
''';
