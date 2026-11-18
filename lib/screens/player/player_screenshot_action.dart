import 'dart:async';

import '../../l10n/app_localizations.dart';
import '../../playback/player_controller.dart';
import '../../playback/screenshot_saver.dart';
import '../../services/bookmark_service.dart';
import '../../services/debug_log_service.dart';
import '../../services/path_probe.dart';
import '../../services/player_service.dart';
import '../../services/settings_service.dart';
import 'player_log.dart';
import 'source_load_coordinator.dart';

class PlayerScreenshotAction {
  PlayerScreenshotAction({
    required this.settings,
    required this.playerService,
    required this.player,
    required this.sourceLoad,
    required this.log,
    required this.isMounted,
    required this.l10n,
    required this.showOsd,
    required this.showMessage,
    required this.operationForTesting,
  });

  final SettingsService settings;
  final IPlayerService playerService;
  final PlayerController player;
  final SourceLoadCoordinator sourceLoad;
  final PlayerDebugLog log;
  final bool Function() isMounted;
  final AppLocalizations Function() l10n;
  final void Function(String message) showOsd;
  final void Function(String message) showMessage;
  final Completer<void>? Function() operationForTesting;

  Future<void> take() async {
    final strings = l10n();
    try {
      final source = player.currentSource;
      if (source == null) return;
      final configuredDirectory = settings.screenshotDir;
      final customDirectory =
          configuredDirectory != null &&
              await PathProbe.directoryExists(configuredDirectory)
          ? configuredDirectory
          : null;
      final saver = ScreenshotSaver(
        capture: (mime) => playerService.screenshot(format: mime),
        resolveScope: sourceLoad.resolveBookmarkScope,
        releaseScope: BookmarkService.stop,
      );
      final result = await saver.save(
        source: source,
        format: settings.screenshotFormat,
        customDirectory: customDirectory,
      );
      switch (result.outcome) {
        case ScreenshotSaveOutcome.noFrame:
          showOsd(strings.osdScreenshotFailed);
        case ScreenshotSaveOutcome.directoryUnavailable:
          log(
            'screenshot_dir_create_failed',
            message: result.error.toString(),
            details: {'dir': result.directory},
            severity: DebugSeverity.warn,
          );
          if (isMounted()) {
            showMessage(strings.snackScreenshotDirInaccessible);
          }
          showOsd(strings.osdScreenshotSaveFailed);
        case ScreenshotSaveOutcome.saved:
          showOsd(strings.osdScreenshotSaved);
          log('screenshot_saved', detailsBuilder: () => {'path': result.path});
        case ScreenshotSaveOutcome.writeFailed:
          showOsd(strings.osdScreenshotSaveFailed);
          log(
            'screenshot_save_failed',
            message: result.error.toString(),
            severity: DebugSeverity.warn,
          );
      }
    } finally {
      final done = operationForTesting();
      if (done != null && !done.isCompleted) {
        done.complete();
      }
    }
  }
}
