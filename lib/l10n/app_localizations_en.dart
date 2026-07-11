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
      'Applies immediately to the player; a new file open picks up VideoController changes';

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
  String get settingsAudioWaveform => 'Audio spectrum visualizer';

  @override
  String get settingsAudioWaveformSubtitle =>
      'Real-time frequency bars while playing audio (Experimental)';

  @override
  String get settingsMultiAudioMixSubtitle =>
      'Play every audio track at once (Experimental; disables visualizer)';

  @override
  String get osdSpectrumUnavailable =>
      'Audio visualizer unavailable on this system';

  @override
  String get osdSpectrumDisabledForMix =>
      'Visualizer paused while mixing audio tracks';

  @override
  String get settingsSeekPreview => 'Seek thumbnails';

  @override
  String get settingsSeekPreviewSubtitle =>
      'Preview frames while scrubbing (uses extra memory)';

  @override
  String get settingsExperimentalStoredPrefsHint =>
      'Stored experimental options (visualizer, mix, Linux compositor blur) turn back on when you re-enable this';

  @override
  String get snackDropPathInaccessible =>
      'Some dropped files are outside the sandbox or inaccessible';

  @override
  String get snackScreenshotDirInaccessible =>
      'Screenshot folder is not writable';

  @override
  String get tooltipMute => 'Mute';

  @override
  String get tooltipUnmute => 'Unmute';

  @override
  String get tooltipCycleSpeed => 'Cycle playback speed';

  @override
  String get tooltipShuffle => 'Shuffle queue';

  @override
  String get queueReorderSemantic => 'Reorder';

  @override
  String get mediaInfoArtist => 'Artist';

  @override
  String get mediaInfoAlbum => 'Album';

  @override
  String get mediaInfoTitle => 'Title';

  @override
  String get audioPlaybackLabel => 'Audio playback';

  @override
  String get flatpakSandboxHint =>
      'Flatpak can only open files from Music, Videos, Downloads, and Pictures unless you use the file picker.';

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
      'With blur on, this adjusts UI translucency (native window opacity stays off so blur can work).';

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
  String get snackUpdateRateLimited =>
      'Update check rate-limited. Please try again in a few minutes.';

  @override
  String get snackUpdateLatest => 'You are on the latest version.';

  @override
  String get snackUpdateLatestBeta => 'You are on the latest beta.';

  @override
  String get snackUpdateNetworkError =>
      'Could not reach the update server. Check your connection.';

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
  String get snackInvalidStreamUrl => 'Enter a valid http:// or https:// URL.';

  @override
  String get snackNoSupportedMediaInFolder =>
      'No supported media found in that folder.';

  @override
  String snackFolderScanFailed(String detail) {
    return 'Could not scan folder. $detail';
  }

  @override
  String snackFolderScanSkipped(int count) {
    return 'Skipped $count unsupported or unreadable item(s).';
  }

  @override
  String snackQueueRemovedMissing(int count) {
    return 'Removed $count missing item(s).';
  }

  @override
  String get emptyStateMessage => 'Drop a file here or click Open';

  @override
  String get emptyStateFlatpakMessage =>
      'Use Open File or Open Folder — drag-and-drop only works for Music, Videos, Downloads, and Pictures';

  @override
  String get emptyStateTipReopenLast =>
      'Tip: Reopen Last (or Ctrl/Cmd+R) restores your previous file';

  @override
  String get actionDismissTip => 'Got it';

  @override
  String get dropOverlayHint => 'Drop media files to play or enqueue';

  @override
  String get keyCaptureWaiting => 'Waiting…';

  @override
  String get buttonOpenFile => 'Open File';

  @override
  String get buttonOpenFolder => 'Open Folder';

  @override
  String get buttonOpenPlaylist => 'Open Playlist';

  @override
  String get buttonSavePlaylist => 'Save Playlist';

  @override
  String get buttonOpenUrl => 'Open URL';

  @override
  String get snackPlaylistEmptyOrInvalid =>
      'Playlist is empty or could not be read';

  @override
  String get snackPlaylistImportFailed => 'Could not import playlist';

  @override
  String get snackPlaylistExportSaved => 'Playlist saved';

  @override
  String get snackPlaylistExportFailed => 'Could not save playlist';

  @override
  String get linuxUpdateGuidanceFlatpak =>
      'Install the new .flatpak from the release page (flatpak install --user …), or remove and reinstall the sideloaded package. Not on Flathub yet.';

  @override
  String get linuxUpdateGuidanceAppImage =>
      'Download the new AppImage from the release page and replace this file.';

  @override
  String get linuxUpdateGuidanceDebRpm =>
      'Install the new package (.deb / .rpm) from the release page.';

  @override
  String get linuxUpdateGuidancePortable =>
      'Download the latest Linux build from the release page and replace this install.';

  @override
  String get linuxUpdateGuidanceGeneric =>
      'Download the latest Linux build from the release page.';

  @override
  String get settingsLinuxUpdateHint =>
      'Linux self-update is not built in — use your package type’s update path.';

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
  String get dialogOpenUrlTitle => 'Open URL';

  @override
  String get dialogOpenUrlHint => 'https://example.com/stream.m3u8';

  @override
  String get dialogMediaInfoTitle => 'Media info';

  @override
  String get dialogMacInstallLocationTitle => 'Move Dacx to Applications';

  @override
  String get dialogMacInstallLocationMessage =>
      'Dacx is meant to run from /Applications/Dacx.app. Move it to the Applications folder for the best update experience.';

  @override
  String get mediaInfoSource => 'Source';

  @override
  String get mediaInfoType => 'Type';

  @override
  String get mediaInfoDuration => 'Duration';

  @override
  String get mediaInfoResolution => 'Resolution';

  @override
  String get mediaInfoAudioTracks => 'Audio tracks';

  @override
  String get mediaInfoSubtitleTracks => 'Subtitle tracks';

  @override
  String get mediaInfoChapters => 'Chapters';

  @override
  String get mediaInfoAudioSelection => 'Selected audio';

  @override
  String get mediaInfoSubtitleSelection => 'Selected subtitles';

  @override
  String get mediaInfoTypeUrlStream => 'URL stream';

  @override
  String get mediaInfoTypeAudioFile => 'Audio file';

  @override
  String get mediaInfoTypeVideoFile => 'Video file';

  @override
  String get mediaInfoUnknown => 'Unknown';

  @override
  String get menuTakeScreenshot => 'Take screenshot';

  @override
  String get menuLoadExternalAudio => 'Load external audio…';

  @override
  String get menuLoadExternalSubtitle => 'Load external subtitle…';

  @override
  String get menuMixAllAudioTracks => 'Mix all audio tracks';

  @override
  String get osdExternalAudioLoaded => 'External audio loaded';

  @override
  String get osdExternalAudioFailed => 'Could not load external audio';

  @override
  String get osdExternalSubtitleLoaded => 'External subtitle loaded';

  @override
  String get osdExternalSubtitleFailed => 'Could not load external subtitle';

  @override
  String get settingsScreenshotDir => 'Screenshot folder';

  @override
  String get settingsScreenshotDirSubtitle =>
      'Where video screenshots are saved';

  @override
  String get settingsScreenshotFormat => 'Screenshot format';

  @override
  String get settingsScreenshotFormatPng => 'PNG';

  @override
  String get settingsScreenshotFormatJpg => 'JPEG';

  @override
  String get settingsChooseScreenshotDir => 'Choose folder…';

  @override
  String get settingsResetScreenshotDir => 'Use default (Pictures/DACX)';

  @override
  String get menuSeekThumbnails => 'Seek thumbnails (uses more resources)';

  @override
  String get menuQueueEmpty => 'Queue (empty)';

  @override
  String menuQueueCount(int count) {
    return 'Queue ($count)';
  }

  @override
  String get menuAddFilesToQueue => 'Add files to queue…';

  @override
  String get menuShuffleQueue => 'Shuffle queue';

  @override
  String get menuMiniPlayer => 'Mini-player (always on top)';

  @override
  String osdAudioTrack(String label) {
    return 'Audio: $label';
  }

  @override
  String get osdSubtitlesOff => 'Subtitles: Off';

  @override
  String osdSubtitlesTrack(String label) {
    return 'Subtitles: $label';
  }

  @override
  String osdChapter(String title) {
    return 'Chapter: $title';
  }

  @override
  String get osdScreenshotFailed => 'Screenshot failed';

  @override
  String get osdScreenshotSaved => 'Screenshot saved';

  @override
  String get osdScreenshotSaveFailed => 'Screenshot save failed';

  @override
  String osdEqualizer(String state) {
    return 'Equalizer: $state';
  }

  @override
  String get osdStateOn => 'On';

  @override
  String get osdStateOff => 'Off';

  @override
  String get osdAudioMixOff => 'Audio mix off';

  @override
  String get osdAudioMixUnsupportedIds => 'Cannot mix: unsupported track ids';

  @override
  String osdAudioMixActive(int count) {
    return 'Mixing $count audio tracks';
  }

  @override
  String get osdAudioMixFailed => 'Could not enable audio mix';

  @override
  String osdResumedAt(String time) {
    return 'Resumed at $time';
  }

  @override
  String get osdNextInQueue => 'Next in queue';

  @override
  String get osdPreviousInQueue => 'Previous in queue';

  @override
  String get osdAddedToQueue => 'Added to queue';

  @override
  String osdAddedMultipleToQueue(int count) {
    return 'Added $count to queue';
  }

  @override
  String get osdMiniPlayerOff => 'Mini-player off';

  @override
  String get osdMiniPlayerOn => 'Mini-player on';

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
  String get actionOpen => 'Open';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionRemoveMissing => 'Remove missing';

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
  String get tooltipOpenFolder => 'Open folder';

  @override
  String get tooltipOpenUrl => 'Open URL (Ctrl/Cmd+U)';

  @override
  String get tooltipRecentFiles => 'Recent files';

  @override
  String get tooltipMediaInfo => 'Media info';

  @override
  String get tooltipPreviousTrack => 'Previous Track (Shift+P)';

  @override
  String get tooltipNextTrack => 'Next Track (Shift+N)';

  @override
  String get tooltipPlayQueue => 'Play Queue';

  @override
  String get tooltipExitMiniPlayer => 'Exit mini-player';

  @override
  String get semanticsSeekBar => 'Seek bar';

  @override
  String semanticsSeekBarValue(String position, String duration) {
    return '$position of $duration';
  }

  @override
  String semanticsAccentColor(String name) {
    return 'Accent color $name';
  }

  @override
  String updateDialogInstallingTitle(String version) {
    return 'Installing Dacx $version';
  }

  @override
  String get updateDialogDownloadingVerifying =>
      'Downloading and verifying in the update helper...';

  @override
  String get updateDialogVerifyingSignature => 'Verifying signature...';

  @override
  String updateDialogDownloadingProgress(String downloaded, String total) {
    return 'Downloading $downloaded / $total';
  }

  @override
  String get updateDialogDownloading => 'Downloading...';

  @override
  String get updateDialogWillClose => 'Dacx will close to apply the update.';

  @override
  String get updateDialogFailedTitle => 'Update failed';

  @override
  String get updateDialogOpenReleasePage => 'Open release page';

  @override
  String get updateActionInstall => 'Install';

  @override
  String get updateActionView => 'View';

  @override
  String snackUpdatedToVersion(String version) {
    return 'Updated to v$version';
  }

  @override
  String snackUpdateMayHaveFailed(String version) {
    return 'Update to v$version may have failed.';
  }

  @override
  String get debugLogTitle => 'Debug Log';

  @override
  String debugLogEntryCount(int count) {
    return '$count entries';
  }

  @override
  String get debugLogCopyButton => 'Copy Log';

  @override
  String get debugLogClearButton => 'Clear Log';

  @override
  String get debugLogEmpty => 'No debug events yet.';

  @override
  String get updateOutcomeUnsupportedPlatform =>
      'Self-update is not supported on this platform.';

  @override
  String updateOutcomeUnsupportedPlatformLinux(String guidance) {
    return 'Self-update is not available on Linux. $guidance';
  }

  @override
  String get updateOutcomeMissingAsset =>
      'The release does not include an installer for this platform.';

  @override
  String get updateOutcomeMissingChecksums =>
      'The release does not include a checksums file. Cannot verify download.';

  @override
  String get updateOutcomeMissingSignature =>
      'The release does not include a signed update manifest. Cannot verify update authenticity.';

  @override
  String get updateOutcomeDownloadFailed => 'Download failed.';

  @override
  String get updateOutcomeChecksumMismatch =>
      'Downloaded file failed checksum verification. Refusing to install.';

  @override
  String get updateOutcomeExtractionFailed =>
      'Could not extract the update package.';

  @override
  String get updateOutcomeSignatureInvalid =>
      'Downloaded app failed code-signature verification.';

  @override
  String get updateOutcomeBundleIdMismatch =>
      'Downloaded app has an unexpected bundle identifier. Refusing to install.';

  @override
  String get updateOutcomeVersionMismatch =>
      'Downloaded app version does not match the selected update. Refusing to install.';

  @override
  String get updateOutcomeTeamIdMismatch =>
      'Downloaded app is signed by an unexpected developer. Refusing to install.';

  @override
  String get updateOutcomeGatekeeperRejected =>
      'Self-update is not available on this build (missing signing configuration).';

  @override
  String get updateOutcomeSpawnFailed => 'Could not launch the installer.';

  @override
  String get updateOutcomeStarted => 'Update started.';

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

  @override
  String get shortcutOpenFile => 'Open file';

  @override
  String get shortcutReopenLast => 'Reopen last file';

  @override
  String get shortcutPlayPause => 'Play / pause';

  @override
  String get shortcutSeekForward => 'Seek forward';

  @override
  String get shortcutSeekBack => 'Seek backward';

  @override
  String get shortcutVolumeUp => 'Volume up';

  @override
  String get shortcutVolumeDown => 'Volume down';

  @override
  String get shortcutToggleMute => 'Toggle mute';

  @override
  String get shortcutToggleFullscreen => 'Toggle fullscreen';

  @override
  String get shortcutExitFullscreen => 'Exit fullscreen';

  @override
  String get shortcutChapterNext => 'Next chapter';

  @override
  String get shortcutChapterPrev => 'Previous chapter';

  @override
  String get shortcutScreenshot => 'Save screenshot';

  @override
  String get shortcutCycleAudioTrack => 'Cycle audio track';

  @override
  String get shortcutCycleSubtitleTrack => 'Cycle subtitle track';

  @override
  String get shortcutToggleSubtitle => 'Toggle subtitle visibility';

  @override
  String get shortcutToggleEqualizer => 'Toggle equalizer';

  @override
  String get shortcutPlaylistNext => 'Next in queue';

  @override
  String get shortcutPlaylistPrev => 'Previous in queue';

  @override
  String get shortcutToggleCompactMode => 'Toggle mini-player';

  @override
  String get shortcutNewWindow => 'Open new window';

  @override
  String get shortcutSpeedSlower => 'Decrease playback speed';

  @override
  String get shortcutSpeedFaster => 'Increase playback speed';

  @override
  String get shortcutCycleSpeed => 'Cycle playback speed';

  @override
  String get shortcutOpenUrl => 'Open URL';

  @override
  String get eqPresetFlat => 'Flat';

  @override
  String get eqPresetBassBoost => 'Bass Boost';

  @override
  String get eqPresetBassReduce => 'Bass Reduce';

  @override
  String get eqPresetTrebleBoost => 'Treble Boost';

  @override
  String get eqPresetVocal => 'Vocal';

  @override
  String get eqPresetRock => 'Rock';

  @override
  String get eqPresetElectronic => 'Electronic';

  @override
  String get eqPresetAcoustic => 'Acoustic';

  @override
  String get eqPresetLoudness => 'Loudness';

  @override
  String get eqPresetClassical => 'Classical';

  @override
  String get subtitleTrackOff => 'Off';

  @override
  String get keybindsTip =>
      'Tip: press F1 or ? at any time to reopen this dialog.';

  @override
  String get keybindsNone => '(none)';

  @override
  String get dismissBarrierLabel => 'Dismiss';

  @override
  String chapterFallbackLabel(int index) {
    return 'Chapter $index';
  }

  @override
  String trackFallbackLabel(String id) {
    return 'Track $id';
  }

  @override
  String get hwAccelStateYes => 'Yes';

  @override
  String get hwAccelStateNo => 'No';

  @override
  String get accentColorBlueGrey => 'Blue Grey';

  @override
  String get accentColorBlue => 'Blue';

  @override
  String get accentColorTeal => 'Teal';

  @override
  String get accentColorPurple => 'Purple';

  @override
  String get accentColorRed => 'Red';

  @override
  String get accentColorOrange => 'Orange';

  @override
  String get accentColorGreen => 'Green';

  @override
  String get accentColorPink => 'Pink';
}
