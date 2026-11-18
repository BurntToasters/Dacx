import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:nativeapi_flutter/nativeapi_flutter.dart' show SizeToNative;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import 'player_remote.dart';

enum TrayAction { playPause, next, previous, show, quit }

enum TrayClick { click, rightClick }

enum TrayClickAction { showWindow, openMenu, none }

class TrayLabels {
  const TrayLabels({
    required this.show,
    required this.quit,
    required this.play,
    required this.pause,
    required this.next,
    required this.previous,
    required this.trackTooltip,
    required this.trackArtistTooltip,
  });

  factory TrayLabels.fromL10n(AppLocalizations l10n) => TrayLabels(
    show: l10n.trayShow,
    quit: l10n.trayQuit,
    play: l10n.actionPlay,
    pause: l10n.actionPause,
    next: l10n.trayNext,
    previous: l10n.trayPrevious,
    trackTooltip: l10n.trayTooltipTrack,
    trackArtistTooltip: l10n.trayTooltipTrackArtist,
  );

  TrayLabels withShowQuit({String? show, String? quit}) => TrayLabels(
    show: show ?? this.show,
    quit: quit ?? this.quit,
    play: play,
    pause: pause,
    next: next,
    previous: previous,
    trackTooltip: trackTooltip,
    trackArtistTooltip: trackArtistTooltip,
  );

  final String show;
  final String quit;
  final String play;
  final String pause;
  final String next;
  final String previous;
  final String Function(String title) trackTooltip;
  final String Function(String title, String artist) trackArtistTooltip;
}

@immutable
class TrayMenuEntry {
  const TrayMenuEntry({
    required this.action,
    required this.label,
    required this.enabled,
  });

  const TrayMenuEntry.separator() : action = null, label = '', enabled = false;

  final TrayAction? action;
  final String label;
  final bool enabled;

  bool get isSeparator => action == null;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuEntry &&
      other.action == action &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(action, label, enabled);
}

@immutable
class TrayMenuSpec {
  const TrayMenuSpec({required this.entries, required this.tooltip});

  static const String appName = 'Dacx';
  static const int windowsTooltipLimit = 127;
  static const int defaultTooltipLimit = 255;

  final List<TrayMenuEntry> entries;
  final String tooltip;

  static int tooltipLimitFor({required bool isWindows}) =>
      isWindows ? windowsTooltipLimit : defaultTooltipLimit;

  factory TrayMenuSpec.build(
    NowPlayingState state,
    TrayLabels labels, {
    int tooltipLimit = windowsTooltipLimit,
  }) {
    final hasMedia = state.hasMedia;
    return TrayMenuSpec(
      entries: [
        TrayMenuEntry(
          action: TrayAction.playPause,
          label: state.isPlaying ? labels.pause : labels.play,
          enabled: hasMedia,
        ),
        TrayMenuEntry(
          action: TrayAction.next,
          label: labels.next,
          enabled: hasMedia && state.canGoNext,
        ),
        TrayMenuEntry(
          action: TrayAction.previous,
          label: labels.previous,
          enabled: hasMedia && state.canGoPrevious,
        ),
        const TrayMenuEntry.separator(),
        TrayMenuEntry(
          action: TrayAction.show,
          label: labels.show,
          enabled: true,
        ),
        TrayMenuEntry(
          action: TrayAction.quit,
          label: labels.quit,
          enabled: true,
        ),
      ],
      tooltip: _tooltipFor(state, labels, tooltipLimit),
    );
  }

