import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../playback/player_controller.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/compact_exit_button.dart';
import '../../../widgets/osd_overlay.dart';
import 'audio_now_playing_view.dart';
import 'player_empty_state.dart';
import 'video_surface.dart';

const _contentSwitchDuration = Duration(milliseconds: 240);

class MediaSurface extends StatelessWidget {
  const MediaSurface({
    super.key,
    required this.player,
    required this.settings,
    required this.hasMedia,
    required this.videoController,
    required this.mediaDisplayTitle,
    required this.mediaDisplayArtist,
    required this.compactMode,
    required this.isFullscreen,
    required this.fullscreenChromeVisible,
    required this.onTap,
    required this.onDoubleTap,
    required this.onHover,
    required this.onScrollVolume,
    required this.onExitCompactMode,
    required this.onDismissEmptyStateTip,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenPlaylist,
    required this.onOpenUrl,
    required this.onReopenLast,
  });

  final PlayerController player;
  final SettingsService settings;
  final bool hasMedia;
  final VideoController? videoController;
  final String? mediaDisplayTitle;
  final String? mediaDisplayArtist;
  final bool compactMode;
  final bool isFullscreen;
  final bool fullscreenChromeVisible;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onHover;
  final void Function(double scrollDeltaY, Duration timeStamp) onScrollVolume;
  final VoidCallback onExitCompactMode;
  final VoidCallback onDismissEmptyStateTip;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenPlaylist;
  final VoidCallback onOpenUrl;
  final VoidCallback onReopenLast;

  Widget _buildContent() {
    if (!hasMedia) {
      return KeyedSubtree(
        key: const ValueKey('media-drop-zone'),
        child: PlayerEmptyState(
          tipDismissed: settings.emptyStateTipDismissed,
          onDismissTip: onDismissEmptyStateTip,
          onOpenFile: onOpenFile,
          onOpenFolder: onOpenFolder,
          onOpenPlaylist: onOpenPlaylist,
          onOpenUrl: onOpenUrl,
          onReopenLast: onReopenLast,
        ),
      );
    }

    if (player.isAudioFile) {
      final showAlbumArt = player.hasAlbumArtTrack;
      return KeyedSubtree(
        key: ValueKey(showAlbumArt ? 'media-audio-with-art' : 'media-audio'),
        child: AudioNowPlayingView(
          showAlbumArt: showAlbumArt,
          source: player.currentSource,
          mediaDisplayTitle: mediaDisplayTitle,
          mediaDisplayArtist: mediaDisplayArtist,
          videoController: videoController,
        ),
      );
    }

    return Container(
      key: const ValueKey('media-video'),
      color: Colors.black,
      child: VideoSurface(controller: videoController),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _contentSwitchDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            ...(currentChild == null
                ? const <Widget>[]
                : <Widget>[currentChild]),
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        final scale = Tween<double>(begin: 0.985, end: 1.0).animate(fade);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: hasMedia ? onTap : null,
        onDoubleTap: hasMedia ? onDoubleTap : null,
        child: MouseRegion(
          cursor: !isFullscreen || fullscreenChromeVisible
              ? MouseCursor.defer
              : SystemMouseCursors.none,
          onHover: (_) => onHover(),
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                onScrollVolume(event.scrollDelta.dy, event.timeStamp);
              }
            },
            child: Stack(
              children: [
                Positioned.fill(child: _buildContent()),
                if (hasMedia && settings.osdEnabled)
                  Positioned.fill(
                    child: OsdOverlay(
                      title: player.osdTitle(),
                      position: player.position,
                      duration: player.duration,
                      visible: player.osdVisible,
                      transientMessage: PlayerController.stripOsdTimestamp(
                        player.osdTransientMessage,
                      ),
                    ),
                  ),
                if (compactMode)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: CompactExitButton(onPressed: onExitCompactMode),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
