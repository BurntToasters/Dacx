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
