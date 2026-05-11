import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'debug_log_service.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef CurrentVersionLoader = Future<String> Function(PackageInfo packageInfo);
typedef HttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});
typedef CanLaunchUrlFn = Future<bool> Function(Uri uri);
typedef LaunchUrlFn = Future<bool> Function(Uri uri, {LaunchMode mode});

enum UpdateChannel { auto, stable, beta }

class UpdateService {
  static const String _owner = 'BurntToasters';
  static const String _repo = 'Dacx';
  static final RegExp _versionPattern = RegExp(
    r'^\d+(?:\.\d+){0,2}(?:[-+][0-9A-Za-z.-]+)?$',
  );
  final DebugLogService? _debugLog;
  final String _debugSource;
  final PackageInfoLoader _packageInfoLoader;
  final CurrentVersionLoader _currentVersionLoader;
  final HttpGet _httpGet;
  final CanLaunchUrlFn _canLaunch;
  final LaunchUrlFn _launch;
  bool _lastCheckSucceeded = false;

  UpdateService({
    DebugLogService? debugLog,
    String debugSource = 'unknown',
    PackageInfoLoader? packageInfoLoader,
    CurrentVersionLoader? currentVersionLoader,
    HttpGet? httpGet,
    CanLaunchUrlFn? canLaunch,
    LaunchUrlFn? launch,
  }) : _debugLog = debugLog,
       _debugSource = debugSource,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _currentVersionLoader =
           currentVersionLoader ?? currentVersionFromPackageInfo,
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

  static UpdateChannel resolveChannel(
    UpdateChannel choice,
    String currentVersion,
  ) {
    if (choice != UpdateChannel.auto) return choice;
    return currentVersion.contains('-')
        ? UpdateChannel.beta
        : UpdateChannel.stable;
  }

  static Future<String> currentVersionFromPlatform() async {
    return currentVersionFromPackageInfo(await PackageInfo.fromPlatform());
  }

  static Future<String> currentVersionFromPackageInfo(
    PackageInfo packageInfo,
  ) async {
    final macOSReleaseVersion = await _macOSReleaseVersionFromRunningBundle();
    if (macOSReleaseVersion != null &&
        _versionPattern.hasMatch(macOSReleaseVersion)) {
      return macOSReleaseVersion;
    }
    if (Platform.isMacOS) {
      return normalizeMacOSPackageVersion(packageInfo.version);
    }
    return packageInfo.version;
  }

