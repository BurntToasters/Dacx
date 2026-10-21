import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/app_localizations.dart';
import '../models/chapter_info.dart';
import '../playback/player_controller.dart';
import '../playback/track_label.dart';

/// Shows the audio track picker. Returns the chosen track, or null when
/// dismissed. Applying the selection is the caller's job.
Future<AudioTrack?> pickAudioTrack(
  BuildContext context, {
  required List<AudioTrack> tracks,
  String? currentId,
}) {
  return showDialog<AudioTrack>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(AppLocalizations.of(ctx).dialogAudioTrackTitle),
      children: tracks
          .map(
            (t) => _TrackOption(
              selected: t.id == currentId,
              label: _trackLabel(ctx, t.title, t.language, t.id),
              ellipsize: true,
              onPressed: () => Navigator.pop(ctx, t),
            ),
          )
          .toList(),
    ),
  );
}

/// Shows the subtitle track picker. [tracks] may include `SubtitleTrack.no()`,
/// which is labeled as "off".
Future<SubtitleTrack?> pickSubtitleTrack(
  BuildContext context, {
  required List<SubtitleTrack> tracks,
  String? currentId,
}) {
  return showDialog<SubtitleTrack>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(AppLocalizations.of(ctx).dialogSubtitleTrackTitle),
      children: tracks
          .map(
            (t) => _TrackOption(
              selected: t.id == currentId,
              label: t.id == 'no'
                  ? AppLocalizations.of(ctx).subtitleTrackOff
                  : _trackLabel(ctx, t.title, t.language, t.id),
              ellipsize: false,
              onPressed: () => Navigator.pop(ctx, t),
            ),
          )
          .toList(),
    ),
  );
}

/// Shows the chapter picker. Returns the chosen chapter index.
Future<int?> pickChapter(BuildContext context, List<ChapterInfo> chapters) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(AppLocalizations.of(ctx).dialogChaptersTitle),
      children: chapters
          .map(
            (c) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c.index),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      PlayerController.formatDuration(c.time),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(c.title, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

String _trackLabel(
  BuildContext context,
  String? title,
  String? language,
  String fallbackId,
) => formatTrackLabel(
  title: title,
  language: language,
  fallbackId: fallbackId,
  fallbackLabel: AppLocalizations.of(context).trackFallbackLabel(fallbackId),
);

class _TrackOption extends StatelessWidget {
  final bool selected;
  final String label;
  final bool ellipsize;
  final VoidCallback onPressed;

  const _TrackOption({
    required this.selected,
    required this.label,
    required this.ellipsize,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: onPressed,
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: ellipsize ? TextOverflow.ellipsis : null,
            ),
          ),
        ],
      ),
    );
  }
}
