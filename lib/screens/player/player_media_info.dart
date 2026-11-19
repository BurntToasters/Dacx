import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/playable_source.dart';
import '../../playback/player_controller.dart';
import '../../services/player_service.dart';
import '../../widgets/dialog_sizing.dart';
import '../../widgets/media_info_dialog.dart';
import 'media_session_coordinator.dart';
import 'track_chapter_controller.dart';

class PlayerMediaInfoPresenter {
  PlayerMediaInfoPresenter({
    required this.player,
    required this.playerService,
    required this.media,
    required this.trackController,
  });

  final PlayerController player;
  final IPlayerService playerService;
  final MediaSessionCoordinator media;
  final TrackChapterController trackController;

  Future<double?> currentVideoAspectRatio() async {
    if (player.isAudioFile || !player.hasVideoOutput) return null;
    final width = double.tryParse(
      await playerService.getProperty('dwidth') ?? '',
    );
    final height = double.tryParse(
      await playerService.getProperty('dheight') ?? '',
    );
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  Future<void> show(BuildContext context) async {
    final source = player.currentSource;
    if (source == null) return;
    if (player.chapters.isEmpty) {
      await trackController.refreshChapters();
    }
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final width = await playerService.getProperty('width');
    final height = await playerService.getProperty('height');
    String? metaTitle;
    String? metaArtist;
    String? metaAlbum;
    try {
      metaTitle = await playerService.getProperty('metadata/by-key/title');
      metaArtist = await playerService.getProperty('metadata/by-key/artist');
      metaAlbum = await playerService.getProperty('metadata/by-key/album');
    } catch (_) {
      // Best-effort tags; fall back to cached display fields / unknown.
    }
    if (!context.mounted) return;
    final tracks = player.currentTracks;
    final audioTracks =
        tracks?.audio.where((t) => t.id != 'auto' && t.id != 'no').length ?? 0;
    final subtitleTracks =
        tracks?.subtitle.where((t) => t.id != 'auto' && t.id != 'no').length ??
        0;
    final audioSelection = player.currentTrackSelection?.audio;
    final subtitleSelection = player.currentTrackSelection?.subtitle;
    final resolution =
        (width != null &&
            height != null &&
            width.trim().isNotEmpty &&
            height.trim().isNotEmpty)
        ? '${width.trim()} × ${height.trim()}'
        : l10n.mediaInfoUnknown;
    final type = source.isUrl
        ? l10n.mediaInfoTypeUrlStream
        : (player.isAudioFile
              ? l10n.mediaInfoTypeAudioFile
              : l10n.mediaInfoTypeVideoFile);
    final titleValue = () {
      final fromMeta = metaTitle?.trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
      final cached = media.displayTitle?.trim();
      if (cached != null && cached.isNotEmpty) return cached;
      return source.displayName;
    }();
    final artistValue = () {
      final fromMeta = metaArtist?.trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
      final cached = media.displayArtist?.trim();
      if (cached != null && cached.isNotEmpty) return cached;
      return l10n.mediaInfoUnknown;
    }();
    final albumValue = () {
      final fromMeta = metaAlbum?.trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
      return l10n.mediaInfoUnknown;
    }();

    await showDialog<void>(
      context: context,
      builder: (ctx) => MediaInfoDialog(
        width: dialogWidth(ctx, 520),
        fields: [
          MediaInfoField(label: l10n.mediaInfoTitle, value: titleValue),
          MediaInfoField(label: l10n.mediaInfoArtist, value: artistValue),
          MediaInfoField(label: l10n.mediaInfoAlbum, value: albumValue),
          MediaInfoField(
            label: l10n.mediaInfoSource,
            value: source.isUrl
                ? PlayableSource.displaySafeUrl(source.value)
                : source.value,
          ),
          MediaInfoField(label: l10n.mediaInfoType, value: type),
          MediaInfoField(
            label: l10n.mediaInfoDuration,
            value: player.duration.inMilliseconds > 0
                ? PlayerController.formatDuration(player.duration)
                : l10n.mediaInfoUnknown,
          ),
          MediaInfoField(label: l10n.mediaInfoResolution, value: resolution),
          MediaInfoField(
            label: l10n.mediaInfoAudioTracks,
            value: '$audioTracks',
          ),
          MediaInfoField(
            label: l10n.mediaInfoSubtitleTracks,
            value: '$subtitleTracks',
          ),
          MediaInfoField(
            label: l10n.mediaInfoChapters,
            value: '${player.chapters.length}',
          ),
          MediaInfoField(
            label: l10n.mediaInfoAudioSelection,
            value: audioSelection == null
                ? l10n.mediaInfoUnknown
                : trackController.trackLabel(
                    audioSelection.title,
                    audioSelection.language,
                    audioSelection.id,
                  ),
          ),
          MediaInfoField(
            label: l10n.mediaInfoSubtitleSelection,
            value: subtitleSelection == null || subtitleSelection.id == 'no'
                ? l10n.mediaInfoUnknown
                : trackController.trackLabel(
                    subtitleSelection.title,
                    subtitleSelection.language,
                    subtitleSelection.id,
                  ),
          ),
        ],
      ),
    );
  }
}
