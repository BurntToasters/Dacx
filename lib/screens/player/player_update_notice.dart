import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../playback/update_launch_policy.dart';
import '../../services/debug_log_service.dart';
import '../../services/self_update_service.dart';
import '../../services/settings_service.dart';
import '../../services/update_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/manual_update_check.dart';
import '../../widgets/update_progress_dialog.dart';
import 'player_log.dart';

const _updateSnackbarDuration = Duration(seconds: 10);

class PlayerUpdateNotice {
  PlayerUpdateNotice({
    required this.settings,
    required this.updateService,
    required this.debugLog,
    required this.log,
  });

  final SettingsService settings;
  final UpdateService updateService;
  final DebugLogService debugLog;
  final PlayerDebugLog log;

  Future<void> runManualCheck(BuildContext context) {
    return runManualUpdateCheck(
      context: context,
      updateService: updateService,
      settings: settings,
      debugLog: debugLog,
      onLog: (event, {message, severity}) {
        log(
          event,
          category: DebugLogCategory.update,
          message: message,
          severity: severity ?? DebugSeverity.info,
        );
      },
    );
  }

  Future<void> showPendingNotice(BuildContext context) async {
    final marker = UpdatePendingMarker.readAndClear();
    if (!context.mounted) return;
    final actualVersion = await UpdateService.currentVersionFromPlatform();
    final decision = UpdateLaunchPolicy.decide(
      marker: marker,
      nowEpochMs: DateTime.now().millisecondsSinceEpoch,
      actualVersion: actualVersion,
    );
    if (!context.mounted || !decision.shouldShow) return;
    final targetVersion = decision.targetVersion!;
    final messenger = ScaffoldMessenger.of(context);
    if (decision.kind == UpdateLaunchNoticeKind.success) {
      log(
        'launch_update_succeeded_notice',
        category: DebugLogCategory.update,
        detailsBuilder: () => {'version': targetVersion},
      );
      messenger.showAppSnackBar(
        AppLocalizations.of(context).snackUpdatedToVersion(targetVersion),
      );
    } else {
      log(
        'launch_update_failed_notice',
        category: DebugLogCategory.update,
        severity: DebugSeverity.warn,
        detailsBuilder: () => {
          'target': targetVersion,
          'actual': actualVersion,
        },
      );
      messenger.showAppSnackBar(
        AppLocalizations.of(context).snackUpdateMayHaveFailed(targetVersion),
      );
    }
  }

  // ── Update check with cooldown ────────────────────────────

  Future<void> checkForUpdates(BuildContext context) async {
    if (!settings.shouldCheckForUpdate) return;
    log(
      'launch_update_check_started',
      category: DebugLogCategory.update,
      detailsBuilder: () => {'last_check_epoch': settings.lastUpdateCheck},
    );
    final update = await updateService.checkForUpdate(
      channel: settings.updateChannel,
    );
    final checkSucceeded = updateService.lastCheckSucceeded;
    if (checkSucceeded) {
      settings.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
    }
    if (update != null && context.mounted) {
      log(
        'launch_update_available',
        category: DebugLogCategory.update,
        detailsBuilder: () => {'version': update.version},
      );
      _showUpdateSnackbar(context, update);
    } else {
      if (checkSucceeded) {
        log('launch_update_not_available', category: DebugLogCategory.update);
      } else {
        log(
          'launch_update_check_failed',
          category: DebugLogCategory.update,
          severity: DebugSeverity.warn,
        );
      }
    }
  }

  void _showUpdateSnackbar(BuildContext context, UpdateInfo update) {
    if (!context.mounted) return;
    log(
      'update_snackbar_shown',
      category: DebugLogCategory.update,
      detailsBuilder: () => {'version': update.version},
    );
    showAppSnackBar(
      context,
      AppLocalizations.of(context).snackUpdateAvailable(update.version),
      duration: _updateSnackbarDuration,
      action: SnackBarAction(
        label: updateActionLabel(AppLocalizations.of(context)),
        onPressed: () => triggerUpdateAction(
          context: context,
          info: update,
          updateService: updateService,
          channelName: settings.updateChannel.name,
          debugLog: debugLog,
        ),
      ),
    );
  }
}
