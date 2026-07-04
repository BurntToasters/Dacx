import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/debug_log_service.dart';

class DebugLogPanel extends StatelessWidget {
  const DebugLogPanel({super.key, required this.debugLog});

  final DebugLogService debugLog;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: ListenableBuilder(
            listenable: debugLog,
            builder: (context, _) {
              final entries = debugLog.entries;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.debugLogTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        l10n.debugLogEntryCount(debugLog.entryCount),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _copyDebugLog(context),
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: Text(l10n.debugLogCopyButton),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: debugLog.entryCount > 0
                            ? () => _clearDebugLog(context)
                            : null,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(l10n.debugLogClearButton),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(l10n.debugLogEmpty),
                    )
                  else
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[entries.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              renderDebugEntry(entry),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    height: 1.28,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _copyDebugLog(BuildContext context) async {
    final text = debugLog.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    debugLog.log(
      category: DebugLogCategory.ui,
      event: 'debug_log_copied',
      details: {'entry_count': debugLog.entryCount},
    );
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.snackDebugLogCopied)));
  }

  void _clearDebugLog(BuildContext context) {
    debugLog.clear();
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.snackDebugLogCleared)));
  }

  static String renderDebugEntry(DebugLogEntry entry) {
    return DebugLogService.formatEntry(entry);
  }
}