  static String _clean(String? text) =>
      (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static String _cutTo(String text, int length) {
    if (length <= 0) return '';
    if (text.length <= length) return text;
    var end = length;
    if (_isHighSurrogate(text.codeUnitAt(end - 1))) end--;
    return text.substring(0, end);
  }

  static String _shorten(String text, int max) {
    if (text.length <= max) return text;
    if (max <= 1) return '…';
    return '${_cutTo(text, max - 1)}…';
  }

  static String _tooltipFor(
    NowPlayingState state,
    TrayLabels labels,
    int limit,
  ) {
    var title = _clean(state.title);
    if (!state.hasMedia || title.isEmpty) return appName;
    var artist = _clean(state.artist);
    final hasArtist = artist.isNotEmpty;
    String format() => hasArtist
        ? labels.trackArtistTooltip(title, artist)
        : labels.trackTooltip(title);
    var text = format();
    for (var guard = 0; text.length > limit && guard < 1000; guard++) {
      final over = text.length - limit;
      final shrinkArtist =
          hasArtist &&
          artist.length > 1 &&
          (artist.length >= title.length || title.length <= 1);
      if (shrinkArtist) {
        artist = _shorten(artist, artist.length - over);
      } else if (title.length > 1) {
        title = _shorten(title, title.length - over);
      } else {
        break;
      }
      text = format();
    }
    if (text.length > limit) text = _cutTo(text, limit);
    return text;
  }

  @override
  bool operator ==(Object other) =>
      other is TrayMenuSpec &&
      other.tooltip == tooltip &&
      listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(tooltip, Object.hashAll(entries));
}

/// System tray icon + menu for minimize-to-tray on desktop.
///
/// Supported on Windows, macOS, and Linux. Elsewhere all methods no-op.
/// Uses tray_manager's native API. The deprecated 0.5 compatibility API is
/// not used, so the discontinued menu_base package is not needed.
class TrayService {
  TrayService({required this.onQuit, this.remote});

  /// Called when the user chooses Quit from the tray menu.
  final Future<void> Function() onQuit;

  final PlayerRemote? remote;

  TrayIcon? _trayIcon;
  Menu? _menu;
  final Map<TrayAction, MenuItem> _items = {};
  bool _initialized = false;
  TrayLabels _labels = TrayLabels.fromL10n(AppLocalizationsEn());
  TrayMenuSpec? _appliedSpec;

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// `flutter test` hosts have no native UI toolkit. On Linux, creating a
  /// GTK menu there aborts the process with SIGTRAP before Dart can catch it,
  /// so the test host is treated as having no native tray.
  static bool get _nativeTrayAvailable =>
      !Platform.environment.containsKey('FLUTTER_TEST');

  bool get isInitialized => _initialized;

  /// Bundled asset path passed to native tray API (relative to flutter_assets).
  @visibleForTesting
  static String trayIconAssetPath({bool? isWindows, bool? isMacOS}) {
    final onWindows = isWindows ?? Platform.isWindows;
    final onMacOS = isMacOS ?? Platform.isMacOS;
    if (onWindows) return 'assets/icon/icon.ico';
    if (onMacOS) return 'assets/icon/tray_icon_template.png';
    return 'assets/icon/icon.png';
  }

  static TrayClickAction clickAction(TrayClick click, {bool? isLinux}) {
    if (isLinux ?? Platform.isLinux) return TrayClickAction.none;
    return switch (click) {
      TrayClick.click => TrayClickAction.showWindow,
      TrayClick.rightClick => TrayClickAction.openMenu,
    };
  }

  Future<void> handleClick(
    TrayClick click, {
    required VoidCallback openMenu,
    bool? isLinux,
  }) async {
    switch (clickAction(click, isLinux: isLinux)) {
      case TrayClickAction.showWindow:
        await showWindow();
      case TrayClickAction.openMenu:
        openMenu();
      case TrayClickAction.none:
        break;
    }
  }

  Future<void> activate(TrayAction action) async {
    switch (action) {
      case TrayAction.playPause:
        await remote?.playPause();
      case TrayAction.next:
        await remote?.next();
      case TrayAction.previous:
        await remote?.previous();
      case TrayAction.show:
        await showWindow();
      case TrayAction.quit:
        await onQuit();
    }
  }

