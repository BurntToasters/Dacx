import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../services/settings_service.dart';

Future<void> restoreWindowGeometry(
  SettingsService settings, {
  Offset? position,
}) async {
  if (position != null) {
    await windowManager.setPosition(position);
  }
  if (settings.rememberWindow && settings.windowMaximized) {
    await windowManager.maximize();
  }
}
