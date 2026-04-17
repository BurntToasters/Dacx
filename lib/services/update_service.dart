import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _owner = 'BurntToasters';
  static const String _repo = 'DACX';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      final response = await http.get(uri, headers: {
        'Accept': 'application/vnd.github.v3+json',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');

      if (_isNewer(latestVersion, currentVersion)) {
        return UpdateInfo(
          version: latestVersion,
          url: data['html_url'] as String? ?? '',
          notes: data['body'] as String? ?? '',
        );
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static String _stripPreRelease(String v) => v.split('-').first;

  bool _isNewer(String latest, String current) {
    final latestParts = _stripPreRelease(latest).split('.').map(int.tryParse).toList();
    final currentParts = _stripPreRelease(current).split('.').map(int.tryParse).toList();

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
