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

enum _AudioLayout { stacked, side, text }

_AudioLayout _layoutFor(Size size) {
  if (size.height >= 440 && size.width >= 220) return _AudioLayout.stacked;
  if (size.height >= 190 && size.width >= 360) return _AudioLayout.side;
  return _AudioLayout.text;
}

class AudioNowPlayingView extends StatelessWidget {
  const AudioNowPlayingView({
    super.key,
    required this.showAlbumArt,
    required this.source,
    required this.mediaDisplayTitle,
    required this.mediaDisplayArtist,
    required this.videoController,
    this.album,
  });

  final bool showAlbumArt;
  final PlayableSource? source;
  final String? mediaDisplayTitle;
  final String? mediaDisplayArtist;
  final VideoController? videoController;
  final String? album;

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
    final albumName = album;
    final caption = (albumName != null && albumName.isNotEmpty)
        ? albumName
        : AppLocalizations.of(context).labelAudioPlayback;

    return Semantics(
      label: AppLocalizations.of(context).audioPlaybackLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final layout = _layoutFor(size);
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: _panel(
                  context,
                  layout,
                  size,
                  title: title,
                  artist: artist,
                  caption: caption,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _panel(
    BuildContext context,
    _AudioLayout layout,
    Size size, {
    required String title,
    required String? artist,
    required String caption,
  }) {
    switch (layout) {
      case _AudioLayout.stacked:
        final inner = math.min(size.width - 48, 700.0) - 64;
        final artSize = math.min(360.0, math.min(size.height - 290, inner));
        return PlayerCenterPanel(
          maxWidth: 700,
          children: [
            Column(
              key: const Key('audio-layout-stacked'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _art(context, artSize, math.min(132.0, inner)),
                const SizedBox(height: 24),
                _texts(
                  context,
                  layout,
                  title: title,
                  artist: artist,
                  caption: caption,
                ),
              ],
            ),
          ],
        );
      case _AudioLayout.side:
        final inner = math.min(size.width - 32, 700.0) - 40;
        final artSize = math.min(
          200.0,
          math.min(size.height - 72, inner * 0.4),
        );
        return PlayerCenterPanel(
          maxWidth: 700,
          outerPadding: const EdgeInsets.all(16),
          panelPadding: const EdgeInsets.all(20),
          children: [
            Row(
              key: const Key('audio-layout-side'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _art(context, artSize, math.min(132.0, artSize)),
                const SizedBox(width: 20),
                Expanded(
                  child: _texts(
                    context,
                    layout,
                    title: title,
                    artist: artist,
                    caption: caption,
                  ),
                ),
              ],
            ),
          ],
        );
      case _AudioLayout.text:
        return PlayerCenterPanel(
          maxWidth: 700,
          outerPadding: const EdgeInsets.all(8),
          panelPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          children: [
            KeyedSubtree(
              key: const Key('audio-layout-text'),
              child: _texts(
                context,
                layout,
                title: title,
                artist: artist,
                caption: caption,
              ),
            ),
          ],
        );
    }
  }

  Widget _art(BuildContext context, double artSize, double iconDiameter) {
    if (showAlbumArt) {
      return AlbumArtSurface(
        key: const Key('audio-album-art'),
        size: artSize,
        videoController: videoController,
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return PlayerCenterIconSurface(
      key: const Key('audio-icon-art'),
      icon: Icons.album,
      size: 54,
      diameter: iconDiameter,
      color: colorScheme.primary.withValues(alpha: 0.88),
    );
  }

  Widget _texts(
    BuildContext context,
    _AudioLayout layout, {
    required String title,
    required String? artist,
    required String caption,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final compact = layout == _AudioLayout.text;
    final side = layout == _AudioLayout.side;
    final align = side ? TextAlign.start : TextAlign.center;
    final titleStyle = compact
        ? theme.textTheme.titleMedium
        : (side ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: side
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side ? 0 : 8),
          child: Text(
            title,
            key: const Key('audio-title'),
            style: titleStyle?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.88),
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            textAlign: align,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (artist != null && artist.isNotEmpty) ...[
          SizedBox(height: compact ? 4 : 6),
          Text(
            artist,
            key: const Key('audio-artist'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
            ),
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        SizedBox(height: compact ? 4 : 10),
        Text(
          caption,
          key: const Key('audio-caption'),
          style:
              (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    height: 1.2,
                  ),
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
