import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/debug_log_service.dart';
import '../../services/settings_service.dart';
import '../../services/update_service.dart';
import '../../theme/window_visuals.dart';
import '../../widgets/keybinds_dialog.dart';
import '../settings_screen.dart';
import 'player_log.dart';

const _settingsFwdTransition = Duration(milliseconds: 340);
const _settingsRevTransition = Duration(milliseconds: 280);

void openPlayerSettings({
  required BuildContext context,
  required SettingsService settings,
  required DebugLogService debugLog,
  required UpdateService updateService,
  required PlayerDebugLog log,
}) {
  if (!context.mounted) return;
  log('open_settings_requested', category: DebugLogCategory.ui);
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: _settingsFwdTransition,
      reverseTransitionDuration: _settingsRevTransition,
      pageBuilder: (_, _, _) => SettingsScreen(
        settings: settings,
        debugLog: debugLog,
        updateService: updateService,
        onEditKeybinds: () =>
            unawaited(showKeybindsDialog(context: context, settings: settings)),
      ),
      opaque: false,
      transitionsBuilder: (context, animation, _, child) {
        // Mask ramps up quickly to hide the player underneath the
        // semi-transparent settings scaffold when blur is active.
        final visuals = context.windowVisuals;
        final maskOpacity = Curves.easeOut.transform(
          (animation.value / 0.45).clamp(0.0, 1.0),
        );
        final zoom = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
            reverseCurve: const Interval(0.0, 0.5, curve: Curves.easeIn),
          ),
        );
        final scale = Tween<double>(begin: 0.94, end: 1.0).animate(zoom);
        final settleOffset = Tween<Offset>(
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(zoom);

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: visuals.overlayTopColor.withValues(alpha: maskOpacity),
            ),
            FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: settleOffset,
                child: ScaleTransition(scale: scale, child: child),
              ),
            ),
          ],
        );
      },
    ),
  );
}
