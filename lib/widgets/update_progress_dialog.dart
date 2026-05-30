import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/debug_log_service.dart';
import '../services/self_update_service.dart';
import '../services/update_service.dart';

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
String updateActionLabel() =>
    SelfUpdateService.isSupported() ? 'Install' : 'View';

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

  String _outcomeLabel(SelfUpdateOutcome o) {
    switch (o) {
      case SelfUpdateOutcome.unsupportedPlatform:
        return 'Self-update is not supported on this platform.';
      case SelfUpdateOutcome.missingAsset:
        return 'The release does not include an installer for this platform.';
      case SelfUpdateOutcome.missingChecksums:
        return 'The release does not include a checksums file. Cannot verify download.';
      case SelfUpdateOutcome.missingSignature:
        return 'The release does not include a signed update manifest. Cannot verify update authenticity.';
      case SelfUpdateOutcome.downloadFailed:
        return 'Download failed.';
      case SelfUpdateOutcome.checksumMismatch:
        return 'Downloaded file failed checksum verification. Refusing to install.';
      case SelfUpdateOutcome.extractionFailed:
        return 'Could not extract the update package.';
      case SelfUpdateOutcome.signatureInvalid:
        return 'Downloaded app failed code-signature verification.';
      case SelfUpdateOutcome.bundleIdentifierMismatch:
        return 'Downloaded app has an unexpected bundle identifier. Refusing to install.';
      case SelfUpdateOutcome.versionMismatch:
        return 'Downloaded app version does not match the selected update. Refusing to install.';
      case SelfUpdateOutcome.teamIdMismatch:
        return 'Downloaded app is signed by an unexpected developer. Refusing to install.';
      case SelfUpdateOutcome.gatekeeperRejected:
        return 'Self-update is not available on this build (missing signing configuration).';
      case SelfUpdateOutcome.spawnFailed:
        return 'Could not launch the installer.';
      case SelfUpdateOutcome.spawned:
        return 'Update started.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) return _buildErrorDialog(context, result);
    return _buildProgressDialog(context);
  }

  Widget _buildProgressDialog(BuildContext context) {
    final progress = _progress;
    final fraction = progress?.fraction;
    final downloaded = progress?.downloadedBytes ?? 0;
    final total = progress?.totalBytes;
    final showVerifying = fraction == 1.0;
    final statusText = Platform.isMacOS && progress == null
        ? 'Downloading and verifying in the update helper...'
        : showVerifying
        ? 'Verifying signature...'
        : total != null
        ? 'Downloading ${_formatMb(downloaded)} / ${_formatMb(total)}'
        : 'Downloading...';

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Installing Dacx ${widget.info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: fraction),
            const SizedBox(height: 12),
            Text(statusText, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Dacx will close to apply the update.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDialog(BuildContext context, SelfUpdateResult result) {
    return AlertDialog(
      title: const Text('Update failed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_outcomeLabel(result.outcome)),
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
          child: const Text('Open release page'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(result),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
