import 'package:flutter/services.dart';
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
  });
}
