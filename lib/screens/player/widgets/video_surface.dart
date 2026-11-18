import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoSurface extends StatelessWidget {
  const VideoSurface({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.fill,
  });

  final VideoController? controller;
  final BoxFit fit;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return const ColoredBox(color: Colors.black);
    }
    return RepaintBoundary(
      child: Video(
        controller: controller,
        controls: NoVideoControls,
        fit: fit,
        fill: fill ?? Colors.transparent,
      ),
    );
  }
}
