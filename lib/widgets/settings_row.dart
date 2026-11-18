import 'package:flutter/material.dart';

class SettingsRow extends StatelessWidget {
  static const double defaultStackBelowWidth = 560.0;

  final Widget title;
  final Widget? subtitle;
  final Widget control;
  final double stackBelowWidth;

  const SettingsRow({
    super.key,
    required this.title,
    required this.control,
    this.subtitle,
    this.stackBelowWidth = defaultStackBelowWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultTextStyle.merge(
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          child: title,
        ),
        if (subtitle != null)
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            child: subtitle!,
          ),
      ],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth + 32 < stackBelowWidth;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  texts,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: control),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: texts),
                const SizedBox(width: 16),
                control,
              ],
            );
          },
        ),
      ),
    );
  }
}
