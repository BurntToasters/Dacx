import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dacx/services/allowed_get_redirect.dart';
import 'package:dacx/services/self_update_service.dart';

void main() {
  group('isHttpRedirectStatus', () {
    test('recognizes common redirect codes', () {
      for (final code in [301, 302, 303, 307, 308]) {
        expect(isHttpRedirectStatus(code), isTrue, reason: '$code');
      }
      expect(isHttpRedirectStatus(200), isFalse);
      expect(isHttpRedirectStatus(404), isFalse);
    });
  });

  group('fetchAllowedGetFollowingRedirects', () {
    const allowedStart =
        'https://github.com/BurntToasters/Dacx/releases/download/v1/Dacx.msi';
    const allowedCdn =
        'https://objects.githubusercontent.com/github-production-release-asset/abc';

    http.StreamedResponse response({
      required int status,
      String? location,
      List<int> body = const [],
    }) {
      return http.StreamedResponse(
        Stream<List<int>>.value(body),
        status,
        headers: location == null ? {} : {'location': location},
      );
    }

    test('returns non-redirect response directly', () async {
      final calls = <Uri>[];
      final result = await fetchAllowedGetFollowingRedirects(
        url: allowedStart,
        timeout: const Duration(seconds: 5),
        httpStream: (request) async {
          calls.add(request.url);
          expect(request.followRedirects, isFalse);
          return response(status: 200, body: [1, 2, 3]);
        },
        isAllowedUrl: SelfUpdateService.isAllowedDownloadUrl,
      );

      expect(result.statusCode, 200);
      expect(calls, [Uri.parse(allowedStart)]);
      expect(await result.stream.toBytes(), [1, 2, 3]);
    });

    test('follows redirect to another allowlisted host', () async {
      final calls = <Uri>[];
      final result = await fetchAllowedGetFollowingRedirects(
        url: allowedStart,
        timeout: const Duration(seconds: 5),
        httpStream: (request) async {
          calls.add(request.url);
          if (request.url.toString() == allowedStart) {
            return response(status: 302, location: allowedCdn);
          }
          return response(status: 200, body: [9]);
        },
        isAllowedUrl: SelfUpdateService.isAllowedDownloadUrl,
      );

      expect(result.statusCode, 200);
      expect(calls.map((u) => u.toString()).toList(), [
        allowedStart,
        allowedCdn,
      ]);
    });

    test('rejects initial non-allowlisted URL', () async {
      await expectLater(
        fetchAllowedGetFollowingRedirects(
          url: 'https://evil.example/msi',
          timeout: const Duration(seconds: 5),
          httpStream: (_) => throw StateError('should not fetch'),
          isAllowedUrl: SelfUpdateService.isAllowedDownloadUrl,
        ),
        throwsA(
          predicate<StateError>(
            (e) => e.message.contains('non-allowlisted host'),
          ),
        ),
      );
    });

    test('rejects redirect to non-allowlisted host', () async {
      await expectLater(
        fetchAllowedGetFollowingRedirects(
          url: allowedStart,
          timeout: const Duration(seconds: 5),
          httpStream: (_) async =>
              response(status: 302, location: 'https://evil.example/payload'),
          isAllowedUrl: SelfUpdateService.isAllowedDownloadUrl,
        ),
        throwsA(
          predicate<StateError>((e) => e.message.contains('Refusing redirect')),
        ),
      );
    });

    test('rejects redirect missing Location header', () async {
      await expectLater(
        fetchAllowedGetFollowingRedirects(
          url: allowedStart,
          timeout: const Duration(seconds: 5),
          httpStream: (_) async => response(status: 302),
          isAllowedUrl: SelfUpdateService.isAllowedDownloadUrl,
        ),
        throwsA(
          predicate<StateError>(
            (e) => e.message.contains('redirect missing Location'),
          ),
        ),
      );
    });

    test('rejects too many redirects', () async {
      await expectLater(
        fetchAllowedGetFollowingRedirects(
          url: allowedStart,
          timeout: const Duration(seconds: 5),
          maxRedirects: 1,
          httpStream: (_) async =>
              response(status: 302, location: '/still-here'),
          isAllowedUrl: SelfUpdateService.isAllowedDownloadUrl,
        ),
        throwsA(
          predicate<StateError>(
            (e) => e.message.contains('Too many redirects'),
          ),
        ),
      );
    });
  });
}
