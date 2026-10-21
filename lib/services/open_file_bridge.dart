import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../playback/player_path_utils.dart';
import '../playback/subscription_bag.dart';

typedef OpenFileRequestCallback = Future<void> Function(
  OpenFileRequest request, {
  required bool forcePlay,
});

typedef OpenFileBatchCallback = Future<void> Function(
  List<OpenFileRequest> requests,
);

typedef OpenFileBridgeLogger = void Function(
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
  static const defaultBatchWindow = Duration(milliseconds: 400);

  OpenFileBridge({
    required this.onOpenRequest,
    this.onOpenBatch,
    this.isActive = _alwaysActive,
    this.onLog,
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    this.retryDelay = defaultRetryDelay,
    this.batchWindow = defaultBatchWindow,
  }) : _methodChannel = methodChannel ?? const MethodChannel(methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(eventChannelName);

  final OpenFileRequestCallback onOpenRequest;
  final OpenFileBatchCallback? onOpenBatch;
  final bool Function() isActive;
  final OpenFileBridgeLogger? onLog;
  final Duration retryDelay;
  final Duration batchWindow;

  final List<OpenFileRequest> _batch = [];
  Timer? _batchTimer;

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
  Future<void> bootstrap({
    SubscriptionBag? subscriptions,
    List<OpenFileRequest> initial = const [],
  }) async {
    if (!isSupportedPlatform) {
      await Future<void>.value();
      await _deliverSafely(initial, retry: false);
      return;
    }
    _log('open_file_bridge_init');
    final bridgeReady = await _drainPendingFiles(initial: initial);
    _attachEventListener(subscriptions: subscriptions);
    if (!bridgeReady) {
      unawaited(_schedulePendingRetry());
    }
  }

  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _batch.clear();
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
  }

  Future<void> _deliver(List<OpenFileRequest> requests) async {
    if (requests.isEmpty || !isActive()) return;
    final batch = onOpenBatch;
    if (requests.length > 1 && batch != null) {
      _log('open_file_batch_received', details: {'count': requests.length});
      await batch(requests);
      return;
    }
    for (final request in requests) {
      if (!isActive()) return;
      _log('open_file_event_received', details: {'path': request.path});
      await onOpenRequest(request, forcePlay: true);
    }
  }

  void _queueLiveRequest(OpenFileRequest request) {
    _batch.add(request);
    _batchTimer?.cancel();
    _batchTimer = Timer(batchWindow, () {
      _batchTimer = null;
      final requests = List<OpenFileRequest>.of(_batch);
      _batch.clear();
      unawaited(_deliverSafely(requests, retry: false));
    });
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

  Future<bool> _drainPendingFiles({
    bool retry = false,
    List<OpenFileRequest> initial = const [],
  }) async {
    if (!isActive()) return true;
    List<dynamic>? pending;
    var ready = true;
    try {
      pending = await _methodChannel.invokeListMethod<dynamic>(
        'getPendingFiles',
      );
    } on MissingPluginException {
      _log('open_file_bridge_missing_plugin', warn: true);
      ready = false;
    } on PlatformException {
      _log('open_file_bridge_platform_exception', warn: true);
      ready = false;
    } catch (e) {
      _log(
        retry ? 'open_file_pending_retry_failed' : 'open_file_bridge_failed',
        message: e.toString(),
        warn: retry,
        error: !retry,
      );
      ready = retry;
    }
    if (!isActive()) return true;
    final entries = pending ?? const <dynamic>[];
    if (entries.isNotEmpty) {
      _log(
        retry ? 'open_file_pending_found_retry' : 'open_file_pending_found',
        details: {'count': entries.length},
      );
    }
    if (onOpenBatch == null) {
      await _deliverSafely(initial, retry: retry);
      for (final entry in entries) {
        if (!isActive()) return ready;
        try {
          await handlePlatformPayload(entry, forcePlay: true);
        } catch (e) {
          _logDeliveryFailure(e, retry: retry);
        }
      }
      return ready;
    }
    await _deliverSafely([
      ...initial,
      for (final entry in entries) ?PlayerPathUtils.coerceOpenRequest(entry),
    ], retry: retry);
    return ready;
  }

  Future<void> _deliverSafely(
    List<OpenFileRequest> requests, {
    required bool retry,
  }) async {
    try {
      await _deliver(requests);
    } catch (e) {
      _logDeliveryFailure(e, retry: retry);
    }
  }

  void _logDeliveryFailure(Object error, {required bool retry}) {
    _log(
      retry ? 'open_file_pending_retry_failed' : 'open_file_bridge_failed',
      message: error.toString(),
      warn: retry,
      error: !retry,
    );
  }

  void _attachEventListener({SubscriptionBag? subscriptions}) {
    final subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (!isActive()) return;
        if (onOpenBatch == null) {
          unawaited(handlePlatformPayload(event, forcePlay: true));
          return;
        }
        final request = PlayerPathUtils.coerceOpenRequest(event);
        if (request != null) _queueLiveRequest(request);
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
