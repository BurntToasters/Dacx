import 'package:dacx/services/player_shortcuts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Helper to create a fake KeyDownEvent for testing.
KeyDownEvent _keyDown(LogicalKeyboardKey key) {
  return KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA, // placeholder
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

KeyRepeatEvent _keyRepeat(LogicalKeyboardKey key) {
  return KeyRepeatEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

KeyUpEvent _keyUp(LogicalKeyboardKey key) {
  return KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

void main() {
  group('PlayerShortcutsService.resolve', () {
    test('space triggers playPause when hasMedia', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.space),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.playPause);
    });

    test('space does not trigger playPause without media', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.space),
        hasMedia: false,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, isNull);
    });

    test('Ctrl+O triggers openFile', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyO),
        hasMedia: false,
        isMetaPressed: false,
        isControlPressed: true,
      );
      expect(action, PlayerShortcutAction.openFile);
    });

    test('Meta+O triggers openFile (macOS)', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyO),
        hasMedia: false,
        isMetaPressed: true,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.openFile);
    });

    test('Ctrl+R triggers reopenLast', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyR),
        hasMedia: false,
        isMetaPressed: false,
        isControlPressed: true,
      );
      expect(action, PlayerShortcutAction.reopenLast);
    });

    test('Ctrl+N triggers newWindow', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyN),
        hasMedia: false,
        isMetaPressed: false,
        isControlPressed: true,
      );
      expect(action, PlayerShortcutAction.newWindow);
    });

    test('Ctrl+S triggers screenshot', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyS),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: true,
      );
      expect(action, PlayerShortcutAction.screenshot);
    });

    test('F triggers toggleFullscreen', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyF),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.toggleFullscreen);
    });

    test('Escape triggers exitFullscreen', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.escape),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.exitFullscreen);
    });

    test('M triggers toggleMute', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyM),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.toggleMute);
    });

    test('A triggers cycleAudioTrack', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyA),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.cycleAudioTrack);
    });

    test('J triggers cycleSubtitleTrack', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyJ),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.cycleSubtitleTrack);
    });

    test('V triggers toggleSubtitle', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyV),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.toggleSubtitle);
    });

    test('E triggers toggleEqualizer', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyE),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.toggleEqualizer);
    });

    test('ArrowRight triggers seekForward', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.arrowRight),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.seekForward);
    });

    test('Ctrl+ArrowRight triggers chapterNext', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.arrowRight),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: true,
      );
      expect(action, PlayerShortcutAction.chapterNext);
    });

    test('ArrowLeft triggers seekBack', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.arrowLeft),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.seekBack);
    });

    test('Ctrl+ArrowLeft triggers chapterPrev', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.arrowLeft),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: true,
      );
      expect(action, PlayerShortcutAction.chapterPrev);
    });

    test('ArrowUp triggers volumeUp', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.arrowUp),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.volumeUp);
    });

    test('ArrowDown triggers volumeDown', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.arrowDown),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.volumeDown);
    });

    test('KeyUpEvent returns null (not actionable)', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyUp(LogicalKeyboardKey.space),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, isNull);
    });

    test('KeyRepeatEvent works for repeatable actions (seek)', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyRepeat(LogicalKeyboardKey.arrowRight),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.seekForward);
    });

    test('KeyRepeatEvent works for volume', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyRepeat(LogicalKeyboardKey.arrowUp),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, PlayerShortcutAction.volumeUp);
    });

    test('unbound key returns null', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyZ),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
      );
      expect(action, isNull);
    });
  });

  group('PlayerShortcutsService custom bindings', () {
    test('custom binding overrides default', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyZ),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
        customBindings: {
          'playPause': ['Z'],
        },
      );
      expect(action, PlayerShortcutAction.playPause);
    });

    test('custom binding with Ctrl modifier', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyP),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: true,
        customBindings: {
          'screenshot': ['Ctrl+P'],
        },
      );
      expect(action, PlayerShortcutAction.screenshot);
    });

    test('custom binding ignores unknown action names', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyZ),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
        customBindings: {
          'nonExistentAction': ['Z'],
        },
      );
      expect(action, isNull);
    });

    test('custom binding playPause still requires hasMedia', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.keyZ),
        hasMedia: false,
        isMetaPressed: false,
        isControlPressed: false,
        customBindings: {
          'playPause': ['Z'],
        },
      );
      expect(action, isNull);
    });

    test('empty custom bindings falls through to default resolver', () {
      final action = PlayerShortcutsService.resolve(
        event: _keyDown(LogicalKeyboardKey.space),
        hasMedia: true,
        isMetaPressed: false,
        isControlPressed: false,
        customBindings: {},
      );
      // Empty map is treated as "no custom bindings" → defaults apply
      expect(action, PlayerShortcutAction.playPause);
    });
  });

  group('shortcutActionLabel', () {
    test('returns non-empty string for all actions without l10n', () {
      for (final action in PlayerShortcutAction.values) {
        expect(shortcutActionLabel(action), isNotEmpty, reason: action.name);
      }
    });

    test('each action has a unique label', () {
      final labels = PlayerShortcutAction.values
          .map((a) => shortcutActionLabel(a))
          .toSet();
      expect(labels.length, PlayerShortcutAction.values.length);
    });
  });

  group('defaultKeybinds', () {
    test('all actions have at least one binding', () {
      for (final action in PlayerShortcutAction.values) {
        expect(
          defaultKeybinds[action],
          isNotNull,
          reason: '${action.name} missing from defaultKeybinds',
        );
        expect(defaultKeybinds[action], isNotEmpty);
      }
    });

    test('all bindings are non-empty strings', () {
      for (final entry in defaultKeybinds.entries) {
        for (final bind in entry.value) {
          expect(bind, isNotEmpty, reason: entry.key.name);
        }
      }
    });
  });
}
