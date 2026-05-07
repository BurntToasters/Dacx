import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'debug_log_service.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef HttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});
typedef CanLaunchUrlFn = Future<bool> Function(Uri uri);
typedef LaunchUrlFn = Future<bool> Function(Uri uri, {LaunchMode mode});

class UpdateService {
  static const String _owner = 'BurntToasters';
  static const String _repo = 'Dacx';
  static const String _windowsInstallerAssetName = 'Dacx-Windows-x64.msi';
  static const String _macOsZipAssetName = 'Dacx-macOS.zip';
  static final RegExp _versionPattern = RegExp(
    r'^\d+(?:\.\d+){0,2}(?:[-+][0-9A-Za-z.-]+)?$',
  );
  final DebugLogService? _debugLog;
  final String _debugSource;
  final PackageInfoLoader _packageInfoLoader;
  final HttpGet _httpGet;
  final CanLaunchUrlFn _canLaunch;
  final LaunchUrlFn _launch;
  bool _lastCheckSucceeded = false;

  UpdateService({
    DebugLogService? debugLog,
    String debugSource = 'unknown',
    PackageInfoLoader? packageInfoLoader,
    HttpGet? httpGet,
    CanLaunchUrlFn? canLaunch,
    LaunchUrlFn? launch,
  }) : _debugLog = debugLog,
       _debugSource = debugSource,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _httpGet = httpGet ?? http.get,
       _canLaunch = canLaunch ?? canLaunchUrl,
       _launch = launch ?? launchUrl;

  bool get lastCheckSucceeded => _lastCheckSucceeded;

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

