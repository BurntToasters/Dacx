// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Dacx';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAutoPlay => 'Auto-play on file open';

  @override
  String get settingsResumePlayback => 'Resume from last position';

  @override
  String get settingsOnScreenDisplay => 'On-screen display';

  @override
  String get settingsMediaSession => 'System media keys / Now Playing';

  @override
  String get settingsAlwaysOnTop => 'Always on top';

  @override
  String get settingsRememberWindow => 'Remember window size & position';

  @override
  String get settingsAllowMultipleWindows => 'Allow multiple windows';

  @override
  String get settingsCheckForUpdates => 'Check for updates on launch';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsAccentColor => 'Accent color';

  @override
  String get settingsHardwareAcceleration => 'Hardware acceleration';

  @override
  String get settingsHardwareAccelerationRestartNote =>
      'Requires restart to take effect';

  @override
  String get settingsPlaybackSpeed => 'Playback speed';

  @override
  String get settingsLoopMode => 'Loop mode';

  @override
  String get snackCouldNotReadDroppedFile =>
      'Could not read dropped file path.';

  @override
  String get snackCouldNotReadSelectedFile =>
      'Could not read selected file path.';

  @override
  String get snackDebugLogCopied => 'Redacted debug log copied to clipboard.';

  @override
  String get snackDebugLogCleared => 'Debug log cleared.';
}
