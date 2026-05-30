import 'dart:async';

/// Serializes async work (e.g. file opens) so only one runs at a time.
class LoadQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(
    Future<void> Function() task, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final run = _tail.then((_) async {
      try {
        await task();
      } catch (e, st) {
        onError?.call(e, st);
      }
    });
    _tail = run;
    return run;
  }
}
