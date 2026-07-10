import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/player_path_utils.dart';
import 'package:dacx/services/open_file_bridge.dart';

import '../support/method_channel_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(OpenFileBridge.methodChannelName);
  const eventChannel = EventChannel(OpenFileBridge.eventChannelName);

  group('OpenFileBridge', () {
    late List<({OpenFileRequest request, bool forcePlay})> opened;
    late List<String> logEvents;
    late MethodChannelRecorder recorder;

    setUp(() {
      opened = [];
      logEvents = [];
      recorder = MethodChannelRecorder(OpenFileBridge.methodChannelName);
      recorder.install();
    });

    tearDown(() {
      recorder.uninstall();
    });

    OpenFileBridge buildBridge({
      bool Function()? isActive,
      Duration retryDelay = Duration.zero,
    }) {
      return OpenFileBridge(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
        retryDelay: retryDelay,
        isActive: isActive ?? () => true,
        onLog:
            (
              event, {
              message,
              details = const {},
              warn = false,
              error = false,
            }) {
              logEvents.add(event);
            },
        onOpenRequest: (request, {required bool forcePlay}) async {
          opened.add((request: request, forcePlay: forcePlay));
        },
      );
    }

    test('handlePlatformPayload opens coerced string paths', () async {
      final bridge = buildBridge();
      await bridge.handlePlatformPayload('/media/song.mp3');
      expect(opened, hasLength(1));
      expect(opened.first.request.path, '/media/song.mp3');
      expect(opened.first.forcePlay, isTrue);
      bridge.dispose();
    });

    test('handlePlatformPayload opens map payloads with bookmarks', () async {
      final bridge = buildBridge();
      await bridge.handlePlatformPayload({
        'path': '/media/video.mkv',
        'bookmark': 'bookmark-data',
      });
      expect(opened, hasLength(1));
      expect(opened.first.request.path, '/media/video.mkv');
      expect(opened.first.request.bookmark, 'bookmark-data');
      bridge.dispose();
    });

    test('handlePlatformPayload ignores invalid payloads', () async {
      final bridge = buildBridge();
      await bridge.handlePlatformPayload(null);
      await bridge.handlePlatformPayload({'path': ''});
      await bridge.handlePlatformPayload(42);
      expect(opened, isEmpty);
      bridge.dispose();
    });

    test('handlePlatformPayload respects isActive', () async {
      var active = false;
      final bridge = buildBridge(isActive: () => active);
      await bridge.handlePlatformPayload('/media/song.mp3');
      expect(opened, isEmpty);
      active = true;
      await bridge.handlePlatformPayload('/media/song.mp3');
      expect(opened, hasLength(1));
      bridge.dispose();
    });

    test('bootstrap drains pending files from method channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'getPendingFiles') {
              return ['/a.mp3', '/b.mp4'];
            }
            return null;
          });

      final bridge = buildBridge();
      await bridge.bootstrap();
      expect(opened.map((e) => e.request.path), ['/a.mp3', '/b.mp4']);
      expect(logEvents, contains('open_file_bridge_init'));
      expect(logEvents, contains('open_file_pending_found'));
      bridge.dispose();
    });

    test('bootstrap retries pending drain when plugin is missing', () async {
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method != 'getPendingFiles') return null;
            callCount++;
            if (callCount == 1) {
              throw MissingPluginException('missing');
            }
            return ['/retry.mp3'];
          });

      final bridge = buildBridge(retryDelay: Duration.zero);
      await bridge.bootstrap();
      await Future<void>.delayed(Duration.zero);
      expect(callCount, 2);
      expect(opened.map((e) => e.request.path), ['/retry.mp3']);
      expect(logEvents, contains('open_file_bridge_missing_plugin'));
      expect(logEvents, contains('open_file_pending_found_retry'));
      bridge.dispose();
    });

    test(
      'bootstrap is a no-op when isActive becomes false mid-drain',
      () async {
        var active = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              if (call.method == 'getPendingFiles') {
                active = false;
                return ['/late.mp3'];
              }
              return null;
            });

        final bridge = buildBridge(isActive: () => active);
        await bridge.bootstrap();
        expect(opened, isEmpty);
        bridge.dispose();
      },
    );
  });
}
