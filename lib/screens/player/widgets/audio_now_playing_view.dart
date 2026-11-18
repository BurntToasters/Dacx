import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../../models/playable_source.dart';
import '../../../theme/glass_decorations.dart';
import '../../../theme/window_visuals.dart';
import 'video_surface.dart';
import 'player_center_panel.dart';

class AudioNowPlayingView extends StatelessWidget {
  const AudioNowPlayingView({
    super.key,
    required this.showAlbumArt,
    required this.source,
    required this.mediaDisplayTitle,
    required this.mediaDisplayArtist,
    required this.videoController,
  });

  final bool showAlbumArt;
  final PlayableSource? source;
  final String? mediaDisplayTitle;
  final String? mediaDisplayArtist;
  final VideoController? videoController;

  @override
  Widget build(BuildContext context) {
    final source = this.source;
    final fileName = source == null
        ? ''
        : (source.isFile
              ? p.basenameWithoutExtension(source.value)
              : source.displayName);
    final title = (mediaDisplayTitle != null && mediaDisplayTitle!.isNotEmpty)
        ? mediaDisplayTitle!
        : fileName;
    final artist = mediaDisplayArtist;
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final shortestSideSize = shortestSide.clamp(220.0, 360.0).toDouble();
        final maxByHeight = (constraints.maxHeight - 260).clamp(170.0, 360.0);
        final albumArtSize = math.min(shortestSideSize, maxByHeight);

        return Semantics(
          label: AppLocalizations.of(context).audioPlaybackLabel,
          child: Center(
            child: PlayerCenterPanel(
              maxWidth: 700,
              children: [
                if (showAlbumArt)
                  AlbumArtSurface(
                    size: albumArtSize,
                    videoController: videoController,
                  )
                else
                  PlayerCenterIconSurface(
                    icon: Icons.album,
                    size: 54,
                    color: colorScheme.primary.withValues(alpha: 0.88),
                  ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (artist != null && artist.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    artist,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  AppLocalizations.of(context).labelAudioPlayback,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AlbumArtSurface extends StatelessWidget {
  const AlbumArtSurface({
    super.key,
    required this.size,
    required this.videoController,
  });

  final double size;
  final VideoController? videoController;

  @override
  Widget build(BuildContext context) {
    final visuals = context.windowVisuals;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visuals.panelBorderColor),
        boxShadow: [
          BoxShadow(
            color: visuals.shadowColor,
            blurRadius: visuals.isGlass ? 28 : 24,
            offset: Offset(0, visuals.isGlass ? 16 : 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: visuals.contentColor,
          child: VideoSurface(
            controller: videoController,
            fit: BoxFit.cover,
            fill: Colors.transparent,
          ),
        ),
      ),
    );
  }
}
