/// Whether in-flight load work should continue after async gaps.
abstract final class LoadOutcomePolicy {
  static bool shouldProceedAfterOpen({
    required bool isLoadCurrent,
    required bool isDisposed,
  }) {
    return isLoadCurrent && !isDisposed;
  }

  static bool shouldRefreshUi({
    required bool mounted,
    required bool isDisposed,
    required bool isLoadCurrent,
  }) {
    return mounted && !isDisposed && isLoadCurrent;
  }
}
