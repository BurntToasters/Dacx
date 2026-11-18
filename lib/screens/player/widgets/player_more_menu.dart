import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../playback/player_controller.dart';
import '../../../playback/playback_mix_policy.dart';
import '../../../playback/sleep_timer_controller.dart';
import '../../../services/player_shortcuts_service.dart';
import '../../../services/playlist_service.dart';
import '../../../services/settings_service.dart';

const double _menuWidth = 280;
const double _fallbackRightMargin = 12;
const double _fallbackBottomMargin = 64;

class PlayerMoreMenuActions {
  const PlayerMoreMenuActions({
    required this.onOpenUrl,
    required this.onAudioTracks,
    required this.onSubtitleTracks,
    required this.onExternalAudio,
    required this.onExternalSubtitle,
    required this.onChapters,
    required this.onEqualizer,
    required this.onAdvancedPlayback,
    required this.onScreenshot,
    required this.onSleepTimer,
    required this.onKeybinds,
    required this.onQueue,
    required this.onEnqueue,
    required this.onSetShuffle,
    required this.onCompact,
  });

  final VoidCallback onOpenUrl;
  final VoidCallback onAudioTracks;
  final VoidCallback onSubtitleTracks;
  final VoidCallback onExternalAudio;
  final VoidCallback onExternalSubtitle;
  final VoidCallback onChapters;
  final VoidCallback onEqualizer;
  final VoidCallback onAdvancedPlayback;
  final VoidCallback onScreenshot;
  final ValueChanged<int?> onSleepTimer;
  final VoidCallback onKeybinds;
  final VoidCallback onQueue;
  final VoidCallback onEnqueue;
  final ValueChanged<bool> onSetShuffle;
  final VoidCallback onCompact;
}

class _MoreMenuConfig {
  const _MoreMenuConfig({
    required this.hasAudioOptions,
    required this.hasSubOptions,
    required this.hasChapters,
    required this.hasCurrentFile,
    required this.compactMode,
    required this.settings,
    required this.sleepTimer,
    required this.playlist,
    required this.onSetShuffle,
  });

  final bool hasAudioOptions;
  final bool hasSubOptions;
  final ValueListenable<bool> hasChapters;
  final bool Function() hasCurrentFile;
  final bool Function() compactMode;
  final SettingsService settings;
  final SleepTimerController sleepTimer;
  final PlaylistService playlist;
  final ValueChanged<bool> onSetShuffle;
}

