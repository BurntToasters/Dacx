import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/player_shortcuts_service.dart';
import '../../services/settings_service.dart';

class PlayerShortcutDispatcher {
  PlayerShortcutDispatcher({
    required this.settings,
    required this.isActive,
    required this.routeIsCurrent,
    required this.hasMedia,
    required this.isEndDrawerOpen,
    required this.onEscape,
    required this.onShowHelp,
    required this.onAction,
  });

  final SettingsService settings;
  final bool Function() isActive;
  final bool Function() routeIsCurrent;
  final bool Function() hasMedia;
  final bool Function() isEndDrawerOpen;
  final KeyEventResult Function() onEscape;
  final VoidCallback onShowHelp;
  final KeyEventResult Function(PlayerShortcutAction action) onAction;

  final FocusNode focusNode = FocusNode(
    debugLabel: 'player-shortcuts',
    skipTraversal: true,
  );

  void attach() {
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    focusNode.dispose();
  }

  bool _focusInPath() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    return primary == focusNode || primary.ancestors.contains(focusNode);
  }

  bool _isEditableFocus(FocusNode primary) {
    final ctx = primary.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _onGlobalKey(KeyEvent event) {
    if (!isActive()) return false;
    if (!routeIsCurrent()) return false;
    if (_focusInPath()) return false;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && _isEditableFocus(primary)) return false;
    return handleKeyEvent(focusNode, event) == KeyEventResult.handled;
  }

  void restoreFocus({bool refocusNativeWindow = true}) {
    if (!isActive()) return;
    if (focusNode.canRequestFocus) {
      focusNode.requestFocus();
    }
    if (refocusNativeWindow) {
      unawaited(windowManager.focus().catchError((_) {}));
    }
  }

  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    final hk = HardwareKeyboard.instance;
    final pressed = LogicalKeyboardKey.expandSynonyms(hk.logicalKeysPressed);
    final controlPressed =
        hk.isControlPressed || pressed.contains(LogicalKeyboardKey.control);
    final metaPressed =
        hk.isMetaPressed || pressed.contains(LogicalKeyboardKey.meta);
    final shiftPressed =
        hk.isShiftPressed || pressed.contains(LogicalKeyboardKey.shift);
    final altPressed =
        hk.isAltPressed || pressed.contains(LogicalKeyboardKey.alt);
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        !metaPressed &&
        !controlPressed &&
        !shiftPressed &&
        !altPressed) {
      return onEscape();
    }
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.f1 ||
            (event.logicalKey == LogicalKeyboardKey.question) ||
            (event.logicalKey == LogicalKeyboardKey.slash && shiftPressed))) {
      onShowHelp();
      return KeyEventResult.handled;
    }
    final custom = settings.keybinds;
    var shortcut = PlayerShortcutsService.resolve(
      event: event,
      hasMedia: hasMedia(),
      isMetaPressed: metaPressed,
      isControlPressed: controlPressed,
      isShiftPressed: shiftPressed,
      isAltPressed: altPressed,
      customBindings: custom.isEmpty ? null : custom,
    );
    if (shortcut == null && settings.advancedPlaybackToolsEnabled) {
      shortcut = PlayerShortcutsService.resolveAdvanced(
        event: event,
        isMetaPressed: metaPressed,
        isControlPressed: controlPressed,
        isShiftPressed: shiftPressed,
        customBindings: custom.isEmpty ? null : custom,
      );
    }

    if (shortcut == null) return KeyEventResult.ignored;

    if (isEndDrawerOpen()) {
      switch (shortcut) {
        case PlayerShortcutAction.seekForward:
        case PlayerShortcutAction.seekBack:
        case PlayerShortcutAction.seekForwardLarge:
        case PlayerShortcutAction.seekBackLarge:
        case PlayerShortcutAction.volumeUp:
        case PlayerShortcutAction.volumeDown:
          return KeyEventResult.ignored;
        default:
          break;
      }
    }

    return onAction(shortcut);
  }
}
