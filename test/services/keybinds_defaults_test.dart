// Default keybindings and shortcut metadata sanity. These catch the most
// common UX regression: adding a new PlayerShortcutAction enum value and
// forgetting to wire a default accelerator or label, which silently
// breaks the customize-shortcuts UI and the no-modifier hot path.

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/player_shortcuts_service.dart';

void main() {
  group('default keybinds', () {
    test('every PlayerShortcutAction has at least one default accelerator', () {
      for (final action in PlayerShortcutAction.values) {
        final binding = defaultKeybinds[action];
        expect(binding, isNotNull, reason: 'no default keybind for $action');
        expect(
          binding!,
          isNotEmpty,
          reason: 'empty default binding list for $action',
        );
        for (final accel in binding) {
          expect(
            accel.trim(),
            isNotEmpty,
            reason: '$action contains empty accelerator',
          );
        }
      }
    });

    test('every PlayerShortcutAction has a non-empty user-facing label', () {
      for (final action in PlayerShortcutAction.values) {
        final label = shortcutActionLabel(action);
        expect(label.trim(), isNotEmpty, reason: 'no label for $action');
        // Catches accidental copy-paste duplicates like a label that just
        // echoes the enum name.
        expect(
          label,
          isNot(equals(action.name)),
          reason: 'label for $action looks like a placeholder',
        );
      }
    });

    test('no two actions share an identical no-modifier accelerator', () {
      // Modified accelerators (Ctrl/Shift/Alt) are allowed to overlap on the
      // base key; only the bare-key bindings would actually collide at
      // runtime.
      final seen = <String, PlayerShortcutAction>{};
      for (final entry in defaultKeybinds.entries) {
        for (final accel in entry.value) {
          if (accel.contains('+')) continue;
          final prior = seen[accel];
          expect(
            prior,
            isNull,
            reason:
                'accelerator "$accel" is bound to both ${entry.key} and $prior',
          );
          seen[accel] = entry.key;
        }
      }
    });
  });
}
