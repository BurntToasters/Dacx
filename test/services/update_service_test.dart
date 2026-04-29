import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dacx/services/update_service.dart';

void main() {
  group('UpdateService.checkForUpdate', () {
    test('returns update when latest version is newer', () async {
      final service = UpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'Dacx',
          packageName: 'run.rosie.dacx',
          version: '0.5.0',
          buildNumber: '1',
          buildSignature: '',
          installerStore: null,
        ),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v0.6.0","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.6.0","body":"notes"}',
          200,
        ),
      );

      final update = await service.checkForUpdate();

      expect(update, isNotNull);
      expect(update!.version, '0.6.0');
      expect(update.url, contains('https://github.com/BurntToasters/Dacx'));
      expect(service.lastCheckSucceeded, isTrue);
    });

    test('returns null for non-200 and marks check failed', () async {
      final service = UpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'Dacx',
          packageName: 'run.rosie.dacx',
          version: '0.5.0',
          buildNumber: '1',
          buildSignature: '',
          installerStore: null,
        ),
        httpGet: (uri, {headers}) async => http.Response('bad', 500),
      );

      final update = await service.checkForUpdate();

      expect(update, isNull);
      expect(service.lastCheckSucceeded, isFalse);
    });

    test('rejects non-https release url in payload', () async {
      final service = UpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'Dacx',
          packageName: 'run.rosie.dacx',
          version: '0.5.0',
          buildNumber: '1',
          buildSignature: '',
          installerStore: null,
        ),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v0.6.0","html_url":"http://example.com/release","body":"notes"}',
          200,
        ),
      );

      final update = await service.checkForUpdate();

      expect(update, isNull);
      expect(service.lastCheckSucceeded, isFalse);
    });
  });

  group('UpdateService.openReleasePage', () {
    test('launches valid https url', () async {
      Uri? launchedUri;
      LaunchMode? launchedMode;

      final service = UpdateService(
        canLaunch: (uri) async => true,
        launch: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUri = uri;
          launchedMode = mode;
          return true;
        },
      );

      await service.openReleasePage(
        'https://github.com/BurntToasters/Dacx/releases/latest',
      );

      expect(launchedUri, isNotNull);
      expect(
        launchedUri.toString(),
        'https://github.com/BurntToasters/Dacx/releases/latest',
      );
      expect(launchedMode, LaunchMode.externalApplication);
    });

    test('does not launch non-https url', () async {
      var called = false;
      final service = UpdateService(
        canLaunch: (uri) async => true,
        launch: (uri, {mode = LaunchMode.platformDefault}) async {
          called = true;
          return true;
        },
      );

      await service.openReleasePage('http://example.com/release');

      expect(called, isFalse);
    });
  });
}
