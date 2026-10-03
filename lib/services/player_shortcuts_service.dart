import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

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
  chapterNext,
  chapterPrev,
  screenshot,
  cycleAudioTrack,
  cycleSubtitleTrack,
  toggleSubtitle,
  toggleEqualizer,
  playlistNext,
  playlistPrev,
  toggleCompactMode,
  newWindow,
  speedSlower,
  speedFaster,
  cycleSpeed,
  openUrl,
  cycleAdvancedLoop,
  subtitleDelayBack,
  subtitleDelayForward,
  audioDelayBack,
  audioDelayForward,
  addPlaybackMarker,
}

/// Default human-readable accelerators, e.g. "Ctrl+O", "Arrow Right".
const Map<PlayerShortcutAction, List<String>> defaultKeybinds = {
  PlayerShortcutAction.openFile: ['Ctrl+O'],
  PlayerShortcutAction.reopenLast: ['Ctrl+R'],
  PlayerShortcutAction.playPause: ['Space'],
  PlayerShortcutAction.seekForward: ['Arrow Right'],
  PlayerShortcutAction.seekBack: ['Arrow Left'],
  PlayerShortcutAction.volumeUp: ['Arrow Up'],
  PlayerShortcutAction.volumeDown: ['Arrow Down'],
  PlayerShortcutAction.toggleMute: ['M'],
  PlayerShortcutAction.toggleFullscreen: ['F'],
  PlayerShortcutAction.exitFullscreen: ['Escape'],
  PlayerShortcutAction.chapterNext: ['Ctrl+Arrow Right'],
  PlayerShortcutAction.chapterPrev: ['Ctrl+Arrow Left'],
  PlayerShortcutAction.screenshot: ['Ctrl+S'],
  PlayerShortcutAction.cycleAudioTrack: ['A'],
  PlayerShortcutAction.cycleSubtitleTrack: ['J'],
  PlayerShortcutAction.toggleSubtitle: ['V'],
  PlayerShortcutAction.toggleEqualizer: ['E'],
  PlayerShortcutAction.playlistNext: ['Shift+N'],
  PlayerShortcutAction.playlistPrev: ['Shift+P'],
  PlayerShortcutAction.toggleCompactMode: ['Ctrl+Shift+M'],
  PlayerShortcutAction.newWindow: ['Ctrl+N'],
  PlayerShortcutAction.speedSlower: ['['],
  PlayerShortcutAction.speedFaster: [']'],
  PlayerShortcutAction.cycleSpeed: ['\\'],
  PlayerShortcutAction.openUrl: ['Ctrl+U'],
  PlayerShortcutAction.cycleAdvancedLoop: ['L'],
  PlayerShortcutAction.subtitleDelayBack: ['Z'],
  PlayerShortcutAction.subtitleDelayForward: ['Shift+Z'],
  PlayerShortcutAction.audioDelayBack: ['Ctrl+-'],
  PlayerShortcutAction.audioDelayForward: ['Ctrl+='],
  PlayerShortcutAction.addPlaybackMarker: ['Ctrl+B'],
};

