import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dacx/services/update_service.dart';

void main() {
  PackageInfo info(String v) => PackageInfo(
    appName: 'Dacx',
    packageName: 'run.rosie.dacx',
    version: v,
    buildNumber: '1',
    buildSignature: '',
    installerStore: null,
  );

  group('UpdateService error flags', () {
    test('403 sets lastCheckRateLimited', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response('rate limited', 403),
      );
      await svc.checkForUpdate();
      expect(svc.lastCheckRateLimited, isTrue);
      expect(svc.lastCheckSucceeded, isFalse);
      expect(svc.lastCheckNetworkError, isFalse);
    });

    test('429 sets lastCheckRateLimited', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response('too many', 429),
      );
      await svc.checkForUpdate();
      expect(svc.lastCheckRateLimited, isTrue);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('SocketException sets lastCheckNetworkError', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async =>
            throw const SocketException('No route to host'),
      );
      await svc.checkForUpdate();
      expect(svc.lastCheckNetworkError, isTrue);
      expect(svc.lastCheckRateLimited, isFalse);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('TimeoutException sets lastCheckNetworkError', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async =>
            throw TimeoutException('timed out', const Duration(seconds: 10)),
      );
      await svc.checkForUpdate();
      expect(svc.lastCheckNetworkError, isTrue);
      expect(svc.lastCheckSucceeded, isFalse);
    });

    test('flags are reset on each check', () async {
      var callCount = 0;
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async {
          callCount++;
          if (callCount == 1) return http.Response('rate limited', 403);
          return http.Response(
            '{"tag_name":"v0.6.0","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.6.0","body":""}',
            200,
          );
        },
      );

      await svc.checkForUpdate();
      expect(svc.lastCheckRateLimited, isTrue);

      await svc.checkForUpdate();
      expect(svc.lastCheckRateLimited, isFalse);
      expect(svc.lastCheckSucceeded, isTrue);
    });

    test('lastEffectiveChannel is set on successful check', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v0.5.0","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.5.0","body":""}',
          200,
        ),
      );
      await svc.checkForUpdate(channel: UpdateChannel.stable);
      expect(svc.lastEffectiveChannel, UpdateChannel.stable);
    });

    test('lastEffectiveChannel is null on failed check', () async {
      final svc = UpdateService(
        packageInfoLoader: () async => info('0.5.0'),
        httpGet: (uri, {headers}) async => http.Response('bad', 500),
      );
      await svc.checkForUpdate();
      expect(svc.lastEffectiveChannel, isNull);
    });
  });

  group('UpdateService beta fallback on rate-limit', () {
    test(
      'beta user on version newer than stable gets null when beta fetch rate-limited',
      () async {
        var requestCount = 0;
        final svc = UpdateService(
          packageInfoLoader: () async => info('0.10.0-beta.4'),
          currentVersionLoader: (_) async => '0.10.0-beta.4',
          httpGet: (uri, {headers}) async {
            requestCount++;
            final path = uri.toString();
            if (path.contains('/releases/latest')) {
              // Stable endpoint succeeds
              return http.Response(
                '{"tag_name":"v0.9.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.9.1","body":""}',
                200,
              );
            }
            // Beta list endpoint is rate-limited
            return http.Response('rate limited', 403);
          },
        );
        final update = await svc.checkForUpdate(channel: UpdateChannel.auto);
        expect(update, isNull);
        expect(svc.lastCheckRateLimited, isTrue);
        expect(svc.lastCheckSucceeded, isFalse);
        expect(requestCount, greaterThan(0));
      },
    );

    test(
      'beta user behind stable gets stable upgrade when beta fetch fails',
      () async {
        final svc = UpdateService(
          packageInfoLoader: () async => info('0.8.0-beta.1'),
          currentVersionLoader: (_) async => '0.8.0-beta.1',
          httpGet: (uri, {headers}) async {
            final path = uri.toString();
            if (path.contains('/releases/latest')) {
              return http.Response(
                '{"tag_name":"v0.9.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.9.1","body":""}',
                200,
              );
            }
            return http.Response('rate limited', 403);
          },
        );
        final update = await svc.checkForUpdate(channel: UpdateChannel.auto);
        expect(update, isNotNull);
        expect(update!.version, '0.9.1');
      },
    );

    test(
      'beta prefers newer stable over older beta when stable wins comparison',
      () async {
        final svc = UpdateService(
          packageInfoLoader: () async => info('0.9.0-beta.1'),
          currentVersionLoader: (_) async => '0.9.0-beta.1',
          httpGet: (uri, {headers}) async {
            final path = uri.toString();
            if (path.contains('/releases') && !path.contains('/latest')) {
              return http.Response(
                '[{"tag_name":"v0.9.0-beta.2","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.9.0-beta.2","body":"","prerelease":true,"draft":false}]',
                200,
              );
            }
            return http.Response(
              '{"tag_name":"v0.9.1","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.9.1","body":""}',
              200,
            );
          },
        );
        final update = await svc.checkForUpdate(channel: UpdateChannel.auto);
        expect(update, isNotNull);
        expect(update!.version, '0.9.1');
        expect(svc.lastEffectiveChannel, UpdateChannel.stable);
      },
    );
  });

  group('UpdateInfo and UpdateAsset', () {
    test('UpdateInfo stores all fields', () {
      const info = UpdateInfo(
        version: '1.2.3',
        url: 'https://example.com',
        notes: 'release notes',
        assets: [
          UpdateAsset(name: 'file.dmg', downloadUrl: 'https://dl.com/file.dmg'),
        ],
      );
      expect(info.version, '1.2.3');
      expect(info.url, 'https://example.com');
      expect(info.notes, 'release notes');
      expect(info.assets.length, 1);
      expect(info.assets.first.name, 'file.dmg');
      expect(info.assets.first.downloadUrl, 'https://dl.com/file.dmg');
    });

    test('UpdateInfo defaults to empty assets', () {
      const info = UpdateInfo(version: '1.0.0', url: 'https://x.com', notes: '');
      expect(info.assets, isEmpty);
    });
  });
}
