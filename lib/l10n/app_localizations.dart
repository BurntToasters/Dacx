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

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates on launch'**
  String get settingsCheckForUpdates;

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

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

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

  /// No description provided for @tooltipRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'Recent files'**
  String get tooltipRecentFiles;

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