Future<String?> showPlayerMoreMenu({
  required BuildContext context,
  required bool hasAudioOptions,
  required bool hasSubOptions,
  required ValueListenable<bool> hasChapters,
  required bool Function() hasCurrentFile,
  required bool Function() compactMode,
  required SettingsService settings,
  required SleepTimerController sleepTimer,
  required PlaylistService playlist,
  required ValueChanged<bool> onSetShuffle,
  Rect? anchor,
}) {
  final overlay = Overlay.of(context);
  final completer = Completer<String?>();
  Rect? localAnchor;
  if (anchor != null) {
    final overlayBox = overlay.context.findRenderObject();
    localAnchor = overlayBox is RenderBox && overlayBox.attached
        ? overlayBox.globalToLocal(anchor.topLeft) & anchor.size
        : anchor;
  }
  late final OverlayEntry entry;
  var finished = false;
  void finish(String? result) {
    if (finished) return;
    finished = true;
    completer.complete(result);
    scheduleMicrotask(() {
      if (entry.mounted) entry.remove();
    });
  }

  final config = _MoreMenuConfig(
    hasAudioOptions: hasAudioOptions,
    hasSubOptions: hasSubOptions,
    hasChapters: hasChapters,
    hasCurrentFile: hasCurrentFile,
    compactMode: compactMode,
    settings: settings,
    sleepTimer: sleepTimer,
    playlist: playlist,
    onSetShuffle: onSetShuffle,
  );
  entry = OverlayEntry(
    builder: (_) => _PlayerMoreMenuHost(
      config: config,
      anchor: localAnchor,
      onDone: finish,
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _PlayerMoreMenuHost extends StatefulWidget {
  const _PlayerMoreMenuHost({
    required this.config,
    required this.anchor,
    required this.onDone,
  });

  final _MoreMenuConfig config;
  final Rect? anchor;
  final ValueChanged<String?> onDone;

  @override
  State<_PlayerMoreMenuHost> createState() => _PlayerMoreMenuHostState();
}

class _PlayerMoreMenuHostState extends State<_PlayerMoreMenuHost> {
  final MenuController _controller = MenuController();
  final FocusNode _firstItemFocus = FocusNode(debugLabel: 'player-more-first');
  final FocusNode _hostFocus = FocusNode(debugLabel: 'player-more-host');
  String? _result;

  _MoreMenuConfig get _config => widget.config;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.open();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hostFocus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    widget.onDone(null);
    _firstItemFocus.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleHostKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _firstItemFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _controller.close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleClose() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      binding.addPostFrameCallback((_) => widget.onDone(_result));
      binding.scheduleFrame();
    });
  }

  String? _shortcutHint(PlayerShortcutAction action) {
    final bound =
        _config.settings.keybinds[action.name] ??
        defaultKeybinds[action] ??
        const <String>[];
    if (bound.isEmpty) return null;
    return PlayerShortcutsService.formatAcceleratorForDisplay(
      PlayerShortcutsService.normalizeAccelerator(bound.first),
      useMacSymbols: Platform.isMacOS,
    );
  }

  Widget _icon(IconData icon) => Icon(icon, size: 18);

  Widget _item({
    required IconData icon,
    required String label,
    required String action,
    PlayerShortcutAction? shortcut,
    Key? key,
    FocusNode? focusNode,
  }) {
    final hint = shortcut == null ? null : _shortcutHint(shortcut);
    return MenuItemButton(
      key: key,
      focusNode: focusNode,
      leadingIcon: _icon(icon),
      trailingIcon: hint == null ? null : _hintText(hint),
      onPressed: () => _result = action,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _hintText(String hint) {
    final theme = Theme.of(context);
    return Text(
      hint,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _switchItem({
    required IconData icon,
    required String label,
    required bool value,
    required VoidCallback onPressed,
    PlayerShortcutAction? shortcut,
    bool closeOnActivate = false,
    bool experimental = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = experimental
        ? Color.lerp(cs.tertiary, Colors.amber, 0.72)
        : null;
    final hint = shortcut == null ? null : _shortcutHint(shortcut);
    return MenuItemButton(
      closeOnActivate: closeOnActivate,
      leadingIcon: Icon(icon, size: 18, color: iconColor),
      trailingIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null) _hintText(hint),
          ExcludeFocus(
            child: IgnorePointer(
              child: Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: value,
                  onChanged: (_) {},
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ],
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _tracksSubmenu(AppLocalizations l10n) {
    return ValueListenableBuilder<bool>(
      valueListenable: _config.hasChapters,
      builder: (context, hasChapters, _) {
        final children = <Widget>[
          if (_config.hasAudioOptions)
            _item(
              icon: Icons.audiotrack,
              label: l10n.dialogAudioTrackTitle,
              action: 'audio',
            ),
          if (_config.hasSubOptions)
            _item(
              icon: Icons.subtitles,
              label: l10n.dialogSubtitleTrackTitle,
              action: 'subtitle',
            ),
          if (hasChapters)
            _item(
              icon: Icons.menu_book,
              label: l10n.dialogChaptersTitle,
              action: 'chapters',
            ),
        ];
        if (children.isEmpty) return const SizedBox.shrink();
        return SubmenuButton(
          leadingIcon: _icon(Icons.audiotrack),
          menuChildren: children,
          child: Text(l10n.menuTracks),
        );
      },
    );
  }

  Widget _sleepSubmenu(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: _config.sleepTimer,
      builder: (context, _) {
        final remaining = _config.sleepTimer.remaining;
        final label = remaining == null
            ? l10n.menuSleepTimer
            : '${l10n.menuSleepTimer} (${PlayerController.formatDuration(remaining)})';
        return SubmenuButton(
          leadingIcon: _icon(Icons.bedtime_outlined),
          menuChildren: [
            if (_config.sleepTimer.isActive)
              _item(
                icon: Icons.timer_off_outlined,
                label: l10n.menuSleepTimerOff,
                action: 'sleep_off',
              ),
            for (final minutes in SleepTimerController.presetMinutes)
              _item(
                icon: Icons.timer_outlined,
                label: l10n.menuSleepTimerMinutes(minutes),
                action: 'sleep_$minutes',
              ),
          ],
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  List<Widget> _menuChildren() {
    final l10n = AppLocalizations.of(context);
    final settings = _config.settings;
    final hasFile = _config.hasCurrentFile();
    return [
      _item(
        icon: Icons.link,
        label: l10n.buttonOpenUrl,
        action: 'open_url',
        shortcut: PlayerShortcutAction.openUrl,
        focusNode: _firstItemFocus,
      ),
      _tracksSubmenu(l10n),
      if (hasFile)
        _item(
          icon: Icons.audio_file,
          label: l10n.menuLoadExternalAudio,
          action: 'external_audio',
        ),
      if (hasFile)
        _item(
          icon: Icons.subtitles_outlined,
          label: l10n.menuLoadExternalSubtitle,
          action: 'external_subtitle',
        ),
      _item(
        icon: Icons.graphic_eq,
        label: l10n.dialogEqualizerTitle,
        action: 'equalizer',
      ),
      if (settings.advancedPlaybackToolsEnabled)
        _item(
          key: const ValueKey('advanced-playback-entry'),
          icon: Icons.tune,
          label: l10n.menuAdvancedPlayback,
          action: 'advanced-playback',
        ),
      if (hasFile)
        _item(
          icon: Icons.photo_camera,
          label: l10n.menuTakeScreenshot,
          action: 'screenshot',
          shortcut: PlayerShortcutAction.screenshot,
        ),
      const Divider(height: 1),
      _sleepSubmenu(l10n),
      const Divider(height: 1),
      if (_config.hasAudioOptions &&
          PlaybackMixPolicy.userFacingEnabled &&
          settings.experimentalFeaturesEnabled)
        _switchItem(
          icon: Icons.multitrack_audio,
          label: l10n.menuMixAllAudioTracks,
          value: settings.multiAudioMix,
          experimental: true,
          onPressed: () {
            settings.multiAudioMix = !settings.multiAudioMix;
            setState(() {});
          },
        ),
      _item(
        icon: Icons.keyboard,
        label: l10n.dialogKeyboardShortcutsTitle,
        action: 'keybinds',
      ),
      const Divider(height: 1),
      _item(
        icon: Icons.queue_music,
        label: _config.playlist.isEmpty
            ? l10n.menuQueueEmpty
            : l10n.menuQueueCount(_config.playlist.length),
        action: 'queue',
      ),
      _item(
        icon: Icons.playlist_add,
        label: l10n.menuAddFilesToQueue,
        action: 'enqueue',
      ),
      _switchItem(
        icon: Icons.shuffle,
        label: l10n.menuShuffleQueue,
        value: settings.playlistShuffle,
        onPressed: () {
          _config.onSetShuffle(!settings.playlistShuffle);
          setState(() {});
        },
      ),
      _switchItem(
        icon: Icons.picture_in_picture_alt,
        label: l10n.menuMiniPlayer,
        value: _config.compactMode(),
        closeOnActivate: true,
        shortcut: PlayerShortcutAction.toggleCompactMode,
        onPressed: () => _result = 'compact',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = constraints.biggest;
        final anchor =
            widget.anchor ??
            Rect.fromLTWH(
              bounds.width - _fallbackRightMargin,
              bounds.height - _fallbackBottomMargin,
              0,
              0,
            );
        final left = math.max(
          0.0,
          math.min(anchor.right - _menuWidth, bounds.width - _menuWidth),
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: anchor.top,
              width: _menuWidth,
              height: anchor.height,
              child: MenuButtonTheme(
                data: const MenuButtonThemeData(
                  style: ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                child: Focus(
                  focusNode: _hostFocus,
                  onKeyEvent: _handleHostKey,
                  child: MenuAnchor(
                    controller: _controller,
                    consumeOutsideTap: true,
                    onClose: _handleClose,
                    style: const MenuStyle(
                      alignment: AlignmentDirectional.bottomStart,
                      minimumSize: WidgetStatePropertyAll(Size(_menuWidth, 0)),
                      maximumSize: WidgetStatePropertyAll(
                        Size(_menuWidth, double.infinity),
                      ),
                    ),
                    menuChildren: [
                      for (final child in _menuChildren())
                        child is Divider
                            ? child
                            : SizedBox(width: _menuWidth, child: child),
                    ],
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

void dispatchPlayerMoreMenuResult(
  String? result,
  PlayerMoreMenuActions actions,
) {
  switch (result) {
    case 'open_url':
      actions.onOpenUrl();
      break;
    case 'audio':
      actions.onAudioTracks();
      break;
    case 'subtitle':
      actions.onSubtitleTracks();
      break;
    case 'external_audio':
      actions.onExternalAudio();
      break;
    case 'external_subtitle':
      actions.onExternalSubtitle();
      break;
    case 'chapters':
      actions.onChapters();
      break;
    case 'equalizer':
      actions.onEqualizer();
      break;
    case 'advanced-playback':
      actions.onAdvancedPlayback();
      break;
    case 'screenshot':
      actions.onScreenshot();
      break;
    case 'sleep_off':
      actions.onSleepTimer(null);
      break;
    case 'keybinds':
      actions.onKeybinds();
      break;
    case 'queue':
      actions.onQueue();
      break;
    case 'enqueue':
      actions.onEnqueue();
      break;
    case 'shuffle':
      // already toggled inline
      break;
    case 'compact':
      actions.onCompact();
      break;
    default:
      final minutes = result != null && result.startsWith('sleep_')
          ? int.tryParse(result.substring('sleep_'.length))
          : null;
      if (minutes != null &&
          SleepTimerController.presetMinutes.contains(minutes)) {
        actions.onSleepTimer(minutes);
      }
  }
}
