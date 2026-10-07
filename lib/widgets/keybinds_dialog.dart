import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/player_shortcuts_service.dart';
import '../services/settings_service.dart';
import 'dialog_sizing.dart';

Future<void> showKeybindsDialog({
  required BuildContext context,
  required SettingsService settings,
}) async {
  final current = Map<String, List<String>>.from(settings.keybinds);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final l10n = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l10n.dialogKeyboardShortcutsTitle),
            content: SizedBox(
              width: dialogWidth(ctx, 460),
              height: dialogHeight(ctx, 480),
              child: Scrollbar(
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        AppLocalizations.of(ctx).keybindsTip,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    ...PlayerShortcutAction.values
                        .where(
                          (a) =>
                              settings.advancedPlaybackToolsEnabled ||
                              !PlayerShortcutsService.isAdvancedAction(a),
                        )
                        .map((a) {
                          final accels =
                              current[a.name] ??
                              defaultKeybinds[a]?.toList(growable: true) ??
                              const <String>[];
                          return ListTile(
                            dense: true,
                            title: Text(
                              shortcutActionLabel(
                                a,
                                l10n: AppLocalizations.of(ctx),
                              ),
                            ),
                            subtitle: Text(
                              accels.isEmpty
                                  ? AppLocalizations.of(ctx).keybindsNone
                                  : accels
                                        .map(
                                          (a) =>
                                              PlayerShortcutsService.formatAcceleratorForDisplay(
                                                a,
                                                useMacSymbols: Platform.isMacOS,
                                              ),
                                        )
                                        .join(', '),
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: l10n.actionSetNewBinding,
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () async {
                                    final accel = await captureKeybind(ctx);
                                    if (accel == null) return;
                                    current[a.name] = [accel];
                                    settings.keybinds = current;
                                    setLocal(() {});
                                  },
                                ),
                                IconButton(
                                  tooltip: l10n.actionResetToDefault,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  onPressed: () {
                                    current.remove(a.name);
                                    settings.keybinds = current;
                                    setLocal(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  settings.resetKeybinds();
                  current.clear();
                  setLocal(() {});
                },
                child: Text(l10n.actionResetAll),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.actionClose),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> captureKeybind(BuildContext context) async {
  final node = FocusNode();
  String? captured;
  var saved = false;
  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final l10n = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l10n.dialogKeyCaptureTitle),
            content: SizedBox(
              width: dialogWidth(ctx, 320),
              child: Focus(
                autofocus: true,
                focusNode: node,
                onKeyEvent: (n, e) {
                  if (e is! KeyDownEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.pop(ctx);
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey != LogicalKeyboardKey.controlLeft &&
                      e.logicalKey != LogicalKeyboardKey.controlRight &&
                      e.logicalKey != LogicalKeyboardKey.shiftLeft &&
                      e.logicalKey != LogicalKeyboardKey.shiftRight &&
                      e.logicalKey != LogicalKeyboardKey.altLeft &&
                      e.logicalKey != LogicalKeyboardKey.altRight &&
                      e.logicalKey != LogicalKeyboardKey.metaLeft &&
                      e.logicalKey != LogicalKeyboardKey.metaRight) {
                    captured = PlayerShortcutsService.acceleratorFromEvent(e);
                    setLocal(() {});
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.center,
                  child: Text(
                    captured ?? l10n.keyCaptureWaiting,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.actionCancel),
              ),
              TextButton(
                onPressed: captured == null
                    ? null
                    : () {
                        saved = true;
                        Navigator.pop(ctx);
                      },
                child: Text(l10n.actionSave),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    node.dispose();
  }
  return saved ? captured : null;
}