  Future<UpdateInfo?> checkForUpdate() async {
    _lastCheckSucceeded = false;
    try {
      final packageInfo = await _packageInfoLoader();
      final currentVersion = packageInfo.version;
      _log(
        'check_started',
        detailsBuilder: () => {'current_version': currentVersion},
      );

      final uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      final response = await _httpGet(
        uri,
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _log(
          'check_http_non_200',
          severity: DebugSeverity.warn,
          detailsBuilder: () => {'status_code': response.statusCode},
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '').trim();
      final releaseUrl = data['html_url'] as String? ?? '';
      final notes = data['body'] as String? ?? '';
      final windowsInstaller = _parseWindowsInstallerAsset(data['assets']);
      final macOsZip = _parseMacOsZipAsset(data['assets']);

      if (!_versionPattern.hasMatch(latestVersion) ||
          !_isLaunchableUrl(releaseUrl)) {
        _log(
          'check_invalid_payload',
          severity: DebugSeverity.warn,
          detailsBuilder: () => {
            'tag_name': tagName,
            'latest_version': latestVersion,
            'url': releaseUrl,
          },
        );
        return null;
      }

      if (_isNewer(latestVersion, currentVersion)) {
        _lastCheckSucceeded = true;
        _log(
          'update_available',
          detailsBuilder: () => {
            'latest_version': latestVersion,
            'current_version': currentVersion,
          },
        );
        return UpdateInfo(
          version: latestVersion,
          url: releaseUrl,
          notes: notes,
          windowsInstallerUrl: windowsInstaller?.url,
          windowsInstallerAssetName: windowsInstaller?.name,
          windowsInstallerSize: windowsInstaller?.size,
          windowsInstallerSha256: windowsInstaller?.sha256,
          macOsZipUrl: macOsZip?.url,
          macOsZipAssetName: macOsZip?.name,
          macOsZipSize: macOsZip?.size,
          macOsZipSha256: macOsZip?.sha256,
        );
      }

      _lastCheckSucceeded = true;
      _log(
        'up_to_date',
        detailsBuilder: () => {
          'latest_version': latestVersion,
          'current_version': currentVersion,
        },
      );
      return null;
    } catch (e) {
      _log(
        'check_failed',
        severity: DebugSeverity.error,
        message: e.toString(),
      );
      return null;
    }
  }

  Future<void> openReleasePage(String url) async {
    if (!_isLaunchableUrl(url)) {
      _log(
        'open_release_page_failed',
        severity: DebugSeverity.warn,
        detailsBuilder: () => {'url': url},
      );
      return;
    }
    final uri = Uri.parse(url);
    _log('open_release_page_requested', detailsBuilder: () => {'url': url});
    if (await _canLaunch(uri)) {
      await _launch(uri, mode: LaunchMode.externalApplication);
      _log('open_release_page_launched', detailsBuilder: () => {'url': url});
      return;
    }
    _log(
      'open_release_page_failed',
      severity: DebugSeverity.warn,
      detailsBuilder: () => {'url': url},
    );
  }

  bool _isLaunchableUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    if (!uri.hasScheme || uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    const allowedHosts = {
      'github.com',
      'www.github.com',
      'objects.githubusercontent.com',
    };
    return allowedHosts.contains(uri.host.toLowerCase());
  }

  bool _isInstallerDownloadUrl(String value) {
    return _isReleaseAssetUrl(value, '.msi');
  }

  bool _isMacOsZipDownloadUrl(String value) {
    return _isReleaseAssetUrl(value, '.zip');
  }

  bool _isReleaseAssetUrl(String value, String extension) {
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

  _WindowsInstallerAsset? _parseWindowsInstallerAsset(Object? value) {
    if (value is! List) return null;
    for (final rawAsset in value) {
      if (rawAsset is! Map) continue;
      final asset = rawAsset.cast<String, dynamic>();
      final name = asset['name'] as String? ?? '';
      if (name != _windowsInstallerAssetName) continue;
      final url = asset['browser_download_url'] as String? ?? '';
      if (!_isInstallerDownloadUrl(url)) return null;
      final digest = asset['digest'] as String?;
      return _WindowsInstallerAsset(
        name: name,
        url: url,
        size: asset['size'] is int ? asset['size'] as int : null,
        sha256: digest != null && digest.startsWith('sha256:')
            ? digest.substring('sha256:'.length)
            : null,
      );
    }
    return null;
  }

  _ReleaseAsset? _parseMacOsZipAsset(Object? value) {
    if (value is! List) return null;
    for (final rawAsset in value) {
      if (rawAsset is! Map) continue;
      final asset = rawAsset.cast<String, dynamic>();
      final name = asset['name'] as String? ?? '';
      if (name != _macOsZipAssetName) continue;
      final url = asset['browser_download_url'] as String? ?? '';
      if (!_isMacOsZipDownloadUrl(url)) return null;
      final digest = asset['digest'] as String?;
      return _ReleaseAsset(
        name: name,
        url: url,
        size: asset['size'] is int ? asset['size'] as int : null,
        sha256: digest != null && digest.startsWith('sha256:')
            ? digest.substring('sha256:'.length)
            : null,
      );
    }
    return null;
  }

  static List<int> _numericParts(String version) {
    return _stripPreRelease(
      version,
    ).split('.').map((p) => int.tryParse(p) ?? 0).toList(growable: false);
  }

  static String _stripPreRelease(String v) =>
      v.split('-').first.split('+').first;

  bool _isNewer(String latest, String current) {
    final latestParts = _numericParts(latest);
    final currentParts = _numericParts(current);

    for (var i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    // Numeric components equal — compare pre-release tags. Per semver, a
    // version without pre-release is considered greater than one with.
    final latestPre = _preReleaseTag(latest);
    final currentPre = _preReleaseTag(current);
    if (latestPre.isEmpty && currentPre.isNotEmpty) return true;
    if (latestPre.isNotEmpty && currentPre.isEmpty) return false;
    return latestPre.compareTo(currentPre) > 0;
  }

  static String _preReleaseTag(String v) {
    final dashIdx = v.indexOf('-');
    if (dashIdx < 0) return '';
    return v.substring(dashIdx + 1).split('+').first;
  }
}

class UpdateInfo {
  final String version;
  final String url;
  final String notes;
  final String? windowsInstallerUrl;
  final String? windowsInstallerAssetName;
  final int? windowsInstallerSize;
  final String? windowsInstallerSha256;
  final String? macOsZipUrl;
  final String? macOsZipAssetName;
  final int? macOsZipSize;
  final String? macOsZipSha256;

  const UpdateInfo({
    required this.version,
    required this.url,
    required this.notes,
    this.windowsInstallerUrl,
    this.windowsInstallerAssetName,
    this.windowsInstallerSize,
    this.windowsInstallerSha256,
    this.macOsZipUrl,
    this.macOsZipAssetName,
    this.macOsZipSize,
    this.macOsZipSha256,
  });

  bool get hasWindowsInstaller => windowsInstallerUrl != null;
  bool get hasMacOsZip => macOsZipUrl != null;
}

class _ReleaseAsset {
  final String name;
  final String url;
  final int? size;
  final String? sha256;

  const _ReleaseAsset({
    required this.name,
    required this.url,
    this.size,
    this.sha256,
  });
}

typedef _WindowsInstallerAsset = _ReleaseAsset;
