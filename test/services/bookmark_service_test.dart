import 'dart:io';
import 'package:dacx/services/bookmark_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('run.rosie.dacx/bookmarks');
  final List<MethodCall> calls = [];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'create') {
            return 'test-token';
          }
          if (call.method == 'resolveAndStart') {
            return {
              'path': '/test/path.mp3',
              'token': 'resolved-token',
              'stale': true,
              'refreshed': 'new-token',
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ResolvedBookmark', () {
    test('carries properties correctly', () {
      const resolved = ResolvedBookmark(
        path: '/a.mp3',
        token: 'tok',
        stale: false,
        refreshed: 'ref',
      );
      expect(resolved.path, '/a.mp3');
      expect(resolved.token, 'tok');
      expect(resolved.stale, isFalse);
      expect(resolved.refreshed, 'ref');
    });
  });

  group('BookmarkService', () {
    test('isSupported mirrors platform OS', () {
      expect(BookmarkService.isSupported, Platform.isMacOS);
    });

    test('createBookmark invokes platform channel on macOS', () async {
      if (!Platform.isMacOS) return;

      final token = await BookmarkService.createBookmark('/movie.mp4');
      expect(token, 'test-token');
      expect(calls, hasLength(1));
      expect(calls.first.method, 'create');
      expect(calls.first.arguments, {'path': '/movie.mp4'});
    });

    test('resolveAndStart resolves values on macOS', () async {
      if (!Platform.isMacOS) return;

      final res = await BookmarkService.resolveAndStart('some-bookmark');
      expect(res, isNotNull);
      expect(res!.path, '/test/path.mp3');
      expect(res.token, 'resolved-token');
      expect(res.stale, isTrue);
      expect(res.refreshed, 'new-token');

      expect(calls, hasLength(1));
      expect(calls.first.method, 'resolveAndStart');
      expect(calls.first.arguments, {'bookmark': 'some-bookmark'});
    });

    test('stop invokes platform channel stop on macOS', () async {
      if (!Platform.isMacOS) return;

      await BookmarkService.stop('resolved-token');
      expect(calls, hasLength(1));
      expect(calls.first.method, 'stop');
      expect(calls.first.arguments, {'token': 'resolved-token'});
    });

    test('resolveAndStart returns null on malformed path', () async {
      if (!Platform.isMacOS) return;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return {'path': '', 'token': 'token'};
          });

      final res = await BookmarkService.resolveAndStart('some-bookmark');
      expect(res, isNull);
    });
  });
}
