import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// System tray icon + menu for minimize-to-tray on desktop.
///
/// Supported on Windows, macOS, and Linux. Elsewhere all methods no-op.
/// Uses tray_manager's native API. The deprecated 0.5 compatibility API is
/// not used, so the discontinued menu_base package is not needed.
class TrayService {
  TrayService({required this.onQuit});

  /// Called when the user chooses Quit from the tray menu.
  final Future<void> Function() onQuit;

  TrayIcon? _trayIcon;
  Menu? _menu;
  MenuItem? _showItem;
  MenuItem? _quitItem;
  bool _initialized = false;
  String _showLabel = 'Show Dacx';
  String _quitLabel = 'Quit';

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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

  Future<void> init({
    required String showLabel,
    required String quitLabel,
  }) async {
    if (!isSupported) return;
    _showLabel = showLabel;
    _quitLabel = quitLabel;
    if (_initialized) {
      _updateMenuLabels();
      return;
    }
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
      _showItem = MenuItem.createWithLabelAndType(
        _showLabel,
        MenuItemType.normal,
      );
      _quitItem = MenuItem.createWithLabelAndType(
        _quitLabel,
        MenuItemType.normal,
      );
      if (_showItem == null || _quitItem == null) {
        throw StateError('tray_manager could not create menu items');
      }
      _showItem!.addListener((event) {
        if (event is MenuItemClickedEvent) unawaited(showWindow());
      });
      _quitItem!.addListener((event) {
        if (event is MenuItemClickedEvent) {
          unawaited(
            onQuit().catchError((Object e) {
              if (kDebugMode) debugPrint('Dacx: tray onQuit failed: $e');
            }),
          );
        }
      });
      menu.addItem(_showItem);
      menu.addSeparator();
      menu.addItem(_quitItem);

      final iconPath = trayIconAssetPath();
      final trayImage = ImageAsset.fromAsset(iconPath);
      if (trayImage == null) {
        throw StateError('tray icon asset not found: $iconPath');
      }
      icon.icon = trayImage;
      if (Platform.isMacOS) {
        icon.isIconTemplate = true;
        icon.iconSize = const Size(22, 22);
      }
      icon.setTooltip('Dacx');
      icon.setContextMenu(menu);
      icon.addListener((event) {
        if (event is TrayIconClickedEvent) {
          if (Platform.isWindows) {
            icon.openContextMenu();
          } else if (!Platform.isLinux) {
            unawaited(showWindow());
          }
        } else if (event is TrayIconRightClickedEvent && !Platform.isLinux) {
          icon.openContextMenu();
        }
      });
      icon.setVisible(true);
      _initialized = true;
    } catch (e) {
      await dispose();
      if (kDebugMode) debugPrint('Dacx: tray init failed: $e');
    }
  }

  void _updateMenuLabels() {
    _showItem?.label = _showLabel;
    _quitItem?.label = _quitLabel;
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

  Future<void> hideToTray() async {
    if (!isSupported) return;
    if (!_initialized) {
      await init(showLabel: _showLabel, quitLabel: _quitLabel);
    }
    try {
      await windowManager.hide();
    } catch (e) {
      if (kDebugMode) debugPrint('Dacx: tray hideToTray failed: $e');
    }
  }

  Future<void> dispose() async {
    final icon = _trayIcon;
    final menu = _menu;
    _trayIcon = null;
    _menu = null;
    _showItem = null;
    _quitItem = null;
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