String shortcutActionLabel(PlayerShortcutAction a, {AppLocalizations? l10n}) {
  if (l10n != null) {
    return switch (a) {
      PlayerShortcutAction.openFile => l10n.shortcutOpenFile,
      PlayerShortcutAction.reopenLast => l10n.shortcutReopenLast,
      PlayerShortcutAction.playPause => l10n.shortcutPlayPause,
      PlayerShortcutAction.seekForward => l10n.shortcutSeekForward,
      PlayerShortcutAction.seekBack => l10n.shortcutSeekBack,
      PlayerShortcutAction.volumeUp => l10n.shortcutVolumeUp,
      PlayerShortcutAction.volumeDown => l10n.shortcutVolumeDown,
      PlayerShortcutAction.toggleMute => l10n.shortcutToggleMute,
      PlayerShortcutAction.toggleFullscreen => l10n.shortcutToggleFullscreen,
      PlayerShortcutAction.exitFullscreen => l10n.shortcutExitFullscreen,
      PlayerShortcutAction.chapterNext => l10n.shortcutChapterNext,
      PlayerShortcutAction.chapterPrev => l10n.shortcutChapterPrev,
      PlayerShortcutAction.screenshot => l10n.shortcutScreenshot,
      PlayerShortcutAction.cycleAudioTrack => l10n.shortcutCycleAudioTrack,
      PlayerShortcutAction.cycleSubtitleTrack =>
        l10n.shortcutCycleSubtitleTrack,
      PlayerShortcutAction.toggleSubtitle => l10n.shortcutToggleSubtitle,
      PlayerShortcutAction.toggleEqualizer => l10n.shortcutToggleEqualizer,
      PlayerShortcutAction.playlistNext => l10n.shortcutPlaylistNext,
      PlayerShortcutAction.playlistPrev => l10n.shortcutPlaylistPrev,
      PlayerShortcutAction.toggleCompactMode => l10n.shortcutToggleCompactMode,
      PlayerShortcutAction.newWindow => l10n.shortcutNewWindow,
      PlayerShortcutAction.speedSlower => l10n.shortcutSpeedSlower,
      PlayerShortcutAction.speedFaster => l10n.shortcutSpeedFaster,
      PlayerShortcutAction.cycleSpeed => l10n.shortcutCycleSpeed,
      PlayerShortcutAction.openUrl => l10n.shortcutOpenUrl,
      PlayerShortcutAction.cycleAdvancedLoop => 'A-B repeat',
      PlayerShortcutAction.subtitleDelayBack => 'Decrease subtitle delay',
      PlayerShortcutAction.subtitleDelayForward => 'Increase subtitle delay',
      PlayerShortcutAction.audioDelayBack => 'Decrease audio delay',
      PlayerShortcutAction.audioDelayForward => 'Increase audio delay',
      PlayerShortcutAction.addPlaybackMarker => 'Add playback marker',
    };
  }
  return switch (a) {
    PlayerShortcutAction.openFile => 'Open file',
    PlayerShortcutAction.reopenLast => 'Reopen last file',
    PlayerShortcutAction.playPause => 'Play / pause',
    PlayerShortcutAction.seekForward => 'Seek forward',
    PlayerShortcutAction.seekBack => 'Seek backward',
    PlayerShortcutAction.volumeUp => 'Volume up',
    PlayerShortcutAction.volumeDown => 'Volume down',
    PlayerShortcutAction.toggleMute => 'Toggle mute',
    PlayerShortcutAction.toggleFullscreen => 'Toggle fullscreen',
    PlayerShortcutAction.exitFullscreen => 'Exit fullscreen',
    PlayerShortcutAction.chapterNext => 'Next chapter / video frame',
    PlayerShortcutAction.chapterPrev => 'Previous chapter / video frame',
    PlayerShortcutAction.screenshot => 'Save screenshot',
    PlayerShortcutAction.cycleAudioTrack => 'Cycle audio track',
    PlayerShortcutAction.cycleSubtitleTrack => 'Cycle subtitle track',
    PlayerShortcutAction.toggleSubtitle => 'Toggle subtitle visibility',
    PlayerShortcutAction.toggleEqualizer => 'Toggle equalizer',
    PlayerShortcutAction.playlistNext => 'Next in queue',
    PlayerShortcutAction.playlistPrev => 'Previous in queue',
    PlayerShortcutAction.toggleCompactMode => 'Toggle mini-player',
    PlayerShortcutAction.newWindow => 'Open new window',
    PlayerShortcutAction.speedSlower => 'Decrease playback speed',
    PlayerShortcutAction.speedFaster => 'Increase playback speed',
    PlayerShortcutAction.cycleSpeed => 'Cycle playback speed',
    PlayerShortcutAction.openUrl => 'Open URL',
    PlayerShortcutAction.cycleAdvancedLoop => 'Cycle A-B repeat',
    PlayerShortcutAction.subtitleDelayBack => 'Decrease subtitle delay',
    PlayerShortcutAction.subtitleDelayForward => 'Increase subtitle delay',
    PlayerShortcutAction.audioDelayBack => 'Decrease audio delay',
    PlayerShortcutAction.audioDelayForward => 'Increase audio delay',
    PlayerShortcutAction.addPlaybackMarker => 'Add playback marker',
  };
}

