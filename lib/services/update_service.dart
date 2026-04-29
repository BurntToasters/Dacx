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
    return uri.hasScheme &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        !uri.hasPort;
  }

  static String _stripPreRelease(String v) => v.split('-').first;

  bool _isNewer(String latest, String current) {
    final latestParts = _stripPreRelease(
      latest,
    ).split('.').map(int.tryParse).toList();
    final currentParts = _stripPreRelease(
      current,
    ).split('.').map(int.tryParse).toList();

    for (var i = 0; i < 3; i++) {
      final l = (i < latestParts.length ? latestParts[i] : 0) ?? 0;
      final c = (i < currentParts.length ? currentParts[i] : 0) ?? 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}

class UpdateInfo {
  final String version;
  final String url;
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.url,
    required this.notes,
  });
}
