import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../playback/linux_install_kind.dart';
import '../services/debug_log_service.dart';
import '../services/self_update_service.dart';
import '../services/update_service.dart';

/// Package-aware Linux update copy (and generic fallback).
String linuxUpdateGuidance(AppLocalizations l10n, {LinuxInstallKind? kind}) {
  final detected = kind ?? LinuxInstallDetector.detect();
  return switch (detected) {
    LinuxInstallKind.flatpak => l10n.linuxUpdateGuidanceFlatpak,
    LinuxInstallKind.appImage => l10n.linuxUpdateGuidanceAppImage,
    LinuxInstallKind.debOrRpm => l10n.linuxUpdateGuidanceDebRpm,
    LinuxInstallKind.portable => l10n.linuxUpdateGuidancePortable,
    LinuxInstallKind.unknown => l10n.linuxUpdateGuidanceGeneric,
  };
}

String unsupportedPlatformUpdateMessage(AppLocalizations l10n) {
  if (Platform.isLinux) {
    return l10n.updateOutcomeUnsupportedPlatformLinux(
      linuxUpdateGuidance(l10n),
    );
  }
  return l10n.updateOutcomeUnsupportedPlatform;
}

/// Snackbar/Settings entry point. On Win/Mac shows the install progress
/// dialog and exits the app on a successful spawn so the helper/watchdog
/// can replace files. On other platforms (or when self-update is
/// unavailable) opens the release page in the browser instead.
Future<void> triggerUpdateAction({
  required BuildContext context,
  required UpdateInfo info,
  required UpdateService updateService,
  required String channelName,
  DebugLogService? debugLog,
}) async {
  if (!SelfUpdateService.isSupported()) {
    await updateService.openReleasePage(info.url);
    return;
  }
  await UpdatePendingMarker.write(
    targetVersion: info.version,
    channel: channelName,
  );
  if (!context.mounted) return;
  final result = await showDialog<SelfUpdateResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateProgressDialog(
      info: info,
      service: SelfUpdateService(debugLog: debugLog),
      onFallbackToBrowser: () => updateService.openReleasePage(info.url),
    ),
  );
  if (result?.outcome == SelfUpdateOutcome.spawned) {
    exit(0);
  }
  UpdatePendingMarker.readAndClear();
}

/// Returns the right snackbar action label for the current platform.
String updateActionLabel(AppLocalizations l10n) =>
    SelfUpdateService.isSupported()
    ? l10n.updateActionInstall
    : l10n.updateActionView;

class UpdateProgressDialog extends StatefulWidget {
  const UpdateProgressDialog({
    super.key,
    required this.info,
    required this.service,
    required this.onFallbackToBrowser,
  });

  final UpdateInfo info;
  final SelfUpdateService service;
  final VoidCallback onFallbackToBrowser;

  @override
  State<UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<UpdateProgressDialog> {
  SelfUpdateProgress? _progress;
  SelfUpdateResult? _result;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final result = await widget.service.applyUpdate(
      widget.info,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (result.outcome == SelfUpdateOutcome.spawned) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() => _result = result);
  }

  String _formatMb(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  String _outcomeLabel(AppLocalizations l10n, SelfUpdateOutcome o) {
    return switch (o) {
      SelfUpdateOutcome.unsupportedPlatform => unsupportedPlatformUpdateMessage(
        l10n,
      ),
      SelfUpdateOutcome.missingAsset => l10n.updateOutcomeMissingAsset,
      SelfUpdateOutcome.missingChecksums => l10n.updateOutcomeMissingChecksums,
      SelfUpdateOutcome.missingSignature => l10n.updateOutcomeMissingSignature,
      SelfUpdateOutcome.downloadFailed => l10n.updateOutcomeDownloadFailed,
      SelfUpdateOutcome.checksumMismatch => l10n.updateOutcomeChecksumMismatch,
      SelfUpdateOutcome.extractionFailed => l10n.updateOutcomeExtractionFailed,
      SelfUpdateOutcome.signatureInvalid => l10n.updateOutcomeSignatureInvalid,
      SelfUpdateOutcome.bundleIdentifierMismatch =>
        l10n.updateOutcomeBundleIdMismatch,
      SelfUpdateOutcome.versionMismatch => l10n.updateOutcomeVersionMismatch,
      SelfUpdateOutcome.teamIdMismatch => l10n.updateOutcomeTeamIdMismatch,
      SelfUpdateOutcome.gatekeeperRejected =>
        l10n.updateOutcomeGatekeeperRejected,
      SelfUpdateOutcome.spawnFailed => l10n.updateOutcomeSpawnFailed,
      SelfUpdateOutcome.spawned => l10n.updateOutcomeStarted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) return _buildErrorDialog(context, result);
    return _buildProgressDialog(context);
  }

  Widget _buildProgressDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = _progress;
    final fraction = progress?.fraction;
    final downloaded = progress?.downloadedBytes ?? 0;
    final total = progress?.totalBytes;
    final showVerifying = fraction == 1.0;
    final statusText = Platform.isMacOS && progress == null
        ? l10n.updateDialogDownloadingVerifying
        : showVerifying
        ? l10n.updateDialogVerifyingSignature
        : total != null
        ? l10n.updateDialogDownloadingProgress(
            _formatMb(downloaded),
            _formatMb(total),
          )
        : l10n.updateDialogDownloading;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.updateDialogInstallingTitle(widget.info.version)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: fraction),
            const SizedBox(height: 12),
            Text(statusText, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              l10n.updateDialogWillClose,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDialog(BuildContext context, SelfUpdateResult result) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.updateDialogFailedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_outcomeLabel(l10n, result.outcome)),
          if (result.message != null && result.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(result.message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onFallbackToBrowser();
            Navigator.of(context).pop(result);
          },
          child: Text(l10n.updateDialogOpenReleasePage),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(result),
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}
