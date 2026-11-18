import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/playable_source.dart';
import '../../playback/file_picker_path.dart';
import '../../playback/m3u_playlist.dart';
import '../../playback/media_folder_scanner.dart';
import '../../playback/source_load_validation_policy.dart';
import '../../services/debug_log_service.dart';
import '../../services/playlist_service.dart';
import '../../services/settings_service.dart';
import 'player_file_pickers.dart';
import 'player_log.dart';
import 'source_load_coordinator.dart';

class PlayerOpenActions {
  PlayerOpenActions({
    required this.settings,
    required this.pickers,
    required this.sourceLoad,
    required this.playlist,
    required this.hasCurrentFile,
    required this.log,
    required this.isMounted,
    required this.isDisposed,
    required this.l10n,
    required this.showMessage,
    required this.promptForUrl,
    required this.confirmClearQueue,
  });

  final SettingsService settings;
  final PlayerFilePickers pickers;
  final SourceLoadCoordinator sourceLoad;
  final PlaylistService Function() playlist;
  final bool Function() hasCurrentFile;
  final PlayerDebugLog log;
  final bool Function() isMounted;
  final bool Function() isDisposed;
  final AppLocalizations Function() l10n;
  final void Function(String message) showMessage;
  final Future<String?> Function() promptForUrl;
  final Future<bool?> Function() confirmClearQueue;

  Future<void> openFile() async {
    log('file_picker_open_requested');
    try {
      final file = await pickers.pickMediaFile();

      if (file == null) {
        log('file_picker_cancelled');
        return;
      }
      final path = FilePickerPath.fromPlatformFilePath(file.path);
      if (path == null) {
        log('file_picker_invalid_path', severity: DebugSeverity.warn);
        if (isMounted()) {
          showMessage(l10n().snackCouldNotReadSelectedFile);
        }
        return;
      }

      await sourceLoad.captureBookmarkFor(path);
      await sourceLoad.openPathOrPlaylist(
        path,
        origin: SourceOrigin.fileDialog,
      );
    } on PlatformException catch (e) {
      log(
        'file_picker_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        final rawDetail = e.message?.trim();
        final detail = rawDetail == null || rawDetail.isEmpty
            ? e.code
            : rawDetail;
        showMessage(l10n().snackFilePickerFailed(detail));
      }
    } catch (e) {
      log(
        'file_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        showMessage(l10n().snackUnableToOpenFilePicker);
      }
    }
  }

  Future<void> openFolder({bool playNow = true}) async {
    log('folder_picker_open_requested');
    try {
      final folder = await pickers.pickFolder();
      if (folder == null || folder.trim().isEmpty) {
        log('folder_picker_cancelled');
        return;
      }
      if (!isMounted()) return;
      final strings = l10n();
      settings.lastOpenDirectory = folder.trim();
      await sourceLoad.captureBookmarkFor(folder.trim());
      final scan = await MediaFolderScanner.scan(
        folder,
        maxItems: PlaylistService.maxQueueItems,
      );
      if (!isMounted()) return;
      if (scan.paths.isEmpty) {
        if (isMounted()) {
          showMessage(strings.snackNoSupportedMediaInFolder);
        }
        return;
      }
      sourceLoad.enqueue(
        scan.paths,
        playNow: playNow,
        origin: SourceOrigin.folderDialog,
      );
      if (isMounted() && (scan.skipped > 0 || scan.truncated > 0)) {
        final parts = <String>[];
        if (scan.skipped > 0) {
          parts.add(strings.snackFolderScanSkipped(scan.skipped));
        }
        if (scan.truncated > 0) {
          parts.add(
            strings.snackQueueTruncated(
              PlaylistService.maxQueueItems,
              scan.truncated,
            ),
          );
        }
        showMessage(parts.join(' '));
      }
    } on PlatformException catch (e) {
      final detail = (e.message == null || e.message!.trim().isEmpty)
          ? e.code
          : e.message!.trim();
      log(
        'folder_picker_platform_exception',
        message: detail,
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        showMessage(l10n().snackFolderScanFailed(detail));
      }
    } catch (e) {
      log(
        'folder_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        showMessage(l10n().snackFolderScanFailed(e.toString()));
      }
    }
  }

  Future<void> openUrl() async {
    final strings = l10n();
    final url = await promptForUrl();
    if (!isMounted()) return;
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (!PlayableSource.isSupportedUrl(trimmed)) {
      if (isMounted()) {
        showMessage(strings.snackInvalidStreamUrl);
      }
      return;
    }
    await sourceLoad.loadSource(PlayableSource.url(trimmed));
  }

  Future<void> openPlaylistPicker({bool playNow = true}) async {
    log('playlist_picker_open_requested');
    try {
      final path = await pickers.pickPlaylistFile();
      if (path == null) return;
      await sourceLoad.captureBookmarkFor(path);
      final parent = p.dirname(path);
      if (parent.isNotEmpty && parent != path) {
        await sourceLoad.captureBookmarkFor(parent);
      }
      await sourceLoad.importPlaylistFile(
        path,
        playNow: playNow,
        origin: SourceOrigin.fileDialog,
      );
    } on PlatformException catch (e) {
      log(
        'playlist_picker_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        final rawDetail = e.message?.trim();
        final detail = rawDetail == null || rawDetail.isEmpty
            ? e.code
            : rawDetail;
        showMessage(l10n().snackFilePickerFailed(detail));
      }
    } catch (e) {
      log(
        'playlist_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        showMessage(l10n().snackUnableToOpenFilePicker);
      }
    }
  }

