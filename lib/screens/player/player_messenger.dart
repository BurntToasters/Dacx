import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';
import '../../playback/osd_policy.dart';
import '../../playback/player_controller.dart';
import '../../playback/source_load_validation_policy.dart';

const _osdHideDuration = Duration(seconds: 3);

class PlayerMessenger {
  PlayerMessenger({
    required this.player,
    required this.osdEnabled,
    required this.isMounted,
    required this.update,
    this.osdMessageProbe,
  });

  final PlayerController player;
  final bool Function() osdEnabled;
  final bool Function() isMounted;
  final void Function(VoidCallback fn) update;
  final ValueNotifier<String?>? osdMessageProbe;
  Timer? _osdHideTimer;

  void pulseOsd() {
    if (!OsdPolicy.shouldShow(osdEnabled: osdEnabled(), mounted: isMounted())) {
      return;
    }
    if (!player.osdVisible) update(() => player.osdVisible = true);
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(_osdHideDuration, () {
      if (isMounted()) update(() => player.osdVisible = false);
    });
  }

  void showOsdMessage(String msg) {
    osdMessageProbe?.value = msg;
    if (!OsdPolicy.shouldShow(osdEnabled: osdEnabled(), mounted: isMounted())) {
      return;
    }
    update(
      () => player.osdTransientMessage = OsdPolicy.formatTransientMessage(msg),
    );
    pulseOsd();
  }

  void dispose() {
    _osdHideTimer?.cancel();
  }

  static String loadUserMessageText(
    AppLocalizations l10n,
    SourceLoadUserMessageKind kind,
  ) {
    return switch (kind) {
      SourceLoadUserMessageKind.invalidFilePath => l10n.snackInvalidFilePath,
      SourceLoadUserMessageKind.invalidStreamUrl => l10n.snackInvalidStreamUrl,
      SourceLoadUserMessageKind.fileNotFound => l10n.snackFileNotFound,
      SourceLoadUserMessageKind.permissionDenied =>
        l10n.snackFileLoadPermissionDenied,
      SourceLoadUserMessageKind.openFailed => l10n.snackFileLoadFailed,
    };
  }
}
