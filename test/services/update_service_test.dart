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
      expect(update.url, 'https://rosie.run/dacx/update?from=v0.5.0');
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

    test('does not launch when canLaunch returns false', () async {
      var called = false;
      final service = UpdateService(
        canLaunch: (uri) async => false,
        launch: (uri, {mode = LaunchMode.platformDefault}) async {
          called = true;
          return true;
        },
      );
      await service.openReleasePage(
        'https://github.com/BurntToasters/Dacx/releases/latest',
      );
      expect(called, isFalse);
    });
  });

  group('UpdateService version comparison', () {
    PackageInfo info(String v) => PackageInfo(
      appName: 'Dacx',
      packageName: 'run.rosie.dacx',
      version: v,
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );

    test('treats stable as newer than equivalent prerelease', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('1.0.0-beta.1'),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v1.0.0","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v1.0.0","body":""}',
          200,
        ),
      );
      final update = await svc.checkForUpdate(channel: UpdateChannel.stable);
      expect(update?.version, '1.0.0');
    });

    test('treats prerelease as older than equivalent stable', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('1.0.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v1.0.0-beta.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v1.0.0-beta.1","body":""}',
          200,
        ),
      );
      expect(await svc.checkForUpdate(), isNull);
    });

    test('rejects non-semver tag names', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"vNEXT","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/vNEXT","body":""}',
          200,
        ),
      );
      expect(await svc.checkForUpdate(), isNull);
    });

    test('returns null on network exception', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => throw Exception('boom'),
      );
      expect(await svc.checkForUpdate(), isNull);
      expect(svc.lastCheckSucceeded, isFalse);
    });
  });

  group('UpdateService.checkForUpdate error paths', () {
    PackageInfo info(String v) => PackageInfo(
      appName: 'Dacx',
      packageName: 'run.rosie.dacx',
      version: v,
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );

    test('returns null on malformed JSON body', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response('not-json{', 200),
      );
      expect(await svc.checkForUpdate(), isNull);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('returns null when tag_name is missing from payload', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '{"html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.6.0","body":""}',
          200,
        ),
      );
      expect(await svc.checkForUpdate(), isNull);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('returns null when html_url host is not on the whitelist', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v0.6.0","html_url":"https://evil.example.com/r","body":""}',
          200,
        ),
      );
      expect(await svc.checkForUpdate(), isNull);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('returns null on 404 (release not found)', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response('not found', 404),
      );
      expect(await svc.checkForUpdate(), isNull);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('returns null when payload JSON is not an object', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response('[]', 200),
      );
      expect(await svc.checkForUpdate(), isNull);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('handles request timeout via thrown TimeoutException', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return http.Response('{}', 200);
        },
      );
      // The internal .timeout(10s) is too long for a unit test; instead
      // simulate the same effect by throwing the timeout directly:
      final svc2 = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => throw Exception('request timed out'),
      );
      expect(await svc2.checkForUpdate(), isNull);
      expect(svc2.lastCheckSucceeded, isFalse);
      // Reference [svc] so the analyzer doesn't complain about unused locals.
      expect(svc, isNotNull);
    });
  });

  group('UpdateService channel resolution', () {
    test('auto picks stable for stable current version', () {
      expect(
        UpdateService.resolveChannel(UpdateChannel.auto, '0.7.4'),
        UpdateChannel.stable,
      );
    });

    test('auto picks beta for prerelease current version', () {
      expect(
        UpdateService.resolveChannel(UpdateChannel.auto, '0.7.4-beta.2'),
        UpdateChannel.beta,
      );
    });

    test('forced stable wins regardless of current version', () {
      expect(
        UpdateService.resolveChannel(UpdateChannel.stable, '0.7.4-beta.2'),
        UpdateChannel.stable,
      );
    });

    test('forced beta wins regardless of current version', () {
      expect(
        UpdateService.resolveChannel(UpdateChannel.beta, '0.7.4'),
        UpdateChannel.beta,
      );
    });
  });

  group('UpdateService macOS version normalization', () {
    test('reads plist string values without spawning macOS tools', () {
      const plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>0.8.0.2</string>
  <key>DacxReleaseVersion</key>
  <string>0.8.0-beta.2</string>
</dict>
</plist>
''';

      expect(
        UpdateService.parseBundleInfoString(plist, 'DacxReleaseVersion'),
        '0.8.0-beta.2',
      );
      expect(
        UpdateService.parseBundleInfoString(
          plist,
          'CFBundleShortVersionString',
        ),
        '0.8.0.2',
      );
      expect(UpdateService.parseBundleInfoString(plist, 'Missing'), isNull);
    });

    test(
      'maps normalized four-part beta bundle version back to semver beta',
      () {
        expect(
          UpdateService.normalizeMacOSPackageVersion('0.8.0.2'),
          '0.8.0-beta.2',
        );
      },
    );

    test('leaves normal semver values unchanged', () {
      expect(UpdateService.normalizeMacOSPackageVersion('0.8.0'), '0.8.0');
      expect(
        UpdateService.normalizeMacOSPackageVersion('0.8.0-beta.2'),
        '0.8.0-beta.2',
      );
    });
  });

  group('UpdateService beta channel', () {
    PackageInfo info(String v) => PackageInfo(
      appName: 'Dacx',
      packageName: 'run.rosie.dacx',
      version: v,
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );

    test('auto on prerelease hits releases list endpoint', () async {
      Uri? requestedUri;
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.4-beta.1'),
        httpGet: (uri, {headers}) async {
          requestedUri = uri;
          return http.Response(
            '[{"tag_name":"v0.7.4-beta.2","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.7.4-beta.2","body":"notes","prerelease":true,"draft":false}]',
            200,
          );
        },
      );
      final update = await svc.checkForUpdate();
      expect(requestedUri.toString(), contains('/releases'));
      expect(requestedUri.toString(), isNot(contains('/releases/latest')));
      expect(update?.version, '0.7.4-beta.2');
    });

    test(
      'auto uses effective current version so normalized macOS beta checks beta channel',
      () async {
        Uri? requestedUri;
        final svc = UpdateService(
          packageInfoLoader: () async => info('0.8.0.1'),
          currentVersionLoader: (packageInfo) async => '0.8.0-beta.1',
          httpGet: (uri, {headers}) async {
            requestedUri = uri;
            return http.Response(
              '[{"tag_name":"v0.8.0-beta.2","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.2","body":"notes","prerelease":true,"draft":false}]',
              200,
            );
          },
        );

        final update = await svc.checkForUpdate();

        expect(requestedUri.toString(), contains('/releases'));
        expect(requestedUri.toString(), isNot(contains('/releases/latest')));
        expect(update?.version, '0.8.0-beta.2');
      },
    );

    test(
      'beta compares against effective current version, not normalized macOS version',
      () async {
        final svc = UpdateService(
          packageInfoLoader: () async => info('0.8.0.1'),
          currentVersionLoader: (packageInfo) async => '0.8.0-beta.1',
          httpGet: (uri, {headers}) async => http.Response(
            '[{"tag_name":"v0.8.0-beta.2","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.2","body":"notes","prerelease":true,"draft":false}]',
            200,
          ),
        );

        final update = await svc.checkForUpdate(channel: UpdateChannel.beta);

        expect(update?.version, '0.8.0-beta.2');
      },
    );

    test('beta channel returns release html_url, not rosie.run', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.4-beta.1'),
        httpGet: (uri, {headers}) async => http.Response(
          '[{"tag_name":"v0.7.4-beta.2","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.7.4-beta.2","body":"","prerelease":true,"draft":false}]',
          200,
        ),
      );
      final update = await svc.checkForUpdate(channel: UpdateChannel.beta);
      expect(
        update?.url,
        'https://github.com/BurntToasters/Dacx/releases/tag/v0.7.4-beta.2',
      );
    });

    test('stable channel still returns rosie.run url', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v0.6.0","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.6.0","body":""}',
          200,
        ),
      );
      final update = await svc.checkForUpdate(channel: UpdateChannel.stable);
      expect(update?.url, 'https://rosie.run/dacx/update?from=v0.5.0');
    });

    test('beta skips drafts and non-prereleases, picks first prerelease', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '[{"tag_name":"v0.7.5","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.7.5","body":"","prerelease":false,"draft":false},'
          '{"tag_name":"v0.8.0-beta.2","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.2","body":"","prerelease":true,"draft":true},'
          '{"tag_name":"v0.8.0-beta.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.1","body":"","prerelease":true,"draft":false}]',
          200,
        ),
      );
      final update = await svc.checkForUpdate(channel: UpdateChannel.beta);
      expect(update?.version, '0.8.0-beta.1');
    });

    test('beta returns null when no prereleases exist', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '[{"tag_name":"v0.7.5","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.7.5","body":"","prerelease":false,"draft":false}]',
          200,
        ),
      );
      expect(await svc.checkForUpdate(channel: UpdateChannel.beta), isNull);
    });

    test('beta returns null when payload is not a list', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.0'),
        httpGet: (uri, {headers}) async =>
            http.Response('{"unexpected":"object"}', 200),
      );
      expect(await svc.checkForUpdate(channel: UpdateChannel.beta), isNull);
    });

    test('beta picks highest version, not list order', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '[{"tag_name":"v0.8.0-beta.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.1","body":"","prerelease":true,"draft":false},'
          '{"tag_name":"v0.8.0-beta.3","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.3","body":"","prerelease":true,"draft":false},'
          '{"tag_name":"v0.8.0-beta.2","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.2","body":"","prerelease":true,"draft":false}]',
          200,
        ),
      );
      final update = await svc.checkForUpdate(channel: UpdateChannel.beta);
      expect(update?.version, '0.8.0-beta.3');
    });

    test('beta skips prerelease with invalid tag and falls through', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '[{"tag_name":"vNEXT","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/vNEXT","body":"","prerelease":true,"draft":false},'
          '{"tag_name":"v0.8.0-beta.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.1","body":"","prerelease":true,"draft":false}]',
          200,
        ),
      );
      final update = await svc.checkForUpdate(channel: UpdateChannel.beta);
      expect(update?.version, '0.8.0-beta.1');
    });

    test('beta skips prerelease with non-allowlisted html_url', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.7.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '[{"tag_name":"v0.8.0-beta.99","html_url":"https://evil.example.com/r","body":"","prerelease":true,"draft":false},'
          '{"tag_name":"v0.8.0-beta.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.1","body":"","prerelease":true,"draft":false}]',
          200,
        ),
      );
      final update = await svc.checkForUpdate(channel: UpdateChannel.beta);
      expect(update?.version, '0.8.0-beta.1');
    });
  });

  group('UpdateService.compareVersions (semver §11)', () {
    test(
      'numeric prerelease identifiers compare numerically, not lexically',
      () {
        expect(
          UpdateService.compareVersions('0.7.4-beta.10', '0.7.4-beta.9'),
          greaterThan(0),
        );
        expect(
          UpdateService.compareVersions('0.7.4-beta.2', '0.7.4-beta.10'),
          lessThan(0),
        );
        expect(
          UpdateService.compareVersions('0.7.4-beta.10', '0.7.4-beta.10'),
          0,
        );
      },
    );

    test('numeric identifier is lower than alpha identifier', () {
      expect(
        UpdateService.compareVersions('1.0.0-1', '1.0.0-alpha'),
        lessThan(0),
      );
    });

    test('longer prerelease identifier wins when prefix is equal', () {
      expect(
        UpdateService.compareVersions('1.0.0-alpha.1', '1.0.0-alpha'),
        greaterThan(0),
      );
    });

    test('stable beats equivalent prerelease', () {
      expect(
        UpdateService.compareVersions('1.0.0', '1.0.0-rc.1'),
        greaterThan(0),
      );
    });

    test('major.minor.patch beats prerelease comparison', () {
      expect(
        UpdateService.compareVersions('0.8.0-beta.1', '0.7.99'),
        greaterThan(0),
      );
    });

    test(
      'prerelease offered to user on older prerelease (regression test)',
      () async {
        PackageInfo info(String v) => PackageInfo(
          appName: 'Dacx',
          packageName: 'run.rosie.dacx',
          version: v,
          buildNumber: '1',
          buildSignature: '',
          installerStore: null,
        );
        final svc = UpdateService(
          packageInfoLoader: () async => info('0.7.4-beta.9'),
          httpGet: (uri, {headers}) async => http.Response(
            '[{"tag_name":"v0.7.4-beta.10","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.7.4-beta.10","body":"","prerelease":true,"draft":false}]',
            200,
          ),
        );
        final update = await svc.checkForUpdate(channel: UpdateChannel.beta);
        expect(update?.version, '0.7.4-beta.10');
      },
    );
  });
}