class PlayerShortcutsService {
  static bool isAdvancedAction(PlayerShortcutAction action) {
    return switch (action) {
      PlayerShortcutAction.cycleAdvancedLoop ||
      PlayerShortcutAction.subtitleDelayBack ||
      PlayerShortcutAction.subtitleDelayForward ||
      PlayerShortcutAction.audioDelayBack ||
      PlayerShortcutAction.audioDelayForward ||
      PlayerShortcutAction.addPlaybackMarker => true,
      _ => false,
    };
  }

  /// Resolves a key event into an action.
  ///
  /// Default behavior preserves the original built-in mapping. When
  /// [customBindings] is provided (action name -> accelerator strings), those
  /// bindings are checked first and **overlay** the defaults: unlisted actions
  /// still use built-in accelerators. A custom accelerator that collides with
  /// a default wins (custom match is preferred).
  static PlayerShortcutAction? resolve({
    required KeyEvent event,
    required bool hasMedia,
    required bool isMetaPressed,
    required bool isControlPressed,
    bool isShiftPressed = false,
    bool isAltPressed = false,
    Map<String, List<String>>? customBindings,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return null;
    }

    if (customBindings != null && customBindings.isNotEmpty) {
      final accel = _formatAccelerator(
        key: event.logicalKey,
        ctrl: isControlPressed,
        meta: isMetaPressed,
        shift: isShiftPressed,
        alt: isAltPressed,
      );
      for (final entry in customBindings.entries) {
        if (!entry.value.contains(accel)) continue;
        final action = _actionByName(entry.key);
        if (action == null) continue;
        if (event is! KeyDownEvent && !_isRepeatableAction(action)) {
          continue;
        }
        if (action == PlayerShortcutAction.playPause && !hasMedia) {
          continue;
        }
        return action;
      }
      // Fall through so unbound actions keep their defaults.
    }

    return _defaultResolve(
      event: event,
      hasMedia: hasMedia,
      isMetaPressed: isMetaPressed,
      isControlPressed: isControlPressed,
      isShiftPressed: isShiftPressed,
    );
  }

