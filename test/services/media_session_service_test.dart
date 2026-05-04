import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/media_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('run.rosie.dacx/media_session');
  late List<MethodCall> calls;

  void installMockHandler(Future<dynamic>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<MediaSessionService> initService({required bool enabled}) async {
    final svc = MediaSessionService(
      debugLog: DebugLogService(isEnabled: () => false),
    );
    await svc.init(enabled: enabled);
    return svc;
  }

  group('MediaSessionService (non-Linux)', () {
    test(
      'init forwards setEnabled to the platform channel',
      () async {
        installMockHandler((_) async => null);
        final svc = await initService(enabled: true);
        addTearDown(svc.dispose);

        expect(
          calls.any(
            (c) => c.method == 'setEnabled' && c.arguments['enabled'] == true,
          ),
          isTrue,
        );
      },
      skip: Platform.isLinux ? 'channel is bypassed on Linux' : false,
    );

    test(
      'updateMetadata is a no-op when disabled',
      () async {
        installMockHandler((_) async => null);
        final svc = await initService(enabled: false);
        addTearDown(svc.dispose);
        calls.clear();

        await svc.updateMetadata(title: 'Song');
        expect(calls.where((c) => c.method == 'update').isEmpty, isTrue);
      },
      skip: Platform.isLinux ? 'channel is bypassed on Linux' : false,
    );

    test(
      'updateMetadata forwards title/duration when enabled',
      () async {
        installMockHandler((_) async => null);
        final svc = await initService(enabled: true);
        addTearDown(svc.dispose);
        calls.clear();

        await svc.updateMetadata(
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(seconds: 42),
        );

        final update = calls.firstWhere((c) => c.method == 'update');
        final args = (update.arguments as Map).cast<String, dynamic>();
        expect(args['title'], 'Song');
        expect(args['artist'], 'Artist');
        expect(args['album'], 'Album');
        expect(args['durationMs'], 42000);
      },
      skip: Platform.isLinux ? 'channel is bypassed on Linux' : false,
    );

    test(
      'updatePosition forwards position and playing flag',
      () async {
        installMockHandler((_) async => null);
        final svc = await initService(enabled: true);
        addTearDown(svc.dispose);
        await svc.updateMetadata(
          title: 'Song',
          duration: const Duration(seconds: 90),
        );
        calls.clear();

        await svc.updatePosition(const Duration(seconds: 5), playing: true);

        final args =
            ((calls.firstWhere((c) => c.method == 'update').arguments) as Map)
                .cast<String, dynamic>();
        expect(args['positionMs'], 5000);
        expect(args['playing'], true);
        expect(args['durationMs'], 90000);
      },
      skip: Platform.isLinux ? 'channel is bypassed on Linux' : false,
    );

    test(
      'clear sends a clear call when platform is available',
      () async {
        installMockHandler((_) async => null);
        final svc = await initService(enabled: true);
        addTearDown(svc.dispose);
        calls.clear();

        await svc.clear();
        expect(calls.where((c) => c.method == 'clear'), isNotEmpty);
      },
      skip: Platform.isLinux ? 'channel is bypassed on Linux' : false,
    );

    test(
      'MissingPluginException disables the bridge after first failure',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              throw MissingPluginException('not registered');
            });

        final svc = await initService(enabled: true);
        addTearDown(svc.dispose);
        // Subsequent calls become no-ops; should not throw.
        await svc.updateMetadata(title: 'X');
        await svc.clear();
        // Only the very first invocation should reach the handler.
        expect(calls, hasLength(1));
        expect(calls.first.method, 'setEnabled');
      },
      skip: Platform.isLinux ? 'channel is bypassed on Linux' : false,
    );

    test(
      'native command callbacks are forwarded to the commands stream',
      () async {
        installMockHandler((_) async => null);
        final svc = await initService(enabled: true);
        addTearDown(svc.dispose);

        final received = <MediaSessionCommand>[];
        final sub = svc.commands.listen(received.add);
        addTearDown(sub.cancel);

        Future<ByteData?> deliver(String action, [int? positionMs]) async {
          final args = <String, dynamic>{
            'action': action,
            // ignore: use_null_aware_elements
            if (positionMs != null) 'positionMs': positionMs,
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
        await Future<void>.delayed(Duration.zero);

        expect(received.map((c) => c.action), containsAll(['toggle', 'seek']));
        final seek = received.firstWhere((c) => c.action == 'seek');
        expect(seek.positionMs, 1234);
      },
      skip: Platform.isLinux ? 'channel is bypassed on Linux' : false,
    );
  });

  group('MediaSessionCommand', () {
    test('stores fields verbatim', () {
      const cmd = MediaSessionCommand('next', 99);
      expect(cmd.action, 'next');
      expect(cmd.positionMs, 99);
    });
  });
}
