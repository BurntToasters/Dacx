import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/release_notes_formatter.dart';
import '../services/update_service.dart';
import 'dialog_sizing.dart';
import 'update_progress_dialog.dart';

class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.info,
    required this.summary,
    required this.confirmLabel,
    required this.releaseNotesUrl,
    required this.onOpenReleaseNotes,
  });

  final UpdateInfo info;
  final ReleaseNotesSummary summary;
  final String confirmLabel;
  final String? releaseNotesUrl;
  final ValueChanged<String> onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final url = releaseNotesUrl;
    return AlertDialog(
      title: Text(l10n.snackUpdateAvailable(info.version)),
      content: SizedBox(
        width: dialogWidth(context, 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!summary.isEmpty) ...[
              Text(l10n.updateWhatsNewTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Flexible(
                child: ConstrainedBox(
                  key: const Key('update-whats-new-list'),
                  constraints: BoxConstraints(
                    maxHeight: dialogHeight(context, 260),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in summary.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  '),
                                Expanded(child: Text(entry)),
                              ],
                            ),
                          ),
                        if (summary.hiddenCount > 0)
                          Text(
                            l10n.updateWhatsNewMore(summary.hiddenCount),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (url != null)
          TextButton(
            key: const Key('update-release-notes-button'),
            onPressed: () => onOpenReleaseNotes(url),
            child: Text(l10n.updateReleaseNotesAction),
          ),
        TextButton(
          key: const Key('update-available-later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.updateActionLater),
        ),
        FilledButton(
          key: const Key('update-available-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

Future<bool> showUpdateAvailableDialog({
  required BuildContext context,
  required UpdateInfo info,
  required UpdateService updateService,
}) async {
  final l10n = AppLocalizations.of(context);
  final summary = formatReleaseNotes(info.notes, version: info.version);
  final candidate = info.releaseUrl.isNotEmpty ? info.releaseUrl : info.url;
  final releaseNotesUrl = isGithubReleaseUrl(candidate) ? candidate : null;
  final confirmLabel = updateActionLabel(l10n);
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => UpdateAvailableDialog(
      info: info,
      summary: summary,
      confirmLabel: confirmLabel,
      releaseNotesUrl: releaseNotesUrl,
      onOpenReleaseNotes: (url) => updateService.openReleasePage(url),
    ),
  );
  return result ?? false;
}
