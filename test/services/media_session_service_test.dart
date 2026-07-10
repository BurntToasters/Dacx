import 'dart:io';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/media_session_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('run.rosie.dacx/media_session');

  late DebugLogService log;
  late List<MethodCall> nativeCalls;

  setUp(() {
    log = DebugLogService(isEnabled: () => true);
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MediaSessionCommand', () {
    test('stores action, positionMs and value', () {
      const cmd = MediaSessionCommand('seek', 5000, value: 1.5);
      expect(cmd.action, 'seek');
      expect(cmd.positionMs, 5000);
      expect(cmd.value, 1.5);
    });

    test('value defaults to null', () {
      const cmd = MediaSessionCommand('play', null);
      expect(cmd.action, 'play');
      expect(cmd.positionMs, isNull);
      expect(cmd.value, isNull);
    });
  });

  group('MediaSessionService', () {
    test('updateMetadata is a no-op when disabled', () async {
      final svc = MediaSessionService(debugLog: log);
      // Not enabled → should not invoke native update.
      await svc.updateMetadata(title: 'Song');
      final updateCalls = nativeCalls.where((c) => c.method == 'update');
      expect(updateCalls, isEmpty);
    });

    test('commands stream is a broadcast stream', () {
      final svc = MediaSessionService(debugLog: log);
      expect(svc.commands.isBroadcast, isTrue);
    });

    test('updatePosition no-op when disabled', () async {
      final svc = MediaSessionService(debugLog: log);
      await svc.updatePosition(const Duration(seconds: 5), playing: true);
      final updateCalls = nativeCalls.where((c) => c.method == 'update');
      expect(updateCalls, isEmpty);
    });

    test('setEnabled and updates invoke platform channel', () async {
      if (Platform.isLinux) return;
      final svc = MediaSessionService(debugLog: log);
      await svc.init(enabled: true);

      expect(nativeCalls.any((c) => c.method == 'setEnabled'), isTrue);

      nativeCalls.clear();
      await svc.updateMetadata(
        title: 'Song Title',
        artist: 'Artist Name',
        album: 'Album Name',
        duration: const Duration(seconds: 90),
      );

      final update = nativeCalls.firstWhere((c) => c.method == 'update');
      final args = update.arguments as Map;
      expect(args['title'], 'Song Title');
      expect(args['artist'], 'Artist Name');
      expect(args['album'], 'Album Name');
      expect(args['durationMs'], 90000);

      nativeCalls.clear();
      await svc.setEnabled(false);
      expect(nativeCalls.any((c) => c.method == 'setEnabled'), isTrue);
    });

    test('clear sends a clear call when platform is available', () async {
      if (Platform.isLinux) return;
      final svc = MediaSessionService(debugLog: log);
      await svc.init(enabled: true);

      nativeCalls.clear();
      await svc.clear();
      expect(nativeCalls.any((c) => c.method == 'clear'), isTrue);
    });

    test(
      'native command callbacks are forwarded to the commands stream',
      () async {
        if (Platform.isLinux) return;
        final svc = MediaSessionService(debugLog: log);
        await svc.init(enabled: true);

        final received = <MediaSessionCommand>[];
        final sub = svc.commands.listen(received.add);
        addTearDown(sub.cancel);

        Future<ByteData?> deliver(
          String action, [
          int? positionMs,
          double? value,
        ]) async {
          final args = <String, dynamic>{
            'action': action,
            'positionMs': ?positionMs,
            'value': ?value,
          };
          final encoded = const StandardMethodCodec().encodeMethodCall(
            MethodCall('command', args),
          );
          return TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .handlePlatformMessage(channel.name, encoded, (_) {});
        }

        await deliver('toggle');
        await deliver('seek', 1234);
        await deliver('volume', null, 0.8);
        await Future<void>.delayed(Duration.zero);

        expect(
          received.map((c) => c.action),
          containsAll(['toggle', 'seek', 'volume']),
        );
        final seek = received.firstWhere((c) => c.action == 'seek');
        expect(seek.positionMs, 1234);
        final volume = received.firstWhere((c) => c.action == 'volume');
        expect(volume.value, 0.8);
      },
    );
  });
}
