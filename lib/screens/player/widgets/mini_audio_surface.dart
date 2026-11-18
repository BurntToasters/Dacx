import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_center_panel.dart';
import 'video_surface.dart';

class MiniAudioSurface extends StatelessWidget {
  const MiniAudioSurface({
    super.key,
    required this.showAlbumArt,
    required this.videoController,
  });

  final bool showAlbumArt;
  final VideoController? videoController;

  @override
  Widget build(BuildContext context) {
    if (showAlbumArt) {
      return SizedBox.expand(
        key: const Key('mini-player-audio-art'),
        child: VideoSurface(
          controller: videoController,
          fit: BoxFit.cover,
          fill: Colors.black,
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = math.max(
          48.0,
          math.min(132.0, constraints.biggest.shortestSide * 0.5),
        );
        return Center(
          child: PlayerCenterIconSurface(
            key: const Key('mini-player-audio-icon'),
            icon: Icons.album,
            size: diameter * 0.4,
            diameter: diameter,
            color: colorScheme.primary.withValues(alpha: 0.88),
          ),
        );
      },
    );
  }
}
