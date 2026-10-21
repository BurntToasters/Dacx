import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/open_file_bridge.dart';
import 'package:dacx/services/player_shortcuts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('custom Cmd keybinds (macOS)', () {
    KeyEvent keyDown(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

    KeyEvent keyUp(LogicalKeyboardKey key) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

    KeyEvent keyRepeat(LogicalKeyboardKey key) => KeyRepeatEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

    PlayerShortcutAction? resolve(
      KeyEvent event, {
      Map<String, List<String>> customBindings = const {},
      bool meta = false,
      bool ctrl = false,
      bool shift = false,
      bool hasMedia = true,
    }) {
      return PlayerShortcutsService.resolve(
        event: event,
        hasMedia: hasMedia,
        isMetaPressed: meta,
        isControlPressed: ctrl,
        isShiftPressed: shift,
        customBindings: customBindings,
      );
    }

    test('M1.1 stored Meta+O fires openFile for live Cmd+O', () {
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyO),
          meta: true,
          customBindings: const {
            'openFile': ['Meta+O'],
          },
        ),
        PlayerShortcutAction.openFile,
      );
    });

    test('M1.2 stored Ctrl+O still fires for live Cmd+O', () {
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyO),
          meta: true,
          customBindings: const {
            'openFile': ['Ctrl+O'],
          },
        ),
        PlayerShortcutAction.openFile,
      );
    });

    test('M1.3 stored Meta+O still fires for live Ctrl+O', () {
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyO),
          ctrl: true,
          customBindings: const {
            'openFile': ['Meta+O'],
          },
        ),
        PlayerShortcutAction.openFile,
      );
    });

    test('M1.4 a rebound default does not leak through after rebinding', () {
      const bindings = {
        'openFile': ['Meta+P'],
      };
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyP),
          meta: true,
          customBindings: bindings,
        ),
        PlayerShortcutAction.openFile,
      );
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyO),
          meta: true,
          customBindings: bindings,
        ),
        isNull,
      );
    });

    test('M1.5 key release of a bound Cmd chord resolves to nothing', () {
      expect(
        resolve(
          keyUp(LogicalKeyboardKey.keyO),
          meta: true,
          customBindings: const {
            'openFile': ['Meta+O'],
          },
        ),
        isNull,
      );
    });

    test('M1.6 modifier order does not matter for a bound chord', () {
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyN),
          meta: true,
          shift: true,
          customBindings: const {
            'playlistNext': ['Shift+Meta+N'],
          },
        ),
        PlayerShortcutAction.playlistNext,
      );
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyO),
          ctrl: true,
          shift: true,
          customBindings: const {
            'openFile': ['Shift+Ctrl+O'],
          },
        ),
        PlayerShortcutAction.openFile,
      );
    });

    test('M1.7 stored space forms fire playPause only with media', () {
      for (final stored in [' ', 'Space']) {
        expect(
          resolve(
            keyDown(LogicalKeyboardKey.space),
            customBindings: {
              'playPause': [stored],
            },
          ),
          PlayerShortcutAction.playPause,
          reason: 'stored "$stored" with media',
        );
        expect(
          resolve(
            keyDown(LogicalKeyboardKey.space),
            hasMedia: false,
            customBindings: {
              'playPause': [stored],
            },
          ),
          isNull,
          reason: 'stored "$stored" without media',
        );
      }
    });

    test('M1.8 stored Ctrl+space form fires for live Cmd+Space', () {
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.space),
          meta: true,
          customBindings: const {
            'playPause': ['Ctrl+ '],
          },
        ),
        PlayerShortcutAction.playPause,
      );
    });

    test('M1.9 repeat fires only for repeatable actions', () {
      expect(
        resolve(
          keyRepeat(LogicalKeyboardKey.arrowRight),
          meta: true,
          customBindings: const {
            'seekForward': ['Meta+Arrow Right'],
          },
        ),
        PlayerShortcutAction.seekForward,
      );
      expect(
        resolve(
          keyRepeat(LogicalKeyboardKey.keyO),
          meta: true,
          customBindings: const {
            'openFile': ['Meta+O'],
          },
        ),
        isNull,
      );
    });

    test('M1.10 unbound Cmd chords keep their defaults', () {
      expect(
        resolve(
          keyDown(LogicalKeyboardKey.keyS),
          meta: true,
          customBindings: const {
            'openFile': ['Meta+P'],
          },
        ),
        PlayerShortcutAction.screenshot,
      );
    });

    test('M1.11 Cmd and Ctrl stay the same accelerator after normalizing', () {
      expect(
        PlayerShortcutsService.normalizeAccelerator('Meta+O'),
        PlayerShortcutsService.normalizeAccelerator('Ctrl+O'),
      );
    });
  });

  group('OpenFileBridge live batch failures', () {
    final desktop = Platform.isMacOS || Platform.isLinux || Platform.isWindows;
    const methodChannel = MethodChannel(OpenFileBridge.methodChannelName);
    const eventChannel = EventChannel(OpenFileBridge.eventChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    MockStreamHandlerEventSink? sink;
    late List<({String event, bool error})> logged;

    setUp(() {
      sink = null;
      logged = [];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'getPendingFiles') return <dynamic>[];
        return null;
      });
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (_, events) {
            sink = events;
          },
        ),
      );
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockStreamHandler(eventChannel, null);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 350));

    test(
      'M2.1-M2.4 a throwing live batch is logged, not retried, and the bridge keeps working',
      skip: !desktop,
      () async {
        final uncaught = <Object>[];
        final batches = <List<String>>[];
        var calls = 0;
        await runZonedGuarded(() async {
          final bridge = OpenFileBridge(
            methodChannel: methodChannel,
            eventChannel: eventChannel,
            batchWindow: const Duration(milliseconds: 100),
            retryDelay: Duration.zero,
            onLog:
                (
                  event, {
                  message,
                  details = const {},
                  warn = false,
                  error = false,
                }) {
                  logged.add((event: event, error: error));
                },
            onOpenRequest: (request, {required bool forcePlay}) async {},
            onOpenBatch: (requests) async {
              calls++;
              if (calls == 1) {
                throw StateError('batch handler exploded');
              }
              batches.add([for (final r in requests) r.path]);
            },
          );
          await bridge.bootstrap();

          sink!.success('/media/a.mp3');
          sink!.success('/media/b.mp3');
          await settle();
          expect(calls, 1, reason: 'failing batch must not be retried');

          sink!.success('/media/c.mp3');
          sink!.success('/media/d.mp3');
          await settle();
          bridge.dispose();
        }, (error, stack) => uncaught.add(error));

        expect(uncaught, isEmpty, reason: 'batch failure must not escape');
        expect(
          logged.where((e) => e.event == 'open_file_bridge_failed' && e.error),
          isNotEmpty,
          reason: 'failure must be logged via onLog',
        );
        expect(calls, 2);
        expect(batches, [
          ['/media/c.mp3', '/media/d.mp3'],
        ]);
      },
    );

    test(
      'M2.5 a live batch is dropped while the bridge is inactive',
      skip: !desktop,
      () async {
        var active = true;
        var calls = 0;
        final bridge = OpenFileBridge(
          methodChannel: methodChannel,
          eventChannel: eventChannel,
          batchWindow: const Duration(milliseconds: 100),
          isActive: () => active,
          onOpenRequest: (request, {required bool forcePlay}) async {},
          onOpenBatch: (requests) async {
            calls++;
          },
        );
        await bridge.bootstrap();
        sink!.success('/media/a.mp3');
        sink!.success('/media/b.mp3');
        active = false;
        await settle();
        expect(calls, 0);
        bridge.dispose();
      },
    );

    test(
      'M2.6 a single live event still goes through onOpenRequest',
      skip: !desktop,
      () async {
        final opened = <String>[];
        final bridge = OpenFileBridge(
          methodChannel: methodChannel,
          eventChannel: eventChannel,
          batchWindow: const Duration(milliseconds: 100),
          onOpenRequest: (request, {required bool forcePlay}) async {
            opened.add(request.path);
          },
          onOpenBatch: (requests) async {
            fail('a single event must not be delivered as a batch');
          },
        );
        await bridge.bootstrap();
        sink!.success('/media/solo.mp3');
        await settle();
        expect(opened, ['/media/solo.mp3']);
        bridge.dispose();
      },
    );
  });
}
