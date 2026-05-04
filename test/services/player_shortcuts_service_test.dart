import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/player_shortcuts_service.dart';

void main() {
  PlayerShortcutAction? resolve(
    KeyEvent event, {
    bool hasMedia = true,
    bool meta = false,
    bool ctrl = false,
  }) {
    return PlayerShortcutsService.resolve(
      event: event,
      hasMedia: hasMedia,
      isMetaPressed: meta,
      isControlPressed: ctrl,
    );
  }

  group('PlayerShortcutsService', () {
    test('maps Ctrl/Cmd + O to open file', () {
      const keyEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyO,
        logicalKey: LogicalKeyboardKey.keyO,
        timeStamp: Duration.zero,
      );

      expect(resolve(keyEvent, ctrl: true), PlayerShortcutAction.openFile);
      expect(resolve(keyEvent, meta: true), PlayerShortcutAction.openFile);
    });

    test('maps Ctrl/Cmd + R to reopen last', () {
      const keyEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyR,
        logicalKey: LogicalKeyboardKey.keyR,
        timeStamp: Duration.zero,
      );

      expect(resolve(keyEvent, ctrl: true), PlayerShortcutAction.reopenLast);
      expect(resolve(keyEvent, meta: true), PlayerShortcutAction.reopenLast);
    });

    test('maps F and Escape for fullscreen actions', () {
      const fullscreenEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        timeStamp: Duration.zero,
      );
      const escapeEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      );

      expect(resolve(fullscreenEvent), PlayerShortcutAction.toggleFullscreen);
      expect(resolve(escapeEvent), PlayerShortcutAction.exitFullscreen);
    });

    test('space requires media for play/pause', () {
      const spaceEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
      );

      expect(
        resolve(spaceEvent, hasMedia: true),
        PlayerShortcutAction.playPause,
      );
      expect(resolve(spaceEvent, hasMedia: false), isNull);
    });

    test('supports repeat key events for seek/volume shortcuts only', () {
      const seekEvent = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowRight,
        logicalKey: LogicalKeyboardKey.arrowRight,
        timeStamp: Duration.zero,
      );
      const volumeEvent = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      );
      const muteEvent = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyM,
        logicalKey: LogicalKeyboardKey.keyM,
        timeStamp: Duration.zero,
      );

      expect(resolve(seekEvent), PlayerShortcutAction.seekForward);
      expect(resolve(volumeEvent), PlayerShortcutAction.volumeDown);
      expect(resolve(muteEvent), isNull);
    });

    test('ignores play/pause and mute when primary modifier is held', () {
      const spaceEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
      );
      const muteEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyM,
        logicalKey: LogicalKeyboardKey.keyM,
        timeStamp: Duration.zero,
      );

      expect(resolve(spaceEvent, ctrl: true), isNull);
      expect(resolve(muteEvent, meta: true), isNull);
    });

    test('ignores key up events', () {
      const keyEvent = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyO,
        logicalKey: LogicalKeyboardKey.keyO,
        timeStamp: Duration.zero,
      );

      expect(resolve(keyEvent, ctrl: true), isNull);
    });

    test('chapter shortcuts trigger when modifier is held with arrow keys', () {
      const arrowRight = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowRight,
        logicalKey: LogicalKeyboardKey.arrowRight,
        timeStamp: Duration.zero,
      );
      const arrowLeft = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowLeft,
        logicalKey: LogicalKeyboardKey.arrowLeft,
        timeStamp: Duration.zero,
      );

      expect(resolve(arrowRight, ctrl: true), PlayerShortcutAction.chapterNext);
      expect(resolve(arrowLeft, meta: true), PlayerShortcutAction.chapterPrev);
    });

    test('extra letter shortcuts map to their actions', () {
      const a = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        timeStamp: Duration.zero,
      );
      const j = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyJ,
        logicalKey: LogicalKeyboardKey.keyJ,
        timeStamp: Duration.zero,
      );
      const v = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyV,
        logicalKey: LogicalKeyboardKey.keyV,
        timeStamp: Duration.zero,
      );
      const e = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyE,
        logicalKey: LogicalKeyboardKey.keyE,
        timeStamp: Duration.zero,
      );
      const s = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyS,
        logicalKey: LogicalKeyboardKey.keyS,
        timeStamp: Duration.zero,
      );

      expect(resolve(a), PlayerShortcutAction.cycleAudioTrack);
      expect(resolve(j), PlayerShortcutAction.cycleSubtitleTrack);
      expect(resolve(v), PlayerShortcutAction.toggleSubtitle);
      expect(resolve(e), PlayerShortcutAction.toggleEqualizer);
      expect(resolve(s, ctrl: true), PlayerShortcutAction.screenshot);
    });

    test('returns null for unmapped keys', () {
      const tab = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.tab,
        logicalKey: LogicalKeyboardKey.tab,
        timeStamp: Duration.zero,
      );
      expect(resolve(tab), isNull);
    });
  });

  group('PlayerShortcutsService.resolve(customBindings)', () {
    PlayerShortcutAction? resolveCustom(
      KeyEvent event,
      Map<String, List<String>> bindings, {
      bool hasMedia = true,
      bool meta = false,
      bool ctrl = false,
      bool shift = false,
      bool alt = false,
    }) {
      return PlayerShortcutsService.resolve(
        event: event,
        hasMedia: hasMedia,
        isMetaPressed: meta,
        isControlPressed: ctrl,
        isShiftPressed: shift,
        isAltPressed: alt,
        customBindings: bindings,
      );
    }

    test('matches a remapped accelerator string', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: LogicalKeyboardKey.keyP,
        timeStamp: Duration.zero,
      );
      expect(
        resolveCustom(
          event,
          {
            'playPause': ['Ctrl+Shift+P'],
          },
          ctrl: true,
          shift: true,
        ),
        PlayerShortcutAction.playPause,
      );
    });

    test('returns null when no custom binding matches the accelerator', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: LogicalKeyboardKey.keyP,
        timeStamp: Duration.zero,
      );
      expect(
        resolveCustom(
          event,
          {
            'playPause': ['Ctrl+Shift+Q'],
          },
          ctrl: true,
          shift: true,
        ),
        isNull,
      );
    });

    test('ignores unknown action names in custom bindings', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: LogicalKeyboardKey.keyP,
        timeStamp: Duration.zero,
      );
      expect(
        resolveCustom(event, {
          'doesNotExist': ['P'],
        }),
        isNull,
      );
    });

    test('repeat events only trigger repeatable custom-bound actions', () {
      const repeat = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowRight,
        logicalKey: LogicalKeyboardKey.arrowRight,
        timeStamp: Duration.zero,
      );
      // Seek-forward IS repeatable.
      expect(
        resolveCustom(repeat, {
          'seekForward': ['Arrow Right'],
        }),
        PlayerShortcutAction.seekForward,
      );
      // Open-file is NOT repeatable, so a key-repeat must be ignored.
      const repeatO = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyO,
        logicalKey: LogicalKeyboardKey.keyO,
        timeStamp: Duration.zero,
      );
      expect(
        resolveCustom(repeatO, {
          'openFile': ['Ctrl+O'],
        }, ctrl: true),
        isNull,
      );
    });

    test('custom playPause requires media to be loaded', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyG,
        logicalKey: LogicalKeyboardKey.keyG,
        timeStamp: Duration.zero,
      );
      expect(
        resolveCustom(event, {
          'playPause': ['G'],
        }, hasMedia: false),
        isNull,
      );
      expect(
        resolveCustom(event, {
          'playPause': ['G'],
        }, hasMedia: true),
        PlayerShortcutAction.playPause,
      );
    });
  });

  group('PlayerShortcutsService.acceleratorFromEvent', () {
    testWidgets('produces a canonical key string from a real event', (
      tester,
    ) async {
      String? captured;
      await tester.pumpWidget(
        Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            captured = PlayerShortcutsService.acceleratorFromEvent(event);
            return KeyEventResult.handled;
          },
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      expect(captured, contains('O'));
    });
  });

  group('shortcutActionLabel', () {
    test('returns a non-empty label for every action', () {
      for (final action in PlayerShortcutAction.values) {
        expect(shortcutActionLabel(action), isNotEmpty);
      }
    });
  });

  group('defaultKeybinds catalog', () {
    test('every action has at least one default binding', () {
      for (final action in PlayerShortcutAction.values) {
        expect(
          defaultKeybinds[action],
          isNotNull,
          reason: 'no default for $action',
        );
        expect(defaultKeybinds[action], isNotEmpty);
      }
    });
  });
}