  Future<void> init({
    TrayLabels? labels,
    String? showLabel,
    String? quitLabel,
  }) async {
    if (!isSupported) return;
    _labels = (labels ?? _labels).withShowQuit(
      show: showLabel,
      quit: quitLabel,
    );
    if (_initialized) {
      _applySpec();
      return;
    }
    if (!_nativeTrayAvailable) return;
    try {
      final icon = TrayIcon.create();
      final menu = Menu.create();
      if (icon == null || menu == null) {
        icon?.dispose();
        menu?.dispose();
        throw StateError('tray_manager could not create native tray handles');
      }
      _trayIcon = icon;
      _menu = menu;
      for (final action in TrayAction.values) {
        final item = MenuItem.createWithLabelAndType('', MenuItemType.normal);
        if (item == null) {
          throw StateError('tray_manager could not create menu items');
        }
        _items[action] = item;
        item.addListener((event) {
          if (event is! MenuItemClickedEvent) return;
          unawaited(
            activate(action).catchError((Object e) {
              if (kDebugMode) {
                debugPrint('Dacx: tray ${action.name} failed: $e');
              }
            }),
          );
        });
      }
      menu.addItem(_items[TrayAction.playPause]);
      menu.addItem(_items[TrayAction.next]);
      menu.addItem(_items[TrayAction.previous]);
      menu.addSeparator();
      menu.addItem(_items[TrayAction.show]);
      menu.addItem(_items[TrayAction.quit]);

      final iconPath = trayIconAssetPath();
      final trayImage = ImageAsset.fromAsset(iconPath);
      if (trayImage == null) {
        throw StateError('tray icon asset not found: $iconPath');
      }
      icon.icon = trayImage;
      if (Platform.isMacOS) {
        icon.isIconTemplate = true;
        icon.iconSize = const Size(22, 22).toNative();
      }
      _appliedSpec = null;
      _applySpec();
      icon.setContextMenu(menu);
      icon.addListener((event) {
        if (event is TrayIconClickedEvent) {
          unawaited(
            handleClick(TrayClick.click, openMenu: icon.openContextMenu),
          );
        } else if (event is TrayIconRightClickedEvent) {
          unawaited(
            handleClick(TrayClick.rightClick, openMenu: icon.openContextMenu),
          );
        }
      });
      icon.setVisible(true);
      remote?.addListener(_applySpec);
      _initialized = true;
    } catch (e) {
      await dispose();
      if (kDebugMode) debugPrint('Dacx: tray init failed: $e');
    }
  }

  void _applySpec() {
    final icon = _trayIcon;
    if (icon == null) return;
    final spec = TrayMenuSpec.build(
      remote?.value ?? NowPlayingState.idle,
      _labels,
      tooltipLimit: TrayMenuSpec.tooltipLimitFor(isWindows: Platform.isWindows),
    );
    if (spec == _appliedSpec) return;
    try {
      for (final entry in spec.entries) {
        final action = entry.action;
        if (action == null) continue;
        final item = _items[action];
        if (item == null) continue;
        item.label = entry.label;
        item.isEnabled = entry.enabled;
      }
      if (spec.tooltip != _appliedSpec?.tooltip) icon.setTooltip(spec.tooltip);
      _appliedSpec = spec;
    } catch (e) {
      if (kDebugMode) debugPrint('Dacx: tray update failed: $e');
    }
  }

  Future<void> showWindow() async {
    if (!isSupported) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      if (kDebugMode) debugPrint('Dacx: tray showWindow failed: $e');
    }
  }

  Future<bool> hideToTray() async {
    if (!isSupported) return false;
    if (!_initialized) {
      await init(labels: _labels);
    }
    try {
      if (!_initialized) {
        await windowManager.minimize();
        return false;
      }
      await windowManager.hide();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Dacx: tray hideToTray failed: $e');
      return false;
    }
  }

  Future<void> dispose() async {
    remote?.removeListener(_applySpec);
    final icon = _trayIcon;
    final menu = _menu;
    _trayIcon = null;
    _menu = null;
    _items.clear();
    _appliedSpec = null;
    _initialized = false;
    try {
      icon?.setVisible(false);
      icon?.dispose();
      menu?.dispose();
    } catch (e) {
      if (kDebugMode) debugPrint('Dacx: tray dispose failed: $e');
    }
  }
}
