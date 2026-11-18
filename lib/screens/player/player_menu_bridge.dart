import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../services/instance_mode_service.dart';
import '../../services/settings_service.dart';
import 'media_session_coordinator.dart';
import 'player_open_actions.dart';

class PlayerMenuBridge {
  PlayerMenuBridge({
    required this.settings,
    required this.media,
    required this.open,
    required this.isActive,
    required this.onCheckForUpdates,
    required this.onOpenPreferences,
  });

  final SettingsService settings;
  final MediaSessionCoordinator media;
  final PlayerOpenActions open;
  final bool Function() isActive;
  final Future<void> Function() onCheckForUpdates;
  final void Function() onOpenPreferences;

  void dispose() {
    if (Platform.isMacOS) {
      const MethodChannel(InstanceModeService.windowMethodChannelName)
          .setMethodCallHandler(null);
    }
  }

  /// macOS application menu → Flutter (Preferences, updates, File menu).
  void initialize() {
    if (!Platform.isMacOS) return;
    const channel = MethodChannel(InstanceModeService.windowMethodChannelName);
    channel.setMethodCallHandler((call) async {
      if (!isActive()) return null;
      switch (call.method) {
        case InstanceModeService.checkForUpdatesMethod:
          await onCheckForUpdates();
          return null;
        case InstanceModeService.openPreferencesMethod:
          onOpenPreferences();
          return null;
        case InstanceModeService.openFileMethod:
          unawaited(open.openFile());
          return null;
        case InstanceModeService.openFolderMethod:
          unawaited(open.openFolder());
          return null;
        case InstanceModeService.openPlaylistMethod:
          unawaited(open.openPlaylistPicker());
          return null;
        case InstanceModeService.openUrlMethod:
          unawaited(open.openUrl());
          return null;
        case InstanceModeService.reopenLastMethod:
          unawaited(open.reopenLastFile());
          return null;
        case InstanceModeService.savePlaylistMethod:
          unawaited(open.exportPlaylistQueue());
          return null;
        case InstanceModeService.newWindowMethod:
          unawaited(InstanceModeService.openNewWindow());
          return null;
        case InstanceModeService.clearRecentFilesMethod:
          settings.clearRecentFiles();
          media.clearJumpList();
          return null;
        case InstanceModeService.openRecentMethod:
          final path = call.arguments;
          if (path is String && path.trim().isNotEmpty) {
            open.loadRecentFile(path.trim());
          }
          return null;
        case InstanceModeService.getRecentFilesMethod:
          await settings.pruneRecentFiles(notifyListeners: false);
          return settings.recentFiles;
        default:
          return null;
      }
    });
  }
}
