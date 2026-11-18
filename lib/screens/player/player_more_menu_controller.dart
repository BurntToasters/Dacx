import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../playback/player_controller.dart';
import '../../services/advanced_playback_controller.dart';
import '../../services/playlist_service.dart';
import '../../services/settings_service.dart';
import '../../playback/sleep_timer_controller.dart';
import '../../widgets/advanced_playback_dialog.dart';
import '../../widgets/equalizer_dialog.dart';
import '../../widgets/keybinds_dialog.dart';
import '../../widgets/track_pickers.dart';
import 'player_open_actions.dart';
import 'player_screenshot_action.dart';
import 'player_transport_controller.dart';
import 'player_window_controller.dart';
import 'source_load_coordinator.dart';
import 'track_chapter_controller.dart';
import 'widgets/player_more_menu.dart';

class PlayerMoreMenuController {
  PlayerMoreMenuController({
    required this.settings,
    required this.player,
    required this.advancedPlayback,
    required this.sleepTimer,
    required this.playlist,
    required this.window,
    required this.transport,
    required this.trackController,
    required this.sourceLoad,
    required this.open,
    required this.screenshot,
    required this.hasCurrentFile,
    required this.isMounted,
    required this.isDisposed,
    required this.l10n,
    required this.showTimedMessage,
    required this.openQueueDrawer,
  });

  final SettingsService settings;
  final PlayerController player;
  final AdvancedPlaybackController advancedPlayback;
  final SleepTimerController sleepTimer;
  final PlaylistService Function() playlist;
  final PlayerWindowController window;
  final PlayerTransportController transport;
  final TrackChapterController trackController;
  final SourceLoadCoordinator sourceLoad;
  final PlayerOpenActions open;
  final PlayerScreenshotAction screenshot;
  final bool Function() hasCurrentFile;
  final bool Function() isMounted;
  final bool Function() isDisposed;
  final AppLocalizations Function() l10n;
  final void Function(String message) showTimedMessage;
  final void Function() openQueueDrawer;

  void onSleepTimerFired() {
    if (!isMounted() || isDisposed()) return;
    unawaited(() async {
      await sourceLoad.stopPlaybackAndResetUi();
      if (!isMounted() || isDisposed()) return;
      showTimedMessage(l10n().snackSleepTimerFired);
    }());
  }

  void setSleepTimerMinutes(int? minutes) {
    final strings = l10n();
    if (minutes == null) {
      final wasActive = sleepTimer.isActive;
      sleepTimer.cancel();
      if (!wasActive || !isMounted()) return;
      showTimedMessage(strings.snackSleepTimerCancelled);
      return;
    }
    sleepTimer.startMinutes(minutes);
    if (!isMounted()) return;
    showTimedMessage(strings.snackSleepTimerSet(minutes));
  }

  bool _menuOpen = false;

  Future<void> showMoreMenu(BuildContext context, {Rect? anchor}) async {
    if (_menuOpen) return;
    _menuOpen = true;
    try {
      final tracks = player.currentTracks;
      final hasAudioOptions = tracks != null && tracks.audio.length > 1;
      final hasSubOptions = tracks != null && tracks.subtitle.isNotEmpty;
      final hasChapters = ValueNotifier<bool>(player.chapters.isNotEmpty);
      var closed = false;
      if (player.chapters.isEmpty) {
        unawaited(
          trackController
              .refreshChapters()
              .then((_) {
                if (closed) return;
                hasChapters.value = player.chapters.isNotEmpty;
              })
              .catchError((Object _) {}),
        );
      }

      final String? result;
      try {
        result = await showPlayerMoreMenu(
          context: context,
          hasAudioOptions: hasAudioOptions,
          hasSubOptions: hasSubOptions,
          hasChapters: hasChapters,
          hasCurrentFile: hasCurrentFile,
          compactMode: () => window.compactMode,
          settings: settings,
          sleepTimer: sleepTimer,
          playlist: playlist(),
          onSetShuffle: transport.setShuffle,
          anchor: anchor,
        );
      } finally {
        closed = true;
      }
      if (!context.mounted) return;
      dispatchPlayerMoreMenuResult(
        result,
        PlayerMoreMenuActions(
          onOpenUrl: () => unawaited(open.openUrl()),
          onAudioTracks: () => unawaited(showAudioTracksDialog(context)),
          onSubtitleTracks: () => unawaited(showSubtitleTracksDialog(context)),
          onExternalAudio: () => unawaited(trackController.pickExternalAudio()),
          onExternalSubtitle: () =>
              unawaited(trackController.pickExternalSubtitle()),
          onChapters: () => unawaited(showChaptersDialog(context)),
          onEqualizer: () => unawaited(
            showEqualizerDialog(
              context: context,
              settings: settings,
              onApply: trackController.applyEqualizer,
            ),
          ),
          onAdvancedPlayback: () =>
              unawaited(showAdvancedPlaybackDialog(context)),
          onScreenshot: () => unawaited(screenshot.take()),
          onSleepTimer: setSleepTimerMinutes,
          onKeybinds: () => unawaited(
            showKeybindsDialog(context: context, settings: settings),
          ),
          onQueue: openQueueDrawer,
          onEnqueue: () => unawaited(open.pickFilesToEnqueue()),
          onSetShuffle: transport.setShuffle,
          onCompact: () => unawaited(window.toggleCompactMode()),
        ),
      );
    } finally {
      _menuOpen = false;
    }
  }

  Future<void> showAdvancedPlaybackDialog(BuildContext context) async {
    if (!settings.advancedPlaybackToolsEnabled) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AdvancedPlaybackDialog(
        controller: advancedPlayback,
        settings: settings,
      ),
    );
  }

  Future<void> showAudioTracksDialog(BuildContext context) async {
    final request = trackController.audioPickerRequest();
    if (request == null) return;
    final selected = await pickAudioTrack(
      context,
      tracks: request.tracks,
      currentId: request.currentId,
    );
    if (selected != null) {
      await trackController.selectAudioTrackFromPicker(selected);
    }
  }

  Future<void> showSubtitleTracksDialog(BuildContext context) async {
    final request = trackController.subtitlePickerRequest();
    if (request == null) return;
    final selected = await pickSubtitleTrack(
      context,
      tracks: request.tracks,
      currentId: request.currentId,
    );
    if (selected != null) {
      await trackController.selectSubtitleTrackFromPicker(selected);
    }
  }

  Future<void> showChaptersDialog(BuildContext context) async {
    if (player.chapters.isEmpty) await trackController.refreshChapters();
    if (!context.mounted || player.chapters.isEmpty) return;
    final picked = await pickChapter(context, player.chapters);
    if (picked != null) {
      await trackController.jumpToChapter(picked);
    }
  }
}
