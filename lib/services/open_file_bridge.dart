import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../playback/player_path_utils.dart';
import '../playback/subscription_bag.dart';

typedef OpenFileRequestCallback =
    Future<void> Function(OpenFileRequest request, {required bool forcePlay});

typedef OpenFileBridgeLogger =
    void Function(
      String event, {
      String? message,
      Map<String, Object?> details,
      bool warn,
      bool error,
    });

/// Bridges native "Open With" / second-instance file delivery into Dart.
///
/// Channel contract (must stay in sync with platform runners):
///   - Method `getPendingFiles` → `List<dynamic>` of path strings or maps
///   - Event stream payloads → same shape as pending entries
class OpenFileBridge {
  static const methodChannelName = 'run.rosie.dacx/open_file/methods';
  static const eventChannelName = 'run.rosie.dacx/open_file/events';
  static const defaultRetryDelay = Duration(milliseconds: 250);

  OpenFileBridge({
    required this.onOpenRequest,
    this.isActive = _alwaysActive,
    this.onLog,
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    this.retryDelay = defaultRetryDelay,
  }) : _methodChannel = methodChannel ?? const MethodChannel(methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(eventChannelName);

  final OpenFileRequestCallback onOpenRequest;
  final bool Function() isActive;
  final OpenFileBridgeLogger? onLog;
  final Duration retryDelay;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  StreamSubscription<dynamic>? _eventSubscription;

  static bool _alwaysActive() => true;

  bool get isSupportedPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  void _log(
    String event, {
    String? message,
    Map<String, Object?> details = const {},
    bool warn = false,
    bool error = false,
  }) {
    onLog?.call(
      event,
      message: message,
      details: details,
      warn: warn,
      error: error,
    );
  }

  /// Starts the bridge: drains pending files, then listens for live events.
  Future<void> bootstrap({SubscriptionBag? subscriptions}) async {
    if (!isSupportedPlatform) return;
    _log('open_file_bridge_init');
    final bridgeReady = await _drainPendingFiles();
    _attachEventListener(subscriptions: subscriptions);
    if (!bridgeReady) {
      unawaited(_schedulePendingRetry());
    }
  }

  void dispose() {
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
  }

  /// Handles one platform event payload. Exposed for unit tests.
  @visibleForTesting
  Future<void> handlePlatformPayload(
    Object? payload, {
    bool forcePlay = true,
  }) async {
    if (!isActive()) return;
    final request = PlayerPathUtils.coerceOpenRequest(payload);
    if (request == null) return;
    _log('open_file_event_received', details: {'path': request.path});
    await onOpenRequest(request, forcePlay: forcePlay);
  }

  Future<bool> _drainPendingFiles({bool retry = false}) async {
    if (!isActive()) return true;
    try {
      final pending = await _methodChannel.invokeListMethod<dynamic>(
        'getPendingFiles',
      );
      if (!isActive()) return true;
      if (pending == null || pending.isEmpty) return true;
      _log(
        retry ? 'open_file_pending_found_retry' : 'open_file_pending_found',
        details: {'count': pending.length},
      );
      for (final entry in pending) {
        if (!isActive()) return true;
        await handlePlatformPayload(entry, forcePlay: true);
      }
      return true;
    } on MissingPluginException {
      _log('open_file_bridge_missing_plugin', warn: true);
      return false;
    } on PlatformException {
      _log('open_file_bridge_platform_exception', warn: true);
      return false;
    } catch (e) {
      _log(
        retry ? 'open_file_pending_retry_failed' : 'open_file_bridge_failed',
        message: e.toString(),
        warn: retry,
        error: !retry,
      );
      return retry;
    }
  }

  void _attachEventListener({SubscriptionBag? subscriptions}) {
    final subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (!isActive()) return;
        unawaited(handlePlatformPayload(event, forcePlay: true));
      },
      onError: (Object error) {
        _log('open_file_event_error', message: error.toString(), warn: true);
      },
    );
    _eventSubscription = subscription;
    subscriptions?.add(subscription);
  }

  Future<void> _schedulePendingRetry() async {
    await Future<void>.delayed(retryDelay);
    if (!isActive()) return;
    await _drainPendingFiles(retry: true);
  }
}
