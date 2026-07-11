import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QueueItemTile extends StatelessWidget {
  const QueueItemTile({
    super.key,
    required this.name,
    required this.isCurrent,
    required this.isUrl,
    required this.playLabel,
    required this.removeLabel,
    required this.colorScheme,
    required this.onActivate,
    required this.onRemove,
    this.reorderLabel,
    this.focusNode,
  });

  final String name;
  final bool isCurrent;
  final bool isUrl;
  final String playLabel;
  final String removeLabel;
  final String? reorderLabel;
  final ColorScheme colorScheme;
  final VoidCallback onActivate;
  final VoidCallback onRemove;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final baseLabel = isCurrent ? '$playLabel: $name' : name;
    final label = reorderLabel == null
        ? baseLabel
        : '$baseLabel. $reorderLabel';
    return Semantics(
      label: label,
      selected: isCurrent,
      button: true,
      onTap: onActivate,
      onLongPress: onRemove,
      child: Focus(
        focusNode: focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown) {
            FocusScope.of(context).nextFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            FocusScope.of(context).previousFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.space) {
            onActivate();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.delete ||
              key == LogicalKeyboardKey.backspace) {
            onRemove();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Material(
            color: isCurrent
                ? colorScheme.primaryContainer.withValues(alpha: 0.58)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              canRequestFocus: false,
              onTap: onActivate,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        isCurrent
                            ? Icons.play_arrow
                            : isUrl
                            ? Icons.link
                            : Icons.music_note,
                        size: 18,
                        color: isCurrent
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isCurrent
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (reorderLabel != null)
                      ExcludeSemantics(
                        child: Tooltip(
                          message: reorderLabel!,
                          child: Icon(
                            Icons.drag_handle,
                            size: 18,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.40,
                            ),
                          ),
                        ),
                      ),
                    ExcludeFocus(
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: removeLabel,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onRemove,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
