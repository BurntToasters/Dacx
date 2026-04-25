import 'package:flutter/services.dart';

enum PlayerShortcutAction {
  openFile,
  reopenLast,
  playPause,
  seekForward,
  seekBack,
  volumeUp,
  volumeDown,
  toggleMute,
  toggleFullscreen,
  exitFullscreen,
}

class PlayerShortcutsService {
  static PlayerShortcutAction? resolve({
    required KeyEvent event,
    required bool hasMedia,
    required bool isMetaPressed,
    required bool isControlPressed,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return null;
    }

    final key = event.logicalKey;
    final primaryModifierPressed = isMetaPressed || isControlPressed;

    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        key == LogicalKeyboardKey.keyO) {
      return PlayerShortcutAction.openFile;
    }

    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        key == LogicalKeyboardKey.keyR) {
      return PlayerShortcutAction.reopenLast;
    }

    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyF) {
      return PlayerShortcutAction.toggleFullscreen;
    }

    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.escape) {
      return PlayerShortcutAction.exitFullscreen;
    }

    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.space &&
        hasMedia) {
      return PlayerShortcutAction.playPause;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      return PlayerShortcutAction.seekForward;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      return PlayerShortcutAction.seekBack;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      return PlayerShortcutAction.volumeUp;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      return PlayerShortcutAction.volumeDown;
    }

    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyM) {
      return PlayerShortcutAction.toggleMute;
    }

    return null;
  }
}