  static String normalizeMacOSPackageVersion(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) return version;
    return '${match[1]}.${match[2]}.${match[3]}-beta.${match[4]}';
  }

  static Future<String?> _macOSReleaseVersionFromRunningBundle() async {
    if (!Platform.isMacOS) return null;
    final exe = Platform.resolvedExecutable;
    const marker = '.app/Contents/MacOS/';
    final idx = exe.indexOf(marker);
    if (idx < 0) return null;
    final appPath = exe.substring(0, idx + '.app'.length);
    final infoPlist = '$appPath/Contents/Info.plist';
    return readBundleInfoString(infoPlist, 'DacxReleaseVersion');
  }

  static Future<String?> readBundleInfoString(
    String infoPlistPath,
    String key,
  ) async {
    try {
      return parseBundleInfoString(
        await File(infoPlistPath).readAsString(),
        key,
      );
    } catch (_) {
      return null;
    }
  }

  static String? parseBundleInfoString(String plistXml, String key) {
    final match = RegExp(
      '<key>\\s*${RegExp.escape(key)}\\s*</key>\\s*<string>(.*?)</string>',
      dotAll: true,
    ).firstMatch(plistXml);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<UpdateInfo?> checkForUpdate({
    UpdateChannel channel = UpdateChannel.auto,
  }) async {
    _lastCheckSucceeded = false;
    try {
      final packageInfo = await _packageInfoLoader();
      final currentVersion = await _currentVersionLoader(packageInfo);
      final resolved = resolveChannel(channel, currentVersion);
      _log(
        'check_started',
        detailsBuilder: () => {
          'current_version': currentVersion,
          'channel': channel.name,
          'resolved_channel': resolved.name,
        },
      );

      final release = resolved == UpdateChannel.beta
          ? await _fetchLatestPrerelease()
          : await _fetchLatestStable();
      if (release == null) return null;

      final latestVersion = release.tagName
          .replaceFirst(RegExp(r'^v'), '')
          .trim();

      if (!_versionPattern.hasMatch(latestVersion) ||
          !_isLaunchableUrl(release.htmlUrl)) {
        _log(
          'check_invalid_payload',
          severity: DebugSeverity.warn,
          detailsBuilder: () => {
            'tag_name': release.tagName,
            'latest_version': latestVersion,
            'url': release.htmlUrl,
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
            'resolved_channel': resolved.name,
          },
        );
        final viewUrl = resolved == UpdateChannel.beta
            ? release.htmlUrl
            : 'https://rosie.run/dacx/update?from=v$currentVersion';
        return UpdateInfo(
          version: latestVersion,
          url: viewUrl,
          notes: release.body,
          assets: release.assets,
        );
      }

      _lastCheckSucceeded = true;
      _log(
        'up_to_date',
        detailsBuilder: () => {
          'latest_version': latestVersion,
          'current_version': currentVersion,
          'resolved_channel': resolved.name,
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

  Future<_Release?> _fetchLatestStable() async {
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
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      _log('check_invalid_payload', severity: DebugSeverity.warn);
      return null;
    }
    return _Release.fromJson(data);
  }

  Future<_Release?> _fetchLatestPrerelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$_owner/$_repo/releases',
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
    final data = jsonDecode(response.body);
    if (data is! List) {
      _log('check_invalid_payload', severity: DebugSeverity.warn);
      return null;
    }
    final candidates = <_Release>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['draft'] == true) continue;
      if (entry['prerelease'] != true) continue;
      final release = _Release.fromJson(entry);
      final version = release.tagName.replaceFirst(RegExp(r'^v'), '').trim();
      if (!_versionPattern.hasMatch(version)) continue;
      if (!_isLaunchableUrl(release.htmlUrl)) continue;
      candidates.add(release);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final av = a.tagName.replaceFirst(RegExp(r'^v'), '').trim();
      final bv = b.tagName.replaceFirst(RegExp(r'^v'), '').trim();
      return compareVersions(bv, av);
    });
    return candidates.first;
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
      'rosie.run',
      'www.rosie.run',
    };
    return allowedHosts.contains(uri.host.toLowerCase());
  }

  static List<int> _numericParts(String version) {
    return _stripPreRelease(
      version,
    ).split('.').map((p) => int.tryParse(p) ?? 0).toList(growable: false);
  }

  static String _stripPreRelease(String v) =>
      v.split('-').first.split('+').first;

  bool _isNewer(String latest, String current) =>
      compareVersions(latest, current) > 0;

  static int compareVersions(String a, String b) {
    final aParts = _numericParts(a);
    final bParts = _numericParts(b);
    for (var i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return _comparePreRelease(_preReleaseTag(a), _preReleaseTag(b));
  }

  static int _comparePreRelease(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    final aParts = a.split('.');
    final bParts = b.split('.');
    final n = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < n; i++) {
      final cmp = _comparePreReleaseIdentifier(aParts[i], bParts[i]);
      if (cmp != 0) return cmp;
    }
    return aParts.length.compareTo(bParts.length);
  }

  static int _comparePreReleaseIdentifier(String a, String b) {
    final aNum = int.tryParse(a);
    final bNum = int.tryParse(b);
    if (aNum != null && bNum != null) return aNum.compareTo(bNum);
    if (aNum != null) return -1;
    if (bNum != null) return 1;
    return a.compareTo(b);
  }

  static String _preReleaseTag(String v) {
    final dashIdx = v.indexOf('-');
    if (dashIdx < 0) return '';
    return v.substring(dashIdx + 1).split('+').first;
  }
}

class _Release {
  final String tagName;
  final String htmlUrl;
  final String body;
  final List<UpdateAsset> assets;

  const _Release({
    required this.tagName,
    required this.htmlUrl,
    required this.body,
    this.assets = const [],
  });

  factory _Release.fromJson(Map<String, dynamic> data) {
    final rawAssets = data['assets'];
    final parsedAssets = <UpdateAsset>[];
    if (rawAssets is List) {
      for (final entry in rawAssets) {
        if (entry is! Map<String, dynamic>) continue;
        final name = entry['name'] as String? ?? '';
        final url = entry['browser_download_url'] as String? ?? '';
        if (name.isEmpty || url.isEmpty) continue;
        parsedAssets.add(UpdateAsset(name: name, downloadUrl: url));
      }
    }
    return _Release(
      tagName: data['tag_name'] as String? ?? '',
      htmlUrl: data['html_url'] as String? ?? '',
      body: data['body'] as String? ?? '',
      assets: parsedAssets,
    );
  }
}

class UpdateAsset {
  final String name;
  final String downloadUrl;

  const UpdateAsset({required this.name, required this.downloadUrl});
}

class UpdateInfo {
  final String version;
  final String url;
  final String notes;
  final List<UpdateAsset> assets;

  const UpdateInfo({
    required this.version,
    required this.url,
    required this.notes,
    this.assets = const [],
  });
}
