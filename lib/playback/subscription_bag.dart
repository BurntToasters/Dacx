import 'dart:async';

/// Holds stream subscriptions and cancels them together on dispose.
class SubscriptionBag {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  void add(StreamSubscription<dynamic> subscription) {
    _subscriptions.add(subscription);
  }

  void cancelAll() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
