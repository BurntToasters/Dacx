/// Pure pre-open guards extracted from [PlayerScreen._loadSourceInternal].
abstract final class SourceLoadPreOpenPolicy {
  static bool shouldAbortBeforeOpen({
    required bool mounted,
    required bool isDisposed,
  }) {
    return !mounted || isDisposed;
  }
}
