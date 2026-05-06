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

  @override
  String get snackUnableToOpenFilePicker => 'Unable to open file picker.';

  @override
  String snackFilePickerFailed(String detail) {
    return 'File picker failed. $detail';
  }

  @override
  String get snackInvalidFilePath => 'Invalid file path. Try another file.';

  @override
  String get snackFileNotFound =>
      'File not found. It may have moved or been deleted.';

  @override
  String get snackUnsupportedFileType =>
      'Unsupported file type. Open an audio/video file.';

  @override
  String get snackFullscreenRejected =>
      'Fullscreen change rejected by window manager.';

  @override
  String snackUpdateAvailable(String version) {
    return 'Dacx v$version is available';
  }

  @override
  String get snackSkippedUnreadableFile => 'Skipped 1 unreadable file.';

  @override
  String snackSkippedUnreadableFiles(int count) {
    return 'Skipped $count unreadable files.';
  }

  @override
  String get emptyStateMessage => 'Drop a file here or click Open';

  @override
  String get buttonOpenFile => 'Open File';

  @override
  String get buttonReopenLast => 'Reopen Last';

  @override
  String get dialogAudioTrackTitle => 'Audio track';

  @override
  String get dialogSubtitleTrackTitle => 'Subtitle track';

  @override
  String get dialogChaptersTitle => 'Chapters';

  @override
  String get dialogEqualizerTitle => 'Equalizer';

  @override
  String get dialogEqualizerEnable => 'Enable';

  @override
  String get dialogPlayQueueTitle => 'Play queue';

  @override
  String get dialogPlayQueueEmpty => 'Queue is empty.';

  @override
  String get dialogPlayQueueAddFiles => 'Add files…';

  @override
  String get dialogKeyboardShortcutsTitle => 'Keyboard shortcuts';

  @override
  String get dialogKeyCaptureTitle => 'Press a key combination';

  @override
  String get actionReset => 'Reset';

  @override
  String get actionResetAll => 'Reset all';

  @override
  String get actionClose => 'Close';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionSetNewBinding => 'Set new binding';

  @override
  String get actionResetToDefault => 'Reset to default';

  @override
  String get labelAudioPlayback => 'Audio playback';

  @override
  String get tooltipReopenLast => 'Reopen last file (Ctrl/Cmd+R)';

  @override
  String get tooltipStop => 'Stop';

  @override
  String get tooltipMore => 'More';

  @override
  String get tooltipSettings => 'Settings';

  @override
  String get tooltipOpenFile => 'Open file';

  @override
  String get tooltipRecentFiles => 'Recent files';

  @override
  String get windowMinimize => 'Minimize window';

  @override
  String get windowMaximize => 'Maximize window';

  @override
  String get windowRestore => 'Restore window';

  @override
  String get windowClose => 'Close window';

  @override
  String get actionPlay => 'Play';

  @override
  String get actionPause => 'Pause';

  @override
  String get loopOff => 'Loop: Off';

  @override
  String get loopAll => 'Loop: All';

  @override
  String get loopSingle => 'Loop: Single';

  @override
  String get volumeLabel => 'Volume';

  @override
  String get volumeMuted => 'Muted';

  @override
  String volumePercent(int pct) {
    return 'Volume $pct percent';
  }
}
