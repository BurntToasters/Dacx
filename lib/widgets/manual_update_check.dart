import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/debug_log_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import 'update_progress_dialog.dart';

/// Shared manual “Check for Updates” flow used by Settings and the macOS
/// application menu. Shows the same snackbars / install action as Settings.
Future<void> runManualUpdateCheck({
  required BuildContext context,
  required UpdateService updateService,
  required SettingsService settings,
  DebugLogService? debugLog,
  void Function(String event, {String? message, DebugSeverity? severity})?
  onLog,
}) async {
  onLog?.call('manual_update_check_requested');
  try {
    final update = await updateService.checkForUpdate(
      channel: settings.updateChannel,
    );
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    if (!updateService.lastCheckSucceeded) {
      onLog?.call('manual_update_check_failed', severity: DebugSeverity.warn);
      final message = updateService.lastCheckRateLimited
          ? l10n.snackUpdateRateLimited
          : updateService.lastCheckNetworkError
          ? l10n.snackUpdateNetworkError
          : l10n.snackUpdateCheckFailed;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (update != null) {
      onLog?.call('manual_update_available');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.snackUpdateAvailable(update.version)),
          action: SnackBarAction(
            label: updateActionLabel(l10n),
            onPressed: () => triggerUpdateAction(
              context: context,
              info: update,
              updateService: updateService,
              channelName: settings.updateChannel.name,
              debugLog: debugLog,
            ),
          ),
        ),
      );
      return;
    }
    onLog?.call('manual_update_not_available');
    final isBeta = updateService.lastEffectiveChannel == UpdateChannel.beta;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isBeta ? l10n.snackUpdateLatestBeta : l10n.snackUpdateLatest,
        ),
      ),
    );
  } catch (e) {
    onLog?.call(
      'manual_update_check_failed',
      message: e.toString(),
      severity: DebugSeverity.error,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).snackUpdateCheckFailed),
      ),
    );
  }
}
