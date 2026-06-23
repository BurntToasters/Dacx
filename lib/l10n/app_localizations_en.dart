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
  String get settingsCheckForUpdatesOnLaunch => 'Check for updates on launch';

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
  String get settingsResumeSubtitle =>
      'Remember playback position for each file';

  @override
  String get settingsOsdSubtitle =>
      'Show title and time overlay during playback';

  @override
  String get settingsMediaSessionSubtitle =>
      'Publish playback to MPRIS / SMTC / Now Playing';

  @override
  String get settingsAllowMultipleWindowsSubtitle =>
      'When off (default), opening a file from your OS reuses the running Dacx window. Press Ctrl/Cmd+N to open an extra window on demand.';

  @override
  String get settingsSectionPlayback => 'Playback';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsSectionExperimental => 'Experimental';

  @override
  String get settingsSectionDebug => 'Debug';

  @override
  String get settingsBack => 'Back';

  @override
  String get settingsHwDecAuto => 'Auto';

  @override
  String get settingsHwDecSafe => 'Safe';

  @override
  String get settingsHwDecOff => 'Off';

  @override
  String settingsHwAccelDebugActive(String state) {
    return 'Debug: HW acceleration active: $state';
  }

  @override
  String settingsHwAccelDebugReason(String reason) {
    return 'Debug: $reason';
  }

  @override
  String get settingsLoopOff => 'Off';

  @override
  String get settingsLoopSingle => 'Single';

  @override
  String get settingsLoopAll => 'Loop';

  @override
  String get settingsWindowOpacity => 'Window opacity';

  @override
  String get settingsWindowOpacityBlurNote =>
      'With blur on (Windows), this adjusts UI translucency.';

  @override
  String settingsPercent(int percent) {
    return '$percent%';
  }

  @override
  String get settingsBackgroundBlur => 'Background blur';

  @override
  String get settingsBlurLinuxExperimentalOn =>
      'Experimental: requires compositor support';

  @override
  String get settingsBlurLinuxExperimentalOff =>
      'Not available on Linux unless experimental mode is enabled';

  @override
  String get settingsBlurNativeSubtitle =>
      'Applies native blur behind app content';

  @override
  String get settingsGlassStrength => 'Glass strength';

  @override
  String get settingsBlurIntensityWindows => 'Adjusts native blur intensity';

  @override
  String get settingsBlurIntensityMac =>
      'Adjusts native glass material intensity';

  @override
  String get settingsLinuxCompositorBlur =>
      'Experimental Linux compositor blur';

  @override
  String get settingsLinuxCompositorBlurSubtitle =>
      'Enables transparent window path for compositors that support blur (for example KDE blur rules)';

  @override
  String get settingsExperimentalEnable => 'Enable Experimental Features';

  @override
  String get settingsExperimentalUnstable =>
      'Experimental features are very unstable.';

  @override
  String get settingsRecentFiles => 'Recent files';

  @override
  String settingsRecentFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
      zero: '0 files',
    );
    return '$_temp0';
  }

  @override
  String get settingsUpdateChannel => 'Update channel';

  @override
  String get settingsUpdateChannelSubtitle =>
      'Auto matches your current version (stable or beta).';

  @override
  String get settingsUpdateChannelAuto => 'Auto';

  @override
  String get settingsUpdateChannelStable => 'Stable';

  @override
  String get settingsUpdateChannelBeta => 'Beta';

  @override
  String get settingsCheckForUpdates => 'Check for updates';

  @override
  String get settingsCheckNow => 'Check now';

  @override
  String get snackUpdateCheckFailed => 'Failed to check for updates.';

  @override
  String get snackUpdateLatest => 'You are on the latest version.';

  @override
  String get settingsKeyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsSupportProject => 'Support this project';

  @override
  String get settingsResetDefaults => 'Reset to defaults';

  @override
  String get settingsResetTitle => 'Reset Settings';

  @override
  String get settingsResetConfirm =>
      'This will reset all settings to their default values. Continue?';

  @override
  String get snackSettingsReset => 'Settings reset to defaults.';

  @override
  String get settingsOpenSourceLicenses => 'Open source licenses';

  @override
  String get settingsAboutDacx => 'About Dacx';

  @override
  String settingsAboutVersion(String version) {
    return 'Version $version • GPLv3';
  }

  @override
  String get settingsViewOnGitHub => 'View on GitHub';

  @override
  String settingsDebugModeTitle(String action) {
    return '$action Debug Mode?';
  }

  @override
  String get settingsDebugModeDisablePrompt =>
      'Do you want to disable hidden debug mode?';

  @override
  String get settingsDebugModeEnablePrompt =>
      'Do you want to enable hidden debug mode? (Debug mode uses more system resources and may cause performance degradation while enabled)';

  @override
  String get settingsActionEnable => 'Enable';

  @override
  String get settingsActionDisable => 'Disable';

  @override
  String get snackDebugModeEnabled => 'Debug mode enabled.';

  @override
  String get snackDebugModeDisabled => 'Debug mode disabled.';

  @override
  String get settingsShortcutOpenFile => 'Open File';

  @override
  String get settingsShortcutReopenLast => 'Reopen Last';

  @override
  String get settingsShortcutPlayPause => 'Play / Pause';

  @override
  String get settingsShortcutSeek => 'Seek ±5 seconds';

  @override
  String get settingsShortcutVolume => 'Volume ±5%';

  @override
  String get settingsShortcutMute => 'Mute / Unmute';

  @override
  String get settingsShortcutFullscreen => 'Toggle Fullscreen';

  @override
  String get settingsShortcutExitFullscreen => 'Exit Fullscreen';

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
  String snackPlaybackOperationFailed(String detail) {
    return 'Playback failed: $detail';
  }

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
  String get snackFileLoadPermissionDenied =>
      'Permission denied. Check file access and try again.';

  @override
  String get snackFileLoadFailed => 'Could not open file. Try another file.';

  @override
  String snackQueueTruncated(int max, int count) {
    return 'Queue is full ($max items). Skipped $count file(s).';
  }

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
  String get dialogMacInstallLocationTitle => 'Move Dacx to Applications';

  @override
  String get dialogMacInstallLocationMessage =>
      'Dacx is meant to run from /Applications/Dacx.app. Move it to the Applications folder for the best update experience.';

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