  static PlayerShortcutAction? _defaultResolve({
    required KeyEvent event,
    required bool hasMedia,
    required bool isMetaPressed,
    required bool isControlPressed,
    required bool isShiftPressed,
  }) {
    final key = event.logicalKey;
    final primaryModifierPressed = isMetaPressed || isControlPressed;

    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        key == LogicalKeyboardKey.keyO) {
      return PlayerShortcutAction.openFile;
    }
    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        key == LogicalKeyboardKey.keyU) {
      return PlayerShortcutAction.openUrl;
    }
    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        key == LogicalKeyboardKey.keyR) {
      return PlayerShortcutAction.reopenLast;
    }
    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        key == LogicalKeyboardKey.keyN) {
      return PlayerShortcutAction.newWindow;
    }
    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        key == LogicalKeyboardKey.keyS) {
      return PlayerShortcutAction.screenshot;
    }
    if (event is KeyDownEvent &&
        isShiftPressed &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyN) {
      return PlayerShortcutAction.playlistNext;
    }
    if (event is KeyDownEvent &&
        isShiftPressed &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyP) {
      return PlayerShortcutAction.playlistPrev;
    }
    if (event is KeyDownEvent &&
        primaryModifierPressed &&
        isShiftPressed &&
        key == LogicalKeyboardKey.keyM) {
      return PlayerShortcutAction.toggleCompactMode;
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
    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyA) {
      return PlayerShortcutAction.cycleAudioTrack;
    }
    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyJ) {
      return PlayerShortcutAction.cycleSubtitleTrack;
    }
    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyV) {
      return PlayerShortcutAction.toggleSubtitle;
    }
    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        key == LogicalKeyboardKey.keyE) {
      return PlayerShortcutAction.toggleEqualizer;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (primaryModifierPressed) {
        return event is KeyDownEvent ? PlayerShortcutAction.chapterNext : null;
      }
      return PlayerShortcutAction.seekForward;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (primaryModifierPressed) {
        return event is KeyDownEvent ? PlayerShortcutAction.chapterPrev : null;
      }
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
    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        !isShiftPressed &&
        key == LogicalKeyboardKey.bracketLeft) {
      return PlayerShortcutAction.speedSlower;
    }
    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        !isShiftPressed &&
        key == LogicalKeyboardKey.bracketRight) {
      return PlayerShortcutAction.speedFaster;
    }
    if (event is KeyDownEvent &&
        !primaryModifierPressed &&
        !isShiftPressed &&
        key == LogicalKeyboardKey.backslash) {
      return PlayerShortcutAction.cycleSpeed;
    }
    return null;
  }

  /// Resolves the opt-in advanced playback accelerators. Kept separate from
  /// the legacy default resolver so callers that rely on its historical
  /// minimalist mapping remain compatible; PlayerScreen invokes this only
  /// after the advanced tools gate is enabled.
  static PlayerShortcutAction? resolveAdvanced({
    required KeyEvent event,
    required bool isMetaPressed,
    required bool isControlPressed,
    required bool isShiftPressed,
  }) {
    if (event is! KeyDownEvent) return null;
    final key = event.logicalKey;
    final primary = isMetaPressed || isControlPressed;
    if (primary && key == LogicalKeyboardKey.keyB) {
      return PlayerShortcutAction.addPlaybackMarker;
    }
    if (primary &&
        (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      return PlayerShortcutAction.audioDelayBack;
    }
    if (primary &&
        (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.numpadAdd)) {
      return PlayerShortcutAction.audioDelayForward;
    }
    if (!primary && key == LogicalKeyboardKey.keyL) {
      return PlayerShortcutAction.cycleAdvancedLoop;
    }
    if (!primary && key == LogicalKeyboardKey.keyZ) {
      return isShiftPressed
          ? PlayerShortcutAction.subtitleDelayForward
          : PlayerShortcutAction.subtitleDelayBack;
    }
    return null;
  }

  static bool _isRepeatableAction(PlayerShortcutAction a) =>
      a == PlayerShortcutAction.seekForward ||
      a == PlayerShortcutAction.seekBack ||
      a == PlayerShortcutAction.volumeUp ||
      a == PlayerShortcutAction.volumeDown;

  static PlayerShortcutAction? _actionByName(String name) {
    for (final a in PlayerShortcutAction.values) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// Builds a canonical accelerator string for a key + modifiers.
  static String _formatAccelerator({
    required LogicalKeyboardKey key,
    required bool ctrl,
    required bool meta,
    required bool shift,
    required bool alt,
  }) {
    final parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (meta) parts.add('Meta');
    if (alt) parts.add('Alt');
    if (shift) parts.add('Shift');
    parts.add(_keyLabel(key));
    return parts.join('+');
  }

  /// Formats a stored accelerator for UI (⌘ on macOS instead of Ctrl).
  static String formatAcceleratorForDisplay(
    String accelerator, {
    required bool useMacSymbols,
  }) {
    if (!useMacSymbols) return accelerator;
    return accelerator
        .replaceAll('Ctrl+', '⌘')
        .replaceAll('Meta+', '⌘')
        .replaceAll('Alt+', '⌥')
        .replaceAll('Shift+', '⇧');
  }

  /// Public helper: translate a live key event into an accelerator string.
  static String acceleratorFromEvent(KeyEvent event) {
    return _formatAccelerator(
      key: event.logicalKey,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
    );
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.isNotEmpty) {
      return label.length == 1 ? label.toUpperCase() : label;
    }
    return key.debugName ?? 'Key(${key.keyId})';
  }
}
