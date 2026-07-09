import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application name shown in window title and About dialog.
  ///
  /// In en, this message translates to:
  /// **'Dacx'**
  String get appTitle;

  /// AppBar title for the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAutoPlay.
  ///
  /// In en, this message translates to:
  /// **'Auto-play on file open'**
  String get settingsAutoPlay;

  /// No description provided for @settingsResumePlayback.
  ///
  /// In en, this message translates to:
  /// **'Resume from last position'**
  String get settingsResumePlayback;

  /// No description provided for @settingsOnScreenDisplay.
  ///
  /// In en, this message translates to:
  /// **'On-screen display'**
  String get settingsOnScreenDisplay;

  /// No description provided for @settingsMediaSession.
  ///
  /// In en, this message translates to:
  /// **'System media keys / Now Playing'**
  String get settingsMediaSession;

  /// No description provided for @settingsAlwaysOnTop.
  ///
  /// In en, this message translates to:
  /// **'Always on top'**
  String get settingsAlwaysOnTop;

  /// No description provided for @settingsRememberWindow.
  ///
  /// In en, this message translates to:
  /// **'Remember window size & position'**
  String get settingsRememberWindow;

  /// No description provided for @settingsAllowMultipleWindows.
  ///
  /// In en, this message translates to:
  /// **'Allow multiple windows'**
  String get settingsAllowMultipleWindows;

  /// No description provided for @settingsCheckForUpdatesOnLaunch.
  ///
  /// In en, this message translates to:
  /// **'Check for updates on launch'**
  String get settingsCheckForUpdatesOnLaunch;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsAccentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get settingsAccentColor;

  /// No description provided for @settingsHardwareAcceleration.
  ///
  /// In en, this message translates to:
  /// **'Hardware acceleration'**
  String get settingsHardwareAcceleration;

  /// No description provided for @settingsHardwareAccelerationRestartNote.
  ///
  /// In en, this message translates to:
  /// **'Requires restart to take effect'**
  String get settingsHardwareAccelerationRestartNote;

  /// No description provided for @settingsPlaybackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get settingsPlaybackSpeed;

  /// No description provided for @settingsLoopMode.
  ///
  /// In en, this message translates to:
  /// **'Loop mode'**
  String get settingsLoopMode;

  /// No description provided for @settingsResumeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remember playback position for each file'**
  String get settingsResumeSubtitle;

  /// No description provided for @settingsOsdSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show title and time overlay during playback'**
  String get settingsOsdSubtitle;

  /// No description provided for @settingsMediaSessionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Publish playback to MPRIS / SMTC / Now Playing'**
  String get settingsMediaSessionSubtitle;

  /// No description provided for @settingsAudioWaveform.
  ///
  /// In en, this message translates to:
  /// **'Audio waveform visualizer'**
  String get settingsAudioWaveform;

  /// No description provided for @settingsAudioWaveformSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show an animated waveform above the playhead for audio tracks'**
  String get settingsAudioWaveformSubtitle;

  /// No description provided for @settingsAllowMultipleWindowsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When off (default), opening a file from your OS reuses the running Dacx window. Press Ctrl/Cmd+N to open an extra window on demand.'**
  String get settingsAllowMultipleWindowsSubtitle;

  /// No description provided for @settingsSectionPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get settingsSectionPlayback;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsSectionGeneral;

  /// No description provided for @settingsSectionExperimental.
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get settingsSectionExperimental;

  /// No description provided for @settingsSectionDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get settingsSectionDebug;

  /// No description provided for @settingsBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get settingsBack;

  /// No description provided for @settingsHwDecAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsHwDecAuto;

  /// No description provided for @settingsHwDecSafe.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get settingsHwDecSafe;

  /// No description provided for @settingsHwDecOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsHwDecOff;

  /// No description provided for @settingsHwAccelDebugActive.
  ///
  /// In en, this message translates to:
  /// **'Debug: HW acceleration active: {state}'**
  String settingsHwAccelDebugActive(String state);

  /// No description provided for @settingsHwAccelDebugReason.
  ///
  /// In en, this message translates to:
  /// **'Debug: {reason}'**
  String settingsHwAccelDebugReason(String reason);

  /// No description provided for @settingsLoopOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsLoopOff;

  /// No description provided for @settingsLoopSingle.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get settingsLoopSingle;

  /// No description provided for @settingsLoopAll.
  ///
  /// In en, this message translates to:
  /// **'Loop'**
  String get settingsLoopAll;

  /// No description provided for @settingsWindowOpacity.
  ///
  /// In en, this message translates to:
  /// **'Window opacity'**
  String get settingsWindowOpacity;

  /// No description provided for @settingsWindowOpacityBlurNote.
  ///
  /// In en, this message translates to:
  /// **'With blur on, this adjusts UI translucency (native window opacity stays off so blur can work).'**
  String get settingsWindowOpacityBlurNote;

  /// No description provided for @settingsPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String settingsPercent(int percent);

  /// No description provided for @settingsBackgroundBlur.
  ///
  /// In en, this message translates to:
  /// **'Background blur'**
  String get settingsBackgroundBlur;

  /// No description provided for @settingsBlurLinuxExperimentalOn.
  ///
  /// In en, this message translates to:
  /// **'Experimental: requires compositor support'**
  String get settingsBlurLinuxExperimentalOn;

  /// No description provided for @settingsBlurLinuxExperimentalOff.
  ///
  /// In en, this message translates to:
  /// **'Not available on Linux unless experimental mode is enabled'**
  String get settingsBlurLinuxExperimentalOff;

  /// No description provided for @settingsBlurNativeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies native blur behind app content'**
  String get settingsBlurNativeSubtitle;

  /// No description provided for @settingsGlassStrength.
  ///
  /// In en, this message translates to:
  /// **'Glass strength'**
  String get settingsGlassStrength;

  /// No description provided for @settingsBlurIntensityWindows.
  ///
  /// In en, this message translates to:
  /// **'Adjusts native blur intensity'**
  String get settingsBlurIntensityWindows;

  /// No description provided for @settingsBlurIntensityMac.
  ///
  /// In en, this message translates to:
  /// **'Adjusts native glass material intensity'**
  String get settingsBlurIntensityMac;

  /// No description provided for @settingsLinuxCompositorBlur.
  ///
  /// In en, this message translates to:
  /// **'Experimental Linux compositor blur'**
  String get settingsLinuxCompositorBlur;

  /// No description provided for @settingsLinuxCompositorBlurSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enables transparent window path for compositors that support blur (for example KDE blur rules)'**
  String get settingsLinuxCompositorBlurSubtitle;

  /// No description provided for @settingsExperimentalEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Experimental Features'**
  String get settingsExperimentalEnable;

  /// No description provided for @settingsExperimentalUnstable.
  ///
  /// In en, this message translates to:
  /// **'Experimental features are very unstable.'**
  String get settingsExperimentalUnstable;

  /// No description provided for @settingsRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'Recent files'**
  String get settingsRecentFiles;

  /// No description provided for @settingsRecentFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 files} =1{1 file} other{{count} files}}'**
  String settingsRecentFilesCount(int count);

  /// No description provided for @settingsUpdateChannel.
  ///
  /// In en, this message translates to:
  /// **'Update channel'**
  String get settingsUpdateChannel;

  /// No description provided for @settingsUpdateChannelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto matches your current version (stable or beta).'**
  String get settingsUpdateChannelSubtitle;

  /// No description provided for @settingsUpdateChannelAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsUpdateChannelAuto;

  /// No description provided for @settingsUpdateChannelStable.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get settingsUpdateChannelStable;

  /// No description provided for @settingsUpdateChannelBeta.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get settingsUpdateChannelBeta;

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckForUpdates;

  /// No description provided for @settingsCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get settingsCheckNow;

  /// No description provided for @snackUpdateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates.'**
  String get snackUpdateCheckFailed;

  /// No description provided for @snackUpdateLatest.
  ///
  /// In en, this message translates to:
  /// **'You are on the latest version.'**
  String get snackUpdateLatest;

  /// No description provided for @settingsKeyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get settingsKeyboardShortcuts;

  /// No description provided for @settingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsHelp;

  /// No description provided for @settingsSupportProject.
  ///
  /// In en, this message translates to:
  /// **'Support this project'**
  String get settingsSupportProject;

  /// No description provided for @settingsResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get settingsResetDefaults;

  /// No description provided for @settingsResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Settings'**
  String get settingsResetTitle;

  /// No description provided for @settingsResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will reset all settings to their default values. Continue?'**
  String get settingsResetConfirm;

  /// No description provided for @snackSettingsReset.
  ///
  /// In en, this message translates to:
  /// **'Settings reset to defaults.'**
  String get snackSettingsReset;

  /// No description provided for @settingsOpenSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get settingsOpenSourceLicenses;

  /// No description provided for @settingsAboutDacx.
  ///
  /// In en, this message translates to:
  /// **'About Dacx'**
  String get settingsAboutDacx;

  /// No description provided for @settingsAboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} • GPLv3'**
  String settingsAboutVersion(String version);

  /// No description provided for @settingsViewOnGitHub.
  ///
  /// In en, this message translates to:
  /// **'View on GitHub'**
  String get settingsViewOnGitHub;

  /// No description provided for @settingsDebugModeTitle.
  ///
  /// In en, this message translates to:
  /// **'{action} Debug Mode?'**
  String settingsDebugModeTitle(String action);

  /// No description provided for @settingsDebugModeDisablePrompt.
  ///
  /// In en, this message translates to:
  /// **'Do you want to disable hidden debug mode?'**
  String get settingsDebugModeDisablePrompt;

  /// No description provided for @settingsDebugModeEnablePrompt.
  ///
  /// In en, this message translates to:
  /// **'Do you want to enable hidden debug mode? (Debug mode uses more system resources and may cause performance degradation while enabled)'**
  String get settingsDebugModeEnablePrompt;

  /// No description provided for @settingsActionEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get settingsActionEnable;

  /// No description provided for @settingsActionDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get settingsActionDisable;

  /// No description provided for @snackDebugModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Debug mode enabled.'**
  String get snackDebugModeEnabled;

  /// No description provided for @snackDebugModeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Debug mode disabled.'**
  String get snackDebugModeDisabled;

  /// No description provided for @settingsShortcutOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get settingsShortcutOpenFile;

  /// No description provided for @settingsShortcutReopenLast.
  ///
  /// In en, this message translates to:
  /// **'Reopen Last'**
  String get settingsShortcutReopenLast;

  /// No description provided for @settingsShortcutPlayPause.
  ///
  /// In en, this message translates to:
  /// **'Play / Pause'**
  String get settingsShortcutPlayPause;

  /// No description provided for @settingsShortcutSeek.
  ///
  /// In en, this message translates to:
  /// **'Seek ±5 seconds'**
  String get settingsShortcutSeek;

  /// No description provided for @settingsShortcutVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume ±5%'**
  String get settingsShortcutVolume;

  /// No description provided for @settingsShortcutMute.
  ///
  /// In en, this message translates to:
  /// **'Mute / Unmute'**
  String get settingsShortcutMute;

  /// No description provided for @settingsShortcutFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Toggle Fullscreen'**
  String get settingsShortcutFullscreen;

  /// No description provided for @settingsShortcutExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen'**
  String get settingsShortcutExitFullscreen;

  /// No description provided for @snackCouldNotReadDroppedFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read dropped file path.'**
  String get snackCouldNotReadDroppedFile;

  /// No description provided for @snackCouldNotReadSelectedFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read selected file path.'**
  String get snackCouldNotReadSelectedFile;

  /// No description provided for @snackDebugLogCopied.
  ///
  /// In en, this message translates to:
  /// **'Redacted debug log copied to clipboard.'**
  String get snackDebugLogCopied;

  /// No description provided for @snackDebugLogCleared.
  ///
  /// In en, this message translates to:
  /// **'Debug log cleared.'**
  String get snackDebugLogCleared;

  /// No description provided for @snackUnableToOpenFilePicker.
  ///
  /// In en, this message translates to:
  /// **'Unable to open file picker.'**
  String get snackUnableToOpenFilePicker;

  /// Shown when a guarded player operation fails (seek, volume, etc.).
  ///
  /// In en, this message translates to:
  /// **'Playback failed: {detail}'**
  String snackPlaybackOperationFailed(String detail);

  /// Shown when the OS file picker raises an error.
  ///
  /// In en, this message translates to:
  /// **'File picker failed. {detail}'**
  String snackFilePickerFailed(String detail);

  /// No description provided for @snackInvalidFilePath.
  ///
  /// In en, this message translates to:
  /// **'Invalid file path. Try another file.'**
  String get snackInvalidFilePath;

  /// No description provided for @snackFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found. It may have moved or been deleted.'**
  String get snackFileNotFound;

  /// No description provided for @snackFileLoadPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied. Check file access and try again.'**
  String get snackFileLoadPermissionDenied;

  /// No description provided for @snackFileLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open file. Try another file.'**
  String get snackFileLoadFailed;

  /// No description provided for @snackQueueTruncated.
  ///
  /// In en, this message translates to:
  /// **'Queue is full ({max} items). Skipped {count} file(s).'**
  String snackQueueTruncated(int max, int count);

  /// No description provided for @snackUnsupportedFileType.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file type. Open an audio/video file.'**
  String get snackUnsupportedFileType;

  /// No description provided for @snackFullscreenRejected.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen change rejected by window manager.'**
  String get snackFullscreenRejected;

  /// No description provided for @snackUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Dacx v{version} is available'**
  String snackUpdateAvailable(String version);

  /// No description provided for @snackSkippedUnreadableFile.
  ///
  /// In en, this message translates to:
  /// **'Skipped 1 unreadable file.'**
  String get snackSkippedUnreadableFile;

  /// No description provided for @snackSkippedUnreadableFiles.
  ///
  /// In en, this message translates to:
  /// **'Skipped {count} unreadable files.'**
  String snackSkippedUnreadableFiles(int count);

  /// No description provided for @snackInvalidStreamUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid http:// or https:// URL.'**
  String get snackInvalidStreamUrl;

  /// No description provided for @snackNoSupportedMediaInFolder.
  ///
  /// In en, this message translates to:
  /// **'No supported media found in that folder.'**
  String get snackNoSupportedMediaInFolder;

  /// No description provided for @snackFolderScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not scan folder. {detail}'**
  String snackFolderScanFailed(String detail);

  /// No description provided for @snackFolderScanSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped {count} unsupported or unreadable item(s).'**
  String snackFolderScanSkipped(int count);

  /// No description provided for @snackQueueRemovedMissing.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} missing item(s).'**
  String snackQueueRemovedMissing(int count);

  /// No description provided for @emptyStateMessage.
  ///
  /// In en, this message translates to:
  /// **'Drop a file here or click Open'**
  String get emptyStateMessage;

  /// No description provided for @buttonOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get buttonOpenFile;

  /// No description provided for @buttonOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get buttonOpenFolder;

  /// No description provided for @buttonOpenUrl.
  ///
  /// In en, this message translates to:
  /// **'Open URL'**
  String get buttonOpenUrl;

  /// No description provided for @buttonReopenLast.
  ///
  /// In en, this message translates to:
  /// **'Reopen Last'**
  String get buttonReopenLast;

  /// No description provided for @dialogAudioTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio track'**
  String get dialogAudioTrackTitle;

  /// No description provided for @dialogSubtitleTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle track'**
  String get dialogSubtitleTrackTitle;

  /// No description provided for @dialogChaptersTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get dialogChaptersTitle;

  /// No description provided for @dialogEqualizerTitle.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get dialogEqualizerTitle;

  /// No description provided for @dialogEqualizerEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get dialogEqualizerEnable;

  /// No description provided for @dialogPlayQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Play queue'**
  String get dialogPlayQueueTitle;

  /// No description provided for @dialogPlayQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Queue is empty.'**
  String get dialogPlayQueueEmpty;

  /// No description provided for @dialogPlayQueueAddFiles.
  ///
  /// In en, this message translates to:
  /// **'Add files…'**
  String get dialogPlayQueueAddFiles;

  /// No description provided for @dialogKeyboardShortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get dialogKeyboardShortcutsTitle;

  /// No description provided for @dialogKeyCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Press a key combination'**
  String get dialogKeyCaptureTitle;

  /// No description provided for @dialogOpenUrlTitle.
  ///
  /// In en, this message translates to:
  /// **'Open URL'**
  String get dialogOpenUrlTitle;

  /// No description provided for @dialogOpenUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/stream.m3u8'**
  String get dialogOpenUrlHint;

  /// No description provided for @dialogMediaInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Media info'**
  String get dialogMediaInfoTitle;

  /// No description provided for @dialogMacInstallLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Move Dacx to Applications'**
  String get dialogMacInstallLocationTitle;

  /// No description provided for @dialogMacInstallLocationMessage.
  ///
  /// In en, this message translates to:
  /// **'Dacx is meant to run from /Applications/Dacx.app. Move it to the Applications folder for the best update experience.'**
  String get dialogMacInstallLocationMessage;

  /// No description provided for @mediaInfoSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get mediaInfoSource;

  /// No description provided for @mediaInfoType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get mediaInfoType;

  /// No description provided for @mediaInfoDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get mediaInfoDuration;

  /// No description provided for @mediaInfoResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get mediaInfoResolution;

  /// No description provided for @mediaInfoAudioTracks.
  ///
  /// In en, this message translates to:
  /// **'Audio tracks'**
  String get mediaInfoAudioTracks;

  /// No description provided for @mediaInfoSubtitleTracks.
  ///
  /// In en, this message translates to:
  /// **'Subtitle tracks'**
  String get mediaInfoSubtitleTracks;

  /// No description provided for @mediaInfoChapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get mediaInfoChapters;

  /// No description provided for @mediaInfoAudioSelection.
  ///
  /// In en, this message translates to:
  /// **'Selected audio'**
  String get mediaInfoAudioSelection;

  /// No description provided for @mediaInfoSubtitleSelection.
  ///
  /// In en, this message translates to:
  /// **'Selected subtitles'**
  String get mediaInfoSubtitleSelection;

  /// No description provided for @mediaInfoTypeUrlStream.
  ///
  /// In en, this message translates to:
  /// **'URL stream'**
  String get mediaInfoTypeUrlStream;

  /// No description provided for @mediaInfoTypeAudioFile.
  ///
  /// In en, this message translates to:
  /// **'Audio file'**
  String get mediaInfoTypeAudioFile;

  /// No description provided for @mediaInfoTypeVideoFile.
  ///
  /// In en, this message translates to:
  /// **'Video file'**
  String get mediaInfoTypeVideoFile;

  /// No description provided for @mediaInfoUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get mediaInfoUnknown;

  /// No description provided for @menuTakeScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Take screenshot'**
  String get menuTakeScreenshot;

  /// No description provided for @menuMixAllAudioTracks.
  ///
  /// In en, this message translates to:
  /// **'Mix all audio tracks'**
  String get menuMixAllAudioTracks;

  /// No description provided for @menuSeekThumbnailsBeta.
  ///
  /// In en, this message translates to:
  /// **'Seek thumbnails (beta: uses more resources)'**
  String get menuSeekThumbnailsBeta;

  /// No description provided for @menuQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Queue (empty)'**
  String get menuQueueEmpty;

  /// No description provided for @menuQueueCount.
  ///
  /// In en, this message translates to:
  /// **'Queue ({count})'**
  String menuQueueCount(int count);

  /// No description provided for @menuAddFilesToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add files to queue…'**
  String get menuAddFilesToQueue;

  /// No description provided for @menuShuffleQueue.
  ///
  /// In en, this message translates to:
  /// **'Shuffle queue'**
  String get menuShuffleQueue;

  /// No description provided for @menuMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Mini-player (always on top)'**
  String get menuMiniPlayer;

  /// No description provided for @osdAudioTrack.
  ///
  /// In en, this message translates to:
  /// **'Audio: {label}'**
  String osdAudioTrack(String label);

  /// No description provided for @osdSubtitlesOff.
  ///
  /// In en, this message translates to:
  /// **'Subtitles: Off'**
  String get osdSubtitlesOff;

  /// No description provided for @osdSubtitlesTrack.
  ///
  /// In en, this message translates to:
  /// **'Subtitles: {label}'**
  String osdSubtitlesTrack(String label);

  /// No description provided for @osdChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter: {title}'**
  String osdChapter(String title);

  /// No description provided for @osdScreenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot failed'**
  String get osdScreenshotFailed;

  /// No description provided for @osdScreenshotSaved.
  ///
  /// In en, this message translates to:
  /// **'Screenshot saved'**
  String get osdScreenshotSaved;

  /// No description provided for @osdScreenshotSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot save failed'**
  String get osdScreenshotSaveFailed;

  /// No description provided for @osdEqualizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer: {state}'**
  String osdEqualizer(String state);

  /// No description provided for @osdStateOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get osdStateOn;

  /// No description provided for @osdStateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get osdStateOff;

  /// No description provided for @osdAudioMixOff.
  ///
  /// In en, this message translates to:
  /// **'Audio mix off'**
  String get osdAudioMixOff;

  /// No description provided for @osdAudioMixUnsupportedIds.
  ///
  /// In en, this message translates to:
  /// **'Cannot mix: unsupported track ids'**
  String get osdAudioMixUnsupportedIds;

  /// No description provided for @osdAudioMixActive.
  ///
  /// In en, this message translates to:
  /// **'Mixing {count} audio tracks'**
  String osdAudioMixActive(int count);

  /// No description provided for @osdAudioMixFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not enable audio mix'**
  String get osdAudioMixFailed;

  /// No description provided for @osdResumedAt.
  ///
  /// In en, this message translates to:
  /// **'Resumed at {time}'**
  String osdResumedAt(String time);

  /// No description provided for @osdNextInQueue.
  ///
  /// In en, this message translates to:
  /// **'Next in queue'**
  String get osdNextInQueue;

  /// No description provided for @osdPreviousInQueue.
  ///
  /// In en, this message translates to:
  /// **'Previous in queue'**
  String get osdPreviousInQueue;

  /// No description provided for @osdAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get osdAddedToQueue;

  /// No description provided for @osdAddedMultipleToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added {count} to queue'**
  String osdAddedMultipleToQueue(int count);

  /// No description provided for @osdMiniPlayerOff.
  ///
  /// In en, this message translates to:
  /// **'Mini-player off'**
  String get osdMiniPlayerOff;

  /// No description provided for @osdMiniPlayerOn.
  ///
  /// In en, this message translates to:
  /// **'Mini-player on'**
  String get osdMiniPlayerOn;

  /// No description provided for @actionReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get actionReset;

  /// No description provided for @actionResetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset all'**
  String get actionResetAll;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionRemoveMissing.
  ///
  /// In en, this message translates to:
  /// **'Remove missing'**
  String get actionRemoveMissing;

  /// No description provided for @actionSetNewBinding.
  ///
  /// In en, this message translates to:
  /// **'Set new binding'**
  String get actionSetNewBinding;

  /// No description provided for @actionResetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get actionResetToDefault;

  /// No description provided for @labelAudioPlayback.
  ///
  /// In en, this message translates to:
  /// **'Audio playback'**
  String get labelAudioPlayback;

  /// No description provided for @tooltipReopenLast.
  ///
  /// In en, this message translates to:
  /// **'Reopen last file (Ctrl/Cmd+R)'**
  String get tooltipReopenLast;

  /// No description provided for @tooltipStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get tooltipStop;

  /// No description provided for @tooltipMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get tooltipMore;

  /// No description provided for @tooltipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// No description provided for @tooltipOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get tooltipOpenFile;

  /// No description provided for @tooltipOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get tooltipOpenFolder;

  /// No description provided for @tooltipOpenUrl.
  ///
  /// In en, this message translates to:
  /// **'Open URL'**
  String get tooltipOpenUrl;

  /// No description provided for @tooltipRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'Recent files'**
  String get tooltipRecentFiles;

  /// No description provided for @tooltipMediaInfo.
  ///
  /// In en, this message translates to:
  /// **'Media info'**
  String get tooltipMediaInfo;

  /// No description provided for @tooltipPreviousTrack.
  ///
  /// In en, this message translates to:
  /// **'Previous Track (PageUp)'**
  String get tooltipPreviousTrack;

  /// No description provided for @tooltipNextTrack.
  ///
  /// In en, this message translates to:
  /// **'Next Track (PageDown)'**
  String get tooltipNextTrack;

  /// No description provided for @tooltipPlayQueue.
  ///
  /// In en, this message translates to:
  /// **'Play Queue'**
  String get tooltipPlayQueue;

  /// No description provided for @tooltipExitMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Exit mini-player'**
  String get tooltipExitMiniPlayer;

  /// No description provided for @semanticsSeekBar.
  ///
  /// In en, this message translates to:
  /// **'Seek bar'**
  String get semanticsSeekBar;

  /// No description provided for @semanticsSeekBarValue.
  ///
  /// In en, this message translates to:
  /// **'{position} of {duration}'**
  String semanticsSeekBarValue(String position, String duration);

  /// No description provided for @semanticsAccentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color {name}'**
  String semanticsAccentColor(String name);

  /// No description provided for @updateDialogInstallingTitle.
  ///
  /// In en, this message translates to:
  /// **'Installing Dacx {version}'**
  String updateDialogInstallingTitle(String version);

  /// No description provided for @updateDialogDownloadingVerifying.
  ///
  /// In en, this message translates to:
  /// **'Downloading and verifying in the update helper...'**
  String get updateDialogDownloadingVerifying;

  /// No description provided for @updateDialogVerifyingSignature.
  ///
  /// In en, this message translates to:
  /// **'Verifying signature...'**
  String get updateDialogVerifyingSignature;

  /// No description provided for @updateDialogDownloadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading {downloaded} / {total}'**
  String updateDialogDownloadingProgress(String downloaded, String total);

  /// No description provided for @updateDialogDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get updateDialogDownloading;

  /// No description provided for @updateDialogWillClose.
  ///
  /// In en, this message translates to:
  /// **'Dacx will close to apply the update.'**
  String get updateDialogWillClose;

  /// No description provided for @updateDialogFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get updateDialogFailedTitle;

  /// No description provided for @updateDialogOpenReleasePage.
  ///
  /// In en, this message translates to:
  /// **'Open release page'**
  String get updateDialogOpenReleasePage;

  /// No description provided for @updateActionInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get updateActionInstall;

  /// No description provided for @updateActionView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get updateActionView;

  /// No description provided for @snackUpdatedToVersion.
  ///
  /// In en, this message translates to:
  /// **'Updated to v{version}'**
  String snackUpdatedToVersion(String version);

  /// No description provided for @snackUpdateMayHaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Update to v{version} may have failed.'**
  String snackUpdateMayHaveFailed(String version);

  /// No description provided for @debugLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug Log'**
  String get debugLogTitle;

  /// No description provided for @debugLogEntryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String debugLogEntryCount(int count);

  /// No description provided for @debugLogCopyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy Log'**
  String get debugLogCopyButton;

  /// No description provided for @debugLogClearButton.
  ///
  /// In en, this message translates to:
  /// **'Clear Log'**
  String get debugLogClearButton;

  /// No description provided for @debugLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No debug events yet.'**
  String get debugLogEmpty;

  /// No description provided for @updateOutcomeUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Self-update is not supported on this platform.'**
  String get updateOutcomeUnsupportedPlatform;

  /// No description provided for @updateOutcomeMissingAsset.
  ///
  /// In en, this message translates to:
  /// **'The release does not include an installer for this platform.'**
  String get updateOutcomeMissingAsset;

  /// No description provided for @updateOutcomeMissingChecksums.
  ///
  /// In en, this message translates to:
  /// **'The release does not include a checksums file. Cannot verify download.'**
  String get updateOutcomeMissingChecksums;

  /// No description provided for @updateOutcomeMissingSignature.
  ///
  /// In en, this message translates to:
  /// **'The release does not include a signed update manifest. Cannot verify update authenticity.'**
  String get updateOutcomeMissingSignature;

  /// No description provided for @updateOutcomeDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed.'**
  String get updateOutcomeDownloadFailed;

  /// No description provided for @updateOutcomeChecksumMismatch.
  ///
  /// In en, this message translates to:
  /// **'Downloaded file failed checksum verification. Refusing to install.'**
  String get updateOutcomeChecksumMismatch;

  /// No description provided for @updateOutcomeExtractionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not extract the update package.'**
  String get updateOutcomeExtractionFailed;

  /// No description provided for @updateOutcomeSignatureInvalid.
  ///
  /// In en, this message translates to:
  /// **'Downloaded app failed code-signature verification.'**
  String get updateOutcomeSignatureInvalid;

  /// No description provided for @updateOutcomeBundleIdMismatch.
  ///
  /// In en, this message translates to:
  /// **'Downloaded app has an unexpected bundle identifier. Refusing to install.'**
  String get updateOutcomeBundleIdMismatch;

  /// No description provided for @updateOutcomeVersionMismatch.
  ///
  /// In en, this message translates to:
  /// **'Downloaded app version does not match the selected update. Refusing to install.'**
  String get updateOutcomeVersionMismatch;

  /// No description provided for @updateOutcomeTeamIdMismatch.
  ///
  /// In en, this message translates to:
  /// **'Downloaded app is signed by an unexpected developer. Refusing to install.'**
  String get updateOutcomeTeamIdMismatch;

  /// No description provided for @updateOutcomeGatekeeperRejected.
  ///
  /// In en, this message translates to:
  /// **'Self-update is not available on this build (missing signing configuration).'**
  String get updateOutcomeGatekeeperRejected;

  /// No description provided for @updateOutcomeSpawnFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not launch the installer.'**
  String get updateOutcomeSpawnFailed;

  /// No description provided for @updateOutcomeStarted.
  ///
  /// In en, this message translates to:
  /// **'Update started.'**
  String get updateOutcomeStarted;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize window'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize window'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore window'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get windowClose;

  /// No description provided for @actionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get actionPlay;

  /// No description provided for @actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// No description provided for @loopOff.
  ///
  /// In en, this message translates to:
  /// **'Loop: Off'**
  String get loopOff;

  /// No description provided for @loopAll.
  ///
  /// In en, this message translates to:
  /// **'Loop: All'**
  String get loopAll;

  /// No description provided for @loopSingle.
  ///
  /// In en, this message translates to:
  /// **'Loop: Single'**
  String get loopSingle;

  /// No description provided for @volumeLabel.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volumeLabel;

  /// No description provided for @volumeMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get volumeMuted;

  /// No description provided for @volumePercent.
  ///
  /// In en, this message translates to:
  /// **'Volume {pct} percent'**
  String volumePercent(int pct);

  /// No description provided for @shortcutOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get shortcutOpenFile;

  /// No description provided for @shortcutReopenLast.
  ///
  /// In en, this message translates to:
  /// **'Reopen last file'**
  String get shortcutReopenLast;

  /// No description provided for @shortcutPlayPause.
  ///
  /// In en, this message translates to:
  /// **'Play / pause'**
  String get shortcutPlayPause;

  /// No description provided for @shortcutSeekForward.
  ///
  /// In en, this message translates to:
  /// **'Seek forward'**
  String get shortcutSeekForward;

  /// No description provided for @shortcutSeekBack.
  ///
  /// In en, this message translates to:
  /// **'Seek backward'**
  String get shortcutSeekBack;

  /// No description provided for @shortcutVolumeUp.
  ///
  /// In en, this message translates to:
  /// **'Volume up'**
  String get shortcutVolumeUp;

  /// No description provided for @shortcutVolumeDown.
  ///
  /// In en, this message translates to:
  /// **'Volume down'**
  String get shortcutVolumeDown;

  /// No description provided for @shortcutToggleMute.
  ///
  /// In en, this message translates to:
  /// **'Toggle mute'**
  String get shortcutToggleMute;

  /// No description provided for @shortcutToggleFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Toggle fullscreen'**
  String get shortcutToggleFullscreen;

  /// No description provided for @shortcutExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get shortcutExitFullscreen;

  /// No description provided for @shortcutChapterNext.
  ///
  /// In en, this message translates to:
  /// **'Next chapter'**
  String get shortcutChapterNext;

  /// No description provided for @shortcutChapterPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous chapter'**
  String get shortcutChapterPrev;

  /// No description provided for @shortcutScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Save screenshot'**
  String get shortcutScreenshot;

  /// No description provided for @shortcutCycleAudioTrack.
  ///
  /// In en, this message translates to:
  /// **'Cycle audio track'**
  String get shortcutCycleAudioTrack;

  /// No description provided for @shortcutCycleSubtitleTrack.
  ///
  /// In en, this message translates to:
  /// **'Cycle subtitle track'**
  String get shortcutCycleSubtitleTrack;

  /// No description provided for @shortcutToggleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Toggle subtitle visibility'**
  String get shortcutToggleSubtitle;

  /// No description provided for @shortcutToggleEqualizer.
  ///
  /// In en, this message translates to:
  /// **'Toggle equalizer'**
  String get shortcutToggleEqualizer;

  /// No description provided for @shortcutPlaylistNext.
  ///
  /// In en, this message translates to:
  /// **'Next in queue'**
  String get shortcutPlaylistNext;

  /// No description provided for @shortcutPlaylistPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous in queue'**
  String get shortcutPlaylistPrev;

  /// No description provided for @shortcutToggleCompactMode.
  ///
  /// In en, this message translates to:
  /// **'Toggle mini-player'**
  String get shortcutToggleCompactMode;

  /// No description provided for @shortcutNewWindow.
  ///
  /// In en, this message translates to:
  /// **'Open new window'**
  String get shortcutNewWindow;

  /// No description provided for @eqPresetFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get eqPresetFlat;

  /// No description provided for @eqPresetBassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass Boost'**
  String get eqPresetBassBoost;

  /// No description provided for @eqPresetBassReduce.
  ///
  /// In en, this message translates to:
  /// **'Bass Reduce'**
  String get eqPresetBassReduce;

  /// No description provided for @eqPresetTrebleBoost.
  ///
  /// In en, this message translates to:
  /// **'Treble Boost'**
  String get eqPresetTrebleBoost;

  /// No description provided for @eqPresetVocal.
  ///
  /// In en, this message translates to:
  /// **'Vocal'**
  String get eqPresetVocal;

  /// No description provided for @eqPresetRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get eqPresetRock;

  /// No description provided for @eqPresetElectronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic'**
  String get eqPresetElectronic;

  /// No description provided for @eqPresetAcoustic.
  ///
  /// In en, this message translates to:
  /// **'Acoustic'**
  String get eqPresetAcoustic;

  /// No description provided for @eqPresetLoudness.
  ///
  /// In en, this message translates to:
  /// **'Loudness'**
  String get eqPresetLoudness;

  /// No description provided for @eqPresetClassical.
  ///
  /// In en, this message translates to:
  /// **'Classical'**
  String get eqPresetClassical;

  /// No description provided for @subtitleTrackOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get subtitleTrackOff;

  /// No description provided for @keybindsTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: press F1 or ? at any time to reopen this dialog.'**
  String get keybindsTip;

  /// No description provided for @keybindsNone.
  ///
  /// In en, this message translates to:
  /// **'(none)'**
  String get keybindsNone;

  /// No description provided for @dismissBarrierLabel.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismissBarrierLabel;

  /// No description provided for @chapterFallbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Chapter {index}'**
  String chapterFallbackLabel(int index);

  /// No description provided for @trackFallbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Track {id}'**
  String trackFallbackLabel(String id);

  /// No description provided for @hwAccelStateYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get hwAccelStateYes;

  /// No description provided for @hwAccelStateNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get hwAccelStateNo;

  /// No description provided for @accentColorBlueGrey.
  ///
  /// In en, this message translates to:
  /// **'Blue Grey'**
  String get accentColorBlueGrey;

  /// No description provided for @accentColorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get accentColorBlue;

  /// No description provided for @accentColorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get accentColorTeal;

  /// No description provided for @accentColorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get accentColorPurple;

  /// No description provided for @accentColorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get accentColorRed;

  /// No description provided for @accentColorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get accentColorOrange;

  /// No description provided for @accentColorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get accentColorGreen;

  /// No description provided for @accentColorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get accentColorPink;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
