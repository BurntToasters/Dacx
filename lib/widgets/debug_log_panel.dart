import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/debug_log_service.dart';

class DebugLogPanel extends StatelessWidget {
  const DebugLogPanel({super.key, required this.debugLog});

  final DebugLogService debugLog;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                      const Expanded(
                        child: Text(
                          'Debug Log',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${debugLog.entryCount} entries',
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
                        label: const Text('Copy Log'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: debugLog.entryCount > 0
                            ? () => _clearDebugLog(context)
                            : null,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Clear Log'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('No debug events yet.'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Redacted debug log copied to clipboard.')),
    );
  }

  void _clearDebugLog(BuildContext context) {
    debugLog.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug log cleared.')));
  }

  static String renderDebugEntry(DebugLogEntry entry) {
    final detailsText = _renderDebugDetails(entry.details);
    final base =
        '[${entry.timestamp.toIso8601String()}] '
        '[${entry.severity.name.toUpperCase()}] '
        '[${entry.category.name}] '
        '${entry.event}';
    final msg = entry.message?.trim();
    if (msg != null && msg.isNotEmpty && detailsText.isNotEmpty) {
      return '$base - $msg | $detailsText';
    }
    if (msg != null && msg.isNotEmpty) return '$base - $msg';
    if (detailsText.isNotEmpty) return '$base | $detailsText';
    return base;
  }

  static String _renderDebugDetails(Map<String, Object?> details) {
    if (details.isEmpty) return '';
    final keys = details.keys.toList()..sort();
    return keys
        .map((key) {
          final safe = details[key]?.toString().replaceAll('\n', r'\n');
          return '$key=$safe';
        })
        .join(', ');
  }
}