  Future<void> exportPlaylistQueue() async {
    if (playlist().isEmpty) return;
    log('playlist_export_requested', category: DebugLogCategory.ui);
    final strings = l10n();
    try {
      final content = M3uPlaylist.encode(playlist().items);
      final path = await pickers.pickPlaylistSavePath(
        dialogTitle: strings.buttonSavePlaylist,
        content: content,
      );
      if (path == null) return;
      pickers.rememberLastOpenDirectory(path);
      if (!isMounted()) return;
      showMessage(strings.snackPlaylistExportSaved);
      log(
        'playlist_exported',
        detailsBuilder: () => {
          'path': path,
          'count': '${playlist().items.length}',
        },
      );
    } on PlatformException catch (e) {
      log(
        'playlist_export_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        showMessage(strings.snackPlaylistExportFailed);
      }
    } catch (e) {
      log(
        'playlist_export_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        showMessage(strings.snackPlaylistExportFailed);
      }
    }
  }

  void loadRecentFile(String path) {
    unawaited(settings.pruneRecentFiles());
    log('recent_file_open_requested', detailsBuilder: () => {'path': path});
    final source = PlayableSource.fromStored(path);
    if (source == null) return;
    if (source.isUrl) {
      unawaited(sourceLoad.loadSource(source, origin: SourceOrigin.recents));
    } else {
      unawaited(
        sourceLoad.openRequestedFile(
          source.value,
          origin: SourceOrigin.recents,
        ),
      );
    }
  }

  Future<void> reopenLastFile() async {
    await settings.pruneRecentFiles();
    if (!isMounted() || isDisposed()) return;
    final recents = settings.recentFiles;
    if (recents.isEmpty) {
      log('reopen_last_fallback_open_picker', category: DebugLogCategory.ui);
      await openFile();
      return;
    }
    final lastPath = recents.first;
    log(
      'reopen_last_requested',
      category: DebugLogCategory.ui,
      detailsBuilder: () => {'path': lastPath},
    );
    final source = PlayableSource.fromStored(lastPath);
    if (source == null) return;
    if (source.isUrl) {
      await sourceLoad.loadSource(source, origin: SourceOrigin.recents);
    } else {
      await sourceLoad.openRequestedFile(
        source.value,
        origin: SourceOrigin.recents,
      );
    }
  }

  Future<void> clearQueueWithConfirmation() async {
    if (playlist().isEmpty) return;
    final confirmed = await confirmClearQueue();
    if (confirmed != true || !isMounted()) return;
    final wasPlaying = hasCurrentFile();
    playlist().clear();
    if (wasPlaying) {
      await sourceLoad.stopPlaybackAndResetUi();
    }
  }

  Future<void> removeMissingQueueItems() async {
    var currentRemoved = false;
    final removed = await playlist().removeMissingFiles(
      onCurrentRemoved: () => currentRemoved = true,
    );
    if (!isMounted()) return;
    if (playlist().isEmpty) {
      unawaited(sourceLoad.stopPlaybackAndResetUi());
    } else if (currentRemoved) {
      final next = playlist().current;
      if (next != null) {
        unawaited(
          sourceLoad.loadSource(
            next,
            syncPlaylist: false,
            origin: SourceOrigin.queue,
          ),
        );
      }
    }
    showMessage(l10n().snackQueueRemovedMissing(removed));
  }

  Future<void> removeQueueItem(int index) async {
    final wasCurrent = index == playlist().index;
    playlist().removeAt(index);
    if (!wasCurrent) return;
    final next = playlist().current;
    if (next == null) {
      await sourceLoad.stopPlaybackAndResetUi();
      return;
    }
    await sourceLoad.loadSource(
      next,
      syncPlaylist: false,
      origin: SourceOrigin.queue,
    );
  }

  Future<void> pickFilesToEnqueue() async {
    try {
      final paths = await pickers.pickFilesToEnqueue();
      if (paths.isEmpty) return;
      final sources = <PlayableSource>[];
      for (final path in paths) {
        await sourceLoad.captureBookmarkFor(path);
        if (M3uPlaylist.isPlaylistPath(path)) {
          try {
            sources.addAll(await M3uPlaylist.parseFile(path));
          } catch (e) {
            log(
              'enqueue_playlist_parse_failed',
              message: e.toString(),
              detailsBuilder: () => {'path': path},
              severity: DebugSeverity.warn,
            );
          }
        } else {
          sources.add(PlayableSource.file(path));
        }
      }
      pickers.rememberLastOpenDirectory(paths.first);
      if (sources.isEmpty) {
        if (isMounted()) {
          showMessage(l10n().snackPlaylistEmptyOrInvalid);
        }
        return;
      }
      sourceLoad.enqueueSources(sources, origin: SourceOrigin.fileDialog);
    } on PlatformException catch (e) {
      log(
        'enqueue_picker_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        final rawDetail = e.message?.trim();
        final detail = rawDetail == null || rawDetail.isEmpty
            ? e.code
            : rawDetail;
        showMessage(l10n().snackFilePickerFailed(detail));
      }
    } catch (e) {
      log(
        'enqueue_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (isMounted()) {
        showMessage(l10n().snackUnableToOpenFilePicker);
      }
    }
  }
}
